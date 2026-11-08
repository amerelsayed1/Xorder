import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/excel_export.dart';
import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/order_record.dart';
import '../../../domain/models/ticket.dart';
import '../history_scope.dart';
import '../sales_export.dart';
import 'history_widgets.dart';
import 'order_detail_pane.dart';
import 'order_status_chip.dart';
import 'payment_status_chip.dart';

/// A sale to open Orders on, from somewhere that names one — Returns' "Open
/// the sale".
class SaleToOpen {
  const SaleToOpen({required this.orderId, required this.invoiceNumber});

  final int orderId;
  final String invoiceNumber;

  @override
  bool operator ==(Object other) =>
      other is SaleToOpen &&
      other.orderId == orderId &&
      other.invoiceNumber == invoiceNumber;

  @override
  int get hashCode => Object.hash(orderId, invoiceNumber);
}

/// Orders — the list of everything this branch has rung up.
///
/// A top-level destination, not a dialog over the sale screen. Looking up an
/// old order is a task somebody arrives at with a receipt in their hand, and
/// routing it means it is reachable without a live ticket to put at risk.
///
/// **Two statuses per row** (plan 17 §4): where the order is and where the
/// money is. They are separate columns, not one chip, because they answer
/// different people — the floor asks the first and the drawer the second.
///
/// **Whose sales** is decided by `HistoryScope` in the providers, not here.
/// This screen only mirrors it: it hides the cashier picker from somebody who
/// may not use it and says the list is theirs alone.
///
/// **Also Invoices and Cancelled orders** ([preset]): the same list with a
/// status filter locked on, not two more screens.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({
    super.key,
    this.onClose,
    this.openedAt,
    this.preset = HistoryPreset.all,
    this.openSale,
  });

  /// The way out, from `/orders`.
  ///
  /// **Null inside the back office**, where this is the Sales tab (BO-2): the
  /// same widget rather than a second screen over the same data, which is how
  /// two lists that were meant to agree stop agreeing. There the back office
  /// owns leaving — its Exit, and its Esc that leaves a field first — so this
  /// draws no Close, binds no Esc and drops its own title under the back
  /// office's header. Whose sales it lists is the same rule either way.
  final VoidCallback? onClose;

  /// The clock, for a test that has to be about a particular date — the
  /// attribution caveat depends on how far the window reaches back, and a test
  /// that read the real clock would change its answer next week.
  @visibleForTesting
  final DateTime? openedAt;

  /// Which of Sales' lists this is: every sale (Orders, and `/orders`),
  /// Invoices, or Cancelled orders.
  ///
  /// A preset's statuses replace the status chips rather than sitting beside
  /// them — a "Voided" chip on the Invoices list could only ever empty it —
  /// and Cancelled orders swaps the money columns for who voided the sale,
  /// when and why. The window, the scope, the pages and the strip's SQL are
  /// the list's own under every preset.
  final HistoryPreset preset;

  /// A sale to open on: its invoice in the search, the widest window, and
  /// the sale itself in the detail pane — which reads it by id, so it shows
  /// even when it is older than the window reaches.
  ///
  /// Read once, when the screen is built. To open a second sale, give the
  /// screen a new key.
  final SaleToOpen? openSale;

  static const staffFilterKey = ValueKey('history-filter-staff');
  static const tenderFilterKey = ValueKey('history-filter-tender');
  static const terminalFilterKey = ValueKey('history-filter-terminal');
  static const attributionCaveatKey = ValueKey('history-attribution-caveat');
  static const ownSalesKey = ValueKey('history-own-sales');

  /// The sideways scroll the table falls back to when the list is narrower
  /// than its columns — at the window's minimum, and in the back office at
  /// its 1100 breakpoint.
  static const sidewaysKey = ValueKey('history-sideways');

  // The strip's four figures and the pager (BO-3).
  static const summaryTotalKey = ValueKey('history-summary-total');
  static const summaryCountKey = ValueKey('history-summary-count');
  static const summaryPaidKey = ValueKey('history-summary-paid');
  static const summaryOutstandingKey = ValueKey('history-summary-outstanding');

  /// Cancelled orders' second figure: what the voided sales came to.
  static const summaryVoidedKey = ValueKey('history-summary-voided');
  static const pagerKey = HistoryPager.barKey;
  static const pagerRangeKey = HistoryPager.rangeKey;
  static const pagerTotalKey = HistoryPager.totalKey;
  static const pagerPageKey = HistoryPager.pageKey;
  static const previousPageKey = HistoryPager.previousKey;
  static const nextPageKey = HistoryPager.nextKey;

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  HistoryRange _range = HistoryRange.today;
  Set<OrderStatus> _statuses = const {};
  Set<OrderType> _types = const {};
  int? _staffId;
  int? _tenderId;
  String? _terminalId;
  String _searchTerm = '';
  int? _selectedId;

  /// The pages turned so far: the last row id of each page before this one,
  /// oldest first. Empty is page one; Previous drops the last.
  ///
  /// A stack rather than a page number, because a keyset page has no number
  /// the database can seek to — only "after this row". Walking back means
  /// asking for the page after the cursor before, which is the page that was
  /// on screen.
  List<int> _cursors = const [];

  /// The filter [_cursors] were turned under. See `build`.
  OrderHistoryQuery? _pagedFor;

  Timer? _debounce;

  /// Sideways, for [_table] when the list is narrower than its columns.
  final _sideways = ScrollController();

  /// Fixed for the life of the screen.
  ///
  /// Taken once rather than read per rebuild: a clock read inside `build` makes
  /// every rebuild a different query, which turns a keystroke into a fresh
  /// database read and makes the family provider leak a cache entry per frame.
  late final DateTime _openedAt = widget.openedAt ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.openSale case final sale?) {
      // Month, the widest window: a refund is usually days after its sale,
      // and a sale the window does not reach is still open in the pane.
      _range = HistoryRange.month;
      _search.text = sale.invoiceNumber;
      _searchTerm = sale.invoiceNumber;
      _selectedId = sale.orderId;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _sideways.dispose();
    super.dispose();
  }

  /// Which columns and figures to draw. A locked [HistoryPreset] decides; with
  /// none, the list takes the Cancelled-orders layout exactly when Voided is the
  /// only status chosen — every row is then a void, and the money columns would
  /// be a column of nothing taken. Every other choice is the plain list.
  HistoryPreset get _layout => widget.preset != HistoryPreset.all
      ? widget.preset
      : (_statuses.length == 1 && _statuses.contains(OrderStatus.voided))
      ? HistoryPreset.voided
      : HistoryPreset.all;

  OrderHistoryQuery _query(DateTime today) {
    final (from, to) = _range.window(today);
    return widget.preset.apply(
      OrderHistoryQuery(
        from: from,
        to: to,
        statuses: _statuses,
        orderTypes: _types,
        servedByStaffId: _staffId,
        tenderTypeId: _tenderId,
        terminalId: _terminalId,
        search: _searchTerm.isEmpty ? null : _searchTerm,
      ),
    );
  }

  /// Whether the person narrowed [query]. A preset's statuses are not theirs
  /// to clear, so a list that is only its preset is not "filtered" and is not
  /// offered a Clear that would change nothing.
  bool _filtered(OrderHistoryQuery? query) {
    if (query == null) return false;
    return widget.preset.statuses == null
        ? query.isFiltered
        : query.copyWith(statuses: const {}).isFiltered;
  }

  void _onSearchChanged(String value) {
    // Debounced, because every keystroke is otherwise a query against a table
    // holding every sale the branch has ever made.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchTerm = value.trim());
    });
  }

  void _clearFilters() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _statuses = const {};
      _types = const {};
      _staffId = null;
      _tenderId = null;
      _terminalId = null;
      _searchTerm = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final day = ref.watch(businessDayProvider);
    // The person acting, as the providers scope it — in the back office the
    // one who came through Admin Mode's door. See `actingStaffProvider`.
    final seesEveryone = HistoryScope.seesEveryone(
      ref.watch(actingStaffProvider),
    );
    final onClose = widget.onClose;

    // The list waits for the business day rather than asking once with the
    // calendar date and again when the day arrives — two reads, and a list
    // that visibly changes its mind about what "today" is. A day that cannot
    // be read falls back to the calendar, which is what "today" meant before
    // there were business days at all.
    final base = day.isLoading
        ? null
        : _query(historyToday(day.valueOrNull, _openedAt));
    // Pages belong to the filter they were turned under. Compared here rather
    // than reset in each handler that changes a filter: there are eight of
    // them, a business day opening changes "today" through none, and the one
    // that forgot would open a new filter on page three of the old one.
    final cursors = base != null && base == _pagedFor
        ? _cursors
        : const <int>[];
    final query = cursors.isEmpty
        ? base
        : base!.copyWith(afterOrderId: cursors.last);
    final orders = query == null
        ? const AsyncValue<List<OrderRecord>>.loading()
        : ref.watch(orderHistoryProvider(query));
    // Keyed by the first page's query, so Next re-reads the rows and not the
    // totals.
    final summary = base == null
        ? const AsyncValue<OrderHistorySummary>.loading()
        : ref.watch(orderHistorySummaryProvider(base));

    return Scaffold(
      backgroundColor: context.pos.page,
      body: CallbackShortcuts(
        bindings: {
          // Escape leaves. On a read-only screen there is nothing to lose by
          // it, and a cashier who opened history mid-service wants out fast.
          // Unbound in the back office, so its own Esc is heard — the one
          // that leaves a field first and the back office second.
          const SingleActivator(LogicalKeyboardKey.escape): ?onClose,
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
              _header(
                context,
                strings,
                summary.valueOrNull?.count,
                seesEveryone,
                base,
              ),
              _filters(context, strings, seesEveryone),
              if (query?.from case final from?
                  when from.isBefore(OrderRecord.servedByReliableFrom))
                _attributionCaveat(context, strings),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Over the list, not across the window. Full width was
                    // tried first and took its height from the detail pane
                    // too, which is where the refund button and a sale's
                    // activity live; the activity test caught its last row
                    // gone below the fold. The strip is about the list, so it
                    // costs the list.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SummaryStrip(summary: summary, preset: _layout),
                          Expanded(
                            child: _list(
                              context,
                              strings,
                              orders,
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
                        color: context.pos.surface,
                        border: BorderDirectional(start: context.pos.resting),
                      ),
                      child: OrderDetailPane(orderId: _selectedId),
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
    OrderHistoryQuery? base,
  ) {
    final pos = context.pos;
    // Every page's count, not this page's: "Today · 50 orders" on a day of
    // two hundred is the list telling somebody the rest do not exist.
    final slice = [
      _range.label(strings),
      if (count != null) strings.orderHistoryCount(count),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PosSpace.s18,
        PosSpace.xl,
        PosSpace.s18,
        PosSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Not in the back office, whose header already names the
                // page — two titles stacked read as two screens.
                if (widget.onClose != null) ...[
                  Text(
                    strings.orderHistoryTitle,
                    style: PosText.screenTitle(color: pos.ink),
                  ),
                  const SizedBox(height: PosSpace.xs),
                ],
                Row(
                  children: [
                    Text(slice, style: PosText.ui(size: 13.5, color: pos.muted)),
                    // Said, not only enforced. A cashier who sees four orders
                    // on a busy night and is not told why concludes the
                    // system lost the rest.
                    if (!seesEveryone)
                      Text(
                        ' · ${strings.orderHistoryOwnSalesOnly}',
                        key: OrderHistoryScreen.ownSalesKey,
                        style: PosText.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: pos.inkWarm,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // BO-11: every page of the filter above, not the one in view, and
          // the strip's figures under them — see `sales_export.dart`. Read
          // through the list's own road and scope, as the person acting.
          // Not wrapped in a `Flexible`: beside the title's `Expanded` it took
          // half of what was left, and the button sat in the middle of the
          // header instead of at its end. The title shrinks first if the room
          // runs out; the button keeps its size and its edge.
          if (base != null)
            ExcelExportButton(
              fileName: salesFileName(base),
              build: (strings, rightToLeft) async => salesWorkbook(
                rows: await ordersToExport(
                  ref.read(orderHistoryRepositoryProvider),
                  base,
                  viewer: ref.read(actingStaffProvider),
                ),
                query: base,
                strings: strings,
                rightToLeft: rightToLeft,
              ),
            ),
          if (widget.onClose case final close?) ...[
            const SizedBox(width: PosSpace.sm),
            PosButton(
              label: strings.close,
              border: Border.fromBorderSide(pos.resting),
              onPressed: close,
            ),
          ],
        ],
      ),
    );
  }

  Widget _filters(BuildContext context, AppStrings strings, bool seesEveryone) {
    final staff = ref.watch(staffDirectoryProvider).valueOrNull ?? const [];
    // Every method the restaurant has ever had, retired ones included: a sale
    // paid with a voucher scheme that ended in June is still a sale somebody
    // may need to find by it.
    final tenders = ref.watch(tenderTypesAllProvider).valueOrNull ?? const [];
    final terminals =
        ref.watch(historyTerminalsProvider).valueOrNull ?? const [];

    return Container(
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
            hint: strings.orderHistorySearchHint,
          ),
          // Only the statuses a till actually writes. Listing all ten would
          // offer four filters that can never match anything until the KDS
          // lands, and a filter that always returns nothing teaches people the
          // list is broken. None under a preset, whose statuses are locked.
          if (widget.preset.statuses == null) ...[
            const HistoryFilterDivider(),
            for (final status in const [
              OrderStatus.paid,
              OrderStatus.voided,
              OrderStatus.refunded,
              OrderStatus.partiallyRefunded,
            ])
              HistoryFilterChip(
                label: status.label(strings),
                selected: _statuses.contains(status),
                onTap: () => setState(() {
                  _statuses = _statuses.contains(status)
                      ? (Set.of(_statuses)..remove(status))
                      : (Set.of(_statuses)..add(status));
                }),
              ),
          ],
          const HistoryFilterDivider(),
          for (final type in ref.watch(branchOrderTypesProvider))
            HistoryFilterChip(
              label: type.label(strings),
              selected: _types.contains(type),
              onTap: () => setState(() {
                _types = _types.contains(type)
                    ? (Set.of(_types)..remove(type))
                    : (Set.of(_types)..add(type));
              }),
            ),
          // Not drawn for somebody who only sees their own sales. The provider
          // would overrule it anyway; a picker that changes nothing is a
          // control that lies.
          if (seesEveryone && staff.isNotEmpty) ...[
            const HistoryFilterDivider(),
            FilterDropdown<int>(
              key: OrderHistoryScreen.staffFilterKey,
              everyone: strings.orderHistoryEveryone,
              options: [for (final person in staff) (person.id, person.name)],
              selected: _staffId,
              onChanged: (id) => setState(() => _staffId = id),
            ),
          ],
          if (tenders.isNotEmpty)
            FilterDropdown<int>(
              key: OrderHistoryScreen.tenderFilterKey,
              everyone: strings.orderHistoryEveryMethod,
              options: [
                for (final tender in tenders) (tender.id, tender.label(strings)),
              ],
              selected: _tenderId,
              onChanged: (id) => setState(() => _tenderId = id),
            ),
          // Only with a second till to tell apart. A branch with one terminal
          // would get a picker whose every answer is the same list.
          if (terminals.length > 1)
            FilterDropdown<String>(
              key: OrderHistoryScreen.terminalFilterKey,
              everyone: strings.orderHistoryEveryTerminal,
              options: [
                for (final till in terminals) (till.id, till.name ?? till.id),
              ],
              selected: _terminalId,
              onChanged: (id) => setState(() => _terminalId = id),
            ),
        ],
      ),
    );
  }

  /// Said whenever the window reaches back before `served_by` could be
  /// trusted — the staff column is on screen for every range, so the caveat
  /// is about what is being shown, not about whether a filter is set.
  ///
  /// It retires itself: thirty days after the fix, no window reaches that far.
  Widget _attributionCaveat(BuildContext context, AppStrings strings) {
    final pos = context.pos;
    final from = OrderRecord.servedByReliableFrom;
    final date =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')}';
    return Container(
      key: OrderHistoryScreen.attributionCaveatKey,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        PosSpace.s18,
        0,
        PosSpace.s18,
        PosSpace.md,
      ),
      padding: const EdgeInsets.all(PosSpace.sm),
      decoration: BoxDecoration(
        color: pos.warnSoft,
        border: BorderDirectional(start: BorderSide(color: pos.warn, width: 2)),
      ),
      child: Text(
        strings.orderHistoryAttributionCaveat(date),
        style: PosText.ui(size: 12.5, color: pos.body),
      ),
    );
  }

  /// Turns to the page after [cursors]' last, under [base]'s filter.
  void _turn(OrderHistoryQuery base, List<int> cursors) => setState(() {
    _pagedFor = base;
    _cursors = cursors;
  });

  Widget _list(
    BuildContext context,
    AppStrings strings,
    AsyncValue<List<OrderRecord>> orders,
    OrderHistoryQuery? query,
    List<int> cursors,
    OrderHistorySummary? summary,
  ) => orders.when(
    loading: () =>
        Center(child: CircularProgressIndicator(color: context.pos.accent)),
    error: (error, _) => HistoryMessage(
      message: strings.orderHistoryUnavailable,
      detail: '$error',
    ),
    data: (data) {
      final filtered = _filtered(query);
      // Empty on page one is an empty filter. Past it, the rows ahead went
      // away while somebody read — a day's sales voided, say — and the pager
      // stays, because it is the way back.
      if (data.isEmpty && cursors.isEmpty) {
        return HistoryMessage(
          message: filtered
              ? strings.orderHistoryEmptyFiltered
              : switch (_layout) {
                  HistoryPreset.all ||
                  HistoryPreset.invoices => strings.orderHistoryEmpty,
                  HistoryPreset.voided => strings.voidedOrdersEmpty,
                },
          action: filtered
              ? (strings.orderHistoryClearFilters, _clearFilters)
              : null,
        );
      }
      final base = query?.unpaged;
      final limit = query?.limit ?? OrderHistoryQuery.pageSize;
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
          Expanded(child: _table(context, strings, data, query?.afterOrderId)),
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

  /// [page] keys the rows, so a page turned to opens at its top rather than
  /// scrolled as far down as the page before it was.
  Widget _table(
    BuildContext context,
    AppStrings strings,
    List<OrderRecord> data,
    int? page,
  ) => HistoryTable(
    minWidth: _Cols.minFor(_layout),
    sideways: _sideways,
    sidewaysKey: OrderHistoryScreen.sidewaysKey,
    headings: _columnHeadings(strings),
    rows: ListView.builder(
      key: ValueKey(('history-rows', page)),
      padding: EdgeInsets.zero,
      itemCount: data.length,
      itemBuilder: (context, index) {
        final order = data[index];
        return _OrderRow(
          order: order,
          preset: _layout,
          selected: order.id == _selectedId,
          onTap: () => setState(() => _selectedId = order.id),
        );
      },
    ),
  );

  Widget _columnHeadings(AppStrings strings) {
    // The two shared columns after the seller, and what follows the total.
    // Over the preset, so a fourth list is a compile error here rather than a
    // table whose headings stand over the wrong columns.
    final (second, third, tail) = switch (_layout) {
      HistoryPreset.all || HistoryPreset.invoices => (
        strings.orderColumnMethod,
        strings.orderColumnTerminal,
        <Widget>[
          SizedBox(
            width: _Cols.status,
            child: MicroLabel(strings.orderColumnStatus),
          ),
          const SizedBox(width: PosSpace.sm),
          SizedBox(
            width: _Cols.payment,
            child: MicroLabel(strings.orderColumnPayment),
          ),
        ],
      ),
      HistoryPreset.voided => (
        strings.orderColumnVoidReason,
        strings.orderColumnVoidedBy,
        <Widget>[
          SizedBox(
            width: _Cols.voidedAt,
            child: MicroLabel(strings.orderColumnVoidedAt),
          ),
        ],
      ),
    };
    return HistoryHeadings(
      children: [
        SizedBox(width: _Cols.invoice, child: MicroLabel(strings.orderColumnInvoice)),
        SizedBox(width: _Cols.time, child: MicroLabel(strings.orderColumnTime)),
        SizedBox(width: _Cols.type, child: MicroLabel(strings.orderColumnType)),
        SizedBox(width: _Cols.table, child: MicroLabel(strings.orderColumnWhere)),
        Expanded(child: MicroLabel(strings.orderColumnStaff)),
        const SizedBox(width: PosSpace.sm),
        Expanded(child: MicroLabel(second)),
        const SizedBox(width: PosSpace.sm),
        Expanded(child: MicroLabel(third)),
        // Who the sale was for. Not on Cancelled orders, whose three shared
        // columns are who voided it, when and why — a customer there would
        // squeeze the reason, which is what that list is read for.
        if (_Cols.hasCustomer(_layout)) ...[
          const SizedBox(width: PosSpace.sm),
          Expanded(child: MicroLabel(strings.customersColumnCustomer)),
        ],
        const SizedBox(width: PosSpace.sm),
        SizedBox(
          width: _Cols.total,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MicroLabel(strings.orderColumnTotal),
          ),
        ),
        const SizedBox(width: PosSpace.md),
        ...tail,
      ],
    );
  }
}

