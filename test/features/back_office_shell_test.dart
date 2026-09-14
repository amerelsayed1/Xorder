import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/data/cloud/cloud_provisioning_repository.dart'
    show posAppVersion;
import 'package:xorder_pos/data/cloud/cloud_sync.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/option_group.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

// Everybody who could be standing in the back office, each holding what they
// hold through a ROLE where a real one would — `PosStaff.capabilities` is
// direct grants only — plus one who holds everything by direct grant, because
// that is a real shape too and the gate has to read both.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);
const _manager = PosStaff(
  id: 2,
  name: 'Mona F.',
  username: 'mona',
  role: PosRole(
    id: 2,
    code: SystemRoles.managerCode,
    nameEn: 'Manager',
    capabilities: {...SystemRoles.manager, PosCapability.adminEnter},
  ),
);
// Let into Admin Mode by the owner, and not into buying.
const _supervisor = PosStaff(
  id: 3,
  name: 'Nour S.',
  username: 'nour',
  role: FakeSessionRepository.trustedSupervisor,
);
const _granted = PosStaff(
  id: 4,
  name: 'Hady K.',
  username: 'hady',
  capabilities: {
    PosCapability.adminEnter,
    PosCapability.staffManage,
    PosCapability.purchaseManage,
  },
);
// The machine and its copies, and nothing of the business.
const _keeper = PosStaff(
  id: 5,
  name: 'Salma T.',
  username: 'salma',
  role: PosRole(
    id: 5,
    code: 'keeper',
    nameEn: 'Keeper',
    capabilities: {
      PosCapability.adminEnter,
      PosCapability.backupManage,
      PosCapability.terminalManage,
    },
  ),
);

const _fixtures = <String, PosStaff>{
  'owner': _owner,
  'manager': _manager,
  'supervisor': _supervisor,
  'direct grant': _granted,
  'keeper': _keeper,
};

/// The tabs whose content is a later slice. None of them holds a pane yet.
const _later = [
  BackOfficeTab.home,
  BackOfficeTab.sales,
  BackOfficeTab.reports,
  BackOfficeTab.finance,
];

class _Sync extends Mock implements CloudSync {}

/// An offline till's catalogue administrator that can be LOOKED at.
///
/// `offlineTerminal()` binds a bare mock, which is right for a test that only
/// asks whether this till authors — and wrong for one that opens every pane,
/// because Extras reads its library the moment it shows. That read is the only
/// one an authoring pane makes unprompted; everything else is a write behind a
/// button the walk never presses, and stays unanswered on purpose.
class _OfflineCatalogue extends Mock implements CatalogAdminRepository {
  _OfflineCatalogue() {
    when(optionLibrary).thenAnswer((_) async => const <LibraryGroup>[]);
  }
}

/// The panes on screen right now, read off the key the shell puts on each.
Set<ManagementPane> _showing(WidgetTester tester) => {
  for (final element in find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('back-office-pane-'),
      )
      .evaluate())
    ManagementPane.values.byName(
      (element.widget.key! as ValueKey<String>).value.substring(
        'back-office-pane-'.length,
      ),
    ),
};

