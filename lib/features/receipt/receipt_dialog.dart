import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/deployment.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/models/receipt_profile.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import 'receipt_data.dart';
import 'receipt_paper.dart';

/// Receipt preview — confirms the sale and starts the next one.
///
/// 360-wide modal on `#e9e6e0` with a 2px ink border; the paper block is white
/// and entirely mono. The footer is honest about sync state: a queued sale says
/// so on the printed slip, because a customer holding a receipt for a sale the
/// server has never seen should be able to tell.
/// The scrim behind the dialog stays with the theme — it is the room, not the
/// paper. Everything on the slip itself is [ReceiptPaper]'s business.
const _receipt = receiptPalette;

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
                  child: ReceiptPaper(
                    data: ReceiptData.fromTicket(
                      ticket,
                      invoiceNumber: result.invoiceNumber,
                      queued: result.queued,
                      // Whether there is a platform at all. An offline till
                      // prints nothing about sync rather than claiming to have
                      // reached something it has never contacted.
                      cloudBacked:
                          ref.watch(deploymentProvider).mode ==
                          DeploymentMode.cloud,
                    ),
                    profile: ref.watch(receiptProfileProvider).valueOrNull ??
                        const ReceiptProfile(branchId: 0),
                    tenantName: session?.tenantName ?? '',
                    terminalCode: session?.terminalCode ?? '',
                    cashierName: session?.userName ?? '',
                  ),
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
