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
import '../../../domain/models/business_day.dart';
import '../../../domain/models/finance_report.dart';
import '../../../domain/models/sales_report.dart';
import '../../../domain/models/shift.dart';
import 'admin_messages.dart';

/// Finance (BO-9, BO-10; plan 19 §2.4): money that moved, read-only, over
/// ledgers that already exist.
///
/// **Four panes, not one pane with tabs of its own.** The shell's sub-nav
/// already draws a second row for a tab with more than one pane, and the
/// table-driven shell test already holds every pane to `managementPanesFor`;
/// tabs inside one pane (Purchasing's shape) would be a second navigation the
/// shell knows nothing about, and a gate the shell test could not see.
///
/// **What is not here, and why.** Net profit (no cost price), bank and
/// e-wallet balances and settlements (no accounting model), rent and salaries
/// (no expense entity — Wave Q) and the account column (no chart of accounts)
/// have no source and are cut, not stubbed: a tile reading zero would say the
/// restaurant made nothing, which is a claim, not an absence.

String financePeriodLabel(AppStrings s, FinancePeriod period) =>
    switch (period) {
      FinancePeriod.today => s.financePeriodToday,
      FinancePeriod.thisWeek => s.financePeriodThisWeek,
      FinancePeriod.thisMonth => s.financePeriodThisMonth,
      FinancePeriod.lastMonth => s.financePeriodLastMonth,
    };

/// Where a Finance card or row leads — each to its own screen (plan 19 §2.4).
enum FinanceTarget {
  /// The Sales tab, whose list a sale row is one of.
  sales,

  /// Purchasing, on its invoices.
  supplierInvoices,

  /// Purchasing, on its payments.
  supplierPayments,

  /// Finance's own panes, for a card's "View all".
  expenses,
  drawers,
  bills,
  transactions,
}

/// How a Finance pane asks the back office to open somewhere. Answers null
/// for a place this person does not have, and the pane then draws no link —
/// the back office owns which panes exist, so the pane only asks.
typedef FinanceLinks = VoidCallback? Function(FinanceTarget target);

/// Where a row of [kind] leads. A pay-out has no screen of its own beyond
/// Expenses; the till's cash screen is the counter's, not the back office's.
FinanceTarget financeTargetOf(FinanceTransactionKind kind) => switch (kind) {
  FinanceTransactionKind.sale => FinanceTarget.sales,
  FinanceTransactionKind.payOut => FinanceTarget.expenses,
  FinanceTransactionKind.supplierInvoice => FinanceTarget.supplierInvoices,
  FinanceTransactionKind.supplierPayment => FinanceTarget.supplierPayments,
};

/// Enum-keyed, so a new kind, state or group fails to compile here until it
/// has its words in both languages (`capability_labels_test.dart`).
String financeKindLabel(AppStrings s, FinanceTransactionKind kind) =>
    switch (kind) {
      FinanceTransactionKind.sale => s.financeKindSale,
      FinanceTransactionKind.payOut => s.financeKindPayOut,
      FinanceTransactionKind.supplierInvoice => s.financeKindSupplierInvoice,
      FinanceTransactionKind.supplierPayment => s.financeKindSupplierPayment,
    };

String financeStatusLabel(AppStrings s, FinanceTransactionStatus status) =>
    switch (status) {
      FinanceTransactionStatus.paid => s.financeStatusPaid,
      FinanceTransactionStatus.partlyPaid => s.financeStatusPartlyPaid,
      FinanceTransactionStatus.unpaid => s.financeStatusUnpaid,
      FinanceTransactionStatus.partlyRefunded => s.financeStatusPartlyRefunded,
      FinanceTransactionStatus.refunded => s.financeStatusRefunded,
      FinanceTransactionStatus.open => s.financeStatusOpen,
      FinanceTransactionStatus.voided => s.financeStatusVoided,
      FinanceTransactionStatus.recorded => s.financeStatusRecorded,
    };

