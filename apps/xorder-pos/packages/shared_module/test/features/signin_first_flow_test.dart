import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/app.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/app/router.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/order_type_config.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/lock/lock_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

/// Sign in first, then Home (pos-signin-first-home): through the real app and
/// the real router, with **no shift open**, which is the morning and the end of
/// the night.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPosFonts);

  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  late ProviderContainer container;
  late _Days days;
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
    bool dayOpen = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    days = _Days(open: dayOpen);
    container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        businessDayRepositoryProvider.overrideWithValue(days),
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
    container.read(setupCompleteProvider.notifier).markComplete();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const XorderPosApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(at(), PosRoutes.start);
    visited = [];
    container.read(routerProvider).routerDelegate.addListener(() {
      final path = at();
      if (visited.isEmpty || visited.last != path) visited.add(path);
    });
  }

  Future<void> signIn(
    WidgetTester tester, {
    String name = 'rana',
    String pin = '1234',
  }) async {
    await tester.tap(find.byKey(const Key('start-sign-in')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
    for (final digit in pin.split('')) {
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

  testWidgets('signing in with no shift open lands on Home, with Start shift '
      'and no drawer', (tester) async {
    await pumpTill(tester);
    await signIn(tester);

    expect(at(), PosRoutes.home);
    expect(find.byKey(const Key('home-start-shift')), findsOneWidget);
    expect(await container.read(shiftRepositoryProvider).current(), isNull);
    await finish(tester);
  }, variant: desktop);

  testWidgets('a branch that sells one way still sees Home before it has a '
      'shift, and starting one goes straight to selling', (tester) async {
    await pumpTill(
      tester,
      rules: const OrderTypeRules([
        OrderTypeConfig(type: OrderType.takeaway, nameEn: 'Takeaway'),
      ]),
    );
    await signIn(tester);

    expect(at(), PosRoutes.home);
    expect(find.byKey(const Key('home-type-takeaway')), findsNothing);

    await tester.tap(find.byKey(const Key('home-start-shift')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open shift'));
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.sale);
    expect(container.read(ticketProvider).orderType, OrderType.takeaway);
    expect(await container.read(shiftRepositoryProvider).current(), isNotNull);
    await finish(tester);
  }, variant: desktop);

  testWidgets('a branch with a choice stays on Home after the shift opens, '
      'its buttons now live', (tester) async {
    await pumpTill(tester);
    await signIn(tester);
    await tester.tap(find.byKey(const Key('home-start-shift')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open shift'));
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.home);
    expect(find.byKey(const Key('home-start-shift')), findsNothing);
    await tester.tap(find.byKey(const Key('home-type-takeaway')));
    await tester.pumpAndSettle();
    expect(at(), PosRoutes.sale);
    await finish(tester);
  }, variant: desktop);

  testWidgets('a manager closes the day without ever opening a shift', (
    tester,
  ) async {
    await pumpTill(tester, dayOpen: true);
    await signIn(tester, name: 'amer', pin: '4321');

    expect(at(), PosRoutes.home);
    await tester.tap(find.byKey(const Key('home-close-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close the day').last);
    await tester.pumpAndSettle();

    expect(days.closedBy, [1], reason: 'the manager is the closer');
    expect(await container.read(shiftRepositoryProvider).current(), isNull);
    await finish(tester);
  }, variant: desktop);

  testWidgets('a cashier is never offered Close the day', (tester) async {
    await pumpTill(tester, dayOpen: true);
    await signIn(tester);

    expect(at(), PosRoutes.home);
    expect(find.byKey(const Key('home-close-day')), findsNothing);
    await finish(tester);
  }, variant: desktop);

  testWidgets('Lock or Switch user from Home with no shift open unlocks to '
      'Home — never onto a sale with no drawer', (tester) async {
    await pumpTill(tester);
    await signIn(tester);
    expect(at(), PosRoutes.home);

    // What the account menu's Lock and Switch user do: no `next`.
    container.read(routerProvider).go(PosRoutes.lock);
    await tester.pumpAndSettle();
    expect(at(), PosRoutes.lock);

    tester.widget<LockScreen>(find.byType(LockScreen)).onUnlocked();
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.home);
    expect(visited, isNot(contains(PosRoutes.sale)));
    await finish(tester);
  }, variant: desktop);

  testWidgets('Lock at the sale screen with a shift open still unlocks to the '
      'sale', (tester) async {
    await pumpTill(tester);
    await signIn(tester);
    await tester.tap(find.byKey(const Key('home-start-shift')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-type-takeaway')));
    await tester.pumpAndSettle();
    expect(at(), PosRoutes.sale);

    container.read(routerProvider).go(PosRoutes.lock);
    await tester.pumpAndSettle();
    tester.widget<LockScreen>(find.byType(LockScreen)).onUnlocked();
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.sale);
    await finish(tester);
  }, variant: desktop);

  testWidgets('Sign out on Home returns to Start, signed out', (tester) async {
    await pumpTill(tester);
    await signIn(tester);

    await tester.tap(find.byKey(const Key('home-sign-out')));
    await tester.pumpAndSettle();

    expect(at(), PosRoutes.start);
    expect(container.read(signedInStaffProvider), isNull);
    expect(visited, isNot(contains(PosRoutes.lock)));
    await finish(tester);
  }, variant: desktop);
}

class _Days implements BusinessDayRepository {
  _Days({required bool open}) : _day = open ? _today : null;

  static final _today = BusinessDay(
    id: 1,
    date: DateTime(2026, 10, 26),
    openedAt: DateTime(2026, 10, 26, 6),
  );

  BusinessDay? _day;
  final closedBy = <int>[];

  @override
  Future<BusinessDay?> current() async => _day;

  @override
  Future<BusinessDay?> lastClosed({DateTime? before}) async => null;

  @override
  Future<DayCloseCheck> check() async =>
      DayCloseCheck(day: _day!, blockers: const []);

  @override
  Future<BusinessDay> open({
    required DateTime date,
    required PosStaff by,
  }) async => _day = BusinessDay(id: 2, date: date, openedAt: date);

  @override
  Future<BusinessDay> close({
    required BusinessDay day,
    required PosStaff by,
    bool force = false,
    String? forceReason,
  }) async {
    closedBy.add(by.id);
    _day = null;
    return day;
  }
}
