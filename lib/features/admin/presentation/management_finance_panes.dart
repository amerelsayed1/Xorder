import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/finance_providers.dart';
import '../../../app/providers.dart' show businessDayProvider;
import '../../../app/reports_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/branch_sales.dart';
import '../../../domain/models/finance_report.dart';
import '../../../domain/models/sales_report.dart';
import 'admin_messages.dart';

/// Finance (BO-9, plan 19 §2.4): money that moved, read-only, over ledgers
/// that already exist.
///
/// **Four panes, not one pane with tabs of its own.** The shell's sub-nav
/// already draws a second row for a tab with more than one pane, and the
/// table-driven shell test already holds every pane to `managementPanesFor`;
/// tabs inside one pane (Purchasing's shape) would be a second navigation the
/// shell knows nothing about, and a gate the shell test could not see.
///
/// **What is not here, and why.** Expenses, bills due, drawers and the
/// transactions table are BO-10. Net profit (no cost price), bank and
/// e-wallet balances and settlements (no accounting model) have no source and
/// are cut, not stubbed: a tile reading zero would say the restaurant made
/// nothing, which is a claim, not an absence.

String financePeriodLabel(AppStrings s, FinancePeriod period) =>
    switch (period) {
      FinancePeriod.today => s.financePeriodToday,
      FinancePeriod.thisWeek => s.financePeriodThisWeek,
      FinancePeriod.thisMonth => s.financePeriodThisMonth,
      FinancePeriod.lastMonth => s.financePeriodLastMonth,
    };

/// A share in basis points as a person reads it: `51.92%`.
///
/// Two decimals because that is what a basis point is, and the shares were
/// already rounded once — to sum to 10,000 — by `basisPointShares`. Printing
/// them to one decimal would be a second rounding, and a legend that adds up
/// to 100.1%.
String formatShareBp(int bp) =>
    '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%';

