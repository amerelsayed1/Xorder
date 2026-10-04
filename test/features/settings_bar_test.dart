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
import 'package:xorder_pos/features/settings/printer_settings_dialog.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

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
  setUpAll(loadPosFonts);

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
    // And onto the back office's screen, as the chord does: Admin Mode is
    // never a session over the till's own screens, and the header — the one
    // place Exit is said since 15 Sep 2026 — is that screen's. Exit goes back
    // to wherever this was pressed, as the chord remembers it.
    final router = container.read(routerProvider);
    final from = router.routerDelegate.currentConfiguration.uri.path;
    if (from != PosRoutes.management) {
      router.go(
        PosRoutes.management,
        extra: ManagementDestination(returnTo: from),
      );
    }
    await tester.pumpAndSettle();
  }

  /// A word of the bar itself — a menu, or a button with no menu under it
  /// (Home's, since 15 Sep 2026) — and not a line of an open menu, which sits
  /// inside the `MenuBar` too but under its menu's `SubmenuButton`.
  bool onTheBar(Element e) =>
      (e.widget is SubmenuButton || e.widget is MenuItemButton) &&
      e.findAncestorWidgetOfExactType<MenuBar>() != null &&
      e.findAncestorWidgetOfExactType<SubmenuButton>() == null;

  String labelOf(Widget w) =>
      ((w is SubmenuButton ? w.child : (w as MenuItemButton).child)! as Text)
          .data!;

  /// The bar's words as drawn, in the order they are built.
  Finder barButtons() => find.byElementPredicate(onTheBar);

  List<String> barLabels(WidgetTester tester) => [
    for (final element in barButtons().evaluate()) labelOf(element.widget),
  ];

  /// The bar's own word, not a line of the same name.
  Finder barButton(String label) => find.byElementPredicate(
    (e) => onTheBar(e) && labelOf(e.widget) == label,
  );

  /// The bar's word only if it opens a menu. Home's does not.
  Finder menuOf(String label) => find.byElementPredicate(
    (e) => onTheBar(e) && e.widget is SubmenuButton && labelOf(e.widget) == label,
  );

  /// Lines of whichever menu is open.
  Finder openLines() => find.byElementPredicate(
    (e) =>
        e.widget is MenuItemButton &&
        e.findAncestorWidgetOfExactType<SubmenuButton>() != null,
  );

  /// Opens [menu], reads its lines in order, and closes it again — so the
  /// next menu read is read alone.
  Future<List<String>> linesOf(WidgetTester tester, String menu) async {
    await tester.tap(menuOf(menu));
    await tester.pumpAndSettle();
    final lines = [
      for (final element in openLines().evaluate()) labelOf(element.widget),
    ];
    await tester.tap(menuOf(menu));
    await tester.pumpAndSettle();
    expect(openLines(), findsNothing, reason: 'closed again');
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

  testWidgets('Admin Mode with nobody signed in at the till still has the '
      'bar, and the back office\'s menus on it', (tester) async {
    // Since 15 Sep 2026 the bar is the only way between the back office's
    // pages: the owner took the on-screen strip away. So "no bar until
    // somebody signs in" has to count Admin Mode as a sign-in, or a manager
    // who entered it on a till nobody had opened would be left on Home with
    // nothing but Exit.
    final container = await pumpApp(tester, staff: null);
    String path() => container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;

    // Where the chord would take them: `_openAdmin`'s own destination.
    container
        .read(routerProvider)
        .go(
          PosRoutes.management,
          extra: const ManagementDestination(returnTo: PosRoutes.start),
        );
    await tester.pumpAndSettle();
    expect(path(), PosRoutes.management);
    expect(
      find.byType(MenuBar),
      findsNothing,
      reason: 'the door is not the back office, and nobody is in yet',
    );

    await intoAdminMode(tester, container);
    expect(container.read(signedInStaffProvider), isNull, reason: 'the till');
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
    ]);

    // And it moves them: a line, then Home again by its word alone.
    await tester.tap(barButton('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Roles & permissions'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('back-office-pane-roles')),
      findsOneWidget,
    );
    await tester.tap(barButton('Home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('back-office-pane-home')), findsOneWidget);

    // Out of Admin Mode, back on the start screen: no bar again.
    await tester.tap(find.byKey(const Key('admin-exit')));
    await tester.pumpAndSettle();
    expect(path(), PosRoutes.start);
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
      'map\'s order, listing its items', (tester) async {
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

    expect(menuOf('Home'), findsNothing, reason: 'a button, not a menu');
    expect(await linesOf(tester, 'Sales'), [
      'Orders',
      'Invoices',
      'Returns',
      'Cancelled orders',
    ]);
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
      'Combos',
    ]);
    // Each thing buying is, with the "new" that starts one: shortcuts no
    // pane's own tabs can be.
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
      'Settlements',
      'Payment methods',
      'Taxes',
      'Bills due',
      'Transactions',
      'Profit & loss',
    ]);
    expect(await linesOf(tester, 'People'), [
      'Staff',
      'Roles & permissions',
      'Shifts',
      'Customers',
    ]);
    expect(await linesOf(tester, 'System'), [
      'Activity',
      'Backup',
      'Devices',
      'Sync',
    ]);
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
        // A direct word has no lines to read: it is its one line.
        if (menu.direct) {
          expect(menuOf(menu.label), findsNothing, reason: menu.label);
          expect(barButton(menu.label), findsOneWidget, reason: menu.label);
          continue;
        }
        expect(await linesOf(tester, menu.label), [
          for (final line in menu.lines) line.label,
        ], reason: menu.label);
      }
      // Settings: everything it held before Admin Mode, in the same order,
      // less the till's own line for each place the back office now offers
      // as a page — then the back office's Settings items. The owner holds
      // `terminal.manage`, so both Printer and About are pages here.
      final settings = [
        for (final menu in bar)
          if (menu.tab == BackOfficeTab.settings) ...menu.lines,
      ];
      final replaced = {
        for (final line in settings)
          if (line.pane == ManagementPane.printer)
            'Printer & cash drawer…'
          else if (line.pane == ManagementPane.about)
            'About XOrder POS',
      };
      expect(replaced, hasLength(2));
      expect(await linesOf(tester, 'Settings'), [
        for (final line in till)
          if (!replaced.contains(line)) line,
        for (final line in settings) line.label,
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

  testWidgets('Settings keeps the till\'s own lines on top and gains the '
      'map\'s six beneath them, each place said once', (tester) async {
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
      'Printer & cash drawer',
      'User',
      'About XOrder',
      'Staff & accounts…',
    ]) {
      expect(till, isNot(contains(item)), reason: item);
    }

    // In Admin Mode the till's Printer and About lines step aside for the
    // pages of the same name, rather than the menu saying each twice — a
    // dialog and a page. Switch user stays: it hands the till over, and is
    // not the map's User.
    await intoAdminMode(tester, container);
    expect(await linesOf(tester, 'Settings'), [
      for (final line in till)
        if (line != 'Printer & cash drawer…' && line != 'About XOrder POS')
          line,
      'Orders & invoices settings',
      'Printer & cash drawer',
      'Language',
      'Appearance',
      'User',
      'About XOrder',
    ]);

    // And back the moment Admin Mode ends.
    await tester.tap(find.byKey(const Key('admin-exit')));
    await tester.pumpAndSettle();
    expect(await linesOf(tester, 'Settings'), till);
  }, variant: desktop);

  testWidgets('the till\'s printer dialog still opens from the till, outside '
      'Admin Mode; inside it, the line is the page', (tester) async {
    final container = await pumpApp(tester);

    await openSettings(tester);
    await tester.tap(find.text('Printer & cash drawer…'));
    await tester.pumpAndSettle();
    expect(find.byType(PrinterSettingsDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(PrinterSettingsDialog))).pop();
    await tester.pumpAndSettle();

    await intoAdminMode(tester, container);
    await openSettings(tester);
    expect(find.text('Printer & cash drawer…'), findsNothing);
    await tester.tap(find.widgetWithText(MenuItemButton, 'Printer & cash drawer'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('back-office-pane-printer')),
      findsOneWidget,
    );
    expect(find.byType(PrinterSettingsDialog), findsNothing);
  }, variant: desktop);

  testWidgets('a line opens its page, and the header\'s Exit leaves Admin '
      'Mode for where it began', (tester) async {
    final container = await pumpApp(tester);
    await intoAdminMode(tester, container);

    for (final (menu, line, pane) in [
      ('People', 'Roles & permissions', ManagementPane.roles),
      ('Settings', 'Orders & invoices settings', ManagementPane.receipt),
      ('Settings', 'Language', ManagementPane.language),
      // The items `pos/ia-screens` built, one per tab it touched and all
      // three of Settings'.
      ('Sales', 'Invoices', ManagementPane.invoices),
      ('Sales', 'Returns', ManagementPane.returns),
      ('Sales', 'Cancelled orders', ManagementPane.voidedOrders),
      ('Finance', 'Settlements', ManagementPane.settlements),
      ('People', 'Shifts', ManagementPane.shifts),
      ('System', 'Sync', ManagementPane.sync),
      ('Settings', 'Printer & cash drawer', ManagementPane.printer),
      ('Settings', 'User', ManagementPane.user),
      ('Settings', 'About XOrder', ManagementPane.about),
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

    await tester.tap(find.byKey(const Key('admin-exit')));
    await tester.pumpAndSettle();
    expect(container.read(adminSessionProvider), isNull);
    // Back to Orders, where Admin Mode began: twelve bar lines later, the
    // way back is still the one it was entered by.
    expect(
      container.read(routerProvider).routerDelegate.currentConfiguration.uri
          .path,
      PosRoutes.orders,
    );
    expect(barLabels(tester), ['Settings'], reason: 'the till\'s bar again');
  }, variant: desktop);

  // The way out is where the chord was pressed, however the back office was
  // moved about in since. Every bar line used to name its pane and no way
  // back, so the first line chosen from the bar replaced the route's memory
  // of where Admin Mode was entered — and Exit went to the start screen
  // instead of the till the manager had come from. The header's Exit is the
  // only one since 15 Sep 2026: the bar's, under Home, went as a duplicate.
  testWidgets('entered by the chord from Orders, a pane chosen from the bar '
      'still exits to Orders', (tester) async {
    final container = await pumpApp(tester);
    String path() => container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    expect(path(), PosRoutes.orders);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(path(), PosRoutes.management, reason: 'the chord opened it');
    await intoAdminMode(tester, container);

    // Two lines, so the second is chosen while already on a bar-opened
    // pane: the memory has to survive being carried, not only made.
    for (final (menu, line) in [
      ('People', 'Roles & permissions'),
      ('System', 'Activity'),
    ]) {
      await tester.tap(barButton(menu));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, line));
      await tester.pumpAndSettle();
    }
    expect(path(), PosRoutes.management);

    await tester.tap(find.byKey(const Key('admin-exit')));
    await tester.pumpAndSettle();
    expect(container.read(adminSessionProvider), isNull);
    expect(path(), PosRoutes.orders, reason: 'where the chord was pressed');
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

  // The owner, 15 Sep 2026: "there is duplication here". Exit was the header's
  // button and a line under Home; Home was a menu whose one other line was
  // Home again. Now Exit is said once and Home is a word that opens Home.
  testWidgets('Exit Admin Mode is said once, by the header, and Home is a '
      'button straight to the landing', (tester) async {
    final container = await pumpApp(tester, offline: true);
    await intoAdminMode(tester, container);

    expect(find.text('Exit Admin Mode'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin-exit')),
        matching: find.text('Exit Admin Mode'),
      ),
      findsOneWidget,
      reason: 'the one is the header\'s',
    );
    // Under no menu of the bar, each opened in turn.
    for (final label in barLabels(tester)) {
      if (menuOf(label).evaluate().isEmpty) continue;
      expect(
        await linesOf(tester, label),
        isNot(contains('Exit Admin Mode')),
        reason: label,
      );
    }

    // Somewhere else, then Home by its word alone: no menu opens on the way.
    await tester.tap(barButton('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Staff'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('back-office-pane-staff')), findsOneWidget);
    expect(menuOf('Home'), findsNothing);
    await tester.tap(barButton('Home'));
    await tester.pumpAndSettle();
    expect(openLines(), findsNothing, reason: 'no menu under Home');
    expect(find.byKey(const ValueKey('back-office-pane-home')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('back-office-title'))).data,
      'Home',
    );
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
    // الرئيسية a button, and the way out said once — by the header.
    expect(menuOf('الرئيسية'), findsNothing);
    expect(barButton('الرئيسية'), findsOneWidget);
    expect(find.text('الخروج من وضع المسؤول'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MenuBar),
        matching: find.text('الخروج من وضع المسؤول'),
      ),
      findsNothing,
    );
    expect(await linesOf(tester, 'الأفراد'), [
      'الموظفون',
      'الأدوار والصلاحيات',
      'الورديات',
      'العملاء',
    ]);
    // Each of the map's six once, in its words — no second printer or about
    // line from the till's own.
    final settings = await linesOf(tester, 'الإعدادات');
    for (final item in [
      'إعدادات الطلبات والفواتير',
      'اللغة',
      'المظهر',
      'الطابعة ودرج النقدية',
      'المستخدم',
      'حول XOrder',
    ]) {
      expect(settings.where((l) => l == item), hasLength(1), reason: item);
    }
    expect(settings, isNot(contains('الطابعة ودرج النقدية…')));
    expect(settings, isNot(contains('حول XOrder POS')));
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
        // after it further along, in the map's order.
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