String billsDueBucketLabel(AppStrings s, BillsDueBucket bucket) =>
    switch (bucket) {
      BillsDueBucket.overdue => s.financeBucketOverdue,
      BillsDueBucket.dueToday => s.financeBucketToday,
      BillsDueBucket.nextSevenDays => s.financeBucketWeek,
      BillsDueBucket.later => s.financeBucketLater,
    };

/// The sentence under every expenses figure: what it is made of, and — when
/// the supplier ledger is not in it — why not.
String supplierFiguresNote(AppStrings s, SupplierFigures figures) =>
    switch (figures) {
      SupplierFigures.included => s.financeExpensesWithSuppliers,
      SupplierFigures.onPlatform =>
        '${s.financeExpensesPayOutsOnly} ${s.financeSuppliersOnPlatform}',
      SupplierFigures.notPermitted =>
        '${s.financeExpensesPayOutsOnly} ${s.financeSuppliersNotPermitted}',
    };

/// A share in basis points as a person reads it: `51.92%`.
///
/// Two decimals because that is what a basis point is, and the shares were
/// already rounded once — to sum to 10,000 — by `basisPointShares`. Printing
/// them to one decimal would be a second rounding, and a legend that adds up
/// to 100.1%.
String formatShareBp(int bp) =>
    '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%';

/// Overview: the period's revenue, what was collected and owed, the tax, the
/// tender bar — and, since BO-10, what went out, what the drawers should
/// hold, what is owed to suppliers and the latest movements.
class FinanceOverviewPane extends StatelessWidget {
  const FinanceOverviewPane({super.key, this.links});

