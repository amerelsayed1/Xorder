import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart' show Pool;
import 'package:shared_module/app/branch_sales_providers.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/payment/payment_screen.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';

import '../support/offline_harness.dart';

/// AC-5 (pos-split-apps): the offline app never sends money.
///
/// "XOrder POS - Offline" is sold on the promise that a sale stays in the
/// building. Before the split that was a mode check in a dozen places; since
/// stage 3 the sync loop, the drain and the platform's branch view are code
/// only the CLOUD app contains, and since stage 4 nothing in the shared till
/// chooses between the apps either. This holds the promise as one flow: the
/// offline app's own wiring, set up from the wizard and selling a ticket to
/// the end, with a platform client sitting right there in
/// `posCloudApiProvider` that records every call and refuses the ones that
/// carry money.
///
/// **Why bind a platform client at all**, when the offline wiring leaves that
/// provider null on its own: null proves only that nothing was given an
/// address. A tripwire proves that nothing in the offline app would use one
/// if it were — which is the property a future change (a shared helper that
/// "just" nudges the platform after a sale) would actually break. And the
/// clock is run on past the cloud app's first scheduled pass (five seconds)
/// and its slowest retry cadence, so a sync loop bound by mistake gets the
/// chance to fire before the test looks.
///
/// What this does NOT prove: the PostgreSQL write path. The harness's orders
/// repository is the fake; that the PostgreSQL repositories queue nothing for
/// the platform on an offline till is held by their own suites
/// (`postgres_orders_repository`, `postgres_sync_queue_repository`, the
/// `syncsSalesToPlatform` rules kept in stage 4).
void main() {
  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'amer',
    role: FakeSessionRepository.owner,
  );

  ProviderContainer offlineApp(_Tripwire platform) {
    final container = ProviderContainer(
      overrides: [
        ...offlineTestOverrides(appMode: DeploymentMode.offline),
        posCloudApiProvider.overrideWithValue(platform),
        // The branch server at 192.168.1.20 is not there in a widget test.
        // Refused at once rather than dialled: a real dial on the fake clock
        // never completes, and every caller on this path already treats a
        // refusal as "the database is down" (the parked-ticket cleanup after a
        // settlement, above all).
        posDatabaseProvider.overrideWithValue(_NoBranchServer()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the tripwire has teeth: a sale offered to it fails the test', () async {
    // Without this the flow below could pass against a tripwire that never
    // fires — every refusal in it is a call that did not happen.
    final platform = _Tripwire();
    await expectLater(
      platform.submitOrder(const {'client_transaction_id': 'x'}),
      throwsA(isA<TestFailure>()),
    );
    expect(platform.salesCalls, ['/api/pos/orders']);
  });

  test('the offline wiring binds nothing that talks to the platform', () {
    final container = offlineApp(_Tripwire());

    expect(container.read(appModeProvider), DeploymentMode.offline);
    expect(container.read(deploymentProvider).mode, DeploymentMode.offline);
    // The three seams the cloud app fills (stage 3). The offline app leaves
    // each on its shared default, which is "no platform".
    expect(container.read(cloudSyncProvider), isNull);
    expect(container.read(bootstrapSeedingProvider), isNull);
    expect(container.read(platformBranchSalesProvider), isNull);
  });

  testWidgets('set up, sell and settle: not one call to the platform', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final platform = _Tripwire();
    final container = offlineApp(platform);

    // ── Set up, through the wizard's own controller ─────────────────────────
    // The offline path as an installer walks it: a licence for this app, the
    // database on the branch server, the first owner, the branch and the till,
    // registered and finished. `bootstrapDatabase` needs a real PostgreSQL;
    // the flag is what it leaves behind.
    final setup = container.read(setupProvider.notifier);
    setup.setLicenceKey('DEV-KEY');
    await tester.runAsync(setup.activateLicence);
    expect(container.read(setupProvider).entitlement?.canSell, isTrue);
    expect(
      container.read(setupProvider).deployment.mode,
      DeploymentMode.offline,
    );
    setup
      ..setDatabaseHost('192.168.1.20')
      ..setDatabasePassword('s3cret')
      ..setOwnerName('Amer')
      ..setOwnerUsername('amer')
      ..setOwnerPin('4321')
      ..setBranch(13, 'Maadi')
      ..setTerminalName('Counter 1');
    setup.state = container.read(setupProvider).copyWith(bootstrapped: true);
    await tester.runAsync(setup.registerTerminal);
    expect(container.read(setupProvider).claimed, isTrue);
    setup.state = container
        .read(setupProvider)
        .copyWith(step: SetupStep.summary, catalogueItems: 19);
    final refused = await tester.runAsync(setup.complete);
    expect(refused, isNull, reason: refused);
    expect(container.read(setupCompleteProvider), isTrue);
    expect(container.read(deploymentProvider).mode, DeploymentMode.offline);

    // ── Sell ────────────────────────────────────────────────────────────────
    container.read(signedInStaffProvider.notifier).signIn(owner);
    final catalog = (await tester.runAsync(
      () => container.read(catalogProvider.future),
    ))!;
    final drink = catalog.products.firstWhere((p) => p.nameEn == 'Soft Drink');
    final ticket = container.read(ticketProvider.notifier);
    ticket.setOrderType(OrderType.takeaway);
    expect(ticket.addProduct(drink), isTrue);

    SettledSale? settled;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    settled = await PaymentScreen.show(context),
                child: const Text('charge'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('charge'));
    await tester.pumpAndSettle();

    // ── Settle ──────────────────────────────────────────────────────────────
    // Enter with nothing typed takes the whole remaining due, in cash — the
    // keyboard path a cashier at speed uses.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(settled, isNotNull, reason: 'the sale did not settle');
    final orders = container.read(ordersRepositoryProvider);
    expect((orders as FakeOrdersRepository).submitted, hasLength(1));
    expect(orders.submitted.single.totals.isSettled, isTrue);

    // ── And then wait, as a till left on overnight would ────────────────────
    // Past the cloud app's first pass (5 s), past the nudge floor, past the
    // thirty-minute retry cadence. Anything that was going to phone home has
    // had its turn.
    container.read(cloudSyncProvider)?.nudge();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(minutes: 31));
    await tester.pumpAndSettle();

    expect(platform.salesCalls, isEmpty);
    expect(platform.calls, isEmpty);

    // The till's own pollers (the parked-ticket refresh) keep a timer; let
    // them go with the app rather than leave the binding holding one.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(minutes: 1));
  });
}

