import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart' show businessDayProvider;
import '../../../app/shift_history_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/branch_sales.dart' show businessDayWire;
import '../../../domain/models/finance_report.dart';
import '../../../domain/models/sales_report.dart';
import '../../../domain/models/shift.dart';
import 'management_finance_panes.dart' show financePeriodLabel;

/// What People › Shifts and Finance › Settlements share: the dates, the three
/// filters, the table and the tiles.
///
/// **Their own copies of Finance's frame, table and tile, not Finance's.**
/// Those are private to `management_finance_panes.dart`, and making them
/// public meant editing a file another slice is restructuring around. The
/// shapes are the same — bordered surface, rows under a resting line, figures
/// mono and on the end side — so the two tabs still read as one product.

/// Enum-keyed, so a fourth state fails to compile here until it has its words
/// in both languages (`capability_labels_test.dart`).
String shiftStatusLabel(AppStrings s, ShiftStatus status) => switch (status) {
  ShiftStatus.open => s.shiftStatusOpen,
  ShiftStatus.closed => s.shiftStatusClosed,
  ShiftStatus.forceClosed => s.shiftStatusForceClosed,
};

/// Western digits in both languages, as the Finance and Activity panes print
/// their times.
String shiftStamp(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${businessDayWire(local)} ${two(local.hour)}:${two(local.minute)}';
}

/// The dates, the filters, and whatever the pane draws of the shifts found.
///
/// Holds the filters itself, so each pane keeps its own: choosing a till on
/// Shifts does not choose it on Settlements.
class ShiftHistoryFrame extends ConsumerStatefulWidget {
  const ShiftHistoryFrame({
    required this.paneKey,
    required this.blurb,
    required this.period,
    required this.statusChoices,
    required this.emptyText,
    required this.builder,
    this.listed = const {},
    super.key,
  });

  final String paneKey;
  final String blurb;

  /// Whose dates these are — Finance's, for a Finance pane.
  final StateProvider<FinancePeriod> period;

  /// What the status filter offers.
  final List<ShiftStatus> statusChoices;

  /// The states asked for while the status filter says "all". Empty is every
  /// state; Settlements asks for the counted ones only.
  final Set<ShiftStatus> listed;

  final String emptyText;

  final List<Widget> Function(BuildContext context, ShiftHistory history)
  builder;

  @override
  ConsumerState<ShiftHistoryFrame> createState() => _ShiftHistoryFrameState();
}

class _ShiftHistoryFrameState extends ConsumerState<ShiftHistoryFrame> {
  String? _terminal;
  int? _staff;
  ShiftStatus? _status;

  /// The last choices the database offered. Kept across a reload so the
  /// dropdowns do not empty and refill every time a filter moves.
  List<(String, String)> _tills = const [];
  List<(int, String)> _people = const [];

  @override
  Widget build(BuildContext context) {
    // New dates, new tills and people. A till chosen last month and absent
    // this week would otherwise be a filter the dropdown can no longer show
    // and the list is still applying — an empty list with no visible reason.
    ref.listen(widget.period, (_, _) {
      setState(() {
        _terminal = null;
        _staff = null;
      });
    });

    final day = ref.watch(businessDayProvider);
    // Nothing until the open day is known, for `_FinanceFrame`'s reason: a
    // range from the calendar and then from the day would ask twice and show
    // the wrong day's shifts in between.
    if (!day.hasValue && !day.hasError) {
      return SizedBox.expand(key: Key(widget.paneKey));
    }
    final now = day.valueOrNull?.date ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = financeFilter(
      ref.watch(widget.period),
      today: today,
      firstDayOfWeekIndex: MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );
    final query = ShiftHistoryQuery(
      from: range.from,
      to: range.to,
      terminalId: _terminal,
      staffId: _staff,
      statuses: switch (_status) {
        final chosen? => {chosen},
        null => widget.listed,
      },
    );
    final value = ref.watch(shiftHistoryProvider(query));
    if (value.valueOrNull case final history?) {
      _tills = history.tills;
      _people = history.staff;
    }

    final s = context.strings;
    return ListView(
      key: Key(widget.paneKey),
      padding: const EdgeInsets.all(PosSpace.s24),
      children: [
        Text(widget.blurb, style: PosText.ui(size: 13.5, color: context.pos.body)),
        const SizedBox(height: PosSpace.lg),
        _PeriodBar(period: widget.period, range: range, keyPrefix: widget.paneKey),
        const SizedBox(height: PosSpace.md),
        Wrap(
          spacing: PosSpace.sm,
          runSpacing: PosSpace.sm,
          children: [
            _Drop<String>(
              dropKey: Key('${widget.paneKey}-till'),
              everyone: s.shiftsAllTills,
              options: _tills,
              selected: _terminal,
              onChanged: (id) => setState(() => _terminal = id),
            ),
            _Drop<int>(
              dropKey: Key('${widget.paneKey}-cashier'),
              everyone: s.shiftsAllCashiers,
              options: _people,
              selected: _staff,
              onChanged: (id) => setState(() => _staff = id),
            ),
            _Drop<ShiftStatus>(
              dropKey: Key('${widget.paneKey}-status'),
              everyone: s.shiftsAllStatuses,
              options: [
                for (final status in widget.statusChoices)
                  (status, shiftStatusLabel(s, status)),
              ],
              selected: _status,
              onChanged: (status) => setState(() => _status = status),
            ),
          ],
        ),
        const SizedBox(height: PosSpace.s24),
        ...switch (value) {
          AsyncData(value: final history?) =>
            history.shifts.isEmpty
                ? [HistoryNote(widget.emptyText)]
                : widget.builder(context, history),
          // Null is the gate: no `reports.view` for the person acting.
          AsyncData() => [HistoryNote(s.shiftsNeedReports)],
          AsyncError() => [HistoryNote(s.financeUnavailable, danger: true)],
          _ => const [SizedBox(height: 120)],
        },
      ],
    );
  }
}

