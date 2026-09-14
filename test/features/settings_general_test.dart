import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/backup/backup_service.dart';
import 'package:xorder_pos/data/backup/pg_tools.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/backup.dart';
import 'package:xorder_pos/domain/models/pos_settings.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_appearance_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_backup_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_receipt_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

const _strings = EnStrings();

const _tools = PgToolset(
  pgDump: '/usr/local/bin/pg_dump',
  pgRestore: '/usr/local/bin/pg_restore',
  version: '16.11',
);

class _Service extends Mock implements BackupService {}

/// Who the receipt says sold the food, recorded rather than stored.
class _Profiles implements ReceiptProfileRepository {
  _Profiles(this._stored);

  ReceiptProfile _stored;
  final saved = <ReceiptProfile>[];

  @override
  Future<ReceiptProfile> load() async => _stored;

  @override
  Future<AdminResult<ReceiptProfile>> save(
    ReceiptProfile profile, {
    required PosStaff by,
  }) async {
    saved.add(profile);
    _stored = profile.copyWith(revision: profile.revision + 1);
    return AdminResult.done(_stored);
  }
}

/// The restaurant's settings, as the writes that reached them.
class _Settings implements SettingsRepository {
  final saved = <(String, String, SettingScope)>[];

  @override
  Future<PosSettings> load() async => PosSettings.empty;

  @override
  Future<void> save({
    required String key,
    required String value,
    required SettingScope scope,
    required PosStaff by,
    String scopeId = '',
  }) async => saved.add((key, value, scope));
}

BackupRecord _record(BackupOutcome outcome, {int daysAgo = 0}) => BackupRecord(
  id: 1,
  takenAt: DateTime.now().subtract(Duration(days: daysAgo)),
  takenByName: 'Amer M.',
  trigger: BackupTrigger.dayClose,
  outcome: outcome,
  filePath: '/backups/xorder_pos-20260914-231407.dump',
  sizeBytes: 4404019,
  checksum: outcome == BackupOutcome.failed ? null : 'a' * 64,
  tablesFound: outcome == BackupOutcome.failed ? 0 : 44,
);

/// The back office through its door, landed on Settings › General.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  String username = 'amer',
  String pin = '4321',
  String language = 'en',
  Size size = const Size(1440, 2600),
  bool offline = false,
  FakeBackupRepository? backups,
  ReceiptProfileRepository? profiles,
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      if (offline) offlineTerminal(),
      receiptProfileRepositoryProvider.overrideWithValue(
        profiles ?? _Profiles(const ReceiptProfile(branchId: 1)),
      ),
      backupRepositoryProvider.overrideWithValue(
        backups ?? FakeBackupRepository(),
      ),
      // Whether PostgreSQL is installed on the box running the tests is not
      // what any of this is about.
      pgToolsProvider.overrideWith((ref) async => _tools),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: ManagementScreen(
          onClose: () {},
          onReconfigure: () {},
          initialPane: ManagementPane.receipt,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await enterAdminMode(tester, username: username, pin: pin);
  return container;
}

/// General's form scroll — the one the cards live at the bottom of.
Finder _generalScroll() => find
    .descendant(
      of: find.byType(ManagementReceiptPane),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200, scrollable: _generalScroll());
  await tester.pumpAndSettle();
}

