import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/config/terminal_config.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/config/terminal_config_store.dart';
import 'package:xorder_pos/data/config/pos_db_secret_store.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';
import 'package:xorder_pos/features/setup/presentation/setup_wizard.dart';

import '../support/fakes.dart';

/// Setup has to be a one-time screen.
///
/// It was not: every launch rebuilt the deployment, the terminal profile and
/// the completion flag from their in-memory defaults, so the wizard reappeared
/// each morning — and reissued the terminal id the licence is pinned to while
/// it was there.
void main() {
  const terminal = TerminalProfile(
    branchId: 13,
    branchName: 'Maadi',
    terminalName: 'Counter 1',
    terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
    restaurantId: 7,
    branchCode: 'MAA',
  );

  const deployment = DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseHost: '192.168.1.20',
  );

  const saved = SavedTerminalConfig(
    deployment: deployment,
    terminal: terminal,
    languageCode: 'ar',
  );

  group('the configuration file', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('xorder_config_test');
    });

    tearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    FileTerminalConfigStore store() =>
        FileTerminalConfigStore(directory: () async => directory);

    test('survives the round trip a restart makes', () async {
      await store().write(saved);

      // A second store, as a second launch would build.
      final restored = await store().read();

      expect(restored, isNotNull);
      expect(restored!.terminal.terminalId, terminal.terminalId);
      expect(restored.terminal.branchName, 'Maadi');
      expect(restored.terminal.restaurantId, 7);
      expect(restored.deployment.mode, DeploymentMode.offline);
      expect(restored.deployment.databaseHost, '192.168.1.20');
      expect(restored.languageCode, 'ar');
      expect(restored.isUsable, isTrue);
    });

    test('never holds the database password', () async {
      await store().write(saved);

      final raw = await File(
        '${directory.path}/${FileTerminalConfigStore.fileName}',
      ).readAsString();
      final json = jsonDecode(raw) as Map<String, Object?>;
      final deployment = json['deployment']! as Map<String, Object?>;

      // The password is in the OS keystore. A config file is the first thing
      // that gets attached to a support email.
      expect(deployment.containsKey('database_password'), isFalse);
      expect(raw.contains('password'), isFalse);
    });

    test(
      'a truncated file reads as no configuration, not as a crash',
      () async {
        final file = File(
          '${directory.path}/${FileTerminalConfigStore.fileName}',
        );
        await file.writeAsString('{"deployment": {"mo');

        expect(await store().read(), isNull);
      },
    );

    test(
      'a configuration naming no terminal is not a finished setup',
      () async {
        await store().write(
          const SavedTerminalConfig(
            deployment: deployment,
            terminal: TerminalProfile(),
            languageCode: 'en',
          ),
        );

        // Better the wizard than a start screen whose every query fails.
        expect(await store().read(), isNull);
      },
    );

    test('a named but unregistered terminal is not a finished setup', () async {
      await store().write(
        const SavedTerminalConfig(
          deployment: deployment,
          terminal: TerminalProfile(
            branchId: 13,
            branchName: 'Maadi',
            terminalName: 'Counter 1',
          ),
          languageCode: 'en',
        ),
      );

      expect(await store().read(), isNull);
    });

    test('clearing it leaves nothing behind for the next launch', () async {
      await store().write(saved);
      await store().clear();

      expect(await store().read(), isNull);
    });
  });

  group('what the next launch does with it', () {
    ProviderContainer boot(TerminalBoot state) {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          terminalBootProvider.overrideWithValue(state),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a saved terminal opens straight into the till', () {
      final container = boot(
        const TerminalBoot(config: saved, hasDatabaseCredential: true),
      );

      expect(container.read(setupCompleteProvider), isTrue);
      expect(
        container.read(terminalProfileProvider).terminalId,
        terminal.terminalId,
      );
      expect(container.read(deploymentProvider).databaseHost, '192.168.1.20');
      // The language belongs to the terminal, not to whoever signs in.
      expect(container.read(localeProvider).languageCode, 'ar');
    });

    test('a terminal whose keystore lost the password goes back to setup', () {
      final container = boot(
        const TerminalBoot(config: saved, hasDatabaseCredential: false),
      );

      // Skipping the wizard here would open a till that cannot reach its
      // database — worse than the wizard, because nothing on screen says why.
      expect(container.read(setupCompleteProvider), isFalse);
    });

    // An empty keystore and a broken one both land the operator on the same
    // screen. They need opposite responses — retype the password, versus this
    // machine cannot keep one — so the boot path has to carry the difference.
    test('an empty keystore is not reported as a broken one', () async {
      final credentials = MutablePosDbCredentials(store: _EmptySecretStore());
      await credentials.restore();

      expect(credentials.isSet, isFalse);
      expect(credentials.storeUnavailable, isFalse);
    });

    test(
      'a keystore that refused is distinguishable from an empty one',
      () async {
        final credentials = MutablePosDbCredentials(
          store: _FailingSecretStore(),
        );
        await credentials.restore();

        expect(credentials.isSet, isFalse);
        expect(
          credentials.storeUnavailable,
          isTrue,
          reason:
              'otherwise the wizard tells an installer to retype a password '
              'that this machine cannot keep, and they are back tomorrow',
        );

        // Routing is unchanged either way: both go to the wizard.
        final container = boot(
          const TerminalBoot(
            config: saved,
            hasDatabaseCredential: false,
            credentialStoreUnavailable: true,
          ),
        );
        expect(container.read(setupCompleteProvider), isFalse);
        expect(
          container.read(terminalBootProvider).credentialStoreUnavailable,
          isTrue,
        );
      },
    );

    test(
      'and reopens the wizard already filled in, missing only the password',
      () {
        final container = boot(
          const TerminalBoot(config: saved, hasDatabaseCredential: false),
        );
        final draft = container.read(setupProvider);

        expect(draft.terminalName, 'Counter 1');
        expect(draft.branchLabel, 'Maadi');
        expect(draft.deployment.databaseHost, '192.168.1.20');
        expect(draft.databasePassword, isEmpty);
        // Above all: reissuing this would stop the installed licence matching.
        expect(draft.terminalId, terminal.terminalId);
      },
    );

    test('a fresh machine gets the wizard and an empty draft', () {
      final container = boot(TerminalBoot.none);

      expect(container.read(setupCompleteProvider), isFalse);
      expect(container.read(setupProvider).terminalName, isEmpty);
      expect(container.read(setupProvider).terminalId, isNull);
    });
  });

  group('finishing setup', () {
    testWidgets('writes the terminal to disk before reporting itself done', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final store = InMemoryTerminalConfigStore();
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          terminalConfigStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildPosTheme(),
            home: SetupWizard(onFinished: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = container.read(setupProvider.notifier);
      controller.setMode(DeploymentMode.offline);
      controller.setDatabaseHost('192.168.1.20');
      controller.setDatabasePassword('s3cret');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            step: SetupStep.summary,
            catalogueItems: 19,
            restaurantId: 7,
            branchCode: 'MAA',
            terminalId: terminal.terminalId,
          );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open the till'));
      await tester.pumpAndSettle();

      expect(store.writes, 1);
      expect(store.saved!.terminal.terminalName, 'Counter 1');
      expect(store.saved!.deployment.databaseHost, '192.168.1.20');
      expect(container.read(setupCompleteProvider), isTrue);
    });

    testWidgets(
      'a terminal that cannot save its setup does not claim to be set up',
      (tester) async {
        tester.view
          ..physicalSize = const Size(1440, 900)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        var finished = false;
        final container = ProviderContainer(
          overrides: [
            ...fakeRepositoryOverrides(),
            terminalConfigStoreProvider.overrideWithValue(
              _UnwritableConfigStore(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildPosTheme(),
              home: SetupWizard(onFinished: () => finished = true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final controller = container.read(setupProvider.notifier);
        controller.setMode(DeploymentMode.offline);
        controller.setDatabaseHost('192.168.1.20');
        controller.setDatabasePassword('s3cret');
        controller.setBranch(13, 'Maadi');
        controller.setTerminalName('Counter 1');
        controller.state = container
            .read(setupProvider)
            .copyWith(
              step: SetupStep.summary,
              catalogueItems: 19,
              restaurantId: 7,
              branchCode: 'MAA',
              terminalId: terminal.terminalId,
            );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open the till'));
        await tester.pumpAndSettle();

        // The operator is still here, password in hand, and can be told. The
        // alternative is a till that looks configured and is not, discovered
        // tomorrow morning by whoever opens the restaurant.
        expect(finished, isFalse);
        expect(container.read(setupCompleteProvider), isFalse);
        expect(find.textContaining('Could not save'), findsOneWidget);
      },
    );

    test('a keystore write failure leaves setup incomplete', () async {
      final credentials = MutablePosDbCredentials(store: _FailingSecretStore());
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          posDbCredentialsStoreProvider.overrideWithValue(credentials),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      controller.setDatabasePassword('s3cret');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            restaurantId: 7,
            branchCode: 'MAA',
            terminalId: terminal.terminalId,
          );

      final error = await controller.complete();

      expect(error, contains('Could not save'));
      expect(container.read(setupCompleteProvider), isFalse);
    });

    test(
      'fresh setup has a stable installation id before licence activation',
      () {
        final container = ProviderContainer(
          overrides: fakeRepositoryOverrides(),
        );
        addTearDown(container.dispose);

        final installationId = container
            .read(terminalProfileProvider)
            .installationId;
        final draft = container.read(setupProvider);

        expect(installationId, isNotNull);
        expect(installationId, isNotEmpty);
        expect(draft.installationId, installationId);

        final controller = container.read(setupProvider.notifier);
        controller.setTerminalName('Counter 1');
        expect(controller.profile.installationId, installationId);
      },
    );
  });

  group('resetting a terminal', () {
    test(
      'clears the saved setup but keeps the id the licence is pinned to',
      () async {
        final store = InMemoryTerminalConfigStore()..saved = saved;
        final credentials = MutablePosDbCredentials()..set('s3cret');

        final container = ProviderContainer(
          overrides: [
            ...fakeRepositoryOverrides(),
            terminalBootProvider.overrideWithValue(
              const TerminalBoot(config: saved, hasDatabaseCredential: true),
            ),
            terminalConfigStoreProvider.overrideWithValue(store),
            posDbCredentialsStoreProvider.overrideWithValue(credentials),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(setupCompleteProvider), isTrue);

        await container.read(terminalResetProvider).run();

        expect(
          store.saved,
          isNull,
          reason: 'a reset that survives a restart is not a reset',
        );
        expect(credentials.isSet, isFalse);
        expect(container.read(setupCompleteProvider), isFalse);
        expect(
          container.read(deploymentProvider),
          DeploymentConfig.unconfigured,
        );
        expect(
          container.read(terminalProfileProvider).terminalId,
          terminal.terminalId,
          reason:
              'reissuing it would turn a reconfiguration into a licence ticket',
        );
        expect(container.read(terminalProfileProvider).terminalName, isNull);
      },
    );
  });
  group('a licence installed on an earlier run', () {
    /// Pre-load the fake issuer the way a previous launch would have left it:
    /// a licence on disk, and a brand-new wizard draft that knows nothing.
    Future<ProviderContainer> boot() async {
      final licences = FakeLicenceService();
      // Activation is what puts a licence on disk. Doing it through the real
      // path rather than reaching into the fake keeps this honest.
      await licences.activate(
        deployment: const DeploymentConfig(mode: DeploymentMode.offline),
        key: 'DEV-KEY',
      );

      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          licenceServiceProvider.overrideWithValue(licences),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is adopted by the wizard instead of being asked for again', () async {
      final container = await boot();

      // Nothing has run yet: the draft is what a fresh process builds.
      expect(container.read(setupProvider).entitlement, isNull);

      // The restore is scheduled from build(), so it lands on the next turn.
      await Future<void>.delayed(Duration.zero);

      final draft = container.read(setupProvider);
      expect(draft.entitlement, isNotNull);
      expect(
        draft.canAdvance,
        isTrue,
        reason:
            'a till holding a valid licence must not be stuck on the '
            'licence step with no way past it',
      );
    });

    test('and its claims still drive the rest of the wizard', () async {
      final container = await boot();

      // Reading it is what builds it, and building it is what schedules the
      // restore — so the read has to come before the wait, not after.
      container.read(setupProvider);
      await Future<void>.delayed(Duration.zero);

      final draft = container.read(setupProvider);
      // The same adoption a fresh activation performs: the tenant is taken from
      // the licence rather than typed, and max_terminals is what decides
      // whether the connection step may point at another machine.
      expect(draft.claims, isNotNull);
      expect(draft.deployment.tenantSlug, isNotEmpty);
      expect(draft.allowsSharedDatabase, isTrue);
    });

    test('can be replaced by one for a different restaurant', () async {
      final container = await boot();
      container.read(setupProvider);
      await Future<void>.delayed(Duration.zero);

      // The restored licence has supplied a tenant.
      final adopted = container.read(setupProvider).deployment.tenantSlug;
      expect(adopted, isNotEmpty);

      // Now install a licence for somebody else — a till being moved, or a
      // developer's machine that last ran the end-to-end suite. The licence
      // step is where the tenant *comes from*, so the incoming licence must not
      // be judged against the tenant of the one it replaces. Refusing it
      // reported the new licence as wrong, when nothing was wrong with it.
      await container
          .read(setupProvider.notifier)
          .activateLicence(fileContents: _licenceFor('another-restaurant'));

      final draft = container.read(setupProvider);
      expect(draft.error, isNull, reason: draft.error ?? '');
      expect(draft.claims?.tenantSlug, 'another-restaurant');
      expect(draft.deployment.tenantSlug, 'another-restaurant');
    });

    test('but a claimed terminal still refuses the wrong restaurant', () async {
      final container = await boot();
      container.read(setupProvider);
      await Future<void>.delayed(Duration.zero);

      // A pairing claim means the tenant came from the dashboard, not from a
      // file. That is authoritative, and the check has to bite.
      final controller = container.read(setupProvider.notifier);
      controller.state = container
          .read(setupProvider)
          .copyWith(
            claimed: true,
            deployment: container
                .read(setupProvider)
                .deployment
                .copyWith(tenantSlug: 'claimed-tenant'),
          );

      await controller.activateLicence(
        fileContents: _licenceFor('somebody-else'),
      );

      expect(container.read(setupProvider).error, isNotNull);
    });

    test('a machine with no licence is left alone', () async {
      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);

      container.read(setupProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(setupProvider).entitlement, isNull);
      expect(
        container.read(setupProvider).canAdvance,
        isFalse,
        reason:
            'a fresh install now opens on the licence step, and an unlicensed '
            'terminal has nothing to set up',
      );
    });
  });
}

/// A disk that will not take the file — full, read-only, or gone.
class _UnwritableConfigStore implements TerminalConfigStore {
  @override
  Future<SavedTerminalConfig?> read() async => null;

  @override
  Future<void> write(SavedTerminalConfig config) async =>
      throw const FileSystemException('No space left on device');

  @override
  Future<void> clear() async {}
}

/// A working keystore that simply holds nothing — a fresh install.
class _EmptySecretStore implements PosDbSecretStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> clear() async {}

  @override
  Object? get lastFailure => null;
}

class _FailingSecretStore implements PosDbSecretStore {
  @override
  Future<String?> read() async {
    _lastFailure = Exception('keystore locked');
    return null;
  }

  @override
  Future<void> write(String value) async => throw Exception('keystore locked');

  @override
  Future<void> clear() async {}

  @override
  Object? get lastFailure => _lastFailure;
  Object? _lastFailure;
}

/// A licence file for [tenant], shaped the way the fake issuer shapes one.
///
/// The fake verifier does not check signatures, so the bytes only have to
/// parse — what is under test is the tenant rule, not the cryptography.
String _licenceFor(String tenant) {
  final now = DateTime.now().toUtc();
  final claims = LicenseClaims(
    licenseId: 'test-$tenant',
    tenantSlug: tenant,
    tenantName: tenant,
    issuedAt: now.subtract(const Duration(days: 1)),
    expiresAt: now.add(const Duration(days: 365)),
    maxTerminals: 4,
    modes: DeploymentMode.values.toSet(),
  );

  return LicenseFile(
    payloadB64: base64Url.encode(utf8.encode(jsonEncode(claims.toJson()))),
    signatureB64: base64Url.encode(List<int>.filled(64, 0)),
  ).serialize();
}