  /// Where its cards and rows lead. Null draws no links.
  final FinanceLinks? links;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return _FinanceFrame(
      paneKey: 'finance-overview',
      blurb: s.financeOverviewBlurb,
      builder: (ref, filter, today) => _read(
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
          const SizedBox(height: PosSpace.md),
          // The mockup's other two headline figures, as far as they have a
          // source: expenses as its label says, and the cash the open drawers
          // should hold in place of a "cash balance" no account exists to
          // keep (plan 19 §2.4).
          _TileRow(
            children: [
              _ExpensesTile(filter: filter),
              const _DrawersTile(),
            ],
          ),
          const SizedBox(height: PosSpace.s28),
          _TenderCard(report: sales),
          const SizedBox(height: PosSpace.s28),
          _ExpensesAndBills(filter: filter, today: today, links: links),
          const SizedBox(height: PosSpace.s28),
          _RecentTransactions(filter: filter, links: links),
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
      builder: (ref, filter, _) => _read(
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
      builder: (ref, filter, _) => _read(
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
      builder: (ref, filter, _) => _read(
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
    this.periodic = true,
  });

  final String paneKey;
  final String blurb;

  /// False for a pane that is a snapshot of now — the drawers, the bills due
  /// — which shows the business date it is as of instead of the period chips.
  /// Chips over a figure that does not move with them would be a control that
  /// changes nothing, which reads as a control that is broken.
  final bool periodic;

  /// Handed the tab's range and the business date it was worked out from.
  final List<Widget> Function(
    WidgetRef ref,
    ReportFilter filter,
    DateTime today,
  )
  builder;

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
    final now = day.valueOrNull?.date ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final filter = financeFilter(
      ref.watch(financePeriodProvider),
      today: today,
      firstDayOfWeekIndex: MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );
    return ListView(
      key: Key(paneKey),
      padding: const EdgeInsets.all(PosSpace.s24),
      children: [
        Text(blurb, style: PosText.ui(size: 13.5, color: context.pos.body)),
        const SizedBox(height: PosSpace.lg),
        if (periodic) _PeriodBar(filter: filter) else _AsOfBar(date: today),
        const SizedBox(height: PosSpace.s24),
        ...builder(ref, filter, today),
      ],
    );
  }
}

/// The business date a snapshot pane is read against.
class _AsOfBar extends StatelessWidget {
  const _AsOfBar({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: PosSize.filterChip,
    child: Row(
      children: [
        MicroLabel(context.strings.financeAsOf),
        const SizedBox(width: PosSpace.sm),
        MonoCode(
          businessDayWire(date),
          key: const Key('finance-as-of'),
          size: 13,
          color: context.pos.ink,
        ),
      ],
    ),
  );
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

Widget _text(
  BuildContext context,
  String text, {
  bool strong = false,
  Color? color,
}) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: PosText.ui(
    size: 13,
    weight: strong ? FontWeight.w700 : FontWeight.w500,
    color: color ?? context.pos.ink,
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
  const _Tile({
    required this.tileKey,
    required this.label,
    required this.value,
    this.caption,
  });

  final String tileKey;
  final String label;
  final Widget value;

  /// What the figure is made of, when the label alone would oversell it.
  final String? caption;

  @override
  Widget build(BuildContext context) => PosSurface(
    key: Key(tileKey),
    padding: const EdgeInsets.all(PosSpace.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(label),
        const SizedBox(height: PosSpace.sm),
        // Scaled down, never cut off: five tiles across 1100 px leave a
        // seven-figure amount no room at full size, and an ellipsis in the
        // middle of a sum is a different sum.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: value,
        ),
        if (caption case final text?) ...[
          const SizedBox(height: PosSpace.xs),
          Text(
            text,
            style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.4),
          ),
        ],
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
  const _TableRow(this.key, this.cells, {this.onTap});

  final Key key;
  final List<Widget> cells;

  /// Where the row leads, when it leads anywhere. The whole row is the
  /// target: a row is what a person points at, not a word inside it.
  final VoidCallback? onTap;
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
    this.total,
  });

  final List<_Column> columns;
  final List<_TableRow> rows;

  /// Null for a table whose rows must not be summed — the transactions, where
  /// an invoice and its payment are two rows for one debt.
  final _TableRow? total;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    Widget line(
      Key? key,
      List<Widget> cells,
      Border border, {
      VoidCallback? onTap,
    }) {
      final row = Container(
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
      return onTap == null
          ? row
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: row,
            );
    }

    return PosSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(null, [
            for (final column in columns) MicroLabel(column.label),
          ], Border(bottom: pos.resting)),
          for (final row in rows)
            line(
              row.key,
              row.cells,
              Border(bottom: pos.hairline),
              onTap: row.onTap,
            ),
          if (total case final total?)
            line(total.key, total.cells, Border(top: pos.emphasis)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.danger = false, super.key});

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

// ── BO-10 ───────────────────────────────────────────────────────────────────

/// Expenses: drawer pay-outs and supplier payments, and the sentence that
/// says which of the two the figure holds.
class FinanceExpensesPane extends StatelessWidget {
  const FinanceExpensesPane({super.key, this.links});

  final FinanceLinks? links;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return _FinanceFrame(
      paneKey: 'finance-expenses',
      blurb: s.financeExpensesBlurb,
      builder: (ref, filter, _) => _read(
        context,
        ref.watch(expenseReportProvider(filter)),
        (report) {
          final included = report.supplierFigures == SupplierFigures.included;
          final entries = report.entries;
          return [
            _TileRow(
              children: [
                _Tile(
                  tileKey: 'finance-tile-expenses-total',
                  label: s.financeKpiExpenses,
                  value: _big(context, report.total),
                ),
                _Tile(
                  tileKey: 'finance-tile-payouts',
                  label: s.financePayOuts,
                  value: _big(context, report.payOutTotal),
                ),
                // Absent rather than zero when the ledger is not read: zero
                // would say nobody was paid, which nobody here knows.
                if (included)
                  _Tile(
                    tileKey: 'finance-tile-supplier-payments',
                    label: s.financeSupplierPayments,
                    value: _big(context, report.supplierTotal),
                  ),
              ],
            ),
            const SizedBox(height: PosSpace.md),
            _Note(
              supplierFiguresNote(s, report.supplierFigures),
              key: const Key('finance-expenses-label'),
            ),
            const SizedBox(height: PosSpace.s24),
            if (entries.isEmpty)
              _Note(s.financeNoExpenses)
            else
              _Table(
                columns: [
                  (label: s.financeTime, flex: 3, numeric: false),
                  (label: s.financeType, flex: 3, numeric: false),
                  (label: s.financeDetails, flex: 6, numeric: false),
                  (label: s.financeMethod, flex: 3, numeric: false),
                  (label: s.financeAmount, flex: 3, numeric: true),
                ],
                rows: [
                  for (final entry in entries)
                    _TableRow(
                      Key('finance-expense-${entry.kind.name}-${entry.sourceId}'),
                      [
                        _code(context, _stamp(entry.occurredAt)),
                        _text(context, financeKindLabel(s, entry.kind)),
                        _text(context, _describe(context, entry)),
                        _text(context, switch (entry) {
                          // Cash, out of the drawer of the till named.
                          PayOutTransaction(:final payOut) => [
                            s.methodCash,
                            ?payOut.terminalName,
                          ].join(' · '),
                          SupplierPaymentTransaction(:final payment) =>
                            AdminText.paymentMethod(s, payment.method),
                          // Neither is ever an expense row.
                          SaleTransaction() || SupplierInvoiceTransaction() =>
                            '—',
                        }),
                        // The amount paid: the figure is a sum of these, not
                        // of their negatives.
                        MonoAmount(-entry.amount),
                      ],
                      onTap: entry.kind == FinanceTransactionKind.supplierPayment
                          ? links?.call(FinanceTarget.supplierPayments)
                          : null,
                    ),
                ],
                // The report's own total, which is these rows by
                // construction — both are the drawer's and the ledger's
                // lists, less what the report leaves out of each.
                total: _TableRow(const Key('finance-expenses-total'), [
                  _text(context, s.financeTotal, strong: true),
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  MonoAmount(report.total, weight: FontWeight.w600),
                ]),
              ),
            if (included) ...[
              const SizedBox(height: PosSpace.md),
              _Note(s.financeCountedOnce),
            ],
          ];
        },
      ),
    );
  }
}

/// Drawers: every drawer open at the branch, and what the Z report will
/// count it against. A snapshot of now, not of the period.
class FinanceDrawersPane extends StatelessWidget {
  const FinanceDrawersPane({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return _FinanceFrame(
      paneKey: 'finance-drawers',
      blurb: s.financeDrawersBlurb,
      periodic: false,
      builder: (ref, _, _) => _read(
        context,
        ref.watch(openDrawersProvider),
        (drawers) {
          Money sum(Money Function(OpenDrawer drawer) of) =>
              drawers.fold(Money.zero, (total, d) => total + of(d));
          return [
            _TileRow(
              children: [
                _Tile(
                  tileKey: 'finance-tile-drawers',
                  label: s.financeKpiDrawers,
                  value: _big(context, _expectedIn(drawers)),
                  caption: _drawerCount(s, drawers),
                ),
              ],
            ),
            const SizedBox(height: PosSpace.s24),
            if (drawers.isNotEmpty) ...[
              _Table(
                columns: [
                  (label: s.terminalCell, flex: 3, numeric: false),
                  (label: s.financeOpenedBy, flex: 3, numeric: false),
                  (label: s.financeOpenedAt, flex: 3, numeric: false),
                  (label: s.financeFloat, flex: 3, numeric: true),
                  (label: s.financeCashTaken, flex: 3, numeric: true),
                  (label: s.financePaidIn, flex: 3, numeric: true),
                  (label: s.financePaidOut, flex: 3, numeric: true),
                  (label: s.financeExpected, flex: 3, numeric: true),
                ],
                rows: [
                  for (final drawer in drawers)
                    _TableRow(Key('finance-drawer-${drawer.shift.id}'), [
                      switch (drawer.terminalName) {
                        final name? => _text(context, name),
                        null => _code(context, drawer.terminalId),
                      },
                      _text(context, drawer.shift.openedByName),
                      _code(context, _stamp(drawer.shift.openedAt)),
                      MonoAmount(drawer.shift.openingFloat),
                      MonoAmount(drawer.summary.cashTaken),
                      MonoAmount(drawer.summary.cashIn),
                      MonoAmount(drawer.summary.cashOut),
                      MonoAmount(drawer.expectedCash, weight: FontWeight.w600),
                    ]),
                ],
                total: _TableRow(const Key('finance-drawers-total'), [
                  _text(context, s.financeTotal, strong: true),
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  MonoAmount(
                    sum((d) => d.shift.openingFloat),
                    weight: FontWeight.w600,
                  ),
                  MonoAmount(
                    sum((d) => d.summary.cashTaken),
                    weight: FontWeight.w600,
                  ),
                  MonoAmount(
                    sum((d) => d.summary.cashIn),
                    weight: FontWeight.w600,
                  ),
                  MonoAmount(
                    sum((d) => d.summary.cashOut),
                    weight: FontWeight.w600,
                  ),
                  MonoAmount(_expectedIn(drawers), weight: FontWeight.w600),
                ]),
              ),
              const SizedBox(height: PosSpace.md),
            ],
            _Note(s.financeDrawersNote),
          ];
        },
      ),
    );
  }
}

/// Bills due: every unpaid supplier invoice, in exactly one group by its due
/// date against the business date. A snapshot of now.
///
/// Only reached where [billsDueProvider] answers — offline, for somebody who
/// holds `purchase.manage` as well as `reports.view` — because the shell
/// hides the pane by the same two rules.
class FinanceBillsPane extends StatelessWidget {
  const FinanceBillsPane({super.key, this.links});