/// Settings › General and the This terminal group (BO-8, plan 19 §2.6).
///
/// What General claims: it is the company form, saving as it always did; this
/// terminal's language and a three-way theme; and the backup pane's summary,
/// acting through the pane's own function and under its gate.
void main() {
  // The bundled faces, as `back_office_shell_test.dart` loads them: "the side
  // nav fits at 1100 px" is a claim about IBM Plex Sans Arabic, and the test
  // font draws every glyph a full em wide.
  setUpAll(() async {
    registerFallbackValue(const PosStaff(id: 0, name: ''));
    registerFallbackValue(BackupTrigger.manual);

    final ui = FontLoader(PosFonts.ui);
    for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      ui.addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-$face.ttf'));
    }
    await ui.load();
    final mono = FontLoader(PosFonts.mono);
    for (final face in ['Regular', 'Medium', 'SemiBold']) {
      mono.addFont(rootBundle.load('assets/fonts/IBMPlexMono-$face.ttf'));
    }
    await mono.load();
  });

  testWidgets('General is the company form, then appearance, then backup', (
    tester,
  ) async {
    await _open(tester);

    final form = find.byKey(const Key('receipt-profile-save'));
    final appearance = find.byKey(const Key('general-appearance'));
    final backup = find.byKey(const Key('general-backup'));
    await _reveal(tester, backup);

    expect(form, findsOneWidget);
    expect(appearance, findsOneWidget);
    expect(backup, findsOneWidget);
    // The mockup's order: the company first, what this machine shows next,
    // the copies last.
    expect(
      tester.getTopLeft(form).dy,
      lessThan(tester.getTopLeft(appearance).dy),
    );
    expect(
      tester.getTopLeft(appearance).dy,
      lessThan(tester.getTopLeft(backup).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the profile saves through General exactly as the pane does', (
    tester,
  ) async {
    // The pane under General is the one `receipt_profile_ui_test.dart` pins;
    // this is the same save, reached through the shell, with the cards under
    // it — which add no field and take no part in it.
    final profiles = _Profiles(
      const ReceiptProfile(branchId: 1, tradeName: 'Koshari'),
    );
    await _open(tester, profiles: profiles);

    final fields = find.descendant(
      of: find.byType(ManagementReceiptPane),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, 'Koshari Downtown');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('receipt-profile-save')));
    await tester.pumpAndSettle();

    expect(profiles.saved.single.tradeName, 'Koshari Downtown');
    expect(find.text(_strings.receiptProfileSaved), findsOneWidget);
  });

  group('appearance, for this terminal', () {
    testWidgets('the theme offers system, light and dark, and each is the '
        "Settings menu's own", (tester) async {
      final container = await _open(tester);
      await _reveal(tester, find.byKey(const Key('general-appearance')));

      for (final (key, label) in [
        ('system', _strings.themeSystem),
        ('light', _strings.themeLight),
        ('dark', _strings.themeDark),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key('appearance-theme-$key')),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: key,
        );
      }

      // `brightnessProvider`, the provider the menu toggles — so what is
      // chosen here is what the bar then offers to reverse.
      for (final (key, expected) in <(String, Brightness?)>[
        ('dark', Brightness.dark),
        ('light', Brightness.light),
        // And back to following the machine, which a toggle could not do.
        ('system', null),
      ]) {
        await tester.tap(find.byKey(Key('appearance-theme-$key')));
        await tester.pumpAndSettle();
        expect(container.read(brightnessProvider), expected, reason: key);
      }
    });

    testWidgets('the language is the one the Settings menu switches', (
      tester,
    ) async {
      final container = await _open(tester);
      await _reveal(tester, find.byKey(const Key('general-appearance')));

      // Each named in itself.
      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);

      await tester.tap(find.byKey(const Key('appearance-language-ar')));
      await tester.pumpAndSettle();
      expect(container.read(localeProvider).languageCode, 'ar');
    });
  });

  group('the backup card', () {
    testWidgets('"Back up now" does what the Backup pane\'s button does', (
      tester,
    ) async {
      final backups = FakeBackupRepository();
      final service = _Service();
      when(
        () => service.take(
          by: any(named: 'by'),
          trigger: any(named: 'trigger'),
        ),
      ).thenAnswer((_) async {
        final taken = _record(BackupOutcome.verified);
        backups.records.insert(0, taken);
        return AdminResult.done(taken);
      });

      await _open(
        tester,
        backups: backups,
        overrides: [backupServiceProvider.overrideWith((ref) async => service)],
      );
      final button = find.byKey(const Key('general-backup-now'));
      await _reveal(tester, button);
      expect(find.text(_strings.backupNoneYet), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      // A manual copy, by whoever is in Admin Mode — the pane's call.
      final call = verify(
        () => service.take(
          by: captureAny(named: 'by'),
          trigger: captureAny(named: 'trigger'),
        ),
      )..called(1);
      expect((call.captured[0] as PosStaff).username, 'amer');
      expect(call.captured[1], BackupTrigger.manual);

      // And the list is read again, so the card says what just happened.
      expect(
        tester.widget<Text>(find.byKey(const Key('general-backup-outcome'))).data,
        _strings.backupOutcomeVerified,
      );
      expect(find.text(_strings.backupNoneYet), findsNothing);
    });

    testWidgets('"Back up now" is absent without backup.manage', (
      tester,
    ) async {
      // A supervisor let into Admin Mode by role, holding no backup.manage.
      final settings = _Settings();
      await _open(
        tester,
        username: 'nour',
        pin: '2468',
        overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
      );
      await _reveal(tester, find.byKey(const Key('general-backup')));

      expect(find.byKey(const Key('general-backup-now')), findsNothing);
      expect(find.text(_strings.backupNowNeedsPermission), findsOneWidget);
      // Nor a door to a pane they do not have.
      expect(find.byKey(const Key('general-backup-open')), findsNothing);
      // The switch still says what happens at day close, and cannot change it.
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('general-backup-on-day-close')),
      );
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNull);
    });

    testWidgets('the day-close switch writes the policy the pane writes', (
      tester,
    ) async {
      final settings = _Settings();
      await _open(
        tester,
        overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
      );
      final toggle = find.byKey(const Key('general-backup-on-day-close'));
      await _reveal(tester, toggle);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(settings.saved, [
        (SettingKey.backupOnDayClose, 'false', SettingScope.restaurant),
      ]);
    });

    testWidgets('it shows the last copy, and its time', (tester) async {
      final record = _record(BackupOutcome.failed);
      await _open(
        tester,
        backups: FakeBackupRepository(
          records: [record, _record(BackupOutcome.verified, daysAgo: 1)],
        ),
      );
      await _reveal(tester, find.byKey(const Key('general-backup')));

      // The newest, whatever came of it: a failed copy last night is the news.
      expect(
        tester.widget<Text>(find.byKey(const Key('general-backup-outcome'))).data,
        _strings.backupOutcomeFailed,
      );
      expect(find.text(backupStamp(record.takenAt)), findsWidgets);
      expect(
        find.textContaining(_strings.backupLastVerified('').trim()),
        findsOneWidget,
      );
    });

    testWidgets('with no copy it says so once — the card, not the notice too', (
      tester,
    ) async {
      await _open(tester);
      await _reveal(tester, find.byKey(const Key('general-backup')));

      expect(find.text(_strings.backupNoneYet), findsOneWidget);
      expect(find.byKey(const Key('management-backup-notice')), findsNothing);

      // And the way to the whole pane.
      await tester.tap(find.byKey(const Key('general-backup-open')));
      await tester.pumpAndSettle();
      expect(find.byType(ManagementBackupPane), findsOneWidget);
    });
  });

  testWidgets('This terminal is a group of its own, holding Language & '
      'appearance', (tester) async {
    await _open(tester);

    final nav = find.byKey(const Key('back-office-settings-nav'));
    for (final text in [
      'ACCOUNT',
      'POINT OF SALE',
      'THIS TERMINAL',
      'Language & appearance',
    ]) {
      expect(
        find.descendant(of: nav, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
    // Last: the restaurant's settings first, this machine's after them.
    expect(
      tester.getTopLeft(find.text('THIS TERMINAL')).dy,
      greaterThan(tester.getTopLeft(find.text('POINT OF SALE')).dy),
    );

    await tester.tap(find.byKey(const Key('back-office-settings-appearance')));
    await tester.pumpAndSettle();
    expect(find.byType(ManagementAppearancePane), findsOneWidget);
    expect(find.byType(TerminalAppearanceCard), findsOneWidget);
  });

  group('at 1100 px', () {
    for (final language in ['en', 'ar']) {
      testWidgets('the side nav and General fit, in $language', (
        tester,
      ) async {
        await _open(
          tester,
          offline: true,
          language: language,
          size: const Size(PosSize.wideShellMin, 800),
        );
        expect(tester.takeException(), isNull);

        final nav = find.byKey(const Key('back-office-settings-nav'));
        expect(tester.getSize(nav).width, PosSize.settingsNav);
        // Every word in the nav whole: a row cut to an ellipsis is a row
        // somebody has to guess at. Read off the paragraphs, so a heading
        // counts as much as a row.
        final paragraphs = find.descendant(
          of: nav,
          matching: find.byType(RichText),
        );
        expect(paragraphs, findsAtLeastNWidgets(11), reason: '3 + 8');
        for (final element in paragraphs.evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: paragraph.text.toPlainText(),
          );
        }

        final ar = find.byKey(const Key('appearance-language-ar'));
        await _reveal(tester, find.byKey(const Key('general-backup')));
        await _reveal(tester, ar);
        expect(tester.takeException(), isNull);

        // Mirrored, not merely translated: English first on the start side,
        // which is the right in Arabic.
        final en = tester.getRect(
          find.byKey(const Key('appearance-language-en')),
        );
        final arRect = tester.getRect(ar);
        expect(
          language == 'ar' ? en.left > arRect.left : en.left < arRect.left,
          isTrue,
        );
        // And inside the pane, not under the nav.
        final navRect = tester.getRect(nav);
        final card = tester.getRect(find.byKey(const Key('general-appearance')));
        expect(
          language == 'ar'
              ? card.right <= navRect.left
              : card.left >= navRect.right,
          isTrue,
        );
      });
    }
  });
}
