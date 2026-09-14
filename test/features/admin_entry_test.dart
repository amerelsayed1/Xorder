import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/app.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/router.dart';
import 'package:xorder_pos/core/config/admin_mode_settings.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

const _strings = EnStrings();

const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

const _cashier = PosStaff(
  id: 1,
  name: 'Rana A.',
  username: 'rana',
  role: FakeSessionRepository.cashier,
);

/// Admin Mode, asked of the whole app rather than of one screen — because
/// every promise it makes is about the app: that the till opens without it,
/// that nothing of it is reachable before a username and PIN, that it ends,
/// and that the till is handed back as it was.
///
/// **Written first as the F8 test.** F8 was bound globally and ungated, on the
/// strength of Management asking for a password before any pane showed. It
/// asked only while no password was held, and nothing forgot one — so after a
/// manager had used the back office once, F8 at a locked till opened the staff
/// pane for whoever pressed it.
void main() {
  // The app mounts a native menu bar whose About item exists only on the
  // desktop platforms this ships to; see `settings_bar_test.dart`.
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    PosStaff? atTheTill,
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [...fakeRepositoryOverrides(), ...overrides],
    );
    addTearDown(container.dispose);
    container.read(localeProvider.notifier).apply('en');
    container.read(setupCompleteProvider.notifier).markComplete();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const XorderPosApp(),
      ),
    );
    if (atTheTill != null) {
      container.read(signedInStaffProvider.notifier).signIn(atTheTill);
    }
    await tester.pumpAndSettle();
    return container;
  }

  String location(ProviderContainer container) =>
      container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> signIn(
    WidgetTester tester,
    String username,
    String pin, {
    String? databasePassword,
  }) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('admin-username')),
        matching: find.byType(TextField),
      ),
      username,
    );
    await tester.enterText(find.byKey(const Key('admin-pin')), pin);
    if (databasePassword != null) {
      await tester.enterText(
        find.byKey(const Key('admin-db-password')),
        databasePassword,
      );
    }
    await tester.tap(find.byKey(const Key('admin-open')));
    await tester.pumpAndSettle();
  }

  List<String> ledger(ProviderContainer container) => [
    for (final entry
        in (container.read(auditRepositoryProvider) as FakeAuditRepository)
            .entries
            .reversed)
      entry.action,
  ];

  final door = find.byKey(const Key('admin-username'));
  // Past the door: the tab strip, which is drawn for nobody who is not. Not a
  // pane's contents — the door lands on the first tab that holds a pane, and
  // which that is depends on the till and the person.
  final inside = find.byKey(const Key('back-office-tabs'));

  group('the way in', () {
    testWidgets('F8 no longer opens the back office from a locked till', (
      tester,
    ) async {
      final app = await pumpApp(tester, atTheTill: _owner);
      app.read(routerProvider).go(PosRoutes.lock);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.pumpAndSettle();

      expect(location(app), PosRoutes.lock);
      expect(inside, findsNothing);
    }, variant: desktop);

    testWidgets('the shortcut opens the door and nothing behind it — even for '
        'the owner, signed in at the till, with the password kept', (
      tester,
    ) async {
      final app = await pumpApp(tester, atTheTill: _owner);
      app.read(routerProvider).go(PosRoutes.lock);
      await tester.pumpAndSettle();

      await chord(tester, LogicalKeyboardKey.keyS);

      expect(location(app), PosRoutes.management);
      expect(door, findsOneWidget);
      expect(inside, findsNothing, reason: 'the chord is not a lock');
      expect(app.read(adminDbCredentialProvider), isNull);
    }, variant: desktop);

    testWidgets('the bar offers no back office outside Admin Mode', (
      tester,
    ) async {
      await pumpApp(tester, atTheTill: _owner);
      expect(find.text(_strings.backOffice), findsNothing);
      expect(find.text(_strings.management), findsNothing);
    }, variant: desktop);

    testWidgets('Ctrl+Shift+R is the forced reset now', (tester) async {
      await pumpApp(tester, atTheTill: _owner);
      await chord(tester, LogicalKeyboardKey.keyR);
      expect(find.text(_strings.forceResetSignInTitle), findsOneWidget);
      expect(door, findsNothing);
    }, variant: desktop);

    testWidgets('the shortcut is this till\'s to choose', (tester) async {
      final app = await pumpApp(tester, atTheTill: _owner);
      await app
          .read(adminModeSettingsProvider.notifier)
          .save(const AdminModeSettings(shortcut: AdminShortcut.ctrlShiftA));
      await tester.pumpAndSettle();

      await chord(tester, LogicalKeyboardKey.keyS);
      expect(door, findsNothing, reason: 'the old chord no longer opens it');

      await chord(tester, LogicalKeyboardKey.keyA);
      expect(door, findsOneWidget);
    }, variant: desktop);
  });

  group('inside', () {
    testWidgets('the owner\'s username and PIN open it, and the till keeps '
        'its cashier', (tester) async {
      final app = await pumpApp(tester, atTheTill: _cashier);
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'amer', '4321');

      // The first tab that holds a pane — Sales, since BO-2 — and the header
      // names the page it landed on.
      final landing = backOfficeLanding(
        backOfficeTabsFor(admin: _owner, authorsItsOwnCatalogue: false),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('back-office-title'))).data,
        _strings.adminTitle(managementPaneLabel(_strings, landing).$1),
      );
      expect(find.byKey(const Key('admin-exit')), findsOneWidget);
      expect(inside, findsOneWidget);
      expect(app.read(adminSessionProvider)!.staff.username, 'amer');
      expect(
        app.read(signedInStaffProvider)!.username,
        'rana',
        reason: 'entering Admin Mode is not taking over the till',
      );
      expect(ledger(app), contains(AuditAction.adminEntered));
    }, variant: desktop);

    testWidgets('the bar shows the back office only while in it', (
      tester,
    ) async {
      await pumpApp(tester, atTheTill: _cashier);
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'amer', '4321');
      // The bar's first menu is the strip's first word since the owner's map
      // (14 Sep 2026) — Home, asked of the bar rather than of the screen,
      // where the strip says it too.
      final home = find.descendant(
        of: find.byType(MenuBar),
        matching: find.text(_strings.tabHome),
      );
      expect(home, findsOneWidget);

      await tester.tap(find.byKey(const Key('admin-exit')));
      await tester.pumpAndSettle();
      expect(home, findsNothing);
    }, variant: desktop);

    testWidgets('Exit returns to where the till was, and forgets everything', (
      tester,
    ) async {
      final app = await pumpApp(tester, atTheTill: _cashier);
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'amer', '4321');
      expect(app.read(adminDbCredentialProvider), 'test-credential');

      await tester.tap(find.byKey(const Key('admin-exit')));
      await tester.pumpAndSettle();

      expect(location(app), PosRoutes.start);
      expect(app.read(adminSessionProvider), isNull);
      expect(app.read(adminDbCredentialProvider), isNull);
      expect(app.read(signedInStaffProvider)!.username, 'rana');
      expect(ledger(app).last, AuditAction.adminExited);

      // And the chord asks again: nothing about the last visit carries over.
      await chord(tester, LogicalKeyboardKey.keyS);
      expect(door, findsOneWidget);
    }, variant: desktop);

    testWidgets('locking the till ends Admin Mode', (tester) async {
      final app = await pumpApp(tester, atTheTill: _cashier);
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'amer', '4321');

      app.read(routerProvider).go(PosRoutes.lock);
      await tester.pumpAndSettle();

      expect(app.read(adminSessionProvider), isNull);
      expect(app.read(adminDbCredentialProvider), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await chord(tester, LogicalKeyboardKey.keyS);
      expect(inside, findsNothing);
      expect(door, findsOneWidget);
    }, variant: desktop);
  });

  group('who is refused', () {
    testWidgets('a cashier with their right PIN, and the ledger says so', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'rana', '1234');

      expect(find.text(_strings.adminSignInAttemptsLeft(4)), findsOneWidget);
      expect(inside, findsNothing);
      expect(ledger(app), [AuditAction.adminRefused]);
    }, variant: desktop);

    testWidgets('a wrong PIN, in the same words, naming nobody', (tester) async {
      final app = await pumpApp(tester);
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'amer', '0000');

      expect(find.text(_strings.adminSignInAttemptsLeft(4)), findsOneWidget);
      expect(ledger(app), isEmpty);
    }, variant: desktop);

    testWidgets('five wrong PINs shut the door for a while, and it says so', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 9, 12, 20);
      await pumpApp(
        tester,
        overrides: [adminClockProvider.overrideWithValue(() => now)],
      );
      await chord(tester, LogicalKeyboardKey.keyS);
      for (var i = 0; i < 4; i++) {
        await signIn(tester, 'amer', '0000');
      }
      expect(find.text(_strings.adminSignInAttemptsLeft(1)), findsOneWidget);

      await signIn(tester, 'amer', '0000');
      expect(find.text(_strings.adminSignInLockedOut(30)), findsOneWidget);

      // The owner's own PIN, and the door still shut: while it is, nothing is
      // checked, so a guess is not a guess.
      await signIn(tester, 'amer', '4321');
      expect(inside, findsNothing);
      expect(find.text(_strings.adminSignInLockedOut(30)), findsOneWidget);
    }, variant: desktop);

    testWidgets('somebody the owner let in through Roles gets in — and only as '
        'far as their role goes', (tester) async {
      // Offline, where Purchasing is a tab only for somebody who buys. On a
      // cloud till Inventory and Purchasing stay as pointers to the platform
      // for everyone in the back office (CB-09), so their presence there would
      // say nothing about Nour's role.
      await pumpApp(tester, overrides: [offlineTerminal()]);
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'nour', '2468');

      expect(inside, findsOneWidget);
      expect(find.byKey(const Key('back-office-tab-purchasing')), findsNothing);
      expect(find.byKey(const Key('back-office-tab-inventory')), findsNothing);
    }, variant: desktop);
  });

  group('the timeout', () {
    testWidgets('left alone for the timeout, it locks itself', (tester) async {
      var now = DateTime.utc(2026, 9, 12, 20);
      final app = await pumpApp(
        tester,
        atTheTill: _cashier,
        overrides: [adminClockProvider.overrideWithValue(() => now)],
      );
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'amer', '4321');
      expect(inside, findsOneWidget);

      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();

      expect(inside, findsNothing);
      expect(find.byKey(const Key('admin-locked')), findsOneWidget);
      expect(door, findsOneWidget);
      expect(app.read(adminDbCredentialProvider), isNull);
      expect(ledger(app).last, AuditAction.adminTimedOut);
    }, variant: desktop);

    testWidgets('somebody still working keeps it open', (tester) async {
      var now = DateTime.utc(2026, 9, 12, 20);
      await pumpApp(
        tester,
        atTheTill: _cashier,
        overrides: [adminClockProvider.overrideWithValue(() => now)],
      );
      await chord(tester, LogicalKeyboardKey.keyS);
      await signIn(tester, 'amer', '4321');

      now = now.add(const Duration(minutes: 4));
      await tester.pump(const Duration(minutes: 4));
      await tester.tap(find.byType(Scaffold).last, warnIfMissed: false);
      await tester.pump();

      now = now.add(const Duration(minutes: 4));
      await tester.pump(const Duration(minutes: 4));
      await tester.pumpAndSettle();

      expect(inside, findsOneWidget, reason: 'eight minutes, but not idle');
    }, variant: desktop);
  });

  testWidgets('a till installed before Admin Mode asks for the back-office '
      'password once, then keeps it', (tester) async {
    final kept = MemorySecretStore();
    final app = await pumpApp(
      tester,
      overrides: [adminDbSecretStoreProvider.overrideWithValue(kept)],
    );
    await chord(tester, LogicalKeyboardKey.keyS);

    await signIn(tester, 'amer', '4321');
    expect(find.byKey(const Key('admin-db-password')), findsOneWidget);
    expect(inside, findsNothing);

    await signIn(tester, 'amer', '4321', databasePassword: 'not-it');
    expect(find.text(_strings.adminDatabasePasswordRefused), findsOneWidget);
    expect(kept.value, isNull, reason: 'tried before it is kept');

    await signIn(tester, 'amer', '4321', databasePassword: 'test-credential');
    expect(inside, findsOneWidget);
    expect(kept.value, 'test-credential');
    expect(app.read(adminSessionProvider)!.staff.can(PosCapability.adminEnter), isTrue);
  }, variant: desktop);
}
