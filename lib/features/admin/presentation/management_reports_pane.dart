import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/reports_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/branch_sales.dart';
import '../../../domain/models/business_day.dart';
import '../../../domain/models/home_sales.dart' show deltaBp;
import '../../../domain/models/sales_report.dart';
import '../application/reports_view.dart';
import 'management_home_pane.dart' show formatDeltaBp;
import 'report_charts.dart';

String reportPeriodLabel(AppStrings s, ReportPeriod period) =>
    switch (period) {
      ReportPeriod.today => s.reportPeriodToday,
      ReportPeriod.week => s.reportPeriodWeek,
      ReportPeriod.month => s.reportPeriodMonth,
      ReportPeriod.custom => s.reportPeriodCustom,
    };

/// Home's words for the same three figures: the line plots what the tiles
/// above it total, and a different word would read as a different number.
String reportTrendMetricLabel(AppStrings s, ReportTrendMetric metric) =>
    switch (metric) {
      ReportTrendMetric.net => s.homeKpiNetSales,
      ReportTrendMetric.orders => s.homeKpiOrders,
      ReportTrendMetric.average => s.homeKpiAverage,
    };

String productRankingLabel(AppStrings s, ProductRanking ranking) =>
    switch (ranking) {
      ProductRanking.quantity => s.reportRankQuantity,
      ProductRanking.amount => s.reportRankAmount,
    };

/// The Reports tab (BO-6, plan 19 §2.3): a period, four tiles against the
/// period before it, the trend, the top five, the payment methods, the tills
/// and what stands out.
///
/// **Every figure on it is BO-5's.** The tiles and the till table are
/// `SalesReport`'s rollup, the trend is its days, the bar is its
/// `tenderShares`, the list is `topProducts`. What this pane adds is a range
/// to ask for and a comparison of two reports — the change in basis points,
/// by Home's `deltaBp`, so a percentage on this tab and one on Home are the
/// same arithmetic. `back_office_reports_test.dart` holds every value on
/// screen to a fake repository's numbers.
///
/// **Net profit and customers are cut** (plan 19 §2.3): no product has a cost
/// price and no sale has a customer. Refunds took the customers' tile, count
/// and amount, as plan 17 S3 lists it.
///
/// **No drill-down yet.** A till row or a day should open the Sales tab on
/// `ReportFilter.historyQuery()`, but the Sales list takes no query from
/// outside — it has three fixed windows of its own — and BO-3 is rewriting
/// that screen for paging now. Threading a query in beneath it would be a
/// merge of two slices through one widget; it is left for after BO-3.
///
/// **Cloud divergence**, flagged as the plan asks: the platform's Insights
/// page is menu engagement, not sales; this follows plan 17 S3 instead.
class ManagementReportsPane extends ConsumerStatefulWidget {
  const ManagementReportsPane({super.key, this.openedAt});

  /// The clock, for a test about a particular week. See
  /// `OrderHistoryScreen.openedAt`, which this copies for the same reason.
  @visibleForTesting
  final DateTime? openedAt;

  @override
  ConsumerState<ManagementReportsPane> createState() =>
      _ManagementReportsPaneState();
}

class _ManagementReportsPaneState extends ConsumerState<ManagementReportsPane> {
  ReportPeriod _period = ReportPeriod.today;
  ({DateTime first, DateTime last})? _custom;
  ReportTrendMetric _metric = ReportTrendMetric.net;
  ProductRanking _ranking = ProductRanking.quantity;

  /// Read once, as the Sales list reads it: a clock read in `build` makes
  /// every rebuild a new filter, and every new filter a new database read.
  late final DateTime _openedAt = widget.openedAt ?? DateTime.now();

  /// The Sales list's rule for "today": the open day's date while one is
  /// open, the calendar's otherwise. One definition, so Today here and Today
  /// there are the same rows.
  DateTime _today(BusinessDay? day) {
    if (day != null && day.isOpen) return day.date;
    return DateTime(_openedAt.year, _openedAt.month, _openedAt.day);
  }

