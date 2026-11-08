import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/platform_endpoint.dart';
import 'package:shared_module/core/config/printer_config.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/config/installer_credentials.dart';
import 'package:shared_module/data/config/setup_progress_store.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';
import 'package:shared_module/features/setup/application/setup_controller.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';
import 'package:shared_module/features/setup/presentation/setup_wizard.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:shared_module/data/sql/embedded_datastore.dart';

/// The cloud main device asks nothing the cloud already knows.
///
/// Owner decision, 2026-09-15: *"cloud setup should get everything from cloud,
/// no need for asking anything."* Eleven screens became four, and the claim
/// this file makes is the strict one — not that the short path works, but that
/// it lands the terminal in **exactly the state the long one did**. A wizard
/// that stops asking and quietly writes something different is worse than a
/// wizard that asks.
///
/// The offline and child paths are not touched here; they keep their own
/// suites, and `licence_decides_mode_test.dart` pins the offline shape.

/// A licence for `islanded`, covering [modes].
///
/// `FakeLicenceService` is the development issuer: it skips the signature and
/// evaluates policy in full, which is what this file is about.
LicenseFile _licence(Set<DeploymentMode> modes) {
  final now = DateTime.now();
  final claims = LicenseClaims(
    licenseId: 'LIC-CLOUD-0001',
    tenantSlug: 'islanded',
    tenantName: 'The Islanded Cafe',
    issuedAt: now.subtract(const Duration(days: 1)),
    expiresAt: now.add(const Duration(days: 365)),
    maxTerminals: 2,
    features: const {'pos'},
    modes: modes,
  );
  return LicenseFile(
    payloadB64: base64Url.encode(utf8.encode(jsonEncode(claims.toJson()))),
    signatureB64: base64Url.encode(List<int>.filled(64, 0)),
    keyId: 'dev',
  );
}

/// A machine the Windows installer prepared, as a test double.
///
/// The real source reads `%ProgramData%\XOrder POS\install-credentials.json`,
/// which a developer's Mac does not have — and a test that depended on the
/// machine it runs on would pass in CI and fail on a laptop, or the reverse.
class _InstalledByTheInstaller implements InstallerCredentialsSource {
  const _InstalledByTheInstaller();

  static const credentials = InstallerCredentials(
    port: 5433,
    database: 'xorder_pos',
    adminUser: 'pos_admin',
    adminPassword: 'Adm1nGeneratedByTheInstaller',
    tillUser: 'pos_till',
    tillPassword: 'T1llGeneratedByTheInstaller',
  );

  @override
  Future<InstallerCredentials?> read() async => credentials;
}

/// A machine nobody's installer ever ran on — a Mac, in practice.
/// A till whose data is its own file: counts how often it was prepared.
class _RecordingFile implements EmbeddedDatastore {
  int prepared = 0;

  @override
  Future<EmbeddedDatastoreReport> prepare(DeploymentConfig config) async {
    prepared++;
    return EmbeddedDatastoreReport(created: prepared == 1, migrations: 64);
  }
}

class _NoInstaller implements InstallerCredentialsSource {
  const _NoInstaller();

  @override
  Future<InstallerCredentials?> read() async => null;
}

/// PostgreSQL, without PostgreSQL. Records what it was asked to build so the
/// test can assert the till's own role was the one granted.
class _RecordingDatabaseBuilder {
  _RecordingDatabaseBuilder({this.refusal});

  /// What the database says instead of building, when the test is about a
  /// failure. Typed as `Object` so both kinds can be asked for: a
  /// `PosDbException`, which the wizard has to translate rather than print,
  /// and a `TillRoleRefused`, which is not a driver error at all.
  final Object? refusal;

  DeploymentConfig? config;
  String? adminPassword;

  /// The till's own, which the builder needs as well: on a machine with no
  /// installer the `pos_till` role does not exist either, and the build is
  /// what creates it.
  String? tillPassword;
  int calls = 0;

