import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_module/app/providers.dart' show businessDayProvider;
import 'package:shared_module/app/waiter_shift_providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/mono_amount.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/domain/models/finance_report.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart' show PosStaff;
import 'package:shared_module/domain/models/waiter_shift.dart';
import 'shift_history_bits.dart';

/// People › Waiter shifts (الأفراد › ورديات النُدُل): when each waiter clocked
/// in and out on the XOrder Waiter handheld over the chosen dates, open shifts
/// on top, and each waiter's hours for the period under them.
///
/// **Read-only, on purpose.** The handheld is the clock; a forgotten clock-out
/// is corrected by the waiter finishing the shift, not by a manager typing a
/// time in here. A back office that could rewrite hours would make this page
/// a record of what the manager said rather than of what the clock saw.
///
/// **Not [ShiftHistoryFrame].** That frame is shaped round the cashier's
/// `ShiftHistory` — till, cashier and drawer-status filters and a Z report per
/// row — none of which a waiter shift has. It takes the frame's period chips
/// ([HistoryPeriodBar]) and table, so the two People pages read as one product.
class ManagementWaiterShiftsPane extends ConsumerWidget {
  const ManagementWaiterShiftsPane({required this.admin, super.key});

  /// The person in Admin Mode.
  final PosStaff admin;

  /// What the shell asks before it offers this pane: People › Shifts' gate,
  /// for the reason `waiterShiftsProvider` gives. The provider asks again, so
  /// a pane reached round the shell still draws nothing.
  static const requires = {PosCapability.reportsView};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const paneKey = 'waiter-shifts';
    final day = ref.watch(businessDayProvider);
    // Nothing until the open day is known, for ShiftHistoryFrame's reason: a
    // range from the calendar and then from the day would read twice and show
    // the wrong day's shifts in between.
    if (!day.hasValue && !day.hasError) {
      return const SizedBox.expand(key: Key(paneKey));
    }
    final now = day.valueOrNull?.date ?? DateTime.now();
    final range = financeFilter(
      ref.watch(waiterShiftsPeriodProvider),
      today: DateTime(now.year, now.month, now.day),
      firstDayOfWeekIndex: MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );
    final value = ref.watch(
      waiterShiftsProvider((from: range.from, to: range.to)),
    );

    final s = context.strings;
    return ListView(
      key: const Key(paneKey),
      padding: const EdgeInsets.all(PosSpace.s24),
      children: [
        Text(
          s.waiterShiftsBlurb,
          style: PosText.ui(size: 13.5, color: context.pos.body),
        ),
        const SizedBox(height: PosSpace.lg),
        HistoryPeriodBar(
          period: waiterShiftsPeriodProvider,
          range: range,
          keyPrefix: paneKey,
        ),
        const SizedBox(height: PosSpace.s24),
        ...switch (value) {
          AsyncData(value: final history?) =>
            history.shifts.isEmpty
                ? [HistoryNote(s.waiterShiftsNone)]
                : _body(context, history),
          // Null is the gate: no `reports.view` for the person acting.
          AsyncData() => [HistoryNote(s.waiterShiftsNeedReports)],
          AsyncError() => [HistoryNote(s.financeUnavailable, danger: true)],
          _ => const [SizedBox(height: 120)],
        },
      ],
    );
  }

  List<Widget> _body(BuildContext context, WaiterShiftHistory history) {
    final s = context.strings;
    final pos = context.pos;
    return [
      HistoryTable(
        columns: [
          (label: s.waiterShiftsWaiter, flex: 3, numeric: false),
          (label: s.waiterShiftsStarted, flex: 3, numeric: false),
          (label: s.waiterShiftsFinished, flex: 3, numeric: false),
          (label: s.waiterShiftsLength, flex: 2, numeric: true),
          (label: s.waiterShiftsHandheld, flex: 3, numeric: false),
        ],
        rows: [
          for (final shift in history.shifts)
            HistoryRow(Key('waiter-shifts-row-${shift.id}'), [
              historyText(context, _name(shift)),
              historyStamp(context, shift.startedAt),
              switch (shift.endedAt) {
                final ended? => historyStamp(context, ended),
                // The accent, as People › Shifts marks an open drawer: the
                // row somebody may need to chase.
                null => historyText(
                  context,
                  s.waiterShiftsOnShift,
                  color: pos.accent,
                ),
              },
              MonoCode(
                waiterShiftHours(history.minutesOf(shift)),
                size: 13,
                weight: FontWeight.w600,
                color: shift.isOpen ? pos.accent : pos.ink,
              ),
              switch (_handhelds(shift)) {
                final names? => historyText(context, names),
                null => historyNone(context),
              },
            ]),
        ],
      ),
      const SizedBox(height: PosSpace.s24),
      MicroLabel(s.waiterShiftsTotals, key: const Key('waiter-shifts-totals')),
      const SizedBox(height: PosSpace.sm),
      HistoryTable(
        columns: [
          (label: s.waiterShiftsWaiter, flex: 6, numeric: false),
          (label: s.waiterShiftsCount, flex: 2, numeric: true),
          (label: s.waiterShiftsHours, flex: 2, numeric: true),
        ],
        rows: [
          for (final total in history.totals)
            HistoryRow(Key('waiter-shifts-total-${total.staffId}'), [
              historyText(context, total.name),
              MonoCode('${total.shifts}', size: 13, color: pos.ink),
              MonoCode(
                waiterShiftHours(total.minutes),
                size: 13,
                weight: FontWeight.w600,
                color: total.onShift ? pos.accent : pos.ink,
              ),
            ]),
        ],
      ),
      const SizedBox(height: PosSpace.md),
      HistoryNote(s.waiterShiftsNote),
    ];
  }

  /// By id for a waiter whose directory row is gone, as [historyTill] does
  /// for a till: a blank name in a list of hours is a shift nobody can chase.
  static String _name(WaiterShiftRecord shift) =>
      shift.staffName ?? '#${shift.staffId}';

  /// The handheld it was started on, and the one it was finished on when that
  /// was another — a waiter whose phone died mid-shift and who finished on a
  /// colleague's is worth seeing. Null for a shift with neither on record (a
  /// handheld since removed).
  static String? _handhelds(WaiterShiftRecord shift) {
    final names = {
      ?shift.startedDevice,
      ?shift.endedDevice,
    };
    // A slash, as People › Shifts' "Opened / closed": an arrow points the
    // wrong way once the row is mirrored in Arabic.
    return names.isEmpty ? null : names.join(' / ');
  }
}
