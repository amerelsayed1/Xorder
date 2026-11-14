import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/discount.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

/// Discounts on a ticket: what they come off, what they cost, and who may give
/// them without asking.
///
/// The golden suite in `ticket_totals_golden_test.dart` pins every undiscounted
/// total and must stay green through all of this — those numbers are receipts
/// people were handed. What follows is only about what changes when money comes
/// off.
void main() {
  final now = DateTime(2026, 9, 8, 12);

  Product product(int priceMinor, {int id = 1, int categoryId = 1}) => Product(
    id: id,
    categoryId: categoryId,
    nameEn: 'Item $id',
    price: Money(priceMinor),
  );

  Ticket ticket({
    List<TicketLine> lines = const [],
    OrderType type = OrderType.dineIn,
    TaxConfig tax = const TaxConfig(),
  }) => Ticket(
    id: 't',
    orderType: type,
    tableId: type == OrderType.dineIn ? 1 : null,
    lines: lines,
    taxConfig: tax,
  );

  TicketLine line(Product p, int quantity) =>
      TicketLine(product: p, quantity: quantity);

  Discount percentage(
    int bp, {
    DiscountScope scope = DiscountScope.item,
    DiscountTargets targets = const DiscountTargets(),
    Money? minOrder,
    bool requiresCustomer = false,
    bool active = true,
    Set<int> days = const {},
  }) => Discount(
    id: 1,
    code: 'pct',
    nameEn: 'Ten off',
    kind: DiscountKind.percentage,
    scope: scope,
    valueBp: bp,
    targets: targets,
    minOrder: minOrder,
    requiresCustomer: requiresCustomer,
    isActive: active,
    daysOfWeek: days,
  );

  /// The ticket after a successful operation, or a failure naming the refusal.
  Ticket ok(TicketResult result) {
    expect(result.refusal, isNull, reason: 'expected this to be allowed');
    return result.ticket!;
  }

  group('what service and tax are charged on', () {
    test('a discount reduces the goods, and everything charged on them', () {
      final base = ticket(lines: [line(product(10000), 1)]);
      final after = ok(
        TicketEngine.applyLineDiscount(
          base,
          '1:',
          percentage(1000),
          now: now,
          appliedBy: 4,
        ),
      );
      final totals = after.totals;

      expect(totals.subtotal.minor, 10000, reason: 'the goods are unchanged');
      expect(totals.discount.minor, 1000);
      expect(totals.net.minor, 9000);
      // 12% of 90.00, not of 100.00.
      expect(totals.service.minor, 1080);
      // 14% of 100.80 = 14.112 → 14.11
      expect(totals.vat.minor, 1411);
      expect(totals.total.minor, 11491);
    });

    test('a fully comped meal costs nothing at all', () {
      // The case that decides the whole design. If service were charged on the
      // gross, a customer whose meal was comped would still be handed a bill
      // for service and VAT on food the business gave away.
      final base = ticket(lines: [line(product(10000), 1)]);
      final after = ok(
        TicketEngine.applyOrderDiscount(
          base,
          percentage(10000, scope: DiscountScope.order),
          now: now,
          appliedBy: 4,
        ),
      );

      expect(after.totals.net.minor, 0);
      expect(after.totals.service.minor, 0);
      expect(after.totals.vat.minor, 0);
      expect(after.totals.total.minor, 0);
    });

    test('the parts still foot to the whole', () {
      final base = ticket(lines: [line(product(3333), 3)]);
      final after = ok(
        TicketEngine.applyOrderDiscount(
          base,
          percentage(1750, scope: DiscountScope.order),
          now: now,
          appliedBy: 4,
        ),
      );
      final t = after.totals;

      expect(
        t.net.minor + t.service.minor + t.vat.minor,
        t.total.minor,
        reason: 'net + service + vat must equal total',
      );
      expect(t.subtotal.minor - t.discount.minor, t.net.minor);
    });

    test('takeaway still takes no service charge', () {
      final base = ticket(
        lines: [line(product(10000), 1)],
        type: OrderType.takeaway,
      );
      final after = ok(
        TicketEngine.applyOrderDiscount(
          base,
          percentage(1000, scope: DiscountScope.order),
          now: now,
          appliedBy: 4,
        ),
      );

      expect(after.totals.service.minor, 0);
      expect(after.totals.vat.minor, 1260); // 14% of 90.00
      expect(after.totals.total.minor, 10260);
    });
  });

  group('what an order discount comes off', () {
    test('the goods less anything already taken off a line', () {
      // 100.00 of food, 50% off one line, then 50% off the order. The order
      // discount takes half of what is LEFT, not half of the gross — otherwise
      // the two together exceed the goods and the total the database refuses to
      // hold is the one the customer was shown.
      var t = ticket(
        lines: [line(product(5000, id: 1), 1), line(product(5000, id: 2), 1)],
      );
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(5000),
          now: now,
          appliedBy: 4,
        ),
      );
      t = ok(
        TicketEngine.applyOrderDiscount(
          t,
          percentage(5000, scope: DiscountScope.order),
          now: now,
          appliedBy: 4,
        ),
      );

      expect(t.totals.subtotal.minor, 10000);
      // 25.00 off the line, then 50% of the remaining 75.00 = 37.50
      expect(t.totals.discount.minor, 2500 + 3750);
      expect(t.totals.net.minor, 3750);
    });

    test('two discounts can never exceed the goods', () {
      var t = ticket(lines: [line(product(10000), 1)]);
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(10000),
          now: now,
          appliedBy: 4,
        ),
      );

      // Nothing is left, so an order discount has nothing to come off.
      final second = TicketEngine.applyOrderDiscount(
        t,
        percentage(10000, scope: DiscountScope.order),
        now: now,
        appliedBy: 4,
      );
      expect(second.refusal, isA<NothingToDiscount>());
      expect(
        t.totals.discount.minor,
        lessThanOrEqualTo(t.totals.subtotal.minor),
      );
    });
  });

  group('stacking', () {
    test('a second discount on the same line is refused', () {
      var t = ticket(lines: [line(product(10000), 1)]);
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(1000),
          now: now,
          appliedBy: 4,
        ),
      );

      final second = TicketEngine.applyLineDiscount(
        t,
        '1:',
        percentage(2000),
        now: now,
        appliedBy: 4,
      );

      // Two discounts summed onto one line cannot afterwards be reported on
      // separately, and how they compound is not a decision for a queue.
      expect(second.refusal, isA<AlreadyDiscounted>());
    });

    test('a second order discount is refused', () {
      var t = ticket(lines: [line(product(10000), 1)]);
      t = ok(
        TicketEngine.applyOrderDiscount(
          t,
          percentage(1000, scope: DiscountScope.order),
          now: now,
          appliedBy: 4,
        ),
      );

      final second = TicketEngine.applyOrderDiscount(
        t,
        percentage(1000, scope: DiscountScope.order),
        now: now,
        appliedBy: 4,
      );
      expect(second.refusal, isA<AlreadyDiscounted>());
    });

    test('one discount per line, on different lines, is fine', () {
      var t = ticket(
        lines: [line(product(5000, id: 1), 1), line(product(5000, id: 2), 1)],
      );
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(1000),
          now: now,
          appliedBy: 4,
        ),
      );
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '2:',
          percentage(2000),
          now: now,
          appliedBy: 4,
        ),
      );

      expect(t.discounts, hasLength(2));
      expect(t.totals.discount.minor, 500 + 1000);
    });
  });

  group('limits', () {
    const cashier = DiscountLimit(maxBp: 1000);

    test('within the limit is allowed', () {
      final t = ticket(lines: [line(product(10000), 1)]);
      final result = TicketEngine.applyLineDiscount(
        t,
        '1:',
        percentage(1000),
        now: now,
        appliedBy: 4,
        limit: cashier,
      );
      expect(result.isOk, isTrue);
    });

    test('above the limit asks for approval rather than refusing', () {
      final t = ticket(lines: [line(product(10000), 1)]);
      final result = TicketEngine.applyLineDiscount(
        t,
        '1:',
        percentage(3000),
        now: now,
        appliedBy: 4,
        limit: cashier,
      );

      final refusal = result.refusal;
      expect(refusal, isA<DiscountAboveLimit>());
      // Both numbers, so the prompt can say "your limit is 10%, this is 30%"
      // rather than "not allowed".
      expect((refusal! as DiscountAboveLimit).requested.minor, 3000);
      expect((refusal as DiscountAboveLimit).base.minor, 10000);
    });

    test('a fixed amount cannot walk around a percentage cap', () {
      // The loophole worth closing: a cashier capped at 10% reaching for a flat
      // 50.00 off a 100.00 order is asking for 50%. Checking maxBp only against
      // percentage discounts would make the cap avoidable by picking the other
      // kind, which is exactly what somebody working around it would do.
      final t = ticket(lines: [line(product(10000), 1)]);
      final result = TicketEngine.applyCustomDiscount(
        t,
        name: 'Off',
        kind: DiscountKind.fixed,
        appliedBy: 4,
        valueMinor: const Money(5000),
        lineKey: '1:',
        limit: cashier,
      );
      expect(result.refusal, isA<DiscountAboveLimit>());
    });

    test('exactly at the limit is permitted, a piastre over is not', () {
      const limit = DiscountLimit(maxBp: 1000);
      expect(
        limit.permits(base: const Money(10000), amount: const Money(1000)),
        isTrue,
      );
      expect(
        limit.permits(base: const Money(10000), amount: const Money(1001)),
        isFalse,
      );
    });

    test('a cash ceiling applies too', () {
      const limit = DiscountLimit(maxAmount: Money(2000));
      expect(
        limit.permits(base: const Money(100000), amount: const Money(2000)),
        isTrue,
      );
      expect(
        limit.permits(base: const Money(100000), amount: const Money(2001)),
        isFalse,
      );
    });

    test('unlimited permits anything', () {
      expect(DiscountLimit.unlimited.isUnlimited, isTrue);
      expect(
        DiscountLimit.unlimited.permits(
          base: const Money(10000),
          amount: const Money(10000),
        ),
        isTrue,
      );
    });

    test('approval is passing no limit at all, and it succeeds', () {
      final t = ticket(lines: [line(product(10000), 1)]);

      final blocked = TicketEngine.applyLineDiscount(
        t,
        '1:',
        percentage(3000),
        now: now,
        appliedBy: 4,
        limit: cashier,
      );
      expect(blocked.refusal, isA<DiscountAboveLimit>());

      // What "lent for this one action" means: the caller retries without a
      // ceiling, and records who approved it.
      final approved = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(3000),
          now: now,
          appliedBy: 4,
          approvedByName: 'Hana Mostafa',
        ),
      );
      expect(approved.discounts.single.approvedByName, 'Hana Mostafa');
      expect(approved.discounts.single.wasApproved, isTrue);
    });
  });

  group('when a discount is not on offer', () {
    test('an inactive one', () {
      final t = ticket(lines: [line(product(10000), 1)]);
      final result = TicketEngine.applyLineDiscount(
        t,
        '1:',
        percentage(1000, active: false),
        now: now,
        appliedBy: 4,
      );
      expect(result.refusal, isA<DiscountNotOffered>());
    });

    test('the wrong day', () {
      final t = ticket(lines: [line(product(10000), 1)]);
      // 8 September 2026 is a Tuesday.
      final result = TicketEngine.applyLineDiscount(
        t,
        '1:',
        percentage(1000, days: {6, 7}),
        now: now,
        appliedBy: 4,
      );
      expect(result.refusal, isA<DiscountNotOffered>());
    });

    test('the wrong order type', () {
      final t = ticket(
        lines: [line(product(10000), 1)],
        type: OrderType.delivery,
      );
      final result = TicketEngine.applyOrderDiscount(
        t,
        percentage(
          1000,
          scope: DiscountScope.order,
          targets: const DiscountTargets(orderTypes: {OrderType.dineIn}),
        ),
        now: now,
        appliedBy: 4,
      );
      expect(result.refusal, isA<DiscountNotOffered>());
    });

    test('the wrong product', () {
      final t = ticket(lines: [line(product(10000, categoryId: 3), 1)]);
      final result = TicketEngine.applyLineDiscount(
        t,
        '1:',
        percentage(1000, targets: const DiscountTargets(categoryIds: {9})),
        now: now,
        appliedBy: 4,
      );
      expect(result.refusal, isA<DiscountNotOffered>());
    });

    test('under the minimum order', () {
      final t = ticket(lines: [line(product(5000), 1)]);
      final result = TicketEngine.applyOrderDiscount(
        t,
        percentage(
          1000,
          scope: DiscountScope.order,
          minOrder: const Money(10000),
        ),
        now: now,
        appliedBy: 4,
      );
      expect(result.refusal, isA<DiscountNotOffered>());
    });

    test('no customer on an order that needs one', () {
      final t = ticket(lines: [line(product(10000), 1)]);

      final without = TicketEngine.applyOrderDiscount(
        t,
        percentage(1000, scope: DiscountScope.order, requiresCustomer: true),
        now: now,
        appliedBy: 4,
      );
      expect(without.refusal, isA<DiscountRequiresCustomer>());

      final with_ = TicketEngine.applyOrderDiscount(
        t,
        percentage(1000, scope: DiscountScope.order, requiresCustomer: true),
        now: now,
        appliedBy: 4,
        hasCustomer: true,
      );
      expect(with_.isOk, isTrue);
    });

    test('an empty ticket', () {
      final result = TicketEngine.applyOrderDiscount(
        ticket(),
        percentage(1000, scope: DiscountScope.order),
        now: now,
        appliedBy: 4,
      );
      expect(result.refusal, isA<NothingToDiscount>());
    });

    test('a line that is not on the ticket', () {
      final t = ticket(lines: [line(product(10000), 1)]);
      final result = TicketEngine.applyLineDiscount(
        t,
        '99:',
        percentage(1000),
        now: now,
        appliedBy: 4,
      );
      expect(result.refusal, isA<LineNotOnTicket>());
    });
  });

  group('custom discounts', () {
    test('a typed percentage prices exactly as a configured one would', () {
      final t = ticket(lines: [line(product(3333), 1)]);

      final configured = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(1250),
          now: now,
          appliedBy: 4,
        ),
      );
      final typed = ok(
        TicketEngine.applyCustomDiscount(
          t,
          name: 'Manager discount',
          kind: DiscountKind.percentage,
          appliedBy: 4,
          valueBp: 1250,
          lineKey: '1:',
        ),
      );

      // A typed 12.5% and a configured 12.5% must not round differently.
      expect(
        typed.discounts.single.amount.minor,
        configured.discounts.single.amount.minor,
      );
    });

    test(
      'carries no discount id, because there is no configuration behind it',
      () {
        final t = ticket(lines: [line(product(10000), 1)]);
        final after = ok(
          TicketEngine.applyCustomDiscount(
            t,
            name: 'Manager discount',
            kind: DiscountKind.fixed,
            appliedBy: 4,
            valueMinor: const Money(1500),
          ),
        );

        expect(after.discounts.single.discountId, isNull);
        expect(after.discounts.single.nameSnapshot, 'Manager discount');
        expect(after.discounts.single.isOrderLevel, isTrue);
      },
    );

    test('never takes off more than there is', () {
      final t = ticket(lines: [line(product(10000), 1)]);
      final after = ok(
        TicketEngine.applyCustomDiscount(
          t,
          name: 'Too much',
          kind: DiscountKind.fixed,
          appliedBy: 4,
          valueMinor: const Money(50000),
        ),
      );

      expect(after.discounts.single.amount.minor, 10000);
      expect(after.totals.total.minor, 0);
    });
  });

  group('removing', () {
    test('a line discount comes off, the order one stays', () {
      var t = ticket(lines: [line(product(10000), 1)]);
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(1000),
          now: now,
          appliedBy: 4,
        ),
      );
      t = ok(
        TicketEngine.applyOrderDiscount(
          t,
          percentage(1000, scope: DiscountScope.order),
          now: now,
          appliedBy: 4,
        ),
      );
      expect(t.discounts, hasLength(2));

      t = TicketEngine.removeDiscount(t, lineKey: '1:');
      expect(t.discounts, hasLength(1));
      expect(t.discounts.single.isOrderLevel, isTrue);
    });

    test('removing the order discount restores the full price', () {
      var t = ticket(lines: [line(product(10000), 1)]);
      final before = t.totals.total.minor;

      t = ok(
        TicketEngine.applyOrderDiscount(
          t,
          percentage(1000, scope: DiscountScope.order),
          now: now,
          appliedBy: 4,
        ),
      );
      expect(t.totals.total.minor, lessThan(before));

      t = TicketEngine.removeDiscount(t);
      expect(t.totals.total.minor, before);
      expect(t.totals.discount.isZero, isTrue);
    });
  });

  group('bookkeeping', () {
    test('a line discount knows which line it came off', () {
      var t = ticket(
        lines: [line(product(5000, id: 1), 1), line(product(5000, id: 2), 1)],
      );
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '2:',
          percentage(1000),
          now: now,
          appliedBy: 4,
        ),
      );

      expect(t.discountOnLine('2:'), isNotNull);
      expect(t.discountOnLine('1:'), isNull);
      expect(t.lineDiscounts, hasLength(1));
      expect(t.orderDiscounts, isEmpty);
    });

    test('the applied record snapshots the name and the rate', () {
      var t = ticket(lines: [line(product(10000), 1)]);
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(1000),
          now: now,
          appliedBy: 4,
        ),
      );

      final applied = t.discounts.single;
      expect(applied.nameSnapshot, 'Ten off');
      expect(applied.kind, DiscountKind.percentage);
      expect(applied.valueBp, 1000);
      expect(applied.discountId, 1);
    });

    test('a reason and a note travel with the discount', () {
      var t = ticket(lines: [line(product(10000), 1)]);
      t = ok(
        TicketEngine.applyLineDiscount(
          t,
          '1:',
          percentage(1000),
          now: now,
          appliedBy: 4,
          reasonId: 4,
          note: 'Regular customer',
        ),
      );

      expect(t.discounts.single.reasonId, 4);
      expect(t.discounts.single.note, 'Regular customer');
    });
  });

  group('tender against a discounted ticket', () {
    test('the balance due is the discounted total', () {
      var t = ticket(lines: [line(product(10000), 1)]);
      t = ok(
        TicketEngine.applyOrderDiscount(
          t,
          percentage(1000, scope: DiscountScope.order),
          now: now,
          appliedBy: 4,
        ),
      );

      final due = t.totals.total.minor;
      t = ok(TicketEngine.addTender(t, typeId: 1, label: 'Cash'));

      // A null amount means "the whole remaining due", and that due must be the
      // discounted figure — not the one before the discount.
      expect(t.tenders.single.amount.minor, due);
      expect(t.totals.due.isZero, isTrue);
    });
  });
}