/// A platform client that writes down every call, and fails the test on any
/// that would send a sale or anything the sales sync carries.
///
/// Recording as well as throwing, because the payment screen and the sync
/// loop both catch `Object` on the way out — a [TestFailure] thrown inside
/// them would be swallowed as "the platform did not answer". The list is what
/// the test reads at the end.
///
/// Every method is overridden, so nothing reaches the real HTTP client the
/// base constructor builds; the licence check — which the offline app IS
/// allowed to make, to renew — answers as if offline and is not counted.
class _Tripwire extends PosCloudApi {
  _Tripwire()
    : super(baseUrl: 'https://tripwire.invalid', deviceToken: () => 'none');

  /// Every platform call, by path.
  final calls = <String>[];

  /// The ones that carry money or the sales sync.
  final salesCalls = <String>[];

  Future<CloudReply> _money(String path) async {
    calls.add(path);
    salesCalls.add(path);
    throw TestFailure('the offline app called $path');
  }

  Future<CloudReply> _other(String path) async {
    calls.add(path);
    return const CloudReply.offline();
  }

  @override
  Future<CloudReply> submitOrder(Map<String, Object?> request) =>
      _money('/api/pos/orders');

  @override
  Future<CloudReply> createCustomer(Map<String, Object?> request) =>
      _money('/api/pos/customers');

  @override
  Future<CloudReply> openShift(Map<String, Object?> request) =>
      _money('/api/pos/shifts');

  @override
  Future<CloudReply> closeShift(
    String shiftClientId,
    Map<String, Object?> request,
  ) => _money('/api/pos/shifts/$shiftClientId/close');

  @override
  Future<CloudReply> recordCashMovement(Map<String, Object?> request) =>
      _money('/api/pos/cash-movements');

  @override
  Future<CloudReply> submitRefund(Map<String, Object?> request) =>
      _money('/api/pos/refunds');

  // The sync loop's own two calls. Neither carries money, but either one
  // happening means a sync loop is running in the offline app, which is the
  // failure this file exists to catch.
  @override
  Future<CloudReply> heartbeat(Map<String, Object?> payload) =>
      _money('/api/pos/terminals/heartbeat');

  @override
  Future<CloudReply> bootstrap() => _money('/api/pos/bootstrap');

  @override
  Future<CloudReply> claimTerminal({
    required String tenantSlug,
    required String pairingCode,
    required String platform,
    required String appVersion,
    required String fingerprint,
  }) => _other('/api/pos/terminals/claim');

  @override
  Future<CloudReply> login({
    required String tenantSlug,
    required String username,
    required String password,
  }) => _other('/api/auth/login');

  @override
  Future<CloudReply> listBranches({required String jwt}) =>
      _other('/api/dashboard/branches');

  @override
  Future<CloudReply> issuePairingCode({
    required String jwt,
    required int terminalId,
  }) => _other('/api/dashboard/pos/terminals/$terminalId/pairing-code');

  @override
  Future<CloudReply> registerTerminal({
    required String jwt,
    required String clientTransactionId,
    required String terminalName,
    required int branchId,
    required String platform,
    required String appVersion,
    required String fingerprint,
  }) => _other('/api/pos/terminals/register');

  @override
  Future<CloudReply> listTerminals({required String jwt}) =>
      _other('/api/dashboard/pos/terminals');

  @override
  Future<CloudReply> checkLicence(Map<String, Object?> payload) async =>
      const CloudReply.offline();
}

/// A branch database that is never reachable. See where it is bound.
class _NoBranchServer extends PosDatabase {
  _NoBranchServer() : super(credentials: MutablePosDbCredentials());

  @override
  Future<Pool<void>> pool(DeploymentConfig config) async =>
      throw PosDbException(PosDbFailure.tcp, 'no branch server here');

  @override
  Future<PosDbFailure?> probe(DeploymentConfig config) async =>
      PosDbFailure.tcp;
}