  Future<void> _pickRange(DateTime today) async {
    final custom = _custom;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: custom == null
          ? null
          : DateTimeRange(start: custom.first, end: custom.last),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = (first: picked.start, last: picked.end);
      _period = ReportPeriod.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final day = ref.watch(businessDayProvider);
    // Wait for the day rather than asking with the calendar and again with
    // the day — two reads, and tiles that visibly change their mind.
    if (day.isLoading) {
      return Center(child: CircularProgressIndicator(color: pos.accent));
    }
    final today = _today(day.valueOrNull);
    final filter = reportFilterFor(
      _period,
      today: today,
      firstDayOfWeekIndex: MaterialLocalizations.of(
        context,
      ).firstDayOfWeekIndex,
      custom: _custom,
    );
    final report = ref.watch(salesReportProvider(filter));
    // Beside the report, not after it: the tiles draw as soon as the period
    // is read and the deltas join them, rather than both waiting on the
    // slower of two reads.
    final previous = ref
        .watch(salesReportProvider(filter.previous))
        .valueOrNull;

    return ListView(
      key: const Key('reports-pane'),
      padding: const EdgeInsets.all(PosSpace.s24),
      children: [
        _PeriodBar(
          period: _period,
          filter: filter,
          onSelect: (period) => period == ReportPeriod.custom
              ? _pickRange(today)
              : setState(() => _period = period),
        ),
        const SizedBox(height: PosSpace.s24),
        ...switch (report) {
          AsyncData(value: final figures?) => _figures(
            context,
            figures,
            previous,
          ),
          // No database behind this till yet. Said, not drawn as zeros: an
          // empty report reads as a week with no sales.
          AsyncData(value: null) => [_Note(strings.reportNoDatabase)],
          AsyncError() => [_Note(strings.reportUnavailable, danger: true)],
          _ => [
            SizedBox(
              height: 240,
              child: Center(
                child: CircularProgressIndicator(color: pos.accent),
              ),
            ),
          ],
        },
      ],
    );
  }

  List<Widget> _figures(
    BuildContext context,
    SalesReport report,
    SalesReport? previous,
  ) {
    final strings = context.strings;
    final average = report.averageOrder;
    final averageBefore = previous?.averageOrder;
    final comparable = previous != null;
    int? against(int now, int? before) =>
        before == null ? null : deltaBp(now, before);

    return [
      _Tiles(
        children: [
          _KpiTile(
            name: 'net',
            label: strings.homeKpiNetSales,
            value: _BigAmount(report.net),
            delta: against(report.net.minor, previous?.net.minor),
            comparable: comparable,
          ),
          _KpiTile(
            name: 'average',
            label: strings.homeKpiAverage,
            value: average == null
                ? const _BigDash()
                : _BigAmount(average),
            delta: average == null
                ? null
                : against(average.minor, averageBefore?.minor),
            comparable: comparable,
          ),
          _KpiTile(
            name: 'orders',
            label: strings.homeKpiOrders,
            value: _BigCount(report.orders),
            delta: against(report.orders, previous?.orders),
            comparable: comparable,
          ),
          _KpiTile(
            name: 'refunds',
            label: strings.reportKpiRefunds,
            value: _BigAmount(report.refunds),
            note: strings.reportRefundCount(report.refundCount),
            delta: against(report.refunds.minor, previous?.refunds.minor),
            comparable: comparable,
            upIsGood: false,
          ),
        ],
      ),
      const SizedBox(height: PosSpace.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _Section(
              key: const Key('reports-trend'),
              title: strings.reportTrend,
              trailing: [
                for (final metric in ReportTrendMetric.values)
                  _Chip(
                    key: Key('reports-metric-${metric.name}'),
                    label: reportTrendMetricLabel(strings, metric),
                    selected: metric == _metric,
                    onTap: () => setState(() => _metric = metric),
                  ),
              ],
              child: _Trend(report: report, metric: _metric),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            flex: 2,
            child: _Section(
              key: const Key('reports-payments'),
              title: strings.reportPayments,
              child: _Payments(report: report),
            ),
          ),
        ],
      ),
      const SizedBox(height: PosSpace.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Section(
              key: const Key('reports-top-products'),
              title: strings.reportTopProducts,
              trailing: [
                for (final ranking in ProductRanking.values)
                  _Chip(
                    key: Key('reports-rank-${ranking.name}'),
                    label: productRankingLabel(strings, ranking),
                    selected: ranking == _ranking,
                    onTap: () => setState(() => _ranking = ranking),
                  ),
              ],
              child: _TopProducts(filter: report.filter, ranking: _ranking),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: _Section(
              key: const Key('reports-insights'),
              title: strings.reportInsights,
              child: _Insights(
                insights: ReportInsights.of(report, previous: previous),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: PosSpace.md),
      _Section(
        key: const Key('reports-terminals'),
        title: strings.reportTerminals,
        child: _TerminalTable(report: report),
      ),
    ];
  }
}

/// The period chips, and the dates they came to.
///
/// The dates are said every time, in mono: "This week" means a different
/// Saturday in Arabic than Sunday in English, and the range is what settles
/// which one somebody is looking at.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.period,
    required this.filter,
    required this.onSelect,
  });

  final ReportPeriod period;
  final ReportFilter filter;
  final ValueChanged<ReportPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final last = DateTime(filter.to.year, filter.to.month, filter.to.day - 1);
    return Row(
      children: [
        for (final (i, option) in ReportPeriod.values.indexed) ...[
          if (i > 0) const SizedBox(width: PosSpace.sm),
          _Chip(
            key: Key('reports-period-${option.name}'),
            label: reportPeriodLabel(strings, option),
            selected: option == period,
            onTap: () => onSelect(option),
          ),
        ],
        const SizedBox(width: PosSpace.lg),
        Flexible(
          child: Text(
            filter.dates.length == 1
                ? businessDayWire(filter.from)
                : '${businessDayWire(filter.from)} → ${businessDayWire(last)}',
            key: const Key('reports-range'),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PosText.mono(size: 13, color: pos.body),
          ),
        ),
        // BO-11's Excel button takes the end of this row, beside the range it
        // exports — not added here, and not stubbed.
      ],
    );
  }
}