  Future<DatabaseBuildReport> call(
    DeploymentConfig config,
    String adminPassword,
    String tillPassword,
  ) async {
    this.config = config;
    this.adminPassword = adminPassword;
    this.tillPassword = tillPassword;
    calls++;
    if (refusal case final refusal?) throw refusal;
    return const DatabaseBuildReport(created: true, migrations: 42);
  }
}

/// Reason codes and order types, recorded instead of written.
class _RecordingDefaultsSeeder {
  int calls = 0;
  int? businessId;

  Future<void> call(
    DeploymentConfig config,
    String adminPassword,
    int businessId,
  ) async {
    calls++;
    this.businessId = businessId;
  }
}

/// Exactly [count] printers, answering at once.
///
/// `FakeHardwarePorts` finds two, which is a different and equally interesting
/// case — so both are asked for by name rather than inherited from the harness.
class _PrintersFound implements HardwarePorts {
  _PrintersFound(this.count);

  final int count;
  int prints = 0;

  @override
  Future<List<DiscoveredPrinter>> discoverPrinters() async => [
    for (var i = 0; i < count; i++)
      DiscoveredPrinter(name: 'EPSON TM-T20III #${i + 1}', transport: 'usb'),
  ];

  @override
  Future<bool> testPrint(String printerName) async {
    prints++;
    return true;
  }

  @override
  Future<bool> sendJob({
    required String printerName,
    required List<int> bytes,
  }) async => true;
}

/// [_licence] as the bootstrap bundle carries it: a JSON object.
Map<String, Object?> _bundled(Set<DeploymentMode> modes) =>
    (jsonDecode(_licence(modes).serialize()) as Map).cast<String, Object?>();