/// The four periods, and the business dates the chosen one covers.
///
/// Selection is a border, as everywhere in this design: ink and two pixels
/// for the chosen period, a resting line for the rest. No tint.
class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({
    required this.period,
    required this.range,
    required this.keyPrefix,
  });

  final StateProvider<FinancePeriod> period;
  final ReportFilter range;
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final s = context.strings;
    final chosen = ref.watch(period);
    final last = DateTime(range.to.year, range.to.month, range.to.day - 1);
    final dates = last == range.from
        ? businessDayWire(last)
        : '${businessDayWire(range.from)} → ${businessDayWire(last)}';
    return Row(
      children: [
        for (final option in FinancePeriod.values) ...[
          GestureDetector(
            key: Key('$keyPrefix-period-${option.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(period.notifier).state = option,
            child: Container(
              height: PosSize.filterChip,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
              decoration: BoxDecoration(
                color: pos.surface,
                border: Border.fromBorderSide(
                  option == chosen ? pos.emphasis : pos.resting,
                ),
              ),
              child: Text(
                financePeriodLabel(s, option),
                maxLines: 1,
                style: PosText.ui(
                  size: 13,
                  weight: option == chosen ? FontWeight.w700 : FontWeight.w500,
                  color: option == chosen ? pos.ink : pos.body,
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
          dates,
          key: Key('$keyPrefix-range'),
          size: 13,
          color: pos.ink,
        ),
      ],
    );
  }
}

/// One filter: "all", or one of [options]. The Users pane's role filter, for
/// any key — an accent border while it narrows the list, resting while not.
class _Drop<T extends Object> extends StatelessWidget {
  const _Drop({
    required this.dropKey,
    required this.everyone,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final Key dropKey;
  final String everyone;
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    // A choice no longer offered is shown as "all" rather than handed to the
    // dropdown, which asserts when its value is not among its items.
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
          key: dropKey,
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

typedef HistoryColumn = ({String label, int flex, bool numeric});

class HistoryRow {
  const HistoryRow(this.key, this.cells, {this.onTap});

  final Key key;
  final List<Widget> cells;

  /// The whole row is the target: a row is what a person points at, not a
  /// word inside it.
  final VoidCallback? onTap;
}

/// Rows of figures under a header.
///
/// Figures sit on the end side — the right in English, the left in Arabic —
/// and are mono and left to right inside that, so a column still aligns on
/// its decimal point when the page is mirrored. **Scaled down, never
/// wrapped**: eleven columns across 1100 px leave a six-figure drawer little
/// room, and a sum broken over two lines reads as two sums.
class HistoryTable extends StatelessWidget {
  const HistoryTable({required this.columns, required this.rows, super.key});

  final List<HistoryColumn> columns;
  final List<HistoryRow> rows;

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
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.md,
          vertical: PosSpace.xs,
        ),
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
                  child: column.numeric
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: cells[i],
                        )
                      : cells[i],
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
        ],
      ),
    );
  }
}

/// A KPI tile. A bordered surface, never a tinted one (`07-design-system.md`).
class HistoryTile extends StatelessWidget {
  const HistoryTile({
    required this.tileKey,
    required this.label,
    required this.value,
    super.key,
  });

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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: value,
        ),
      ],
    ),
  );
}

/// Equal-width tiles of equal height, with the design's gutter between.
class HistoryTileRow extends StatelessWidget {
  const HistoryTileRow({required this.children, super.key});

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

class HistoryNote extends StatelessWidget {
  const HistoryNote(this.text, {this.danger = false, super.key});

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

/// A name, one line, ellipsised: a column of people, not of paragraphs.
Widget historyText(BuildContext context, String text, {Color? color}) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: PosText.ui(size: 13, weight: FontWeight.w500, color: color ?? context.pos.ink),
);

/// A time, mono and left to right in either language.
Widget historyStamp(BuildContext context, DateTime at) =>
    MonoCode(shiftStamp(at), size: 12, color: context.pos.ink);

/// A dash for a figure that does not exist yet — an open drawer's count — so
/// it is not read as a count of nothing.
Widget historyNone(BuildContext context) =>
    Text('—', style: PosText.mono(size: 13, color: context.pos.muted));

/// Over or short, or the mask for somebody who may not see a drawer's
/// difference — see [ShiftHistoryFrame]'s callers.
Widget historyVariance(BuildContext context, Money? variance, {required bool masked}) =>
    switch (variance) {
      null => historyNone(context),
      final amount => MonoAmount(
        amount,
        weight: FontWeight.w600,
        masked: masked,
      ),
    };

/// The till a shift was on, by name; by id for a till whose row is gone.
Widget historyTill(BuildContext context, ShiftRecord record) =>
    switch (record.terminalName) {
      final name? => historyText(context, name),
      null => MonoCode(record.terminalId, size: 12, color: context.pos.ink),
    };
