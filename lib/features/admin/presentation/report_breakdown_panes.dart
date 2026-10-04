/// Reports' five breakdowns — the owner's map of 14 Sep 2026: التقارير ›
/// المبيعات، الأصناف، طرق الدفع، الفروع والأجهزة، الموظفين.
///
/// **Each is Business summary read one way, over the same period.** The
/// period is `reportPeriodProvider`'s, which the summary and all five set and
/// read, so moving between them keeps it; each page works out what it comes
/// to from the day that is open, exactly as the summary does
/// ([reportFilterIn]). Deep-linking into sections of the summary was the
/// alternative, and was rejected because the period lived inside that page:
/// every link would have opened it on Today.
///
/// **Every figure is BO-5's.** Sales, Payment methods and Branches & devices
/// are the same `SalesReport` the summary's tiles are read off — its days, its
/// `tenderShares`, its terminals — so their totals rows ARE the summary's
/// tiles, not sums that happen to agree. Items is `topProducts` without its
/// limit and Employees is `staffSales`, each a query of BO-5's repository with
/// the drill-down's own WHERE. Nothing here adds up money but the Items
/// total, which is the rows' sum and is labelled as the thing it is.
///
/// **One pane per item**, so the bar reaches each by its own `ManagementPane`,
/// and the header names the page on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/excel_export.dart';
import '../../../app/providers.dart';
import '../../../app/reports_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/branch_sales.dart';
import '../../../domain/models/profit_report.dart';
import '../../../domain/models/sales_report.dart';
import '../application/report_export.dart';
import '../application/reports_view.dart';
import 'management_finance_panes.dart' show formatShareBp;
import 'management_reports_pane.dart';
import 'report_charts.dart';

/// The period bar over one breakdown's figures.
///
/// Waits for the business day before asking anything, as the summary does:
/// asking with the calendar and again with the day is two reads, and figures
/// that visibly change their mind.
class _BreakdownFrame extends ConsumerStatefulWidget {
  const _BreakdownFrame({
    required this.name,
    required this.body,
    this.openedAt,
  });

  /// The pane's key, `reports-<name>-pane`.
  final String name;
  final Widget Function(ReportFilter filter) body;
  final DateTime? openedAt;

  @override
  ConsumerState<_BreakdownFrame> createState() => _BreakdownFrameState();
}

class _BreakdownFrameState extends ConsumerState<_BreakdownFrame> {
  /// Read once, for the summary's reason: a clock read in `build` is a new
  /// filter, and a new database read, on every rebuild.
  late final DateTime _openedAt = widget.openedAt ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(businessDayProvider);
    if (day.isLoading) {
      return Center(child: CircularProgressIndicator(color: context.pos.accent));
    }
    final today = reportToday(day.valueOrNull, _openedAt);
    final filter = reportFilterIn(
      context,
      ref.watch(reportPeriodProvider),
      today,
    );
    return ListView(
      key: Key('reports-${widget.name}-pane'),
      padding: const EdgeInsets.all(PosSpace.s24),
      children: [
        ReportPeriodBar(filter: filter, today: today),
        widget.body(filter),
      ],
    );
  }
}

/// A breakdown's figures, or the sentence that stands in for them — and, over
/// figures, the export for whoever holds `report.export`.
///
/// The summary's states, in the summary's words: no database is said rather
/// than drawn as zeros, which would read as a period with no sales.
class _Figures<T extends Object> extends ConsumerWidget {
  const _Figures({required this.value, required this.figures, this.export});

  final AsyncValue<T?> value;
  final List<Widget> Function(T figures) figures;

  /// The button for these figures. Only ever built with figures in hand: a
  /// file of a read not yet finished would be zeros that look like a week.
  final Widget Function(T figures)? export;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final export = this.export;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value case AsyncData(value: final shown?)
            when export != null && ref.watch(reportExportAllowedProvider)) ...[
          const SizedBox(height: PosSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: export(shown),
          ),
        ],
        const SizedBox(height: PosSpace.s24),
        ...switch (value) {
          AsyncData(value: final shown?) => figures(shown),
          AsyncData(value: null) => [ReportNote(strings.reportNoDatabase)],
          AsyncError() => [ReportNote(strings.reportUnavailable, danger: true)],
          _ => [
            SizedBox(
              height: 240,
              child: Center(
                child: CircularProgressIndicator(color: context.pos.accent),
              ),
            ),
          ],
        },
      ],
    );
  }
}

