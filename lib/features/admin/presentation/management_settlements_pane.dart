import 'package:flutter/material.dart';

import '../../../app/finance_providers.dart' show financePeriodProvider;
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import '../../shift/presentation/shift_dialogs.dart';
import 'shift_history_bits.dart';

/// Finance › Settlements (المالية › التسويات): the drawer cash-ups — each
/// closed shift's count against what the Z report expected, the difference,
/// who counted, and the note or approval they closed with.
///
/// **Read-only.** A count is made at the drawer and stored by the close; this
/// screen reads what was stored and has no control that writes. "Settlement"
/// here is a cash reconciliation, not the bank and wallet settlements Finance
/// cut for having no accounting model to read them from.
///
/// **The strip is the rows.** [CashUpTotals.of] sums the very records the
/// table draws, so the two cannot be a query apart.
class ManagementSettlementsPane extends StatelessWidget {
  const ManagementSettlementsPane({required this.admin, super.key});

  /// The person in Admin Mode.
  final PosStaff admin;

  /// `reports.view`, as every Finance pane. The data is read through
  /// `shiftHistoryProvider`, which asks it of the person acting.
  static const requires = {PosCapability.reportsView};

  /// Only counted drawers are cash-ups. An open shift has nothing to settle.
  static const _counted = {ShiftStatus.closed, ShiftStatus.forceClosed};

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    // As on Shifts: the difference is `cash.variance.view`'s to see. A strip
    // of totals made of masked rows would be the rows unmasked, summed.
    final seesVariance = Authorization.check(
      admin,
      PosCapability.cashVarianceView,
    ).isAllowed;

    return ShiftHistoryFrame(
      paneKey: 'settlements',
      blurb: s.settlementsBlurb,
      // Finance's dates: one choice for the tab, so moving from Drawers to
      // Settlements does not quietly move from this month to this week.
      period: financePeriodProvider,
      statusChoices: const [ShiftStatus.closed, ShiftStatus.forceClosed],
      listed: _counted,
      emptyText: s.settlementsNone,
      builder: (context, history) {
        final totals = CashUpTotals.of(history.shifts);
        Widget money(Money value) => MonoAmount(
          value,
          size: 26,
          weight: FontWeight.w600,
          masked: !seesVariance,
        );
        return [
          HistoryTileRow(
            children: [
              HistoryTile(
                tileKey: 'settlements-tile-count',
                label: s.settlementsKpiCount,
                value: Text(
                  '${totals.count}',
                  textDirection: TextDirection.ltr,
                  style: PosText.mono(
                    size: 26,
                    weight: FontWeight.w600,
                    color: context.pos.ink,
                  ),
                ),
              ),
              HistoryTile(
                tileKey: 'settlements-tile-over',
                label: s.settlementsKpiOver,
                value: money(totals.over),
              ),
              HistoryTile(
                tileKey: 'settlements-tile-short',
                label: s.settlementsKpiShort,
                value: money(totals.short),
              ),
              HistoryTile(
                tileKey: 'settlements-tile-net',
                label: s.settlementsKpiNet,
                value: money(totals.net),
              ),
            ],
          ),
          const SizedBox(height: PosSpace.s24),
          HistoryTable(
            columns: [
              (label: s.terminalCell, flex: 2, numeric: false),
              (label: s.financeOpenedBy, flex: 3, numeric: false),
              (label: s.shiftsClosedAt, flex: 3, numeric: false),
              (label: s.settlementsCountedBy, flex: 3, numeric: false),
              (label: s.financeExpected, flex: 2, numeric: true),
              (label: s.zCounted, flex: 2, numeric: true),
              (label: s.shiftsOverShort, flex: 2, numeric: true),
              (label: s.settlementsNoteApproval, flex: 4, numeric: false),
            ],
            rows: [
              for (final record in history.shifts)
                HistoryRow(
                  Key('settlements-row-${record.shift.id}'),
                  [
                    historyTill(context, record),
                    historyText(context, record.shift.openedByName),
                    switch (record.shift.closedAt) {
                      final closed? => historyStamp(context, closed),
                      null => historyNone(context),
                    },
                    historyText(
                      context,
                      record.closedByName ?? '—',
                      // Somebody else's drawer: the name is the point.
                      color: record.status == ShiftStatus.forceClosed
                          ? context.pos.warn
                          : null,
                    ),
                    MonoAmount(record.expectedCash),
                    switch (record.countedCash) {
                      final counted? => MonoAmount(counted),
                      null => historyNone(context),
                    },
                    historyVariance(
                      context,
                      record.overShort,
                      masked: !seesVariance,
                    ),
                    _NoteCell(record: record),
                  ],
                  onTap: () => ShiftReportDialog.show(
                    context,
                    record: record,
                    blind: !seesVariance,
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

/// The approval, then the note — each a line, each cut short rather than
/// wrapped: the whole of both is in the report the row opens.
class _NoteCell extends StatelessWidget {
  const _NoteCell({required this.record});

  final ShiftRecord record;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final note = record.note?.trim();
    final lines = [
      if (record.approvedByName case final name?) s.settlementsApprovedBy(name),
      if (note != null && note.isNotEmpty) note,
    ];
    if (lines.isEmpty) return historyNone(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PosText.ui(size: 12.5, color: context.pos.body),
          ),
      ],
    );
  }
}