/// Overview: the period's revenue, what was collected and owed, the tax, and
/// the tender bar.
class FinanceOverviewPane extends StatelessWidget {
  const FinanceOverviewPane({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return _FinanceFrame(
      paneKey: 'finance-overview',
      blurb: s.financeOverviewBlurb,
      builder: (ref, filter) => _read(
        context,
        ref.watch(salesReportProvider(filter)),
        (sales) => [
          _TileRow(
            children: [
              _Tile(
                tileKey: 'finance-tile-revenue',
                label: s.financeKpiRevenue,
                value: _big(context, sales.net),
              ),
              _Tile(
                tileKey: 'finance-tile-collected',
                label: s.financeKpiCollected,
                value: _big(context, sales.collected),
              ),
              _Tile(
                tileKey: 'finance-tile-on-account',
                label: s.financeKpiOnAccount,
                value: _big(context, sales.onAccount),
              ),
              _Tile(
                tileKey: 'finance-tile-tax',
                label: s.financeKpiTax,
                value: _big(
                  context,
                  ref.watch(taxReportProvider(filter)).valueOrNull?.net,
                ),
              ),
            ],
          ),
          const SizedBox(height: PosSpace.s28),
          _TenderCard(report: sales),
        ],
      ),
    );
  }
}

/// Revenue: Reports' sales totals, and the business days they are made of.
class FinanceRevenuePane extends StatelessWidget {
  const FinanceRevenuePane({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return _FinanceFrame(
      paneKey: 'finance-revenue',
      blurb: s.financeRevenueBlurb,
      builder: (ref, filter) => _read(
        context,
        ref.watch(salesReportProvider(filter)),
        (sales) => [
          _TileRow(
            children: [
              _Tile(
                tileKey: 'finance-tile-net',
                label: s.financeNet,
                value: _big(context, sales.net),
              ),
              _Tile(
                tileKey: 'finance-tile-orders',
                label: s.financeOrders,
                value: _bigCount(context, sales.orders),
              ),
              _Tile(
                tileKey: 'finance-tile-average',
                label: s.financeAverage,
                value: _big(context, sales.averageOrder),
              ),
            ],
          ),
          const SizedBox(height: PosSpace.s28),
          // The days are the report's own cells summed by date, so the rows
          // add up to the total line by construction; the total line is the
          // report's figure, not a re-addition of what is drawn above it.
          _Table(
            columns: [
              (label: s.financeDate, flex: 3, numeric: false),
              (label: s.financeOrders, flex: 2, numeric: true),
              (label: s.financeGross, flex: 3, numeric: true),
              (label: s.financeDiscounts, flex: 3, numeric: true),
              (label: s.financeRefunds, flex: 3, numeric: true),
              (label: s.financeNet, flex: 3, numeric: true),
            ],
            rows: [
              for (final day in sales.days)
                _TableRow(
                  Key('finance-revenue-day-${businessDayWire(day.date)}'),
                  [
                    _code(context, businessDayWire(day.date)),
                    _count(context, day.orders),
                    MonoAmount(day.gross),
                    MonoAmount(day.discounts),
                    MonoAmount(day.refunds),
                    MonoAmount(day.net),
                  ],
                ),
            ],
            total: _TableRow(const Key('finance-revenue-total'), [
              _text(context, s.financeTotal, strong: true),
              _count(context, sales.orders, strong: true),
              MonoAmount(sales.gross, weight: FontWeight.w600),
              MonoAmount(sales.discounts, weight: FontWeight.w600),
              MonoAmount(sales.refunds, weight: FontWeight.w600),
              MonoAmount(sales.net, weight: FontWeight.w600),
            ]),
          ),
          const SizedBox(height: PosSpace.md),
          _Note(s.financeRefundsNote),
        ],
      ),
    );
  }
}

/// Payments: the methods, and every payment behind them.
class FinancePaymentsPane extends StatelessWidget {
  const FinancePaymentsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return _FinanceFrame(
      paneKey: 'finance-payments',
      blurb: s.financePaymentsBlurb,
      builder: (ref, filter) => _read(
        context,
        ref.watch(salesReportProvider(filter)),
        (sales) {
          final methods = sales.paymentsByMethod;
          final shares = sales.tenderShares;
          final zero = Money(0, currency: sales.currency, exponent: sales.exponent);
          return [
            MicroLabel(s.financeByMethod),
            const SizedBox(height: PosSpace.sm),
            if (methods.isEmpty)
              _Note(s.financeNoPayments)
            else
              _Table(
                columns: [
                  (label: s.financeMethod, flex: 4, numeric: false),
                  (label: s.financePaymentCount, flex: 2, numeric: true),
                  (label: s.financeAmount, flex: 3, numeric: true),
                  (label: s.financeShare, flex: 2, numeric: true),
                ],
                rows: [
                  for (final (i, method) in methods.indexed)
                    _TableRow(Key('finance-method-row-$i'), [
                      _text(
                        context,
                        // On account is listed — it is payment rows — but
                        // named for what it is, and given no share: it is
                        // owed, not taken (§3a rule 3).
                        method.bucket == PaymentBucket.onAccount
                            ? '${method.label} · ${s.financeKpiOnAccount}'
                            : method.label,
                      ),
                      _count(context, method.count),
                      MonoAmount(method.amount),
                      switch (shares.firstWhereOrNull(
                        (t) => t.method.sameMethodAs(method),
                      )) {
                        final share? => _code(
                          context,
                          formatShareBp(share.basisPoints),
                        ),
                        null => _code(context, '—'),
                      },
                    ]),
                ],
                // Summed off the rows drawn above it, which are every payment
                // of the period by method — so the line is collected plus on
                // account, and says so by being their sum.
                total: _TableRow(const Key('finance-method-total'), [
                  _text(context, s.financeTotal, strong: true),
                  _count(
                    context,
                    methods.fold(0, (sum, m) => sum + m.count),
                    strong: true,
                  ),
                  MonoAmount(
                    methods.fold(zero, (sum, m) => sum + m.amount),
                    weight: FontWeight.w600,
                  ),
                  const SizedBox.shrink(),
                ]),
              ),
            const SizedBox(height: PosSpace.s28),
            MicroLabel(s.financeLedgerTitle),
            const SizedBox(height: PosSpace.sm),
            ..._read(
              context,
              ref.watch(paymentLedgerProvider(filter)),
              (ledger) => [
                if (ledger.entries.isEmpty)
                  _Note(s.financeNoPayments)
                else ...[
                  _Table(
                    columns: [
                      (label: s.financeTime, flex: 3, numeric: false),
                      (label: s.financeInvoice, flex: 3, numeric: false),
                      (label: s.terminalCell, flex: 3, numeric: false),
                      (label: s.financeMethod, flex: 3, numeric: false),
                      (label: s.financeAmount, flex: 3, numeric: true),
                    ],
                    rows: [
                      for (final entry in ledger.entries)
                        _TableRow(Key('finance-ledger-row-${entry.paymentId}'), [
                          _code(context, _stamp(entry.occurredAt)),
                          _code(context, entry.invoiceNumber),
                          switch (entry.terminalName) {
                            final name? => _text(context, name),
                            // A stranger terminal, listed as the terminal
                            // table lists it: by the id it wrote.
                            null => _code(context, entry.terminalId),
                          },
                          _text(context, entry.label),
                          MonoAmount(entry.amount),
                        ]),
                    ],
                    total: _TableRow(const Key('finance-ledger-total'), [
                      _text(context, s.financeLedgerTotal, strong: true),
                      const SizedBox.shrink(),
                      const SizedBox.shrink(),
                      const SizedBox.shrink(),
                      MonoAmount(ledger.total, weight: FontWeight.w600),
                    ]),
                  ),
                  if (ledger.truncated) ...[
                    const SizedBox(height: PosSpace.sm),
                    _Note(s.financeLedgerTruncated(ledger.entries.length)),
                  ],
                ],
              ],
            ),
          ];
        },
      ),
    );
  }
}

/// Taxes: charged by rate, less what refunds gave back — the figure a VAT
/// return needs.
class FinanceTaxesPane extends StatelessWidget {
  const FinanceTaxesPane({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return _FinanceFrame(
      paneKey: 'finance-taxes',
      blurb: s.financeTaxesBlurb,
      builder: (ref, filter) => _read(
        context,
        ref.watch(taxReportProvider(filter)),
        (taxes) {
          final unattributed = taxes.unattributedRefunds;
          if (taxes.rates.isEmpty && unattributed.minor == 0) {
            return [_Note(s.financeNoTaxes)];
          }
          final zero = Money(0, currency: taxes.currency, exponent: taxes.exponent);
          return [
            _Table(
              columns: [
                (label: s.financeTaxName, flex: 3, numeric: false),
                (label: s.financeTaxRate, flex: 2, numeric: true),
                (label: s.financeTaxBase, flex: 3, numeric: true),
                (label: s.financeTaxCharged, flex: 3, numeric: true),
                (label: s.financeTaxRefunded, flex: 3, numeric: true),
                (label: s.financeTaxNet, flex: 3, numeric: true),
              ],
              rows: [
                for (final (i, rate) in taxes.rates.indexed)
                  _TableRow(Key('finance-tax-row-$i'), [
                    _text(context, rate.name),
                    _code(context, AdminText.rateBp(rate.rateBp)),
                    MonoAmount(rate.base),
                    MonoAmount(rate.charged),
                    MonoAmount(rate.refunded),
                    MonoAmount(rate.net),
                  ]),
                if (unattributed.minor != 0)
                  _TableRow(const Key('finance-tax-unattributed'), [
                    _text(context, s.financeTaxUnattributed),
                    _code(context, '—'),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    MonoAmount(unattributed),
                    MonoAmount(-unattributed),
                  ]),
              ],
              // Charged, refunded and net are the report's own sums of these
              // rows; the base is summed here because the report has no use
              // for it beyond this line.
              total: _TableRow(const Key('finance-tax-total'), [
                _text(context, s.financeTotal, strong: true),
                const SizedBox.shrink(),
                MonoAmount(
                  taxes.rates.fold(zero, (sum, r) => sum + r.base),
                  weight: FontWeight.w600,
                ),
                MonoAmount(taxes.charged, weight: FontWeight.w600),
                MonoAmount(taxes.refunded, weight: FontWeight.w600),
                MonoAmount(taxes.net, weight: FontWeight.w600),
              ]),
            ),
            const SizedBox(height: PosSpace.md),
            _Note(s.financeTaxNote),
          ];
        },
      ),
    );
  }
}

/// The part every Finance pane shares: what it is, the period, the range.
///
/// **The range is worked out from the open business day**, not the
/// calendar: at 1 a.m. on a night that runs past midnight, "today" is the day
/// still being traded, which is the date its sales are filed under. With no
/// day open it is the calendar's, as the sales list files a sale no day
/// covers.
class _FinanceFrame extends ConsumerWidget {
  const _FinanceFrame({
    required this.paneKey,
    required this.blurb,
    required this.builder,
  });