// ── The table every breakdown draws ────────────────────────────────────────

const _count = 72.0;
const _money = 124.0;

/// A column of a breakdown table: its width, and the figure in it.
typedef _Cell = ({double width, Widget child});

_Cell _countCell(BuildContext context, int value, {bool total = false}) => (
  width: _count,
  child: Text(
    '$value',
    textAlign: TextAlign.end,
    textDirection: TextDirection.ltr,
    style: PosText.mono(
      size: 13,
      weight: total ? FontWeight.w700 : FontWeight.w400,
      color: context.pos.ink,
    ),
  ),
);

/// An amount, or a dash where there is none — an average with no orders.
_Cell _moneyCell(BuildContext context, Money? value, {bool total = false}) => (
  width: _money,
  child: Align(
    alignment: AlignmentDirectional.centerEnd,
    child: value == null
        ? Text('—', style: PosText.mono(size: 13, color: context.pos.muted))
        : MonoAmount(
            value,
            weight: total ? FontWeight.w700 : FontWeight.w400,
          ),
  ),
);

_Cell _textCell(BuildContext context, String value, double width) => (
  width: width,
  child: Text(
    value,
    textAlign: TextAlign.end,
    textDirection: TextDirection.ltr,
    style: PosText.mono(size: 12.5, color: context.pos.muted),
  ),
);

/// The headings, each over its column's end edge, as the summary's till
/// table heads its own.
class _Headings extends StatelessWidget {
  const _Headings({required this.lead, required this.columns});

  final String lead;
  final List<(String, double)> columns;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: Row(
      children: [
        Expanded(child: MicroLabel(lead)),
        for (final (label, width) in columns)
          SizedBox(
            width: width,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: MicroLabel(label),
            ),
          ),
      ],
    ),
  );
}

/// One row: what it is at the start edge, its figures after. A total is set
/// off by the stronger rule above it and bold figures — never a tint.
class _Line extends StatelessWidget {
  const _Line({
    required this.lead,
    required this.cells,
    this.total = false,
    super.key,
  });

  final Widget lead;
  final List<_Cell> cells;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Container(
      constraints: const BoxConstraints(minHeight: PosSize.reportRow),
      decoration: BoxDecoration(
        border: Border(top: total ? pos.resting : pos.hairline),
      ),
      child: Row(
        children: [
          Expanded(child: lead),
          for (final cell in cells)
            SizedBox(width: cell.width, child: cell.child),
        ],
      ),
    );
  }
}

Widget _name(BuildContext context, String text, {bool total = false}) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: PosText.ui(
    size: 13,
    weight: total ? FontWeight.w700 : FontWeight.w400,
    color: context.pos.ink,
  ),
);

Widget _caption(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: PosSpace.md),
  child: Text(
    text,
    style: PosText.ui(size: 12, color: context.pos.muted, height: 1.4),
  ),
);

// ── المبيعات ────────────────────────────────────────────────────────────────

/// Reports › Sales: the summary's per-day series as a table, and its trend.
///
/// The totals row is the report's rollup — the summary's tiles themselves —
/// not the column added up here. `reports_test.dart` holds the days to the
/// same figures, column by column, so the rows and the bottom line agree by a
/// test rather than by this page's arithmetic.
///
/// **Net before refunds**, in the owner's order for the page (day, orders,
/// gross, discounts, net, refunds, average), though net is gross less both:
/// the page is read for net, and refunds sit beside the average as what
/// explains a low one.
class ReportSalesPane extends ConsumerStatefulWidget {
  const ReportSalesPane({super.key, this.openedAt});

  @visibleForTesting
  final DateTime? openedAt;

  @override
  ConsumerState<ReportSalesPane> createState() => _ReportSalesPaneState();
}

class _ReportSalesPaneState extends ConsumerState<ReportSalesPane> {
  ReportTrendMetric _metric = ReportTrendMetric.net;

