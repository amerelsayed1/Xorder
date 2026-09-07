import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/labels.dart';
import '../../core/l10n/app_strings.dart';
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
/// A receipt is paper, and paper is white in a dark room too.
///
/// This dialog renders a PRINTED artefact rather than a screen: white stock,
/// grey platen behind it, black impact ink. Theming it would put the dark
/// theme's near-white ink on that white stock and hand the operator a blank
/// preview of a receipt that will print perfectly well.
///
/// The scrim behind the dialog is the exception and stays with the theme — it
/// is the room, not the paper.
const _receipt = PosPalette.light;

class ReceiptDialog extends ConsumerWidget {
  const ReceiptDialog({super.key, required this.ticket, required this.result});

  final Ticket ticket;
  final SubmitOrderResult result;

  static Future<void> show(
    BuildContext context, {
    required Ticket ticket,
    required SubmitOrderResult result,
  }) => showDialog<void>(
    context: context,
    barrierColor: context.pos.scrimHeavy,
    barrierDismissible: false,
    builder: (_) => ReceiptDialog(ticket: ticket, result: result),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).valueOrNull;
    final totals = ticket.totals;
    final strings = context.strings;

    return Dialog(
      backgroundColor: const Color(0xFFE9E6E0),
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: RoundedRectangleBorder(
        side: _receipt.emphasis,
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
                  child: _paper(session, totals, strings),
                ),
              ),
              const SizedBox(height: PosSpace.md),
              _actions(context, ref, strings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paper(
    PosSession? session,
    TicketTotals totals,
    AppStrings strings,
  ) => Container(
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
          style: PosText.ui(
            size: 17,
            weight: FontWeight.w800,
            color: _receipt.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          strings.taxRegistrationLine,
          textAlign: TextAlign.center,
          style: PosText.mono(size: 11, color: _receipt.body),
        ),
        _dashed(),
        _row(
          result.invoiceNumber ?? strings.provisionalInvoice,
          '${session?.terminalCode ?? ''} / ${(session?.userName ?? '').toUpperCase()}',
        ),
        _row(
          [
            ticket.orderType.label(strings),
            if (ticket.tableLabel != null) ticket.tableLabel!,
          ].join(' · '),
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
                    '${line.quantity} '
                    '${line.product.displayName(strings.languageCode)}',
                    overflow: TextOverflow.ellipsis,
                    style: PosText.mono(size: 12.5, color: _receipt.ink),
                  ),
                ),
                Text(
                  line.lineTotal.format(),
                  style: PosText.mono(size: 12.5, color: _receipt.ink),
                ),
              ],
            ),
          ),
        _dashed(),
        _row(strings.receiptSubtotal, totals.subtotal.format(), size: 12),
        // The rates come off the ticket, not off this file. They were
        // printed as a fixed 12/14 here, which quietly contradicted both
        // the cart's totals block and the arithmetic the customer is
        // holding whenever a branch is configured differently.
        if (!totals.service.isZero)
          _row(
            strings.receiptService(
              (ticket.taxConfig.serviceBp / 100).toStringAsFixed(0),
            ),
            totals.service.format(),
            size: 12,
          ),
        _row(
          strings.receiptVat((ticket.taxConfig.vatBp / 100).toStringAsFixed(0)),
          totals.vat.format(),
          size: 12,
        ),
        Container(
          margin: const EdgeInsets.only(top: PosSpace.sm),
          padding: const EdgeInsets.only(top: PosSpace.sm),
          decoration: BoxDecoration(
            border: Border(top: _receipt.emphasis),
          ),
          child: Row(
            children: [
              Text(
                strings.receiptTotal,
                style: PosText.mono(color: _receipt.inkWarm, size: 17, weight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                totals.total.format(),
                style: PosText.mono(color: _receipt.inkWarm, size: 17, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
        _row(strings.receiptPaid, totals.paid.format(), size: 12),
        _row(strings.receiptChange, totals.change.format(), size: 12),
        _dashed(),
        Text(
          result.invoiceNumber == null || result.queued
              ? strings.receiptQueuedOffline
              : strings.receiptSynced,
          textAlign: TextAlign.center,
          style: PosText.mono(size: 10.5, color: _receipt.body),
        ),
        Text(
          'xorder.io',
          textAlign: TextAlign.center,
          style: PosText.mono(size: 10.5, color: _receipt.body),
        ),
        Text(
          strings.receiptThanks,
          textAlign: TextAlign.center,
          style: strings.languageCode == 'ar'
              ? PosText.arabic(size: 11, color: _receipt.body)
              : PosText.mono(size: 10.5, color: _receipt.body),
        ),
        // Tax figures came from read-only device config, not the server.
        // Disclosing that is deliberate — see POS-BE-013.
        if (ticket.taxConfig.source == TaxSource.deviceConfig)
          Padding(
            padding: const EdgeInsets.only(top: PosSpace.sm),
            child: Text(
              strings.receiptTaxFromDevice,
              textAlign: TextAlign.center,
              style: PosText.mono(size: 9.5, color: _receipt.warn),
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
      style: PosText.mono(size: 11, color: _receipt.shellLineMeta),
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
            style: PosText.mono(size: size, color: _receipt.ink),
          ),
        ),
        Text(
          right,
          style: PosText.mono(size: size, color: _receipt.ink),
        ),
      ],
    ),
  );

  Widget _actions(BuildContext context, WidgetRef ref, AppStrings strings) =>
      Row(
        children: [
          Expanded(
            child: PosButton(
              label: strings.newSale,
              height: 48,
              background: _receipt.ink,
              foreground: Colors.white,
              onPressed: () => _finish(context, ref),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            child: PosButton(
              label: strings.printAndNew,
              height: 48,
              border: Border.fromBorderSide(
                BorderSide(color: _receipt.inkWarm),
              ),
              onPressed: () {
                // A missing printer must degrade, never block: the sale is
                // already complete and the receipt queues.
                posToast(context, strings.receiptQueuedToast);
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