/// Await [work] inside a widget test. The fakes behind it wait on real
/// delays, which only elapse when the test clock is pumped — awaiting it bare
/// would wait for ever.
Future<void> settle(WidgetTester tester, Future<void> work) async {
  var done = false;
  unawaited(work.whenComplete(() => done = true));
  for (var i = 0; !done && i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await work;
}

void main() {
  /// Pumps the wizard and hands back the container and the config store.
  Future<(ProviderContainer, InMemoryTerminalConfigStore)> open(
    WidgetTester tester, {
    InstallerCredentialsSource installer = const _InstalledByTheInstaller(),
    required _RecordingDatabaseBuilder builder,
    required HardwarePorts printers,
    InMemorySetupProgressStore? progress,
    _RecordingDefaultsSeeder? defaults,
    EmbeddedDatastore? embedded,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = InMemoryTerminalConfigStore();
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        terminalConfigStoreProvider.overrideWithValue(store),
        installerCredentialsProvider.overrideWithValue(installer),
        databaseBuilderProvider.overrideWithValue(builder.call),
        hardwarePortsProvider.overrideWithValue(printers),
        if (progress != null)
          setupProgressStoreProvider.overrideWithValue(progress),
        if (defaults != null)
          cloudDefaultsSeederProvider.overrideWithValue(defaults.call),
        if (embedded != null)
          embeddedDatastoreProvider.overrideWithValue(embedded),
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
    return (container, store);
  }

  /// Answer the screen the wizard is on the way the owner does, and go on.
  ///
  /// The sign-in, the branch and the till are the questions on this path
  /// (pos-cloud-sign-in-setup). [modes] is the licence the claim's bundle
  /// carries — handed to the wizard here the way the cloud app's claim hook
  /// hands it — or none at all when null.
  Future<void> answer(
    WidgetTester tester,
    ProviderContainer container, {
    Set<DeploymentMode>? modes,
  }) async {
    final controller = container.read(setupProvider.notifier);
    switch (container.read(setupProvider).step) {
      case SetupStep.account:
        controller.setTenantSlug('islanded');
        controller.setOperatorUsername(FakeProvisioningRepository.demoUsername);
        controller.setOperatorPassword(FakeProvisioningRepository.demoPassword);
        await settle(tester, controller.connectTenant());
      case SetupStep.branch:
        controller.setBranch(1, 'Maadi');
      case SetupStep.terminal:
        if (modes != null) {
          await settle(
            tester,
            controller.receiveBundleLicence(_bundled(modes)),
          );
        }
        await settle(tester, controller.registerTerminal());
      default:
        break;
    }
    await tester.pumpAndSettle();
  }

  /// Walk the wizard the way an owner does — sign in, the branch, the till,
  /// then Continue until it opens — and record every screen that was shown.
  ///
  /// Recording the screens rather than reading `visibleSteps` is the point: a
  /// step can be listed and never reached, and the claim here is about what a
  /// person is made to look at.
  Future<List<SetupStep>> walk(
    WidgetTester tester,
    ProviderContainer container, {
    required Set<DeploymentMode> modes,
  }) async {
    final seen = <SetupStep>[container.read(setupProvider).step];

    while (!container.read(setupProvider).isLastStep) {
      final at = container.read(setupProvider).step;
      await answer(tester, container, modes: modes);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final now = container.read(setupProvider).step;
      if (now == at) {
        fail(
          'the wizard would not leave ${at.name}: '
          '${container.read(setupProvider).error}',
        );
      }
      seen.add(now);
    }
    return seen;
  }

  group('a restart between the claim and "Open the till"', () {
    /// What the first run left behind: the claim, and the licence the bundle
    /// embedded. No pairing code — it is spent, and nothing keeps it.
    SetupProgress claimed() => SetupProgress(
      deployment: DeploymentConfig(
        mode: DeploymentMode.cloud,
        tenantSlug: 'islanded',
        baseUrl: PlatformEndpoint.base,
      ),
      terminalId: '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10',
      terminalName: 'Counter 1',
      locale: 'en',
      branchId: 13,
      branchLabel: 'Maadi',
      businessId: 1,
      branchCode: 'MAADI',
      licence: _licence({DeploymentMode.cloud}).serialize(),
    );

    testWidgets('reopens on the connecting screen and builds unasked', (
      tester,
    ) async {
      final builder = _RecordingDatabaseBuilder();
      final progress = InMemorySetupProgressStore()..saved = claimed();
      final (container, _) = await open(
        tester,
        builder: builder,
        printers: _PrintersFound(1),
        progress: progress,
      );

      final draft = container.read(setupProvider);
      // Past the three questions this machine already answered, and onto the
      // screen whose pane runs provisioning on its own.
      expect(draft.step, SetupStep.connecting);
      expect(draft.claimed, isTrue);
      expect(draft.provisioned, isTrue);
      expect(builder.calls, 1);
      expect(draft.error, isNull);
      // Said on screen: a wizard that opens on its fourth screen with nothing
      // typed looks like a fault to whoever restarted it.
      expect(find.textContaining('carried on'), findsOneWidget);
      // And the code was not asked for.
      expect(find.text('Claim this terminal'), findsNothing);
    });

    testWidgets('is finished with once the till opens', (tester) async {
      final progress = InMemorySetupProgressStore()..saved = claimed();
      final (container, store) = await open(
        tester,
        builder: _RecordingDatabaseBuilder(),
        printers: _PrintersFound(1),
        progress: progress,
      );

      for (var i = 0; !container.read(setupProvider).isLastStep; i++) {
        // A step that will not advance fails here rather than hanging the run.
        if (i > 10) fail('stuck on ${container.read(setupProvider).step}');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Open the till'));
      await tester.pumpAndSettle();

      expect(store.saved, isNotNull, reason: 'the till is configured');
      expect(progress.saved, isNull, reason: 'and the claim record is spent');
    });
  });

  group("the till's own lists", () {
    testWidgets('are written the moment the code is spent, and seeded only '
        'once the bundle has landed', (tester) async {
      final defaults = _RecordingDefaultsSeeder();
      final progress = InMemorySetupProgressStore();
      final (container, _) = await open(
        tester,
        builder: _RecordingDatabaseBuilder(),
        printers: _PrintersFound(1),
        progress: progress,
        defaults: defaults,
      );

      await walk(tester, container, modes: {DeploymentMode.cloud});

      // The claim wrote its record before the wizard moved on.
      expect(progress.saved, isNotNull);
      expect(progress.saved!.terminalName, 'Counter 1');
      // This harness has no platform to fetch a bundle from, so there is no
      // business row to hang reasons on — and nothing tried. The seed's
      // failure is a notice, and the defaults wait for the retry that clears
      // it rather than failing a second time on the same missing row.
      expect(defaults.calls, 0);
    });
  });

  group('the screens a cloud main device is shown', () {
    testWidgets('a single-mode licence and one printer: five screens', (
      tester,
    ) async {
      final builder = _RecordingDatabaseBuilder();
      final (container, _) = await open(
        tester,
        builder: builder,
        printers: _PrintersFound(1),
      );

      final seen = await walk(tester, container, modes: {DeploymentMode.cloud});

      expect(seen, [
        SetupStep.account,
        SetupStep.branch,
        SetupStep.terminal,
        SetupStep.connecting,
        SetupStep.summary,
      ]);
    });

    testWidgets('two printers add the hardware screen, and only it', (
      tester,
    ) async {
      // Which of two printers prints the receipt is the one hardware question
      // nobody but the person standing at the till can answer.
      final builder = _RecordingDatabaseBuilder();
      final (container, _) = await open(
        tester,
        builder: builder,
        printers: _PrintersFound(2),
      );

      final seen = await walk(tester, container, modes: {DeploymentMode.cloud});

      expect(seen, [
        SetupStep.account,
        SetupStep.branch,
        SetupStep.terminal,
        SetupStep.connecting,
        SetupStep.hardware,
        SetupStep.summary,
      ]);
      // And nothing was chosen for the operator: two printers is a choice, so
      // the wizard leaves it open rather than picking the first.
      expect(container.read(setupProvider).printerName, isNull);
    });

    testWidgets('no printer at all is also a question', (tester) async {
      final builder = _RecordingDatabaseBuilder();
      final (container, _) = await open(
        tester,
        builder: builder,
        printers: _PrintersFound(0),
      );

      final seen = await walk(tester, container, modes: {DeploymentMode.cloud});

      expect(seen, contains(SetupStep.hardware));
    });
  });

  group('what the short path writes', () {
    testWidgets('is what the long path wrote for the same inputs', (
      tester,
    ) async {
      final builder = _RecordingDatabaseBuilder();
      final (container, store) = await open(
        tester,
        builder: builder,
        printers: _PrintersFound(1),
      );

      await walk(tester, container, modes: {DeploymentMode.cloud});
      await tester.tap(find.text('Open the till'));
      await tester.pumpAndSettle();

      final saved = store.saved!;

      // The terminal, exactly as the claim described it — the same fields
      // `setup_persistence_test.dart` asserts after the long walk.
      expect(saved.terminal.terminalName, 'Counter 1');
      expect(saved.terminal.branchId, 1);
      expect(saved.terminal.branchName, 'Maadi');
      expect(saved.terminal.branchCode, 'MAADI');
      expect(saved.terminal.businessId, 1);
      expect(saved.terminal.provisioned, isTrue);
      expect(saved.setupComplete, isTrue);

      // The deployment: the licence's tenant, the build's platform, and the
      // database the installer built — none of it typed.
      expect(saved.deployment.mode, DeploymentMode.cloud);
      expect(saved.deployment.tenantSlug, 'islanded');
      expect(saved.deployment.baseUrl, PlatformEndpoint.base);
      expect(saved.deployment.databaseHost, DeploymentConfig.localhost);
      expect(saved.deployment.databaseName, 'xorder_pos');
      expect(saved.deployment.databasePort, 5433);
      expect(saved.deployment.databaseUser, 'pos_till');
      expect(saved.deployment.adminDatabaseUser, 'pos_admin');
      expect(saved.deployment.syncPolicy, SyncPolicy.automatic);

      // The printer, detected. 80mm because that is the roll every business
      // this ships to runs, and a receipt built for 576 dots on a 58mm head
      // loses its right-hand column rather than scaling.
      expect(saved.printer.name, 'EPSON TM-T20III #1');
      expect(saved.printer.paperWidthDots, PrinterConfig.width80mm);

      // A password in device config is a password that ends up in a support
      // email — the long path's rule, and the short one does not relax it.
      expect(
        saved.deployment.toJson().values,
        isNot(contains(_InstalledByTheInstaller.credentials.tillPassword)),
      );
      expect(
        await container.read(posDbCredentialsProvider).password(),
        _InstalledByTheInstaller.credentials.tillPassword,
      );
      // And the administrator's, so Admin Mode is a username and a PIN rather
      // than a generated password nobody was ever told.
      expect(
        await container.read(adminDbSecretStoreProvider).read(),
        _InstalledByTheInstaller.credentials.adminPassword,
      );
    });

    testWidgets('builds the database as the administrator, grants the till', (
      tester,
    ) async {
      final builder = _RecordingDatabaseBuilder();
      final (container, _) = await open(
        tester,
        builder: builder,
        printers: _PrintersFound(1),
      );

      await walk(tester, container, modes: {DeploymentMode.cloud});

      expect(
        builder.adminPassword,
        _InstalledByTheInstaller.credentials.adminPassword,
        reason: 'DDL is never the till credential',
      );
      expect(builder.config!.databaseName, 'xorder_pos');
      expect(builder.config!.databasePort, 5433);
      expect(builder.config!.databaseUser, 'pos_till');
    });

    testWidgets(
      'keeps the test print, which the hardware screen used to hold',
      (tester) async {
        final printers = _PrintersFound(1);
        final builder = _RecordingDatabaseBuilder();
        final (container, _) = await open(
          tester,
          builder: builder,
          printers: printers,
        );

        await walk(tester, container, modes: {DeploymentMode.cloud});

        // Somebody has to be able to put paper through the thing before the
        // business opens, and with the hardware screen gone this is the last
        // place they can.
        await tester.tap(find.text('Test print'));
        await tester.pumpAndSettle();
        expect(printers.prints, 1);
      },
    );
  });

  group('a machine the installer never ran on', () {
    const en = EnStrings();

    /// Sign-in, branch, till, Continue — as far as the connecting step, which
    /// is where this machine's missing credentials file strands it.
    Future<SetupController> upToTheDatabase(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      for (var i = 0; i < 3; i++) {
        await answer(tester, container, modes: {DeploymentMode.cloud});
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      return container.read(setupProvider.notifier);
    }

    testWidgets('asks for the database rather than guessing a password', (
      tester,
    ) async {
      // macOS has no installer, so there is no credentials file and no way to
      // know a password nobody typed. This is the one fallback on the path.
      final builder = _RecordingDatabaseBuilder();
      final (container, _) = await open(
        tester,
        installer: const _NoInstaller(),
        builder: builder,
        printers: _PrintersFound(1),
      );

      final controller = await upToTheDatabase(tester, container);

      expect(container.read(setupProvider).step, SetupStep.connecting);
      expect(container.read(setupProvider).needsDatabase, isTrue);
      expect(find.text('NO INSTALLED DATABASE FOUND'), findsOneWidget);
      // Prefilled: the business's own name for its database, and the
      // till account every wizard-built install shares.
      expect(
        container.read(setupProvider).deployment.databaseName,
        'islanded_db',
      );
      expect(container.read(setupProvider).deployment.databaseUser, 'pos_till');
      // And it cannot be walked past: the till has nowhere to write a sale.
      expect(container.read(setupProvider).canAdvance, isFalse);

      // The administrator half, which this screen asked for nothing of until
      // 2026-09-16 — and then ran the seeder against a database nothing had
      // created.
      expect(find.text('ADMINISTRATOR ROLE'), findsOneWidget);
      expect(find.text('POS_ADMIN PASSWORD'), findsOneWidget);
      expect(
        container.read(setupProvider).deployment.adminDatabaseUser,
        'pos_admin',
      );

      // The till's password alone is not enough to BUILD anything, so the
      // button stays dead until the account that can is named as well.
      controller.setDatabasePassword('typed-by-hand');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this database'));
      await tester.pumpAndSettle();
      expect(builder.calls, 0);
      expect(container.read(setupProvider).provisioned, isFalse);

      controller.setAdminDatabasePassword('admin-typed-by-hand');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this database'));
      await tester.pumpAndSettle();

      // Built with what was typed, and granted to the till account beside it.
      expect(builder.adminPassword, 'admin-typed-by-hand');
      // The till's password goes down as well, and not only into the secret
      // store: on a machine with no installer there is no `pos_till` role
      // either, and the build is the only thing that can create it — with
      // this, the password every sale after tonight connects with.
      expect(builder.tillPassword, 'typed-by-hand');
      // Built under the business's own name — no installer named it first.
      expect(builder.config!.databaseName, 'islanded_db');
      expect(builder.config!.databaseUser, 'pos_till');
      expect(builder.config!.adminDatabaseUser, 'pos_admin');
      expect(container.read(setupProvider).provisioned, isTrue);
      expect(container.read(setupProvider).canAdvance, isTrue);
      // And the step says so, rather than leaving the form that built it up.
      expect(find.text(en.tillIsReady), findsOneWidget);
    });

    testWidgets('keeps the administrator password for the back office', (
      tester,
    ) async {
      final builder = _RecordingDatabaseBuilder();
      final (container, store) = await open(
        tester,
        installer: const _NoInstaller(),
        builder: builder,
        printers: _PrintersFound(1),
      );

      final controller = await upToTheDatabase(tester, container);
      controller
        ..setDatabasePassword('typed-by-hand')
        ..setAdminDatabasePassword('admin-typed-by-hand');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this database'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open the till'));
      await tester.pumpAndSettle();

      // Exactly what the installer-credentials path does with the generated
      // one: Admin Mode's first sign-in is a username and a PIN either way.
      expect(
        await container.read(adminDbSecretStoreProvider).read(),
        'admin-typed-by-hand',
      );
      expect(
        await container.read(posDbCredentialsProvider).password(),
        'typed-by-hand',
      );
      // A password in device config is a password in a support email.
      expect(
        store.saved!.deployment.toJson().values,
        isNot(contains('admin-typed-by-hand')),
      );
    });

    testWidgets('a build that fails is a sentence, and stops the wizard', (
      tester,
    ) async {
      // The failure the walk of 16 Sep 2026 actually produced, with the
      // difference that it used to arrive from the SEEDER — the build was
      // skipped entirely — and reached the screen as the driver's own words.
      final builder = _RecordingDatabaseBuilder(
        refusal: PosDbException(
          PosDbFailure.missingDatabase,
          'Severity.fatal 3D000: database "xorder_pos" does not exist',
        ),
      );
      final (container, _) = await open(
        tester,
        installer: const _NoInstaller(),
        builder: builder,
        printers: _PrintersFound(1),
      );

      final controller = await upToTheDatabase(tester, container);
      controller
        ..setDatabasePassword('typed-by-hand')
        ..setAdminDatabasePassword('admin-typed-by-hand');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this database'));
      await tester.pumpAndSettle();

      expect(builder.calls, 1);
      expect(
        find.text(en.bootstrapDatabaseMissing('islanded_db', 'pos_admin')),
        findsOneWidget,
        reason: 'the operator reads a sentence, not a driver',
      );
      expect(find.textContaining('PosDbException'), findsNothing);
      expect(find.textContaining('3D000'), findsNothing);

      // And Continue stays dim. A till whose database was never built has
      // nowhere to write a sale, and finishing setup over it only moves the
      // failure to the first order of the morning.
      expect(container.read(setupProvider).provisioned, isFalse);
      expect(container.read(setupProvider).canAdvance, isFalse);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(container.read(setupProvider).step, SetupStep.connecting);
    });

    testWidgets('a role PostgreSQL never heard of is not a bad password', (
      tester,
    ) async {
      // The failure a Mac produced on 26 Sep 2026, verbatim, on this very
      // screen: `pos_admin` is what the Windows installer creates, and a
      // PostgreSQL installed by hand has no such role. It reached the error
      // bar as `Severity.fatal 28000: role "pos_admin" does not exist` —
      // English, and the driver's — because this path opens its own
      // connection and nothing translated it. Then, once it was translated,
      // it was classed as `auth` and read "PostgreSQL rejected «pos_admin»
      // and that password", which is a password nobody mistyped and a field
      // that will never fix it.
      final builder = _RecordingDatabaseBuilder(
        refusal: PosDbException(
          PosDbFailure.missingRole,
          'ServerException Severity.fatal 28000: role "pos_admin" does not '
          'exist',
        ),
      );
      final (container, _) = await open(
        tester,
        installer: const _NoInstaller(),
        builder: builder,
        printers: _PrintersFound(1),
      );

      final controller = await upToTheDatabase(tester, container);
      controller
        ..setDatabasePassword('typed-by-hand')
        ..setAdminDatabasePassword('admin-typed-by-hand');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this database'));
      await tester.pumpAndSettle();

      // The field above the error bar is the one that fixes this, and the
      // sentence sends the operator to it.
      expect(
        find.text(en.bootstrapAdminRoleMissing('pos_admin')),
        findsOneWidget,
      );
      expect(
        find.text(en.bootstrapAuthFailed('pos_admin')),
        findsNothing,
        reason: 'a role that does not exist has no password to get right',
      );
      expect(find.textContaining('28000'), findsNothing);
      expect(find.textContaining('Severity'), findsNothing);
      expect(container.read(setupProvider).provisioned, isFalse);
    });

    testWidgets('an administrator that cannot make the till account says so', (
      tester,
    ) async {
      // The other end of the same machine: an administrator role that exists
      // and may create databases, and a `pos_till` that does not exist and
      // cannot be created by it. `permissionDenied` would have read as a
      // refused GRANT on a table — the remedy for which is nothing like this
      // one.
      final builder = _RecordingDatabaseBuilder(
        refusal: const TillRoleRefused(role: 'pos_till', admin: 'pos_admin'),
      );
      final (container, _) = await open(
        tester,
        installer: const _NoInstaller(),
        builder: builder,
        printers: _PrintersFound(1),
      );

      final controller = await upToTheDatabase(tester, container);
      controller
        ..setDatabasePassword('typed-by-hand')
        ..setAdminDatabasePassword('admin-typed-by-hand');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this database'));
      await tester.pumpAndSettle();

      expect(
        find.text(en.tillRoleRefused('pos_till', 'pos_admin')),
        findsOneWidget,
      );
      expect(find.textContaining('TillRoleRefused'), findsNothing);
      expect(container.read(setupProvider).provisioned, isFalse);
      expect(container.read(setupProvider).canAdvance, isFalse);
    });
  });

  // pos-cloud-sign-in-setup, BR-5 / AC-5 / AC-6: the licence the platform
  // sent is checked at the connecting step, before the till is called ready.
  group('the licence the platform sent', () {
    /// Through sign-in, branch and till, with [modes] as the bundle's licence
    /// (none when null), and onto the connecting step.
    Future<ProviderContainer> toConnecting(
      WidgetTester tester, {
      Set<DeploymentMode>? modes,
    }) async {
      final (container, _) = await open(
        tester,
        builder: _RecordingDatabaseBuilder(),
        printers: _PrintersFound(1),
      );
      for (var i = 0; i < 3; i++) {
        await answer(tester, container, modes: modes);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      expect(container.read(setupProvider).step, SetupStep.connecting);
      return container;
    }

    testWidgets('none at all: the till is not called ready', (tester) async {
      final container = await toConnecting(tester);

      final draft = container.read(setupProvider);
      expect(draft.provisioned, isFalse);
      expect(draft.canAdvance, isFalse);
      expect(draft.error, const EnStrings().cloudLicenceMissing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('one for the offline app is refused, by name', (tester) async {
      final container = await toConnecting(
        tester,
        modes: {DeploymentMode.offline},
      );

      final draft = container.read(setupProvider);
      expect(draft.provisioned, isFalse);
      expect(draft.canAdvance, isFalse);
      expect(draft.error, isNotNull);
      expect(draft.error, isNot(const EnStrings().cloudLicenceMissing));
    });

    testWidgets('fixed on the dashboard, Try again finishes the step', (
      tester,
    ) async {
      final container = await toConnecting(tester);
      expect(container.read(setupProvider).provisioned, isFalse);

      // What the next bundle pull brings once XOrder has issued the licence;
      // this harness has no platform to pull it from, so it is handed over.
      await settle(
        tester,
        container
            .read(setupProvider.notifier)
            .receiveBundleLicence(_bundled({DeploymentMode.cloud})),
      );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      final draft = container.read(setupProvider);
      expect(draft.error, isNull);
      expect(draft.provisioned, isTrue);
      expect(draft.canAdvance, isTrue);
    });
  });

  // pos-cloud-single-till-sqlite, stage 5: the cloud app's data is a file of
  // its own, so the connecting step prepares it — no installer file, no
  // database fields, no PostgreSQL build.
  group('a till whose data is its own file', () {
    testWidgets('is never asked for a database, and nothing is built', (
      tester,
    ) async {
      final builder = _RecordingDatabaseBuilder();
      final file = _RecordingFile();
      final (container, _) = await open(
        tester,
        // As on a Mac with no installer: the PostgreSQL path would stop here.
        installer: const _NoInstaller(),
        builder: builder,
        printers: _PrintersFound(1),
        embedded: file,
      );
      for (var i = 0; i < 3; i++) {
        await answer(tester, container, modes: {DeploymentMode.cloud});
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }

      final draft = container.read(setupProvider);
      expect(draft.step, SetupStep.connecting);
      expect(draft.needsDatabase, isFalse);
      expect(find.text('Use this database'), findsNothing);
      expect(file.prepared, 1);
      expect(builder.calls, 0);
      expect(draft.provisioned, isTrue, reason: '${draft.error}');
      expect(
        draft.bootstrapReport,
        contains(const EnStrings().createdDataFile),
      );
    });
  });

  group('the till and the administrator are never confused', () {
    // Found live on 16 Sep 2026: a mistyped TILL password on the fallback
    // screen made the SEED step's own connection fail authentication — and
    // the notice named "pos_admin", because `_bootstrapFailure` always had.
    // `catalogueAuthFailed` is the seed step's own wording; the two must
    // never read the same, or the mix-up is back the moment somebody merges
    // a "helpful" refactor that reunifies them.
    test('name the account that actually failed, not the other one', () {
      const en = EnStrings();
      const ar = ArStrings();
      for (final s in [en, ar]) {
        expect(
          s.catalogueAuthFailed('pos_till'),
          isNot(s.bootstrapAuthFailed('pos_till')),
        );
        expect(s.catalogueAuthFailed('pos_till'), contains('pos_till'));
        expect(s.catalogueAuthFailed('pos_till'), isNot(contains('pos_admin')));
      }
    });
  });
}