/// A choice among a few. The Sales list's chip, without the ripple and the
/// fill: selection is the accent border, and nothing on this design moves or
/// tints under a pointer.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: PosSize.filterChip - 8,
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
        decoration: BoxDecoration(
          border: Border.fromBorderSide(
            selected ? pos.accentBorder : pos.resting,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              style: PosText.ui(
                size: 12.5,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? pos.ink : pos.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Equal-width tiles of equal height, as Home lays out its own.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(width: PosSpace.md),
          Expanded(child: child),
        ],
      ],
    ),
  );
}

class _BigAmount extends StatelessWidget {
  const _BigAmount(this.value);

  final Money value;

  @override
  Widget build(BuildContext context) =>
      MonoAmount(value, size: 26, weight: FontWeight.w600);
}

class _BigCount extends StatelessWidget {
  const _BigCount(this.value);

  final int value;

  @override
  Widget build(BuildContext context) => Text(
    '$value',
    textDirection: TextDirection.ltr,
    style: PosText.mono(
      size: 26,
      weight: FontWeight.w600,
      color: context.pos.ink,
    ),
  );
}

class _BigDash extends StatelessWidget {
  const _BigDash();

  @override
  Widget build(BuildContext context) =>
      Text('—', style: PosText.mono(size: 26, color: context.pos.muted));
}

