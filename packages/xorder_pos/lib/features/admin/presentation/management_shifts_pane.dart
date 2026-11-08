import 'package:flutter/material.dart';

import '../../../app/shift_history_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import '../../shift/presentation/shift_dialogs.dart';
import 'shift_history_bits.dart';

/// People › Shifts (الأفراد › الورديات): every shift at the branch over the
/// chosen dates, open ones on top, each row opening its Z report.
///
/// **Read-only, and every figure is the Z report's.** Float, cash taken, paid
/// in and paid out come from `ShiftRepository.summarise` — the function the
/// cash-up closes against and Finance's drawers read — and expected, counted
/// and over/short are what the close stored. Nothing is summed here for this
/// screen, so nothing here can disagree with the report a row opens.
class ManagementShiftsPane extends StatelessWidget {
  const ManagementShiftsPane({required this.admin, super.key});

  /// The person in Admin Mode.
  final PosStaff admin;

  /// What the shell asks before it offers this pane: `reports.view`, the gate
  /// its data is read through — see `shiftHistoryProvider` for why not
  /// `staff.manage`. The provider asks again, so a pane reached round the
  /// shell still draws nothing.
  static const requires = {PosCapability.reportsView};

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    // The till's rule for revealing a count's difference: `cash.variance.view`,
    // which the closed cash-up asks before it shows one. Expected stays
    // visible, as Finance › Drawers shows it to the same people.
    final seesVariance = Authorization.check(
      admin,
      PosCapability.cashVarianceView,
    ).isAllowed;

    return ShiftHistoryFrame(
      paneKey: 'shifts',
      blurb: s.shiftsBlurb,
      period: shiftsPeriodProvider,
      statusChoices: ShiftStatus.values,
      emptyText: s.shiftsNone,
      builder: (context, history) {
        final pos = context.pos;
        return [
          HistoryTable(
            columns: [
              (label: s.terminalCell, flex: 2, numeric: false),
              (label: s.shiftsCashier, flex: 3, numeric: false),
              (label: s.shiftsOpenedClosed, flex: 4, numeric: false),
              (label: s.financeStatus, flex: 3, numeric: false),
              (label: s.financeFloat, flex: 2, numeric: true),
              (label: s.financeCashTaken, flex: 2, numeric: true),
              (label: s.financePaidIn, flex: 2, numeric: true),
              (label: s.financePaidOut, flex: 2, numeric: true),
              (label: s.financeExpected, flex: 2, numeric: true),
              (label: s.zCounted, flex: 2, numeric: true),
              (label: s.shiftsOverShort, flex: 2, numeric: true),
            ],
            rows: [
              for (final record in history.shifts)
                HistoryRow(
                  Key('shifts-row-${record.shift.id}'),
                  [
                    historyTill(context, record),
                    historyText(context, record.shift.openedByName),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        historyStamp(context, record.shift.openedAt),
                        if (record.shift.closedAt case final closed?)
                          historyStamp(context, closed),
                      ],
                    ),
                    historyText(
                      context,
                      shiftStatusLabel(s, record.status),
                      color: switch (record.status) {
                        ShiftStatus.open => pos.accent,
                        ShiftStatus.closed => pos.body,
                        ShiftStatus.forceClosed => pos.warn,
                      },
                    ),
                    MonoAmount(record.shift.openingFloat),
                    MonoAmount(record.summary.cashTaken),
                    MonoAmount(record.summary.cashIn),
                    MonoAmount(record.summary.cashOut),
                    MonoAmount(record.expectedCash, weight: FontWeight.w600),
                    switch (record.countedCash) {
                      final counted? => MonoAmount(counted),
                      null => historyNone(context),
                    },
                    historyVariance(
                      context,
                      record.overShort,
                      masked: !seesVariance,
                    ),
                  ],
                  // The report as the closed cash-up shows it: counted, the
                  // expected figure it was judged against, and — for somebody
                  // who may see it — the difference. An open drawer's expected
                  // figure is Finance › Drawers' own, shown to the same people.
                  onTap: () => ShiftReportDialog.show(
                    context,
                    record: record,
                    blind: !record.shift.isOpen && !seesVariance,
                  ),
                ),
            ],
          ),
          const SizedBox(height: PosSpace.md),
          if (history.cut) ...[
            HistoryNote(s.shiftsCut(ShiftHistory.limit)),
            const SizedBox(height: PosSpace.sm),
          ],
          if (!seesVariance) ...[
            HistoryNote(s.shiftsVarianceHidden),
            const SizedBox(height: PosSpace.sm),
          ],
          HistoryNote(s.shiftsExpectedNote),
        ];
      },
    );
  }
}