  final FinanceLinks? links;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    return _FinanceFrame(
      paneKey: 'finance-bills',
      blurb: s.financeBillsBlurb,
      periodic: false,
      builder: (ref, _, today) => _read(
        context,
        ref.watch(billsDueProvider(today)),
        (bills) {
          final zero = Money(0, currency: bills.currency, exponent: bills.exponent);
          return [
            _TileRow(
              children: [
                for (final bucket in BillsDueBucket.values)
                  _Tile(
                    tileKey: 'finance-bills-${bucket.name}',
                    label: billsDueBucketLabel(s, bucket),
                    value: _big(context, bills.amount(bucket)),
                  ),
                _Tile(
                  tileKey: 'finance-bills-total',
                  label: s.financeTotalOwed,
                  value: _big(context, bills.total),
                ),
              ],
            ),
            const SizedBox(height: PosSpace.s24),
            if (bills.invoices.isEmpty)
              _Note(s.financeNoBills)
            else
              _Table(
                columns: [
                  (label: s.financeSupplier, flex: 4, numeric: false),
                  (label: s.financeInvoice, flex: 3, numeric: false),
                  (label: s.financeDueDate, flex: 3, numeric: false),
                  (label: s.financeStatus, flex: 3, numeric: false),
                  (label: s.financeAmount, flex: 3, numeric: true),
                  (label: s.financePaid, flex: 3, numeric: true),
                  (label: s.financeOutstanding, flex: 3, numeric: true),
                ],
                rows: [
                  for (final invoice in bills.invoices)
                    _TableRow(
                      Key('finance-bill-${invoice.id}'),
                      [
                        _text(context, invoice.supplierName ?? '—'),
                        _code(context, invoice.number),
                        _code(context, businessDayWire(invoice.dueAt.toLocal())),
                        _text(
                          context,
                          billsDueBucketLabel(s, bills.bucketOf(invoice)),
                          color: bills.bucketOf(invoice) == BillsDueBucket.overdue
                              ? pos.danger
                              : pos.body,
                        ),
                        MonoAmount(invoice.total),
                        MonoAmount(invoice.paid),
                        MonoAmount(invoice.outstanding),
                      ],
                      onTap: links?.call(FinanceTarget.supplierInvoices),
                    ),
                ],
                // Outstanding is the report's total, the tile beside the
                // groups; the other two are summed here for the line alone.
                total: _TableRow(const Key('finance-bills-table-total'), [
                  _text(context, s.financeTotal, strong: true),
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  MonoAmount(
                    bills.invoices.fold(zero, (sum, i) => sum + i.total),
                    weight: FontWeight.w600,
                  ),
                  MonoAmount(
                    bills.invoices.fold(zero, (sum, i) => sum + i.paid),
                    weight: FontWeight.w600,
                  ),
                  MonoAmount(bills.total, weight: FontWeight.w600),
                ]),
              ),
            const SizedBox(height: PosSpace.md),
            _Note(s.financeBillsNote),
          ];
        },
      ),
    );
  }
}

/// Transactions: sales, pay-outs, supplier invoices and supplier payments,
/// newest first — the Overview's table, all of it.
class FinanceTransactionsPane extends StatelessWidget {
  const FinanceTransactionsPane({super.key, this.links});

