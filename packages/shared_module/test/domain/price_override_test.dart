import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/discount.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

/// Selling a line at a price that is not the menu price.
///
/// The claim that matters most here is the last group's: **a price override is
/// a discount by another name**, and the same ceiling has to govern both. A
/// cashier who may take 10% off must not be able to reprice a 50.00 dish to
/// 5.00 and take 90%.
void main() {
  final now = DateTime(2026, 9, 7, 13);

  const grill = Product(
    id: 101,
    categoryId: 11,
    nameEn: 'Mixed Grill',
    price: Money(5000),
  );
  const extraBread = Modifier(
    id: 7,
    groupId: 3,
    nameEn: 'Extra bread',
    priceDelta: Money(1000),
  );

  Ticket ticket({
    int quantity = 2,
    List<Modifier> modifiers = const [],
    LineStage stage = LineStage.draft,
    LineVoid? voided,
  }) => Ticket(
    id: 'txn-1',
    orderType: OrderType.takeaway,
    // No service and no VAT, so an assertion about a total is an assertion
    // about the override and nothing else.
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
    lines: [
      TicketLine(
        product: grill,
        quantity: quantity,
        modifiers: modifiers,
        stage: stage,
        voided: voided,
      ),
    ],
  );

  String keyOf(Ticket t) => t.lines.single.key;

  Ticket ok(TicketResult result) {
    expect(
      result.refusal,
      isNull,
      reason: 'expected a ticket, got ${result.refusal.runtimeType}',
    );
    return result.ticket!;
  }

  TicketRefusal refused(TicketResult result) {
    expect(result.ticket, isNull, reason: 'expected a refusal, got a ticket');
    return result.refusal!;
  }

  group('setting a price', () {
    test('replaces the unit price and the line total', () {
      final start = ticket(quantity: 2);
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );

      final line = after.lines.single;
      expect(line.unitPrice.minor, 4000);
      expect(line.lineTotal.minor, 8000);
      expect(after.totals.subtotal.minor, 8000);
    });

    test('keeps the menu price for the strike-through', () {
      final start = ticket();
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );

      final line = after.lines.single;
      expect(line.isRepriced, isTrue);
      expect(line.menuUnitPrice.minor, 5000);
      expect(line.priceOverride!.original.minor, 5000);
      expect(line.priceOverride!.reduction.minor, 1000);
    });

    test('replaces the whole unit price, modifiers folded in', () {
      // "Make it 40" means the customer pays 40 for that item, not 40 plus the
      // extras. Anything else asks a cashier to do arithmetic at a counter.
      final start = ticket(quantity: 1, modifiers: const [extraBread]);
      expect(start.lines.single.unitPrice.minor, 6000);

      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );
      expect(after.lines.single.unitPrice.minor, 4000);
      // And the menu price it is measured against still includes them.
      expect(after.lines.single.menuUnitPrice.minor, 6000);
    });

    test('records who, when and why', () {
      final start = ticket();
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
          reasonId: 12,
          note: 'Cold when it arrived',
          approvedByStaffId: 9,
          approvedByName: 'Hana Mostafa',
        ),
      );

      final override = after.lines.single.priceOverride!;
      expect(override.byStaffId, 4);
      expect(override.at, now);
      expect(override.reasonId, 12);
      expect(override.note, 'Cold when it arrived');
      // Both people, as everywhere else a limit was lent.
      expect(override.approvedByStaffId, 9);
      expect(override.approvedByName, 'Hana Mostafa');
    });

    test('writes a price_overridden event with both figures', () {
      final start = ticket();
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
          reasonId: 12,
        ),
      );

      final event = after.lineEvents.single;
      expect(event.event, 'price_overridden');
      expect(event.unitPriceBefore, 5000);
      expect(event.unitPriceAfter, 4000);
      expect(event.staffId, 4);
      expect(event.reasonId, 12);
    });

    test('the event name is one migration 9 already allows', () {
      // A string this build invents that the CHECK does not know fails the
      // whole settlement transaction.
      expect(TicketLineEventKind.priceOverridden, 'price_overridden');
    });

    test('zero is a comp, and allowed', () {
      final start = ticket();
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          Money.zero,
          by: 4,
          now: now,
        ),
      );
      expect(after.totals.total.minor, 0);
    });

    test('charging more than the menu price is allowed', () {
      // Rare and legitimate — a surcharge, a corrected underpriced item. It
      // gives nothing away, so no ceiling applies, but it is still recorded.
      final start = ticket(quantity: 1);
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(6000),
          by: 4,
          now: now,
          limit: const DiscountLimit(maxBp: 1000),
        ),
      );
      expect(after.lines.single.unitPrice.minor, 6000);
      expect(after.lines.single.priceOverride!.reduction.minor, -1000);
    });

    test('a line the kitchen has already made can still be repriced', () {
      // Repricing cooked food is a money decision, not a kitchen one — and it
      // is exactly what a manager reaches for when somebody complains about a
      // dish they have half eaten.
      final start = ticket(stage: LineStage.sent);
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );
      expect(after.lines.single.unitPrice.minor, 4000);
    });
  });

  group('what is refused', () {
    test('a line that is not on the ticket', () {
      expect(
        refused(
          TicketEngine.overridePrice(
            ticket(),
            '999:',
            const Money(4000),
            by: 4,
            now: now,
          ),
        ),
        isA<LineNotOnTicket>(),
      );
    });

    test('a voided line — nobody is being charged for it', () {
      final start = ticket(
        voided: LineVoid(byStaffId: 4, at: now),
      );
      expect(
        refused(
          TicketEngine.overridePrice(
            start,
            keyOf(start),
            const Money(4000),
            by: 4,
            now: now,
          ),
        ),
        isA<AlreadyVoided>(),
      );
    });

    test('a negative price, which is a refund wearing a disguise', () {
      final start = ticket();
      expect(
        refused(
          TicketEngine.overridePrice(
            start,
            keyOf(start),
            const Money(-100),
            by: 4,
            now: now,
          ),
        ),
        isA<PriceBelowZero>(),
      );
    });

    test('the price it already carries', () {
      // An override that changes nothing still writes an audit row naming
      // somebody, and a ledger full of no-ops is a ledger nobody reads.
      final start = ticket();
      expect(
        refused(
          TicketEngine.overridePrice(
            start,
            keyOf(start),
            const Money(5000),
            by: 4,
            now: now,
          ),
        ),
        isA<PriceUnchanged>(),
      );
    });
  });

  group('the limit — a price override is a discount by another name', () {
    test('a reduction inside the ceiling is allowed', () {
      // 10% of a 100.00 line is 10.00, and 45.00 × 2 is exactly that.
      final start = ticket(quantity: 2);
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4500),
          by: 4,
          now: now,
          limit: const DiscountLimit(maxBp: 1000),
        ),
      );
      expect(after.lines.single.unitPrice.minor, 4500);
    });

    test('a reduction past the ceiling is refused, naming both figures', () {
      // The bypass this closes: 50.00 → 5.00 is 90% off a line a 10% cashier
      // could never have discounted that far.
      final start = ticket(quantity: 2);
      final refusal =
          refused(
                TicketEngine.overridePrice(
                  start,
                  keyOf(start),
                  const Money(500),
                  by: 4,
                  now: now,
                  limit: const DiscountLimit(maxBp: 1000),
                ),
              )
              as PriceBelowLimit;

      expect(refusal.base.minor, 10000);
      expect(refusal.reduction.minor, 9000);
    });

    test('a cash ceiling applies too', () {
      final start = ticket(quantity: 2);
      expect(
        refused(
          TicketEngine.overridePrice(
            start,
            keyOf(start),
            const Money(4000),
            by: 4,
            now: now,
            limit: const DiscountLimit(maxAmount: Money(1000)),
          ),
        ),
        isA<PriceBelowLimit>(),
      );
    });

    test('no limit passed means a supervisor already said yes', () {
      // The discount sheet's own pattern: approval retries with `limit: null`.
      final start = ticket(quantity: 2);
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(500),
          by: 4,
          now: now,
          approvedByStaffId: 9,
        ),
      );
      expect(after.lines.single.unitPrice.minor, 500);
    });

    test('the ceiling is measured against the menu price, not the last one', () {
      // Otherwise two overrides in a row each look small while together they
      // clear the ceiling: 50 → 45 passes, then 45 → 40.50 passes, and the
      // customer has 19% off.
      final start = ticket(quantity: 1);
      final once = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4500),
          by: 4,
          now: now,
          limit: const DiscountLimit(maxBp: 1000),
        ),
      );

      expect(
        refused(
          TicketEngine.overridePrice(
            once,
            keyOf(once),
            const Money(4050),
            by: 4,
            now: now,
            limit: const DiscountLimit(maxBp: 1000),
          ),
        ),
        isA<PriceBelowLimit>(),
      );
    });

    test('"was" always quotes the menu, not a previous override', () {
      final start = ticket(quantity: 1);
      final once = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4500),
          by: 4,
          now: now,
        ),
      );
      final twice = ok(
        TicketEngine.overridePrice(
          once,
          keyOf(once),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );
      // Not 45.00 — a second override that quoted the first one's price as the
      // list price would understate what the business gave away.
      expect(twice.lines.single.priceOverride!.original.minor, 5000);
    });
  });

  group('putting it back', () {
    test('restores the menu price', () {
      final start = ticket();
      final repriced = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );
      final restored = ok(
        TicketEngine.clearPriceOverride(
          repriced,
          keyOf(repriced),
          by: 4,
          now: now,
        ),
      );

      expect(restored.lines.single.isRepriced, isFalse);
      expect(restored.lines.single.unitPrice.minor, 5000);
    });

    test('records the correction rather than erasing the original', () {
      // A correction that deleted its predecessor would let somebody reprice,
      // sell, and tidy up after.
      final start = ticket();
      final repriced = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );
      final restored = ok(
        TicketEngine.clearPriceOverride(
          repriced,
          keyOf(repriced),
          by: 4,
          now: now,
        ),
      );

      expect(restored.lineEvents, hasLength(2));
      expect(restored.lineEvents.last.unitPriceBefore, 4000);
      expect(restored.lineEvents.last.unitPriceAfter, 5000);
    });

    test('clearing a line that was never repriced is refused', () {
      final start = ticket();
      expect(
        refused(
          TicketEngine.clearPriceOverride(
            start,
            keyOf(start),
            by: 4,
            now: now,
          ),
        ),
        isA<PriceUnchanged>(),
      );
    });
  });

  group('with everything else on the ticket', () {
    test('tax is charged on the agreed price, not the menu price', () {
      final start = Ticket(
        id: 'txn-2',
        orderType: OrderType.dineIn,
        taxConfig: const TaxConfig(serviceBp: 1000, vatBp: 1400),
        lines: [TicketLine(product: grill, quantity: 2)],
      );
      final after = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );

      // 80.00 subtotal, 8.00 service, 12.32 VAT, 100.32 total.
      expect(after.totals.subtotal.minor, 8000);
      expect(after.totals.service.minor, 800);
      expect(after.totals.vat.minor, 1232);
      expect(after.totals.total.minor, 10032);
    });

    test('a voided repriced line stops counting, like any other', () {
      final start = ticket(quantity: 1, stage: LineStage.sent);
      final repriced = ok(
        TicketEngine.overridePrice(
          start,
          keyOf(start),
          const Money(4000),
          by: 4,
          now: now,
        ),
      );
      final voided = ok(
        TicketEngine.voidLine(repriced, keyOf(repriced), by: 4, now: now),
      );
      expect(voided.totals.subtotal.minor, 0);
    });
  });
}
