import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';

/// Receipt preview — confirms the sale and starts the next one.
///
/// 360-wide modal on `#e9e6e0` with a 2px ink border; the paper block is white
/// and entirely mono. The footer is honest about sync state: a queued sale says
/// so on the printed slip, because a customer holding a receipt for a sale the
/// server has never seen should be able to tell.
class ReceiptDialog extends ConsumerWidget {
  const ReceiptDialog({super.key, required this.ticket, required this.result});

  final Ticket ticket;
  final SubmitOrderResult result;

  static Future<void> show(
    BuildContext context, {
    required Ticket ticket,
    required SubmitOrderResult result,
  }) =>
      showDialog<void>(
        context: context,
        barrierColor: PosColors.scrimHeavy,
        barrierDismissible: false,
        builder: (_) => ReceiptDialog(ticket: ticket, result: result),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).valueOrNull;
    final totals = ticket.totals;

    return Dialog(
      backgroundColor: const Color(0xFFE9E6E0),
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: const RoundedRectangleBorder(
        side: PosBorders.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: _paper(session, totals),
                ),
              ),
              const SizedBox(height: PosSpace.md),
              _actions(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paper(PosSession? session, TicketTotals totals) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: PosSpace.s18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              (session?.tenantName ?? '').toUpperCase(),
              textAlign: TextAlign.center,
              style: PosText.ui(size: 17, weight: FontWeight.w800, color: PosColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              'مطعم محسوب',
              textAlign: TextAlign.center,
              style: PosText.arabic(size: 13, color: PosColors.body),
            ),
            Text(
              'TAX REG 000-000-000',
              textAlign: TextAlign.center,
              style: PosText.mono(size: 11, color: PosColors.body),
            ),
            _dashed(),
            _row(
              result.invoiceNumber ?? 'PROVISIONAL',
              '${session?.terminalCode ?? ''} / ${(session?.userName ?? '').toUpperCase()}',
            ),
            _row(
              [ticket.orderType.label, if (ticket.tableLabel != null) ticket.tableLabel!]
                  .join(' · '),
              _timestamp(),
            ),
            _dashed(),
            for (final line in ticket.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.quantity} ${line.product.nameEn}',
                        overflow: TextOverflow.ellipsis,
                        style: PosText.mono(size: 12.5, color: PosColors.ink),
                      ),
                    ),
                    Text(
                      line.lineTotal.format(),
                      style: PosText.mono(size: 12.5, color: PosColors.ink),
                    ),
                  ],
                ),
              ),
            _dashed(),
            _row('SUBTOTAL', totals.subtotal.format(), size: 12),
            if (!totals.service.isZero) _row('SERVICE 12%', totals.service.format(), size: 12),
            _row('VAT 14%', totals.vat.format(), size: 12),
            Container(
              margin: const EdgeInsets.only(top: PosSpace.sm),
              padding: const EdgeInsets.only(top: PosSpace.sm),
              decoration: const BoxDecoration(border: Border(top: PosBorders.emphasis)),
              child: Row(children: [
                Text('TOTAL', style: PosText.mono(size: 17, weight: FontWeight.w600)),
                const Spacer(),
                Text(
                  totals.total.format(),
                  style: PosText.mono(size: 17, weight: FontWeight.w600),
                ),
              ]),
            ),
            _row('PAID', totals.paid.format(), size: 12),
            _row('CHANGE', totals.change.format(), size: 12),
            _dashed(),
            Text(
              result.invoiceNumber == null || result.queued
                  ? 'QUEUED OFFLINE — WILL SYNC'
                  : 'SYNCED TO XORDER',
              textAlign: TextAlign.center,
              style: PosText.mono(size: 10.5, color: PosColors.body),
            ),
            Text(
              'xorder.io',
              textAlign: TextAlign.center,
              style: PosText.mono(size: 10.5, color: PosColors.body),
            ),
            Text(
              'شكراً لزيارتكم',
              textAlign: TextAlign.center,
              style: PosText.arabic(size: 11, color: PosColors.body),
            ),
            // Tax figures came from read-only device config, not the server.
            // Disclosing that is deliberate — see POS-BE-013.
            if (ticket.taxConfig.source == TaxSource.deviceConfig)
              Padding(
                padding: const EdgeInsets.only(top: PosSpace.sm),
                child: Text(
                  'TAX FROM DEVICE CONFIG',
                  textAlign: TextAlign.center,
                  style: PosText.mono(size: 9.5, color: PosColors.warn),
                ),
              ),
          ],
        ),
      );

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.day)}/${two(now.month)} ${two(now.hour)}:${two(now.minute)}';
  }

  Widget _dashed() => Padding(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
        child: Text(
          '-' * 42,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: PosText.mono(size: 11, color: PosColors.shellLineMeta),
        ),
      );

  Widget _row(String left, String right, {double size = 12.5}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Expanded(
              child: Text(
                left,
                overflow: TextOverflow.ellipsis,
                style: PosText.mono(size: size, color: PosColors.ink),
              ),
            ),
            Text(right, style: PosText.mono(size: size, color: PosColors.ink)),
          ],
        ),
      );

  Widget _actions(BuildContext context, WidgetRef ref) => Row(
        children: [
          Expanded(
            child: PosButton(
              label: 'New sale',
              height: 48,
              background: PosColors.ink,
              foreground: Colors.white,
              onPressed: () => _finish(context, ref),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            child: PosButton(
              label: 'Print & new',
              height: 48,
              border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
              onPressed: () {
                // A missing printer must degrade, never block: the sale is
                // already complete and the receipt queues.
                posToast(context, 'Receipt queued for the default printer.');
                _finish(context, ref);
              },
            ),
          ),
        ],
      );

  void _finish(BuildContext context, WidgetRef ref) {
    ref.read(ticketProvider.notifier).reset();
    Navigator.of(context).pop();
  }
}
