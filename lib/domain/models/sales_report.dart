/// Wave G's read model — plan 11 §9, plan 17 S3, plan 19 BO-5. One branch, a
/// range of business days, and the figures the Reports tab draws.
///
/// **Every figure is the sum of the rows its drill-down lists** (plan 17 S3).
/// That is designed in rather than hoped for:
///
/// * the sales counted are exactly the rows `OrderHistoryRepository.search`
///   returns for [ReportFilter.historyQuery] — the reports build their WHERE
///   from the history's own, not from a restatement of it;
/// * the period totals, the per-day series and the per-terminal table are all
///   read off one set of (day, terminal) cells, so none of them can disagree
///   with another by a sale committed between two reads;
/// * a refund is filed under the day it was ISSUED and the terminal that
///   issued it (§3a rule 4) — it is that drawer the money left — never the
///   original sale's.
library;

import 'package:collection/collection.dart';

import '../../core/money/money.dart';
import '../../core/money/rounding.dart';
import 'branch_sales.dart';
import 'order_record.dart';
import 'ticket.dart' show OrderType;

/// What a report is over. Plan 11 §9's `ReportFilter`, minus the branch: a
/// till reads its own branch and no other (plan 17 §2), so the branch is the
/// repository's, fixed at setup, and not something a filter can name.
class ReportFilter {
  /// [from] inclusive, [to] exclusive, both **business dates** — the dates
  /// that name trading days, not calendar windows. A night that runs to 2 a.m.
  /// is one date (§0 rule 5). A sale no business day covers is filed by its
  /// local calendar date, exactly as the sales list files it.
  ///
  /// Both are cut to local midnight, so a caller passing `DateTime.now()`
  /// gets the day it meant rather than a range that starts at 14:07.
  ReportFilter({
    required DateTime from,
    required DateTime to,
    this.terminalId,
    this.servedByStaffId,
    this.orderTypes = const {},
  }) : from = _date(from),
       to = _date(to) {
    if (!this.from.isBefore(this.to)) {
      throw ArgumentError(
        'A report covers at least one day: $from is not before $to.',
      );
    }
  }

  /// One business day.
  factory ReportFilter.day(
    DateTime day, {
    String? terminalId,
    int? servedByStaffId,
    Set<OrderType> orderTypes = const {},
  }) => ReportFilter(
    from: day,
    to: DateTime(day.year, day.month, day.day + 1),
    terminalId: terminalId,
    servedByStaffId: servedByStaffId,
    orderTypes: orderTypes,
  );

  final DateTime from;
  final DateTime to;

  /// `pos_terminals.id` as text. Sales rung up at it, and refunds ISSUED at it.
  final String? terminalId;

  /// Sales this person rang up (`served_by`), and refunds this person issued
  /// (`refunded_by`). Issued, not "against their sales", for the same reason
  /// a refund belongs to the terminal that gave the money back: it is the act
  /// of the person who did it.
  final int? servedByStaffId;

  /// Empty means every type. A refund carries no order type of its own; it is
  /// counted under its sale's.
  final Set<OrderType> orderTypes;

  static DateTime _date(DateTime at) => DateTime(at.year, at.month, at.day);

  /// Every business date in the range, in order.
  ///
  /// Built by calendar arithmetic on local dates, never by adding 24-hour
  /// durations: Egypt keeps summer time, and a range stepped in hours lands on
  /// 23:00 of the wrong day twice a year.
  List<DateTime> get dates => [
    for (
      var day = from;
      day.isBefore(to);
      day = DateTime(day.year, day.month, day.day + 1)
    )
      day,
  ];

  /// The same number of days immediately before this range, with the same
  /// terminal, person and types — what a "vs previous period" delta compares
  /// against.
  ReportFilter get previous => ReportFilter(
    from: DateTime(from.year, from.month, from.day - dates.length),
    to: from,
    terminalId: terminalId,
    servedByStaffId: servedByStaffId,
    orderTypes: orderTypes,
  );

  /// The sales list this report's sales figures drill into (plan 17 S1). The
  /// reports run over exactly the rows this query lists; a tile that opened
  /// anything else would be a tile whose number the list does not explain.
  ///
  /// [limit] is the list's ceiling and has no part in the figures.
  OrderHistoryQuery historyQuery({int limit = 200}) => OrderHistoryQuery(
    from: from,
    to: to,
    statuses: settledStatuses,
    orderTypes: orderTypes,
    servedByStaffId: servedByStaffId,
    terminalId: terminalId,
    limit: limit,
  );

  /// Value equality: this is the key of a `FutureProvider.family`, and a
  /// screen builds a fresh filter on every rebuild. See [OrderHistoryQuery]'s
  /// `==` for the loop identity equality caused there.
  @override
  bool operator ==(Object other) =>
      other is ReportFilter &&
      other.from == from &&
      other.to == to &&
      other.terminalId == terminalId &&
      other.servedByStaffId == servedByStaffId &&
      const SetEquality<OrderType>().equals(other.orderTypes, orderTypes);

  @override
  int get hashCode => Object.hash(
    from,
    to,
    terminalId,
    servedByStaffId,
    const SetEquality<OrderType>().hash(orderTypes),
  );
}

/// One business date of the trend. Days with nothing are present, at zero: a
/// trend line with a missing Tuesday draws Monday straight to Wednesday and
/// hides the day the restaurant was shut.
class ReportDay {
  const ReportDay({
    required this.date,
    required this.orders,
    required this.gross,
    required this.discounts,
    required this.refunds,
    required this.refundCount,
  });

  final DateTime date;
  final int orders;

