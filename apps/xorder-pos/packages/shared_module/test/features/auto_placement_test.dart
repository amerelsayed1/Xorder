import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// tablet-cloud-onboarding, Stage 3 (Q2): after the owner signs in, a cloud
/// till places itself when there is nothing to choose, and asks whenever there
/// is. AC-1, AC-2.
class _Platform implements ProvisioningRepository {
  _Platform({
    this.branches = const [PosBranch(id: 1, name: 'Main', code: 'MAIN')],
    this.terminals = const [],
    this.registerRefusal,
  });

  final List<PosBranch> branches;
  final List<PosTerminalSummary> terminals;
  final ClaimResult? registerRefusal;

  final registered = <String>[];
  final adopted = <int>[];

  @override
  Future<TenantConnection> connect({
    required String tenantSlug,
    required String username,
    required String password,
  }) async => TenantConnection(
    tenantName: 'Demo',
    branches: branches,
    terminals: terminals,
  );

  @override
  Future<ClaimResult> adoptTerminal({
    required String tenantSlug,
    required String username,
    required String password,
    required int terminalId,
  }) async {
    adopted.add(terminalId);
    return const ClaimResult(code: 'UNUSED');
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
    registered.add(terminalName);
    return registerRefusal ??
        const ClaimResult(
          claim: TerminalClaim(
            terminalId: 'uuid-new',
            terminalName: 'Tablet',
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
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer harness(_Platform platform) {
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(appMode: DeploymentMode.cloud),
        provisioningRepositoryProvider.overrideWithValue(platform),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<SetupDraft> signIn(ProviderContainer container) async {
    final controller = container.read(setupProvider.notifier);
    controller.setTenantSlug('demo');
    controller.setOperatorUsername('owner');
    controller.setOperatorPassword('secret');
    await controller.connectTenant();
    return container.read(setupProvider);
  }

  const waiting = PosTerminalSummary(
    id: 7,
    name: 'Counter 1',
    branchId: 1,
    state: 'provisioned',
  );
  const inService = PosTerminalSummary(
    id: 9,
    name: 'Busy',
    branchId: 1,
    state: 'active',
  );

  test('one branch and no waiting till: it registers itself and the branch '
      'and terminal screens are not walked', () async {
    final platform = _Platform();
    final draft = await signIn(harness(platform));

    expect(platform.registered, hasLength(1));
    expect(draft.claimed, isTrue);
    expect(draft.autoPlaced, isTrue);
    expect(draft.visibleSteps, isNot(contains(SetupStep.branch)));
    expect(draft.visibleSteps, isNot(contains(SetupStep.terminal)));
    expect(draft.visibleSteps.first, SetupStep.account);
    expect(draft.visibleSteps, contains(SetupStep.connecting));
  });

  test('a till already in service beside it does not stop it registering '
      '(it is not offered for adoption)', () async {
    final platform = _Platform(terminals: const [inService]);
    final draft = await signIn(harness(platform));

    expect(platform.registered, hasLength(1));
    expect(platform.adopted, isEmpty);
    expect(draft.autoPlaced, isTrue);
  });

  test('a till waiting to be adopted is asked about, never taken', () async {
    final platform = _Platform(terminals: const [waiting]);
    final draft = await signIn(harness(platform));

    expect(platform.registered, isEmpty);
    expect(platform.adopted, isEmpty);
    expect(draft.claimed, isFalse);
    expect(draft.autoPlaced, isFalse);
    expect(draft.visibleSteps, contains(SetupStep.branch));
    expect(draft.visibleSteps, contains(SetupStep.terminal));
  });

  test('several branches are asked about', () async {
    final platform = _Platform(
      branches: const [
        PosBranch(id: 1, name: 'Maadi', code: 'MAA'),
        PosBranch(id: 2, name: 'Zamalek', code: 'ZAM'),
      ],
    );
    final draft = await signIn(harness(platform));

    expect(platform.registered, isEmpty);
    expect(draft.autoPlaced, isFalse);
    expect(draft.visibleSteps, contains(SetupStep.branch));
  });

  test(
    'a refused registration falls back to the screens, with the reason',
    () async {
      final platform = _Platform(
        registerRefusal: const ClaimResult(
          code: 'TERMINAL_LIMIT',
          message: 'This plan allows 1 terminal.',
        ),
      );
      final draft = await signIn(harness(platform));

      expect(platform.registered, hasLength(1));
      expect(draft.claimed, isFalse);
      expect(draft.autoPlaced, isFalse);
      expect(draft.error, isNotNull);
      expect(draft.visibleSteps, contains(SetupStep.terminal));
    },
  );

  test(
    'Next from the account step goes to connecting, and Back returns to it',
    () async {
      final container = harness(_Platform());
      await signIn(container);
      final controller = container.read(setupProvider.notifier);

      controller.next();
      expect(container.read(setupProvider).step, SetupStep.connecting);

      controller.back();
      expect(container.read(setupProvider).step, SetupStep.account);
    },
  );

  test('an offline app never places itself', () async {
    final platform = _Platform();
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
        provisioningRepositoryProvider.overrideWithValue(platform),
      ],
    );
    addTearDown(container.dispose);

    final draft = await signIn(container);

    expect(platform.registered, isEmpty);
    expect(draft.autoPlaced, isFalse);
  });
}
