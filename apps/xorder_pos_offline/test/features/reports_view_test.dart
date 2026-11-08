import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/home_sales.dart' show deltaBp;
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos_offline/features/admin/application/reports_view.dart';
import 'package:xorder_pos_offline/features/admin/presentation/report_charts.dart';

/// The Reports tab's rules that are not drawing: which days a period means,
/// what the trend plots, which day and till stand out — and the charts'
/// geometry, held to numbers rather than to pixels on a screenshot.
void main() {
  // Thursday.
  final thursday = DateTime(2026, 9, 10);

  group('the period chips', () {
    test('today is the one business date', () {
      final filter = reportFilterFor(
        ReportPeriod.today,
        today: DateTime(2026, 9, 10, 14, 7),
        firstDayOfWeekIndex: 0,
      );
      expect(filter, ReportFilter.day(thursday));
    });

    test("this week starts on the locale's first day, and runs to today", () {
      DateTime startFor(int first, [DateTime? today]) => reportFilterFor(
        ReportPeriod.week,
        today: today ?? thursday,
        firstDayOfWeekIndex: first,
      ).from;

      expect(startFor(0), DateTime(2026, 9, 6), reason: 'Sunday, as en');
      expect(startFor(6), DateTime(2026, 9, 5), reason: 'Saturday, as ar');
      expect(startFor(1), DateTime(2026, 9, 7), reason: 'Monday');
      // On the first day itself the week is that one day, not last week.
      expect(startFor(6, DateTime(2026, 9, 12)), DateTime(2026, 9, 12));
      expect(
        reportFilterFor(
          ReportPeriod.week,
          today: thursday,
          firstDayOfWeekIndex: 6,
        ).to,
        DateTime(2026, 9, 11),
      );
    });

    test('this month is the first to today, and compared with as many days '
        'before it', () {
      final month = reportFilterFor(
        ReportPeriod.month,
        today: thursday,
        firstDayOfWeekIndex: 0,
      );
      expect(month.from, DateTime(2026, 9, 1));
      expect(month.to, DateTime(2026, 9, 11));
      expect(month.previous.from, DateTime(2026, 8, 22));
      expect(month.previous.to, DateTime(2026, 9, 1));
    });

    test('a custom range includes the last date picked', () {
      final custom = reportFilterFor(
        ReportPeriod.custom,
        today: thursday,
        firstDayOfWeekIndex: 0,
        custom: (first: DateTime(2026, 8, 1), last: DateTime(2026, 8, 3)),
      );
      expect(custom.dates, [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 2),
        DateTime(2026, 8, 3),
      ]);
      expect(
        () => reportFilterFor(
          ReportPeriod.custom,
          today: thursday,
          firstDayOfWeekIndex: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  ReportDay day(int d, {int orders = 1, int gross = 0, int refunds = 0}) =>
      ReportDay(
        date: DateTime(2026, 9, d),
        orders: orders,
        gross: Money(gross),
        discounts: Money.zero,
        refunds: Money(refunds),
        refundCount: refunds > 0 ? 1 : 0,
      );

  TerminalSales till(String id, int gross, {String? name}) => TerminalSales(
    terminalId: id,
    name: name ?? id,
    orders: 1,
    gross: Money(gross),
    discounts: Money.zero,
    refunds: Money.zero,
    refundCount: 0,
  );

  SalesReport report({
    List<ReportDay> days = const [],
    List<TerminalSales> terminals = const [],
  }) => SalesReport(
    filter: ReportFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 4)),
    terminals: terminals,
    days: days,
  );

  test("the trend plots a day's own figures, and a shut day's average is a "
      'gap', () {
    final busy = day(1, orders: 3, gross: 1000, refunds: 100);
    expect(trendValue(busy, ReportTrendMetric.net), 900);
    expect(trendValue(busy, ReportTrendMetric.orders), 3);
    expect(trendValue(busy, ReportTrendMetric.average), 300);
    final shut = day(2, orders: 0);
    expect(trendValue(shut, ReportTrendMetric.net), 0);
    expect(trendValue(shut, ReportTrendMetric.average), isNull);
  });

  group('the insights', () {
    test('the best day and the busiest till, ties to the first', () {
      final insights = ReportInsights.of(
        report(
          days: [day(1, gross: 500), day(2, gross: 900), day(3, gross: 900)],
          terminals: [till('a', 200), till('b', 700), till('c', 700)],
        ),
      );
      expect(insights.bestDay!.date, DateTime(2026, 9, 2));
      expect(insights.topTerminal!.terminalId, 'b');
      expect(insights.netDeltaBp, isNull, reason: 'no previous period');
    });

    test('one day or one till is nothing to be best of, and nothing sold '
        'is nothing to point at', () {
      expect(
        ReportInsights.of(
          report(days: [day(1, gross: 500)], terminals: [till('a', 500)]),
        ).isEmpty,
        isTrue,
      );
      expect(
        ReportInsights.of(
          report(
            days: [day(1), day(2)],
            terminals: [till('a', 0), till('b', 0)],
          ),
        ).isEmpty,
        isTrue,
      );
    });

    test('the growth is the net tile\'s own change', () {
      final now = report(terminals: [till('a', 1250)]);
      final before = report(terminals: [till('a', 1000)]);
      expect(
        ReportInsights.of(now, previous: before).netDeltaBp,
        deltaBp(1250, 1000),
      );
    });
  });

  group('the charts, as geometry', () {
    const plot = Size(300, 100);

    test('time runs from the start edge — the right, in Arabic', () {
      final ltr = trendPoints([10, 20, 30], plot, TextDirection.ltr);
      final rtl = trendPoints([10, 20, 30], plot, TextDirection.rtl);
      expect(ltr.first!.dx, 0);
      expect(ltr.last!.dx, 300);
      expect(rtl.first!.dx, 300);
      expect(rtl.last!.dx, 0);
      // Mirrored, not re-scaled: the heights are the same.
      expect([for (final p in rtl) p!.dy], [for (final p in ltr) p!.dy]);
    });

    test('zero is always on the chart, and a gap stays a gap', () {
      final points = trendPoints([50, null, 100], plot, TextDirection.ltr);
      expect(points[1], isNull);
      expect(points[0]!.dy, 50, reason: 'half of 100, measured from zero');
      expect(points[2]!.dy, 0);
      expect(trendPoints([7], plot, TextDirection.rtl).single!.dx, 150);
    });

    test('shares fill the bar exactly, from the start edge', () {
      final ltr = shareSpans([3334, 3333, 3333], 300, TextDirection.ltr);
      expect(ltr.first.$1, 0);
      expect(ltr.last.$2, 300);
      final rtl = shareSpans([3334, 3333, 3333], 300, TextDirection.rtl);
      expect(rtl.first.$2, 300);
      expect(rtl.last.$1, 0);
    });

    test('a bar is measured against the longest', () {
      expect(rankLength(24, 48, 200), 100);
      expect(rankLength(0, 48, 200), 0);
      expect(rankLength(5, 0, 200), 0);
    });
  });
}