  /// Before discounts, as [TerminalSales.gross].
  final Money gross;
  final Money discounts;

  /// Refunds issued on this date, whatever day the sale was.
  final Money refunds;
  final int refundCount;

  /// §3a rule 5.
  Money get net => gross - discounts - refunds;

  /// This date's net per order — the trend's third line (plan 19 §2.3).
  ///
  /// [SalesReport.averageOrder]'s rule, one day wide: net, rounded half-up
  /// once, here. A getter on the day rather than a division in the chart, so
  /// the line and the tile above it cannot come to round differently. Null
  /// with no orders: a day the restaurant was shut is a gap in the average,
  /// where drawing zero would read as a day of free food.
  Money? get averageOrder =>
      orders == 0 ? null : net.copyWith(minor: roundHalfUp(net.minor, orders));
}

/// Which way the top-products list is ranked.
enum ProductRanking { quantity, amount }

/// One product's sales over the range.
///
/// **Net of refunded and voided units, before discounts.** Quantity is what
/// was sold and kept: a voided line never left the kitchen's ticket as a sale,
/// and a refunded unit came back. The amount is that quantity at the unit
/// price it was sold at. Discounts are not taken off: an order-level discount
/// belongs to no one line, and splitting it across lines would be a rule this
/// report invented. The label on screen has to say "before discounts".
///
/// Unlike the refunds figure, a refund here is taken off the sale's own
/// period, not the refund's: the question is "what sold", and a Koshari sold
/// on Monday and brought back on Tuesday was not a Tuesday sale of anything.
class ProductSales {
  const ProductSales({
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.amount,
  });

  /// Null for a line that names no menu item — an open-price charge or a
  /// combo. Those are grouped by the name they were sold under.
  final int? menuItemId;

  /// The name on the most recent line sold, so a dish renamed mid-range shows
  /// under the name the kitchen uses now.
  final String name;

  /// Whole units. `pos_order_lines.quantity` counts portions, not thousandths.
  final int quantity;
  final Money amount;
}

/// One payment method's part of what was collected.
class TenderShare {
  const TenderShare({required this.method, required this.basisPoints});

  final MethodTotal method;

  /// Of the collected total, in basis points. The shares of one report sum to
  /// exactly 10,000 — see [basisPointShares].
  final int basisPoints;
}

/// The Reports tab's figures for one [filter].
///
/// Totals are read off [terminals] (through [TerminalRollup]), exactly as the
/// branch view's are, so the per-terminal table and the tiles above it agree
/// to the piastre by construction. [days] is the same cells summed the other
/// way.
class SalesReport with TerminalRollup {
  const SalesReport({
    required this.filter,
    required this.terminals,
    required this.days,
    this.currency = 'EGP',
    this.exponent = 2,
  });

  final ReportFilter filter;

  /// Every terminal of the branch, zeros included (§3a rule 2) — or only the
  /// filter's terminal, when it names one.
  @override
  final List<TerminalSales> terminals;

  /// Every date of [filter], in order, zeros included.
  final List<ReportDay> days;

  @override
  final String currency;
  @override
  final int exponent;

  /// Net sales per order, rounded half-up once, here.
  ///
  /// Net, not what the orders were charged: plan 19 §2.1 defines Home's
  /// average as net ÷ orders, and one word meaning two numbers on two tabs is
  /// the thing a manager reconciles by hand. It follows that a day heavy with
  /// refunds of last week's sales has a lower average, which is true of the
  /// money and is what the tile says.
  ///
  /// Null with no orders — "no average" rather than an average of zero, which
  /// would read as a day of free food.
  Money? get averageOrder =>
      orders == 0 ? null : net.copyWith(minor: roundHalfUp(net.minor, orders));

  /// What was collected, by method, with each method's share.
  ///
  /// On account is not here: it is money owed, not taken (§3a rule 3), and a
  /// bar that gave it a slice would show a debt as takings. It is [onAccount],
  /// shown on its own.
  List<TenderShare> get tenderShares {
    final collected = [
      for (final method in paymentsByMethod)
        if (method.bucket.isCollected) method,
    ];
    final shares = basisPointShares([
      for (final method in collected) method.amount.minor,
    ]);
    return [
      for (var i = 0; i < collected.length; i++)
        TenderShare(method: collected[i], basisPoints: shares[i]),
    ];
  }
}

/// Each of [parts]' share of their sum, in basis points, summing to exactly
/// 10,000 — or all zero when there is nothing to share.
///
/// **Largest remainder, at this one point.** Rounding each share on its own
/// gives 3,333 three times for three equal tenders, and a bar whose legend
/// adds up to 99.99% is a bar somebody asks about. Every part is floored, and
/// the basis points left over go one each to the parts with the largest
/// remainders — ties to the larger part, then to the earlier one, so the same
/// takings always draw the same bar.
List<int> basisPointShares(List<int> parts) {
  if (parts.any((part) => part < 0)) {
    throw ArgumentError.value(
      parts,
      'parts',
      'A share is of money taken; none of it can be negative.',
    );
  }
  const whole = 10000;
  final total = parts.sum;
  if (total == 0) return List.filled(parts.length, 0);

  final shares = [for (final part in parts) part * whole ~/ total];
  final remainders = [for (final part in parts) part * whole % total];
  var left = whole - shares.sum;

  final order = List.generate(parts.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      if (byRemainder != 0) return byRemainder;
      final byPart = parts[b].compareTo(parts[a]);
      return byPart != 0 ? byPart : a.compareTo(b);
    });
  for (final i in order) {
    if (left == 0) break;
    shares[i]++;
    left--;
  }
  return shares;
}
