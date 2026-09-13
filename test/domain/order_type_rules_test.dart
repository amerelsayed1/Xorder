import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/order_type_config.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

/// What a kind of order requires (§31).
///
/// This wave exists to delete one comparison — `type == OrderType.dineIn` —
/// from three files where what it actually meant was *"does this kind of order
/// have a table"*. The tests that matter are the ones where those two answers
/// differ, which is a restaurant that seats something other than dine-in.
void main() {
  const product = Product(
    id: 1,
    categoryId: 1,
    nameEn: 'Grill',
    price: Money(10000),
  );

  Ticket seated() => TicketEngine.attachTable(
    TicketEngine.addLine(
      Ticket(id: 'txn-1', orderType: OrderType.dineIn),
      product,
    ).ticket!,
    7,
    'T7',
    guests: 2,
  );

  group('the seeded four', () {
    const rules = OrderTypeRules.fallback;

    test('only dine-in has tables', () {
      expect(rules.requiresTable(OrderType.dineIn), isTrue);
      for (final type in [
        OrderType.takeaway,
        OrderType.delivery,
        OrderType.driveThru,
      ]) {
        expect(rules.requiresTable(type), isFalse, reason: type.wire);
      }
    });

    test('delivery wants a customer and an address', () {
      expect(rules.requiresCustomer(OrderType.delivery), isTrue);
      expect(rules.requiresAddress(OrderType.delivery), isTrue);
      expect(rules.requiresCustomer(OrderType.takeaway), isFalse);
    });

    test('the branch has seating', () {
      expect(rules.hasSeating, isTrue);
    });

    test('a type nobody configured is treated as unseated', () {
      // The safe direction: a ticket that wrongly keeps a table sends a
      // cashier to a floor plan that does not have it.
      const empty = OrderTypeRules([]);
      expect(empty.requiresTable(OrderType.dineIn), isFalse);
      expect(empty.hasSeating, isFalse);
    });
  });

  group('a restaurant that seats something else', () {
    // The case the hardcoded comparison could not express: catering is seated
    // and is not dine-in; this branch does no dine-in at all.
    const rules = OrderTypeRules([
      OrderTypeConfig(
        type: OrderType.driveThru,
        nameEn: 'Catering',
        requiresTable: true,
      ),
      OrderTypeConfig(type: OrderType.takeaway, nameEn: 'Counter'),
    ]);

    test('it still has seating', () {
      expect(rules.hasSeating, isTrue);
      expect(rules.requiresTable(OrderType.driveThru), isTrue);
    });

    test('and dine-in, which it does not sell, does not', () {
      expect(rules.requiresTable(OrderType.dineIn), isFalse);
    });

    test('an inactive seated type does not give the branch a floor', () {
      const retired = OrderTypeRules([
        OrderTypeConfig(
          type: OrderType.dineIn,
          nameEn: 'Dine in',
          requiresTable: true,
          isActive: false,
        ),
      ]);
      expect(retired.hasSeating, isFalse);
    });
  });

  group('switching type detaches the table, or does not', () {
    test('moving to an unseated type drops it', () {
      final moved = TicketEngine.setOrderType(seated(), OrderType.takeaway);
      expect(moved.tableId, isNull);
      expect(moved.tableLabel, isNull);
    });

    test('moving to another seated type keeps it', () {
      // The behaviour the old comparison made impossible: dine-in to catering,
      // both seated, same table.
      final moved = TicketEngine.setOrderType(
        seated(),
        OrderType.driveThru,
        seated: true,
      );
      expect(moved.tableId, 7);
      expect(moved.tableLabel, 'T7');
    });

    test('the engine defaults to dropping it', () {
      // Pure and configuration-free: a caller that does not say assumes the
      // safer answer, which is to ask the cashier to pick a table again rather
      // than to keep one the new type may not have.
      final moved = TicketEngine.setOrderType(seated(), OrderType.driveThru);
      expect(moved.tableId, isNull);
    });

    test('switching to the same type changes nothing', () {
      final same = TicketEngine.setOrderType(seated(), OrderType.dineIn);
      expect(same.tableId, 7);
    });
  });

  test('the seeded config matches what migration 25 writes', () {
    // Two definitions of "what a restaurant starts with" is how a fresh
    // install and a migrated one end up different.
    expect(
      OrderTypeConfig.seeded.map((c) => c.type.wire),
      ['dine_in', 'takeaway', 'delivery', 'drive_thru'],
    );
    expect(
      OrderTypeConfig.seeded.where((c) => c.requiresTable).map((c) => c.type),
      [OrderType.dineIn],
    );
    expect(
      OrderTypeConfig.seeded
          .where((c) => c.requiresAddress)
          .map((c) => c.type),
      [OrderType.delivery],
    );
  });
}
