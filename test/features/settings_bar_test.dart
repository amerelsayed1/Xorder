import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/app.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/router.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/tokens.dart';

import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

/// The owner's role, not a hand-picked capability: which tabs the bar's menus
/// list is `backOfficeTabsFor`'s answer, and it hides Purchasing from somebody
/// who manages the rota but does not buy the stock.
const _owner = PosStaff(
  id: 1,
  name: 'Rana A.',
  username: 'rana',
  role: PosRole(
    id: 1,
    code: 'owner',
    nameEn: 'Owner',
    capabilities: SystemRoles.owner,
  ),
);

const _cashier = PosStaff(
  id: 2,
  name: 'Omar K.',
  username: 'omar',
  role: PosRole(
    id: 2,
    code: 'cashier',
    nameEn: 'Cashier',
    capabilities: SystemRoles.cashier,
  ),
);

/// Words for areas the back office no longer has: they went into Settings,
/// Finance and System when the tabs came back (BO-1), and must not return as
/// menus. People did return, as a tab of the owner's map.
const _oldAreas = ['Money', 'Buying', 'Compliance'];

/// The Settings bar has to describe the till it is sitting on.
///
/// It did not. `MenuBarWidget` needs an Overlay ancestor, so the bar builds one
/// of its own — and `Overlay.initialEntries` is honoured ONCE, when the Overlay
/// first builds. Every entry constructed afterwards is discarded, so a menu
/// assembled outside the entry keeps the first frame's values for the life of
/// the process. The body still followed the theme and the language, because
/// those travel by inherited widget, which left the menu as the only thing on
/// screen still describing a till that no longer existed: "Switch to light",
/// offered on a till already showing light.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled faces, not the test font, for the width test below: the test
  // font draws every glyph a full em wide, and "the owner's bar fits at
  // 1100 px" is a claim about IBM Plex Sans Arabic, in both of its scripts.
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

  // Every test here runs as macOS. The app mounts a native `PlatformMenuBar`
  // above this bar, and its About item exists only on the desktop platforms
  // this ships to — under the test binding's default platform that item throws
  // on the first frame and takes the tree down before the bar under test
  // builds at all.
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// Signed in as [staff], because the bar is absent until somebody is.
  ///
  /// [offline] where a test is about Purchasing's own entries: the harness is
  /// a cloud till, where the platform authors purchasing (CB-09).
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    PosStaff? staff = _owner,
    bool setUp = true,
    bool offline = false,
    double width = 1440,
  }) async {
    tester.view
      ..physicalSize = Size(width, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        if (offline) offlineTerminal(),
      ],
    );
    addTearDown(container.dispose);

    // English, asked for rather than assumed: the product's default is Arabic —
    // its restaurants are in Egypt — and these tests read English copy.
    container.read(localeProvider.notifier).apply('en');
    if (setUp) container.read(setupCompleteProvider.notifier).markComplete();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const XorderPosApp(),
      ),
    );
    if (staff != null) {
      container.read(signedInStaffProvider.notifier).signIn(staff);
      // Off the front door: the start screen shows the bar to nobody.
      container.read(routerProvider).go(PosRoutes.orders);
    }
    await tester.pumpAndSettle();
    return container;
  }

  /// Amer, the fake directory's owner, into Admin Mode — which is what puts
  /// the back office's menus on the bar.
  Future<void> intoAdminMode(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await container
        .read(adminSessionProvider.notifier)
        .signIn(username: 'amer', pin: '4321');
    await tester.pumpAndSettle();
  }

  /// The bar's menus as drawn, in the order they are built.
  Finder barButtons() => find.descendant(
    of: find.byType(MenuBar),
    matching: find.byType(SubmenuButton),
  );

  List<String> barLabels(WidgetTester tester) => [
    for (final button in tester.widgetList<SubmenuButton>(barButtons()))
      (button.child! as Text).data!,
  ];

  /// The bar's own button, not a line of the same name: an open menu's lines
  /// sit inside the `MenuBar` too, and Home's first line is called Home.
  Finder barButton(String label) => find.byWidgetPredicate(
    (w) => w is SubmenuButton && w.child is Text && (w.child! as Text).data == label,
  );

  /// Opens [menu], reads its lines in order, and closes it again — so the
  /// next menu read is read alone.
  Future<List<String>> linesOf(WidgetTester tester, String menu) async {
    await tester.tap(barButton(menu));
    await tester.pumpAndSettle();
    final lines = [
      for (final item in tester.widgetList<MenuItemButton>(
        find.byType(MenuItemButton),
      ))
        (item.child! as Text).data!,
    ];
    await tester.tap(barButton(menu));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing, reason: 'closed again');
    return lines;
  }

  /// [label] because the bar button is itself translated — which is the point
  /// of the second test below.
  Future<void> openSettings(
    WidgetTester tester, {
    String label = 'Settings',
  }) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('nobody signed in: no bar at all', (tester) async {
    final container = await pumpApp(tester, staff: null);

    // Whoever walks up to a till on the start screen is not yet anybody, so
    // the whole bar waits for a sign-in. And the bar is no way into the back
    // office: that is a hidden chord and a username and PIN, and a word here
    // would be a second, visible door.
    expect(find.byType(MenuBar), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Management'), findsNothing);

    // The bar arrives with a sign-in, past the front door, and leaves with the
    // sign-out.
    container.read(signedInStaffProvider.notifier).signIn(_owner);
    container.read(routerProvider).go(PosRoutes.orders);
    await tester.pumpAndSettle();
    expect(find.byType(MenuBar), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(
      barLabels(tester),
      ['Settings'],
      reason: 'the owner signed in at the till is not in Admin Mode',
    );
    expect(find.text('Management'), findsNothing);

    container.read(signedInStaffProvider.notifier).signOut();
    await tester.pumpAndSettle();
    expect(find.byType(MenuBar), findsNothing);
    expect(find.text('Settings'), findsNothing);
  }, variant: desktop);

  testWidgets('and not on the start screen, even with somebody signed in', (
    tester,
  ) async {
    final container = await pumpApp(tester, staff: null);

    // Signed in while still on the front door: the start screen is where
    // somebody signs in to sell, so it stays clean.
    container.read(signedInStaffProvider.notifier).signIn(_owner);
    await tester.pumpAndSettle();
    expect(find.byType(MenuBar), findsNothing);
    expect(find.text('Rana A.'), findsNothing, reason: 'no name strip either');

    container.read(routerProvider).go(PosRoutes.orders);
    await tester.pumpAndSettle();
    expect(find.byType(MenuBar), findsOneWidget);

    container.read(routerProvider).go(PosRoutes.start);
    await tester.pumpAndSettle();
    expect(find.byType(MenuBar), findsNothing);
  }, variant: desktop);

  testWidgets('nor on the lock screen, even in Admin Mode', (tester) async {
    // The back office's menus keep the bar's old rule: in front of the till
    // there is no bar, whoever is signed in behind it.
    final container = await pumpApp(tester);
    await intoAdminMode(tester, container);
    expect(barLabels(tester), contains('Home'));

    container.read(routerProvider).go(PosRoutes.lock);
    await tester.pumpAndSettle();
    expect(find.byType(MenuBar), findsNothing);
  }, variant: desktop);

  testWidgets('but a till being set up keeps it, for the language switch', (
    tester,
  ) async {
    await pumpApp(tester, staff: null, setUp: false);

    // The wizard has no language step up front; this bar is how an installer
    // facing a refusal they cannot read gets it in their language.
    expect(barLabels(tester), ['Settings'], reason: 'no back office');
    await openSettings(tester);
    expect(find.text('العربية'), findsOneWidget);
    // And only what nobody signed in may see.
    expect(find.text('Printer & cash drawer…'), findsNothing);
  }, variant: desktop);

  testWidgets('a cashier gets the till\'s settings and none of the back '
      'office', (tester) async {
    await pumpApp(tester, staff: _cashier);

    expect(barLabels(tester), ['Settings']);
    for (final area in _oldAreas) {
      expect(find.text(area), findsNothing, reason: area);
    }

    await openSettings(tester);
    expect(find.text('Switch user'), findsOneWidget);
    expect(find.text('Orders & invoices'), findsOneWidget);
    // Configuring the machine is `terminal.manage`, which a cashier lacks.
    expect(find.text('Printer & cash drawer…'), findsNothing);
    expect(find.text('⇧⌘S'), findsNothing);
  }, variant: desktop);

  testWidgets('the theme item names the theme the next tap would give', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    // The first frame is dark — the state the menu used to freeze at.
    container.read(brightnessProvider.notifier).apply(Brightness.dark);
    await tester.pumpAndSettle();

    await openSettings(tester);
    expect(find.text('Switch to light'), findsOneWidget);

    // Tap it. The till is now light, and the menu has to say so the next time
    // it is opened — this is the assertion the bug failed.
    await tester.tap(find.text('Switch to light'));
    await tester.pumpAndSettle();

    await openSettings(tester);
    expect(
      find.text('Switch to dark'),
      findsOneWidget,
      reason: 'the till is showing light; offering light again is a lie',
    );
    expect(find.text('Switch to light'), findsNothing);
  }, variant: desktop);

  testWidgets('and the language item flips with it, for the same reason', (
    tester,
  ) async {
    await pumpApp(tester);

    await openSettings(tester);
    // Reads as the language you would GET, not the one you are in.
    expect(find.text('العربية'), findsOneWidget);

    // Switch from the menu itself, which is how anyone actually does it.
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    // The bar button moved too, which is the same fix working one level up.
    await openSettings(tester, label: 'الإعدادات');
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsNothing);
  }, variant: desktop);

  testWidgets('the back office is the owner\'s map: a menu per tab, in the '
      'strip\'s order, listing its items', (tester) async {
    // Offline, because Purchasing's own lines are what this reads. The cloud
    // bar's pointers are asserted below.
    final container = await pumpApp(tester, offline: true);
    await intoAdminMode(tester, container);

    // Settings is the till's own menu, last, with the back office's Settings
    // folded in — not a second الإعدادات.
    expect(barLabels(tester), [
      'Home',
      'Sales',
      'Reports',
      'Menu',
      'Inventory',
      'Purchasing',
      'Finance',
      'People',
      'System',
      'Settings',
    ]);
    expect(find.text('Management'), findsNothing);
    for (final area in _oldAreas) {
      expect(find.text(area), findsNothing, reason: area);
    }

    expect(await linesOf(tester, 'Home'), ['Home', 'Exit Admin Mode']);
    expect(await linesOf(tester, 'Sales'), ['Orders']);
    expect(await linesOf(tester, 'Reports'), [
      'Business summary',
      'Sales',
      'Items',
      'Payment methods',
      'Branches & devices',
      'Employees',
    ]);
    expect(await linesOf(tester, 'Menu'), [
      'Menu',
      'Categories',
      'Extras library',
      'Floor',
    ]);
    // Each thing buying is, with the "new" that starts one: the shortcuts the
    // strip cannot be.
    expect(await linesOf(tester, 'Purchasing'), [
      'Purchase orders',
      'New order',
      'Suppliers',
      'New supplier',
      'Invoices',
      'Enter an invoice',
      'Payments',
    ]);
    expect(await linesOf(tester, 'Finance'), [
      'Overview',
      'Revenue',
      'Treasury',
      'Expenses',
      'Payment methods',
      'Taxes',
      'Bills due',
      'Transactions',
    ]);
    expect(await linesOf(tester, 'People'), ['Staff', 'Roles & permissions']);
    expect(await linesOf(tester, 'System'), ['Activity', 'Backup', 'Devices']);
  }, variant: desktop);

  // The drawn bar held to the rule, menu by menu, on both deployments.
  for (final offline in [true, false]) {
    final where = offline ? 'offline' : 'cloud';
    testWidgets('the owner, $where: every menu lists what managementBarFor '
        'says, and nothing else', (tester) async {
      final container = await pumpApp(tester, offline: offline);
      final till = await linesOf(tester, 'Settings');
      await intoAdminMode(tester, container);

      final bar = managementBarFor(
        const EnStrings(),
        admin: container.read(adminSessionProvider)!.staff,
        authorsItsOwnCatalogue: offline,
      );
      expect(barLabels(tester), [
        for (final menu in bar)
          if (menu.tab != BackOfficeTab.settings) menu.label,
        'Settings',
      ]);
      for (final menu in bar) {
        if (menu.tab == BackOfficeTab.settings) continue;
        expect(await linesOf(tester, menu.label), [
          for (final line in menu.lines) line.label,
          if (menu.tab == BackOfficeTab.home) 'Exit Admin Mode',
        ], reason: menu.label);
      }
      // Settings: everything it held before Admin Mode, in the same order,
      // and then the back office's Settings items.
      expect(await linesOf(tester, 'Settings'), [
        ...till,
        for (final menu in bar)
          if (menu.tab == BackOfficeTab.settings)
            for (final line in menu.lines) line.label,
      ]);
    }, variant: desktop);
  }

  testWidgets('on a cloud till Inventory and Purchasing each hold one line, '
      'saying where they went', (tester) async {
    // CB-09: the platform authors purchasing and stock on cloud. What is under
    // each menu is the answer, not lists of rows the platform would never see.
    //
    // In Admin Mode as the owner: every capability, `purchase.manage`
    // included — a local Owner role grants it even though no cloud bundle ever
    // does.
    final container = await pumpApp(tester);
    await intoAdminMode(tester, container);

    expect(barLabels(tester), [
      'Home',
      'Sales',
      'Reports',
      'Inventory',
      'Purchasing',
      'Finance',
      'People',
      'System',
      'Settings',
    ], reason: 'no Menu: the platform authors it');
    for (final menu in ['Inventory', 'Purchasing']) {
      expect(await linesOf(tester, menu), [
        'Purchasing & stock — on xorder.io…',
      ], reason: menu);
    }
  }, variant: desktop);

  testWidgets('Settings keeps the till\'s own lines on top, and gains the '
      'back office\'s beneath them', (tester) async {
    final container = await pumpApp(tester, offline: true);

    final till = await linesOf(tester, 'Settings');
    expect(
      till,
      containsAllInOrder([
        'Orders & invoices',
        'Printer & cash drawer…',
        'Switch user',
        'About XOrder POS',
      ]),
    );
    // Outside Admin Mode the back office's Settings are nowhere.
    for (final item in [
      'Orders & invoices settings',
      'Language',
      'Appearance',
      'Staff & accounts…',
    ]) {
      expect(till, isNot(contains(item)), reason: item);
    }

    await intoAdminMode(tester, container);
    expect(await linesOf(tester, 'Settings'), [
      ...till,
      'Orders & invoices settings',
      'Language',
      'Appearance',
    ]);
  }, variant: desktop);

  testWidgets('a line opens its page, and Exit leaves Admin Mode as the '
      'header\'s Exit does', (tester) async {
    final container = await pumpApp(tester);
    await intoAdminMode(tester, container);

    for (final (menu, line, pane) in [
      ('People', 'Roles & permissions', ManagementPane.roles),
      ('Settings', 'Orders & invoices settings', ManagementPane.receipt),
      ('Settings', 'Language', ManagementPane.language),
    ]) {
      await tester.tap(barButton(menu));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, line));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('back-office-pane-${pane.name}')),
        findsOneWidget,
        reason: '$menu › $line',
      );
    }

    await tester.tap(barButton('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Exit Admin Mode'));
    await tester.pumpAndSettle();
    expect(container.read(adminSessionProvider), isNull);
    expect(
      container.read(routerProvider).routerDelegate.currentConfiguration.uri
          .path,
      PosRoutes.start,
      reason: 'opened from the bar, which names no way back',
    );
    expect(find.byType(MenuBar), findsNothing);
  }, variant: desktop);

  testWidgets('handing the till over is named for what it is', (tester) async {
    await pumpApp(tester);

    await openSettings(tester);
    // The lock screen signs in whoever's PIN it is, so this is the same door as
    // Lock — but nobody hands a till to a colleague by reaching for Lock.
    expect(find.text('Switch user'), findsOneWidget);
  }, variant: desktop);

  testWidgets('the reset names its chord, and nothing names Admin Mode\'s', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);

    // Printed, so an installer can discover a reset nobody would guess.
    expect(find.text('⇧⌘R'), findsOneWidget);
    // Admin Mode's chord is printed nowhere: a hidden way in that the menu
    // advertises is not hidden. F8, which used to be, is gone.
    expect(find.text('⇧⌘S'), findsNothing);
    expect(find.text('F8'), findsNothing);
  }, variant: desktop);

  testWidgets('and the same in Arabic, the map\'s own words', (tester) async {
    final container = await pumpApp(tester);
    await intoAdminMode(tester, container);
    container.read(localeProvider.notifier).apply('ar');
    await tester.pumpAndSettle();

    // A cloud till: no المنيو, and one الإعدادات.
    expect(barLabels(tester), [
      'الرئيسية',
      'المبيعات',
      'التقارير',
      'المخزون',
      'المشتريات',
      'المالية',
      'الأفراد',
      'النظام',
      'الإعدادات',
    ]);
    expect(await linesOf(tester, 'الرئيسية'), [
      'الرئيسية',
      'الخروج من وضع المسؤول',
    ]);
    expect(await linesOf(tester, 'الأفراد'), [
      'الموظفون',
      'الأدوار والصلاحيات',
    ]);
    for (final menu in ['المخزون', 'المشتريات']) {
      expect(await linesOf(tester, menu), [
        const ArStrings().purchasingOnPlatformEntry,
      ], reason: menu);
    }
  }, variant: desktop);

  group('at 1100 px', () {
    for (final language in ['en', 'ar']) {
      testWidgets('the owner\'s whole bar fits, offline, in $language — and '
          'runs from the start edge', (tester) async {
        // Offline, the owner: the most menus anybody gets.
        final container = await pumpApp(
          tester,
          offline: true,
          width: PosSize.wideShellMin,
        );
        await intoAdminMode(tester, container);
        container.read(localeProvider.notifier).apply(language);
        await tester.pumpAndSettle();

        final labels = barLabels(tester);
        expect(labels, hasLength(10), reason: 'the map\'s ten words');
        final rects = [
          for (var i = 0; i < labels.length; i++)
            tester.getRect(barButtons().at(i)),
        ];
        for (final (i, rect) in rects.indexed) {
          expect(rect.left, greaterThanOrEqualTo(0), reason: labels[i]);
          expect(
            rect.right,
            lessThanOrEqualTo(PosSize.wideShellMin),
            reason: labels[i],
          );
        }
        // Home at the start edge — the right, in Arabic — and each menu
        // after it further along, as the strip below runs.
        for (var i = 1; i < rects.length; i++) {
          expect(
            language == 'ar'
                ? rects[i].right <= rects[i - 1].left
                : rects[i].left >= rects[i - 1].right,
            isTrue,
            reason: '${labels[i - 1]} then ${labels[i]}',
          );
        }
      }, variant: desktop);
    }
  });

  testWidgets('About names the version support will ask for', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.tap(find.text('About XOrder POS'));
    await tester.pumpAndSettle();

    expect(find.text('1.0.0'), findsOneWidget);
  }, variant: desktop);
}