  final String paneKey;
  final String blurb;
  final List<Widget> Function(WidgetRef ref, ReportFilter filter) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(businessDayProvider);
    // Nothing until the open day is known. A range from the calendar first
    // and then from the day would ask the database twice and show the wrong
    // day's figures in between. An error falls back on the calendar: the day
    // is only the anchor, and a range is still better than no screen.
    if (!day.hasValue && !day.hasError) {
      return SizedBox.expand(key: Key(paneKey));
    }
    final open = day.valueOrNull?.date;
    final filter = financeFilter(
      ref.watch(financePeriodProvider),
      today: open ?? DateTime.now(),
      firstDayOfWeekIndex: MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );
    return ListView(
      key: Key(paneKey),
      padding: const EdgeInsets.all(PosSpace.s24),
      children: [
        Text(blurb, style: PosText.ui(size: 13.5, color: context.pos.body)),
        const SizedBox(height: PosSpace.lg),
        _PeriodBar(filter: filter),
        const SizedBox(height: PosSpace.s24),
        ...builder(ref, filter),
      ],
    );
  }
}

/// The four periods, and the business dates the chosen one covers.
///
/// Selection is a border, as everywhere in this design: ink and two pixels
/// for the chosen period, a resting line for the rest. No tint.
class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final s = context.strings;
    final chosen = ref.watch(financePeriodProvider);
    final last = DateTime(filter.to.year, filter.to.month, filter.to.day - 1);
    final range = last == filter.from
        ? businessDayWire(last)
        : '${businessDayWire(filter.from)} → ${businessDayWire(last)}';
    return Row(
      children: [
        for (final period in FinancePeriod.values) ...[
          GestureDetector(
            key: Key('finance-period-${period.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(financePeriodProvider.notifier).state = period,
            child: Container(
              height: PosSize.filterChip,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
              decoration: BoxDecoration(
                color: pos.surface,
                border: Border.fromBorderSide(
                  period == chosen ? pos.emphasis : pos.resting,
                ),
              ),
              child: Text(
                financePeriodLabel(s, period),
                maxLines: 1,
                style: PosText.ui(
                  size: 13,
                  weight: period == chosen ? FontWeight.w700 : FontWeight.w500,
                  color: period == chosen ? pos.ink : pos.body,
                ),
              ),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
        ],
        const Spacer(),
        MicroLabel(s.financeBusinessDates),
        const SizedBox(width: PosSpace.sm),
        MonoCode(
          range,
          key: const Key('finance-range'),
          size: 13,
          color: pos.ink,
        ),
      ],
    );
  }
}

/// A figure, or the words for why there is none. Loading is a gap of the
/// height the figures will take, so the page does not jump when they land.
List<Widget> _read<T extends Object>(
  BuildContext context,
  AsyncValue<T?> value,
  List<Widget> Function(T) build,
) => switch (value) {
  AsyncData(value: final found?) => build(found),
  AsyncData() => [_Note(context.strings.financeNoFigures)],
  AsyncError() => [_Note(context.strings.financeUnavailable, danger: true)],
  _ => const [SizedBox(height: 120)],
};

Widget _big(BuildContext context, Money? value) => switch (value) {
  final amount? => MonoAmount(amount, size: 26, weight: FontWeight.w600),
  // No average with no sales — "none", not a sale of zero.
  null => Text('—', style: PosText.mono(size: 26, color: context.pos.muted)),
};

Widget _bigCount(BuildContext context, int value) => Text(
  '$value',
  textDirection: TextDirection.ltr,
  style: PosText.mono(size: 26, weight: FontWeight.w600, color: context.pos.ink),
);

Widget _count(BuildContext context, int value, {bool strong = false}) => Text(
  '$value',
  textDirection: TextDirection.ltr,
  style: PosText.mono(
    size: 13,
    weight: strong ? FontWeight.w600 : FontWeight.w400,
    color: context.pos.ink,
  ),
);

Widget _code(BuildContext context, String text) =>
    MonoCode(text, size: 13, color: context.pos.ink);

Widget _text(BuildContext context, String text, {bool strong = false}) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: PosText.ui(
    size: 13,
    weight: strong ? FontWeight.w700 : FontWeight.w500,
    color: context.pos.ink,
  ),
);

/// Western digits in both languages, as the backup pane prints its copies.
String _stamp(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${businessDayWire(local)} ${two(local.hour)}:${two(local.minute)}';
}

/// Equal-width tiles of equal height, with the design's gutter between.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.children});

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

/// A KPI tile. A bordered surface, never a tinted one (`07-design-system.md`).
class _Tile extends StatelessWidget {
  const _Tile({required this.tileKey, required this.label, required this.value});