  @override
  Widget build(BuildContext context) => _BreakdownFrame(
    name: 'sales',
    openedAt: widget.openedAt,
    body: (filter) => _Figures<SalesReport>(
      value: ref.watch(salesReportProvider(filter)),
      export: (report) => ExcelExportButton(
        fileName: reportFileName(filter, section: 'sales'),
        build: (strings, rightToLeft) async => salesDaysWorkbook(
          report: report,
          strings: strings,
          rightToLeft: rightToLeft,
        ),
      ),
      figures: (report) => [
        ReportSection(
          key: const Key('reports-sales-trend'),
          title: context.strings.reportTrend,
          trailing: [
            for (final metric in ReportTrendMetric.values)
              ReportChip(
                key: Key('reports-metric-${metric.name}'),
                label: reportTrendMetricLabel(context.strings, metric),
                selected: metric == _metric,
                onTap: () => setState(() => _metric = metric),
              ),
          ],
          child: TrendChart(
            values: [for (final day in report.days) trendValue(day, _metric)],
            height: 140,
          ),
        ),
        const SizedBox(height: PosSpace.md),
        ReportSection(
          key: const Key('reports-sales-days'),
          title: context.strings.reportsSales,
          child: _DaysTable(report: report),
        ),
      ],
    ),
  );
}

class _DaysTable extends StatelessWidget {
  const _DaysTable({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    List<_Cell> figures({
      required int orders,
      required Money gross,
      required Money discounts,
      required Money net,
      required Money refunds,
      required Money? average,
      bool total = false,
    }) => [
      _countCell(context, orders, total: total),
      _moneyCell(context, gross, total: total),
      _moneyCell(context, discounts, total: total),
      _moneyCell(context, net, total: total),
      _moneyCell(context, refunds, total: total),
      _moneyCell(context, average, total: total),
    ];
    return Column(
      children: [
        _Headings(
          lead: s.exportColumnDate,
          columns: [
            (s.homeKpiOrders, _count),
            (s.dayGross, _money),
            (s.orderDetailDiscounts, _money),
            (s.homeKpiNetSales, _money),
            (s.reportKpiRefunds, _money),
            (s.homeKpiAverage, _money),
          ],
        ),
        for (final day in report.days)
          _Line(
            key: Key('reports-day-${businessDayWire(day.date)}'),
            lead: Text(
              businessDayWire(day.date),
              textDirection: TextDirection.ltr,
              style: PosText.mono(size: 13, color: context.pos.ink),
            ),
            cells: figures(
              orders: day.orders,
              gross: day.gross,
              discounts: day.discounts,
              net: day.net,
              refunds: day.refunds,
              average: day.averageOrder,
            ),
          ),
        _Line(
          key: const Key('reports-days-total'),
          total: true,
          lead: _name(context, s.reportBranchTotal, total: true),
          cells: figures(
            orders: report.orders,
            gross: report.gross,
            discounts: report.discounts,
            net: report.net,
            refunds: report.refunds,
            average: report.averageOrder,
            total: true,
          ),
        ),
      ],
    );
  }
}

// ── الأصناف ─────────────────────────────────────────────────────────────────

/// Reports › Items: every product sold in the period, ranked by quantity or
/// by amount — BO-5's top list with no limit, so its first five are the
/// summary's five.
///
/// **Its total is not net sales, and says so.** A product's amount is before
/// the order's discount and service, and a refunded unit comes off the day it
/// was sold, not the day it came back ([ProductSales]). The alternative —
/// sharing each order's discount out across its lines so the column met the
/// net tile — is a rule this report would be inventing, and the ETA filing
/// would disagree with it line by line.
class ReportItemsPane extends ConsumerStatefulWidget {
  const ReportItemsPane({super.key, this.openedAt});

  @visibleForTesting
  final DateTime? openedAt;

  @override
  ConsumerState<ReportItemsPane> createState() => _ReportItemsPaneState();
}

class _ReportItemsPaneState extends ConsumerState<ReportItemsPane> {
  ProductRanking _ranking = ProductRanking.quantity;