  final FinanceLinks? links;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return _FinanceFrame(
      paneKey: 'finance-transactions',
      blurb: s.financeTransactionsBlurb,
      builder: (ref, filter, _) => _read(
        context,
        ref.watch(financeTransactionsProvider(filter)),
        (list) => [
          if (list.entries.isEmpty)
            _Note(s.financeNoTransactions)
          else
            _TransactionsTable(entries: list.entries, links: links),
          if (list.truncated) ...[
            const SizedBox(height: PosSpace.sm),
            _Note(s.financeTransactionsTruncated(list.entries.length)),
          ],
          const SizedBox(height: PosSpace.md),
          _Note(s.financeTransactionsNote),
        ],
      ),
    );
  }
}

/// How many rows the Overview's cards show before "View all".
const _recentExpenses = 5;
const _recentTransactions = 8;

Money _expectedIn(List<OpenDrawer> drawers) =>
    drawers.fold(Money.zero, (total, d) => total + d.expectedCash);

String _drawerCount(AppStrings s, List<OpenDrawer> drawers) => drawers.isEmpty
    ? s.financeNoOpenDrawers
    : s.financeOpenDrawerCount(drawers.length);

class _ExpensesTile extends ConsumerWidget {
  const _ExpensesTile({required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final report = ref.watch(expenseReportProvider(filter)).valueOrNull;
    return _Tile(
      tileKey: 'finance-tile-expenses',
      label: s.financeKpiExpenses,
      value: _big(context, report?.total),
      // What the figure is made of, under it, every time it is shown.
      caption: switch (report) {
        final report? => supplierFiguresNote(s, report.supplierFigures),
        null => null,
      },
    );
  }
}

class _DrawersTile extends ConsumerWidget {
  const _DrawersTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final drawers = ref.watch(openDrawersProvider).valueOrNull;
    return _Tile(
      tileKey: 'finance-tile-drawers',
      label: s.financeKpiDrawers,
      value: _big(context, drawers == null ? null : _expectedIn(drawers)),
      caption: drawers == null ? null : _drawerCount(s, drawers),
    );
  }
}