/// Home's tile, against the previous period rather than the previous day.
///
/// A copy rather than Home's widget: Home's says "vs the previous day, same
/// time since opening", which is Home's comparison and not this one, and a
/// tile taking its sentence as a parameter would be a tile whose words could
/// be handed the wrong comparison.
class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.name,
    required this.label,
    required this.value,
    required this.delta,
    required this.comparable,
    this.note,
    this.upIsGood = true,
  });

  final String name;
  final String label;
  final Widget value;
  final int? delta;

  /// Whether the previous period could be read at all. A null [delta] with
  /// one means its figure was zero, which has no percentage.
  final bool comparable;
  final String? note;

  /// Refunds going up is not good news, and green would say it was.
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final muted = PosText.ui(size: 12, color: pos.muted);
    return PosSurface(
      key: Key('reports-tile-$name'),
      padding: const EdgeInsets.all(PosSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(label),
          const SizedBox(height: PosSpace.sm),
          value,
          if (note case final note?) ...[
            const SizedBox(height: PosSpace.xs),
            Text(note, style: muted),
          ],
          const SizedBox(height: PosSpace.sm),
          switch (delta) {
            final bp? => Row(
              key: Key('reports-delta-$name'),
              children: [
                Icon(
                  bp > 0
                      ? Icons.arrow_upward
                      : (bp < 0 ? Icons.arrow_downward : Icons.remove),
                  size: 14,
                  color: _tone(pos, bp),
                ),
                const SizedBox(width: PosSpace.xs),
                Text(
                  formatDeltaBp(bp),
                  textDirection: TextDirection.ltr,
                  style: PosText.mono(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: _tone(pos, bp),
                  ),
                ),
                const SizedBox(width: PosSpace.sm),
                Flexible(
                  child: Text(
                    strings.reportVsPrevious,
                    maxLines: 2,
                    style: muted,
                  ),
                ),
              ],
            ),
            null => Text(
              comparable
                  ? '— ${strings.reportVsPrevious}'
                  : strings.reportNoComparison,
              style: muted,
            ),
          },
        ],
      ),
    );
  }

  /// Colour on the words and the arrow only, never the tile — as on Home.
  Color _tone(PosPalette pos, int bp) {
    if (bp == 0) return pos.muted;
    return (bp > 0) == upIsGood ? pos.ok : pos.danger;
  }
}

/// A bordered block with a heading, and the choices that change it.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.trailing = const [],
    super.key,
  });

  final String title;
  final Widget child;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => PosSurface(
    padding: const EdgeInsets.all(PosSpace.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(
                  size: 14,
                  weight: FontWeight.w700,
                  color: context.pos.ink,
                ),
              ),
            ),
            for (final (i, choice) in trailing.indexed) ...[
              if (i > 0) const SizedBox(width: PosSpace.xs),
              choice,
            ],
          ],
        ),
        const SizedBox(height: PosSpace.md),
        child,
      ],
    ),
  );
}

/// The line, the largest value it reaches, and the dates at its two ends —
/// the first at the start edge, as the line's first point is.
class _Trend extends StatelessWidget {
  const _Trend({required this.report, required this.metric});

  final SalesReport report;
  final ReportTrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final values = [for (final day in report.days) trendValue(day, metric)];
    final peak = values.whereType<int>().fold<int?>(
      null,
      (top, value) => top == null || value > top ? value : top,
    );
    final caption = PosText.mono(size: 11.5, color: pos.muted);
    String figure(int value) => switch (metric) {
      ReportTrendMetric.orders => '$value',
      ReportTrendMetric.net ||
      ReportTrendMetric.average => report.net.copyWith(minor: value).format(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          peak == null ? '—' : figure(peak),
          key: const Key('reports-trend-peak'),
          textDirection: TextDirection.ltr,
          style: caption,
        ),
        const SizedBox(height: PosSpace.xs),
        TrendChart(values: values),
        const SizedBox(height: PosSpace.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              businessDayWire(report.days.first.date),
              textDirection: TextDirection.ltr,
              style: caption,
            ),
            if (report.days.length > 1)
              Text(
                businessDayWire(report.days.last.date),
                textDirection: TextDirection.ltr,
                style: caption,
              ),
          ],
        ),
      ],
    );
  }
}

/// A share in basis points as a person reads it: `42.50%`. Two decimals, as
/// [formatDeltaBp] prints a change — a basis point is a hundredth of one.
String _share(int bp) =>
    '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%';

