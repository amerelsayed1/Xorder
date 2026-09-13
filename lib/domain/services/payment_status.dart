/// Where a sale stands with money — derived, never stored.
///
/// This is the second of SALES-§8's "two separate concepts". `pos_orders.status`
/// answers where the ORDER is (sent, voided, refunded); this answers where the
/// MONEY is. They are computed from different rows and they can disagree — a
/// voided order is UNPAID, which is true and is not the same fact as VOIDED.
///
/// **Not a column.** A stored payment status is a second copy of what the
/// payment and refund rows already say, and a second copy drifts: the first
/// refund written by a code path that forgot to update it would leave a sale
/// reading PAID with money gone back. Derived from the rows, it cannot disagree
/// with them. Plan 17 §0 rule 3.
///
/// The SQL twin of [paymentStatusFromSums] lives in
/// `PostgresOrderHistoryRepository.paymentStatusSql`, and
/// `test/data/sales_history_test.dart` holds the two to the same answers. A
/// change to one without the other fails that suite.
library;

/// The five states. **These strings are data** — the SQL twin returns them,
/// and a report reading the SQL must be able to key on the same words.
///
/// There is no OVERPAID. A payment row records the amount APPLIED to the bill,
/// never the amount tendered — change is a till concern and never reaches the
/// ledger (plan 17 S2). So "paid more than the total" is not a state a correct
/// ledger can be in, and inventing a word for it would give every cash sale
/// with change a way to trip it the day somebody wrote tendered by mistake.
enum PaymentStatus {
  /// Nothing has been taken. A voided order is this; so is a sale left to
  /// settle later (S4).
  unpaid('UNPAID'),

  /// Some of the total has been taken and some is still owed.
  partiallyPaid('PARTIALLY_PAID'),

  /// Everything owed has been taken, and nothing has gone back.
  paid('PAID'),

  /// Some of what was taken has gone back.
  partiallyRefunded('PARTIALLY_REFUNDED'),

  /// Everything that was taken has gone back.
  refunded('REFUNDED');

  const PaymentStatus(this.wire);

  final String wire;

  static PaymentStatus? fromWire(String value) {
    for (final status in PaymentStatus.values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}

/// The status of a sale from its rows.
///
/// [paymentsMinor] is every `pos_order_payments.amount_minor`, [refundsMinor]
/// every `pos_refunds.total_minor`. Minor units, never a double.
PaymentStatus paymentStatusOf({
  required int totalMinor,
  required Iterable<int> paymentsMinor,
  required Iterable<int> refundsMinor,
}) => paymentStatusFromSums(
  totalMinor: totalMinor,
  paidMinor: paymentsMinor.fold(0, (sum, amount) => sum + amount),
  refundedMinor: refundsMinor.fold(0, (sum, amount) => sum + amount),
);

/// The same rule over sums already taken — which is what the database hands
/// back, one row per sale.
///
/// **A refund outranks everything before it.** Once money has gone back, "how
/// much went back" is the question a person is asking, and answering PAID for
/// a sale half of which was returned would be the stale answer the plan warns
/// about. Measured against what was TAKEN, not the total: a sale that was part
/// paid and had all of that part returned has nothing of the customer's left,
/// which is REFUNDED, not PARTIALLY_REFUNDED.
///
/// **`paid >= total` rather than `==`**, so a zero-total sale — a comp, a
/// staff meal discounted to nothing — reads PAID. Nothing was owed and nothing
/// is missing; UNPAID would send somebody hunting for money that never existed.
PaymentStatus paymentStatusFromSums({
  required int totalMinor,
  required int paidMinor,
  required int refundedMinor,
}) {
  if (refundedMinor > 0) {
    return refundedMinor >= paidMinor
        ? PaymentStatus.refunded
        : PaymentStatus.partiallyRefunded;
  }
  if (paidMinor >= totalMinor) return PaymentStatus.paid;
  if (paidMinor == 0) return PaymentStatus.unpaid;
  return PaymentStatus.partiallyPaid;
}
