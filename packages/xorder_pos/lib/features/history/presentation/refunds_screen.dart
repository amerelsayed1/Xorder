import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/refund_history.dart';
import '../history_scope.dart';
import 'history_widgets.dart';
import 'order_history_screen.dart' show SaleToOpen;
import 'refund_detail_pane.dart';

/// Returns (المرتجعات) — one row per refund the branch has given, newest
/// first, under Sales in the back office.
///
/// The sales list's shape on purpose: the same three windows, the same
/// search box, a strip over the list and a detail pane beside it, and the
/// same scope — a cashier without `order.view_all` sees the refunds against
/// their own sales (`HistoryScope.scopeRefunds`), applied in the provider.
///
/// **Its figures are its rows.** The strip is `summariseRefunds` over the
/// WHERE the list pages through, and the rows are drawn positive: every row
/// is money given back, so a sign on each would only be something to add up
/// wrong against the total above them.
///
/// A back-office pane only, so there is no Close and no Esc of its own: the
/// back office owns leaving, as it does for Orders.
class RefundsScreen extends ConsumerStatefulWidget {
  const RefundsScreen({super.key, this.onOpenSale, this.openedAt});

  /// Opens the sale a refund was against, in Orders. Null hides the button.
  final ValueChanged<SaleToOpen>? onOpenSale;

  /// The clock, for a test about a particular date.
  @visibleForTesting
  final DateTime? openedAt;

  static const ownSalesKey = ValueKey('returns-own-sales');
  static const sidewaysKey = ValueKey('returns-sideways');
  static const summaryCountKey = ValueKey('returns-summary-count');
  static const summaryTotalKey = ValueKey('returns-summary-total');

  @override
  ConsumerState<RefundsScreen> createState() => _RefundsScreenState();
}