/// The stacked bar and its legend, and on account on its own line under
/// them: owed, not taken, so never a slice (§3a rule 3).
class _Payments extends StatelessWidget {
  const _Payments({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final shares = report.tenderShares;
    final owed = report.onAccount;
    if (shares.isEmpty && owed.isZero) return _Note(strings.reportNoPayments);
    final colors = chartSeries(pos);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shares.isNotEmpty) ...[
          ShareBar(
            basisPoints: [for (final share in shares) share.basisPoints],
            colors: colors,
          ),
          const SizedBox(height: PosSpace.md),
          for (final (i, share) in shares.indexed)
            SizedBox(
              key: Key('reports-tender-$i'),
              height: PosSize.reportRow - 8,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    color: colors[i % colors.length],
                  ),
                  const SizedBox(width: PosSpace.sm),
                  // As written on the payment rows — the restaurant's own
                  // name for the method, in whatever language it chose.
                  Expanded(
                    child: Text(
                      share.method.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PosText.ui(size: 13, color: pos.ink),
                    ),
                  ),
                  MonoAmount(share.method.amount),
                  SizedBox(
                    width: 72,
                    child: Text(
                      _share(share.basisPoints),
                      textAlign: TextAlign.end,
                      textDirection: TextDirection.ltr,
                      style: PosText.mono(size: 12.5, color: pos.muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (!owed.isZero)
          Container(
            key: const Key('reports-on-account'),
            margin: const EdgeInsets.only(top: PosSpace.sm),
            padding: const EdgeInsets.only(top: PosSpace.sm),
            decoration: BoxDecoration(border: Border(top: pos.hairline)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    strings.reportOnAccount,
                    style: PosText.ui(size: 13, color: pos.body),
                  ),
                ),
                MonoAmount(owed),
              ],
            ),
          ),
      ],
    );
  }
}

/// The top five, ranked one way, each with a bar against the first.
class _TopProducts extends ConsumerWidget {
  const _TopProducts({required this.filter, required this.ranking});

  final ReportFilter filter;
  final ProductRanking ranking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final strings = context.strings;
    int measure(ProductSales product) => switch (ranking) {
      ProductRanking.quantity => product.quantity,
      ProductRanking.amount => product.amount.minor,
    };
    return switch (ref.watch(
      topProductsProvider((filter: filter, by: ranking)),
    )) {
      AsyncData(value: final products) when products.isEmpty => _Note(
        strings.reportNoProducts,
      ),
      AsyncData(value: final products) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 56,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: MicroLabel(strings.reportColumnQuantity),
                ),
              ),
              SizedBox(
                width: 112,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: MicroLabel(strings.reportColumnAmount),
                ),
              ),
            ],
          ),
          const SizedBox(height: PosSpace.xs),
          for (final (i, product) in products.indexed)
            Padding(
              key: Key('reports-product-$i'),
              padding: const EdgeInsets.symmetric(vertical: PosSpace.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${i + 1}',
                      textDirection: TextDirection.ltr,
                      style: PosText.mono(size: 12.5, color: pos.muted),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PosText.ui(size: 13, color: pos.ink),
                        ),
                        const SizedBox(height: PosSpace.xs),
                        RankBar(
                          value: measure(product),
                          longest: products.map(measure).reduce(
                            (a, b) => a > b ? a : b,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${product.quantity}',
                      textAlign: TextAlign.end,
                      textDirection: TextDirection.ltr,
                      style: PosText.mono(size: 13, color: pos.ink),
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: MonoAmount(product.amount),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: PosSpace.sm),
          // Said beside the list, because a product's amount here will not
          // match what the tiles call sales: an order's discount belongs to no
          // one line, and ProductSales does not invent a share of it.
          Text(
            strings.reportTopProductsNote,
            style: PosText.ui(size: 12, color: pos.muted),
          ),
        ],
      ),
      AsyncError() => _Note(strings.reportUnavailable, danger: true),
      _ => const SizedBox(height: 120),
    };
  }
}

class _Insights extends StatelessWidget {
  const _Insights({required this.insights});

