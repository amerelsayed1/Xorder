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
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart' show etaFilingEnabled;
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_purchasing_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_roles_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos/features/admin/presentation/management_staff_pane.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// CB-09 slice e: on a cloud till the platform authors buying and stock.
///
/// The claim is about deployment, not permission. The platform withholds
/// `purchase.manage` from every bundle, but roles are the till's own even on
/// cloud, so a local Owner or Manager role — or a direct grant — still carries
/// it. Every test here therefore gives the person the capability and asserts
/// the panes are gone anyway; a test with nobody holding it would pass on the
/// old capability gate and prove nothing.
void main() {
  // An offline owner's strip holds all ten of the map's words; measured in
  // the bundled faces, not the test font's (see `loadPosFonts`).
  setUpAll(loadPosFonts);

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
        // Categories with the menu: the same pane, reached from the map's
        // الأقسام line.
        {
          ManagementPane.menu,
          ManagementPane.categories,
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

  group("the bar's menus agree with the strip", () {
    const s = EnStrings();

    List<ManagementBarEntry> lines(
      PosStaff staff, {
      required bool authors,
    }) => [
      for (final menu in managementBarFor(
        s,
        admin: staff,
        authorsItsOwnCatalogue: authors,
      ))
        ...menu.lines,
    ];

    // Every fixture, on both deployments: the whole bar held against
    // `managementPanesFor`, the rule the strip is held to.
    for (final staff in [...buyers, rota]) {
      for (final authors in [true, false]) {
        final where = authors ? 'offline' : 'cloud';
        test('${staff.name}, $where: a line per item, Purchasing\'s own, and '
            'the pointer only where it points', () {
          final menus = managementBarFor(
            s,
            admin: staff,
            authorsItsOwnCatalogue: authors,
          );
          final tabs = backOfficeTabsFor(
            admin: staff,
            authorsItsOwnCatalogue: authors,
          );
          final panes = managementPanesFor(
            admin: staff,
            authorsItsOwnCatalogue: authors,
          );
          final all = lines(staff, authors: authors);

          // A menu per visible tab, in the strip's order, named as the strip
          // names it — the same ten words in both places.
          expect(
            [for (final menu in menus) menu.tab],
            [for (final (tab, _) in tabs) tab],
          );
          for (final menu in menus) {
            expect(menu.label, backOfficeTabName(s, menu.tab));
            expect(menu.lines, isNotEmpty, reason: 'a word over a gap');
            for (final line in menu.lines) {
              expect(line.tab, menu.tab, reason: line.label);
              expect(tabOf(line.open().pane!), menu.tab, reason: line.label);
            }
          }

          // Each menu's lines are its tab's items — the sub-nav's words, in
          // the sub-nav's order — with Purchasing's own lines in place of its
          // one.
          for (final (tab, own) in tabs) {
            if (own.isEmpty) continue;
            expect(
              [
                for (final menu in menus)
                  if (menu.tab == tab)
                    for (final line in menu.lines) line.label,
              ],
              [
                for (final item in backOfficeItemsFor(s, tab, own))
                  ...switch (managementMenuEntries(s, item.opens)) {
                    final entries when entries.isNotEmpty => [
                      for (final (label, _, _) in entries) label,
                    ],
                    _ => [item.label],
                  },
              ],
              reason: tab.name,
            );
          }

          // And what the lines reach, through their items, is exactly the
          // panes the strip has.
          List<ManagementPane> holdsOf(ManagementBarEntry line) => [
            for (final (tab, own) in tabs)
              if (tab == line.tab)
                for (final item in backOfficeItemsFor(s, tab, own))
                  if (item.opens == line.pane) ...item.holds,
          ];
          expect(
            {
              for (final line in all)
                if (line.pane != null) ...holdsOf(line),
            },
            panes.toSet(),
          );

          // The pointer: under Inventory and Purchasing on a cloud till, for
          // whoever would buy offline, and for nobody else anywhere.
          final buys = Authorization.check(
            staff,
            PosCapability.purchaseManage,
          ).isAllowed;
          expect(
            {
              for (final line in all)
                if (line.pane == null) line.tab,
            },
            !authors && buys
                ? {BackOfficeTab.inventory, BackOfficeTab.purchasing}
                : isEmpty,
          );
          for (final menu in menus) {
            if (!menu.lines.any((line) => line.pane == null)) continue;
            expect(menu.lines, hasLength(1), reason: menu.label);
            expect(menu.lines.single.label, s.purchasingOnPlatformEntry);
            final landing = menu.lines.single.open().pane!;
            expect(
              hiddenBecausePlatformAuthors(
                landing,
                authorsItsOwnCatalogue: false,
              ),
              isTrue,
              reason: 'the screen shows the tab and says why, not a refusal',
            );
            expect(
              platformAuthoredPointer(s, landing),
              s.purchasingComesFromPlatform,
            );
          }
          if (!authors) {
            expect(
              [for (final menu in menus) menu.tab],
              isNot(contains(BackOfficeTab.menu)),
            );
          }
        });
      }
    }

    test('no two menus the bar draws share a label, in either language', () {
      // Settings is folded into the till's own Settings menu, because the two
      // would otherwise be the same word twice.
      for (final strings in const <AppStrings>[EnStrings(), ArStrings()]) {
        expect(
          backOfficeTabName(strings, BackOfficeTab.settings),
          strings.settings,
          reason: 'the premise of the fold',
        );
        for (final staff in [...buyers, rota]) {
          for (final authors in [true, false]) {
            final drawn = [
              for (final menu in managementBarFor(
                strings,
                admin: staff,
                authorsItsOwnCatalogue: authors,
              ))
                if (menu.tab != BackOfficeTab.settings) menu.label,
              strings.settings,
            ];
            expect(
              drawn.toSet(),
              hasLength(drawn.length),
              reason: '${staff.name}, authors: $authors, $drawn',
            );
          }
        }
      }
    });

    test('Settings\' lines are its three items, General first', () {
      final settings = managementBarFor(
        s,
        admin: owner,
        authorsItsOwnCatalogue: true,
      ).firstWhere((menu) => menu.tab == BackOfficeTab.settings).lines;
      expect([for (final line in settings) line.label], [
        'Orders & invoices settings',
        'Language',
        'Appearance',
      ]);
      expect([for (final line in settings) line.divider], everyElement(false));
      expect(settings.first.open().pane, ManagementPane.receipt);
    });

    test('Purchasing lists its tabs in the map\'s order, each with its '
        '"new"', () {
      final purchasing = managementBarFor(
        s,
        admin: owner,
        authorsItsOwnCatalogue: true,
      ).firstWhere((menu) => menu.tab == BackOfficeTab.purchasing).lines;
      expect([for (final line in purchasing) line.label], [
        'Purchase orders',
        'New order',
        'Suppliers',
        'New supplier',
        'Invoices',
        'Enter an invoice',
        'Payments',
      ]);
      expect(
        [for (final line in purchasing) line.open().purchasingTab],
        [
          PurchasingTab.orders,
          PurchasingTab.orders,
          PurchasingTab.suppliers,
          PurchasingTab.suppliers,
          PurchasingTab.invoices,
          PurchasingTab.invoices,
          PurchasingTab.payments,
        ],
      );
      expect(
        [for (final line in purchasing) line.divider],
        [false, false, true, false, true, false, false],
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
        expect(tabs, contains(BackOfficeTab.people), reason: 'Staff');
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
