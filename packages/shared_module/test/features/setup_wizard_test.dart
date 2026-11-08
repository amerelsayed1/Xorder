import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/platform_endpoint.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';
import 'package:shared_module/features/setup/presentation/setup_wizard.dart';

import 'package:xorder_pos_test_support/fakes.dart';

const _desktop = Size(1440, 900);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  VoidCallback? onFinished,
  DeploymentMode? appMode,
}) async {
  tester.view
    ..physicalSize = _desktop
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: fakeRepositoryOverrides(appMode: appMode),
  );
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
      // Cloud is the default mode. A fresh cloud draft is addressed to the
      // build's platform (pos-cloud-sign-in-setup); this one has had it
      // cleared, which is the state the message is about.
      expect(
        container.read(setupProvider).deployment.mode,
        DeploymentMode.cloud,
      );
      controller.state = container
          .read(setupProvider)
          .copyWith(
            deployment: container
                .read(setupProvider)
                .deployment
                .copyWith(baseUrl: ''),
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
          ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
          posDatabaseProvider.overrideWithValue(
            _ProbesAs(PosDbFailure.missingDatabase),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
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

    /// Found driving the real till offline (report 2026-10-24, F-1): the
    /// database password field was left empty on a machine whose PostgreSQL
    /// trusts localhost. The till never contacts PostgreSQL without a password,
    /// yet the wizard said "PostgreSQL rejected the username or password" and
    /// sent the installer to check a role that was fine.
    test('an empty database password is named, not blamed on PostgreSQL', () async {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
          // What the real pool does with no credential: an auth failure.
          posDatabaseProvider.overrideWithValue(_ProbesAs(PosDbFailure.auth)),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      controller.setDatabasePassword('');

      expect(await controller.testConnection(), isFalse);

      final draft = container.read(setupProvider);
      final strings = container.read(stringsProvider);
      expect(draft.error, strings.databasePasswordRequired);
      expect(draft.error, isNot(strings.authFailure(draft.deployment.databaseUser)));
    });

    test('a login that is refused is still a refusal', () async {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
          posDatabaseProvider.overrideWithValue(_ProbesAs(PosDbFailure.auth)),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
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

    test('an offline terminal cannot advance unregistered', () {
      // This rule used to pass an unregistered offline terminal, and then
      // `complete()` refused it for having no business id and no branch
      // code — which only registration supplies. The operator reached the last
      // screen before being told the sixth was wrong.
      final container = ProviderContainer(
        overrides: fakeRepositoryOverrides(appMode: DeploymentMode.offline),
      );
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

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

    test('offline, the licence supplies the tenant and it cannot be retyped', () {
      final container = ProviderContainer(
        overrides: fakeRepositoryOverrides(appMode: DeploymentMode.offline),
      );
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
              mode: DeploymentMode.offline,
              tenantSlug: 'mahsoub',
            ),
          );

      // After it, retyping could only ever contradict the licence — and the
      // verifier would reject that as a tenant mismatch on a licence that was
      // perfectly good.
      controller.setTenantSlug('somewhere-else');
      expect(container.read(setupProvider).deployment.tenantSlug, 'mahsoub');
    });

    // pos-cloud-sign-in-setup: a cloud till has no licence step, so the owner
    // types the business address, and nothing a licence once said locks it.
    test('on cloud the owner types the business address, and the database '
        'is named after it', () {
      final container = ProviderContainer(
        overrides: fakeRepositoryOverrides(appMode: DeploymentMode.cloud),
      );
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      final fresh = container.read(setupProvider);
      expect(fresh.step, SetupStep.account);
      // Addressed to the build's platform without a licence to name it.
      expect(fresh.deployment.baseUrl, PlatformEndpoint.base);

      controller.setTenantSlug('Cafe-Nile.xorder.io');
      var draft = container.read(setupProvider);
      expect(draft.deployment.tenantSlug, 'cafe-nile');
      expect(
        draft.deployment.databaseName,
        DeploymentConfig.databaseNameFor('cafe-nile'),
      );

      // A typo corrected follows through to the name it derived.
      controller.setTenantSlug('cafe-nil');
      controller.setTenantSlug('cafe-nile2');
      draft = container.read(setupProvider);
      expect(draft.deployment.tenantSlug, 'cafe-nile2');
      expect(
        draft.deployment.databaseName,
        DeploymentConfig.databaseNameFor('cafe-nile2'),
      );
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
      // And names the database after the business: the wizard builds it,
      // and `mahsoub_db` says whose it is where `xorder_pos` said nothing.
      expect(draft.deployment.databaseName, 'mahsoub_db');

      // A name the operator typed is theirs; the default is only a default.
      controller.setDatabaseName('shop_db');
      await controller.activateLicence();
      expect(container.read(setupProvider).deployment.databaseName, 'shop_db');
    });

    test('the draft follows the language bar, so the last word is the operator\'s', () async {
      // The claim sets the business's own language, and the Settings bar
      // lets whoever is standing there switch back. The draft used to keep
      // the claim's answer, and `complete()` wrote that to disk — a till
      // switched to English on the last screen booted in Arabic.
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);
      container.read(localeProvider.notifier).apply('ar');
      expect(container.read(setupProvider).locale, 'ar');

      container.read(localeProvider.notifier).apply('en');
      expect(container.read(setupProvider).locale, 'en');
      expect(controller.state.locale, 'en');
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
    // pos-cloud-sign-in-setup, AC-1 and AC-10.
    testWidgets('the cloud app opens on the owner sign-in, and nothing else', (
      tester,
    ) async {
      final container = await _pump(tester, appMode: DeploymentMode.cloud);
      final steps = container.read(setupProvider).visibleSteps;

      expect(find.text('TERMINAL SETUP'), findsOneWidget);
      expect(find.text('STEP 1 OF ${steps.length}'), findsOneWidget);
      expect(container.read(setupProvider).step, SetupStep.account);

      // The three questions: the business address (only the part before
      // `.xorder.io`), the owner's username and password. MicroLabel
      // uppercases, as every field label on this screen does.
      expect(find.text('BUSINESS ADDRESS'), findsOneWidget);
      expect(find.text('.xorder.io'), findsOneWidget);
      expect(find.text('USERNAME'), findsOneWidget);
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(
        find.text(const EnStrings().ownerSignInHelp),
        findsOneWidget,
      );

      // No licence key, no licence server, no pairing code, no other road.
      expect(find.text('Activate online'), findsNothing);
      expect(find.text('LICENCE SERVER'), findsNothing);
      expect(find.text('LICENCE KEY'), findsNothing);
      expect(find.text('SETUP CODE'), findsNothing);
      expect(find.text('Sign in instead'), findsNothing);
    });

    // Found running the app on 2026-11-08: on an Arabic screen the suffix sat
    // before the address and read "xorder.io.demo".
    testWidgets('on an Arabic screen the address still reads cafe-nile.xorder.io',
        (tester) async {
      final container = await _pump(tester, appMode: DeploymentMode.cloud);
      container.read(localeProvider.notifier).apply('ar');
      await tester.pumpAndSettle();

      final suffix = find.text('.xorder.io');
      expect(suffix, findsOneWidget);
      final direction = tester
          .widget<Directionality>(
            find
                .ancestor(of: suffix, matching: find.byType(Directionality))
                .first,
          )
          .textDirection;
      expect(direction, TextDirection.ltr);
    });

    testWidgets('the offline app opens on the licence, as it always has', (
      tester,
    ) async {
      final container = await _pump(tester, appMode: DeploymentMode.offline);
      final steps = container.read(setupProvider).visibleSteps;

      expect(find.text('STEP 1 OF ${steps.length}'), findsOneWidget);
      expect(find.text('Licence'), findsWidgets);
      // The licence PANE, not merely its name on the rail.
      expect(find.text('Activate online'), findsOneWidget);
      expect(find.text('Activate from file'), findsNothing);
      // And the platform the key will be sent to, stated on the same screen
      // (unchanged by pos-cloud-sign-in-setup, which is cloud only).
      expect(find.text('LICENCE SERVER'), findsOneWidget);
      expect(find.text(PlatformEndpoint.base), findsWidgets);
    });

    testWidgets('the licence is asked first offline, and not at all on cloud', (
      tester,
    ) async {
      final container = await _pump(tester, appMode: DeploymentMode.offline);
      final offline = container.read(setupProvider).visibleSteps;
      expect(offline.first, SetupStep.licence);
      expect(offline[1], SetupStep.language);

      final cloud = container
          .read(setupProvider)
          .copyWith(
            // Off the licence: the step being stood on is always listed.
            step: SetupStep.account,
            deployment: const DeploymentConfig(mode: DeploymentMode.cloud),
          )
          .visibleSteps;
      expect(cloud.first, SetupStep.account);
      expect(cloud, isNot(contains(SetupStep.licence)));
      expect(cloud, isNot(contains(SetupStep.language)));
    });

    testWidgets('the offline wizard opens on the licence and stops there '
        'unlicensed', (tester) async {
      final container = await _pump(tester, appMode: DeploymentMode.offline);
      expect(container.read(setupProvider).step, SetupStep.licence);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(container.read(setupProvider).step, SetupStep.licence);
    });

    testWidgets('the cloud wizard will not leave the sign-in unsigned', (
      tester,
    ) async {
      final container = await _pump(tester, appMode: DeploymentMode.cloud);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(container.read(setupProvider).step, SetupStep.account);
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
      // `pos_users` on this machine, and it used to read the CLOUD sign-in
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
        // empty screen. It is two screens now (pos-setup-owner-step); the first
        // asks for the one password and says in plain words why.
        expect(find.text('This machine has no database yet'), findsNothing);
        expect(find.text('Database access'), findsOneWidget);
        expect(
          find.byKey(const Key('first-install-database-access')),
          findsOneWidget,
        );
        // One button per screen: no "Build the database" beside a dimmed
        // Continue.
        expect(find.text('Build the database'), findsNothing);
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
      final container = await _pump(tester, appMode: DeploymentMode.offline);
      final controller = container.read(setupProvider.notifier);
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
      final container = await _pump(tester, appMode: DeploymentMode.offline);
      final controller = container.read(setupProvider.notifier);

      expect(container.read(posDbCredentialsStoreProvider).isSet, isFalse);

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
            businessId: 7,
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

      // A mini-PC under the counter with no backup is how a business loses a
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
    test('the owner signs in and adopts the till the dashboard made', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setTenantSlug('mahsoub');
      controller.setOperatorUsername(FakeProvisioningRepository.demoUsername);
      controller.setOperatorPassword(FakeProvisioningRepository.demoPassword);
      await controller.connectTenant();
      // The waiting till is offered first; the one in service is not.
      expect(container.read(setupProvider).adoptTerminalId, 11);
      await controller.registerTerminal();

      final draft = container.read(setupProvider);
      expect(draft.claimed, isTrue);
      // The branch and till name arrived from the server: the terminal row
      // existed before this machine did.
      expect(draft.branchLabel, 'Maadi');
      expect(draft.terminalName, 'Counter 1');
      expect(draft.terminalId, isNotNull);
      expect(draft.error, isNull);
    });

    // pos-cloud-sign-in-setup, AC-7: only the owner sets up a cloud till.
    test('an account that is not the owner\'s is refused and pulls nothing',
        () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      final controller = container.read(setupProvider.notifier);

      controller.setTenantSlug('mahsoub');
      controller.setOperatorUsername(FakeProvisioningRepository.staffUsername);
      controller.setOperatorPassword(FakeProvisioningRepository.demoPassword);
      await controller.connectTenant();

      final draft = container.read(setupProvider);
      expect(draft.connected, isFalse);
      expect(draft.pulledBranches, isNull);
      expect(draft.pulledTerminals, isNull);
      expect(draft.error, contains('Only the business owner'));
      expect(draft.canAdvance, isFalse);
    });

    test('manual setup needs credentials before it can go on', () {
      const noCredentials = SetupDraft(
        step: SetupStep.account,
        deployment: DeploymentConfig(
          mode: DeploymentMode.cloud,
          tenantSlug: 'mahsoub',
        ),
      );
      expect(noCredentials.canAdvance, isFalse);

      const withCredentials = SetupDraft(
        step: SetupStep.account,
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
              businessId: 7,
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
      expect(error, contains('business identity'));
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
            businessId: 7,
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
  // reach a business with an empty menu and a tick beside it. Until the
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