class _RefundsScreenState extends ConsumerState<RefundsScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _sideways = ScrollController();

  HistoryRange _range = HistoryRange.today;
  String _searchTerm = '';

  /// The row clicked, kept as the row rather than its id: the pane draws its
  /// head from it, and turning the page away must not blank the pane.
  RefundRecord? _selected;

  /// Keyset pages, as the sales list turns them — see its `_cursors`.
  List<int> _cursors = const [];
  RefundHistoryQuery? _pagedFor;

  Timer? _debounce;

  late final DateTime _openedAt = widget.openedAt ?? DateTime.now();

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _sideways.dispose();
    super.dispose();
  }

  RefundHistoryQuery _query(DateTime today) {
    final (from, to) = _range.window(today);
    return RefundHistoryQuery(
      from: from,
      to: to,
      search: _searchTerm.isEmpty ? null : _searchTerm,
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchTerm = value.trim());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() => _searchTerm = '');
  }

  void _turn(RefundHistoryQuery base, List<int> cursors) => setState(() {
    _pagedFor = base;
    _cursors = cursors;
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final day = ref.watch(businessDayProvider);
    final seesEveryone = HistoryScope.seesEveryone(
      ref.watch(actingStaffProvider),
    );

    // Waits for the business day, as the sales list does, so "Today" is
    // asked once and means the trading day.
    final base = day.isLoading
        ? null
        : _query(historyToday(day.valueOrNull, _openedAt));
    final cursors = base != null && base == _pagedFor
        ? _cursors
        : const <int>[];
    final query = cursors.isEmpty
        ? base
        : base!.copyWith(afterRefundId: cursors.last);
    final rows = query == null
        ? const AsyncValue<List<RefundRecord>>.loading()
        : ref.watch(refundHistoryProvider(query));
    final summary = base == null
        ? const AsyncValue<RefundHistorySummary>.loading()
        : ref.watch(refundHistorySummaryProvider(base));

    return Scaffold(
      backgroundColor: pos.page,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _searchFocus.requestFocus,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _searchFocus.requestFocus,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, strings, summary.valueOrNull?.count, seesEveryone),
              _filters(strings),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _strip(context, strings, summary),
                          Expanded(
                            child: _list(
                              context,
                              strings,
                              rows,
                              query,
                              cursors,
                              summary.valueOrNull,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: PosSize.historyDetail,
                      decoration: BoxDecoration(
                        color: pos.surface,
                        border: BorderDirectional(start: pos.resting),
                      ),
                      child: RefundDetailPane(
                        refund: _selected,
                        onOpenSale: widget.onOpenSale,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppStrings strings,
    int? count,
    bool seesEveryone,
  ) {
    final pos = context.pos;
    final slice = [
      _range.label(strings),
      if (count != null) strings.returnsCount(count),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PosSpace.s18,
        PosSpace.xl,
        PosSpace.s18,
        PosSpace.md,
      ),
      child: Row(
        children: [
          Text(slice, style: PosText.ui(size: 13.5, color: pos.muted)),
          // Said, as on the sales list: a cashier shown three refunds on a
          // day of twelve should know why.
          if (!seesEveryone)
            Text(
              ' · ${strings.orderHistoryOwnSalesOnly}',
              key: RefundsScreen.ownSalesKey,
              style: PosText.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: pos.inkWarm,
              ),
            ),
        ],
      ),
    );
  }

  Widget _filters(AppStrings strings) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PosSpace.s18,
      0,
      PosSpace.s18,
      PosSpace.md,
    ),
    child: Wrap(
      spacing: PosSpace.sm,
      runSpacing: PosSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final range in HistoryRange.values)
          HistoryFilterChip(
            label: range.label(strings),
            selected: _range == range,
            onTap: () => setState(() => _range = range),
          ),
        const HistoryFilterDivider(),
        HistorySearchField(
          controller: _search,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          hint: strings.returnsSearchHint,
        ),
      ],
    ),
  );

  /// Two figures: how many, and what went back. A dash for a figure not
  /// read; the list says why when it cannot be.
  Widget _strip(
    BuildContext context,
    AppStrings strings,
    AsyncValue<RefundHistorySummary> summary,
  ) {
    final pos = context.pos;
    final figures = summary.valueOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PosSpace.s18,
        0,
        PosSpace.s18,
        PosSpace.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: HistorySummaryTile(
              label: strings.returnsSummaryCount,
              value: figures == null
                  ? HistorySummaryTile.dash(pos, RefundsScreen.summaryCountKey)
                  : HistorySummaryTile.count(
                      pos,
                      RefundsScreen.summaryCountKey,
                      figures.count,
                    ),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            child: HistorySummaryTile(
              label: strings.returnsSummaryTotal,
              value: figures == null
                  ? HistorySummaryTile.dash(pos, RefundsScreen.summaryTotalKey)
                  : MonoAmount(
                      figures.total,
                      key: RefundsScreen.summaryTotalKey,
                      size: 20,
                      weight: FontWeight.w600,
                      color: pos.ink,
                    ),
              note: strings.returnsSummaryTotalNote,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    AppStrings strings,
    AsyncValue<List<RefundRecord>> rows,
    RefundHistoryQuery? query,
    List<int> cursors,
    RefundHistorySummary? summary,
  ) => rows.when(
    loading: () =>
        Center(child: CircularProgressIndicator(color: context.pos.accent)),
    error: (error, _) => HistoryMessage(
      message: strings.returnsUnavailable,
      detail: '$error',
    ),
    data: (data) {
      final filtered = query?.isFiltered ?? false;
      if (data.isEmpty && cursors.isEmpty) {
        return HistoryMessage(
          message: filtered
              ? strings.returnsEmptyFiltered
              : strings.returnsEmpty,
          action: filtered
              ? (strings.orderHistoryClearFilters, _clearSearch)
              : null,
        );
      }
      final base = query?.unpaged;
      final limit = query?.limit ?? RefundHistoryQuery.pageSize;
      final offset = cursors.length * limit;
      final total = summary?.count;
      final hasNext = HistoryPager.hasNext(
        length: data.length,
        limit: limit,
        offset: offset,
        total: total,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: HistoryTable(
              minWidth: _Cols.minTable,
              sideways: _sideways,
              sidewaysKey: RefundsScreen.sidewaysKey,
              headings: _headings(strings),
              rows: ListView.builder(
                key: ValueKey(('returns-rows', query?.afterRefundId)),
                padding: EdgeInsets.zero,
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final refund = data[index];
                  return _RefundRow(
                    refund: refund,
                    selected: refund.id == _selected?.id,
                    onTap: () => setState(() => _selected = refund),
                  );
                },
              ),
            ),
          ),
          HistoryPager(
            first: data.isEmpty ? offset : offset + 1,
            last: offset + data.length,
            total: total,
            page: cursors.length + 1,
            pages: HistoryPager.pagesOf(total, limit),
            onPrevious: base == null || cursors.isEmpty
                ? null
                : () => _turn(base, cursors.sublist(0, cursors.length - 1)),
            onNext: base == null || !hasNext
                ? null
                : () => _turn(base, [...cursors, data.last.id]),
          ),
        ],
      );
    },
  );

  Widget _headings(AppStrings strings) => HistoryHeadings(
    children: [
      SizedBox(width: _Cols.refund, child: MicroLabel(strings.returnColumnRefund)),
      SizedBox(width: _Cols.time, child: MicroLabel(strings.orderColumnTime)),
      SizedBox(
        width: _Cols.invoice,
        child: MicroLabel(strings.returnColumnInvoice),
      ),
      Expanded(child: MicroLabel(strings.returnColumnCashier)),
      const SizedBox(width: PosSpace.sm),
      Expanded(child: MicroLabel(strings.returnColumnReason)),
      const SizedBox(width: PosSpace.sm),
      SizedBox(
        width: _Cols.lines,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: MicroLabel(strings.returnColumnLines),
        ),
      ),
      const SizedBox(width: PosSpace.sm),
      SizedBox(
        width: _Cols.amount,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: MicroLabel(strings.returnColumnAmount),
        ),
      ),
      const SizedBox(width: PosSpace.md),
      Expanded(child: MicroLabel(strings.orderColumnTerminal)),
    ],
  );
}

