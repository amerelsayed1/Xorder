/// §3a of `docs/pos/17-sales-and-payments-plan.md` — one branch's business day,
/// every terminal summed and each broken out.
///
/// **The branch figures are derived from the terminal rows, never stored beside
/// them.** Rule 1 says the branch total and the terminal rows cannot disagree,
/// and the cheapest way to make that true is to give the total nowhere else to
/// live. A [BranchSales] that carried its own gross next to a list of rows
/// would be one constructor call away from a screen whose bottom line does not
/// add up — and a manager who catches that once stops trusting every number on
/// it. Both sources (the shared database and the platform) build rows; neither
/// builds a total.
library;

import '../../core/money/money.dart';
import 'order_record.dart';
import 'tender_method.dart';

/// The sales every sales figure counts: money was taken, whatever happened
/// after. A refunded sale is still a sale — its refund is counted where and
/// when it was issued (rule 4), not by deleting the sale from the day it was
/// made. Voided, cancelled and still-open orders took no money.
///
/// One set for the branch view, the reports and the day close alike. Three
/// literal lists of four words each was the shape before, and a fifth status
/// added to one of them would have been a figure that no longer matched its
/// neighbour on the same screen.
const settledStatuses = {
  OrderStatus.paid,
  OrderStatus.closed,
  OrderStatus.partiallyRefunded,
  OrderStatus.refunded,
};

/// Which of §3a's figures a payment lands in.
enum PaymentBucket {
  cash,
  electronic,
  onAccount,
  other;

  /// Rule 3, in one place for both sources.
  ///
  /// `account` is decided FIRST, before the cash flag. On account is money
  /// owed, and a business that ticked "counts as cash" on it by mistake must
  /// not see a debt reported as takings. The cash flag is the one snapshotted
  /// on the PAYMENT row at settlement (migration 23), not today's tender
  /// configuration — a flag changed on Thursday must not re-describe Tuesday.
  ///
  /// A `cash`-kind tender whose payment was not flagged as cash is [other], not
  /// [cash]: rule 3 defines cash by the flag, and the flag is what the drawer
  /// was judged against at cash-up. Two definitions of "cash" on two screens is
  /// a variance nobody can explain.
  static PaymentBucket of({
    required TenderKind kind,
    required bool countsAsCash,
  }) => switch (kind) {
    TenderKind.account => onAccount,
    TenderKind.card || TenderKind.wallet => countsAsCash ? cash : electronic,
    TenderKind.cash ||
    TenderKind.voucher ||
    TenderKind.other => countsAsCash ? cash : other,
  };

  /// Whether money in this bucket was collected — the question rule 3 exists
  /// to answer. A voucher is collected: it was paid for before it was spent,
  /// and nobody owes the business for it.
  bool get isCollected => switch (this) {
    cash || electronic || other => true,
    onAccount => false,
  };
}

/// One payment method's takings on one terminal (or, merged, the branch).
class MethodTotal {
  const MethodTotal({
    required this.tenderTypeId,
    required this.label,
    required this.kind,
    required this.countsAsCash,
    required this.count,
    required this.amount,
  });

  /// Null when the source does not say. Part of the merge key, so null merges
  /// only with null.
  final int? tenderTypeId;

  /// The label as it was written on the payment rows, not today's name for the
  /// tender — the same reason the Z report groups by it.
  final String label;
  final TenderKind kind;
  final bool countsAsCash;
  final int count;
  final Money amount;

  PaymentBucket get bucket =>
      PaymentBucket.of(kind: kind, countsAsCash: countsAsCash);

  bool sameMethodAs(MethodTotal other) =>
      other.tenderTypeId == tenderTypeId &&
      other.label == label &&
      other.kind == kind &&
      other.countsAsCash == countsAsCash;

  MethodTotal plus(MethodTotal other) => MethodTotal(
    tenderTypeId: tenderTypeId,
    label: label,
    kind: kind,
    countsAsCash: countsAsCash,
    count: count + other.count,
    amount: amount + other.amount,
  );
}

/// One terminal's row in the breakdown.
class TerminalSales {
  const TerminalSales({
    required this.terminalId,
    required this.name,
    required this.orders,
    required this.gross,
    required this.discounts,
    required this.refunds,
    required this.refundCount,
    this.payments = const [],
    this.lastReceivedAt,
  });

  final String terminalId;

  /// Null for a terminal that took money at this branch but has no row for it
  /// in the branch's terminal list. It is listed anyway: rule 2 exists because
  /// a missing row is the one thing a manager cannot notice, and dropping money
  /// a stranger terminal took would leave the branch total quietly short.
  final String? name;

  /// Settled sales. Voided and still-open orders took no money and are not
  /// here.
  final int orders;

  /// Before discounts — `total_minor + discount_minor`. The stored total
  /// already has the discount taken off, so using it here would make rule 5
  /// subtract every discount twice.
  final Money gross;
  final Money discounts;

  /// Refunds this terminal ISSUED in the day, whoever made the original sale
  /// (rule 4). It is this terminal's drawer the money left.
  final Money refunds;
  final int refundCount;

