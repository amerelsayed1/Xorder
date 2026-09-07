import 'dart:async';

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
import '../../../domain/models/order_record.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/repositories/repositories.dart';
import 'order_detail_pane.dart';
import 'order_status_chip.dart';

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

  /// Whole local days, ending at the end of today.
  ///
  /// Local rather than UTC for the same reason [OrderHistoryQuery.today] is: a
  /// day at a till in Cairo is the day the people standing at it are having.
  (DateTime, DateTime) window(DateTime now) {
    final endOfToday = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final days = switch (this) {
      HistoryRange.today => 1,
      HistoryRange.week => 7,
      HistoryRange.month => 30,
    };
    return (endOfToday.subtract(Duration(days: days)), endOfToday);
  }
}

/// Orders — the list of everything this branch has rung up.
///
/// A top-level destination, not a dialog over the sale screen. Looking up an
/// old order is a task somebody arrives at with a receipt in their hand, and
/// routing it means it is reachable without a live ticket to put at risk.
///
/// Read-only today. Reprint (A7) and refund (A5) attach to the detail pane,
/// which is why the pane exists in its own file rather than as a private widget
/// here — those two need somewhere to land.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key, required this.onClose});

  final VoidCallback onClose;

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
  String _searchTerm = '';
  int? _selectedId;

  Timer? _debounce;

  /// Fixed for the life of the screen.
  ///
  /// Taken once rather than read per rebuild: a clock read inside `build` makes
  /// every rebuild a different query, which turns a keystroke into a fresh
  /// database read and makes the family provider leak a cache entry per frame.
  late final DateTime _openedAt = DateTime.now();

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  OrderHistoryQuery get _query {
    final (from, to) = _range.window(_openedAt);
    return OrderHistoryQuery(
      from: from,
      to: to,
      statuses: _statuses,
      orderTypes: _types,
      servedByStaffId: _staffId,
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
      _searchTerm = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final orders = ref.watch(orderHistoryProvider(_query));

    return Scaffold(
      backgroundColor: context.pos.page,
      body: CallbackShortcuts(
        bindings: {
          // Escape leaves. On a read-only screen there is nothing to lose by
          // it, and a cashier who opened history mid-service wants out fast.
          const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
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
              _header(context, strings, orders.valueOrNull),
              _filters(context, strings),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _list(context, strings, orders)),
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
  ) {
    final pos = context.pos;
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
                Text(
                  strings.orderHistoryTitle,
                  style: PosText.screenTitle(color: pos.ink),
                ),
                const SizedBox(height: PosSpace.xs),
                Text(
                  orders == null
                      ? _range.label(strings)
                      : '${_range.label(strings)} · '
                            '${strings.orderHistoryCount(orders.length)}',
                  style: PosText.ui(size: 13.5, color: pos.muted),
                ),
              ],
            ),
          ),
          PosButton(
            label: strings.close,
            border: Border.fromBorderSide(pos.resting),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context, AppStrings strings) {
    final pos = context.pos;
    final staff = ref.watch(staffDirectoryProvider).valueOrNull ?? const [];

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
          if (staff.isNotEmpty) ...[
            _divider(pos),
            _StaffFilter(
              staff: staff,
              selectedId: _staffId,
              onChanged: (id) => setState(() => _staffId = id),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(PosPalette pos) =>
      Container(width: 1, height: PosSize.filterChip - 12, color: pos.line);

  Widget _list(
    BuildContext context,
    AppStrings strings,
    AsyncValue<List<OrderRecord>> orders,
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
      if (data.isEmpty) {
        return _message(
          context,
          _query.isFiltered
              ? strings.orderHistoryEmptyFiltered
              : strings.orderHistoryEmpty,
          action: _query.isFiltered
              ? (strings.orderHistoryClearFilters, _clearFilters)
              : null,
        );
      }
      return Column(
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
          if (data.length >= _query.limit)
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
                strings.orderHistoryTruncated(_query.limit),
                style: PosText.ui(size: 12.5, color: context.pos.warn),
              ),
            ),
        ],
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
        SizedBox(
          width: _Cols.total,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MicroLabel(strings.orderColumnTotal),
          ),
        ),
        const SizedBox(width: PosSpace.md),
        SizedBox(width: _Cols.status, child: MicroLabel(strings.orderColumnStatus)),
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
            ],
          ),
        ),
      ),
    );
  }

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

class _StaffFilter extends StatelessWidget {
  const _StaffFilter({
    required this.staff,
    required this.selectedId,
    required this.onChanged,
  });

  final List<PosStaff> staff;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Container(
      height: PosSize.filterChip,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(
          selectedId == null ? pos.resting : pos.accentBorder,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: selectedId,
          isDense: true,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.zero,
          style: PosText.ui(size: 12.5, color: pos.body),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(context.strings.orderHistoryEveryone),
            ),
            for (final person in staff)
              DropdownMenuItem(value: person.id, child: Text(person.name)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