  final String tileKey;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => PosSurface(
    key: Key(tileKey),
    padding: const EdgeInsets.all(PosSpace.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(label),
        const SizedBox(height: PosSpace.sm),
        value,
      ],
    ),
  );
}

/// The payment methods' shares of what was collected, as a bar and a legend.
///
/// **A 100% stacked bar, not the mockup's donut** (plan 19 §2.3): square, as
/// everything here is, and a legend beside a bar reads the same in Arabic,
/// where a donut's clockwise order does not.
class _TenderCard extends StatelessWidget {
  const _TenderCard({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final s = context.strings;
    final shares = report.tenderShares;
    final palette = tenderColours(pos);
    Color colourOf(int i) => palette[i % palette.length];
    return PosSurface(
      key: const Key('finance-tenders'),
      padding: const EdgeInsets.all(PosSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(s.financeTendersTitle),
          const SizedBox(height: PosSpace.md),
          if (shares.isEmpty)
            _Note(s.financeNothingCollected)
          else ...[
            TenderShareBar(
              key: const Key('finance-tender-bar'),
              basisPoints: [for (final share in shares) share.basisPoints],
              colours: [for (var i = 0; i < shares.length; i++) colourOf(i)],
            ),
            const SizedBox(height: PosSpace.md),
            for (final (i, share) in shares.indexed)
              _LegendRow(
                rowKey: Key('finance-tender-row-$i'),
                colour: colourOf(i),
                label: share.method.label,
                amount: share.method.amount,
                share: formatShareBp(share.basisPoints),
              ),
            // The report's own collected figure — which is the rows above by
            // construction, since both are the collected methods summed.
            _LegendRow(
              rowKey: const Key('finance-tender-total'),
              label: s.financeTotal,
              amount: report.collected,
              share: formatShareBp(
                shares.fold(0, (sum, share) => sum + share.basisPoints),
              ),
              strong: true,
            ),
          ],
          if (report.onAccount.minor != 0) ...[
            const SizedBox(height: PosSpace.md),
            _LegendRow(
              rowKey: const Key('finance-on-account'),
              label: s.financeKpiOnAccount,
              amount: report.onAccount,
            ),
            const SizedBox(height: PosSpace.xs),
            Text(
              s.financeOnAccountNote,
              style: PosText.ui(size: 12.5, color: pos.muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

/// The colours the bar takes its segments in, in order. Palette tokens only,
/// full strength — no pastel: a light tint of the accent beside the accent is
/// two segments nobody can tell apart on a till's screen in daylight.
List<Color> tenderColours(PosPalette pos) => [
  pos.accent,
  pos.ink,
  pos.ok,
  pos.warn,
  pos.danger,
  pos.muted,
];

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.rowKey,
    required this.label,
    required this.amount,
    this.colour,
    this.share,
    this.strong = false,
  });

  final Key rowKey;
  final String label;
  final Money amount;
  final Color? colour;
  final String? share;
  final bool strong;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: rowKey,
    height: PosSize.reportRow,
    child: Row(
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: colour == null ? null : ColoredBox(color: colour!),
        ),
        const SizedBox(width: PosSpace.sm),
        Expanded(child: _text(context, label, strong: strong)),
        MonoAmount(
          amount,
          weight: strong ? FontWeight.w600 : FontWeight.w400,
        ),
        SizedBox(
          width: 88,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: share == null ? null : _code(context, share!),
          ),
        ),
      ],
    ),
  );
}

/// The stacked bar itself.
///
/// **Integers until the last step.** The shares arrive in basis points that
/// sum to 10,000; this is the one place they become pixels, so no `double`
/// ever holds a figure — only a position on the screen.
///
/// Drawn from the start edge: the right, in Arabic, so the first method in
/// the legend is the first segment the eye meets in either language.
class TenderShareBar extends StatelessWidget {
  const TenderShareBar({
    required this.basisPoints,
    required this.colours,
    super.key,
  });

