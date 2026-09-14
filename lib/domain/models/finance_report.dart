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
import 'branch_sales.dart';
import 'sales_report.dart';
import 'tender_method.dart';

/// One rate's tax over a range: what the sales were charged, and what the
/// refunds issued in the range gave back.
///
/// Keyed by rate AND name, as `pos_order_taxes` is: a restaurant that renamed
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
