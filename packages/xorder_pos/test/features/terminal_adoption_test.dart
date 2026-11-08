import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The wizard must ADOPT a terminal the dashboard already created, not make
/// another one beside it.
///
/// Since tenant creation started leaving terminals provisioned and waiting
/// (owner decision, 2026-09-05), the credentials path's old behaviour —
/// always `registerManually`, always a brand-new row — is how a two-seat
/// business ends up with four terminals and a seat limit nobody can explain.
class _Recorder implements ProvisioningRepository {
  _Recorder({this.terminals = const []});

  final List<PosTerminalSummary> terminals;

  int? adopted;
  String? registeredName;

  @override
  Future<TenantConnection> connect({
    required String tenantSlug,
    required String username,
    required String password,
  }) async => TenantConnection(
    tenantName: 'Demo',
    branches: const [PosBranch(id: 1, name: 'Main', code: 'MAIN')],
    terminals: terminals,
  );

  @override
  Future<ClaimResult> adoptTerminal({
    required String tenantSlug,
    required String username,
    required String password,
    required int terminalId,
  }) async {
    adopted = terminalId;
    return const ClaimResult(
      claim: TerminalClaim(
        terminalId: 'uuid-adopted',
        terminalName: 'Counter 1',
        branchId: 1,
        branchName: 'Main',
        syncPolicy: SyncPolicy.automatic,
      ),
    );
  }

  @override
  Future<ClaimResult> registerManually({
    required String tenantSlug,
    required String username,
    required String password,
    required String terminalName,
    required int branchId,
    required String? installId,
  }) async {
    registeredName = terminalName;
    return const ClaimResult(
      claim: TerminalClaim(
        terminalId: 'uuid-new',
        terminalName: 'New Till',
        branchId: 1,
        branchName: 'Main',
        syncPolicy: SyncPolicy.automatic,
      ),
    );
  }

  @override
  Future<ClaimResult> claimByCode({
    required String tenantSlug,
    required String code,
  }) async => const ClaimResult(code: 'UNUSED');
}

void main() {
  // SetupController.build restores the installed licence, which reaches
  // path_provider — the binding has to exist before any container is made.
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer harness(_Recorder repo) {
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        // After the shared fakes, so this one wins.
        provisioningRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> signIn(ProviderContainer container) async {
    final controller = container.read(setupProvider.notifier);
    controller.setTenantSlug('demo');
    controller.setOperatorUsername('manager');
    controller.setOperatorPassword('secret');
    await controller.connectTenant();
  }

  test('signing in pulls the terminals the dashboard already created', () async {
    final repo = _Recorder(
      terminals: const [
        PosTerminalSummary(
          id: 7,
          name: 'Counter 1',
          branchId: 1,
          state: 'provisioned',
        ),
      ],
    );
    final container = harness(repo);
    await signIn(container);

    final draft = container.read(setupProvider);
    expect(draft.pulledTerminals, hasLength(1));
    // Pre-selected: adopting is the default, creating another is the choice.
    expect(draft.adoptTerminalId, 7);
    expect(draft.terminalName, 'Counter 1');
  });

  test('a till in service is never offered for adoption', () async {
    // Adopting an `active` terminal would take the seat out from under a
    // machine that is trading on it.
    final repo = _Recorder(
      terminals: const [
        PosTerminalSummary(
          id: 9,
          name: 'Busy',
          branchId: 1,
          state: 'active',
        ),
      ],
    );
    final container = harness(repo);
    await signIn(container);

    expect(container.read(setupProvider).adoptTerminalId, isNull);
  });

  test('adopting claims the existing row, creating nothing', () async {
    final repo = _Recorder(
      terminals: const [
        PosTerminalSummary(
          id: 7,
          name: 'Counter 1',
          branchId: 1,
          state: 'provisioned',
        ),
      ],
    );
    final container = harness(repo);
    await signIn(container);
    await container.read(setupProvider.notifier).registerTerminal();

    expect(repo.adopted, 7);
    expect(repo.registeredName, isNull, reason: 'no new terminal may be made');

    final draft = container.read(setupProvider);
    expect(draft.claimed, isTrue);
    expect(draft.terminalId, 'uuid-adopted');
  });

  test('a tenant with no terminals still registers a new one', () async {
    // The first till at a brand-new tenant: nothing to adopt, so the old path
    // is exactly right and must not have been broken by any of this.
    final repo = _Recorder();
    final container = harness(repo);
    await signIn(container);

    final controller = container.read(setupProvider.notifier);
    controller.setTerminalName('Counter 1');
    controller.setBranch(1, 'Main');
    await controller.registerTerminal();

    expect(repo.registeredName, 'Counter 1');
    expect(repo.adopted, isNull);
    expect(container.read(setupProvider).terminalId, 'uuid-new');
  });

  test('choosing "a new till" overrides the pre-selection', () async {
    final repo = _Recorder(
      terminals: const [
        PosTerminalSummary(
          id: 7,
          name: 'Counter 1',
          branchId: 1,
          state: 'provisioned',
        ),
      ],
    );
    final container = harness(repo);
    await signIn(container);

    final controller = container.read(setupProvider.notifier);
    controller.setAdoptedTerminal(null);
    // The adopted name is cleared with it — it belonged to the other till.
    expect(container.read(setupProvider).terminalName, isEmpty);

    controller.setTerminalName('Counter 3');
    controller.setBranch(1, 'Main');
    await controller.registerTerminal();

    expect(repo.registeredName, 'Counter 3');
    expect(repo.adopted, isNull);
  });
}
