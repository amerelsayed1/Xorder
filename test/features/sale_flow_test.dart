import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:flutter/services.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/floor/floor_screen.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import '../support/fakes.dart';

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
        onCloseShift: () {},
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
        onCloseShift: () {},
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

  testWidgets('a product with required modifiers opens the sheet first', (tester) async {
    await _pumpDesktop(
      tester,
      SaleScreen(
        onLock: () {},
        onTables: () {},
        onOrders: () {},
        onCloseShift: () {},
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
        onCloseShift: () {},
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
              onCloseShift: () {},
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

    testWidgets('a cashier is not shown a control they cannot use', (
      tester,
    ) async {
      await pumpTill(tester, capabilities: {PosCapability.operate});
      // Hidden, not greyed. A control that is dead for a cashier's whole shift
      // is clutter in a rail they use all day.
      expect(find.text('Orders'), findsNothing);
    });

    testWidgets('F7 is refused for a cashier, not merely undrawn', (
      tester,
    ) async {
      // The gate that matters. A key on a keyboard reaches the handler whether
      // or not a button was drawn, so a check that lived only in the widget
      // tree would be one the shortcut walks straight past.
      final opened = await pumpTill(
        tester,
        capabilities: {PosCapability.operate},
      );

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
