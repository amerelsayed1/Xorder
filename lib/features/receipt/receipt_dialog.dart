import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/deployment.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/models/receipt_profile.dart';
import '../../domain/models/tender_method.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/mono_amount.dart';
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

  ReceiptData _slip() => _data ??= ReceiptData.fromTicket(
    ticket,
    invoiceNumber: result.invoiceNumber,
    queued: result.queued,
    // Whether there is a platform at all. An offline till prints nothing
    // about sync rather than claiming to have reached something it has
    // never contacted.
    cloudBacked: ref.read(deploymentProvider).mode == DeploymentMode.cloud,
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
              // Above the paper, not on it: the slip is the customer's and
              // says "Change 170.00" in its own small type. This is the
              // cashier's, for the seconds they are counting it out.
              if (ticket.totals.change.isPositive) ...[
                _changeDue(strings),
                const SizedBox(height: PosSpace.md),
              ],
              Flexible(
                child: SingleChildScrollView(
                  child: ReceiptPaper(
                    data: _slip(),
                    profile:
                        ref.watch(receiptProfileProvider).valueOrNull ??
                        const ReceiptProfile(branchId: 0),
                    tenantName: session?.tenantName ?? '',
                    terminalCode: session?.terminalCode ?? '',
                    cashierName: ref.watch(operatorNameProvider),
                    tenderMethods: _tenderMethods(),
                    logo: ref.watch(receiptLogoProvider).valueOrNull,
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

  /// The change, as the biggest number on the screen.
  ///
  /// The audit watched a cashier hand back 170 on a 500 note by reading it
  /// off a line of the slip in 11px mono — the same size as the VAT. The
  /// amount is the engine's (`TicketTotals.change`, the same figure the slip
  /// prints); nothing here adds or subtracts. 46px is `bigNumeric`, the size
  /// the payment screen gave the amount due a moment ago, so what was owed
  /// and what goes back are read at the same size.
  ///
  /// Keyed, so a test can tell this figure from the slip's own change row.
  Widget _changeDue(AppStrings strings) => Container(
    key: const ValueKey('change-due'),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.s14,
    ),
    color: _receipt.ink,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(strings.changeDue, color: Colors.white),
        const SizedBox(height: PosSpace.xs),
        // Scaled down, never clipped: a figure that lost its leading digit
        // to the dialog's edge would be the one lie this banner must not
        // tell. At 46px mono the widest change a till hands back fits the
        // 296px inside the paper; this is for the day one does not.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MonoAmount(
                ticket.totals.change,
                size: 46,
                weight: FontWeight.w600,
                color: Colors.white,
                // The currency is the smaller label beside it.
                withCurrency: false,
              ),
              Padding(
                // Directional: after the figure, which is its right in
                // English and its left in Arabic.
                padding: const EdgeInsetsDirectional.only(bottom: 6, start: 6),
                child: Text(
                  ticket.currency,
                  style: PosText.ui(size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _actions(BuildContext context, WidgetRef ref, AppStrings strings) {
    final printer = ref.watch(printerConfigProvider);
    return Row(
      children: [
        Expanded(
          child: PosButton(
            label: strings.newSale,
            height: 48,
            background: _receipt.ink,
            foreground: Colors.white,
            onPressed: _printing
                ? null
                : () => _finish(context, ref, openDrawer: _drawerOpens()),
          ),
        ),
        const SizedBox(width: PosSpace.sm),
        // On a till with no printer the print button is disabled and says
        // why, in its own place: it used to stay live, print nothing and
        // toast about it afterwards, and a disabled control with no words
        // on it is a fault the cashier reports. Not hidden, because the
        // dialog's two-button layout is what hands learn, and the day the
        // printer is plugged in the button should be where it always was.
        Expanded(
          child: printer.isConfigured
              ? PosButton(
                  label: strings.printAndNew,
                  height: 48,
                  border: Border.fromBorderSide(
                    BorderSide(color: _receipt.inkWarm),
                  ),
                  onPressed: _printing ? null : () => _print(context, strings),
                )
              : Tooltip(
                  message: strings.receiptNoPrinterToast,
                  child: PosButton(
                    label: strings.receiptNoPrinter,
                    height: 48,
                    border: Border.fromBorderSide(
                      BorderSide(color: _receipt.inkWarm),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Print the slip, then start the next sale.
  ///
  /// **The sale is already complete before this runs.** Nothing here is allowed
  /// to hold the counter up or to leave the ticket on screen: whatever the
  /// printer does, the cashier is told what happened in one sentence and the
  /// till moves on. What changed is that the sentence is now true — it used to
  /// say "queued" while nothing was printed and nothing was queued.
  Future<void> _print(BuildContext context, AppStrings strings) async {
    setState(() => _printing = true);

    // Before anything else is read: the one await ahead of the build. It never
    // throws, and a logo that is slow or missing is a slip without one.
    final logo = await ref
        .read(receiptLogoProvider.future)
        .catchError((Object _) => null);
    if (!mounted) return;

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
      tenderMethods: _tenderMethods(),
      logo: logo,
    );

    final outcome = await ref
        .read(receiptPrinterProvider)
        .printReceipt(
          document,
          // Drawer opening is not part of a queued print job.  Otherwise an
          // offline printer could open the till on the next shift, long after
          // the cash sale it belonged to.
          openDrawer: false,
          // The local `pos_orders.id`, which is what `serverId` holds on a till
          // writing to its own branch database. Null on a sale that never
          // reached a row, and the column is nullable for exactly that.
          orderId: result.serverId,
          invoiceNumber: result.invoiceNumber,
        );

    if (!context.mounted) return;
    posToast(context, printOutcomeMessage(strings, outcome));
    await _finish(context, ref, openDrawer: _drawerOpens());
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
  /// The till's tender types, for the Arabic name on the slip. The seeded list
  /// while they load, which is what the payment screen falls back to as well.
  List<TenderMethod> _tenderMethods() =>
      ref.read(tenderTypesProvider).valueOrNull ?? TenderMethod.seeded;

  bool _drawerOpens() {
    final methods = _tenderMethods();
    return ticket.tenders.any(
      (tender) => methods.any(
        (method) => method.id == tender.typeId && method.opensDrawer,
      ),
    );
  }

  Future<void> _finish(
    BuildContext context,
    WidgetRef ref, {
    required bool openDrawer,
  }) async {
    if (openDrawer) {
      setState(() => _printing = true);
      final printer = ref.read(receiptPrinterProvider);
      final opened = await printer.openDrawer();
      if (!context.mounted) return;
      // A till with no printer has nothing to kick a drawer through, and the
      // print outcome already said so — a second sentence about the drawer
      // would only replace it. A printer that is set up and answered nothing
      // is different: the cash is in the cashier's hand right now, so that
      // takes the toast over whatever the print said.
      if (!opened && printer.printer.isConfigured) {
        posToast(context, context.strings.drawerCouldNotOpen);
      }
    }
    if (!context.mounted) return;
    ref.read(ticketProvider.notifier).reset();
    Navigator.of(context).pop();
  }
}