  final List<int> basisPoints;
  final List<Color> colours;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 20,
    width: double.infinity,
    child: CustomPaint(
      painter: _SharePainter(
        basisPoints: basisPoints,
        colours: colours,
        direction: Directionality.of(context),
      ),
    ),
  );
}

class _SharePainter extends CustomPainter {
  _SharePainter({
    required this.basisPoints,
    required this.colours,
    required this.direction,
  });

  final List<int> basisPoints;
  final List<Color> colours;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    var from = 0;
    for (final (i, bp) in basisPoints.indexed) {
      final to = from + bp;
      final start = size.width * from / 10000;
      final end = size.width * to / 10000;
      final rect = direction == TextDirection.rtl
          ? Rect.fromLTRB(size.width - end, 0, size.width - start, size.height)
          : Rect.fromLTRB(start, 0, end, size.height);
      canvas.drawRect(rect, Paint()..color = colours[i]);
      from = to;
    }
  }

  @override
  bool shouldRepaint(_SharePainter old) =>
      old.direction != direction ||
      !const ListEquality<int>().equals(old.basisPoints, basisPoints) ||
      !const ListEquality<Color>().equals(old.colours, colours);
}

typedef _Column = ({String label, int flex, bool numeric});

class _TableRow {
  const _TableRow(this.key, this.cells);

