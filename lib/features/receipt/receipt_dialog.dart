import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/deployment.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/models/receipt_profile.dart';
import '../../domain/models/tender_method.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import 'receipt_data.dart';
import 'receipt_document.dart';
import 'receipt_paper.dart';
import 'receipt_printing.dart';

/// Receipt preview — confirms the sale and starts the next one.
///
/// 360-wide modal on `#e9e6e0` with a 2px ink border; the paper block is white
/// and entirely mono. The footer is honest about sync state: a queued sale says
/// so on the printed slip, because a customer holding a receipt for a sale the
/// server has never seen should be able to tell.
/// The scrim behind the dialog stays with the theme — it is the room, not the
/// paper. Everything on the slip itself is [ReceiptPaper]'s business.
const _receipt = receiptPalette;

class ReceiptDialog extends ConsumerStatefulWidget {
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
  ConsumerState<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends ConsumerState<ReceiptDialog> {
  /// True while the bytes are being built and sent.
  ///
  /// Rasterising a receipt is a few milliseconds and a socket write is a few
  /// more, so this is rarely seen — but a second tap while the first job is in
  /// flight would print the receipt twice, and a customer with two copies of
  /// one sale is how a refund gets claimed twice.
  bool _printing = false;

  Ticket get ticket => widget.ticket;
  SubmitOrderResult get result => widget.result;

  /// The slip, built once.
  ///
  /// Cached rather than rebuilt for the print, because `fromTicket` stamps
  /// `DateTime.now()`: a second call would produce a document a few
  /// milliseconds later than the one on screen, and the paper handed over has
  /// to be the paper that was previewed.
  ReceiptData? _data;

  ReceiptData _slip() =>
      _data ??= ReceiptData.fromTicket(
        ticket,
        invoiceNumber: result.invoiceNumber,
        queued: result.queued,
        // Whether there is a platform at all. An offline till prints nothing
        // about sync rather than claiming to have reached something it has
        // never contacted.
        cloudBacked:
            ref.read(deploymentProvider).mode == DeploymentMode.cloud,
      );

  @override
  Widget build(BuildContext context) {
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
                    data: _slip(),
                    profile: ref.watch(receiptProfileProvider).valueOrNull ??
                        const ReceiptProfile(branchId: 0),
                    tenantName: session?.tenantName ?? '',
                    terminalCode: session?.terminalCode ?? '',
                    cashierName: ref.watch(operatorNameProvider),
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
              onPressed: _printing ? null : () => _finish(context, ref),
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
              onPressed: _printing ? null : () => _print(context, strings),
            ),
          ),
        ],
      );

  /// Print the slip, then start the next sale.
  ///
  /// **The sale is already complete before this runs.** Nothing here is allowed
  /// to hold the counter up or to leave the ticket on screen: whatever the
  /// printer does, the cashier is told what happened in one sentence and the
  /// till moves on. What changed is that the sentence is now true — it used to
  /// say "queued" while nothing was printed and nothing was queued.
  Future<void> _print(BuildContext context, AppStrings strings) async {
    setState(() => _printing = true);

    final session = ref.read(sessionProvider).valueOrNull;
    final document = ReceiptDocument.of(
      _slip(),
      strings: strings,
      profile:
          ref.read(receiptProfileProvider).valueOrNull ??
          const ReceiptProfile(branchId: 0),
      tenantName: session?.tenantName ?? '',
      terminalCode: session?.terminalCode ?? '',
      cashierName: ref.watch(operatorNameProvider),
    );

    final outcome = await ref
        .read(receiptPrinterProvider)
        .printReceipt(
          document,
          openDrawer: _drawerOpens(),
          // The local `pos_orders.id`, which is what `serverId` holds on a till
          // writing to its own branch database. Null on a sale that never
          // reached a row, and the column is nullable for exactly that.
          orderId: result.serverId,
          invoiceNumber: result.invoiceNumber,
        );

    if (!context.mounted) return;
    posToast(context, printOutcomeMessage(strings, outcome));
    _finish(context, ref);
  }

  /// Whether this sale should spring the drawer.
  ///
  /// Read from the tender types as they are configured **now** rather than
  /// snapshotted onto the tender the way `countsAsCash` is. The two look alike
  /// and are not: `countsAsCash` decides what a cash-up says a drawer should
  /// have held weeks later, so it has to be frozen at the moment the money
  /// moved. This decides whether a solenoid fires in the next half second, and
  /// the only correct answer to that is what the restaurant has configured
  /// right now.
  bool _drawerOpens() {
    final methods = ref.read(tenderTypesProvider).valueOrNull ??
        TenderMethod.seeded;
    return ticket.tenders.any(
      (tender) => methods.any(
        (method) => method.id == tender.typeId && method.opensDrawer,
      ),
    );
  }

  void _finish(BuildContext context, WidgetRef ref) {
    ref.read(ticketProvider.notifier).reset();
    Navigator.of(context).pop();
  }
}