  @override
  Widget build(BuildContext context) => _BreakdownFrame(
    name: 'items',
    openedAt: widget.openedAt,
    body: (filter) => _Figures<List<ProductSales>>(
      // The list is never null, so no database is asked of the repository:
      // "nothing was sold" on a till with no database would be a lie.
      value: ref.watch(reportsRepositoryProvider) == null
          ? const AsyncData(null)
          : ref.watch(allProductsProvider((filter: filter, by: _ranking))),
      export: (products) => ExcelExportButton(
        fileName: reportFileName(filter, section: 'items'),
        build: (strings, rightToLeft) async => itemsWorkbook(
          filter: filter,
          products: products,
          strings: strings,
          rightToLeft: rightToLeft,
          // The page's own read, so the file is the figures on screen. A
          // ledger that failed to read is a sheet left out — the section above
          // already said it was unavailable — rather than an export that
          // fails with the items it could have written.
          profit: await ref
              .read(profitReportProvider(filter).future)
              .then<ProfitReport?>((report) => report)
              .catchError((Object _) => null),
        ),
      ),
      figures: (products) => [
        ReportSection(
          key: const Key('reports-items'),
          title: context.strings.reportsItems,
          trailing: [
            for (final ranking in ProductRanking.values)
              ReportChip(
                key: Key('reports-rank-${ranking.name}'),
                label: productRankingLabel(context.strings, ranking),
                selected: ranking == _ranking,
                onTap: () => setState(() => _ranking = ranking),
              ),
          ],
          child: products.isEmpty
              ? ReportNote(context.strings.reportNoProducts)
              : _ItemsTable(products: products, ranking: _ranking),
        ),
        // Only once something sold: profit on nothing is not a section.
        if (products.isNotEmpty) ...[
          const SizedBox(height: PosSpace.lg),
          _ProfitSection(filter: filter),
        ],
      ],
    ),
  );
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.products, required this.ranking});

  final List<ProductSales> products;
  final ProductRanking ranking;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    int measure(ProductSales product) => switch (ranking) {
      ProductRanking.quantity => product.quantity,
      ProductRanking.amount => product.amount.minor,
    };
    final longest = products.map(measure).reduce((a, b) => a > b ? a : b);
    final totals = productTotals(products);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headings(
          lead: s.exportColumnProduct,
          columns: [(s.reportColumnQuantity, _count), (s.reportColumnAmount, _money)],
        ),
        for (final (i, product) in products.indexed)
          _Line(
            key: Key('reports-item-$i'),
            lead: Padding(
              padding: const EdgeInsetsDirectional.only(
                top: PosSpace.xs,
                bottom: PosSpace.xs,
                end: PosSpace.lg,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
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
                        _name(context, product.name),
                        const SizedBox(height: PosSpace.xs),
                        RankBar(value: measure(product), longest: longest),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            cells: [
              _countCell(context, product.quantity),
              _moneyCell(context, product.amount),
            ],
          ),
        _Line(
          key: const Key('reports-items-total'),
          total: true,
          lead: _name(context, s.reportAllItems, total: true),
          cells: [
            _countCell(context, totals.quantity, total: true),
            _moneyCell(context, totals.amount, total: true),
          ],
        ),
        _caption(context, s.reportItemsNote),
      ],
    );
  }
}

// ── الربح ───────────────────────────────────────────────────────────────────

/// A margin, signed, to two decimals — `formatShareBp` for shares, which are
/// never negative. A loss has to read as one: through the share formatter,
/// −6.25% would print as −6.75%, because Dart's `%` is never negative.
String formatMarginBp(int bp) =>
    '${bp < 0 ? '-' : ''}${formatShareBp(bp.abs())}';

