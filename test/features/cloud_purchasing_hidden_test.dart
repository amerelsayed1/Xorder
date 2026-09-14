import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart' show etaFilingEnabled;
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_purchasing_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_roles_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos/features/admin/presentation/management_staff_pane.dart';

import '../support/fakes.dart';

/// CB-09 slice e: on a cloud till the platform authors buying and stock.
///
/// The claim is about deployment, not permission. The platform withholds
/// `purchase.manage` from every bundle, but roles are the till's own even on
/// cloud, so a local Owner or Manager role — or a direct grant — still carries
/// it. Every test here therefore gives the person the capability and asserts
/// the panes are gone anyway; a test with nobody holding it would pass on the
/// old capability gate and prove nothing.
void main() {
  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'amer',
    role: PosRole(
      id: 1,
      code: SystemRoles.ownerCode,
      nameEn: 'Owner',
      capabilities: SystemRoles.owner,
    ),
  );
  const manager = PosStaff(
    id: 2,
    name: 'Nour S.',
    username: 'nour',
    role: PosRole(
      id: 2,
      code: SystemRoles.managerCode,
      nameEn: 'Manager',
      capabilities: SystemRoles.manager,
    ),
  );
  // No role at all: the grant against their own name is the whole of it.
  const granted = PosStaff(
    id: 3,
    name: 'Hady K.',
    username: 'hady',
    capabilities: {PosCapability.staffManage, PosCapability.purchaseManage},
  );
  const buyers = [owner, manager, granted];
  // Through the back office's door by a role, holding nothing that buys.
  const rota = PosStaff(
    id: 4,
    name: 'Salma R.',
    username: 'salma',
    role: PosRole(
      id: 4,
      code: 'rota',
      nameEn: 'Rota manager',
      capabilities: {
        PosCapability.operate,
        PosCapability.staffManage,
        PosCapability.adminEnter,
      },
    ),
  );

  const platformAuthored = [
    ManagementPane.purchasing,
    ManagementPane.items,
    ManagementPane.stock,
    ManagementPane.units,
  ];

  group('which panes a cloud till has', () {
    test('none of the four, even for an owner who holds purchase.manage', () {
      expect(
        owner.can(PosCapability.purchaseManage),
        isTrue,
        reason: 'the premise: the capability alone would have let them in',
      );
      final panes = managementPanesFor(
        admin: owner,
        authorsItsOwnCatalogue: false,
      );
      for (final pane in platformAuthored) {
        expect(panes, isNot(contains(pane)), reason: pane.name);
      }
      final tabs = backOfficeTabsFor(
        admin: owner,
        authorsItsOwnCatalogue: false,
      );
      // The two tabs stay, as words that point at the platform — with nothing
      // of their own under them.
      expect(
        [for (final (tab, _) in tabs) tab],
        containsAll([BackOfficeTab.inventory, BackOfficeTab.purchasing]),
      );
      for (final (tab, own) in tabs) {
        if (tab == BackOfficeTab.inventory ||
            tab == BackOfficeTab.purchasing) {
          expect(own, isEmpty, reason: tab.name);
        }
      }
      expect(
        [for (final (tab, _) in tabs) tab],
        isNot(contains(BackOfficeTab.menu)),
      );
    });

    test('nor for a local Manager role, nor for a direct grant', () {
      for (final staff in [manager, granted]) {
        expect(staff.can(PosCapability.purchaseManage), isTrue);
        final panes = managementPanesFor(
          admin: staff,
          authorsItsOwnCatalogue: false,
        );
        for (final pane in platformAuthored) {
          expect(panes, isNot(contains(pane)), reason: '${staff.name}: $pane');
        }
      }
    });

    test('offline is unchanged: the owner has every pane, the four included',
        () {
      // Every pane this build shows at all: e-receipt filing is a build switch
      // (off since 2026-09-13), and it hides ETA on both deployments alike.
      expect(
        managementPanesFor(admin: owner, authorsItsOwnCatalogue: true),
        [
          for (final pane in ManagementPane.values)
            if (pane != ManagementPane.eta || etaFilingEnabled) pane,
        ],
      );
      final panes = managementPanesFor(
        admin: manager,
        authorsItsOwnCatalogue: true,
      );
      for (final pane in platformAuthored) {
        expect(panes, contains(pane), reason: pane.name);
      }
      // Still the owner's alone — the capability gate is untouched.
      expect(panes, isNot(contains(ManagementPane.backup)));
    });

    test('cloud is offline less exactly what the platform authors', () {
      // Pins the rule both ways: nothing else moved, and this is the whole set.
      expect(
        {
          for (final pane in ManagementPane.values)
            if (hiddenBecausePlatformAuthors(
              pane,
              authorsItsOwnCatalogue: false,
            ))
              pane,
        },
        // Extras with the menu: sizes and extras are part of the catalogue
        // the platform authors, and the seeder rewrites them on a cloud till.
        // Finance's Bills due with the buying (BO-10): it reads nothing but
        // the supplier ledger, which is the platform's on a cloud till.
        {
          ManagementPane.menu,
          ManagementPane.floor,
          ManagementPane.extras,
          ManagementPane.financeBills,
          ...platformAuthored,
        },
      );
      for (final staff in buyers) {
        expect(
          managementPanesFor(admin: staff, authorsItsOwnCatalogue: false),
          [
            for (final pane in managementPanesFor(
              admin: staff,
              authorsItsOwnCatalogue: true,
            ))
              if (!hiddenBecausePlatformAuthors(
                pane,
                authorsItsOwnCatalogue: false,
              ))
                pane,
          ],
          reason: staff.name,
        );
      }
      for (final pane in ManagementPane.values) {
        expect(
          hiddenBecausePlatformAuthors(pane, authorsItsOwnCatalogue: true),
          isFalse,
          reason: 'offline authors everything: $pane',
        );
      }
    });
  });

  group('the Back office menu agrees with the strip', () {
    const s = EnStrings();

    List<ManagementBarEntry> lines(
      PosStaff staff, {
      required bool authors,
    }) => managementBarFor(s, admin: staff, authorsItsOwnCatalogue: authors);

    test('on cloud, every line opens a pane the strip has, or is the pointer',
        () {
      for (final staff in buyers) {
        final tabs = backOfficeTabsFor(
          admin: staff,
          authorsItsOwnCatalogue: false,
        );
        final strip = [for (final (_, own) in tabs) ...own];
        for (final line in lines(staff, authors: false)) {
          if (line.pane == null) continue;
          expect(strip, contains(line.open().pane), reason: line.label);
        }
        // A line for each tab that holds a pane, and the pointer for the two
        // that only point.
        expect(
          {for (final line in lines(staff, authors: false)) line.tab},
          {
            for (final (tab, own) in tabs)
              if (own.isNotEmpty) tab,
            BackOfficeTab.purchasing,
          },
          reason: staff.name,
        );
        expect(
          [for (final line in lines(staff, authors: false)) line.tab],
          isNot(contains(BackOfficeTab.inventory)),
          reason: 'the pointer names stock too; a second line would repeat it',
        );
      }
    });

    test('and the pointer is one line, which lands on the notice', () {
      final pointers = [
        for (final line in lines(owner, authors: false))
          if (line.pane == null) line,
      ];
      expect(pointers, hasLength(1), reason: 'one pointer in the whole bar');
      expect(pointers.single.label, s.purchasingOnPlatformEntry);

      final landing = pointers.single.open().pane!;
      expect(
        hiddenBecausePlatformAuthors(
          landing,
          authorsItsOwnCatalogue: false,
        ),
        isTrue,
        reason: 'the screen shows the tab and says why, rather than refusing',
      );
      expect(
        platformAuthoredPointer(s, landing),
        s.purchasingComesFromPlatform,
      );
    });

    test('and nobody who does not buy is pointed at buying', () {
      // Offline they have no Purchasing or Inventory tab; xorder-new's sidebar
      // hides the Purchasing group from them. The pointer is for whoever it
      // replaced.
      expect(rota.can(PosCapability.purchaseManage), isFalse);
      for (final authors in [false, true]) {
        final tabs = [
          for (final (tab, _) in backOfficeTabsFor(
            admin: rota,
            authorsItsOwnCatalogue: authors,
          ))
            tab,
        ];
        expect(tabs, contains(BackOfficeTab.settings), reason: 'Users');
        expect(
          tabs,
          isNot(contains(BackOfficeTab.purchasing)),
          reason: 'authors: $authors',
        );
        expect(
          tabs,
          isNot(contains(BackOfficeTab.inventory)),
          reason: 'authors: $authors',
        );
        expect(
          lines(rota, authors: authors).where((line) => line.pane == null),
          isEmpty,
          reason: 'authors: $authors',
        );
      }
    });

    test('offline, Purchasing\'s seven lines, no pointer, one line per tab',
        () {
      final bar = lines(owner, authors: true);
      expect(bar.where((line) => line.pane == null), isEmpty);
      expect(
        [
          for (final line in bar)
            if (line.tab == BackOfficeTab.purchasing) line.label,
        ],
        [
          for (final (label, _, _)
              in managementMenuEntries(s, ManagementPane.purchasing))
            label,
        ],
      );
      for (final (tab, own) in backOfficeTabsFor(
        admin: owner,
        authorsItsOwnCatalogue: true,
      )) {
        if (tab == BackOfficeTab.purchasing) continue;
        final mine = [
          for (final line in bar)
            if (line.tab == tab) line,
        ];
        expect(mine, hasLength(1), reason: tab.name);
        expect(mine.single.label, backOfficeTabName(s, tab));
        expect(mine.single.open().pane, own.first, reason: tab.name);
      }
    });
  });

  test('the pointer covers purchasing and inventory, and nothing else', () {
    const s = EnStrings();
    for (final pane in ManagementPane.values) {
      final buyingOrStock =
          tabOf(pane) == BackOfficeTab.purchasing ||
          tabOf(pane) == BackOfficeTab.inventory;
      expect(
        platformAuthoredPointer(s, pane) != null,
        buyingOrStock,
        reason: pane.name,
      );
    }
  });

  group('a deep link to a platform-authored pane', () {
    const cloud = DeploymentConfig(
      mode: DeploymentMode.cloud,
      baseUrl: 'https://xorder.io',
      tenantSlug: 'mahsoub',
    );

    /// The back office asking for [pane] — pumped again with another pane, it
    /// is what the bar does to a screen that is already open.
    Widget screen(
      ProviderContainer container, {
      required ManagementPane pane,
      String language = 'en',
    }) => UncontrolledProviderScope(
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
    );

    /// Cloud by DEPLOYMENT, not by an override: the provider the rule reads is
    /// derived from the mode, and this is where that is proved. [offline]
    /// binds a catalogue administrator instead, as an offline till has.
    Future<ProviderContainer> open(
      WidgetTester tester, {
      required ManagementPane pane,
      String language = 'en',
      bool offline = false,
      String username = 'amer',
      String pin = '4321',
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          if (offline) offlineTerminal(),
        ],
      );
      addTearDown(container.dispose);
      if (!offline) container.read(deploymentProvider.notifier).apply(cloud);

      await tester.pumpWidget(screen(container, pane: pane, language: language));
      await tester.pumpAndSettle();

      // Through Admin Mode's door — as Amer, the owner, unless a test says
      // otherwise: every capability, purchasing's included.
      await enterAdminMode(tester, username: username, pin: pin);
      return container;
    }

    testWidgets('lands on the Purchasing tab on a cloud till, and says where '
        'buying went', (tester) async {
      final container = await open(tester, pane: ManagementPane.purchasing);

      expect(container.read(catalogAdminRepositoryProvider), isNull);
      expect(
        container
            .read(adminSessionProvider)!
            .staff
            .can(PosCapability.purchaseManage),
        isTrue,
      );

      expect(find.byType(ManagementPurchasingPane), findsNothing);
      // The tab they asked for, not a silent fall-back to another one.
      expect(find.byType(ManagementStaffPane), findsNothing);
      expect(
        find.byKey(const Key('back-office-tab-purchasing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsOneWidget,
      );
      expect(
        find.text(const EnStrings().purchasingComesFromPlatform),
        findsOneWidget,
      );
    });

    testWidgets('and says it in Arabic on an Arabic till', (tester) async {
      await open(tester, pane: ManagementPane.units, language: 'ar');

      expect(
        find.text(const ArStrings().purchasingComesFromPlatform),
        findsOneWidget,
      );
      expect(
        find.text(const EnStrings().purchasingComesFromPlatform),
        findsNothing,
      );
    });

    // Asked for through the screen's own inputs, as the bar asks: a new
    // request moves on, and the sentence goes with the request that made it.
    testWidgets('asking for another pane moves on, and the sentence goes too', (
      tester,
    ) async {
      final container = await open(tester, pane: ManagementPane.stock);
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsOneWidget,
      );

      await tester.pumpWidget(screen(container, pane: ManagementPane.roles));
      await tester.pumpAndSettle();

      expect(find.byType(ManagementRolesPane), findsOneWidget);
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsNothing,
      );
    });

    testWidgets('somebody who does not buy is told nothing, as offline', (
      tester,
    ) async {
      // Nour, the fake directory's trusted supervisor: through the door, and
      // the rota's, but not the stockroom's.
      await open(
        tester,
        pane: ManagementPane.purchasing,
        username: 'nour',
        pin: '2468',
      );

      // The door's landing, as for any pane they do not have — not the
      // Purchasing tab with a sentence sending them somewhere they cannot go.
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsNothing,
      );
      expect(find.byType(ManagementPurchasingPane), findsNothing);
      expect(find.byType(ManagementScreen), findsOneWidget);
    });

    testWidgets('offline, the same link opens Purchasing and says nothing', (
      tester,
    ) async {
      await open(tester, pane: ManagementPane.purchasing, offline: true);

      expect(find.byType(ManagementPurchasingPane), findsOneWidget);
      expect(
        find.byKey(const Key('management-platform-pointer')),
        findsNothing,
      );
    });
  });

  test('the pointer is a real sentence in both languages', () {
    for (final s in const <AppStrings>[EnStrings(), ArStrings()]) {
      expect(s.purchasingComesFromPlatform, contains('xorder.io'));
      expect(s.purchasingOnPlatformEntry, contains('xorder.io'));
    }
    // Arabic words, not the English left in place.
    expect(
      const ArStrings().purchasingComesFromPlatform,
      contains('المشتريات'),
    );
    expect(
      const ArStrings().purchasingOnPlatformEntry,
      isNot(const EnStrings().purchasingOnPlatformEntry),
    );
  });
}