/// Recent expenses, and beside it the bills-due card where there is one.
class _ExpensesAndBills extends ConsumerWidget {
  const _ExpensesAndBills({
    required this.filter,
    required this.today,
    this.links,
  });

  final ReportFilter filter;
  final DateTime today;
  final FinanceLinks? links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = _RecentExpensesCard(filter: filter, links: links);
    // **Absent, not empty**, on a cloud till and without `purchase.manage`.
    // A card reading "nothing owed" to somebody who may not see what is owed
    // would be a claim; the recent expenses take the width instead.
    if (ref.watch(supplierFiguresProvider) != SupplierFigures.included) {
      return recent;
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: recent),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: _BillsCard(today: today, links: links),
          ),
        ],
      ),
    );
  }
}

class _RecentExpensesCard extends ConsumerWidget {
  const _RecentExpensesCard({required this.filter, this.links});

  final ReportFilter filter;
  final FinanceLinks? links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    return PosSurface(
      key: const Key('finance-recent-expenses'),
      padding: const EdgeInsets.all(PosSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            title: s.financeRecentExpenses,
            openKey: 'finance-open-expenses',
            onOpen: links?.call(FinanceTarget.expenses),
          ),
          const SizedBox(height: PosSpace.sm),
          ..._read(context, ref.watch(expenseReportProvider(filter)), (report) {
            final entries = report.entries;
            return [
              if (entries.isEmpty)
                _Note(s.financeNoExpenses)
              else
                for (final entry in entries.take(_recentExpenses))
                  _FigureLine(
                    rowKey: Key(
                      'finance-recent-expense-${entry.kind.name}-'
                      '${entry.sourceId}',
                    ),
                    label: _describe(context, entry),
                    amount: -entry.amount,
                  ),
              // The period's figure, not the rows above it: they are the
              // latest few, and the line says what all of them come to.
              _FigureLine(
                rowKey: const Key('finance-recent-expenses-total'),
                label: s.financeKpiExpenses,
                amount: report.total,
                strong: true,
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                supplierFiguresNote(s, report.supplierFigures),
                style: PosText.ui(
                  size: 12.5,
                  color: context.pos.muted,
                  height: 1.4,
                ),
              ),
            ];
          }),
        ],
      ),
    );
  }
}