/// The back office through its door, in [language], at [width].
Future<ProviderContainer> _open(
  WidgetTester tester, {
  ManagementPane? pane,
  bool offline = false,
  String language = 'en',
  double width = 1440,
  String username = 'amer',
  String pin = '4321',
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      if (offline)
        catalogAdminRepositoryProvider.overrideWithValue(_OfflineCatalogue()),
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
          initialPane: pane,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await enterAdminMode(tester, username: username, pin: pin);
  return container;
}

/// Every tab in the strip, and every row of every sub-nav and side nav under
/// it — what a person can reach by pointing, collected as they reach it.
Future<Set<ManagementPane>> _walk(WidgetTester tester) async {
  final seen = <ManagementPane>{..._showing(tester)};
  Future<void> tap(Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
    seen.addAll(_showing(tester));
  }

  for (final tab in BackOfficeTab.values) {
    final word = find.byKey(Key('back-office-tab-${tab.name}'));
    if (word.evaluate().isEmpty) continue;
    await tap(word);
    for (final pane in ManagementPane.values) {
      for (final row in [
        'back-office-subnav-${pane.name}',
        'back-office-settings-${pane.name}',
      ]) {
        if (find.byKey(Key(row)).evaluate().isNotEmpty) {
          await tap(find.byKey(Key(row)));
        }
      }
    }
  }
  return seen;
}

/// The back office's shell (BO-1): nine tabs, sub-nav, Settings' side nav, a
/// status bar and one bar menu — and not one pane more or less than before.
///
/// **Re-hosting, so the claim is equality.** Every pane a person could open
/// through the old flat bar they can open through the tabs, and nothing
/// else; `managementPanesFor` is the rule that was there before this slice
/// and is unchanged by it, so it is what the tabs are held to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled faces, not the test font. The test font draws every glyph a
  // full em wide, which is a measurement of nothing: "all tabs fit at 1100 px"
  // is a claim about IBM Plex Sans Arabic, in both of its scripts.
  setUpAll(() async {
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

  group('the tabs reach exactly what the back office reached before', () {
    for (final MapEntry(key: name, value: admin) in _fixtures.entries) {
      for (final authors in [true, false]) {
        final where = authors ? 'offline' : 'cloud';
        test('$name, $where', () {
          final before = managementPanesFor(
            admin: admin,
            authorsItsOwnCatalogue: authors,
          );
          final tabs = backOfficeTabsFor(
            admin: admin,
            authorsItsOwnCatalogue: authors,
          );
          final reachable = [for (final (_, own) in tabs) ...own];

          expect(reachable.toSet(), before.toSet());
          expect(reachable, hasLength(before.length), reason: 'no pane twice');

          for (final (tab, own) in tabs) {
            for (final pane in own) {
              expect(tabOf(pane), tab, reason: pane.name);
            }
            // A tab with no visible pane is absent — bar the two a cloud till
            // keeps as pointers to the platform.
            if (own.isEmpty) {
              expect(authors, isFalse, reason: tab.name);
              expect(tab, isIn(const [
                BackOfficeTab.inventory,
                BackOfficeTab.purchasing,
              ]));
            }
          }
          for (final tab in _later) {
            expect(
              [for (final (t, _) in tabs) t],
              isNot(contains(tab)),
              reason: '${tab.name} has no pane until its slice lands',
            );
          }

          // The bar reaches nothing the tabs do not.
          for (final line in managementBarFor(
            const EnStrings(),
            admin: admin,
            authorsItsOwnCatalogue: authors,
          )) {
            final to = line.open().pane!;
            if (line.pane == null) {
              expect(
                hiddenBecausePlatformAuthors(
                  to,
                  authorsItsOwnCatalogue: authors,
                ),
                isTrue,
                reason: line.label,
              );
            } else {
              expect(reachable, contains(to), reason: line.label);
            }
          }
        });
      }
    }
  });

  group('and by pointing, not only by the rule', () {
    for (final (name, username, pin) in [
      ('the owner', 'amer', '4321'),
      ('a supervisor who does not buy', 'nour', '2468'),
    ]) {
      for (final offline in [true, false]) {
        final where = offline ? 'offline' : 'cloud';
        testWidgets('$name, $where', (tester) async {
          final container = await _open(
            tester,
            offline: offline,
            username: username,
            pin: pin,
          );
          final admin = container.read(adminSessionProvider)!.staff;

          expect(
            await _walk(tester),
            managementPanesFor(
              admin: admin,
              authorsItsOwnCatalogue: offline,
            ).toSet(),
          );
          for (final tab in _later) {
            expect(
              find.byKey(Key('back-office-tab-${tab.name}')),
              findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('where the door lands', () {
    testWidgets('offline, the first tab: Menu', (tester) async {
      await _open(tester, offline: true);
      expect(_showing(tester), {ManagementPane.menu});
    });

    testWidgets('on cloud, the first tab that holds a pane — not a pointer', (
      tester,
    ) async {
      // Inventory is first on a cloud till and holds only a sentence;
      // greeting the owner with "this is not here" on every entry would make
      // the sentence a welcome.
      await _open(tester);
      expect(_showing(tester), {ManagementPane.activity});
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsNothing,
      );
    });
  });

  testWidgets('on a cloud till Menu is absent, and Inventory and Purchasing '
      'point at the platform', (tester) async {
    await _open(tester);

    expect(find.byKey(const Key('back-office-tab-menu')), findsNothing);
    for (final tab in [BackOfficeTab.inventory, BackOfficeTab.purchasing]) {
      await tester.tap(find.byKey(Key('back-office-tab-${tab.name}')));
      await tester.pumpAndSettle();
      expect(
        find.text(const EnStrings().purchasingComesFromPlatform),
        findsOneWidget,
        reason: tab.name,
      );
      expect(_showing(tester), isEmpty, reason: 'a sentence, not a pane');
    }
  });

  group('Settings', () {
    test('every Settings pane has a place in the side nav, and only those', () {
      for (final pane in ManagementPane.values) {
        expect(
          settingsPlaceOf(pane) != null,
          tabOf(pane) == BackOfficeTab.settings,
          reason: pane.name,
        );
      }
      final places = [
        for (final pane in ManagementPane.values) ?settingsPlaceOf(pane),
      ];
      expect(places.toSet(), hasLength(places.length), reason: 'no two alike');
    });

    test('Staff and Roles are Users and Roles under Account; no People tab',
        () {
      const s = EnStrings();
      for (final pane in [ManagementPane.staff, ManagementPane.roles]) {
        expect(tabOf(pane), BackOfficeTab.settings);
        expect(settingsPlaceOf(pane)!.$1, SettingsSection.account);
      }
      expect(managementPaneLabel(s, ManagementPane.staff).$1, s.settingsUsers);
      expect(
        [for (final tab in BackOfficeTab.values) tab.name],
        isNot(contains('people')),
      );
    });

    test('Money is Settings, Receipt is General, ETA is System', () {
      const s = EnStrings();
      for (final pane in [
        ManagementPane.taxes,
        ManagementPane.charges,
        ManagementPane.tenders,
        ManagementPane.orderTypes,
      ]) {
        expect(tabOf(pane), BackOfficeTab.settings, reason: pane.name);
        expect(settingsPlaceOf(pane)!.$1, SettingsSection.pointOfSale);
      }
      expect(tabOf(ManagementPane.receipt), BackOfficeTab.settings);
      expect(
        managementPaneLabel(s, ManagementPane.receipt).$1,
        s.settingsGeneral,
      );
      expect(tabOf(ManagementPane.eta), BackOfficeTab.system);
    });

    testWidgets('the side nav is grouped, and holds Users and Roles', (
      tester,
    ) async {
      await _open(tester, pane: ManagementPane.staff);

      final nav = find.byKey(const Key('back-office-settings-nav'));
      expect(tester.getSize(nav).width, PosSize.settingsNav);
      for (final text in ['ACCOUNT', 'POINT OF SALE', 'General', 'Users']) {
        expect(
          find.descendant(of: nav, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      await tester.tap(find.byKey(const Key('back-office-settings-roles')));
      await tester.pumpAndSettle();
      expect(_showing(tester), {ManagementPane.roles});
      expect(find.text('People'), findsNothing);
    });
  });

  group('at 1100 px', () {
    for (final language in ['en', 'ar']) {
      testWidgets('all nine tabs fit without scrolling, in $language', (
        tester,
      ) async {
        // All nine, though only five hold a pane today: the slice that adds
        // the ninth word should not be the one that finds out it does not fit.
        tester.view
          ..physicalSize = const Size(PosSize.wideShellMin, 800)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildPosTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  BackOfficeTabStrip(
                    tabs: BackOfficeTab.values,
                    // The widest state a word can be in: selected is bold.
                    selected: BackOfficeTab.purchasing,
                    onSelect: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // A Row that runs out of room reports an overflow, and this is where
        // that report would surface.
        expect(tester.takeException(), isNull);
        final rects = [
          for (final tab in BackOfficeTab.values)
            tester.getRect(find.byKey(Key('back-office-tab-${tab.name}'))),
        ];
        for (final (i, rect) in rects.indexed) {
          final name = BackOfficeTab.values[i].name;
          expect(rect.left, greaterThanOrEqualTo(0), reason: name);
          expect(
            rect.right,
            lessThanOrEqualTo(PosSize.wideShellMin),
            reason: name,
          );
        }
        // Home at the start edge: the right, in Arabic.
        final home = rects.first;
        final settings = rects.last;
        expect(
          language == 'ar'
              ? home.left > settings.left
              : home.left < settings.left,
          isTrue,
        );
      });

      testWidgets('the back office itself, in $language: tabs, side nav and '
          'direction', (tester) async {
        await _open(
          tester,
          offline: true,
          language: language,
          width: PosSize.wideShellMin,
        );
        expect(tester.takeException(), isNull);

        final admin = _owner;
        for (final (tab, _) in backOfficeTabsFor(
          admin: admin,
          authorsItsOwnCatalogue: true,
        )) {
          final rect = tester.getRect(
            find.byKey(Key('back-office-tab-${tab.name}')),
          );
          expect(rect.left, greaterThanOrEqualTo(0), reason: tab.name);
          expect(
            rect.right,
            lessThanOrEqualTo(PosSize.wideShellMin),
            reason: tab.name,
          );
        }

        await tester.tap(find.byKey(const Key('back-office-tab-settings')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // The side nav on the start side — the right, in Arabic.
        final nav = tester.getRect(
          find.byKey(const Key('back-office-settings-nav')),
        );
        expect(nav.width, PosSize.settingsNav);
        if (language == 'ar') {
          expect(nav.right, PosSize.wideShellMin);
        } else {
          expect(nav.left, 0);
        }
      });
    }
  });

  group('the status bar', () {
    testWidgets('an offline-style till: the branch server, the branch, the '
        'version and who is in', (tester) async {
      final container = await _open(tester);
      container
          .read(terminalProfileProvider.notifier)
          .apply(const TerminalProfile(branchName: 'Maadi'));
      await tester.pumpAndSettle();

      final bar = find.byKey(const Key('back-office-status-bar'));
      Finder inBar(Finder f) => find.descendant(of: bar, matching: f);

      // No platform to sync with, so the branch server — as the till shows.
      expect(inBar(find.byType(BranchServerPill)), findsOneWidget);
      expect(inBar(find.byType(SyncPill)), findsNothing);
      expect(
        inBar(find.text(const EnStrings().branchDatabaseReady)),
        findsOneWidget,
      );
      expect(inBar(find.text('Maadi')), findsOneWidget);
      expect(inBar(find.text('v$posAppVersion')), findsOneWidget);
      expect(inBar(find.text('Amer M. · Owner')), findsOneWidget);
    });

    testWidgets('a cloud till: the sync state instead', (tester) async {
      await _open(
        tester,
        overrides: [cloudSyncProvider.overrideWithValue(_Sync())],
      );

      final bar = find.byKey(const Key('back-office-status-bar'));
      expect(
        find.descendant(of: bar, matching: find.byType(SyncPill)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.byType(BranchServerPill)),
        findsNothing,
      );
    });

    testWidgets('in Arabic the role is Arabic and the version stays a code', (
      tester,
    ) async {
      await _open(tester, language: 'ar');

      final bar = find.byKey(const Key('back-office-status-bar'));
      expect(
        find.descendant(of: bar, matching: find.text('Amer M. · المالك')),
        findsOneWidget,
      );
      final version = tester.widget<Text>(
        find.byKey(const Key('back-office-status-version')),
      );
      expect(version.textDirection, TextDirection.ltr);
      expect(version.data, 'v$posAppVersion');
    });
  });

  test('every tab is named in both languages, never the same word twice', () {
    for (final s in const <AppStrings>[EnStrings(), ArStrings()]) {
      final names = [
        for (final tab in BackOfficeTab.values) backOfficeTabName(s, tab),
      ];
      expect(names.toSet(), hasLength(BackOfficeTab.values.length));
    }
    for (final tab in BackOfficeTab.values) {
      expect(
        backOfficeTabName(const ArStrings(), tab),
        isNot(backOfficeTabName(const EnStrings(), tab)),
        reason: tab.name,
      );
    }
    expect(const ArStrings().backOffice, isNot(const EnStrings().backOffice));
  });
}
