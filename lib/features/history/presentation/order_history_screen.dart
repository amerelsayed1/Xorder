import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/business_day.dart';
import '../../../domain/models/order_record.dart';
import '../../../domain/models/ticket.dart';
import '../history_scope.dart';
import 'order_detail_pane.dart';
import 'order_status_chip.dart';
import 'payment_status_chip.dart';

/// How far back the list reaches.
///
/// Three fixed windows rather than a date picker. The question at a counter is
/// almost always "earlier today" and occasionally "last week"; a two-field date
/// range makes the common case slower to serve the rare one. An arbitrary range
/// belongs in Reports (Wave G), where somebody is sitting down.
enum HistoryRange { today, week, month }

extension on HistoryRange {
  String label(AppStrings s) => switch (this) {
    HistoryRange.today => s.orderHistoryToday,
    HistoryRange.week => s.orderHistoryLast7Days,
    HistoryRange.month => s.orderHistoryLast30Days,
  };

  /// Whole business dates, ending with [today]'s.
  ///
  /// [today] is the trading day, not the calendar one: at 1 a.m. with
  /// yesterday's business day still open, "Today" is yesterday's date, and the
  /// list shows the night that is still going rather than the hour since
  /// midnight. See [OrderHistoryQuery.from] for how a sale finds its date.
  (DateTime, DateTime) window(DateTime today) {
    final end = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 1));
    final days = switch (this) {
      HistoryRange.today => 1,
      HistoryRange.week => 7,
      HistoryRange.month => 30,
    };
    return (end.subtract(Duration(days: days)), end);
  }
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
class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key, this.onClose, this.openedAt});

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

  static const staffFilterKey = ValueKey('history-filter-staff');
  static const tenderFilterKey = ValueKey('history-filter-tender');
  static const terminalFilterKey = ValueKey('history-filter-terminal');
  static const attributionCaveatKey = ValueKey('history-attribution-caveat');
  static const ownSalesKey = ValueKey('history-own-sales');

  /// The sideways scroll the table falls back to when the list is narrower
  /// than its columns — at the window's minimum, and in the back office at
  /// its 1100 breakpoint.
  static const sidewaysKey = ValueKey('history-sideways');

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
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _sideways.dispose();
    super.dispose();
  }

  /// The business date "Today" means: the open day's, when one is open, and
  /// the calendar date otherwise — which is also the date a sale with no
  /// business day is filed under, so the fallback agrees with itself.
  DateTime _today(BusinessDay? day) {
    if (day != null && day.isOpen) return day.date;
    return DateTime(_openedAt.year, _openedAt.month, _openedAt.day);
  }

  OrderHistoryQuery _query(DateTime today) {
    final (from, to) = _range.window(today);
    return OrderHistoryQuery(
      from: from,
      to: to,
      statuses: _statuses,
      orderTypes: _types,
      servedByStaffId: _staffId,
      tenderTypeId: _tenderId,
      terminalId: _terminalId,
      search: _searchTerm.isEmpty ? null : _searchTerm,
    );
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
    final query = day.isLoading ? null : _query(_today(day.valueOrNull));
    final orders = query == null
        ? const AsyncValue<List<OrderRecord>>.loading()
        : ref.watch(orderHistoryProvider(query));

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
              _header(context, strings, orders.valueOrNull, seesEveryone),
              _filters(context, strings, seesEveryone),
              if (query?.from case final from?
                  when from.isBefore(OrderRecord.servedByReliableFrom))
                _attributionCaveat(context, strings),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _list(context, strings, orders, query)),
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
    List<OrderRecord>? orders,
    bool seesEveryone,
  ) {
    final pos = context.pos;
    final slice = [
      _range.label(strings),
      if (orders != null) strings.orderHistoryCount(orders.length),
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
          if (widget.onClose case final close?)
            PosButton(
              label: strings.close,
              border: Border.fromBorderSide(pos.resting),
              onPressed: close,
            ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context, AppStrings strings, bool seesEveryone) {
    final pos = context.pos;
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
            _FilterChip(
              label: range.label(strings),
              selected: _range == range,
              onTap: () => setState(() => _range = range),
            ),
          _divider(pos),
          SizedBox(
            width: 220,
            height: PosSize.filterChip,
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              style: PosText.mono(size: 13, color: pos.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: strings.orderHistorySearchHint,
                hintStyle: PosText.ui(size: 13, color: pos.muted),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: PosSpace.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: pos.resting,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: pos.resting,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: pos.accentBorder,
                ),
              ),
            ),
          ),
          _divider(pos),
          // Only the statuses a till actually writes. Listing all ten would
          // offer four filters that can never match anything until the KDS
          // lands, and a filter that always returns nothing teaches people the
          // list is broken.
          for (final status in const [
            OrderStatus.paid,
            OrderStatus.voided,
            OrderStatus.refunded,
            OrderStatus.partiallyRefunded,
          ])
            _FilterChip(
              label: status.label(strings),
              selected: _statuses.contains(status),
              onTap: () => setState(() {
                _statuses = _statuses.contains(status)
                    ? (Set.of(_statuses)..remove(status))
                    : (Set.of(_statuses)..add(status));
              }),
            ),
          _divider(pos),
          for (final type in ref.watch(branchOrderTypesProvider))
            _FilterChip(
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
            _divider(pos),
            _PickFilter<int>(
              key: OrderHistoryScreen.staffFilterKey,
              everyone: strings.orderHistoryEveryone,
              options: [for (final person in staff) (person.id, person.name)],
              selected: _staffId,
              onChanged: (id) => setState(() => _staffId = id),
            ),
          ],
          if (tenders.isNotEmpty)
            _PickFilter<int>(
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
            _PickFilter<String>(
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

  Widget _divider(PosPalette pos) =>
      Container(width: 1, height: PosSize.filterChip - 12, color: pos.line);

  Widget _list(
    BuildContext context,
    AppStrings strings,
    AsyncValue<List<OrderRecord>> orders,
    OrderHistoryQuery? query,
  ) => orders.when(
    loading: () =>
        Center(child: CircularProgressIndicator(color: context.pos.accent)),
    // The error itself, not a generic apology. "History could not be read" with
    // the reason underneath is what lets somebody tell a dead network apart
    // from a permissions problem without opening a log.
    error: (error, _) => _message(
      context,
      strings.orderHistoryUnavailable,
      detail: '$error',
    ),
    data: (data) {
      final filtered = query?.isFiltered ?? false;
      if (data.isEmpty) {
        return _message(
          context,
          filtered
              ? strings.orderHistoryEmptyFiltered
              : strings.orderHistoryEmpty,
          action: filtered
              ? (strings.orderHistoryClearFilters, _clearFilters)
              : null,
        );
      }
      final limit = query?.limit ?? const OrderHistoryQuery().limit;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _table(context, strings, data)),
          if (data.length >= limit)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: PosSpace.s18,
                vertical: PosSpace.sm,
              ),
              decoration: BoxDecoration(
                color: context.pos.warnSoft,
                border: BorderDirectional(top: context.pos.resting),
              ),
              child: Text(
                strings.orderHistoryTruncated(limit),
                style: PosText.ui(size: 12.5, color: context.pos.warn),
              ),
            ),
        ],
      );
    },
  );

  /// The headings and the rows, as one block that scrolls sideways when the
  /// list is too narrow for it rather than squeezing.
  ///
  /// At the window's minimum (1024, `main.dart`) the list beside the detail
  /// pane is about 600 wide and its fixed columns alone are wider: a Row that
  /// ran out of room, on `/orders` as much as in the back office. Rejected:
  /// dropping columns below a width. The column somebody needs is the one
  /// that was dropped, and a table whose columns come and go with the window
  /// is two tables to learn.
  Widget _table(
    BuildContext context,
    AppStrings strings,
    List<OrderRecord> data,
  ) => LayoutBuilder(
    builder: (context, box) {
      final width = math.max(box.maxWidth, _Cols.minTable);
      final table = SizedBox(
        width: width,
        height: box.maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _columnHeadings(context, strings),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final order = data[index];
                  return _OrderRow(
                    order: order,
                    selected: order.id == _selectedId,
                    onTap: () => setState(() => _selectedId = order.id),
                  );
                },
              ),
            ),
          ],
        ),
      );
      if (width <= box.maxWidth) return table;
      // A bar that is always drawn, because a desktop scroll view shows none
      // sideways of its own, and a table with columns past the edge and
      // nothing saying so reads as a table with fewer columns.
      return Scrollbar(
        controller: _sideways,
        thumbVisibility: true,
        radius: Radius.zero,
        child: SingleChildScrollView(
          key: OrderHistoryScreen.sidewaysKey,
          controller: _sideways,
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      );
    },
  );

  Widget _message(
    BuildContext context,
    String message, {
    String? detail,
    (String, VoidCallback)? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: PosText.ui(size: 14, color: context.pos.muted),
          ),
          if (detail != null) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: PosText.ui(size: 12.5, color: context.pos.muted),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: PosSpace.md),
            PosButton(
              label: action.$1,
              border: Border.fromBorderSide(context.pos.resting),
              onPressed: action.$2,
            ),
          ],
        ],
      ),
    ),
  );

  Widget _columnHeadings(BuildContext context, AppStrings strings) => Container(
    height: 28,
    padding: const EdgeInsetsDirectional.only(
      start: PosSpace.s18,
      end: PosSpace.md,
    ),
    decoration: BoxDecoration(
      border: BorderDirectional(
        top: context.pos.hairline,
        bottom: context.pos.hairline,
      ),
    ),
    child: Row(
      children: [
        SizedBox(width: _Cols.invoice, child: MicroLabel(strings.orderColumnInvoice)),
        SizedBox(width: _Cols.time, child: MicroLabel(strings.orderColumnTime)),
        SizedBox(width: _Cols.type, child: MicroLabel(strings.orderColumnType)),
        SizedBox(width: _Cols.table, child: MicroLabel(strings.orderColumnWhere)),
        Expanded(child: MicroLabel(strings.orderColumnStaff)),
        const SizedBox(width: PosSpace.sm),
        Expanded(child: MicroLabel(strings.orderColumnMethod)),
        const SizedBox(width: PosSpace.sm),
        Expanded(child: MicroLabel(strings.orderColumnTerminal)),
        const SizedBox(width: PosSpace.sm),
        SizedBox(
          width: _Cols.total,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MicroLabel(strings.orderColumnTotal),
          ),
        ),
        const SizedBox(width: PosSpace.md),
        SizedBox(width: _Cols.status, child: MicroLabel(strings.orderColumnStatus)),
        const SizedBox(width: PosSpace.sm),
        SizedBox(
          width: _Cols.payment,
          child: MicroLabel(strings.orderColumnPayment),
        ),
      ],
    ),
  );
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

  /// The least each of the three columns sharing what is left — who sold
  /// it, what it was paid with, which till — gets before the table scrolls
  /// sideways instead.
  static const shared = 72.0;

  /// The whole row at its narrowest: every fixed column, the shared three at
  /// [shared], and the padding and gaps between. Arithmetic over the widths
  /// above rather than a number, so widening one cannot leave this stale.
  static const minTable =
      PosSpace.s18 +
      invoice +
      time +
      type +
      table +
      3 * (shared + PosSpace.sm) +
      total +
      PosSpace.md +
      status +
      PosSpace.sm +
      payment +
      PosSpace.md;
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.selected,
    required this.onTap,
  });

  final OrderRecord order;
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

    return Material(
      color: selected ? pos.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: PosSize.reportRow,
          padding: const EdgeInsetsDirectional.only(
            start: PosSpace.s18,
            end: PosSpace.md,
          ),
          decoration: BoxDecoration(
            border: BorderDirectional(
              bottom: pos.hairline,
              start: selected
                  ? BorderSide(color: pos.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Row(
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
                child: MonoCode(_time(order.occurredAt), size: 12),
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
              Expanded(
                child: Text(
                  _methods(order, strings),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(size: 12.5, color: pos.body),
                ),
              ),
              const SizedBox(width: PosSpace.sm),
              Expanded(
                child: Text(
                  order.terminalName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(size: 12.5, color: pos.body),
                ),
              ),
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
        ),
      ),
    );
  }

  /// Every method, in the reader's language and the order they were taken —
  /// "Cash + Card" for a split bill. Through `tenderName`, so a method the
  /// restaurant renamed reads as they named it, as its receipt does.
  static String _methods(OrderRecord order, AppStrings strings) =>
      order.tenders.isEmpty
      ? '—'
      : order.tenders
            .map((t) => tenderName(t.tenderTypeId, t.label, strings))
            .join(' + ');

  /// 24-hour, zero-padded, mono. Not `TimeOfDay.format` — that follows the
  /// locale into 12-hour with an am/pm suffix, and a column of times that
  /// changes width row by row cannot be scanned.
  static String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Material(
      color: selected ? pos.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: PosSize.filterChip,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              selected ? pos.accentBorder : pos.resting,
            ),
          ),
          // A `Row` sized to its child, not `alignment: Alignment.center`. A
          // `Container` with an alignment expands to fill whatever it is given,
          // and inside a `Wrap` that is the full line width — every chip taking
          // a row of its own, and a filter bar 600px tall squeezing the list it
          // is meant to filter down to nothing. The first widget test written
          // against this screen caught it.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: PosText.ui(
                  size: 12.5,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? pos.inkWarm : pos.body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of several values, or all of them — the cashier, the payment method and
/// the till are the same control over different lists.
///
/// Generic rather than three near-copies: the staff picker was the only one
/// when it was written, and the second copy is where the borders of the three
/// would have started to disagree.
class _PickFilter<T extends Object> extends StatelessWidget {
  const _PickFilter({
    super.key,
    required this.everyone,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  /// The label for "no filter".
  final String everyone;
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    // A selection that is no longer offered — a till deleted while the screen
    // was open — is shown as "everyone" rather than handed to the dropdown,
    // which asserts when its value is not among its items.
    final value = options.any((option) => option.$1 == selected)
        ? selected
        : null;
    return Container(
      height: PosSize.filterChip,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(
          value == null ? pos.resting : pos.accentBorder,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isDense: true,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.zero,
          style: PosText.ui(size: 12.5, color: pos.body),
          items: [
            DropdownMenuItem<T?>(value: null, child: Text(everyone)),
            for (final (id, label) in options)
              DropdownMenuItem<T?>(value: id, child: Text(label)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