class _BillsCard extends ConsumerWidget {
  const _BillsCard({required this.today, this.links});

  final DateTime today;
  final FinanceLinks? links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    return PosSurface(
      key: const Key('finance-bills-card'),
      padding: const EdgeInsets.all(PosSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            title: s.financeBills,
            openKey: 'finance-open-bills',
            onOpen: links?.call(FinanceTarget.bills),
          ),
          const SizedBox(height: PosSpace.sm),
          ..._read(context, ref.watch(billsDueProvider(today)), (bills) => [
            for (final bucket in BillsDueBucket.values)
              _FigureLine(
                rowKey: Key('finance-bills-card-${bucket.name}'),
                label: billsDueBucketLabel(s, bucket),
                count: bills.count(bucket),
                amount: bills.amount(bucket),
                danger:
                    bucket == BillsDueBucket.overdue &&
                    bills.count(bucket) > 0,
              ),
            _FigureLine(
              rowKey: const Key('finance-bills-card-total'),
              label: s.financeTotalOwed,
              count: bills.invoices.length,
              amount: bills.total,
              strong: true,
            ),
          ]),
        ],
      ),
    );
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions({required this.filter, this.links});

  final ReportFilter filter;
  final FinanceLinks? links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    return Column(
      key: const Key('finance-recent-transactions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardHeader(
          title: s.financeRecentTransactions,
          openKey: 'finance-open-transactions',
          onOpen: links?.call(FinanceTarget.transactions),
        ),
        const SizedBox(height: PosSpace.sm),
        ..._read(
          context,
          ref.watch(financeTransactionsProvider(filter)),
          (list) => [
            if (list.entries.isEmpty)
              _Note(s.financeNoTransactions)
            else
              _TransactionsTable(
                entries: list.entries.take(_recentTransactions).toList(),
                links: links,
              ),
          ],
        ),
      ],
    );
  }
}

/// The union table, shared by the Overview's card and the Transactions pane
/// so the two cannot draw one row two ways.
class _TransactionsTable extends StatelessWidget {
  const _TransactionsTable({required this.entries, this.links});

