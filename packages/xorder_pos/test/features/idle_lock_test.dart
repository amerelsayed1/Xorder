import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/router.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/lock/idle_lock.dart';
import 'package:xorder_pos/features/lock/lock_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// Five minutes with nobody at the till, and it locks (ADR-006).
///
/// There was no such thing: a cashier who walked away left the drawer's
/// shift, the discount key and the refund screen to whoever walked up. Each
/// test here moves the till's clock and the test's timers together, so five
/// minutes pass in a moment, and asserts where the till ended up and who is
/// still signed in.
void main() {
  late DateTime now;
  late ProviderContainer container;
  late GoRouter router;

  const rana = PosStaff(
    id: 1,
    name: 'Rana A.',
    username: 'rana',
    role: FakeSessionRepository.cashier,
  );
  const amer = PosStaff(
    id: 2,
    name: 'Amer M.',
    username: 'amer',
    role: FakeSessionRepository.owner,
  );

  final openShift = PosShift(
    id: 3,
    openedAt: DateTime(2026, 10, 25, 9),
    openingFloat: const Money(20000),
    openedByName: 'Rana A.',
    openedById: 1,
  );

  /// The till as the idle lock sees it, behind a router of placeholder
  /// screens: what is under test is where it goes, not what is drawn there.
  Future<void> pumpTill(
    WidgetTester tester, {
    String at = PosRoutes.sale,
    PosStaff? signedIn = rana,
    bool shiftOpen = true,
    bool configured = true,
    List<Override> overrides = const [],
  }) async {
    now = DateTime.utc(2026, 10, 25, 20);
    router = GoRouter(
      initialLocation: at,
      routes: [
        for (final path in const [
          PosRoutes.start,
          PosRoutes.lock,
          PosRoutes.sale,
          PosRoutes.home,
          PosRoutes.floor,
          PosRoutes.orders,
          PosRoutes.management,
          PosRoutes.welcome,
          PosRoutes.setup,
        ])
          GoRoute(
            path: path,
            builder: (_, state) => Text(
              state.extra == LockReason.inactivity ? '$path idle' : path,
              textDirection: TextDirection.ltr,
            ),
          ),
      ],
    );

    container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        tillClockProvider.overrideWithValue(() => now),
        setupCompleteProvider.overrideWith(
          () => configured ? _Configured() : _Unconfigured(),
        ),
        shiftProvider.overrideWith((ref) async => shiftOpen ? openShift : null),
        routerProvider.overrideWithValue(router),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await container.read(shiftProvider.future);
    if (signedIn != null) {
      container.read(signedInStaffProvider.notifier).signIn(signedIn);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => TillIdleLock(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The till's clock and the test's timers, moved together.
  Future<void> wait(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(d);
    await tester.pumpAndSettle();
  }

  String location() => router.routerDelegate.currentConfiguration.uri.path;

  testWidgets('five idle minutes sign the cashier out and lock the till', (
    tester,
  ) async {
    await pumpTill(tester);

    await wait(tester, const Duration(minutes: 4, seconds: 59));
    expect(location(), PosRoutes.sale, reason: 'not a second early');
    expect(container.read(signedInStaffProvider), isNotNull);

    await wait(tester, const Duration(seconds: 1));
    expect(location(), PosRoutes.lock);
    expect(container.read(signedInStaffProvider), isNull);
    // And the lock screen is told why, so it can say so.
    expect(find.text('${PosRoutes.lock} idle'), findsOneWidget);
  });

  testWidgets('five idle minutes on the home screen sign the till out and '
      'return to Start — Home is nobody\'s once nobody is signed in', (
    tester,
  ) async {
    await pumpTill(tester, at: PosRoutes.home);

    await wait(tester, const Duration(minutes: 4, seconds: 59));
    expect(location(), PosRoutes.home, reason: 'not a second early');

    await wait(tester, const Duration(seconds: 1));
    expect(location(), PosRoutes.start);
    expect(container.read(signedInStaffProvider), isNull);
  });

  testWidgets('a key resets the clock — the sale screen is driven by them', (
    tester,
  ) async {
    await pumpTill(tester);

    await wait(tester, const Duration(minutes: 4));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await wait(tester, const Duration(minutes: 4));
    expect(location(), PosRoutes.sale);
    expect(container.read(signedInStaffProvider), isNotNull);

    await wait(tester, const Duration(minutes: 1));
    expect(location(), PosRoutes.lock, reason: 'five minutes after the key');
  });

  testWidgets('and so does a touch', (tester) async {
    await pumpTill(tester);

    await wait(tester, const Duration(minutes: 4));
    await tester.tapAt(const Offset(20, 20));
    await wait(tester, const Duration(minutes: 4));
    expect(location(), PosRoutes.sale);
    expect(container.read(signedInStaffProvider), isNotNull);
  });

  testWidgets('the ticket on screen survives the lock, id and lines', (
    tester,
  ) async {
    await pumpTill(tester);
    final tickets = container.read(ticketProvider.notifier);
    expect(
      tickets.addProduct(
        const Product(
          id: 101,
          categoryId: 1,
          nameEn: 'Burger',
          price: Money(9500),
        ),
      ),
      isTrue,
    );
    final before = container.read(ticketProvider);

    await wait(tester, tillIdleTimeout);
    expect(location(), PosRoutes.lock);

    final after = container.read(ticketProvider);
    expect(
      after.id,
      before.id,
      reason: 'reset() mints a new id; locking must not',
    );
    expect(after.lines, hasLength(1));
    expect(after.lines.single.product.nameEn, 'Burger');

    // Today's policy, pinned so a change to it is a decision rather than an
    // accident: somebody else signing in carries on the same ticket.
    container.read(signedInStaffProvider.notifier).signIn(amer);
    expect(container.read(ticketProvider).id, before.id);
    expect(container.read(ticketProvider).lines, hasLength(1));
  });

  testWidgets('nobody signed in, nothing to lock', (tester) async {
    await pumpTill(tester, signedIn: null);

    await wait(tester, tillIdleTimeout);
    expect(location(), PosRoutes.sale, reason: 'the idle lock went nowhere');
  });

  testWidgets('not on a till that is not set up', (tester) async {
    await pumpTill(tester, at: PosRoutes.welcome, configured: false);

    await wait(tester, tillIdleTimeout);
    expect(location(), PosRoutes.welcome);
    expect(container.read(signedInStaffProvider), isNotNull);
  });

  testWidgets('not while a payment is part-way through', (tester) async {
    await pumpTill(tester);
    const payment = Object();
    container.read(idleLockGuardProvider).hold(payment);

    await wait(tester, tillIdleTimeout + const Duration(minutes: 1));
    expect(location(), PosRoutes.sale);
    expect(container.read(signedInStaffProvider), isNotNull);

    // Settled, and nobody touches anything after: locked within moments,
    // not a whole timeout later.
    container.read(idleLockGuardProvider).release(payment);
    await wait(tester, TillIdleLock.heldRetry);
    expect(location(), PosRoutes.lock);
    expect(container.read(signedInStaffProvider), isNull);
  });

  testWidgets('the order history locks too while a shift is open', (
    tester,
  ) async {
    await pumpTill(tester, at: PosRoutes.orders);

    await wait(tester, tillIdleTimeout);
    expect(location(), PosRoutes.lock);
  });

  testWidgets('with no shift open it signs out and stays put', (tester) async {
    await pumpTill(tester, at: PosRoutes.start, shiftOpen: false);

    await wait(tester, tillIdleTimeout);
    expect(location(), PosRoutes.start);
    expect(container.read(signedInStaffProvider), isNull);
  });

  testWidgets('Admin Mode keeps its own clock; the till waits for it', (
    tester,
  ) async {
    await pumpTill(tester, at: PosRoutes.management);

    await wait(tester, tillIdleTimeout + const Duration(minutes: 1));
    expect(location(), PosRoutes.management);
    expect(container.read(signedInStaffProvider), isNotNull);

    // Admin Mode timed out and went back to the till: nobody has touched
    // anything, so the till locks at the next look.
    router.go(PosRoutes.sale);
    await tester.pumpAndSettle();
    await wait(tester, TillIdleLock.heldRetry);
    expect(location(), PosRoutes.lock);
  });

  testWidgets('the timeout is the constant, injectable for a test', (
    tester,
  ) async {
    expect(tillIdleTimeout, const Duration(minutes: 5));
    await pumpTill(
      tester,
      overrides: [
        tillIdleTimeoutProvider.overrideWithValue(const Duration(seconds: 30)),
      ],
    );

    await wait(tester, const Duration(seconds: 30));
    expect(location(), PosRoutes.lock);
  });
}

class _Configured extends SetupCompletionController {
  @override
  bool build() => true;
}

class _Unconfigured extends SetupCompletionController {
  @override
  bool build() => false;
}
