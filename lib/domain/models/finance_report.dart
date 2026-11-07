/// Finance's read model — plan 19 BO-9: taxes by rate, the payment ledger,
/// and the periods the tab reads them over.
///
/// **Read-only, over ledgers that already exist** (owner, 14 Sep). Revenue and
/// the tender bar are not here: they are BO-5's [SalesReport], read through
/// the same provider the Reports tab reads, so Finance's revenue and Reports'
/// are one query and cannot disagree. What this file adds is only what that
/// report does not carry — tax, by rate, and payments one row each.
library;

import '../../core/money/money.dart';
import '../services/payment_status.dart';
import 'branch_sales.dart';
import 'business_day.dart';
import 'order_record.dart';
import 'sales_report.dart';
import 'supplier_invoice.dart';
import 'tender_method.dart';

/// One rate's tax over a range: what the sales were charged, and what the
/// refunds issued in the range gave back.
///
/// Keyed by rate AND name, as `pos_order_taxes` is: a business that renamed
/// "VAT" mid-month sees two rows, because that is what its receipts said.
class TaxCollected {
  const TaxCollected({
    required this.name,
    required this.rateBp,
    required this.orders,
    required this.base,
    required this.charged,
    required this.refunded,
  });

  /// The name the sale's receipt printed (`name_snapshot`), not today's.
  final String name;

  /// Basis points. 1400 = 14%, 0 = zero-rated.
  final int rateBp;

  /// Sales in the range taxed at this rate.
  final int orders;

  /// What this rate was charged on, on those sales — before refunds. A refund
  /// row carries no base by rate, and inventing one would be a figure no
  /// receipt ever printed.
  final Money base;

  /// The sum of `pos_order_taxes.amount_minor` for the range's sales.
  final Money charged;

  /// This rate's part of the VAT of refunds ISSUED in the range, whatever day
  /// the sale was — a credit note belongs to the period it was given in, as a
  /// refund belongs to the drawer that paid it (plan 17 §3a rule 4).
  final Money refunded;

  Money get net => charged - refunded;
}

/// Tax for one [filter], by rate.
///
/// **The total is the rows.** Charged and refunded are summed off [rates]
/// here, never stored beside them — the rule `TerminalRollup` holds for the
/// sales figures, for the same reason.
class TaxReport {
  const TaxReport({
    required this.filter,
    required this.rates,
    required this.unattributedRefunds,
    this.currency = 'EGP',
    this.exponent = 2,
  });

  final ReportFilter filter;

  /// Highest rate first, so the standard rate leads and the exceptions read
  /// as exceptions — the order a receipt prints them in.
  final List<TaxCollected> rates;

  /// Refund VAT whose sale recorded no rate at all. Migration 16 gave every
  /// taxed sale a breakdown, so this should be zero; it is carried rather than
  /// dropped because a refund's tax that vanished from the total would leave
  /// the refunded column short with nothing on screen to say why.
  final Money unattributedRefunds;

  final String currency;
  final int exponent;

  Money get _zero => Money(0, currency: currency, exponent: exponent);

  Money get charged => rates.fold(_zero, (sum, r) => sum + r.charged);

  Money get refunded =>
      rates.fold(unattributedRefunds, (sum, r) => sum + r.refunded);

  Money get net => charged - refunded;
}

/// One `pos_order_payments` row — the accountant's view (plan 17 S2): a sale
/// paid in three tenders is one row in Sales and three here.
class PaymentEntry {
  const PaymentEntry({
    required this.paymentId,
    required this.orderId,
    required this.invoiceNumber,
    required this.occurredAt,
    required this.terminalId,
    required this.terminalName,
    required this.tenderTypeId,
    required this.label,
    required this.kind,
    required this.countsAsCash,
    required this.amount,
  });

  final int paymentId;
  final int orderId;
  final String invoiceNumber;

  /// When the payment was taken, which for a later settlement is not the
  /// sale's time.
  final DateTime occurredAt;
  final String terminalId;

  /// Null for a terminal not registered to the branch — listed anyway, as
  /// the terminal table lists it.
  final String? terminalName;
  final int? tenderTypeId;

  /// As written on the payment row, the same label the Z report groups by.
  final String label;
  final TenderKind kind;
  final bool countsAsCash;
  final Money amount;

  /// The same rule the tender bar sorts by, so a row and the bar above it
  /// never call one payment two things.
  PaymentBucket get bucket =>
      PaymentBucket.of(kind: kind, countsAsCash: countsAsCash);
}

