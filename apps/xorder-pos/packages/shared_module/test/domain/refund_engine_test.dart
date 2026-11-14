import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/order_record.dart';
import 'package:shared_module/domain/models/refund.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/refund_engine.dart';

/// How a refund gives money back.
///
/// The claim under test throughout is that **no tax is ever recomputed**. Every
/// part of a partial refund is a share of what the order actually charged, so a
/// rate that changed after the sale, or a rate that does not divide evenly,
/// cannot move a figure on a refund receipt.
///
/// The second claim is the remainder rule: a bill refunded in pieces gives back
/// exactly what it took, to the piastre, however the pieces were cut.
void main() {
  final soldAt = DateTime(2026, 9, 7, 13, 0);
  final now = DateTime(2026, 9, 7, 18, 0);

  /// A dine-in order: 3 × 50.00 + 1 × 25.00 = 175.00 subtotal, 10% service on
  /// it, 14% VAT on the two together. Worked once, by hand, and then held as
  /// literals — a fixture that recomputed its own expectations would agree with
  /// any arithmetic the engine happened to do.
  ///
  ///   subtotal 175.00 · service 17.50 · VAT (192.50 × 14%) 26.95
  ///   total 219.45
  OrderRecordDetail order({
    int subtotal = 17500,
    int discount = 0,
    int service = 1750,
    int vat = 2695,
    int total = 21945,
    OrderStatus status = OrderStatus.paid,
    List<OrderRecordLine>? lines,
    DateTime? at,
  }) => OrderRecordDetail(
    order: OrderRecord(
      id: 1,
      clientTransactionId: 'txn-1',
      invoiceNumber: 'INV-1',
      status: status,
      orderType: OrderType.dineIn,
      occurredAt: at ?? soldAt,
      subtotal: Money(subtotal),
      discount: Money(discount),
      service: Money(service),
      vat: Money(vat),
      total: Money(total),
    ),
    lines:
        lines ??
        const [
          OrderRecordLine(
            id: 10,
            lineKey: 'L1',
            name: 'Mixed Grill',
            quantity: 3,
            unitPrice: Money(5000),
            lineTotal: Money(15000),
          ),
          OrderRecordLine(
            id: 11,
            lineKey: 'L2',
            name: 'Mint tea',
            quantity: 1,
            unitPrice: Money(2500),
            lineTotal: Money(2500),
          ),
        ],
    payments: const [],
    discounts: const [],
  );

  RefundQuote quote(
    (RefundQuote?, RefundRefusal?) result, {
    String? because,
  }) {
    expect(
      result.$2,
      isNull,
      reason: because ?? 'expected a quote, got ${result.$2.runtimeType}',
    );
    return result.$1!;
  }

  RefundRefusal refusal((RefundQuote?, RefundRefusal?) result) {
    expect(result.$1, isNull, reason: 'expected a refusal, got a quote');
    return result.$2!;
  }

  group('a full refund', () {
    test('gives back exactly what the order took, part for part', () {
      final result = RefundEngine.quoteForLines(
        detail: order(),
        quantities: {10: 3, 11: 1},
        previous: const [],
        policy: RefundPolicy.defaults,
        at: now,
      );

      final q = quote(result);
      expect(q.subtotal.minor, 17500);
      expect(q.service.minor, 1750);
      expect(q.vat.minor, 2695);
      expect(q.total.minor, 21945);
      expect(q.kind, RefundKind.full);
    });

    test('is full even when it is the second refund', () {
      // "Full" describes the state it leaves the order in, not whether it was
      // the first thing that happened. A report totalling `kind = 'full'` is
      // counting orders that ended up fully refunded.
      final result = RefundEngine.quoteForLines(
        detail: order(
          lines: const [
            OrderRecordLine(
              id: 10,
              lineKey: 'L1',
              name: 'Mixed Grill',
              quantity: 3,
              unitPrice: Money(5000),
              lineTotal: Money(15000),
              refundedQuantity: 1,
            ),
            OrderRecordLine(
              id: 11,
              lineKey: 'L2',
              name: 'Mint tea',
              quantity: 1,
              unitPrice: Money(2500),
              lineTotal: Money(2500),
            ),
          ],
        ),
        quantities: {10: 2, 11: 1},
        previous: [_previous(total: 6270, subtotal: 5000, service: 500, vat: 770)],
        policy: RefundPolicy.defaults,
        at: now,
      );

      final q = quote(result);
      expect(q.kind, RefundKind.full);
      expect(q.total.minor, 21945 - 6270);
    });
  });

  group('a partial refund', () {
    test('pro-rates service and VAT rather than recomputing them', () {
      // One 50.00 grill off a 175.00 subtotal is 2/7 of the order. The engine
      // never sees a rate: 1750 × 5000 ÷ 17500 = 500, 2695 × 5000 ÷ 17500 = 770.
      final q = quote(
        RefundEngine.quoteForLines(
          detail: order(),
          quantities: {10: 1},
          previous: const [],
          policy: RefundPolicy.defaults,
          at: now,
        ),
      );

      expect(q.subtotal.minor, 5000);
      expect(q.service.minor, 500);
      expect(q.vat.minor, 770);
      expect(q.total.minor, 6270);
      expect(q.kind, RefundKind.partial);
    });

    test('carries the lines it is giving back', () {
      final q = quote(
        RefundEngine.quoteForLines(
          detail: order(),
          quantities: {10: 2},
          previous: const [],
          policy: RefundPolicy.defaults,
          at: now,
        ),
      );

      expect(q.lines, hasLength(1));
      expect(q.lines.single.orderLineId, 10);
      expect(q.lines.single.quantity, 2);
      expect(q.lines.single.name, 'Mixed Grill');
      expect(q.lines.single.lineTotal.minor, 10000);
    });

    test('a zero quantity is not a selection', () {
      final result = RefundEngine.quoteForLines(
        detail: order(),
        quantities: {10: 0, 11: 0},
        previous: const [],
        policy: RefundPolicy.defaults,
        at: now,
      );
      expect(refusal(result), isA<NothingSelected>());
    });

    test('takes the discount back proportionally too', () {
      // 200.00 of food, 20.00 off, no service, 14% VAT on 180.00 = 25.20.
      // Refunding half the food gives back half the discount as well —
      // otherwise the customer is handed back money the business never took.
      final q = quote(
        RefundEngine.quoteForLines(
          detail: order(
            subtotal: 20000,
            discount: 2000,
            service: 0,
            vat: 2520,
            total: 20520,
            lines: const [
              OrderRecordLine(
                id: 10,
                lineKey: 'L1',
                name: 'Platter',
                quantity: 2,
                unitPrice: Money(10000),
                lineTotal: Money(20000),
              ),
            ],
          ),
          quantities: {10: 1},
          previous: const [],
          policy: RefundPolicy.defaults,
          at: now,
        ),
      );

      expect(q.subtotal.minor, 10000);
      expect(q.discount.minor, 1000);
      expect(q.vat.minor, 1260);
      expect(q.total.minor, 10260);
    });
  });

  group('the remainder rule', () {
    test('a bill refunded line by line gives back exactly its total', () {
      // The case the rule exists for. 100.00 of food across three lines does
      // not divide into three whole piastres of VAT, so three independent
      // pro-rata refunds would miss the total — and the database would refuse
      // the last one.
      final detail = order(
        subtotal: 10000,
        discount: 0,
        service: 0,
        vat: 1400,
        total: 11400,
        lines: const [
          OrderRecordLine(
            id: 10,
            lineKey: 'L1',
            name: 'A',
            quantity: 1,
            unitPrice: Money(3333),
            lineTotal: Money(3333),
          ),
          OrderRecordLine(
            id: 11,
            lineKey: 'L2',
            name: 'B',
            quantity: 1,
            unitPrice: Money(3333),
            lineTotal: Money(3333),
          ),
          OrderRecordLine(
            id: 12,
            lineKey: 'L3',
            name: 'C',
            quantity: 1,
            unitPrice: Money(3334),
            lineTotal: Money(3334),
          ),
        ],
      );

      final issued = <Refund>[];
      var refundedSoFar = 0;

      for (final id in [10, 11, 12]) {
        final remaining = [
          for (final line in detail.lines)
            if (issued.every((r) => r.lines.every((l) => l.orderLineId != line.id)))
              line,
        ];
        final current = OrderRecordDetail(
          order: detail.order,
          lines: [
            for (final line in detail.lines)
              if (remaining.contains(line))
                line
              else
                OrderRecordLine(
                  id: line.id,
                  lineKey: line.lineKey,
                  name: line.name,
                  quantity: line.quantity,
                  unitPrice: line.unitPrice,
                  lineTotal: line.lineTotal,
                  refundedQuantity: line.quantity,
                ),
          ],
          payments: const [],
          discounts: const [],
        );

        final q = quote(
          RefundEngine.quoteForLines(
            detail: current,
            quantities: {id: 1},
            previous: issued,
            policy: RefundPolicy.defaults,
            at: now,
          ),
        );
        refundedSoFar += q.total.minor;
        issued.add(
          Refund(
            id: issued.length + 1,
            clientRefundId: 'r${issued.length}',
            orderId: 1,
            kind: q.kind,
            subtotal: q.subtotal,
            discount: q.discount,
            service: q.service,
            vat: q.vat,
            total: q.total,
            occurredAt: now,
            lines: q.lines,
          ),
        );
      }

      // To the piastre. Not "about right".
      expect(refundedSoFar, 11400);
      expect(issued.last.kind, RefundKind.full);
      // And the parts reconcile too, not only the total.
      expect(issued.fold<int>(0, (s, r) => s + r.vat.minor), 1400);
      expect(issued.fold<int>(0, (s, r) => s + r.subtotal.minor), 10000);
    });

    test('a short read of the lines does not refund the whole order', () {
      // The dangerous shape: `detail.lines` holds one line of a two-line order,
      // so "every line, in full" is true while most of the bill is missing. The
      // value check is what stops the remainder rule handing back 219.45 for
      // 25.00 of food.
      final q = quote(
        RefundEngine.quoteForLines(
          detail: order(
            lines: const [
              OrderRecordLine(
                id: 11,
                lineKey: 'L2',
                name: 'Mint tea',
                quantity: 1,
                unitPrice: Money(2500),
                lineTotal: Money(2500),
              ),
            ],
          ),
          quantities: {11: 1},
          previous: const [],
          policy: RefundPolicy.defaults,
          at: now,
        ),
      );

      expect(q.kind, RefundKind.partial);
      expect(q.subtotal.minor, 2500);
      // Pro-rata: 1750 × 2500 ÷ 17500 = 250, 2695 × 2500 ÷ 17500 = 385.
      expect(q.total.minor, 3135);
    });

    test('the closing refund is what is left, not a fresh pro-rata', () {
      final q = quote(
        RefundEngine.quoteForLines(
          detail: order(
            lines: const [
              OrderRecordLine(
                id: 10,
                lineKey: 'L1',
                name: 'Mixed Grill',
                quantity: 3,
                unitPrice: Money(5000),
                lineTotal: Money(15000),
                refundedQuantity: 3,
              ),
              OrderRecordLine(
                id: 11,
                lineKey: 'L2',
                name: 'Mint tea',
                quantity: 1,
                unitPrice: Money(2500),
                lineTotal: Money(2500),
              ),
            ],
          ),
          quantities: {11: 1},
          previous: [
            _previous(total: 18810, subtotal: 15000, service: 1500, vat: 2310),
          ],
          policy: RefundPolicy.defaults,
          at: now,
        ),
      );

      expect(q.total.minor, 21945 - 18810);
      expect(q.subtotal.minor, 2500);
      expect(q.service.minor, 250);
      expect(q.vat.minor, 385);
      expect(q.kind, RefundKind.full);
    });
  });

  group('an amount refund', () {
    test('gives back the amount asked for, exactly', () {
      final q = quote(
        RefundEngine.quoteForAmount(
          detail: order(),
          gross: const Money(5000),
          previous: const [],
          policy: RefundPolicy.defaults,
          at: now,
        ),
      );

      // The gross is what the customer is handed, so it is the figure that must
      // be exact. The parts are shares of it.
      expect(q.total.minor, 5000);
      expect(q.subtotal.minor - q.discount.minor + q.service.minor + q.vat.minor, 5000);
      expect(q.lines, isEmpty);
      expect(q.kind, RefundKind.partial);
    });

    test('an amount that clears the order closes it', () {
      final q = quote(
        RefundEngine.quoteForAmount(
          detail: order(),
          gross: const Money(21945),
          previous: const [],
          policy: RefundPolicy.defaults,
          at: now,
        ),
      );
      expect(q.kind, RefundKind.full);
      expect(q.total.minor, 21945);
      expect(q.vat.minor, 2695);
    });

    test('more than the order has left is refused', () {
      final result = RefundEngine.quoteForAmount(
        detail: order(),
        gross: const Money(30000),
        previous: const [],
        policy: RefundPolicy.defaults,
        at: now,
      );
      final r = refusal(result);
      expect(r, isA<AboveRemainingValue>());
      expect((r as AboveRemainingValue).remaining.minor, 21945);
    });

    test('what is left accounts for refunds already given', () {
      final result = RefundEngine.quoteForAmount(
        detail: order(),
        gross: const Money(20000),
        previous: [_previous(total: 6270, subtotal: 5000, service: 500, vat: 770)],
        policy: RefundPolicy.defaults,
        at: now,
      );
      final r = refusal(result) as AboveRemainingValue;
      expect(r.remaining.minor, 21945 - 6270);
    });

    test('zero and negative are not amounts', () {
      for (final amount in [const Money(0), const Money(-100)]) {
        expect(
          refusal(
            RefundEngine.quoteForAmount(
              detail: order(),
              gross: amount,
              previous: const [],
              policy: RefundPolicy.defaults,
              at: now,
            ),
          ),
          isA<NothingSelected>(),
        );
      }
    });
  });

  group('what is refused', () {
    test('refunds switched off', () {
      final result = RefundEngine.quoteForLines(
        detail: order(),
        quantities: {10: 1},
        previous: const [],
        policy: const RefundPolicy(enabled: false),
        at: now,
      );
      expect(refusal(result), isA<RefundsDisabled>());
    });

    test('a voided order — money that never arrived cannot go back', () {
      final result = RefundEngine.quoteForLines(
        detail: order(status: OrderStatus.voided),
        quantities: {10: 1},
        previous: const [],
        policy: RefundPolicy.defaults,
        at: now,
      );
      expect(refusal(result), isA<NothingLeftToRefund>());
    });

    test('an order already fully refunded', () {
      final result = RefundEngine.quoteForLines(
        detail: order(status: OrderStatus.partiallyRefunded),
        quantities: {10: 1},
        previous: [_previous(total: 21945, subtotal: 17500, service: 1750, vat: 2695)],
        policy: RefundPolicy.defaults,
        at: now,
      );
      expect(refusal(result), isA<NothingLeftToRefund>());
    });

    test('a line that is not on the order', () {
      final result = RefundEngine.quoteForLines(
        detail: order(),
        quantities: {99: 1},
        previous: const [],
        policy: RefundPolicy.defaults,
        at: now,
      );
      expect(refusal(result), isA<LineNotOnOrder>());
    });

    test('more of a line than remains, naming both numbers', () {
      final result = RefundEngine.quoteForLines(
        detail: order(
          lines: const [
            OrderRecordLine(
              id: 10,
              lineKey: 'L1',
              name: 'Mixed Grill',
              quantity: 3,
              unitPrice: Money(5000),
              lineTotal: Money(15000),
              refundedQuantity: 2,
            ),
          ],
        ),
        quantities: {10: 3},
        previous: const [],
        policy: RefundPolicy.defaults,
        at: now,
      );

      final r = refusal(result) as MoreThanRemains;
      expect(r.asked, 3);
      // "You asked for 3 and 1 is left" is a sentence a cashier can act on.
      expect(r.remaining, 1);
    });

    test('a voided line has nothing to give back', () {
      final result = RefundEngine.quoteForLines(
        detail: order(
          lines: [
            OrderRecordLine(
              id: 10,
              lineKey: 'L1',
              name: 'Mixed Grill',
              quantity: 3,
              unitPrice: const Money(5000),
              lineTotal: const Money(15000),
              voidedAt: soldAt,
            ),
          ],
        ),
        quantities: {10: 1},
        previous: const [],
        policy: RefundPolicy.defaults,
        at: now,
      );
      expect(refusal(result), isA<MoreThanRemains>());
    });

    test('above the policy ceiling, which nobody can approve away', () {
      final result = RefundEngine.quoteForLines(
        detail: order(),
        quantities: {10: 3, 11: 1},
        previous: const [],
        policy: const RefundPolicy(maxValue: Money(10000)),
        at: now,
      );
      final r = refusal(result) as AboveRefundLimit;
      expect(r.asked.minor, 21945);
      expect(r.limit.minor, 10000);
    });
  });

  group('the window', () {
    test('a same-day policy refuses yesterday', () {
      final result = RefundEngine.quoteForLines(
        detail: order(at: DateTime(2026, 9, 6, 23, 30)),
        quantities: {10: 1},
        previous: const [],
        policy: const RefundPolicy(window: RefundWindow.sameDay),
        at: now,
      );
      expect(refusal(result), isA<OutsideRefundWindow>());
    });

    test('a same-day policy allows this morning', () {
      final result = RefundEngine.quoteForLines(
        detail: order(at: DateTime(2026, 9, 7, 9)),
        quantities: {10: 1},
        previous: const [],
        policy: const RefundPolicy(window: RefundWindow.sameDay),
        at: now,
      );
      expect(result.$2, isNull);
    });

    test('the default seven days refuses an eight-day-old sale', () {
      final result = RefundEngine.quoteForLines(
        detail: order(at: now.subtract(const Duration(days: 8))),
        quantities: {10: 1},
        previous: const [],
        policy: RefundPolicy.defaults,
        at: now,
      );
      expect(refusal(result), isA<OutsideRefundWindow>());
    });

    test('a same-shift policy asks the caller, which is the only thing that knows', () {
      // A shift is a row a value object cannot see.
      const policy = RefundPolicy(window: RefundWindow.sameShift);
      expect(
        RefundEngine.quoteForLines(
          detail: order(),
          quantities: {10: 1},
          previous: const [],
          policy: policy,
          at: now,
          sameShift: false,
        ).$2,
        isA<OutsideRefundWindow>(),
      );
      expect(
        RefundEngine.quoteForLines(
          detail: order(),
          quantities: {10: 1},
          previous: const [],
          policy: policy,
          at: now,
          sameShift: true,
        ).$2,
        isNull,
      );
    });

    test('unlimited means what it says', () {
      final result = RefundEngine.quoteForLines(
        detail: order(at: DateTime(2019, 1, 1)),
        quantities: {10: 1},
        previous: const [],
        policy: const RefundPolicy(window: RefundWindow.unlimited),
        at: now,
      );
      expect(result.$2, isNull);
    });
  });

  group('approval', () {
    test('is required above the threshold', () {
      final q = quote(
        RefundEngine.quoteForLines(
          detail: order(),
          quantities: {10: 1},
          previous: const [],
          policy: const RefundPolicy(approvalThreshold: Money(5000)),
          at: now,
        ),
      );
      // 62.70 against a 50.00 threshold.
      expect(q.requiresApproval, isTrue);
    });

    test('is not required at exactly the threshold', () {
      // A threshold is the largest amount that passes unaided, not the smallest
      // that needs help. "Approval above 500" must not prompt on 500.
      final q = quote(
        RefundEngine.quoteForAmount(
          detail: order(),
          gross: const Money(5000),
          previous: const [],
          policy: const RefundPolicy(approvalThreshold: Money(5000)),
          at: now,
        ),
      );
      expect(q.requiresApproval, isFalse);
    });

    test('is never required when no threshold is set', () {
      final q = quote(
        RefundEngine.quoteForLines(
          detail: order(),
          quantities: {10: 3, 11: 1},
          previous: const [],
          policy: RefundPolicy.defaults,
          at: now,
        ),
      );
      expect(q.requiresApproval, isFalse);
    });
  });

  group('RefundPolicy', () {
    test('the defaults are the specification\'s, not the permissive ones', () {
      const policy = RefundPolicy.defaults;
      expect(policy.enabled, isTrue);
      // Seven days rather than unlimited: the safe default for money leaving a
      // drawer is the one that expires.
      expect(policy.window, RefundWindow.days7);
      expect(policy.reasonRequired, isTrue);
      expect(policy.maxValue, isNull);
      expect(policy.approvalThreshold, isNull);
    });

    test('every window round-trips through its wire value', () {
      for (final window in RefundWindow.values) {
        expect(RefundWindow.fromWire(window.wire), window);
      }
      expect(RefundWindow.fromWire('fortnight'), isNull);
    });

    test('the wire values are the ones §18 names', () {
      expect(RefundWindow.values.map((w) => w.wire).toSet(), {
        'same_shift',
        'same_day',
        '7d',
        '30d',
        'unlimited',
      });
    });

    test('kind round-trips, and matches migration 12\'s CHECK', () {
      expect(RefundKind.values.map((k) => k.wire).toSet(), {'full', 'partial'});
      for (final kind in RefundKind.values) {
        expect(RefundKind.fromWire(kind.wire), kind);
      }
    });
  });
}

Refund _previous({
  required int total,
  required int subtotal,
  int discount = 0,
  int service = 0,
  int vat = 0,
}) => Refund(
  id: 1,
  clientRefundId: 'prev',
  orderId: 1,
  kind: RefundKind.partial,
  subtotal: Money(subtotal),
  discount: Money(discount),
  service: Money(service),
  vat: Money(vat),
  total: Money(total),
  occurredAt: DateTime(2026, 9, 7, 14),
);