  final List<MethodTotal> payments;

  /// When the platform last heard from this terminal. Null from the shared
  /// database, where there is nothing to hear — every till writes the rows
  /// directly.
  final DateTime? lastReceivedAt;

  bool get isRegistered => name != null;

  /// Rule 5.
  Money get net => gross - discounts - refunds;

  Money get cash => _bucket(PaymentBucket.cash);
  Money get electronic => _bucket(PaymentBucket.electronic);
  Money get onAccount => _bucket(PaymentBucket.onAccount);
  Money get otherTender => _bucket(PaymentBucket.other);

  /// Everything taken in, never on account (rule 3).
  Money get collected => payments
      .where((p) => p.bucket.isCollected)
      .fold(_zero, (sum, p) => sum + p.amount);

  Money get _zero => gross.copyWith(minor: 0);

  Money _bucket(PaymentBucket bucket) => payments
      .where((p) => p.bucket == bucket)
      .fold(_zero, (sum, p) => sum + p.amount);
}

/// Rule 1's arithmetic, for anything that is "terminals, and totals read off
/// them".
///
/// Shared by [BranchSales] (one business day) and `SalesReport` (a range of
/// them), so the two cannot come to disagree about what net or collected
/// means. Copying these getters into the report was the alternative; the copy
/// is the one that stops being updated, and the first sign would be Home and
/// Reports showing two different "today" figures for the same day.
mixin TerminalRollup {
  /// Every terminal of the branch, zeros included (rule 2).
  List<TerminalSales> get terminals;
  String get currency;
  int get exponent;

  Money get _zero => Money(0, currency: currency, exponent: exponent);

  Money _sum(Money Function(TerminalSales) figure) =>
      terminals.fold(_zero, (sum, t) => sum + figure(t));

  int get orders => terminals.fold(0, (sum, t) => sum + t.orders);
  int get refundCount => terminals.fold(0, (sum, t) => sum + t.refundCount);

  Money get gross => _sum((t) => t.gross);
  Money get discounts => _sum((t) => t.discounts);
  Money get refunds => _sum((t) => t.refunds);

  /// Summed from the rows' own net rather than recomputed from the branch's
  /// gross, discounts and refunds. They are equal — rule 5 is linear — and
  /// summing the rows is what keeps "the branch is the rows" literally true
  /// if either formula ever changes.
  Money get net => _sum((t) => t.net);

  Money get cash => _sum((t) => t.cash);
  Money get electronic => _sum((t) => t.electronic);
  Money get onAccount => _sum((t) => t.onAccount);
  Money get otherTender => _sum((t) => t.otherTender);
  Money get collected => _sum((t) => t.collected);

  /// Payments collected by method, merged across terminals — the branch
  /// summary's list. Merged from the rows, so it reconciles to them by
  /// construction.
  List<MethodTotal> get paymentsByMethod {
    final merged = <MethodTotal>[];
    for (final payment in terminals.expand((t) => t.payments)) {
      final at = merged.indexWhere((m) => m.sameMethodAs(payment));
      if (at < 0) {
        merged.add(payment);
      } else {
        merged[at] = merged[at].plus(payment);
      }
    }
    return List.unmodifiable(merged);
  }

  TerminalSales? terminal(String terminalId) {
    for (final t in terminals) {
      if (t.terminalId == terminalId) return t;
    }
    return null;
  }
}

/// The branch for one business day: its terminals, and totals read off them.
class BranchSales with TerminalRollup {
  const BranchSales({
    required this.branchId,
    required this.businessDay,
    required this.terminals,
    this.currency = 'EGP',
    this.exponent = 2,
  });

  final int branchId;

  /// The date that NAMES the trading day — not a calendar window. A night that
  /// runs to 2 a.m. is one business day (§0 rule 5).
  final DateTime businessDay;

  @override
  final List<TerminalSales> terminals;

  @override
  final String currency;
  @override
  final int exponent;
}

/// One sale on another terminal, for drill-down on a per-till cloud branch.
///
/// Deliberately thinner than `OrderRecord`: it is what the platform returns
/// for somebody else's till, and this till has none of its lines, tax rows or
/// audit trail. On a shared database the drill-down is S1's sales list, not
/// this.
class BranchTerminalSale {
  const BranchTerminalSale({
    required this.serverId,
    required this.occurredAt,
    required this.total,
    required this.discount,
    required this.refunded,
    this.clientTransactionId,
    this.invoiceNumber,
    this.settlementStatus,
    this.actingUserId,
  });

  final int serverId;
  final String? clientTransactionId;
  final String? invoiceNumber;

  /// The platform's derived payment status, as sent. Kept as the wire value
  /// this round because nothing shows it yet; the screen that does must map
  /// it onto an enum with a label in both languages, never switch on the
  /// string.
  final String? settlementStatus;
  final DateTime occurredAt;
  final Money total;
  final Money discount;
  final Money refunded;
  final int? actingUserId;
}

/// `YYYY-MM-DD` — how a business day travels, in SQL and on the wire alike.
String businessDayWire(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