/// Column widths, in one place so the headings and the rows cannot drift.
abstract final class _Cols {
  static const invoice = 132.0;
  static const time = 64.0;
  static const type = 96.0;
  static const table = 88.0;
  static const total = 104.0;
  static const status = 104.0;

  /// Wide enough for PART REFUNDED in mono without an ellipsis.
  static const payment = 112.0;

  /// `2026-09-14 13:05` in 12 px mono.
  static const voidedAt = 124.0;

  /// The least each of the three columns sharing what is left — who sold
  /// it, what it was paid with, which till — gets before the table scrolls
  /// sideways instead.
  static const shared = 72.0;

  /// Everything up to and including the total, which every preset draws.
  static const _common =
      PosSpace.s18 +
      invoice +
      time +
      type +
      table +
      3 * (shared + PosSpace.sm) +
      total +
      PosSpace.md;

  /// The whole row at its narrowest: every fixed column, the shared three at
  /// [shared], and the padding and gaps between. Arithmetic over the widths
  /// above rather than a number, so widening one cannot leave this stale.
  static const minTable =
      _common +
      (shared + PosSpace.sm) +
      status +
      PosSpace.sm +
      payment +
      PosSpace.md;

  /// Whether a list draws the Customer column — every list but Cancelled
  /// orders. The fourth of the columns that share what is left, so the table's
  /// minimum grows by one [shared] and a gap.
  static bool hasCustomer(HistoryPreset preset) => switch (preset) {
    HistoryPreset.all || HistoryPreset.invoices => true,
    HistoryPreset.voided => false,
  };

