import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/printer_config.dart';
import 'package:shared_module/core/config/terminal_config.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/config/setup_progress_store.dart';
import 'package:shared_module/data/config/terminal_config_store.dart';
import 'package:shared_module/data/config/pos_db_secret_store.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/features/licensing/data/licence_service.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';
import 'package:shared_module/features/setup/presentation/setup_wizard.dart';

import 'package:xorder_pos_test_support/fakes.dart';

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
    businessId: 7,
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
      expect(restored.terminal.businessId, 7);
      expect(restored.deployment.mode, DeploymentMode.offline);
      expect(restored.deployment.databaseHost, '192.168.1.20');
      expect(restored.languageCode, 'ar');
      expect(restored.isUsable, isTrue);
    });

    test('remembers the printer the installer chose', () async {
      // **It did not, and that is why nothing printed.** The hardware step has
      // offered a printer list since setup existed and the choice was held in
      // the draft and written nowhere — so the till came up the next morning
      // with no address to send a receipt to.
      await store().write(
        saved.copyWith(
          printer: const PrinterConfig(
            name: '192.168.1.44:9100',
            paperWidthDots: PrinterConfig.width58mm,
          ),
        ),
      );

      final restored = await store().read();
      expect(restored!.printer.name, '192.168.1.44:9100');
      expect(restored.printer.paperWidthDots, PrinterConfig.width58mm);
      expect(restored.printer.isConfigured, isTrue);
    });

    test('a file written before printing existed reads as no printer', () async {
      final file = File('${directory.path}/${FileTerminalConfigStore.fileName}');
      final json =
          jsonDecode(await () async {
                await store().write(saved);
                return file.readAsString();
              }())
              as Map<String, Object?>;
      json.remove('printer');
      await file.writeAsString(jsonEncode(json));

      // Which is the honest answer, and the one the settle dialog reports out
      // loud rather than claiming to have queued something.
      final restored = await store().read();
      expect(restored!.printer.isConfigured, isFalse);
      // And 80mm, because that is the roll the till most likely has on it and
      // the installer can see and change it.
      expect(restored.printer.paperWidthDots, PrinterConfig.width80mm);
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
          // Not the English override: what this group asserts is that a
          // terminal opens in the language it was SET UP in.
          ...fakeRepositoryOverrides(english: false),
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
      // So does the printer. A till that had to be told again every morning
      // which printer it is bolted to is a till that prints nothing.
      expect(container.read(printerConfigProvider).isConfigured, isFalse);
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
          ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
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
      controller.setDatabaseHost('192.168.1.20');
      controller.setDatabasePassword('s3cret');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            step: SetupStep.summary,
            catalogueItems: 19,
            businessId: 7,
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
            ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
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
        controller.setDatabaseHost('192.168.1.20');
        controller.setDatabasePassword('s3cret');
        controller.setBranch(13, 'Maadi');
        controller.setTerminalName('Counter 1');
        controller.state = container
            .read(setupProvider)
            .copyWith(
              step: SetupStep.summary,
              catalogueItems: 19,
              businessId: 7,
              branchCode: 'MAA',
              terminalId: terminal.terminalId,
            );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open the till'));
        await tester.pumpAndSettle();

        // The operator is still here, password in hand, and can be told. The
        // alternative is a till that looks configured and is not, discovered
        // tomorrow morning by whoever opens the business.
        expect(finished, isFalse);
        expect(container.read(setupCompleteProvider), isFalse);
        expect(find.textContaining('Could not save'), findsOneWidget);
      },
    );

    test('finishing setup writes the printer to disk and to memory', () async {
      final store = InMemoryTerminalConfigStore();
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          terminalConfigStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      controller.setDatabasePassword('s3cret');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.setPrinter('192.168.1.44:9100');
      controller.setPaperWidth(PrinterConfig.width58mm);
      controller.state = container
          .read(setupProvider)
          .copyWith(
            businessId: 7,
            branchCode: 'MAA',
            terminalId: terminal.terminalId,
          );

      expect(await controller.complete(), isNull);

      // On disk, for tomorrow morning.
      expect(store.saved!.printer.name, '192.168.1.44:9100');
      expect(store.saved!.printer.paperWidthDots, PrinterConfig.width58mm);
      // And in memory, for the first sale — setup finishes without a restart,
      // so a till that only wrote the file would print nothing until it was
      // relaunched.
      expect(
        container.read(printerConfigProvider).name,
        '192.168.1.44:9100',
      );
    });

    /// The licence is step ONE of ten. Writing it there installed it on every
    /// machine somebody merely *tried* a key on — an owner seeing what a key
    /// covers, an installer stopped at the database password — and the file
    /// outlived the abandoned wizard. The next person through was judged
    /// against a licence for a business that terminal had never been set up
    /// for, and told their own licence was the wrong one.
    test('activating a licence installs nothing until setup finishes', () async {
      final licences = FakeLicenceService();
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          licenceServiceProvider.overrideWithValue(licences),
          terminalConfigStoreProvider.overrideWithValue(
            InMemoryTerminalConfigStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      await controller.activateLicence(
        fileContents: _licenceFor('kashri-altahrir'),
      );

      // Read, judged and on screen — the wizard runs on these claims.
      final draft = container.read(setupProvider);
      expect(draft.entitlement, isNotNull);
      expect(draft.claims?.tenantSlug, 'kashri-altahrir');
      // And nothing on disk. That is the whole point: walk away here and the
      // machine is exactly as it was.
      expect(
        await licences.installed(),
        isNull,
        reason: 'an abandoned wizard must not leave a licence behind',
      );

      // Now finish, as the last screen does.
      controller.setDatabasePassword('s3cret');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            businessId: 7,
            branchCode: 'MAA',
            terminalId: terminal.terminalId,
          );

      expect(await controller.complete(), isNull);

      final installed = await licences.installed();
      expect(installed, isNotNull);
      expect(
        LicenseVerifier.claimsOf(installed!)?.tenantSlug,
        'kashri-altahrir',
        reason:
            'a finished terminal that cannot find its licence opens on '
            '"Not licensed" with nothing to explain itself with',
      );
    });

    test('the licence that lands is the last one activated', () async {
      final licences = FakeLicenceService();
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          licenceServiceProvider.overrideWithValue(licences),
          terminalConfigStoreProvider.overrideWithValue(
            InMemoryTerminalConfigStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      // Somebody pastes the wrong file first, then the right one. Only the
      // second was ever meant to be on this machine.
      await controller.activateLicence(fileContents: _licenceFor('wrong-one'));
      await controller.activateLicence(
        fileContents: _licenceFor('kashri-altahrir'),
      );

      controller.setDatabasePassword('s3cret');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            businessId: 7,
            branchCode: 'MAA',
            terminalId: terminal.terminalId,
          );

      expect(await controller.complete(), isNull);

      expect(
        LicenseVerifier.claimsOf((await licences.installed())!)?.tenantSlug,
        'kashri-altahrir',
      );
    });

    /// A cloud terminal never types a key: the bootstrap bundle its claim
    /// carries has a licence embedded, and that used to be written to disk the
    /// moment the claim returned — at step six, with four screens still to go.
    /// The same rule has to hold for it.
    test('a licence from the bootstrap bundle waits with the rest', () async {
      final licences = FakeLicenceService();
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          licenceServiceProvider.overrideWithValue(licences),
          terminalConfigStoreProvider.overrideWithValue(
            InMemoryTerminalConfigStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(setupProvider.notifier);
      // What the operator typed at step one.
      await controller.activateLicence(fileContents: _licenceFor('typed-one'));
      // What the claim came back with four steps later. The platform's own
      // copy for this terminal, so it supersedes the typed one.
      controller.holdLicence(
        LicenseFile.tryParse(_licenceFor('from-the-bundle'))!,
      );

      expect(
        await licences.installed(),
        isNull,
        reason: 'a claim is step six of ten, not the end of the wizard',
      );

      controller.setDatabasePassword('s3cret');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      controller.state = container
          .read(setupProvider)
          .copyWith(
            businessId: 7,
            branchCode: 'MAA',
            terminalId: terminal.terminalId,
          );

      expect(await controller.complete(), isNull);

      expect(
        LicenseVerifier.claimsOf((await licences.installed())!)?.tenantSlug,
        'from-the-bundle',
      );
    });

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
            businessId: 7,
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

    /// The reset that worked on disk and not in memory.
    ///
    /// `terminalBootProvider` is the snapshot taken before the first frame, and
    /// an override cannot be corrected from inside the process — so the wizard
    /// reopened seeded from the terminal that had just been cleared: the old
    /// tenant, and `claimed: true`. That pair is exactly what switches the
    /// tenant check back on in `activateLicence`, so the next business's
    /// licence was refused for belonging to the wrong business, naming one no
    /// longer on the machine. Restarting the app fixed it, which is a support
    /// call for a button whose whole purpose is not to need one.
    test('and the wizard it reopens has forgotten that business', () async {
      const claimed = SavedTerminalConfig(
        deployment: DeploymentConfig(
          mode: DeploymentMode.offline,
          databaseHost: '192.168.1.20',
          tenantSlug: 'first-business',
        ),
        terminal: TerminalProfile(
          branchId: 13,
          branchName: 'Maadi',
          terminalName: 'Counter 1',
          terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
          businessId: 7,
          branchCode: 'MAA',
          provisioned: true,
        ),
        languageCode: 'ar',
      );

      final container = ProviderContainer(
        overrides: [
          // Not the English override: the draft keeping Arabic across a reset
          // is one of the things this test is for.
          ...fakeRepositoryOverrides(english: false),
          terminalBootProvider.overrideWithValue(
            const TerminalBoot(config: claimed, hasDatabaseCredential: true),
          ),
          terminalConfigStoreProvider.overrideWithValue(
            InMemoryTerminalConfigStore()..saved = claimed,
          ),
          licenceServiceProvider.overrideWithValue(FakeLicenceService()),
        ],
      );
      addTearDown(container.dispose);

      // The terminal as it stands: one business's, and claimed.
      expect(
        container.read(setupProvider).deployment.tenantSlug,
        'first-business',
      );
      expect(container.read(setupProvider).claimed, isTrue);

      await container.read(terminalResetProvider).run();

      final draft = container.read(setupProvider);
      expect(draft.deployment.tenantSlug, isNull);
      expect(draft.claimed, isFalse);
      expect(draft.terminalName, isEmpty);
      expect(draft.branchLabel, isNull);
      // Kept, because the licence is pinned to it and the config file that
      // held it is gone — the profile is the only place that still knows.
      expect(
        draft.terminalId,
        'e6c0f0a2-0000-4000-8000-000000000001',
        reason: 'a new id here unpins the licence this till already holds',
      );
      // Kept for the same class of reason: the screen is in Arabic, and
      // completing the wizard writes whatever this says.
      expect(draft.locale, 'ar');

      // And the point of all of it: another business's licence installs.
      await container
          .read(setupProvider.notifier)
          .activateLicence(fileContents: _licenceFor('second-business'));

      final activated = container.read(setupProvider);
      expect(activated.error, isNull, reason: activated.error ?? '');
      expect(activated.claims?.tenantSlug, 'second-business');
      expect(activated.deployment.tenantSlug, 'second-business');
    });
  });
  group('a claim made on an earlier run', () {
    const terminalId = '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10';

    /// The first launch: a licence activated, a code claimed, and the process
    /// gone before "Open the till". The store handed in is all that survives.
    Future<void> firstRun(InMemorySetupProgressStore progress) async {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          setupProgressStoreProvider.overrideWithValue(progress),
        ],
      );
      final controller = container.read(setupProvider.notifier);
      controller.setLicenceKey('DEV-KEY');
      await controller.activateLicence();
      controller.setPairingCode(FakeProvisioningRepository.demoCode);
      await controller.claimTerminal();
      expect(container.read(setupProvider).claimed, isTrue);
      container.dispose();
    }

    /// The second launch, over the same store. Reading the draft is what
    /// builds it, and building it is what schedules the restore.
    Future<ProviderContainer> secondRun(
      InMemorySetupProgressStore progress,
    ) async {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          setupProgressStoreProvider.overrideWithValue(progress),
        ],
      );
      addTearDown(container.dispose);
      container.read(setupProvider);
      await pumpEventQueue();
      return container;
    }

    test('is written the moment the code is spent', () async {
      final progress = InMemorySetupProgressStore();
      await firstRun(progress);

      final written = progress.saved;
      expect(written, isNotNull);
      expect(written!.terminalId, terminalId);
      expect(written.terminalName, 'Counter 1');
      expect(written.branchLabel, 'Maadi');
      expect(written.deployment.mode, DeploymentMode.cloud);
      // The licence rides along, so the till it completes into is licensed.
      // No password does — the record has no field for one, and its JSON
      // is what a support engineer may be sent.
      expect(written.licence, isNotNull);
      expect(jsonEncode(written.toJson()), isNot(contains('password')));
    });

    test('carries the wizard on at the connecting step', () async {
      final progress = InMemorySetupProgressStore();
      await firstRun(progress);

      // A fresh process knows nothing until the restore lands.
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          setupProgressStoreProvider.overrideWithValue(progress),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(setupProvider).step, SetupStep.licence);
      await pumpEventQueue();

      final draft = container.read(setupProvider);
      // Past the licence, the mode and the code — the three questions this
      // machine already answered — and onto the screen that asks nothing.
      expect(draft.step, SetupStep.connecting);
      expect(draft.claimed, isTrue);
      expect(draft.terminalId, terminalId);
      expect(draft.terminalName, 'Counter 1');
      expect(draft.branchId, 13);
      expect(draft.branchCode, 'MAADI');
      expect(draft.deployment.mode, DeploymentMode.cloud);
      // Judged again on the way in, and held for complete() to write.
      expect(draft.entitlement, isNotNull);
      expect(draft.licenceFile, isNotNull);
      // Flagged, so the connecting screen can say so in its report.
      expect(draft.resumed, isTrue);
      expect(draft.error, isNull);
    });

    test('is forgotten once the till opens', () async {
      final progress = InMemorySetupProgressStore();
      await firstRun(progress);
      final container = await secondRun(progress);
      final controller = container.read(setupProvider.notifier);

      // The connecting pane is not pumped here; stand in for what it does.
      controller.setDatabasePassword('s3cret');
      controller.state = container.read(setupProvider).copyWith(
        provisioned: true,
      );
      expect(await controller.complete(), isNull);

      expect(
        progress.saved,
        isNull,
        reason:
            'a record that outlives the config would resume the wrong '
            'install after the next reset',
      );
    });

    test('and by a reset', () async {
      final progress = InMemorySetupProgressStore();
      await firstRun(progress);
      final container = await secondRun(progress);

      await container.read(terminalResetProvider).run();

      expect(progress.saved, isNull);
    });
  });

  // P0-4. The offline twin of the group above, for a seat rather than a code:
  // a registration on the branch database spends one of the licence's
  // `max_terminals`, and a wizard that forgot it had registered spent another.
  group('an offline registration made on an earlier run', () {
    const issued = '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10';

    ProviderContainer launch(
      InMemorySetupProgressStore progress,
      FakeProvisioningRepository provisioning, {
      InMemoryTerminalConfigStore? config,
    }) {
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(appMode: DeploymentMode.offline),
          setupProgressStoreProvider.overrideWithValue(progress),
          provisioningRepositoryProvider.overrideWithValue(provisioning),
          if (config != null)
            terminalConfigStoreProvider.overrideWithValue(config),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// Licensed, offline, database built, first administrator typed — the
    /// state the terminal step's Register button is pressed from.
    Future<SetupController> readyToRegister(ProviderContainer container) async {
      final controller = container.read(setupProvider.notifier);
      controller.setLicenceKey('DEV-KEY');
      await controller.activateLicence();
      controller.setDatabaseHost('192.168.1.20');
      controller.setDatabasePassword('s3cret');
      controller.setOwnerName('Amer');
      controller.setOwnerUsername('amer');
      controller.setOwnerPin('4321');
      controller.setBranch(13, 'Maadi');
      controller.setTerminalName('Counter 1');
      // `bootstrapDatabase` needs a real PostgreSQL; what it leaves behind is
      // this flag, and the registration is what is under test.
      controller.state = container
          .read(setupProvider)
          .copyWith(bootstrapped: true);
      expect(
        container.read(setupProvider).deployment.mode,
        DeploymentMode.offline,
      );
      return controller;
    }

    test('is written before the registration and again after it', () async {
      final progress = InMemorySetupProgressStore();
      final provisioning = FakeProvisioningRepository();
      final container = launch(progress, provisioning);
      final controller = await readyToRegister(container);
      final installationId = container.read(setupProvider).installationId;

      await controller.registerTerminal();

      expect(container.read(setupProvider).claimed, isTrue);
      // The install id went to the database, so the row it made is keyed.
      expect(provisioning.registrations, [installationId]);
      // Once with the id alone, before the row existed; once with the row.
      expect(progress.writes, 2);
      final written = progress.saved!;
      expect(written.claimed, isTrue);
      expect(written.installationId, installationId);
      expect(written.terminalId, issued);
      expect(written.bootstrapped, isTrue);
      expect(written.deployment.mode, DeploymentMode.offline);
      // Same rule as the cloud record: no password has a field to land in.
      final json = jsonEncode(written.toJson());
      expect(json, isNot(contains('s3cret')));
      expect(json, isNot(contains('4321')));
    });

    test('resumes with the terminal it registered, and registers '
        'nothing', () async {
      final progress = InMemorySetupProgressStore();
      final first = FakeProvisioningRepository();
      final firstRun = launch(progress, first);
      await (await readyToRegister(firstRun)).registerTerminal();
      final installationId = firstRun.read(setupProvider).installationId;

      // A fresh process: a fresh installation id was minted in memory, and
      // nothing has been typed.
      final second = FakeProvisioningRepository();
      final config = InMemoryTerminalConfigStore();
      final container = launch(progress, second, config: config);
      expect(container.read(setupProvider).step, SetupStep.licence);
      await pumpEventQueue();

      final draft = container.read(setupProvider);
      // On the screen whose passwords are in no file, everything else filled.
      expect(draft.step, SetupStep.deployment);
      expect(draft.claimed, isTrue);
      expect(draft.terminalId, issued);
      expect(draft.installationId, installationId);
      // The licence fingerprints the profile's id, not the draft's.
      expect(
        container.read(terminalProfileProvider).installationId,
        installationId,
      );
      expect(draft.bootstrapped, isTrue);
      expect(draft.branchId, 13);
      expect(draft.deployment.mode, DeploymentMode.offline);
      expect(draft.entitlement, isNotNull);
      expect(draft.resumed, isTrue);
      // The terminal step lets a claimed draft through, and its Register
      // button is dead on one — so the walk to the end spends no seat.
      expect(draft.copyWith(step: SetupStep.terminal).canAdvance, isTrue);

      final controller = container.read(setupProvider.notifier);
      controller.setDatabasePassword('s3cret');
      expect(await controller.complete(), isNull);

      expect(second.registrations, isEmpty);
      expect(config.saved!.terminal.terminalId, issued);
      expect(config.saved!.terminal.installationId, installationId);
      expect(progress.saved, isNull);
    });

    test('a registration that never came back gives up only its '
        'identity', () async {
      // Killed after the first record and before the second: the row may or
      // may not exist, so nothing may claim it does — but the id it would be
      // keyed on must be the one the next attempt sends.
      final progress = InMemorySetupProgressStore()
        ..saved = const SetupProgress(
          deployment: DeploymentConfig(
            mode: DeploymentMode.offline,
            databaseHost: '192.168.1.20',
          ),
          terminalId: 'guessed-on-this-device',
          terminalName: 'Counter 1',
          installationId: 'install-from-the-first-run',
          claimed: false,
        );
      final provisioning = FakeProvisioningRepository();
      final container = launch(progress, provisioning);
      container.read(setupProvider);
      await pumpEventQueue();

      final draft = container.read(setupProvider);
      expect(draft.step, SetupStep.licence);
      expect(draft.claimed, isFalse);
      expect(draft.terminalId, isNot('guessed-on-this-device'));
      expect(draft.installationId, 'install-from-the-first-run');
      expect(
        container.read(terminalProfileProvider).installationId,
        'install-from-the-first-run',
      );

      await (await readyToRegister(container)).registerTerminal();
      expect(provisioning.registrations, ['install-from-the-first-run']);
    });
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

    test('can be replaced by one for a different business', () async {
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
          .activateLicence(fileContents: _licenceFor('another-business'));

      final draft = container.read(setupProvider);
      expect(draft.error, isNull, reason: draft.error ?? '');
      expect(draft.claims?.tenantSlug, 'another-business');
      expect(draft.deployment.tenantSlug, 'another-business');
    });

    test('but a claimed terminal still refuses the wrong business', () async {
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

      // Refused in the verdict, which the pane's status card draws. The
      // footer's error bar is silent on purpose: it used to repeat the card's
      // sentence, and the same words twice on one screen read as two faults.
      final draft = container.read(setupProvider);
      expect(draft.entitlement?.state, LicenseState.tenantMismatch);
      expect(draft.entitlement?.notice, isA<LicenceTenantMismatch>());
      expect(draft.entitlement?.canSell, isFalse);
      expect(draft.error, isNull, reason: draft.error ?? '');
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
