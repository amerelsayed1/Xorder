import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/refund.dart';
import '../../../domain/models/refund_history.dart';
import 'history_widgets.dart';
import 'order_history_screen.dart' show SaleToOpen;

/// One refund, opened from Returns.
///
/// The head is the row that was clicked; the items, the tenders and the
/// parts of the total are `refundsForOrderProvider` — the read the sale's
/// own detail pane and the refund engine already use — rather than a second
/// query for one refund. A second read of the same rows is where a refund
/// shown here would start to differ from the same refund shown on its sale.
///
/// Everything is read. A refund is corrected by issuing another, never by
/// editing this one, so the only action is the way to the sale.
class RefundDetailPane extends ConsumerWidget {
  const RefundDetailPane({super.key, required this.refund, this.onOpenSale});

  /// Null when nothing is selected.
  final RefundRecord? refund;

  /// Opens the sale this refund was against, in Orders. Null draws no
  /// button — where there is no Orders to open it in.
  final ValueChanged<SaleToOpen>? onOpenSale;

  static const openSaleKey = ValueKey('refund-open-sale');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final pos = context.pos;
    final row = refund;
    if (row == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Text(
            strings.returnsPickARefund,
            textAlign: TextAlign.center,
            style: PosText.ui(size: 13.5, color: pos.muted),
          ),
        ),
      );
    }

    final read = ref.watch(refundsForOrderProvider(row.orderId));
    final full = read.valueOrNull
        ?.where((given) => given.id == row.id)
        .firstOrNull;
    final open = onOpenSale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _head(context, strings, row),
        Expanded(
          child: read.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: pos.accent)),
            error: (error, _) => HistoryMessage(
              message: strings.returnsUnavailable,
              detail: '$error',
            ),
            data: (_) => ListView(
              padding: const EdgeInsets.fromLTRB(
                PosSpace.md,
                PosSpace.md,
                PosSpace.md,
                PosSpace.xl,
              ),
              children: [
                if (reasonInReaderLanguage(
                      context,
                      english: row.reasonName,
                      arabic: row.reasonNameAr,
                    )
                    case final reason?) ...[
                  MicroLabel(strings.returnColumnReason),
                  const SizedBox(height: PosSpace.xs),
                  Text(reason, style: PosText.ui(size: 12.5, color: pos.ink)),
                ],
                if (row.note case final note? when note.trim().isNotEmpty)
                  Text(note, style: PosText.ui(size: 12.5, color: pos.muted)),
                const SizedBox(height: PosSpace.md),
                MicroLabel(strings.orderDetailLines),
                const SizedBox(height: PosSpace.xs),
                if (full == null || full.isAmountOnly)
                  Text(
                    strings.returnDetailAmountOnly,
                    style: PosText.ui(size: 12.5, color: pos.muted),
                  )
                else
                  for (final line in full.lines) _line(context, line),
                const SizedBox(height: PosSpace.md),
                _totals(context, strings, row, full),
                if (full != null && full.payments.isNotEmpty) ...[
                  const SizedBox(height: PosSpace.md),
                  MicroLabel(strings.returnDetailReturnedTo),
                  const SizedBox(height: PosSpace.xs),
                  for (final tender in full.payments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tenderName(
                                tender.tenderTypeId,
                                tender.label,
                                strings,
                              ),
                              overflow: TextOverflow.ellipsis,
                              style: PosText.ui(size: 12.5, color: pos.ink),
                            ),
                          ),
                          MonoAmount(tender.amount, size: 12.5),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (open != null)
          Container(
            padding: const EdgeInsets.all(PosSpace.md),
            decoration: BoxDecoration(
              border: BorderDirectional(top: pos.hairline),
            ),
            child: PosButton(
              key: openSaleKey,
              label: strings.returnDetailOpenSale,
              border: Border.fromBorderSide(pos.resting),
              onPressed: () => open(
                SaleToOpen(
                  orderId: row.orderId,
                  invoiceNumber: row.invoiceNumber,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _head(BuildContext context, AppStrings strings, RefundRecord row) {
    final pos = context.pos;
    Widget muted(String text) => Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: PosText.ui(size: 12.5, color: pos.muted),
    );
    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(border: BorderDirectional(bottom: pos.resting)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MicroLabel(strings.returnColumnRefund),
              const SizedBox(width: PosSpace.sm),
              // The number and its `#` as one mono, left-to-right run.
              MonoCode(
                '#${row.id}',
                size: 15,
                weight: FontWeight.w600,
                color: pos.ink,
              ),
              const Spacer(),
              Text(
                refundKindLabel(strings, row.kind),
                style: PosText.ui(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: pos.warn,
                ),
              ),
            ],
          ),
          const SizedBox(height: PosSpace.xs),
          Row(
            children: [
              Expanded(
                child: muted(
                  '${strings.returnColumnCashier}: ${row.refundedByName ?? '—'}',
                ),
              ),
              MonoCode(historyStamp(row.occurredAt), size: 11.5),
            ],
          ),
          if (row.approvedByName case final approver?)
            muted(strings.orderDetailApprovedBy(approver)),
          if (row.terminalName case final till?)
            muted('${strings.orderDetailTerminal}: $till'),
          const SizedBox(height: PosSpace.sm),
          Row(
            children: [
              MicroLabel(strings.returnColumnInvoice),
              const SizedBox(width: PosSpace.sm),
              Expanded(
                child: MonoCode(row.invoiceNumber, size: 12.5, color: pos.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, RefundLineSelection line) {
    final pos = context.pos;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 28, child: MonoCode('${line.quantity}', size: 12.5)),
          Expanded(
            child: Text(
              line.name,
              overflow: TextOverflow.ellipsis,
              style: PosText.ui(size: 12.5, color: pos.ink),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          MonoAmount(line.lineTotal, size: 12.5),
        ],
      ),
    );
  }

  /// The refund's own parts, as written when it was given — never worked out
  /// again from its lines. Only the total while the full refund is read, or
  /// if it cannot be: the total is on the row, and is the figure that matters.
  Widget _totals(
    BuildContext context,
    AppStrings strings,
    RefundRecord row,
    Refund? full,
  ) {
    final pos = context.pos;
    Widget line(String label, Money value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PosText.ui(
                size: strong ? 13.5 : 12.5,
                weight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? pos.ink : pos.muted,
              ),
            ),
          ),
          MonoAmount(
            value,
            size: strong ? 15 : 12.5,
            weight: strong ? FontWeight.w700 : FontWeight.w400,
            color: pos.ink,
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      decoration: BoxDecoration(
        border: BorderDirectional(top: pos.hairline, bottom: pos.hairline),
      ),
      child: Column(
        children: [
          if (full != null) ...[
            line(strings.orderDetailSubtotal, full.subtotal),
            if (full.discount.minor != 0)
              line(strings.orderDetailDiscount, -full.discount),
            if (full.service.minor != 0)
              line(strings.orderDetailService, full.service),
            line(strings.orderDetailVat, full.vat),
            const SizedBox(height: 2),
          ],
          line(strings.returnsSummaryTotal, row.total, strong: true),
        ],
      ),
    );
  }
}