  final ReportInsights insights;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    if (insights.isEmpty) return _Note(strings.reportInsightsNone);
    final data = PosText.mono(
      size: 13,
      weight: FontWeight.w600,
      color: pos.ink,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insights.bestDay case final day?)
          _Insight(
            name: 'bestDay',
            label: strings.reportInsightBestDay,
            children: [
              Text(
                businessDayWire(day.date),
                textDirection: TextDirection.ltr,
                style: data,
              ),
              MonoAmount(day.net, weight: FontWeight.w600),
            ],
          ),
        if (insights.topTerminal case final till?)
          _Insight(
            name: 'topTerminal',
            label: strings.reportInsightTopTerminal,
            children: [
              Flexible(
                child: Text(
                  till.name ?? till.terminalId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: pos.ink,
                  ),
                ),
              ),
              MonoAmount(till.net, weight: FontWeight.w600),
            ],
          ),
        if (insights.netDeltaBp case final bp?)
          _Insight(
            name: 'growth',
            label: strings.reportInsightGrowth,
            children: [
              Text(
                formatDeltaBp(bp),
                textDirection: TextDirection.ltr,
                style: PosText.mono(
                  size: 13,
                  weight: FontWeight.w600,
                  color: bp > 0 ? pos.ok : (bp < 0 ? pos.danger : pos.muted),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Insight extends StatelessWidget {
  const _Insight({
    required this.name,
    required this.label,
    required this.children,
  });

  final String name;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    key: Key('reports-insight-$name'),
    padding: const EdgeInsets.only(bottom: PosSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(label),
        const SizedBox(height: PosSpace.xs),
        Row(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(width: PosSpace.md),
              child,
            ],
          ],
        ),
      ],
    ),
  );
}

/// Every till of the branch, zeros included (§3a rule 2), and the branch
/// under them — the report's own rollup of the same rows, so the bottom line
/// is the column's sum by construction rather than by a second addition.
class _TerminalTable extends StatelessWidget {
  const _TerminalTable({required this.report});

  final SalesReport report;

  static const _count = 72.0;
  static const _money = 124.0;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    Widget heading(String text, double width) => SizedBox(
      width: width,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: MicroLabel(text),
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              Expanded(child: MicroLabel(strings.orderColumnTerminal)),
              heading(strings.homeKpiOrders, _count),
              heading(strings.dayGross, _money),
              heading(strings.orderDetailDiscounts, _money),
              heading(strings.reportKpiRefunds, _money),
              heading(strings.homeKpiNetSales, _money),
            ],
          ),
        ),
        for (final till in report.terminals)
          _TerminalRow(
            key: Key('reports-terminal-${till.terminalId}'),
            name: till.name == null
                ? Row(
                    children: [
                      Flexible(
                        child: Text(
                          till.terminalId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: PosText.mono(size: 12.5, color: pos.body),
                        ),
                      ),
                      const SizedBox(width: PosSpace.sm),
                      Text(
                        strings.reportUnregistered,
                        style: PosText.ui(size: 12, color: pos.warn),
                      ),
                    ],
                  )
                : Text(
                    till.name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PosText.ui(size: 13, color: pos.ink),
                  ),
            orders: till.orders,
            gross: till.gross,
            discounts: till.discounts,
            refunds: till.refunds,
            net: till.net,
          ),
        _TerminalRow(
          key: const Key('reports-terminal-total'),
          total: true,
          name: Text(
            strings.reportBranchTotal,
            style: PosText.ui(
              size: 13,
              weight: FontWeight.w700,
              color: pos.ink,
            ),
          ),
          orders: report.orders,
          gross: report.gross,
          discounts: report.discounts,
          refunds: report.refunds,
          net: report.net,
        ),
      ],
    );
  }
}

class _TerminalRow extends StatelessWidget {
  const _TerminalRow({
    required this.name,
    required this.orders,
    required this.gross,
    required this.discounts,
    required this.refunds,
    required this.net,
    this.total = false,
    super.key,
  });

  final Widget name;
  final int orders;
  final Money gross;
  final Money discounts;
  final Money refunds;
  final Money net;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final weight = total ? FontWeight.w700 : FontWeight.w400;
    Widget amount(Money value) => SizedBox(
      width: _TerminalTable._money,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: MonoAmount(value, weight: weight),
      ),
    );
    return Container(
      height: PosSize.reportRow,
      decoration: BoxDecoration(
        border: Border(top: total ? pos.resting : pos.hairline),
      ),
      child: Row(
        children: [
          Expanded(child: name),
          SizedBox(
            width: _TerminalTable._count,
            child: Text(
              '$orders',
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              style: PosText.mono(size: 13, weight: weight, color: pos.ink),
            ),
          ),
          amount(gross),
          amount(discounts),
          amount(refunds),
          amount(net),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Text(
    text,
    key: const Key('reports-note'),
    style: PosText.ui(
      size: 13,
      color: danger ? context.pos.danger : context.pos.body,
      height: 1.4,
    ),
  );
}
