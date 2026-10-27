import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/app.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/router.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/order_type_config.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/floor/floor_screen.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/lock/lock_screen.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

const _rana = PosStaff(
  id: 1,
  name: 'Rana A.',
  username: 'rana',
  role: FakeSessionRepository.cashier,
);

OrderTypeRules _only(List<OrderType> types) => OrderTypeRules([
  for (final type in types)
    OrderTypeConfig(
      type: type,
      nameEn: type.wire,
      requiresTable: type == OrderType.dineIn,
    ),
]);

/// After the shift opens (pos-home-screen): Home when the branch sells more
/// than one way, straight on when it sells one, and where each button goes.
///
/// Through the real app and the real router: what is under test is the wiring.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPosFonts);

  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  final openShift = PosShift(
    id: 3,
    openedAt: DateTime(2026, 10, 26, 9),
    openingFloat: const Money(20000),
    openedByName: 'Rana A.',
    openedById: 1,
  );

  late ProviderContainer container;

  /// Every route the till went through, in order: "Home never shows" is a
  /// claim about the way, not only the destination, because Home forwards a
  /// one-type branch by itself and would hide a router that sent it there.
  var visited = <String>[];

  String at() => container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  Future<void> pumpTill(
    WidgetTester tester, {
    OrderTypeRules? rules,
    bool signedIn = true,
    String language = 'en',
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        shiftProvider.overrideWith((ref) async => openShift),
        // A licence that lets a shift open: without one Start refuses.
        licenceEntitlementProvider.overrideWith(
          (ref) async => const LicenseEntitlement(
            state: LicenseState.valid,
            canOpenShift: true,
            canSell: true,
            canChangeConfiguration: true,
          ),
        ),
        if (rules != null)
          orderTypeConfigProvider.overrideWith((ref) async => rules),
      ],
    );
    addTearDown(container.dispose);
    container.read(localeProvider.notifier).apply(language);
    container.read(setupCompleteProvider.notifier).markComplete();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const XorderPosApp(),
      ),
    );
    if (signedIn) container.read(signedInStaffProvider.notifier).signIn(_rana);
    await tester.pumpAndSettle();
    expect(at(), PosRoutes.start);
    visited = [];
    container.read(routerProvider).routerDelegate.addListener(() {
      final path = at();
      if (visited.isEmpty || visited.last != path) visited.add(path);
    });
  }

  /// Sign in at Start, as everybody now does first (pos-signin-first-home): a
  /// name and a PIN, in the dialog Start's button opens. The shift is open in
  /// these tests (a restart, or a morning already begun), so this lands where
  /// the router sends somebody with a shift open.
  Future<void> resume(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('start-sign-in')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rana');
    await tester.pump();
    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text(digit)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('several types: the shift goes to Home, one button each', (
    tester,
  ) async {
    await pumpTill(tester);
    await resume(tester);

    expect(at(), PosRoutes.home);
    for (final wire in ['dine_in', 'takeaway', 'delivery', 'drive_thru']) {
      expect(find.byKey(Key('home-type-$wire')), findsOneWidget, reason: wire);
    }
    await finish(tester);
  }, variant: desktop);

  testWidgets('a type that is not seated starts a sale of that type, with no '
      'table', (tester) async {
    await pumpTill(tester);
    await resume(tester);

    await tester.tap(find.byKey(const Key('home-type-takeaway')));
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.sale);
    final ticket = container.read(ticketProvider);
    expect(ticket.orderType, OrderType.takeaway);
    expect(ticket.tableId, isNull);
    await finish(tester);
  }, variant: desktop);

  testWidgets('a seated type opens the floor, and Back from the floor is '
      'Home', (tester) async {
    await pumpTill(tester);
    await resume(tester);

    await tester.tap(find.byKey(const Key('home-type-dine_in')));
    await tester.pumpAndSettle();
    expect(at(), PosRoutes.floor);

    tester.widget<FloorScreen>(find.byType(FloorScreen)).onClose();
    await tester.pumpAndSettle();
    expect(at(), PosRoutes.home);
    await finish(tester);
  }, variant: desktop);

  testWidgets('one unseated type: straight to the sale, no Home', (
    tester,
  ) async {
    await pumpTill(tester, rules: _only([OrderType.takeaway]));
    await resume(tester);

    expect(at(), PosRoutes.sale);
    expect(visited, isNot(contains(PosRoutes.home)));
    expect(container.read(ticketProvider).orderType, OrderType.takeaway);
    await finish(tester);
  }, variant: desktop);

  testWidgets('one seated type: straight to the floor, whose Back is Start', (
    tester,
  ) async {
    await pumpTill(tester, rules: _only([OrderType.dineIn]));
    await resume(tester);

    expect(at(), PosRoutes.floor);
    expect(visited, isNot(contains(PosRoutes.home)));
    tester.widget<FloorScreen>(find.byType(FloorScreen)).onClose();
    await tester.pumpAndSettle();
    expect(at(), PosRoutes.start, reason: 'there is no Home to go back to');
    await finish(tester);
  }, variant: desktop);

  testWidgets('two types and nothing seated: Home, not the floor', (
    tester,
  ) async {
    await pumpTill(
      tester,
      rules: _only([OrderType.takeaway, OrderType.delivery]),
    );
    await resume(tester);

    expect(at(), PosRoutes.home);
    expect(find.byKey(const Key('home-type-dine_in')), findsNothing);
    await finish(tester);
  }, variant: desktop);

  testWidgets('Home with nobody signed in is Start, never the lock screen', (
    tester,
  ) async {
    await pumpTill(tester, signedIn: false);

    container.read(routerProvider).go(PosRoutes.home);
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.start);
    expect(visited, isNot(contains(PosRoutes.lock)));
    await finish(tester);
  }, variant: desktop);

  testWidgets('in Arabic the buttons carry the Arabic names', (tester) async {
    await pumpTill(tester, language: 'ar');
    container.read(routerProvider).go(PosRoutes.home);
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.home);
    expect(find.text('صالة'), findsOneWidget);
    expect(find.text('تيك أواي'), findsOneWidget);
    await finish(tester);
  }, variant: desktop);

  testWidgets('a restart with the shift still open: sign in at Start, and '
      'Home — no lock screen on the way', (tester) async {
    await pumpTill(tester, signedIn: false);
    await resume(tester);

    expect(at(), PosRoutes.home);
    expect(visited, isNot(contains(PosRoutes.lock)));
    expect(container.read(signedInStaffProvider)?.name, 'Rana A.');
    await finish(tester);
  }, variant: desktop);

  testWidgets('Lock pressed at the till is not a resume: unlocking goes back '
      'to the sale, as it always did', (tester) async {
    await pumpTill(tester);
    container.read(routerProvider).go(PosRoutes.sale);
    await tester.pumpAndSettle();

    container.read(routerProvider).go(PosRoutes.lock);
    await tester.pumpAndSettle();
    tester.widget<LockScreen>(find.byType(LockScreen)).onUnlocked();
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.sale);
    await finish(tester);
  }, variant: desktop);

  group('the lock screen remembers where the till was heading', () {
    test('a selling screen is returned to; anything else is the sale', () {
      expect(unlockTarget(PosRoutes.home), PosRoutes.home);
      expect(unlockTarget(PosRoutes.floor), PosRoutes.floor);
      expect(unlockTarget(PosRoutes.sale), PosRoutes.sale);
      expect(unlockTarget(null), PosRoutes.sale);
      expect(unlockTarget(PosRoutes.orders), PosRoutes.sale);
      expect(unlockTarget(PosRoutes.management), PosRoutes.sale);
      expect(unlockTarget('https://example.com'), PosRoutes.sale);
      expect(unlockTarget('/home/../management'), PosRoutes.sale);
    });

    test('the location carries the screen and survives a round trip', () {
      final uri = Uri.parse(lockLocationFrom(PosRoutes.home));
      expect(uri.path, PosRoutes.lock);
      expect(unlockTarget(uri.queryParameters['next']), PosRoutes.home);
    });
  });

  group('the floor drops its two header buttons where Home replaces them', () {
    final sell = const EnStrings().sellWithoutTable;
    final back = const EnStrings().backToTill;

    testWidgets('a branch with Home: neither button, Escape is the way back', (
      tester,
    ) async {
      await pumpTill(tester);
      await resume(tester);
      await tester.tap(find.byKey(const Key('home-type-dine_in')));
      await tester.pumpAndSettle();

      expect(at(), PosRoutes.floor);
      expect(find.text(sell), findsNothing);
      expect(find.text(back), findsNothing);
      await finish(tester);
    }, variant: desktop);

    testWidgets('one way of selling, seated: the Floor is the entry, so both '
        'stay', (tester) async {
      await pumpTill(tester, rules: _only([OrderType.dineIn]));
      await resume(tester);

      expect(at(), PosRoutes.floor);
      expect(find.text(sell), findsOneWidget);
      expect(find.text(back), findsOneWidget);
      await finish(tester);
    }, variant: desktop);
  });

  group('Escape is back, one step along the way', () {
    testWidgets('floor → Home', (tester) async {
      await pumpTill(tester);
      await resume(tester);
      await tester.tap(find.byKey(const Key('home-type-dine_in')));
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.floor);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.home);
      await finish(tester);
    }, variant: desktop);

    testWidgets('Home → Start, where the shift was resumed', (tester) async {
      await pumpTill(tester);
      await resume(tester);
      expect(at(), PosRoutes.home);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.start);
      await finish(tester);
    }, variant: desktop);

    testWidgets('sale of a type that is not seated → Home', (tester) async {
      await pumpTill(tester);
      await resume(tester);
      await tester.tap(find.byKey(const Key('home-type-takeaway')));
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.sale);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.home);
      await finish(tester);
    }, variant: desktop);

    testWidgets('a typed search is cleared first; the next Escape steps back', (
      tester,
    ) async {
      await pumpTill(tester);
      await resume(tester);
      await tester.tap(find.byKey(const Key('home-type-takeaway')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f2); // the search box
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'cola');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.sale, reason: 'the first Escape only clears');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.home);
      await finish(tester);
    }, variant: desktop);

    testWidgets('a seated bill → the floor, parked on its table, never '
        'converted or lost', (tester) async {
      await pumpTill(tester);
      await resume(tester);
      await tester.tap(find.byKey(const Key('home-type-dine_in')));
      await tester.pumpAndSettle();

      // Seat the ticket and put something on it, as the floor and the menu do.
      final tables = await tester.runAsync(
        () => container.read(floorTablesProvider.future),
      );
      container.read(ticketProvider.notifier).attachTable(tables!.first);
      container.read(routerProvider).go(PosRoutes.sale);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Soft Drink'));
      await tester.pumpAndSettle();
      expect(container.read(ticketProvider).isSeated, isTrue);
      expect(container.read(ticketProvider).lines, isNotEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(at(), PosRoutes.floor, reason: 'one step back, not two');
      expect(
        container.read(ticketProvider).lines,
        isEmpty,
        reason: 'the live ticket cleared; the bill is on the table',
      );
      expect(
        container.read(openTicketsProvider.notifier).at(tables.first.id),
        isNotNull,
        reason: 'parked on its table',
      );
      await finish(tester);
    }, variant: desktop);

    testWidgets('one way of selling, seated: floor → Start', (tester) async {
      await pumpTill(tester, rules: _only([OrderType.dineIn]));
      await resume(tester);
      expect(at(), PosRoutes.floor);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.start, reason: 'what its back button does');
      await finish(tester);
    }, variant: desktop);

    testWidgets('one way of selling, not seated: the sale has nothing before '
        'it, so Escape stays', (tester) async {
      await pumpTill(tester, rules: _only([OrderType.takeaway]));
      await resume(tester);
      expect(at(), PosRoutes.sale);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.sale);
      await finish(tester);
    }, variant: desktop);

    testWidgets('the licence screen → Start', (tester) async {
      await pumpTill(tester);
      container.read(routerProvider).go(PosRoutes.licence);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.licence);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(at(), PosRoutes.start);
      await finish(tester);
    }, variant: desktop);
  });
}
