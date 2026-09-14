/// Plan 19 §2.1 — the back office's Home: one business day's takings, and the
/// day before it cut at the same time since it opened.
///
/// **No figure here is new arithmetic over sales.** Net, orders and the rows
/// behind them are [BranchSales]'s; this file only divides one of them by
/// another (the average) and compares two days (the delta). A Home that summed
/// orders itself would be a second definition of a day's takings, one screen
/// away from the day close that already has one.
library;

import '../../core/money/money.dart';
import '../../core/money/rounding.dart';
import 'branch_sales.dart';
import 'business_day.dart';

/// What Home's tiles show: a day, and what to compare it with.
class HomeSales {
  const HomeSales({
    required this.day,
    required this.sales,
    this.previousDay,
    this.previous,
  });

  /// The open day, or — when none is open — the last one closed. Home says
  /// which (see [isOpen]); a closed day's figures shown as "today" would tell
  /// a manager at 9 a.m. that they have already taken last night's money.
  final BusinessDay day;

  /// [day]'s takings, whole — exactly `BranchSales` for that business day.
  final BranchSales sales;

  /// The closed day before [day], by business date. Null on a branch's first
  /// day, when there is nothing to compare with.
  final BusinessDay? previousDay;

  /// [previousDay]'s takings up to [comparisonCut] — not the whole day.
  final BranchSales? previous;

  bool get isOpen => day.isOpen;

  Money? get average => averageOrder(sales);

  int? get netDeltaBp => switch (previous) {
    final before? => deltaBp(sales.net.minor, before.net.minor),
    null => null,
  };

  int? get ordersDeltaBp => switch (previous) {
    final before? => deltaBp(sales.orders, before.orders),
    null => null,
  };

  int? get averageDeltaBp => switch ((average, previous)) {
    (final now?, final before?) => switch (averageOrder(before)) {
      final then? => deltaBp(now.minor, then.minor),
      null => null,
    },
    _ => null,
  };
}

/// Net ÷ orders, in whole minor units, rounded half up — once, here.
///
/// Net rather than gross, because gross before discounts and refunds is money
/// the restaurant never had: an average built on it flatters every day that
/// gave anything away. Null with no orders, rather than zero: a zero average
/// is a claim about orders, and there were none.
Money? averageOrder(BranchSales sales) => sales.orders == 0
    ? null
    : sales.net.copyWith(minor: roundHalfUp(sales.net.minor, sales.orders));

/// The change from [before] to [now], in basis points (1250 = +12.50%).
///
/// Integer, like every share in this codebase, and rounded once. Null when
/// [before] is zero: "up infinity percent" on the first sale of a quiet day is
/// not a number anybody can act on. Divided by the MAGNITUDE of [before], so a
/// day that went from −100 to +100 net (a refund-heavy morning recovering)
/// reads as up, not down.
int? deltaBp(int now, int before) =>
    before == 0 ? null : roundHalfUp((now - before) * 10000, before.abs());

/// Where to cut [previous]: as long after it opened as [day] has been open.
///
/// **Elapsed since opening, not the clock time.** A restaurant that opened at
/// 10 today and at 8 yesterday is two hours into its day at noon, and
/// yesterday at noon it was four — comparing the clock would make today look
/// short by two hours of trade it never had the chance to do. The rule is the
/// plan's (§2.1): a whole-day comparison reads as a collapse every morning,
/// and a clock-time one reads as one every late opening.
///
/// A closed [day] is compared over its whole length, so the last closed day
/// shown on a morning with nothing open is held against the same span of the
/// day before it. Never negative: a clock behind the day's own opening cuts
/// at the opening, and compares with nothing rather than with the future.
DateTime comparisonCut({
  required BusinessDay day,
  required BusinessDay previous,
  required DateTime now,
}) {
  final elapsed = (day.closedAt ?? now).difference(day.openedAt);
  return previous.openedAt.add(elapsed.isNegative ? Duration.zero : elapsed);
}