  static const minVoided = _common + voidedAt + PosSpace.md;

  static double minFor(HistoryPreset preset) => switch (preset) {
    HistoryPreset.all || HistoryPreset.invoices => minTable,
    HistoryPreset.voided => minVoided,
  };
}

/// The figures over every page (BO-3): total sales, invoices, paid and
/// outstanding — or, for Cancelled orders, how many were voided and what
/// they came to.
///
/// Cancelled orders has two figures rather than the four with zeros in: every
/// row there is struck through, so "Total sales" and "Paid" would read 0.00
/// over a list of voids, which is true and says nothing.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, required this.preset});

  final AsyncValue<OrderHistorySummary> summary;
  final HistoryPreset preset;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final figures = summary.valueOrNull;

    Widget amount(Key key, Money Function(OrderHistorySummary) of) =>
        switch (figures) {
          final known? => MonoAmount(
            of(known),
            key: key,
            size: 20,
            weight: FontWeight.w600,
            // Owed money in the warning colour, on the figure and never the
            // tile, and only when there is some: a zero is not a warning.
            color: key == OrderHistoryScreen.summaryOutstandingKey &&
                    of(known).minor > 0
                ? pos.warn
                : pos.ink,
          ),
          null => HistorySummaryTile.dash(pos, key),
        };

    final count = figures == null
        ? HistorySummaryTile.dash(pos, OrderHistoryScreen.summaryCountKey)
        : HistorySummaryTile.count(
            pos,
            OrderHistoryScreen.summaryCountKey,
            figures.count,
          );

    final tiles = switch (preset) {
      HistoryPreset.all || HistoryPreset.invoices => [
        HistorySummaryTile(
          label: strings.orderSummaryTotal,
          value: amount(OrderHistoryScreen.summaryTotalKey, (s) => s.total),
          note: strings.orderSummaryTotalNote,
        ),
        HistorySummaryTile(
          label: strings.orderSummaryCount,
          value: count,
          // The count is every row, struck-through ones too, because it
          // is what the pager counts. Said, when there are any, or it
          // reads as disagreeing with the total beside it.
          note: figures != null && figures.dead > 0
              ? strings.orderSummaryCountDead(figures.dead)
              : null,
        ),
        HistorySummaryTile(
          label: strings.orderSummaryPaid,
          value: amount(OrderHistoryScreen.summaryPaidKey, (s) => s.paid),
          note: strings.orderSummaryPaidNote,
        ),
        HistorySummaryTile(
          label: strings.orderSummaryOutstanding,
          value: amount(
            OrderHistoryScreen.summaryOutstandingKey,
            (s) => s.outstanding,
          ),
          note: strings.orderSummaryOutstandingNote,
        ),
      ],
      HistoryPreset.voided => [
        HistorySummaryTile(label: strings.voidedSummaryCount, value: count),
        HistorySummaryTile(
          label: strings.voidedSummaryTotal,
          value: amount(
            OrderHistoryScreen.summaryVoidedKey,
            (s) => s.deadTotal,
          ),
          note: strings.voidedSummaryTotalNote,
        ),
      ],
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PosSpace.s18,
        0,
        PosSpace.s18,
        PosSpace.md,
      ),
      child: Row(
        children: [
          for (final (index, tile) in tiles.indexed) ...[
            if (index > 0) const SizedBox(width: PosSpace.sm),
            Expanded(child: tile),
          ],
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final OrderRecord order;
  final HistoryPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;

    // A voided order is struck through rather than merely tinted. The colour
    // says "look at this"; the strike says "this is not money" — and on a list
    // being scanned for a total, that second statement is the one that matters.
    final dead = order.status.isDead;

    Widget words(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PosText.ui(size: 12.5, color: pos.body),
    );

    final (second, third, tail) = switch (preset) {
      HistoryPreset.all || HistoryPreset.invoices => (
        words(paidWith(order, strings)),
        words(order.terminalName ?? '—'),
        <Widget>[
          SizedBox(
            width: _Cols.status,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OrderStatusChip(order.status),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          SizedBox(
            width: _Cols.payment,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: PaymentStatusChip(order.paymentStatus),
            ),
          ),
        ],
      ),
      HistoryPreset.voided => (
        words(
          reasonInReaderLanguage(
                context,
                english: order.voidReason,
                arabic: order.voidReasonAr,
              ) ??
              '—',
        ),
        words(order.voidedByName ?? '—'),
        <Widget>[
          SizedBox(
            width: _Cols.voidedAt,
            child: MonoCode(
              switch (order.voidedAt) {
                final at? => historyStamp(at),
                null => '—',
              },
              size: 12,
            ),
          ),
        ],
      ),
    };

    return HistoryListRow(
      selected: selected,
      onTap: onTap,
      children: [
        SizedBox(
          width: _Cols.invoice,
          child: MonoCode(
            order.invoiceNumber,
            size: 12.5,
            color: dead ? pos.muted : pos.ink,
          ),
        ),
        SizedBox(
          width: _Cols.time,
          child: MonoCode(historyTime(order.occurredAt), size: 12),
        ),
        SizedBox(
          width: _Cols.type,
          child: Text(
            order.orderType.label(strings),
            overflow: TextOverflow.ellipsis,
            style: PosText.ui(size: 12.5, color: pos.body),
          ),
        ),
        SizedBox(
          width: _Cols.table,
          child: Text(
            order.tableLabel ?? '—',
            overflow: TextOverflow.ellipsis,
            style: PosText.ui(size: 12.5, color: pos.body),
          ),
        ),
        Expanded(
          child: Text(
            order.servedByName ?? '—',
            overflow: TextOverflow.ellipsis,
            style: PosText.ui(size: 12.5, color: pos.body),
          ),
        ),
        const SizedBox(width: PosSpace.sm),
        Expanded(child: second),
        const SizedBox(width: PosSpace.sm),
        Expanded(child: third),
        if (_Cols.hasCustomer(preset)) ...[
          const SizedBox(width: PosSpace.sm),
          Expanded(
            child: Text(
              order.customerName ?? '—',
              key: Key('history-customer-${order.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PosText.ui(
                size: 12.5,
                color: order.hasCustomer ? pos.body : pos.muted,
              ),
            ),
          ),
        ],
        const SizedBox(width: PosSpace.sm),
        SizedBox(
          width: _Cols.total,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DefaultTextStyle.merge(
              style: TextStyle(
                decoration: dead ? TextDecoration.lineThrough : null,
                decorationColor: pos.danger,
              ),
              child: MonoAmount(
                order.total,
                size: 13,
                weight: FontWeight.w600,
                color: dead ? pos.muted : pos.ink,
              ),
            ),
          ),
        ),
        const SizedBox(width: PosSpace.md),
        ...tail,
      ],
    );
  }
}