  final List<FinanceTransaction> entries;
  final FinanceLinks? links;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    return _Table(
      columns: [
        (label: s.financeType, flex: 3, numeric: false),
        (label: s.financeReference, flex: 5, numeric: false),
        (label: s.financeTime, flex: 3, numeric: false),
        (label: s.financeAmount, flex: 3, numeric: true),
        (label: s.financeStatus, flex: 2, numeric: false),
      ],
      rows: [
        for (final entry in entries)
          _TableRow(
            Key('finance-transaction-${entry.kind.name}-${entry.sourceId}'),
            [
              _text(context, financeKindLabel(s, entry.kind)),
              switch (entry) {
                // The invoice number as the receipt printed it: a code.
                SaleTransaction(:final sale) => _code(
                  context,
                  sale.invoiceNumber,
                ),
                _ => _text(context, _describe(context, entry)),
              },
              _code(context, _stamp(entry.occurredAt)),
              // A void is shown at its amount but not in the colours of money
              // that moved — it did not.
              MonoAmount(
                entry.amount,
                color: entry.status == FinanceTransactionStatus.voided
                    ? pos.muted
                    : null,
              ),
              _text(
                context,
                financeStatusLabel(s, entry.status),
                color: entry.status == FinanceTransactionStatus.voided
                    ? pos.danger
                    : pos.body,
              ),
            ],
            onTap: links?.call(financeTargetOf(entry.kind)),
          ),
      ],
    );
  }
}

/// A card's title, and its way to the whole list where there is one.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.openKey, this.onOpen});

  final String title;
  final String openKey;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: PosSize.filterChip,
    child: Row(
      children: [
        Expanded(child: MicroLabel(title)),
        if (onOpen case final open?)
          PosButton(
            key: Key(openKey),
            label: context.strings.financeViewAll,
            height: PosSize.filterChip,
            fontSize: 12.5,
            border: Border.fromBorderSide(context.pos.resting),
            onPressed: open,
          ),
      ],
    ),
  );
}

/// One figure on a card: a label, perhaps a count, and an amount; the total
/// line under a heavier rule, as a table's is.
class _FigureLine extends StatelessWidget {
  const _FigureLine({
    required this.rowKey,
    required this.label,
    required this.amount,
    this.count,
    this.strong = false,
    this.danger = false,
  });

  final Key rowKey;
  final String label;
  final Money amount;
  final int? count;
  final bool strong;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
    key: rowKey,
    constraints: const BoxConstraints(minHeight: PosSize.reportRow),
    decoration: strong
        ? BoxDecoration(border: Border(top: context.pos.emphasis))
        : null,
    child: Row(
      children: [
        Expanded(
          child: _text(
            context,
            label,
            strong: strong,
            color: danger ? context.pos.danger : null,
          ),
        ),
        if (count case final value?)
          SizedBox(
            width: 48,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _count(context, value, strong: strong),
            ),
          ),
        const SizedBox(width: PosSpace.md),
        MonoAmount(
          amount,
          weight: strong ? FontWeight.w600 : FontWeight.w400,
        ),
      ],
    ),
  );
}

/// What a row is, in words: an invoice number, a pay-out's reason and note,
/// a supplier and their bill. A switch over the sealed cases, so a fifth kind
/// of row cannot be drawn without being described.
String _describe(BuildContext context, FinanceTransaction entry) =>
    switch (entry) {
      SaleTransaction(:final sale) => sale.invoiceNumber,
      PayOutTransaction(:final payOut) => _payOutText(context, payOut),
      SupplierInvoiceTransaction(:final invoice) => [
        ?invoice.supplierName,
        invoice.number,
      ].join(' · '),
      SupplierPaymentTransaction(:final payment) => [
        ?payment.supplierName,
        payment.invoiceNumber ?? context.strings.financeKpiOnAccount,
      ].join(' · '),
    };

/// A pay-out as its drawer recorded it: the reason in the reader's language,
/// the other as the fallback — the rule a void's reason follows — and the
/// note after it.
String _payOutText(BuildContext context, CashMovement payOut) {
  final arabic = Directionality.of(context) == TextDirection.rtl;
  final reason = [
    arabic ? payOut.reasonNameAr : payOut.reasonName,
    arabic ? payOut.reasonName : payOut.reasonNameAr,
  ].firstWhereOrNull((name) => name != null && name.trim().isNotEmpty);
  final note = payOut.note?.trim();
  final parts = [?reason, if (note != null && note.isNotEmpty) note];
  return parts.isEmpty ? '—' : parts.join(' · ');
}
