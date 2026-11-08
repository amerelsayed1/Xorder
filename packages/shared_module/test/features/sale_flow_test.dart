import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:flutter/services.dart';
import 'package:shared_module/domain/models/dining_table.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/floor/floor_screen.dart';
import 'package:shared_module/features/payment/payment_screen.dart';
import 'package:shared_module/features/sale/sale_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// A desktop-sized surface. The three-pane shell only exists above 1100dp, so
/// testing it at the default 800×600 would exercise a shell the design does not
/// consider primary.
const _desktop = Size(1440, 900);

Future<void> _pumpDesktop(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = _desktop
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: fakeRepositoryOverrides(),
      child: MaterialApp(theme: buildPosTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the floor lists tables with their live state', (tester) async {
    await _pumpDesktop(
      tester,
      FloorScreen(
        onTablePicked: (_) {},
        onSellWithoutTable: () {},
        onClose: () {},
      ),
    );

    expect(find.text('Pick a table'), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);
    // Seeded from the prototype: T3, T4, T5(bill), T7, T12, T14(bill).
    expect(find.text('FREE 10'), findsOneWidget);
    expect(find.text('OCCUPIED 4'), findsOneWidget);
    expect(find.text('BILL ASKED 2'), findsOneWidget);
  });

  testWidgets('picking a table hands the table back to the caller', (tester) async {
    var picked = '';
    await _pumpDesktop(
      tester,
      FloorScreen(
        onTablePicked: (table) => picked = table.label,
        onSellWithoutTable: () {},
        onClose: () {},
      ),
    );

    await tester.tap(find.text('T3'));
    await tester.pumpAndSettle();

    expect(picked, 'T3');
  });

  testWidgets('the wide shell shows rail, grid and cart together', (tester) async {
    await _pumpDesktop(
      tester,
      SaleScreen(
        onLock: () {},
        onTables: () {},
        onOrders: () {},
      ),
    );

    expect(find.text('CATEGORIES'), findsOneWidget); // rail
    expect(find.text('Mixed Grill Platter'), findsOneWidget); // grid
    expect(find.text('TOTAL'), findsOneWidget); // cart
    expect(find.textContaining('Ticket is empty'), findsOneWidget);
  });

  testWidgets('tapping a plain product puts it on the ticket', (tester) async {
    late WidgetRef capturedRef;

    tester.view
      ..physicalSize = _desktop
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeRepositoryOverrides(),
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Consumer(builder: (context, ref, _) {
            capturedRef = ref;
            return SaleScreen(
        onLock: () {},
        onTables: () {},
        onOrders: () {},
      );
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Soft Drink has no modifier groups, so it must go straight on — an extra
    // confirmation on every drink would cost the cashier real seconds.
    await tester.tap(find.text('Soft Drink'));
    await tester.pumpAndSettle();

    final ticket = capturedRef.read(ticketProvider);
    expect(ticket.lines, hasLength(1));
    expect(ticket.lines.single.product.nameEn, 'Soft Drink');
  });

  group('an order served at a table is charged at one', () {
    Future<({WidgetRef ref, List<String> events})> sell(
      WidgetTester tester,
      OrderType type,
    ) async {
      late WidgetRef capturedRef;
      final events = <String>[];
      tester.view
        ..physicalSize = _desktop
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: fakeRepositoryOverrides(),
          child: MaterialApp(
            theme: buildPosTheme(),
            home: Consumer(builder: (context, ref, _) {
              capturedRef = ref;
              return SaleScreen(
                onLock: () {},
                onTables: () => events.add('tables'),
                onOrders: () {},
              );
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      capturedRef.read(ticketProvider.notifier).setOrderType(type);
      await tester.tap(find.text('Soft Drink'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      return (ref: capturedRef, events: events);
    }

    testWidgets('a dine-in ticket with no table goes to the floor, not to '
        'payment', (tester) async {
      // A dine-in bill with no table on it is one the floor cannot show and
      // the receipt cannot place.
      final sale = await sell(tester, OrderType.dineIn);
      expect(
        sale.ref.read(orderTypeRulesProvider).requiresTable(OrderType.dineIn),
        isTrue,
        reason: 'the precondition: dine-in is served at a table',
      );

      expect(find.byType(PaymentScreen), findsNothing);
      expect(find.textContaining('Choose a table first'), findsOneWidget);
      expect(sale.events, ['tables']);
      expect(
        sale.ref.read(ticketProvider).lines,
        hasLength(1),
        reason: 'the order waits for its table; it is not thrown away',
      );
    });

    testWidgets('a takeaway ticket needs no table', (tester) async {
      final sale = await sell(tester, OrderType.takeaway);

      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(sale.events, isEmpty);
    });

    testWidgets('collecting on a table-less dine-in ticket leaves for the '
        'floor WITH the intent, so the floor can send it on into payment', (
      tester,
    ) async {
      final events = <String>[];
      late WidgetRef capturedRef;
      tester.view
        ..physicalSize = _desktop
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: fakeRepositoryOverrides(),
          child: MaterialApp(
            theme: buildPosTheme(),
            home: Consumer(builder: (context, ref, _) {
              capturedRef = ref;
              return SaleScreen(
                onLock: () {},
                onTables: () => events.add('tables'),
                onTablesToCollect: () => events.add('tables-to-collect'),
                onOrders: () {},
              );
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      capturedRef.read(ticketProvider.notifier).setOrderType(OrderType.dineIn);
      await tester.tap(find.text('Soft Drink'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();

      expect(events, ['tables-to-collect']);
      expect(find.byType(PaymentScreen), findsNothing);
    });

    testWidgets('and opened with that intent, the sale screen goes straight '
        'to payment — the cashier does not press F9 twice', (tester) async {
      // What the floor hands back: the ticket, now takeaway or seated, and
      // the intent it left with. Before this the cashier landed on the sale
      // screen and had to press collect again (16 Oct 2026).
      late WidgetRef capturedRef;
      late StateSetter rebuild;
      var collectOnOpen = false;
      tester.view
        ..physicalSize = _desktop
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: fakeRepositoryOverrides(),
          child: MaterialApp(
            theme: buildPosTheme(),
            home: Consumer(builder: (context, ref, _) {
              capturedRef = ref;
              return StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  // A new key remounts the screen, as arriving from the
                  // floor does; the ticket lives in the container and stays.
                  return SaleScreen(
                    key: ValueKey(collectOnOpen),
                    collectOnOpen: collectOnOpen,
                    onLock: () {},
                    onTables: () {},
                    onOrders: () {},
                  );
                },
              );
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      capturedRef.read(ticketProvider.notifier).setOrderType(OrderType.takeaway);
      await tester.tap(find.text('Soft Drink'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsNothing);

      rebuild(() => collectOnOpen = true);
      await tester.pumpAndSettle();

      expect(find.byType(PaymentScreen), findsOneWidget);
    });
  });

  testWidgets('a product with required modifiers opens the sheet first', (tester) async {
    await _pumpDesktop(
      tester,
      SaleScreen(
        onLock: () {},
        onTables: () {},
        onOrders: () {},
      ),
    );

    await tester.tap(find.text('Mixed Grill Platter'));
    await tester.pumpAndSettle();

    expect(find.text('Add to ticket'), findsOneWidget);
    expect(find.text('REQUIRED · PICK 1'), findsOneWidget);
  });

  testWidgets('an out-of-stock product is refused with an explanation', (tester) async {
    await _pumpDesktop(
      tester,
      SaleScreen(
        onLock: () {},
        onTables: () {},
        onOrders: () {},
      ),
    );

    await tester.tap(find.text('Lamb Chops'));
    await tester.pumpAndSettle();

    expect(find.textContaining("out of stock"), findsOneWidget);
  });

  test('the fake orders repository is idempotent on the ticket id', () async {
    // The server contract (POS-BE-007) says five submissions of one
    // client_transaction_id create exactly one order and return the same body.
    final repository = FakeOrdersRepository();
    final ticket = Ticket(id: 'same-id', orderType: OrderType.takeaway);

    final first = await repository.submit(ticket);
    final replay = await repository.submit(ticket);

    expect(repository.submitted, hasLength(1));
    expect(replay.invoiceNumber, first.invoiceNumber);
    expect(replay.clientTransactionId, first.clientTransactionId);
  });

  testWidgets('a branch with no tables still offers a way to sell', (
    tester,
  ) async {
    var sold = false;
    var closed = false;
    tester.view
      ..physicalSize = _desktop
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(),
          tablesProvider.overrideWith((ref) async => const <DiningTable>[]),
        ],
        child: MaterialApp(
          theme: buildPosTheme(),
          home: FloorScreen(
            onTablePicked: (_) {},
            onSellWithoutTable: () => sold = true,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The dead end this replaces: an empty grid, no words, and no control on
    // the screen at all — a cashier with an open shift and no way forward.
    expect(
      find.textContaining('No tables on this branch yet'),
      findsOneWidget,
    );

    await tester.tap(find.text('Sell without a table'));
    await tester.pumpAndSettle();
    expect(sold, isTrue);

    await tester.tap(find.text('Back to the till'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  group('reaching order history', () {
    Future<bool Function()> pumpTill(
      WidgetTester tester, {
      required Set<String> capabilities,
    }) async {
      var opened = false;
      tester.view
        ..physicalSize = _desktop
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...fakeRepositoryOverrides(),
            signedInStaffProvider.overrideWith(
              () => _StaffHolding(capabilities),
            ),
          ],
          child: MaterialApp(
            theme: buildPosTheme(),
            home: SaleScreen(
              onLock: () {},
              onTables: () {},
              onOrders: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return () => opened;
    }

    testWidgets('a supervisor gets the button and the key', (tester) async {
      final opened = await pumpTill(
        tester,
        capabilities: {PosCapability.operate, PosCapability.orderViewAll},
      );

      expect(find.text('Orders'), findsOneWidget);
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(opened(), isTrue);
    });

    testWidgets('a cashier gets the button too — for their own sales', (
      tester,
    ) async {
      // It used to be hidden: history was all-or-nothing, so a cashier saw
      // everybody's sales or nobody's. It is scoped per person now — without
      // `order.view_all` the list is the cashier's own (`history_scope.dart`,
      // tested there) — so the door opens for anyone who may work the till.
      final opened = await pumpTill(
        tester,
        capabilities: {PosCapability.operate},
      );

      expect(find.text('Orders'), findsOneWidget);
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(opened(), isTrue);
    });

    testWidgets('and F7 opens it for them, not only the button', (
      tester,
    ) async {
      final opened = await pumpTill(
        tester,
        capabilities: {PosCapability.operate},
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(opened(), isTrue);
    });

    testWidgets('F7 is refused for somebody who may not work the till', (
      tester,
    ) async {
      // The gate that matters. A key on a keyboard reaches the handler whether
      // or not a button was drawn, so a check that lived only in the widget
      // tree would be one the shortcut walks straight past.
      final opened = await pumpTill(tester, capabilities: const {});

      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();

      expect(opened(), isFalse);
      expect(
        find.textContaining('permission to see'),
        findsOneWidget,
        reason: 'a key that silently does nothing reads as a broken keyboard',
      );
    });

    testWidgets('F7 opens history for somebody who may look', (tester) async {
      final opened = await pumpTill(
        tester,
        capabilities: {PosCapability.operate, PosCapability.orderViewAll},
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(opened(), isTrue);
    });
  });

}

/// A signed-in person holding exactly the capabilities a test names.
class _StaffHolding extends SignedInStaffController {
  _StaffHolding(this.capabilities);

  final Set<String> capabilities;

  @override
  PosStaff? build() =>
      PosStaff(id: 4, name: 'Nour Adel', capabilities: capabilities);
}