/// The payments of one [filter]'s sales, newest first.
class PaymentLedger {
  const PaymentLedger({
    required this.filter,
    required this.entries,
    required this.truncated,
    this.currency = 'EGP',
    this.exponent = 2,
  });

  final ReportFilter filter;
  final List<PaymentEntry> entries;

  /// More payments exist than were listed. The screen then says the list is
  /// the newest ones, and takes its method totals from the report rather than
  /// from these rows — a total over a cut list would be a total of nothing.
  final bool truncated;

  final String currency;
  final int exponent;

  /// The rows listed, summed. Equal to collected plus on account when
  /// [truncated] is false.
  Money get total => entries.fold(
    Money(0, currency: currency, exponent: exponent),
    (sum, e) => sum + e.amount,
  );
}

/// The ranges Finance offers. An enum and a total switch for the words, so a
/// fifth period without an Arabic label fails to compile.
///
/// **Months, because tax is filed by month.** Last month is here for the VAT
/// return; a custom range is Reports' (BO-6), not repeated here.
enum FinancePeriod { today, thisWeek, thisMonth, lastMonth }

/// The business dates [period] covers, counted from [today].
///
/// [today] is the business date trading is in — the open day's, when a night
/// has run past midnight — not the calendar's. [firstDayOfWeekIndex] is the
/// locale's, 0 for Sunday (`MaterialLocalizations`): Egypt's week starts on
/// Saturday in Arabic and Sunday in English, and hard-coding either is a week
/// that starts wrong for half the people reading it.
///
/// Periods run up to and including today, never past it: a month of 30 days
/// on the 14th would draw sixteen days of zeros and read as a collapse.
ReportFilter financeFilter(
  FinancePeriod period, {
  required DateTime today,
  required int firstDayOfWeekIndex,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final tomorrow = DateTime(day.year, day.month, day.day + 1);
  return switch (period) {
    FinancePeriod.today => ReportFilter(from: day, to: tomorrow),
    FinancePeriod.thisWeek => ReportFilter(
      // `weekday % 7` is 0 for Sunday, as the index is.
      from: DateTime(
        day.year,
        day.month,
        day.day - (day.weekday % 7 - firstDayOfWeekIndex) % 7,
      ),
      to: tomorrow,
    ),
    FinancePeriod.thisMonth => ReportFilter(
      from: DateTime(day.year, day.month),
      to: tomorrow,
    ),
    FinancePeriod.lastMonth => ReportFilter(
      from: DateTime(day.year, day.month - 1),
      to: DateTime(day.year, day.month),
    ),
  };
}

// ── BO-10: expenses, bills due, transactions ────────────────────────────────

/// Whether the supplier ledger is in a Finance figure, and if not, why.
///
/// **Three answers, because the label has to say which.** An expenses figure
/// that silently drops supplier payments reads as a month in which nobody was
/// paid; the sentence under it is what stops a manager comparing it with last
/// month's and finding a saving that is not there. An enum and a total switch
/// for the words, so a fourth reason cannot reach the screen unlabelled.
enum SupplierFigures {
  /// Read, through the back office's credential, and counted.
  included,

  /// A cloud till: the platform is the only author of purchasing (CB-09), and
  /// nothing of it comes down to this database.
  onPlatform,

  /// This person may not read the supplier ledger — `purchase.manage`, the
  /// Purchasing pane's gate. A figure made of those rows is those rows.
  notPermitted,
}

/// What a range holds of the supplier ledger (BO-10).
///
/// Read on the administrator's connection; the till holds no grant on either
/// table (doc 16 §6).
class SupplierSpending {
  const SupplierSpending({
    required this.invoices,
    required this.payments,
    required this.drawerMovementIds,
  });

  static const none = SupplierSpending(
    invoices: [],
    payments: [],
    drawerMovementIds: {},
  );

  /// Issued in the range, newest first. Voided ones included — the
  /// transactions table shows them as void rather than hiding them.
  final List<SupplierInvoice> invoices;

  /// Paid in the range, newest first. Voided ones included, for the same
  /// reason; [ExpenseReport] counts only the live ones.
  final List<SupplierPayment> payments;

  /// The drawer pay-outs in the range that a supplier payment — live or
  /// voided — records as its own `cash_movement_id`.
  ///
  /// **The same money twice, unless somebody takes one away.** Paying a
  /// supplier out of a till writes a `pay_out` and the payment in one
  /// transaction; "pay-outs plus supplier payments" read literally counts that
  /// cash twice. The payment is the row that says who was paid and for what,
  /// so it is the one kept, and these pay-outs are left out of the drawer
  /// side. A voided payment's pay-out is left out too: either a `pay_in` put
  /// the cash back, which is not an expense, or the drawer was already counted
  /// and the void's note says where the money went — a loss to explain, not a
  /// supplier paid.
  final Set<int> drawerMovementIds;
}

/// Money paid out over a range: drawer pay-outs and supplier payments.
///
/// **Expenses = drawer pay-outs + supplier payments not voided**, with each
/// supplier paid from a drawer counted once (see
/// [SupplierSpending.drawerMovementIds]). Rent and salaries are not here —
/// there is no expense entity to hold them (Wave Q, doc 16 §4) — and the
/// screen says what is, rather than calling this "all expenses".
class ExpenseReport {
  const ExpenseReport({
    required this.filter,
    required this.payOuts,
    required this.supplierFigures,
    this.suppliers,
    this.currency = 'EGP',
    this.exponent = 2,
  });

  final ReportFilter filter;

  /// Every `pay_out` in the range, as the drawers recorded them.
  final List<CashMovement> payOuts;

  /// Null unless [supplierFigures] is [SupplierFigures.included].
  final SupplierSpending? suppliers;
  final SupplierFigures supplierFigures;

  final String currency;
  final int exponent;

  Money get _zero => Money(0, currency: currency, exponent: exponent);

  /// The pay-outs counted as themselves: all of them, less those that are a
  /// supplier payment's own. Without the ledger nothing is taken away — a
  /// supplier paid from the drawer is still money out of the drawer, and is
  /// counted once, as the pay-out it is.
  List<CashMovement> get drawerPayOuts {
    final linked = suppliers?.drawerMovementIds ?? const <int>{};
    return [
      for (final payOut in payOuts)
        if (!linked.contains(payOut.id)) payOut,
    ];
  }

  /// The supplier payments counted: the range's, less the voided.
  List<SupplierPayment> get supplierPayments => [
    for (final payment in suppliers?.payments ?? const <SupplierPayment>[])
      if (!payment.isVoided) payment,
  ];

  Money get payOutTotal =>
      drawerPayOuts.fold(_zero, (sum, p) => sum + p.amount);

  Money get supplierTotal =>
      supplierPayments.fold(_zero, (sum, p) => sum + p.amount);

  /// The figure. The rows above, summed — never stored beside them.
  Money get total => payOutTotal + supplierTotal;

  /// Both kinds as one list, newest first — the rows the total is made of.
  List<FinanceTransaction> get entries => [
    for (final payOut in drawerPayOuts) PayOutTransaction(payOut),
    for (final payment in supplierPayments) SupplierPaymentTransaction(payment),
  ]..sort(FinanceTransaction.newestFirst);
}

/// Which of the bills-due groups an unpaid invoice is in.
///
/// **A partition, so four groups where the mockup drew three.** Overdue, due
/// today and due within the week leave out every bill due later, and a total
/// beside three figures that do not add up to it is a card nobody trusts. An
/// enum, keyed by a total switch for its words.
enum BillsDueBucket {
  /// The due date is before the business date.
  overdue,

  /// Due on the business date itself.
  dueToday,

  /// Due within the seven days after it.
  nextSevenDays,

  /// Due later than that.
  later,
}

/// The group [dueAt] falls in, against [businessDate].
///
/// **By date, not by instant.** A bill due on the 14th is due all of the
/// 14th, whatever time of day the form stored; comparing instants would make
/// it overdue at 00:01 — or, for one stored at noon UTC, at three in the
/// afternoon in Cairo. The due date is the local calendar date of [dueAt],
/// as every date in this product is read, and [businessDate] is the day
/// trading is in: at 1 a.m. after a late night that is still yesterday's.
///
/// Days are counted on calendar dates, never in 24-hour steps: Egypt keeps
/// summer time, and a week counted in hours lands on the wrong day twice a
/// year.
BillsDueBucket billsDueBucket(DateTime dueAt, {required DateTime businessDate}) {
  final local = dueAt.toLocal();
  final due = DateTime(local.year, local.month, local.day);
  final today = DateTime(businessDate.year, businessDate.month, businessDate.day);
  final weekOut = DateTime(today.year, today.month, today.day + 7);
  if (due.isBefore(today)) return BillsDueBucket.overdue;
  if (due == today) return BillsDueBucket.dueToday;
  if (!due.isAfter(weekOut)) return BillsDueBucket.nextSevenDays;
  return BillsDueBucket.later;
}

/// What is owed to suppliers, grouped by when it falls due (BO-10).
///
/// Built from `SupplierInvoicesRepository.unpaid` — the Purchasing pane's own
/// worklist, so the card and the pane cannot disagree about what is owed —
/// and nothing else. Amounts are what is still outstanding on each bill. On-
/// account money is not taken off: it lowers what a supplier is owed but
/// clears no particular bill, which is `SupplierAccount.overdue`'s rule too.
class BillsDue {
  BillsDue.of(
    Iterable<SupplierInvoice> unpaid, {
    required DateTime businessDate,
    this.currency = 'EGP',
    this.exponent = 2,
  }) : businessDate = DateTime(
         businessDate.year,
         businessDate.month,
         businessDate.day,
       ),
       invoices = List.unmodifiable(unpaid);

  final DateTime businessDate;

  /// Oldest due first, as [unpaid] returned them.
  final List<SupplierInvoice> invoices;

  final String currency;
  final int exponent;

  Money get _zero => Money(0, currency: currency, exponent: exponent);

  BillsDueBucket bucketOf(SupplierInvoice invoice) =>
      billsDueBucket(invoice.dueAt, businessDate: businessDate);

  List<SupplierInvoice> inBucket(BillsDueBucket bucket) => [
    for (final invoice in invoices)
      if (bucketOf(invoice) == bucket) invoice,
  ];

  int count(BillsDueBucket bucket) => inBucket(bucket).length;

  Money amount(BillsDueBucket bucket) =>
      inBucket(bucket).fold(_zero, (sum, i) => sum + i.outstanding);

  /// Summed over [invoices], not over the groups — so "the groups add up to
  /// the total" is a claim a test can check rather than a tautology.
  Money get total => invoices.fold(_zero, (sum, i) => sum + i.outstanding);
}

/// What the transactions table calls a row. Enum-keyed words.
enum FinanceTransactionKind { sale, payOut, supplierInvoice, supplierPayment }

/// A row's state, in the source's own terms (plan 19 §2.4: "pending" has no
/// producer, so it is not offered).
enum FinanceTransactionStatus {
  paid,
  partlyPaid,
  unpaid,
  partlyRefunded,
  refunded,

  /// A sale still in flight — committed, not yet settled.
  open,
  voided,

  /// A pay-out: it happened, and a drawer movement has no other state.
  recorded,
}

/// One row of the transactions table: a sale, a drawer pay-out, a supplier
/// invoice or a supplier payment, as its own table recorded it.
///
/// **Sealed, and each case holds its source row.** The table needs a
/// different reference from each — an invoice number, a reason, a supplier —
/// and a switch over the cases is exhaustive, so a fifth kind of row cannot
/// reach the screen without a way to be drawn.
sealed class FinanceTransaction {
  const FinanceTransaction();

  FinanceTransactionKind get kind;
  int get sourceId;
  DateTime get occurredAt;

  /// Signed as money moves for the business: a sale in, the rest out. A
  /// supplier invoice is a bill rather than money that moved, and is signed
  /// as what it will cost; its payment is a row of its own.
  Money get amount;
  FinanceTransactionStatus get status;

  /// Newest first; within one instant by kind, then by the source's id, so
  /// every row has exactly one place in the list.
  static int newestFirst(FinanceTransaction a, FinanceTransaction b) {
    final at = b.occurredAt.compareTo(a.occurredAt);
    if (at != 0) return at;
    final kind = a.kind.index - b.kind.index;
    return kind != 0 ? kind : b.sourceId - a.sourceId;
  }
}

final class SaleTransaction extends FinanceTransaction {
  const SaleTransaction(this.sale);

  final OrderRecord sale;

  @override
  FinanceTransactionKind get kind => FinanceTransactionKind.sale;
  @override
  int get sourceId => sale.id;
  @override
  DateTime get occurredAt => sale.occurredAt;
  @override
  Money get amount => sale.total;

  /// The order's own state where it says the money never came — void,
  /// cancelled, not yet settled — and where the money stands otherwise, by
  /// the sales list's payment rule.
  @override
  FinanceTransactionStatus get status => switch (sale.status) {
    OrderStatus.voided || OrderStatus.cancelled => FinanceTransactionStatus.voided,
    OrderStatus.draft ||
    OrderStatus.open ||
    OrderStatus.sentToKitchen ||
    OrderStatus.ready => FinanceTransactionStatus.open,
    OrderStatus.paid ||
    OrderStatus.closed ||
    OrderStatus.refunded ||
    OrderStatus.partiallyRefunded => switch (sale.paymentStatus) {
      PaymentStatus.paid => FinanceTransactionStatus.paid,
      PaymentStatus.partiallyPaid => FinanceTransactionStatus.partlyPaid,
      PaymentStatus.unpaid => FinanceTransactionStatus.unpaid,
      PaymentStatus.partiallyRefunded =>
        FinanceTransactionStatus.partlyRefunded,
      PaymentStatus.refunded => FinanceTransactionStatus.refunded,
    },
  };
}

final class PayOutTransaction extends FinanceTransaction {
  const PayOutTransaction(this.payOut);

  final CashMovement payOut;

  @override
  FinanceTransactionKind get kind => FinanceTransactionKind.payOut;
  @override
  int get sourceId => payOut.id;
  @override
  DateTime get occurredAt => payOut.occurredAt;
  @override
  Money get amount => -payOut.amount;
  @override
  FinanceTransactionStatus get status => FinanceTransactionStatus.recorded;
}

final class SupplierInvoiceTransaction extends FinanceTransaction {
  const SupplierInvoiceTransaction(this.invoice);

  final SupplierInvoice invoice;

  @override
  FinanceTransactionKind get kind => FinanceTransactionKind.supplierInvoice;
  @override
  int get sourceId => invoice.id;
  @override
  DateTime get occurredAt => invoice.issuedAt;
  @override
  Money get amount => -invoice.total;
  @override
  FinanceTransactionStatus get status => invoice.isVoided
      ? FinanceTransactionStatus.voided
      : invoice.isSettled
      ? FinanceTransactionStatus.paid
      : invoice.paid.isPositive
      ? FinanceTransactionStatus.partlyPaid
      : FinanceTransactionStatus.unpaid;
}

final class SupplierPaymentTransaction extends FinanceTransaction {
  const SupplierPaymentTransaction(this.payment);

  final SupplierPayment payment;

  @override
  FinanceTransactionKind get kind => FinanceTransactionKind.supplierPayment;
  @override
  int get sourceId => payment.id;
  @override
  DateTime get occurredAt => payment.paidAt;
  @override
  Money get amount => -payment.amount;
  @override
  FinanceTransactionStatus get status => payment.isVoided
      ? FinanceTransactionStatus.voided
      : FinanceTransactionStatus.paid;
}

/// The union table (plan 19 §2.4): sales, drawer pay-outs, supplier invoices
/// and supplier payments over one range, newest first.
///
/// **No total line, on purpose.** An invoice and the payment that settles it
/// are two rows for one debt, so a sum down this column would count it twice.
/// The figures are the other panes'; this is where they are traced.
class FinanceTransactions {
  /// The newest [limit] rows of the four sources merged.
  ///
  /// **Each source cut at [limit] first, and the merge still exact.** Any row
  /// in the true newest [limit] of the union is in the newest [limit] of its
  /// own source, so reading [limit] of each and cutting the merge is the same
  /// list as merging everything — at the cost of [limit] rows per source,
  /// not every sale of the month. [salesCut] says the sales read stopped at
  /// its limit, so there are older sales than any listed.
  factory FinanceTransactions.of({
    required List<OrderRecord> sales,
    required bool salesCut,
    required ExpenseReport expenses,
    int limit = FinanceTransactions.limit,
  }) {
    final all = <FinanceTransaction>[
      for (final sale in sales) SaleTransaction(sale),
      // The drawer's, less any a supplier payment owns — the payment is its
      // row, as in the expenses figure.
      for (final payOut in expenses.drawerPayOuts) PayOutTransaction(payOut),
      for (final invoice in expenses.suppliers?.invoices ??
          const <SupplierInvoice>[])
        SupplierInvoiceTransaction(invoice),
      for (final payment in expenses.suppliers?.payments ??
          const <SupplierPayment>[])
        SupplierPaymentTransaction(payment),
    ]..sort(FinanceTransaction.newestFirst);
    return FinanceTransactions._(
      entries: List.unmodifiable(all.take(limit)),
      truncated: salesCut || all.length > limit,
    );
  }

  const FinanceTransactions._({required this.entries, required this.truncated});

  /// Rows read per source, and rows listed. Two hundred, as the payment
  /// ledger's cut is five hundred: enough for a week of a busy branch, and a
  /// month narrows to it with the period chips.
  static const limit = 200;

  final List<FinanceTransaction> entries;

  /// Older rows exist than the ones listed.
  final bool truncated;
}
