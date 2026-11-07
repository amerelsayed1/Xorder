import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/services/payment_status.dart';

/// The payment status rule (plan 17 S1).
///
/// Every case is stated as the rows a sale would have, not as sums, because the
/// acceptance criterion is "payment status matches the rows it is derived
/// from" — and the sums are where a rule goes wrong (a refund counted against
/// the total instead of against what was taken).
void main() {
  PaymentStatus of(int total, List<int> payments, [List<int> refunds = const []]) =>
      paymentStatusOf(
        totalMinor: total,
        paymentsMinor: payments,
        refundsMinor: refunds,
      );

  group('before anything goes back', () {
    test('no payment rows is UNPAID', () {
      expect(of(26800, []), PaymentStatus.unpaid);
    });

    test('rows short of the total are PARTIALLY_PAID', () {
      expect(of(26800, [10000]), PaymentStatus.partiallyPaid);
    });

    test('split tender summing to the total is PAID', () {
      // Two rows, neither of which is the total on its own. A rule that looked
      // at one payment would call this part paid.
      expect(of(26800, [20000, 6800]), PaymentStatus.paid);
    });

    test('a sale that owed nothing is PAID, not UNPAID', () {
      // A comp discounted to zero. UNPAID would send somebody looking for
      // money that never existed.
      expect(of(0, []), PaymentStatus.paid);
    });
  });

  group('once money has gone back', () {
    test('part of it is PARTIALLY_REFUNDED', () {
      expect(of(26800, [26800], [5000]), PaymentStatus.partiallyRefunded);
    });

    test('several refunds adding up to what was taken are REFUNDED', () {
      expect(of(26800, [20000, 6800], [6800, 20000]), PaymentStatus.refunded);
    });

    test('is measured against what was taken, not the total', () {
      // 100.00 owed, 40.00 taken, 40.00 given back: nothing of the customer's
      // is left with the business. Measured against the total this would
      // read PARTIALLY_REFUNDED — true of the bill, false of the money.
      expect(of(10000, [4000], [4000]), PaymentStatus.refunded);
    });

    test('a refund outranks a shortfall', () {
      // Part paid and part returned. "How much went back" is the question
      // once anything has.
      expect(of(10000, [6000], [1000]), PaymentStatus.partiallyRefunded);
    });
  });

  test('the sums form and the rows form are one rule', () {
    // The repository reads sums; the till has rows. Both must answer alike.
    const cases = <(int, List<int>, List<int>)>[
      (26800, [], []),
      (26800, [10000], []),
      (26800, [20000, 6800], []),
      (0, [], []),
      (26800, [26800], [5000]),
      (10000, [4000], [4000]),
    ];
    for (final (total, paid, back) in cases) {
      expect(
        paymentStatusFromSums(
          totalMinor: total,
          paidMinor: paid.fold(0, (a, b) => a + b),
          refundedMinor: back.fold(0, (a, b) => a + b),
        ),
        of(total, paid, back),
        reason: '$total $paid $back',
      );
    }
  });

  test('the wire strings are the ones the SQL twin returns', () {
    // The repository parses the SQL's answer with fromWire; a renamed member
    // would silently fall back to the Dart rule and the SQL would be unused.
    expect(PaymentStatus.values.map((s) => s.wire), [
      'UNPAID',
      'PARTIALLY_PAID',
      'PAID',
      'PARTIALLY_REFUNDED',
      'REFUNDED',
    ]);
    for (final status in PaymentStatus.values) {
      expect(PaymentStatus.fromWire(status.wire), status);
    }
    expect(PaymentStatus.fromWire('OVERPAID'), isNull);
  });
}
