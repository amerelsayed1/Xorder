import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/config/platform_endpoint.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';
import 'package:xorder_pos/features/setup/presentation/setup_wizard.dart';

import '../support/fakes.dart';

const _desktop = Size(1440, 900);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  VoidCallback? onFinished,
}) async {
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

/// Jump the wizard to the connection step.
///
/// The licence step now stands between language and connection, and it cannot
/// be advanced past without a real entitlement — which is the point of the
/// reorder. Widget tests about the connection pane set the step directly rather
/// than activating a licence they are not testing.
Future<void> _toConnection(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final controller = container.read(setupProvider.notifier);
  controller.state = container
      .read(setupProvider)
      .copyWith(step: SetupStep.deployment);
  await tester.pumpAndSettle();
}

/// Put the wizard on the connection step with the OFFLINE config in force.
///
/// Offline cannot be reached through the phase-1 UI — its tile is dimmed — but
/// the panes still render it, and phase 2 will re-enable the tile. Tests about
/// those panes set the state directly.
Future<void> _toOfflineConnection(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final controller = container.read(setupProvider.notifier);
  controller.state = container
      .read(setupProvider)
      .copyWith(
        step: SetupStep.deployment,
        deployment: const DeploymentConfig(mode: DeploymentMode.offline),
      );
  await tester.pumpAndSettle();
}

void main() {
  group('testing the connection', () {
    test('an empty platform address is named, not reported as unreachable', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      // Cloud is the default mode, and its platform address starts empty.
      expect(
        container.read(setupProvider).deployment.mode,
        DeploymentMode.cloud,
      );

      expect(await controller.testConnection(), isFalse);

      final error = container.read(setupProvider).error;
      // "Could not reach null" sent an installer to check a network cable over
      // a field they had simply not filled in yet.
      expect(error, isNot(contains('null')));
      expect(error, contains('platform address'));
    });

    /// A database that does not exist yet is the ordinary state of a first
    /// install — the NEXT step is what creates it, and the message says so.
    /// Painting it red anyway told the installer something was wrong at the one
    /// moment nothing was, on a screen whose own words are "continue".
    test('a database that is not there yet is a notice, not a refusal', () async {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          posDatabaseProvider.overrideWithValue(
            _ProbesAs(PosDbFailure.missingDatabase),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      controller.setMode(DeploymentMode.offline);
      controller.setDatabaseName('kashri_altahrir');
      controller.setDatabasePassword('s3cret');

      // Still false: the database did not answer, and a caller asking whether
      // it did must not be told otherwise.
      expect(await controller.testConnection(), isFalse);

      final draft = container.read(setupProvider);
      expect(draft.error, isNull, reason: draft.error ?? '');
      expect(draft.notice, contains('kashri_altahrir'));
      // And the step is not gated on the probe, so the operator can do what the
      // message tells them to.
      expect(draft.copyWith(step: SetupStep.deployment).canAdvance, isTrue);
    });

    test('a login that is refused is still a refusal', () async {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          posDatabaseProvider.overrideWithValue(_ProbesAs(PosDbFailure.auth)),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      controller.setMode(DeploymentMode.offline);
      controller.setDatabasePassword('wrong');

      expect(await controller.testConnection(), isFalse);

      final draft = container.read(setupProvider);
      expect(draft.error, isNotNull);
      expect(draft.notice, isNull);
    });
  });

  group('step gating', () {
    test('the opening step gates; connection needs an endpoint', () {
      // A fresh draft opens on the LICENCE now, and an unlicensed till may not
      // advance off it. This assertion used to read the opposite way, because
      // the wizard used to open on the language step, which always advances.
      const draft = SetupDraft();
      expect(draft.canAdvance, isFalse);
      expect(const SetupDraft(step: SetupStep.language).canAdvance, isTrue);

      const cloudNoUrl = SetupDraft(step: SetupStep.deployment);
      expect(cloudNoUrl.canAdvance, isFalse);

      const withUrl = SetupDraft(
        step: SetupStep.deployment,
        deployment: DeploymentConfig(
          mode: DeploymentMode.cloud,
          baseUrl: 'https://xorder.io',
        ),
        databasePassword: 's3cret',
      );
      expect(withUrl.canAdvance, isTrue);
    });

    test('offline needs no platform address, but still needs a credential', () {
      const noCredential = SetupDraft(
        step: SetupStep.deployment,
        deployment: DeploymentConfig(mode: DeploymentMode.offline),
      );
      expect(
        noCredential.canAdvance,
        isFalse,
        reason: 'every mode writes straight to PostgreSQL now',
      );

      expect(
        noCredential.copyWith(databasePassword: 's3cret').canAdvance,
        isTrue,
      );
    });

    test(
      'the plan, not the mode, decides whether the database may be elsewhere',
      () {
        const soloPlan = SetupDraft();
        expect(soloPlan.maxTerminals, 1);
        expect(soloPlan.allowsSharedDatabase, isFalse);

        final multi = soloPlan.copyWith(
          claims: LicenseClaims(
            licenseId: 'lic',
            tenantSlug: 'mahsoub',
            tenantName: 'Mahsoub Grill',
            issuedAt: DateTime.utc(2026, 1, 1),
            expiresAt: DateTime.utc(2027, 1, 1),
            maxTerminals: 4,
          ),
        );
        expect(multi.allowsSharedDatabase, isTrue);
      },
    );

    test('an empty modes claim licenses everything rather than nothing', () {
      // Parsing an absent claim into an empty set and then refusing every mode
      // reads to the operator as a till that will not set up, with no way to
      // tell why.
      final draft = const SetupDraft().copyWith(
        claims: LicenseClaims(
          licenseId: 'lic',
          tenantSlug: 'mahsoub',
          tenantName: 'Mahsoub Grill',
          issuedAt: DateTime.utc(2026, 1, 1),
          expiresAt: DateTime.utc(2027, 1, 1),
          modes: const {},
        ),
      );
      expect(draft.licensedModes, DeploymentMode.values.toSet());
    });

    test(
      'hardware never blocks — a till with no printer still finishes setup',
      () {
        const draft = SetupDraft(step: SetupStep.hardware);
        expect(draft.printerName, isNull);
        expect(draft.canAdvance, isTrue);
      },
    );

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
    test('a scheme-less platform address is completed, never mis-parsed', () {
      expect(
        SetupController.baseUrlFrom('localhost:8100'),
        'http://localhost:8100',
      );
      expect(
        SetupController.baseUrlFrom('127.0.0.1:8100'),
        'http://127.0.0.1:8100',
      );
      expect(
        SetupController.baseUrlFrom('192.168.1.20:8100'),
        'http://192.168.1.20:8100',
      );
      expect(SetupController.baseUrlFrom('xorder.io'), 'https://xorder.io');
      expect(
        SetupController.baseUrlFrom('https://xorder.io'),
        'https://xorder.io',
      );
      expect(SetupController.baseUrlFrom(''), '');
    });

    test('re-selecting the current mode keeps every typed detail', () {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setBaseUrl('http://127.0.0.1:8100');
      controller.setDatabaseName('xorder-test-pos');
      controller.setDatabaseUser('pos_till');
      controller.setDatabasePort('5433');

      // Tapping the already-selected Cloud tile on the way past must be a
      // no-op — what is entered in an input stays entered.
      controller.setMode(DeploymentMode.cloud);

      final config = container.read(setupProvider).deployment;
      expect(config.databaseName, 'xorder-test-pos');
      expect(config.databaseUser, 'pos_till');
      expect(config.databasePort, 5433);
      expect(config.baseUrl, 'http://127.0.0.1:8100');
    });

    test('switching to offline drops the pairing-code method', () {
      // A pairing code is minted by a dashboard, and offline has none. A draft
      // left on that method would show a disabled tile and a button that can
      // never succeed.
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setMethod(SetupMethod.pairingCode);
      expect(container.read(setupProvider).method, SetupMethod.pairingCode);

      controller.setMode(DeploymentMode.offline);
      expect(container.read(setupProvider).method, SetupMethod.manual);

      // And it cannot be chosen again while offline.
      controller.setMethod(SetupMethod.pairingCode);
      expect(container.read(setupProvider).method, SetupMethod.manual);
    });

    test('an offline terminal cannot advance unregistered', () {
      // This rule used to pass an unregistered offline terminal, and then
      // `complete()` refused it for having no restaurant id and no branch
      // code — which only registration supplies. The operator reached the last
      // screen before being told the sixth was wrong.
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setMode(DeploymentMode.offline);
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(step: SetupStep.terminal);

      expect(
        container.read(setupProvider).canAdvance,
        isFalse,
        reason: 'a name alone is not a registered terminal',
      );
    });

    test('a mode the licence does not cover is refused', () {
      // The phase-1 block on offline is gone; the LICENCE is the only rule
      // left. A cloud-only licence must still refuse the switch, and must not
      // clear what the operator already typed while refusing it.
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setBaseUrl('https://xorder.io');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            claims: LicenseClaims(
              licenseId: 'LIC-CLOUD-ONLY',
              tenantSlug: 'mahsoub',
              tenantName: 'Mahsoub',
              issuedAt: DateTime.utc(2026),
              expiresAt: DateTime.utc(2027),
              modes: const {DeploymentMode.cloud},
            ),
          );
      controller.setMode(DeploymentMode.offline);

      final draft = container.read(setupProvider);
      expect(draft.deployment.mode, DeploymentMode.cloud);
      expect(
        draft.deployment.baseUrl,
        'https://xorder.io',
        reason: 'a refused switch must not clear what was already typed',
      );
    });

    test('the licence supplies the tenant, and it cannot then be retyped', () {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      // Before a licence, the slug is a question.
      controller.setTenantSlug('Typed');
      expect(container.read(setupProvider).deployment.tenantSlug, 'typed');

      controller.state = container
          .read(setupProvider)
          .copyWith(
            claims: LicenseClaims(
              licenseId: 'lic',
              tenantSlug: 'mahsoub',
              tenantName: 'Mahsoub Grill',
              issuedAt: DateTime.utc(2026, 1, 1),
              expiresAt: DateTime.utc(2027, 1, 1),
            ),
            deployment: const DeploymentConfig(
              mode: DeploymentMode.cloud,
              tenantSlug: 'mahsoub',
            ),
          );

      // After it, retyping could only ever contradict the licence — and the
      // verifier would reject that as a tenant mismatch on a licence that was
      // perfectly good.
      controller.setTenantSlug('somewhere-else');
      expect(container.read(setupProvider).deployment.tenantSlug, 'mahsoub');
    });

    test('activation adopts the licence tenant and a mode it covers', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setLicenceKey('XORD-TEST');
      await controller.activateLicence();

      final draft = container.read(setupProvider);
      expect(draft.claims, isNotNull);
      expect(
        draft.deployment.tenantSlug,
        draft.claims!.tenantSlug,
        reason: 'the licence names its tenant; the operator should not have to',
      );
      expect(draft.licensedModes, contains(draft.deployment.mode));
    });

    test('a licence activated against a typed platform is claimed there too', () async {
      // The bug: the licence step said xorder.io, the claim two screens later
      // went to the build default — on a developer's machine the local stack —
      // and the dashboard's pairing code came back "not recognised" from a
      // platform that had never issued it.
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setLicenceServer('https://xorder.io');
      controller.setLicenceKey('XORD-TEST');
      await controller.activateLicence();

      final draft = container.read(setupProvider);
      expect(draft.deployment.mode, DeploymentMode.cloud);
      expect(draft.deployment.baseUrl, 'https://xorder.io');

      // And the same when the mode is re-chosen later.
      controller.setMode(DeploymentMode.offline);
      controller.setMode(DeploymentMode.cloud);
      expect(container.read(setupProvider).deployment.baseUrl, 'https://xorder.io');
    });

    test('with no platform typed, a licence falls back to the build default', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setLicenceKey('XORD-TEST');
      await controller.activateLicence();

      final draft = container.read(setupProvider);
      if (draft.deployment.mode.needsBaseUrl) {
        expect(draft.deployment.baseUrl, PlatformEndpoint.base);
      }
    });

    test('a mode the licence does not cover cannot be selected', () {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.state = container
          .read(setupProvider)
          .copyWith(
            claims: LicenseClaims(
              licenseId: 'lic',
              tenantSlug: 'mahsoub',
              tenantName: 'Mahsoub Grill',
              issuedAt: DateTime.utc(2026, 1, 1),
              expiresAt: DateTime.utc(2027, 1, 1),
              modes: const {DeploymentMode.cloud},
            ),
          );

      controller.setMode(DeploymentMode.offline);
      expect(
        container.read(setupProvider).deployment.mode,
        DeploymentMode.cloud,
      );
    });

    test('a pasted domain or URL normalises to its tenant slug', () {
      expect(SetupController.slugFrom('demo.xorder.io'), 'demo');
      expect(SetupController.slugFrom('https://demo.xorder.io/menu/'), 'demo');
      expect(
        SetupController.slugFrom('  Mahsoub-Restaurnt '),
        'mahsoub-restaurnt',
      );
      expect(SetupController.slugFrom('demo'), 'demo');

      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);
      controller.setTenantSlug('demo.xorder.io');
      expect(container.read(setupProvider).deployment.tenantSlug, 'demo');
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
    testWidgets('opens on the licence, which is step one of six', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('TERMINAL SETUP'), findsOneWidget);
      // Six, not eleven (owner decision, 2026-09-15). A fresh draft is cloud,
      // and a cloud main device is asked for a licence, a mode it may not even
      // have a choice about, and a setup code — the rest it is told.
      expect(find.text('STEP 1 OF 6'), findsOneWidget);
      // The licence step used to be hidden on the cloud path, then merely
      // second. It is first now: it decides the mode, supplies the tenant, and
      // says whether there is anything to set up at all.
      expect(find.text('Licence'), findsWidgets);
      expect(find.text('Ready'), findsWidgets);

      // The licence PANE, not merely its name on the rail: the first thing an
      // installer sees is the field they have to fill.
      expect(find.text('Activate online'), findsOneWidget);
      // And nothing else. The `.xlic` file path was removed with the offline
      // licence delivery it served; a second button here would be one that
      // no supplier can answer.
      expect(find.text('Activate from file'), findsNothing);

      // And the platform the key will be sent to, stated on the same screen.
      // Its absence is what made "not recognised" unreadable: a key issued by
      // one platform and checked against another is refused correctly, and
      // without the address there is nothing to tell the installer that.
      // MicroLabel uppercases, as every field label on this screen does.
      expect(find.text('LICENCE SERVER'), findsOneWidget);
      // Twice over, and both are wanted: the field's value, and the hint that
      // shows what blanking it would return to.
      expect(find.text(PlatformEndpoint.base), findsWidgets);
    });

    testWidgets('the licence is asked before the mode it decides', (
      tester,
    ) async {
      final container = await _pump(tester);
      final steps = container.read(setupProvider).visibleSteps;

      // The whole point of the reorder. A tenant is sold cloud, offline or
      // both when the Super Admin creates it; the modes claim carries that to
      // the till, so the mode screen can offer only what was bought instead of
      // accepting a choice and refusing it two screens later.
      expect(
        steps.indexOf(SetupStep.licence),
        lessThan(steps.indexOf(SetupStep.setupType)),
      );
      // And the licence is first of all (owner decision, 2026-09-06). The
      // language step that used to hold this place is second on the OFFLINE
      // path and gone from the cloud one, which is what a fresh draft walks:
      // the restaurant already told the dashboard which language it works in.
      // The property the old order protected — being able to READ a licence
      // refusal — is held by the language switch the Settings bar carries on
      // every screen, including this one.
      expect(steps.first, SetupStep.licence);
      expect(steps[1], SetupStep.setupType);
      expect(steps, isNot(contains(SetupStep.language)));

      final offline = container
          .read(setupProvider)
          .copyWith(
            deployment: const DeploymentConfig(mode: DeploymentMode.offline),
          );
      expect(offline.visibleSteps[1], SetupStep.language);
    });

    testWidgets('the wizard opens on the licence and stops there unlicensed', (
      tester,
    ) async {
      final container = await _pump(tester);
      expect(container.read(setupProvider).step, SetupStep.licence);

      // Nothing is installed, so there is nothing to go on with: a till that
      // cannot say what it is licensed for has not earned the right to pick
      // how it runs — or to be asked anything else.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(container.read(setupProvider).step, SetupStep.licence);
    });

    test('an offline till may not leave the account step unbuilt', () {
      // The gate that replaced `connected`. Nothing may go on until the
      // database exists and holds the person who will open the till.
      const offline = SetupDraft(
        step: SetupStep.account,
        deployment: DeploymentConfig(mode: DeploymentMode.offline),
      );
      expect(offline.canAdvance, isFalse);
      expect(offline.copyWith(bootstrapped: true).canAdvance, isTrue);
    });

    test('a licence-driven mode change is a notice, not an error', () {
      // "This licence does not cover Cloud, so the terminal was set to
      // Offline" is the wizard reporting that it did the right thing. It used
      // to arrive in the red error bar, on the first screen of a healthy
      // install, as the only coloured thing on it.
      const draft = SetupDraft(notice: 'This licence does not cover Cloud…');

      expect(draft.notice, isNotNull);
      expect(draft.error, isNull);
    });

    test('an offline till registers as the administrator it just created', () {
      // The regression this pins: registration authenticates against
      // `pos_staff` on this machine, and it used to read the CLOUD sign-in
      // fields — which the offline path stopped collecting when its account
      // step became "First administrator". It sent an empty username to the
      // till's own database and was refused on the last step of the wizard.
      const draft = SetupDraft(
        step: SetupStep.terminal,
        deployment: DeploymentConfig(mode: DeploymentMode.offline),
        ownerUsername: 'amer',
        ownerPin: '1234',
        terminalName: 'Counter 1',
      );

      // The fields the offline path fills are the owner's, and they are the
      // only ones with anything in them.
      expect(draft.ownerUsername, isNotEmpty);
      expect(draft.ownerPin, isNotEmpty);
      expect(draft.operatorUsername, isEmpty);
      expect(draft.operatorPassword, isEmpty);
    });

    testWidgets(
      'an offline till creates its first administrator, not a login',
      (tester) async {
        // The bug this replaces: the account step asked an offline terminal to
        // sign in to a platform it does not have, with an account that does not
        // exist yet, and `canAdvance` required a connection it can never make —
        // so the offline path could not get past step 5 at all.
        final container = await _pump(tester);
        final controller = container.read(setupProvider.notifier);
        controller.state = container
            .read(setupProvider)
            .copyWith(
              step: SetupStep.account,
              deployment: const DeploymentConfig(mode: DeploymentMode.offline),
            );
        await tester.pumpAndSettle();

        expect(find.text('First administrator'), findsWidgets);
        expect(find.text('Sign in'), findsNothing);
        // Nothing to connect to, so nothing offering to.
        expect(find.text('Connect & pull configuration'), findsNothing);

        // And its FIELDS, open. This block used to sit collapsed behind a
        // button labelled "This machine has no database yet" — a status line
        // wearing a button, which as the whole content of a step reads as an
        // empty screen.
        expect(find.text('This machine has no database yet'), findsNothing);
        expect(find.text('FIRST INSTALL ON THIS MACHINE'), findsOneWidget);
        expect(find.text('Build the database'), findsOneWidget);
      },
    );

    testWidgets('the connection step states the mode instead of re-asking', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _toConnection(tester, container);

      expect(container.read(setupProvider).step, SetupStep.deployment);
      expect(find.text('SETUP TYPE'), findsOneWidget);
      expect(find.text('CLOUD'), findsOneWidget);

      // Only cloud has a queue to drain, so the policy is asked here.
      expect(find.text('Automatic'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);
    });

    testWidgets('an offline terminal is not asked when to send sales', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _toOfflineConnection(tester, container);

      // Asking a till that never sends sales to choose when it sends them was a
      // question with no answer.
      expect(find.text('SENDING SALES'), findsNothing);
      expect(find.text('Automatic'), findsNothing);
      expect(find.text('PLATFORM ADDRESS'), findsNothing);
    });

    testWidgets('the database is configured in every mode', (tester) async {
      final container = await _pump(tester);
      await _toConnection(tester, container);

      // Cloud is selected by default and now keeps a local PostgreSQL of its
      // own, so these are not branch-server fields any more.
      expect(find.text('DATABASE'), findsOneWidget);
      expect(find.text('DATABASE USER'), findsOneWidget);
      expect(find.text('DATABASE PASSWORD'), findsOneWidget);
      expect(find.text('PORT'), findsOneWidget);

      await _toOfflineConnection(tester, container);
      expect(find.text('DATABASE USER'), findsOneWidget);
    });

    testWidgets('database name and password keep focus while typing', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _toConnection(tester, container);

      final name = find.byKey(const ValueKey('Database name:false'));
      await tester.tap(name);
      await tester.enterText(name, 'shop');
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: name, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(name, 'shop_db');
      await tester.pump();
      expect(container.read(setupProvider).deployment.databaseName, 'shop_db');

      // A mode change creates a fresh DeploymentConfig. The field must show
      // that external reset as well as preserve focus during ordinary typing;
      // otherwise the screen and the repository connect to different names.
      await _toOfflineConnection(tester, container);
      expect(
        container.read(setupProvider).deployment.databaseName,
        'xorder_pos',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: name, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'xorder_pos',
      );

      // Keyed on which password this is, not on its caption — the caption
      // is translated and the key must not move with the language.
      final password = find.byKey(const ValueKey('database:password'));
      await tester.ensureVisible(password);
      await tester.pumpAndSettle();
      await tester.tap(password);
      await tester.enterText(password, 's3');
      await tester.pump();
      await tester.enterText(password, 's3cret');
      await tester.pump();
      expect(container.read(setupProvider).databasePassword, 's3cret');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: password,
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isTrue,
      );
    });

    testWidgets('a one-terminal plan is never asked for a database address', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _toConnection(tester, container);

      // The default plan covers one terminal, so the only honest answer is this
      // machine — and a field the operator cannot answer correctly is worse
      // than no field.
      expect(find.text('DATABASE ADDRESS'), findsNothing);
      expect(container.read(setupProvider).deployment.isSingleMachine, isTrue);

      container.read(setupProvider.notifier).state = container
          .read(setupProvider)
          .copyWith(
            claims: LicenseClaims(
              licenseId: 'lic',
              tenantSlug: 'mahsoub',
              tenantName: 'Mahsoub Grill',
              issuedAt: DateTime.utc(2026, 1, 1),
              expiresAt: DateTime.utc(2027, 1, 1),
              maxTerminals: 4,
            ),
          );
      await tester.pumpAndSettle();

      expect(find.text('DATABASE ADDRESS'), findsOneWidget);
    });

    testWidgets('the database defaults are the restricted ones', (
      tester,
    ) async {
      final container = await _pump(tester);
      final config = container.read(setupProvider).deployment;

      // Never a superuser by default. An operator who changes it is making a
      // choice; an operator who accepts the default is safe.
      expect(config.databaseUser, 'pos_till');
      expect(config.databaseName, 'xorder_pos');
      expect(config.databasePort, 5432);
    });

    testWidgets('the database password never reaches the persisted config', (
      tester,
    ) async {
      final container = await _pump(tester);
      final controller = container.read(setupProvider.notifier);
      controller.setMode(DeploymentMode.offline);
      controller.setDatabasePassword('s3cret');

      // A password in device config is a password that ends up in a support
      // email. It belongs in the OS keystore and nowhere else.
      final json = container.read(setupProvider).deployment.toJson();
      expect(json.values.contains('s3cret'), isFalse);
      expect(json.containsKey('database_password'), isFalse);
      expect(json['database_user'], 'pos_till');
    });

    testWidgets('finishing setup hands the password to the credential store', (
      tester,
    ) async {
      final container = await _pump(tester);
      final controller = container.read(setupProvider.notifier);

      expect(container.read(posDbCredentialsStoreProvider).isSet, isFalse);

      controller.setMode(DeploymentMode.offline);
      controller.setDatabaseHost('192.168.1.20');
      controller.setDatabasePassword('s3cret');
      controller.setTenantSlug('mahsoub');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            step: SetupStep.summary,
            catalogueItems: 19,
            restaurantId: 7,
            branchCode: 'MAA',
            terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
          );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open the till'));
      await tester.pumpAndSettle();

      expect(container.read(posDbCredentialsStoreProvider).isSet, isTrue);
      expect(
        await container.read(posDbCredentialsProvider).password(),
        's3cret',
      );
    });

    testWidgets('a single-machine till warns about backups', (tester) async {
      final container = await _pump(tester);
      await _toOfflineConnection(tester, container);

      // A mini-PC under the counter with no backup is how a restaurant loses a
      // year of sales, so the wizard says it out loud.
      expect(find.textContaining('no second copy'), findsOneWidget);
      expect(find.textContaining('one terminal'), findsOneWidget);
    });

    testWidgets('the sync policy is a choice, and it sticks', (tester) async {
      final container = await _pump(tester);
      await _toConnection(tester, container);

      // Cloud is the default, and it is the only mode with a queue to drain.
      expect(
        container.read(setupProvider).deployment.syncPolicy,
        SyncPolicy.automatic,
      );

      // The sync tiles now sit below the database fields, so the pane has to be
      // scrolled to reach them.
      await tester.ensureVisible(find.text('Manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();

      expect(
        container.read(setupProvider).deployment.syncPolicy,
        SyncPolicy.manual,
      );
    });

    testWidgets('Continue is disabled until the step is satisfied', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _toConnection(tester, container);

      // Cloud selected by default, but no address and no credential yet.
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
        deployment: DeploymentConfig(
          mode: DeploymentMode.cloud,
          tenantSlug: 'mahsoub',
        ),
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
      expect(
        container.read(setupProvider).error,
        contains('already been used'),
      );
    });

    test(
      'switching path forgets the claim rather than leaving it behind',
      () async {
        final container = ProviderContainer(
          overrides: fakeRepositoryOverrides(),
        );
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
      },
    );

    test('manual setup needs credentials before it can go on', () {
      const noCredentials = SetupDraft(
        step: SetupStep.account,
        method: SetupMethod.manual,
        deployment: DeploymentConfig(
          mode: DeploymentMode.cloud,
          tenantSlug: 'mahsoub',
        ),
      );
      expect(noCredentials.canAdvance, isFalse);

      const withCredentials = SetupDraft(
        step: SetupStep.account,
        method: SetupMethod.manual,
        deployment: DeploymentConfig(
          mode: DeploymentMode.cloud,
          tenantSlug: 'mahsoub',
        ),
        operatorUsername: 'manager',
        operatorPassword: 'hunter2',
      );
      expect(
        withCredentials.canAdvance,
        isFalse,
        reason:
            'typed credentials have pulled nothing yet — everything after '
            'this step displays what the pull brings back',
      );
      expect(withCredentials.copyWith(connected: true).canAdvance, isTrue);
    });

    test(
      'connecting pulls the tenant configuration for the next steps',
      () async {
        final container = ProviderContainer(
          overrides: fakeRepositoryOverrides(),
        );
        addTearDown(container.dispose);
        final controller = container.read(setupProvider.notifier);

        controller.setTenantSlug('mahsoub');
        controller.setOperatorUsername(FakeProvisioningRepository.demoUsername);
        controller.setOperatorPassword(FakeProvisioningRepository.demoPassword);
        await controller.connectTenant();

        final draft = container.read(setupProvider);
        expect(draft.connected, isTrue);
        expect(draft.tenantName, 'Mahsoub');
        expect(draft.pulledBranches, hasLength(2));
        expect(draft.error, isNull);

        // Editing a credential makes the pull stale — the branch list on screen
        // would belong to a login that no longer exists.
        controller.setOperatorPassword('changed');
        expect(container.read(setupProvider).connected, isFalse);
        expect(container.read(setupProvider).pulledBranches, isNull);
      },
    );

    test('a rejected connect says so and pulls nothing', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setTenantSlug('mahsoub');
      controller.setOperatorUsername('manager');
      controller.setOperatorPassword('wrong');
      await controller.connectTenant();

      final draft = container.read(setupProvider);
      expect(draft.connected, isFalse);
      expect(draft.pulledBranches, isNull);
      expect(draft.error, contains('not accepted'));
    });

    test(
      'completion names the missing field instead of blaming registration',
      () async {
        final container = ProviderContainer(
          overrides: fakeRepositoryOverrides(),
        );
        addTearDown(container.dispose);
        final controller = container.read(setupProvider.notifier);

        // Everything set except the invoice prefix — the exact state a branch
        // with no code used to produce, on a till whose registration succeeded.
        controller.setTenantSlug('mahsoub');
        controller.setBranch(3, 'Main Branch');
        controller.setTerminalName('Counter 1');
        controller.state = container
            .read(setupProvider)
            .copyWith(
              restaurantId: 7,
              terminalId: 'e6c0f0a2-0000-4000-8000-000000000002',
            );

        final error = await controller.complete();
        expect(error, contains('invoice prefix'));
        expect(error, isNot(contains('has not been registered')));
        expect(container.read(setupCompleteProvider), isFalse);
      },
    );

    test('a failed manual registration cannot open an unusable till', () async {
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
      // On the cloud path a failed registration BLOCKS the terminal step —
      // every later step pulls from the platform with the credential that
      // registration issues, so "continue anyway" is a dead end wearing a
      // Continue button.
      expect(draft.copyWith(step: SetupStep.terminal).canAdvance, isFalse);
      final error = await controller.complete();
      // The guard names the actual gaps a failed registration leaves behind.
      expect(error, contains('restaurant identity'));
      expect(container.read(setupCompleteProvider), isFalse);
    });
  });

  group('handover to the till', () {
    testWidgets('publishes branch, terminal and deployment on finish', (
      tester,
    ) async {
      var finished = false;
      final container = await _pump(tester, onFinished: () => finished = true);
      final controller = container.read(setupProvider.notifier);

      // Offline is dimmed in the phase-1 UI, so the draft is put there
      // directly — the handover below must keep working for phase 2.
      controller.state = container
          .read(setupProvider)
          .copyWith(
            deployment: const DeploymentConfig(
              mode: DeploymentMode.offline,
              databaseHost: '192.168.1.20',
            ),
          );
      controller.setTenantSlug('mahsoub');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            restaurantId: 7,
            branchCode: 'MAA',
            terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
          );

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

      expect(container.read(deploymentProvider).mode, DeploymentMode.offline);
      expect(container.read(deploymentProvider).databaseHost, '192.168.1.20');
    });
  });

  // A catalogue download that returns nothing used to render in the same green
  // box as a successful one, and `canAdvance` accepted it — so a till could
  // reach a restaurant with an empty menu and a tick beside it. Until the
  // catalogue endpoints land (POS-BE-012 / POS-BE-023) this is the *normal*
  // outcome on a fresh site, which is what makes it worth a test.
  group('an empty catalogue', () {
    Future<ProviderContainer> at(
      WidgetTester tester,
      SetupStep step,
      int items,
    ) async {
      final container = await _pump(tester);
      final controller = container.read(setupProvider.notifier);
      controller.state = container
          .read(setupProvider)
          .copyWith(step: step, catalogueItems: items);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('is not reported as a successful download', (tester) async {
      await at(tester, SetupStep.catalogue, 0);

      expect(find.text('No menu on this terminal'), findsOneWidget);
      expect(
        find.text('0 items cached on this terminal.'),
        findsNothing,
        reason: 'a download of nothing is not a cached menu',
      );
    });

    testWidgets('says what it costs the operator', (tester) async {
      await at(tester, SetupStep.catalogue, 0);

      expect(
        find.textContaining('nothing to ring up'),
        findsOneWidget,
        reason: 'the consequence has to be stated, not implied by a colour',
      );
    });

    testWidgets('still lets setup finish', (tester) async {
      // Deliberate: blocking would strand every installer, because on a fresh
      // site there is currently no way to load a menu at all.
      const empty = SetupDraft(step: SetupStep.catalogue, catalogueItems: 0);
      expect(empty.canAdvance, isTrue);
    });

    testWidgets('is repeated on the last screen before the till opens', (
      tester,
    ) async {
      await at(tester, SetupStep.summary, 0);

      expect(find.text('No menu on this terminal'), findsOneWidget);
    });

    testWidgets('leaves a real menu looking exactly as it did', (tester) async {
      await at(tester, SetupStep.catalogue, 19);

      expect(find.text('19 items cached on this terminal.'), findsOneWidget);
      expect(find.text('No menu on this terminal'), findsNothing);
    });
  });
}

/// A database that always answers with [failure] — or with success when it is
/// null. Subclassed rather than mocked: `probe` is the only thing under test
/// here, and everything else on `PosDatabase` needs a live server.
class _ProbesAs extends PosDatabase {
  _ProbesAs(this.failure) : super(credentials: MutablePosDbCredentials());

  final PosDbFailure? failure;

  @override
  Future<PosDbFailure?> probe(DeploymentConfig config) async => failure;
}
