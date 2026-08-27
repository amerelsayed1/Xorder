import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';
import 'package:xorder_pos/features/setup/presentation/setup_wizard.dart';

import '../support/fakes.dart';

const _desktop = Size(1440, 900);

Future<ProviderContainer> _pump(WidgetTester tester, {VoidCallback? onFinished}) async {
  tester.view
    ..physicalSize = _desktop
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: fakeRepositoryOverrides());
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildPosTheme(),
        home: SetupWizard(onFinished: onFinished ?? () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('step gating', () {
    test('language always advances; connection needs an endpoint', () {
      const draft = SetupDraft();
      expect(draft.canAdvance, isTrue);

      const cloudNoUrl = SetupDraft(step: SetupStep.deployment);
      expect(cloudNoUrl.canAdvance, isFalse);

      const withUrl = SetupDraft(
        step: SetupStep.deployment,
        deployment: DeploymentConfig(mode: DeploymentMode.cloud, baseUrl: 'https://xorder.io'),
      );
      expect(withUrl.canAdvance, isTrue);
    });

    test('standalone needs no endpoint at all', () {
      const draft = SetupDraft(
        step: SetupStep.deployment,
        deployment: DeploymentConfig(mode: DeploymentMode.standalone),
      );
      expect(draft.canAdvance, isTrue);
    });

    test('hardware never blocks — a till with no printer still finishes setup', () {
      const draft = SetupDraft(step: SetupStep.hardware);
      expect(draft.printerName, isNull);
      expect(draft.canAdvance, isTrue);
    });

    test('a licence in its grace window still lets setup finish', () {
      const inGrace = SetupDraft(
        step: SetupStep.licence,
        entitlement: LicenseEntitlement(
          state: LicenseState.inGrace,
          canOpenShift: true,
          canSell: true,
          canChangeConfiguration: false,
        ),
      );
      expect(inGrace.canAdvance, isTrue);
    });

    test('a missing licence blocks the licence step', () {
      const missing = SetupDraft(
        step: SetupStep.licence,
        entitlement: LicenseEntitlement(
          state: LicenseState.missing,
          canOpenShift: false,
          canSell: false,
          canChangeConfiguration: false,
        ),
      );
      expect(missing.canAdvance, isFalse);
    });

    test('catalogue must actually have synced', () {
      const unsynced = SetupDraft(step: SetupStep.catalogue);
      expect(unsynced.canAdvance, isFalse);

      const synced = SetupDraft(step: SetupStep.catalogue, catalogueItems: 19);
      expect(synced.canAdvance, isTrue);
    });
  });

  group('controller', () {
    test('changing deployment mode discards a licence checked against the old one', () {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setMode(DeploymentMode.cloud);
      controller.setBaseUrl('https://xorder.io');
      container.read(setupProvider.notifier).state = container.read(setupProvider).copyWith(
            entitlement: const LicenseEntitlement(
              state: LicenseState.valid,
              canOpenShift: true,
              canSell: true,
              canChangeConfiguration: true,
            ),
          );
      expect(container.read(setupProvider).entitlement, isNotNull);

      controller.setMode(DeploymentMode.branchServer);
      expect(
        container.read(setupProvider).entitlement,
        isNull,
        reason: 'a cloud licence does not necessarily cover a branch server',
      );
      expect(container.read(setupProvider).deployment.baseUrl, isNull);
    });

    test('the terminal id is generated once and never reissued', () {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setTerminalName('Counter 1');
      final first = container.read(setupProvider).terminalId;
      expect(first, isNotNull);

      controller.setTerminalName('Counter 1 — renamed');
      expect(container.read(setupProvider).terminalId, first);
    });

    test('activation with an empty key fails without crashing', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);

      await container.read(setupProvider.notifier).activateLicence();

      final draft = container.read(setupProvider);
      expect(draft.busy, isFalse);
      expect(draft.error, contains('not recognised'));
    });

    test('a development key issues a licence that permits trade', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setTenantSlug('mahsoub');
      controller.setLicenceKey('XORD-TEST-0001');
      await controller.activateLicence();

      final draft = container.read(setupProvider);
      expect(draft.entitlement?.state, LicenseState.valid);
      expect(draft.error, isNull);
    });

    test('a key naming an expired term surfaces the expired state', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setTenantSlug('mahsoub');
      controller.setLicenceKey('XORD-EXPIRED-0001');
      await controller.activateLicence();

      final draft = container.read(setupProvider);
      expect(draft.entitlement?.state, LicenseState.expired);
      // Still sellable inside an open shift — that is the whole policy.
      expect(draft.entitlement?.canOpenShift, isFalse);
      expect(draft.entitlement?.canSell, isTrue);
    });
  });

  group('wizard UI', () {
    testWidgets('opens on the language step with the full rail visible', (tester) async {
      await _pump(tester);

      expect(find.text('TERMINAL SETUP'), findsOneWidget);
      expect(find.text('STEP 1 OF 10'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      // Every step is listed, so the installer can see how much is left.
      expect(find.text('Licence'), findsWidgets);
      expect(find.text('Ready'), findsWidgets);
    });

    testWidgets('Continue moves to the connection step', (tester) async {
      final container = await _pump(tester);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(container.read(setupProvider).step, SetupStep.deployment);
      expect(find.text('Cloud'), findsOneWidget);
      expect(find.text('Branch server'), findsOneWidget);
      expect(find.text('Islanded'), findsOneWidget);

      // The same step asks the second question: when the queue drains. There is
      // no online-required mode, so this is the only sync choice there is.
      expect(find.text('Automatic'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);
    });

    testWidgets('a branch server must be given an upstream, not offered one', (tester) async {
      final container = await _pump(tester);
      final controller = container.read(setupProvider.notifier);
      controller.next();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Branch server'));
      await tester.pumpAndSettle();

      // Was "UPSTREAM (OPTIONAL)". An islanded branch server was withdrawn when
      // every client had to be trackable from Super Admin (POS-BE-022).
      expect(find.text('UPSTREAM'), findsOneWidget);

      controller.setBaseUrl('https://192.168.1.20:8100');
      expect(
        container.read(setupProvider).canAdvance,
        isFalse,
        reason: 'a branch that forwards nowhere is a restaurant nobody can see',
      );

      controller.setUpstreamUrl('https://xorder.io');
      expect(
        container.read(setupProvider).canAdvance,
        isFalse,
        reason: 'a branch-server till writes straight to PostgreSQL, so it needs '
            'a credential to do it with',
      );

      controller.setDatabasePassword('s3cret');
      expect(container.read(setupProvider).canAdvance, isTrue);
    });

    testWidgets('the branch database fields appear only for a branch server', (tester) async {
      final container = await _pump(tester);
      container.read(setupProvider.notifier).next();
      await tester.pumpAndSettle();

      // Cloud is selected by default and has no database of its own.
      expect(find.text('BRANCH DATABASE'), findsNothing);

      await tester.tap(find.text('Branch server'));
      await tester.pumpAndSettle();

      expect(find.text('BRANCH DATABASE'), findsOneWidget);
      expect(find.text('DATABASE'), findsOneWidget);
      expect(find.text('DATABASE USER'), findsOneWidget);
      expect(find.text('DATABASE PASSWORD'), findsOneWidget);
      expect(find.text('PORT'), findsOneWidget);
    });

    testWidgets('the database defaults are the restricted ones', (tester) async {
      final container = await _pump(tester);
      final config = container.read(setupProvider).deployment;

      // Never a superuser by default. An operator who changes it is making a
      // choice; an operator who accepts the default is safe.
      expect(config.databaseUser, 'pos_till');
      expect(config.databaseName, 'xorder_pos');
      expect(config.databasePort, 5432);
    });

    testWidgets('the database password never reaches the persisted config', (tester) async {
      final container = await _pump(tester);
      final controller = container.read(setupProvider.notifier);
      controller.setMode(DeploymentMode.branchServer);
      controller.setDatabasePassword('s3cret');

      // A password in device config is a password that ends up in a support
      // email. It belongs in the OS keystore and nowhere else.
      final json = container.read(setupProvider).deployment.toJson();
      expect(json.values.contains('s3cret'), isFalse);
      expect(json.containsKey('database_password'), isFalse);
      expect(json['database_user'], 'pos_till');
    });

    testWidgets('finishing setup hands the password to the credential store', (tester) async {
      final container = await _pump(tester);
      final controller = container.read(setupProvider.notifier);

      expect(container.read(posDbCredentialsStoreProvider).isSet, isFalse);

      controller.setMode(DeploymentMode.branchServer);
      controller.setBaseUrl('https://192.168.1.20:8100');
      controller.setUpstreamUrl('https://xorder.io');
      controller.setDatabasePassword('s3cret');
      controller.setTenantSlug('mahsoub');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(step: SetupStep.summary, catalogueItems: 19);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open the till'));
      await tester.pumpAndSettle();

      expect(container.read(posDbCredentialsStoreProvider).isSet, isTrue);
      expect(await container.read(posDbCredentialsProvider).password(), 's3cret');
    });

    testWidgets('an islanded till warns about backups and says it still checks in', (tester) async {
      final container = await _pump(tester);
      container.read(setupProvider.notifier).next();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Islanded'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no second copy'), findsOneWidget);
      expect(find.textContaining('checks in'), findsOneWidget);
    });

    testWidgets('the sync policy is a choice, and it sticks', (tester) async {
      final container = await _pump(tester);
      container.read(setupProvider.notifier).next();
      await tester.pumpAndSettle();

      expect(container.read(setupProvider).deployment.syncPolicy, SyncPolicy.automatic);

      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();

      expect(container.read(setupProvider).deployment.syncPolicy, SyncPolicy.manual);
    });

    testWidgets('Continue is disabled until the step is satisfied', (tester) async {
      final container = await _pump(tester);
      container.read(setupProvider.notifier).next();
      await tester.pumpAndSettle();

      // Cloud selected by default, but no address entered yet.
      expect(container.read(setupProvider).canAdvance, isFalse);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(container.read(setupProvider).step, SetupStep.deployment);
    });
  });

  group('provisioning', () {
    test('a pairing code fills in what the dashboard already decided', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setTenantSlug('mahsoub');
      controller.setPairingCode(FakeProvisioningRepository.demoCode);
      await controller.claimTerminal();

      final draft = container.read(setupProvider);
      expect(draft.claimed, isTrue);
      // The branch and till name arrived from the server. That inversion is the
      // whole point: the terminal row existed before this machine did.
      expect(draft.branchLabel, 'Maadi');
      expect(draft.terminalName, 'Counter 1');
      expect(draft.terminalId, isNotNull);
      expect(draft.error, isNull);
    });

    test('the account step will not advance on an unredeemed code', () {
      const typed = SetupDraft(
        step: SetupStep.account,
        deployment: DeploymentConfig(mode: DeploymentMode.cloud, tenantSlug: 'mahsoub'),
        pairingCode: 'MAADI-7Q42',
      );
      expect(
        typed.canAdvance,
        isFalse,
        reason: 'everything after this step is the answer the code returns',
      );
    });

    test('a wrong code and a spent code are different problems', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);
      controller.setTenantSlug('mahsoub');

      controller.setPairingCode('NOPE-0000');
      await controller.claimTerminal();
      expect(container.read(setupProvider).claimed, isFalse);
      expect(container.read(setupProvider).error, contains('not recognised'));

      controller.setPairingCode(FakeProvisioningRepository.demoCode);
      await controller.claimTerminal();
      expect(container.read(setupProvider).claimed, isTrue);

      // Redeeming it a second time must not read as a typo — the operator needs
      // a new code, not another attempt at this one.
      controller.setMethod(SetupMethod.pairingCode);
      controller.setPairingCode(FakeProvisioningRepository.demoCode);
      await controller.claimTerminal();
      expect(container.read(setupProvider).error, contains('already been used'));
    });

    test('switching path forgets the claim rather than leaving it behind', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setTenantSlug('mahsoub');
      controller.setPairingCode(FakeProvisioningRepository.demoCode);
      await controller.claimTerminal();
      expect(container.read(setupProvider).branchLabel, 'Maadi');

      controller.setMethod(SetupMethod.manual);

      final draft = container.read(setupProvider);
      expect(draft.claimed, isFalse);
      expect(draft.branchId, isNull);
      expect(draft.branchLabel, isNull);
      expect(draft.terminalName, isEmpty);
      expect(draft.terminalId, isNull);
    });

    test('manual setup needs credentials before it can go on', () {
      const noCredentials = SetupDraft(
        step: SetupStep.account,
        method: SetupMethod.manual,
        deployment: DeploymentConfig(mode: DeploymentMode.cloud, tenantSlug: 'mahsoub'),
      );
      expect(noCredentials.canAdvance, isFalse);

      const withCredentials = SetupDraft(
        step: SetupStep.account,
        method: SetupMethod.manual,
        deployment: DeploymentConfig(mode: DeploymentMode.cloud, tenantSlug: 'mahsoub'),
        operatorUsername: 'manager',
        operatorPassword: 'hunter2',
      );
      expect(withCredentials.canAdvance, isTrue);
    });

    test('a failed manual registration does not strand the installer', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setMethod(SetupMethod.manual);
      controller.setTenantSlug('mahsoub');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      // No credentials — the fake refuses.
      await controller.registerTerminal();

      final draft = container.read(setupProvider);
      expect(draft.claimed, isFalse);
      expect(draft.error, isNotNull);
      // The terminal step still lets them through; it registers at first sync.
      expect(draft.copyWith(step: SetupStep.terminal).canAdvance, isTrue);
    });
  });

  group('handover to the till', () {
    testWidgets('publishes branch, terminal and deployment on finish', (tester) async {
      var finished = false;
      final container = await _pump(tester, onFinished: () => finished = true);
      final controller = container.read(setupProvider.notifier);

      // Walk the draft as the operator would. setMode is first because
      // changing it deliberately clears the endpoint.
      controller.setMode(DeploymentMode.branchServer);
      controller.setBaseUrl('https://192.168.1.20:8100');
      controller.setTenantSlug('mahsoub');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');

      // Jump to the last step rather than awaiting the catalogue sync: this
      // test is about the handover, and awaiting a Future.delayed here would
      // block forever because nothing pumps the fake clock.
      controller.state = container
          .read(setupProvider)
          .copyWith(step: SetupStep.summary, catalogueItems: 19);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open the till'));
      await tester.pumpAndSettle();

      expect(finished, isTrue);
      expect(container.read(setupCompleteProvider), isTrue);

      // The branch and till name are properties of the machine, so they must
      // outlive the wizard rather than being read off whoever signed in.
      final profile = container.read(terminalProfileProvider);
      expect(profile.branchName, 'Maadi');
      expect(profile.terminalName, 'Counter 1');
      expect(profile.terminalId, isNotNull);

      expect(container.read(deploymentProvider).mode, DeploymentMode.branchServer);
      expect(container.read(deploymentProvider).baseUrl, 'https://192.168.1.20:8100');
    });
  });
}
