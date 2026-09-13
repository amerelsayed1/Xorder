import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/app.dart';
import 'package:xorder_pos/app/providers.dart';

import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';

import '../support/fakes.dart';

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
  // Every test here runs as macOS. The app mounts a native `PlatformMenuBar`
  // above this bar, and its About item exists only on the desktop platforms
  // this ships to — under the test binding's default platform that item throws
  // on the first frame and takes the tree down before the bar under test
  // builds at all.
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// [offline] where a test is about Buying's own entries: the harness is a
  /// cloud till, where the platform authors purchasing (CB-09).
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    bool offline = false,
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

    // English, asked for rather than assumed: the product's default is Arabic —
    // its restaurants are in Egypt — and these tests read English copy.
    container.read(localeProvider.notifier).apply('en');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const XorderPosApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
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

  testWidgets('each area of the back office is its own word in the bar', (
    tester,
  ) async {
    // Offline, because Buying's own entries are what this reads. The cloud
    // bar's Buying is a single pointer — asserted below.
    final container = await pumpApp(tester, offline: true);

    // Nobody signed in yet — and that is not the same as nobody permitted. The
    // management screen's own PIN pad is what signs somebody in, so hiding the
    // way to it would be a lock with its key inside. One door, under one word,
    // because which areas an unknown person has is not a question the bar can
    // answer.
    expect(find.text('Management'), findsOneWidget);
    expect(find.text('Buying'), findsNothing);

    container
        .read(signedInStaffProvider.notifier)
        .signIn(
          const PosStaff(
            id: 1,
            name: 'Rana A.',
            username: 'rana',
            // The owner's role, not a hand-picked capability: which areas
            // appear is `managementAreasFor`'s answer, and it hides Buying from
            // somebody who manages the rota but does not buy the stock.
            role: PosRole(
              id: 1,
              code: 'owner',
              nameEn: 'Owner',
              capabilities: SystemRoles.owner,
            ),
          ),
        );
    await tester.pumpAndSettle();

    // Now the areas themselves. "Where do I enter this invoice" is answered by
    // Buying, in the bar, rather than by the fifth line of a scrolling list.
    expect(find.text('Management'), findsNothing);
    for (final area in ['People', 'Money', 'Buying', 'Compliance', 'System']) {
      expect(find.text(area), findsOneWidget, reason: area);
    }

    await tester.tap(find.text('Buying'));
    await tester.pumpAndSettle();
    // Each thing buying is, with the "new" that starts one — not one word that
    // opens a screen and makes you find them again.
    for (final entry in [
      'Purchase orders',
      'New order',
      'Invoices',
      'Enter an invoice',
      'Payments',
      'Suppliers',
      'New supplier',
    ]) {
      expect(find.text(entry), findsOneWidget, reason: entry);
    }

    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    expect(find.text('Tax'), findsOneWidget);
  }, variant: desktop);

  testWidgets('on a cloud till Buying is one line, saying where it went', (
    tester,
  ) async {
    // CB-09: the platform authors purchasing and stock on cloud. The word
    // stays where a manager learned to look for it; what is under it is the
    // answer, not four lists of rows the platform would never see.
    final container = await pumpApp(tester);
    container
        .read(signedInStaffProvider.notifier)
        .signIn(
          const PosStaff(
            id: 1,
            name: 'Rana A.',
            username: 'rana',
            // Every capability, `purchase.manage` included — a local Owner
            // role grants it even though no cloud bundle ever does.
            role: PosRole(
              id: 1,
              code: 'owner',
              nameEn: 'Owner',
              capabilities: SystemRoles.owner,
            ),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('Buying'), findsOneWidget);
    expect(find.text('Inventory'), findsNothing);

    await tester.tap(find.text('Buying'));
    await tester.pumpAndSettle();
    expect(find.text('Purchasing & stock — on xorder.io…'), findsOneWidget);
    for (final entry in [
      'Purchase orders',
      'New order',
      'Invoices',
      'Enter an invoice',
      'Payments',
      'Suppliers',
      'New supplier',
    ]) {
      expect(find.text(entry), findsNothing, reason: entry);
    }
  }, variant: desktop);

  testWidgets('handing the till over is named for what it is', (tester) async {
    await pumpApp(tester);

    await openSettings(tester);
    // The lock screen signs in whoever's PIN it is, so this is the same door as
    // Lock — but nobody hands a till to a colleague by reaching for Lock.
    expect(find.text('Switch user'), findsOneWidget);
  }, variant: desktop);

  testWidgets('the back office has a key, and the menu says which', (
    tester,
  ) async {
    await pumpApp(tester);

    // On the Management menu, beside the item it opens — not in Settings,
    // where "Staff & accounts" and "Management" were the same door twice.
    await openSettings(tester, label: 'Management');
    // Back-office work is something a manager does twenty times an evening
    // between orders, and a key nobody can guess is a key nobody uses.
    expect(find.text('F8'), findsOneWidget);
  }, variant: desktop);

  testWidgets('and the same in Arabic, where the bar is mirrored', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    container.read(localeProvider.notifier).apply('ar');
    container
        .read(signedInStaffProvider.notifier)
        .signIn(
          const PosStaff(
            id: 1,
            name: 'Rana A.',
            username: 'rana',
            role: PosRole(
              id: 1,
              code: 'owner',
              nameEn: 'Owner',
              capabilities: SystemRoles.owner,
            ),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('المال'), findsOneWidget);

    await tester.tap(find.text('المال'));
    await tester.pumpAndSettle();

    // A pane name, not the area's own word again — the area and its pane share
    // a name under المشتريات, and an assertion that cannot tell them apart is
    // an assertion that a menu which never opened would still pass.
    expect(find.text('الضريبة'), findsOneWidget);
  }, variant: desktop);

  testWidgets('Settings holds the till\'s own settings, not the back office '
      'again', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    expect(find.text('Orders & invoices'), findsOneWidget);
    expect(find.text('Printer & cash drawer…'), findsOneWidget);
    expect(find.text('About XOrder POS'), findsOneWidget);
    // The back office has its own menu beside this one.
    expect(find.text('Staff & accounts…'), findsNothing);
  }, variant: desktop);

  testWidgets('About names the version support will ask for', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.tap(find.text('About XOrder POS'));
    await tester.pumpAndSettle();

    expect(find.text('1.0.0'), findsOneWidget);
  }, variant: desktop);
}
