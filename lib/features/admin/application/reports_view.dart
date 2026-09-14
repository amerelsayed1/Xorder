/// The Reports tab's choices, and the three things it reads off a report
/// that BO-5 does not hand over ready-made (plan 19 BO-6).
///
/// **Nothing here adds up sales.** Every figure the tab draws is a getter on
/// `SalesReport`, `ReportDay`, `TerminalSales` or `ProductSales`; this file
/// only decides which range to ask for, which of a day's figures the trend
/// line plots, and which day and which till stood out. A tab that summed
/// orders itself would be a second definition of the takings, one tab away
/// from the Sales list that is meant to explain them.
library;

import '../../../domain/models/branch_sales.dart';
import '../../../domain/models/home_sales.dart' show deltaBp;
import '../../../domain/models/sales_report.dart';

/// What the period chips offer. An enum and a total switch for the words, so
/// a fifth chip without an Arabic label fails to compile.
enum ReportPeriod { today, week, month, custom }

/// The trend line's three readings of a day (plan 19 §2.3: net, orders,
/// average).
enum ReportTrendMetric { net, orders, average }

/// The range [period] covers, ending with [today]'s business date.
///
/// **To date, not whole.** This week and this month run to the end of today,
/// not to Saturday or the 30th: the days after today have taken nothing, and
/// counting them would halve a month's average on the 15th. The comparison is
/// `ReportFilter.previous` — the same number of days just before — so the
/// first nine days of September are held against the nine before them.
///
/// [firstDayOfWeekIndex] is the locale's, as `MaterialLocalizations` reads it
/// from `intl` (0 = Sunday). Not hard-coded: an Egyptian week starts on
/// Saturday and an English one on Sunday, and a "this week" that began on
/// Monday would be nobody's week (plan 19 §2.3).
///
/// [custom] is inclusive at both ends, as a date-range picker returns it.
ReportFilter reportFilterFor(
  ReportPeriod period, {
  required DateTime today,
  required int firstDayOfWeekIndex,
  ({DateTime first, DateTime last})? custom,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final tomorrow = DateTime(day.year, day.month, day.day + 1);
  return switch (period) {
    ReportPeriod.today => ReportFilter.day(day),
    // `weekday % 7` puts Sunday at 0, which is how the index counts.
    ReportPeriod.week => ReportFilter(
      from: DateTime(
        day.year,
        day.month,
        day.day - (day.weekday % 7 - firstDayOfWeekIndex + 7) % 7,
      ),
      to: tomorrow,
    ),
    ReportPeriod.month => ReportFilter(
      from: DateTime(day.year, day.month),
      to: tomorrow,
    ),
    ReportPeriod.custom => switch (custom) {
      (:final first, :final last) => ReportFilter(
        from: first,
        to: DateTime(last.year, last.month, last.day + 1),
      ),
      null => throw ArgumentError.notNull('custom'),
    },
  };
}

/// Which of [day]'s figures the trend plots, as the integer it is — minor
/// units for money, a count for orders.
///
/// Null only for the average of a day with no orders: a gap in the line,
/// where a zero would draw a shut Tuesday as a day of free food.
int? trendValue(ReportDay day, ReportTrendMetric metric) => switch (metric) {
  ReportTrendMetric.net => day.net.minor,
  ReportTrendMetric.orders => day.orders,
  ReportTrendMetric.average => day.averageOrder?.minor,
};

/// The mockup's key insights, as far as there is a source for them (plan 19
/// §2.3): the best day, the busiest till and the headline change. "Top
/// branch" became the busiest till (one branch per till) and "new customers"
/// is cut (there are none to count).
///
/// **Each is a pick, not a sum** — a day and a till out of the lists the
/// report already holds, and the same change the net tile shows. Ties go to
/// the earlier day and to the till listed first, so the same takings always
/// name the same one.
class ReportInsights {
  const ReportInsights({this.bestDay, this.topTerminal, this.netDeltaBp});

  /// Built from [report] and, when it could be read, the period before it.
  factory ReportInsights.of(SalesReport report, {SalesReport? previous}) {
    // A best day needs two days to be best of, and a busiest till two tills:
    // "Thursday was your best day" on a report of Thursday says nothing.
    ReportDay? best;
    if (report.days.length > 1) {
      for (final day in report.days) {
        if (day.net.isPositive &&
            (best == null || day.net.minor > best.net.minor)) {
          best = day;
        }
      }
    }
    TerminalSales? top;
    if (report.terminals.length > 1) {
      for (final till in report.terminals) {
        if (till.net.isPositive &&
            (top == null || till.net.minor > top.net.minor)) {
          top = till;
        }
      }
    }
    return ReportInsights(
      bestDay: best,
      topTerminal: top,
      netDeltaBp: switch (previous) {
        final before? => deltaBp(report.net.minor, before.net.minor),
        null => null,
      },
    );
  }

  final ReportDay? bestDay;
  final TerminalSales? topTerminal;
  final int? netDeltaBp;

  bool get isEmpty =>
      bestDay == null && topTerminal == null && netDeltaBp == null;
}
