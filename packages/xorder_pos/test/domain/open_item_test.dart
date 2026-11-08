import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

/// Charging for something that is not on the menu (§17).
///
/// The claim doing the work: a one-off charge is an **ordinary line**. It is
/// taxed, discounted, voided and printed like any other, because the only
/// unusual thing about it is that no menu item is behind it.
void main() {
  final now = DateTime(2026, 9, 8, 13);

  const grill = Product(
    id: 101,
    categoryId: 11,
    nameEn: 'Mixed Grill',
    price: Money(5000),
  );

  Ticket ticket({TaxConfig? tax, OrderType type = OrderType.takeaway}) =>
      Ticket(
        id: 'txn-1',
        orderType: type,
        taxConfig: tax ?? const TaxConfig(serviceBp: 0, vatBp: 0),
      );

  Ticket ok(TicketResult result) {
    expect(result.refusal, isNull, reason: '${result.refusal.runtimeType}');
    return result.ticket!;
  }

  group('adding one', () {
    test('becomes a line at the price that was typed', () {
      final after = ok(
        TicketEngine.addOpenPriceLine(
          ticket(),
          name: 'Delivery',
          price: const Money(3000),
        ),
      );

      expect(after.lines.single.product.nameEn, 'Delivery');
      expect(after.lines.single.unitPrice.minor, 3000);
      expect(after.totals.subtotal.minor, 3000);
    });

    test('carries a quantity', () {
      final after = ok(
        TicketEngine.addOpenPriceLine(
          ticket(),
          name: 'Corkage',
          price: const Money(2500),
          quantity: 3,
        ),
      );
      expect(after.lines.single.quantity, 3);
      expect(after.totals.subtotal.minor, 7500);
    });

    test('is taxed like anything else', () {
      // It is not a fee bolted on outside the bill. 100.00 with 10% service and
      // 14% VAT is 100 + 10 + 15.40.
      final after = ok(
        TicketEngine.addOpenPriceLine(
          // Dine-in, because service is dine-in only by default — which is
          // itself worth knowing: a delivery fee on a takeaway ticket attracts
          // VAT and no service, exactly as the food does.
          ticket(
            type: OrderType.dineIn,
            tax: const TaxConfig(serviceBp: 1000, vatBp: 1400),
          ),
          name: 'Birthday cake',
          price: const Money(10000),
        ),
      );
      expect(after.totals.service.minor, 1000);
      expect(after.totals.vat.minor, 1540);
      expect(after.totals.total.minor, 12540);
    });

    test('names itself as having no menu item behind it', () {
      final after = ok(
        TicketEngine.addOpenPriceLine(
          ticket(),
          name: 'Delivery',
          price: const Money(3000),
        ),
      );
      // The flag, not a convention about the id — `menu_item_id` is written
      // NULL off the back of this.
      expect(after.lines.single.product.isOpenPrice, isTrue);
      expect(after.lines.single.product.id, isNegative);
    });

    test('the name is trimmed', () {
      final after = ok(
        TicketEngine.addOpenPriceLine(
          ticket(),
          name: '  Delivery  ',
          price: const Money(1000),
        ),
      );
      expect(after.lines.single.product.nameEn, 'Delivery');
    });

    test('zero is allowed — a comped extra still belongs on the receipt', () {
      final after = ok(
        TicketEngine.addOpenPriceLine(
          ticket(),
          name: 'Birthday candle',
          price: Money.zero,
        ),
      );
      expect(after.lines, hasLength(1));
      expect(after.totals.total.minor, 0);
    });
  });

  group('two of them stay two', () {
    test('different charges do not merge into one line', () {
      // `TicketLine` merges on the product id. A shared id would turn a 30.00
      // delivery and a 25.00 corkage into `2×` at whichever price came first.
      var t = ok(
        TicketEngine.addOpenPriceLine(
          ticket(),
          name: 'Delivery',
          price: const Money(3000),
        ),
      );
      t = ok(
        TicketEngine.addOpenPriceLine(
          t,
          name: 'Corkage',
          price: const Money(2500),
        ),
      );

      expect(t.lines, hasLength(2));
      expect(t.lines.map((l) => l.product.id).toSet(), hasLength(2));
      expect(t.totals.subtotal.minor, 5500);
    });

    test('ids stay clear of menu items and of each other', () {
      var t = ticket().copyWith(lines: [TicketLine(product: grill, quantity: 1)]);
      t = ok(
        TicketEngine.addOpenPriceLine(t, name: 'A', price: const Money(100)),
      );
      t = ok(
        TicketEngine.addOpenPriceLine(t, name: 'B', price: const Money(200)),
      );

      final ids = t.lines.map((l) => l.product.id).toList();
      expect(ids, containsAll([101]));
      expect(ids.where((id) => id < 0).toSet(), hasLength(2));
    });

    test('an id is not reused after a line is removed', () {
      // Otherwise a discount or a void still pointing at the old key would
      // reattach itself to a different charge.
      var t = ok(
        TicketEngine.addOpenPriceLine(ticket(), name: 'A', price: const Money(100)),
      );
      final first = t.lines.single.product.id;

      t = ok(
        TicketEngine.cancelLine(t, t.lines.single.key, by: 4, now: now),
      );
      t = ok(
        TicketEngine.addOpenPriceLine(t, name: 'B', price: const Money(200)),
      );

      // The ticket is empty of lines again, so the allocator restarts — which
      // is safe precisely because nothing is left pointing at the old id.
      expect(t.lines.single.product.isOpenPrice, isTrue);
      expect(t.lines.single.product.nameEn, 'B');
      expect(first, isNegative);
    });
  });

  group('what is refused', () {
    test('a charge with no name', () {
      // "Item" against 200.00 is a line nobody can account for a week later.
      for (final name in ['', '   ']) {
        final result = TicketEngine.addOpenPriceLine(
          ticket(),
          name: name,
          price: const Money(1000),
        );
        expect(result.refusal, isA<OpenItemNeedsName>(), reason: '"$name"');
      }
    });

    test('a negative price', () {
      final result = TicketEngine.addOpenPriceLine(
        ticket(),
        name: 'Refund-ish',
        price: const Money(-100),
      );
      // Money going the other way is a refund, which has its own flow and its
      // own permission.
      expect(result.refusal, isA<PriceBelowZero>());
    });

    test('a quantity of nothing', () {
      final result = TicketEngine.addOpenPriceLine(
        ticket(),
        name: 'Delivery',
        price: const Money(1000),
        quantity: 0,
      );
      expect(result.refusal, isNotNull);
    });
  });

  group('it behaves like any other line', () {
    test('it can be voided, and stops counting', () {
      var t = ok(
        TicketEngine.addOpenPriceLine(
          ticket(),
          name: 'Delivery',
          price: const Money(3000),
        ),
      );
      t = t.copyWith(
        lines: [t.lines.single.copyWith(stage: LineStage.sent)],
      );
      t = ok(TicketEngine.voidLine(t, t.lines.single.key, by: 4, now: now));

      expect(t.totals.subtotal.minor, 0);
      // Still on the ticket, as any voided line is.
      expect(t.lines, hasLength(1));
    });

    test('it can be repriced', () {
      var t = ok(
        TicketEngine.addOpenPriceLine(
          ticket(),
          name: 'Delivery',
          price: const Money(3000),
        ),
      );
      t = ok(
        TicketEngine.overridePrice(
          t,
          t.lines.single.key,
          const Money(2000),
          by: 4,
          now: now,
        ),
      );
      expect(t.totals.subtotal.minor, 2000);
    });
  });
}