/// Reports › Items, under the list: what the same sales earned, where the
/// till knows what they cost (`ProfitReport`).
///
/// **It says what it does not know before it says what it does.** The margin
/// is on the costed revenue only, so the coverage sits beside it and the
/// revenue it cannot speak to has a line of its own: a margin shown alone would
/// read as the business's, and it is not. A product with no cost is a row with
/// a tag and dashes, never a zero cost — "free" and "unknown" are different
/// claims.
///
/// Its own read, so the list above never waits on it or fails with it.
class _ProfitSection extends ConsumerWidget {
  const _ProfitSection({required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    return ReportSection(
      key: const Key('reports-profit'),
      title: s.profitTitle,
      child: switch (ref.watch(profitReportProvider(filter))) {
        AsyncData(value: final report?) => _ProfitBody(report: report),
        AsyncData(value: null) => ReportNote(s.reportNoDatabase),
        AsyncError() => ReportNote(s.reportUnavailable, danger: true),
        _ => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}

class _ProfitBody extends StatelessWidget {
  const _ProfitBody({required this.report});

  final ProfitReport report;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final margin = report.marginBp;
    final coverage = report.coverageBp;

    if (!report.hasAnyCost) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReportNote(s.profitNothingCosted, key: const Key('profit-nothing-costed')),
          if (report.revenueIncludesTax) _taxNote(context),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: PosSpace.s28,
          runSpacing: PosSpace.md,
          children: [
            _Figure(
              key: const Key('profit-tile-profit'),
              label: s.profitKpiProfit,
              child: MonoAmount(
                report.profit,
                size: 22,
                weight: FontWeight.w600,
                color: report.profit.minor < 0 ? context.pos.danger : null,
              ),
            ),
            _Figure(
              key: const Key('profit-tile-margin'),
              label: s.profitColumnMargin,
              child: _bp(context, margin, size: 22),
            ),
            _Figure(
              key: const Key('profit-tile-coverage'),
              label: s.profitKpiCoverage,
              note: coverage == null ? null : s.profitCoverageNote,
              child: _bp(context, coverage, size: 22, share: true),
            ),
            if (report.uncostedRevenue.minor > 0)
              _Figure(
                key: const Key('profit-tile-uncosted'),
                label: s.profitUncostedRevenue,
                child: MonoAmount(
                  report.uncostedRevenue,
                  size: 22,
                  weight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: PosSpace.lg),
        _Headings(
          lead: s.exportColumnProduct,
          columns: [
            (s.reportColumnAmount, _money),
            (s.profitColumnCost, _money),
            (s.profitColumnProfit, _money),
            (s.profitColumnMargin, _count + 12),
          ],
        ),
        for (final (i, product) in report.products.indexed)
          _Line(
            key: Key('reports-profit-$i'),
            lead: Padding(
              padding: const EdgeInsetsDirectional.only(
                top: PosSpace.xs,
                bottom: PosSpace.xs,
                end: PosSpace.lg,
              ),
              child: Row(
                children: [
                  Flexible(child: _name(context, product.name)),
                  if (!product.isCosted)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: PosSpace.sm,
                      ),
                      child: Text(
                        s.profitNoCostTag,
                        key: Key('reports-profit-$i-uncosted'),
                        style: PosText.ui(
                          size: 11.5,
                          color: context.pos.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            cells: [
              _moneyCell(context, product.revenue),
              _moneyCell(context, product.cost),
              _profitCell(context, product.profit),
              _marginCell(context, product.marginBp),
            ],
          ),
        _Line(
          key: const Key('reports-profit-total'),
          total: true,
          lead: _name(context, s.reportAllItems, total: true),
          cells: [
            _moneyCell(context, report.revenue, total: true),
            _moneyCell(context, report.cost, total: true),
            _profitCell(context, report.profit, total: true),
            _marginCell(context, margin, total: true),
          ],
        ),
        if (report.revenueIncludesTax) _taxNote(context),
        _caption(context, s.profitNote),
      ],
    );
  }

  Widget _taxNote(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: PosSpace.md),
    child: Text(
      context.strings.profitTaxNote,
      key: const Key('profit-tax-note'),
      style: PosText.ui(
        size: 12.5,
        weight: FontWeight.w600,
        color: context.pos.warn,
        height: 1.4,
      ),
    ),
  );
}

/// A basis-point figure in the table's mono: a dash for none, danger for a
/// loss.
Widget _bp(
  BuildContext context,
  int? bp, {
  double size = 13,
  bool share = false,
  bool bold = false,
}) {
  final pos = context.pos;
  if (bp == null) {
    return Text('—', style: PosText.mono(size: size, color: pos.muted));
  }
  return Text(
    share ? formatShareBp(bp) : formatMarginBp(bp),
    textDirection: TextDirection.ltr,
    style: PosText.mono(
      size: size,
      weight: size > 14
          ? FontWeight.w600
          : (bold ? FontWeight.w700 : FontWeight.w400),
      color: bp < 0 ? pos.danger : pos.ink,
    ),
  );
}

/// Profit, or a dash where there is no cost; a loss in the danger colour.
_Cell _profitCell(BuildContext context, Money? value, {bool total = false}) => (
  width: _money,
  child: Align(
    alignment: AlignmentDirectional.centerEnd,
    child: value == null
        ? Text('—', style: PosText.mono(size: 13, color: context.pos.muted))
        : MonoAmount(
            value,
            weight: total ? FontWeight.w700 : FontWeight.w400,
            color: value.minor < 0 ? context.pos.danger : null,
          ),
  ),
);

_Cell _marginCell(BuildContext context, int? bp, {bool total = false}) => (
  width: _count + 12,
  child: Align(
    alignment: AlignmentDirectional.centerEnd,
    child: _bp(context, bp, bold: total),
  ),
);

/// A labelled figure above the table.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.child, this.note, super.key});

  final String label;
  final Widget child;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(label),
      const SizedBox(height: PosSpace.xs),
      child,
      if (note != null)
        Text(note!, style: PosText.ui(size: 11.5, color: context.pos.muted)),
    ],
  );
}

// ── طرق الدفع ───────────────────────────────────────────────────────────────

/// Reports › Payment methods: the summary's bar with a row per method — how
/// many payments, how much, what share.
///
/// **The total is what was collected, and on account is under it on its own**
/// (§3a rule 3), as the summary shows it: owed is not taken, so it has no
/// share and is not in the collected figure. The shares are BO-5's
/// `basisPointShares`, so the column is exactly 100.00% and not a rounding
/// short of it.
class ReportPaymentsPane extends ConsumerWidget {
  const ReportPaymentsPane({super.key, this.openedAt});

  @visibleForTesting
  final DateTime? openedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _BreakdownFrame(
    name: 'payments',
    openedAt: openedAt,
    body: (filter) => _Figures<SalesReport>(
      value: ref.watch(salesReportProvider(filter)),
      export: (report) => ExcelExportButton(
        fileName: reportFileName(filter, section: 'payments'),
        build: (strings, rightToLeft) async => paymentsWorkbook(
          report: report,
          strings: strings,
          rightToLeft: rightToLeft,
        ),
      ),
      figures: (report) => [
        ReportSection(
          key: const Key('reports-methods'),
          title: context.strings.reportsPaymentMethods,
          child: report.tenderShares.isEmpty && report.onAccount.isZero
              ? ReportNote(context.strings.reportNoPayments)
              : _MethodsTable(report: report),
        ),
      ],
    ),
  );
}

class _MethodsTable extends StatelessWidget {
  const _MethodsTable({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    final shares = report.tenderShares;
    final colors = chartSeries(pos);
    const share = 88.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shares.isNotEmpty) ...[
          ShareBar(
            basisPoints: [for (final share in shares) share.basisPoints],
            colors: colors,
          ),
          const SizedBox(height: PosSpace.md),
        ],
        _Headings(
          lead: s.orderColumnMethod,
          columns: [
            (s.reportColumnPayments, _count),
            (s.reportColumnAmount, _money),
            (s.exportColumnShare, share),
          ],
        ),
        for (final (i, tender) in shares.indexed)
          _Line(
            key: Key('reports-method-$i'),
            lead: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  color: colors[i % colors.length],
                ),
                const SizedBox(width: PosSpace.sm),
                // The restaurant's own name for the method, as written on the
                // payment rows.
                Expanded(child: _name(context, tender.method.label)),
              ],
            ),
            cells: [
              _countCell(context, tender.method.count),
              _moneyCell(context, tender.method.amount),
              _textCell(context, formatShareBp(tender.basisPoints), share),
            ],
          ),
        _Line(
          key: const Key('reports-methods-total'),
          total: true,
          lead: _name(context, s.financeKpiCollected, total: true),
          cells: [
            _countCell(context, report.collectedPayments, total: true),
            _moneyCell(context, report.collected, total: true),
            _textCell(
              context,
              formatShareBp(
                shares.fold(0, (sum, tender) => sum + tender.basisPoints),
              ),
              share,
            ),
          ],
        ),
        if (!report.onAccount.isZero)
          _Line(
            key: const Key('reports-methods-on-account'),
            lead: Text(
              s.reportOnAccount,
              style: PosText.ui(size: 13, color: pos.body),
            ),
            cells: [
              _countCell(context, report.onAccountPayments),
              _moneyCell(context, report.onAccount),
              (width: share, child: const SizedBox.shrink()),
            ],
          ),
      ],
    );
  }
}

