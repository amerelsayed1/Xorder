import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/config/file_secret_store.dart';
import 'package:shared_module/data/config/secret_store.dart';
import 'package:shared_module/data/config/setup_progress_store.dart';
import 'package:shared_module/data/config/terminal_config_store.dart';
import 'package:shared_module/features/licensing/data/file_license_store.dart';
import 'package:shared_module/features/licensing/data/licence_check_store.dart';
import 'package:shared_module/features/setup/presentation/setup_wizard.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// A hard reset that really goes back to a blank till, on any operating system.
///
/// Found on the real till: the setup wizard opened on "Licensed" every time,
/// because the ordinary reset deliberately keeps the licence file (and the
/// terminal id it is pinned to), and there was nothing on the first screen to
/// start truly from scratch — the way out was deleting files by hand from a
/// folder the operator has to know the path of, and the path differs between
/// macOS and Windows.
///
/// These tests use REAL files in a temporary folder, through the same stores
/// the app uses. Every store resolves its folder through one function
/// (`getApplicationSupportDirectory`), so a test that points them all at a
/// temporary folder exercises exactly the wipe that runs on both systems.
void main() {
  const en = EnStrings();

  /// Every file the till keeps, plus a stranger the reset must leave alone.
  const kept = 'notes-from-the-installer.txt';
  final files = [
    TerminalConfigStoreFile.name,
    FileSecretStore.fileName,
    FileLicenseStore.fileName,
    FileLicenceCheckStore.fileName,
    FileSetupProgressStore.fileName,
  ];

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xorder_hard_reset');
    for (final name in [...files, kept]) {
      await File('${directory.path}/$name').writeAsString('{"x":1}');
    }
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  bool exists(String name) => File('${directory.path}/$name').existsSync();

  ProviderContainer container([List<Override> extra = const []]) {
    Future<Directory> here() async => directory;
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        ...extra,
        terminalConfigStoreProvider.overrideWithValue(
          FileTerminalConfigStore(directory: here),
        ),
        setupProgressStoreProvider.overrideWithValue(
          FileSetupProgressStore(directory: here),
        ),
        licenseStoreProvider.overrideWithValue(
          FileLicenseStore(directory: here),
        ),
        licenceCheckStoreProvider.overrideWithValue(
          FileLicenceCheckStore(directory: here),
        ),
        adminDbSecretStoreProvider.overrideWithValue(
          FileSecretStore(
            key: FileSecretStore.adminPasswordKey,
            directory: here,
          ),
        ),
        secretsFileProvider.overrideWithValue(
          FileSecretStore(
            key: FileSecretStore.databasePasswordKey,
            directory: here,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the ordinary reset', () {
    test('keeps the licence, as before', () async {
      await container().read(terminalResetProvider).run();

      expect(exists(FileLicenseStore.fileName), isTrue);
      expect(exists(FileLicenceCheckStore.fileName), isTrue);
      expect(exists(TerminalConfigStoreFile.name), isFalse);
    });
  });

  group('the hard reset', () {
    test('removes every file the till keeps, and nothing else', () async {
      await container().read(terminalResetProvider).runHard();

      for (final name in files) {
        expect(exists(name), isFalse, reason: '$name should be gone');
      }
      expect(exists(kept), isTrue, reason: 'it wipes files, not the folder');
    });

    test(
      'gives the till a new identity, so it is a new installation',
      () async {
        final c = container();
        final before = c.read(terminalProfileProvider);

        await c.read(terminalResetProvider).runHard();

        final after = c.read(terminalProfileProvider);
        expect(after.installationId, isNotNull);
        expect(after.installationId, isNot(before.installationId));
        expect(after.terminalId, isNull, reason: 'not registered any more');
      },
    );

    test(
      'is safe to run twice, and on a machine with nothing to remove',
      () async {
        final c = container();
        await c.read(terminalResetProvider).runHard();
        await c.read(terminalResetProvider).runHard();

        for (final name in files) {
          expect(exists(name), isFalse);
        }
      },
    );
  });

  group('the button in the setup wizard', () {
    // The wipe itself is proven above with real files. Here only the wiring:
    // the button, the warning, and what Cancel and Confirm do. (The secrets
    // store spawns a real `chmod`, which a widget test's fake clock cannot wait
    // on, so a recording double stands in for the reset.)
    late _RecordingReset reset;

    Future<void> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          terminalResetProvider.overrideWith(
            (ref) => reset = _RecordingReset(ref),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(terminalResetProvider); // builds the recording double now
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildPosTheme(),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: SetupWizard(onFinished: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is on the first screen, with a warning before anything goes', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byKey(const Key('hard-reset')), findsOneWidget);

      await tester.tap(find.byKey(const Key('hard-reset')));
      await tester.pumpAndSettle();

      expect(find.text(en.hardResetTitle), findsOneWidget);
      expect(find.text(en.hardResetBody), findsOneWidget);
      expect(reset.hardRuns, 0, reason: 'asking is not doing');
      // It says what it does NOT touch: the one thing an owner fears losing.
      expect(en.hardResetBody, contains('does not delete any database'));
    });

    testWidgets('Cancel changes nothing', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('hard-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();

      expect(reset.hardRuns, 0);
      expect(find.text(en.hardResetTitle), findsNothing, reason: 'closed');
    });

    testWidgets('confirming runs the hard reset, once', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('hard-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.hardResetConfirm));
      await tester.pumpAndSettle();

      expect(reset.hardRuns, 1);
      expect(find.text(en.hardResetTitle), findsNothing, reason: 'closed');
    });

    testWidgets('a reset that fails says so instead of failing silently', (
      tester,
    ) async {
      await pump(tester);
      reset.failWith = 'disk is read-only';

      await tester.tap(find.byKey(const Key('hard-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.hardResetConfirm));
      await tester.pumpAndSettle();

      expect(
        find.text(en.hardResetFailed('Bad state: disk is read-only')),
        findsOneWidget,
      );
    });
  });

  test('the hard reset is worded in both languages, and the two differ', () {
    const ar = ArStrings();
    for (final pair in [
      (en.hardResetButton, ar.hardResetButton),
      (en.hardResetTitle, ar.hardResetTitle),
      (en.hardResetBody, ar.hardResetBody),
      (en.hardResetConfirm, ar.hardResetConfirm),
      (en.hardResetFailed('x'), ar.hardResetFailed('x')),
    ]) {
      expect(pair.$1, isNotEmpty);
      expect(pair.$2, isNotEmpty);
      expect(pair.$2, isNot(pair.$1));
    }
  });

  // pos-cloud-single-till-sqlite: a cloud till's data file is encrypted with a
  // key in this same store. Wiping it with everything else would make every
  // sale in the file — unsent ones included — unreadable, and this reset
  // promises not to touch a sale.
  test('a hard reset puts back what guards the data, and nothing else',
      () async {
    final c = container([
      hardResetSurvivorsProvider.overrideWith(
        (ref) => [KeyedSecretStore(ref.watch(secretStoreProvider), 'data_key')],
      ),
    ]);
    final secrets = c.read(secretStoreProvider);
    await secrets.write('data_key', 'k' * 64);
    await secrets.write(FileSecretStore.deviceTokenKey, 'a-device-token');

    await c.read(terminalResetProvider).runHard();

    expect(await secrets.read('data_key'), 'k' * 64);
    expect(await secrets.read(FileSecretStore.deviceTokenKey), isNull);
  });
}

/// The config file's name, spelled where it is defined.
class TerminalConfigStoreFile {
  static const name = FileTerminalConfigStore.fileName;
}

/// Counts the hard resets instead of touching the disk.
class _RecordingReset extends TerminalReset {
  _RecordingReset(super.ref);

  int hardRuns = 0;
  String? failWith;

  @override
  Future<void> runHard() async {
    if (failWith case final reason?) throw StateError(reason);
    hardRuns++;
  }
}