/// Column widths, in one place so the headings and the rows cannot drift.
abstract final class _Cols {
  static const refund = 72.0;

  /// `2026-09-14 13:05` in 12 px mono. The date as well as the time: the
  /// window reaches back a month, and a refund is asked about by its day.
  static const time = 124.0;
  static const invoice = 132.0;
  static const lines = 56.0;
  static const amount = 104.0;

  /// The least each of the three columns sharing what is left — who gave it,
  /// why, which till — gets before the table scrolls sideways instead.
  static const shared = 72.0;

  /// The row at its narrowest, as arithmetic over the widths above.
  static const minTable =
      PosSpace.s18 +
      refund +
      time +
      invoice +
      shared +
      PosSpace.sm +
      shared +
      PosSpace.sm +
      lines +
      PosSpace.sm +
      amount +
      PosSpace.md +
      shared +
      PosSpace.md;
}

class _RefundRow extends StatelessWidget {
  const _RefundRow({
    required this.refund,
    required this.selected,
    required this.onTap,
  });

  final RefundRecord refund;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    Widget words(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PosText.ui(size: 12.5, color: pos.body),
    );
    return HistoryListRow(
      selected: selected,
      onTap: onTap,
      children: [
        SizedBox(
          width: _Cols.refund,
          child: MonoCode('#${refund.id}', size: 12.5, color: pos.ink),
        ),
        SizedBox(
          width: _Cols.time,
          child: MonoCode(historyStamp(refund.occurredAt), size: 12),
        ),
        SizedBox(
          width: _Cols.invoice,
          child: MonoCode(refund.invoiceNumber, size: 12.5, color: pos.ink),
        ),
        Expanded(child: words(refund.refundedByName ?? '—')),
        const SizedBox(width: PosSpace.sm),
        Expanded(
          child: words(
            reasonInReaderLanguage(
                  context,
                  english: refund.reasonName,
                  arabic: refund.reasonNameAr,
                ) ??
                '—',
          ),
        ),
        const SizedBox(width: PosSpace.sm),
        SizedBox(
          width: _Cols.lines,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MonoCode('${refund.lineCount}', size: 12.5),
          ),
        ),
        const SizedBox(width: PosSpace.sm),
        SizedBox(
          width: _Cols.amount,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MonoAmount(
              refund.total,
              size: 13,
              weight: FontWeight.w600,
              color: pos.ink,
            ),
          ),
        ),
        const SizedBox(width: PosSpace.md),
        Expanded(child: words(refund.terminalName ?? '—')),
      ],
    );
  }
}