// ── الفروع والأجهزة ─────────────────────────────────────────────────────────

/// Reports › Branches & devices: the branch's tills, each with its figures,
/// and the branch under them.
///
/// **One branch, said rather than drawn as a list of one.** A till reads its
/// own branch and no other (plan 17 §2), so there is no second branch to
/// list; a branch table with one row would promise a comparison this till
/// cannot make. The tills are the summary's own table — every one registered,
/// the idle ones at zero (§3a rule 2) — and its bottom line is the report's
/// rollup of those rows, equal to them to the piastre by construction.
class ReportBranchesPane extends ConsumerWidget {
  const ReportBranchesPane({super.key, this.openedAt});

  @visibleForTesting
  final DateTime? openedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(terminalProfileProvider).branchName;
    final named = branch == null || branch.isEmpty ? null : branch;
    return _BreakdownFrame(
      name: 'branches',
      openedAt: openedAt,
      body: (filter) => _Figures<SalesReport>(
        value: ref.watch(salesReportProvider(filter)),
        export: (report) => ExcelExportButton(
          fileName: reportFileName(filter, section: 'tills'),
          build: (strings, rightToLeft) async => terminalsWorkbook(
            report: report,
            strings: strings,
            rightToLeft: rightToLeft,
          ),
        ),
        figures: (report) => [
          ReportSection(
            key: const Key('reports-branch'),
            title: named ?? context.strings.reportTerminals,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReportTerminalTable(report: report),
                _caption(context, context.strings.reportBranchesNote(named)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── الموظفين ────────────────────────────────────────────────────────────────

/// Reports › Employees: per person, what they sold, refunded and voided.
///
/// Each figure is the act of the person who did it ([StaffSales]), and the
/// page says so under the table: a refund on a cashier's row that they did
/// not ring up the sale for is the first thing somebody asks about. The
/// branch total is the rows' rollup, which `reports_test.dart` holds equal to
/// the summary's net tile.
class ReportEmployeesPane extends ConsumerWidget {
  const ReportEmployeesPane({super.key, this.openedAt});

  @visibleForTesting
  final DateTime? openedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _BreakdownFrame(
    name: 'employees',
    openedAt: openedAt,
    body: (filter) => _Figures<StaffSalesReport>(
      value: ref.watch(staffSalesProvider(filter)),
      export: (report) => ExcelExportButton(
        fileName: reportFileName(filter, section: 'staff'),
        build: (strings, rightToLeft) async => staffWorkbook(
          report: report,
          strings: strings,
          rightToLeft: rightToLeft,
        ),
      ),
      figures: (report) => [
        ReportSection(
          key: const Key('reports-staff'),
          title: context.strings.reportsEmployees,
          child: report.people.isEmpty
              ? ReportNote(context.strings.reportNoStaffSales)
              : _StaffTable(report: report),
        ),
      ],
    ),
  );
}

class _StaffTable extends StatelessWidget {
  const _StaffTable({required this.report});

  final StaffSalesReport report;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    List<_Cell> figures({
      required int orders,
      required Money net,
      required Money? average,
      required Money refunds,
      required int voids,
      bool total = false,
    }) => [
      _countCell(context, orders, total: total),
      _moneyCell(context, net, total: total),
      _moneyCell(context, average, total: total),
      _moneyCell(context, refunds, total: total),
      _countCell(context, voids, total: total),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Headings(
          lead: s.reportColumnSeller,
          columns: [
            (s.homeKpiOrders, _count),
            (s.homeKpiNetSales, _money),
            (s.homeKpiAverage, _money),
            (s.reportKpiRefunds, _money),
            (s.reportColumnVoids, _count),
          ],
        ),
        for (final person in report.people)
          _Line(
            key: Key('reports-staff-${person.staffId ?? 'none'}'),
            lead: person.name == null
                ? Text(
                    s.reportSellerNotRecorded,
                    style: PosText.ui(size: 13, color: context.pos.warn),
                  )
                : _name(context, person.name!),
            cells: figures(
              orders: person.orders,
              net: person.net,
              average: person.averageOrder,
              refunds: person.refunds,
              voids: person.voids,
            ),
          ),
        _Line(
          key: const Key('reports-staff-total'),
          total: true,
          lead: _name(context, s.reportBranchTotal, total: true),
          cells: figures(
            orders: report.orders,
            net: report.net,
            average: report.averageOrder,
            refunds: report.refunds,
            voids: report.voids,
            total: true,
          ),
        ),
        _caption(context, s.reportStaffNote),
      ],
    );
  }
}