  final Key key;
  final List<Widget> cells;
}

/// Rows of figures under a header, and a total line under a heavier rule.
///
/// Figures sit on the end side — the right in English, the left in Arabic —
/// and are mono and left to right inside that, so a column still aligns on
/// its decimal point when the page is mirrored.
class _Table extends StatelessWidget {
  const _Table({
    required this.columns,
    required this.rows,
    required this.total,
  });

  final List<_Column> columns;
  final List<_TableRow> rows;
  final _TableRow total;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    Widget line(Key? key, List<Widget> cells, Border border) => Container(
      key: key,
      constraints: const BoxConstraints(minHeight: PosSize.reportRow),
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
      decoration: BoxDecoration(border: border),
      child: Row(
        children: [
          for (final (i, column) in columns.indexed) ...[
            if (i > 0) const SizedBox(width: PosSpace.sm),
            Expanded(
              flex: column.flex,
              child: Align(
                alignment: column.numeric
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: cells[i],
              ),
            ),
          ],
        ],
      ),
    );
    return PosSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(null, [
            for (final column in columns) MicroLabel(column.label),
          ], Border(bottom: pos.resting)),
          for (final row in rows)
            line(row.key, row.cells, Border(bottom: pos.hairline)),
          line(total.key, total.cells, Border(top: pos.emphasis)),
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
    style: PosText.ui(
      size: 13,
      color: danger ? context.pos.danger : context.pos.body,
      height: 1.4,
    ),
  );
}
