import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/models/receipt_profile.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/order_record.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/refund.dart';
import '../../domain/models/shift.dart';
import '../../domain/models/tender_method.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/authorization.dart';
import '../admin/presentation/supervisor_override.dart';
import 'receipt_data.dart';
import 'receipt_document.dart';
import 'receipt_paper.dart';
import 'receipt_printing.dart';

/// Printing a copy of a receipt that already exists.
///
/// **The slip is marked.** A reprint that looked identical to the original is a
/// second document for one sale, and two identical receipts is how a refund
/// gets claimed twice. `REPRINT — NOT AN ORIGINAL` goes across the top, before
/// the business's name, so somebody handed the paper knows what it is before
/// they read what is on it.
///
/// **And it is recorded.** `AuditAction.receiptReprinted` has existed as a
/// constant since the audit ledger was built and has never been written by
/// anything. This is what writes it.
class ReprintDialog extends ConsumerStatefulWidget {
  const ReprintDialog({
    super.key,
    required this.detail,
    required this.refunds,
    this.approvedBy,
  });

  final OrderRecordDetail detail;

  /// The supervisor who let a cashier reprint, when one did. On the ledger
  /// row with the cashier: the row used to name only the cashier, so a
  /// reprint a supervisor had approved read as one nobody had.
  final PosStaff? approvedBy;

  /// What has since gone back. Printed on the slip so it cannot be used to
  /// claim a refund that has already been given.
  final List<Refund> refunds;

  /// What happened to the paper, or null when nothing was attempted — the
  /// cashier cancelled, or the reprint could not be recorded.
  ///
  /// **It used to return a bare `true` and the caller said "Reprint sent, and
  /// recorded".** Half of that sentence was a guess: nothing was sent, because
  /// nothing printed anywhere in the product. Now that a reprint really does go
  /// to a printer, the caller is told which of the four things happened.
  static Future<PrintOutcome?> show(
    BuildContext context, {
    required OrderRecordDetail detail,
    required List<Refund> refunds,
    PosStaff? approvedBy,
  }) => showDialog<PrintOutcome>(
    context: context,
    barrierColor: context.pos.scrimHeavy,
    builder: (_) =>
        ReprintDialog(detail: detail, refunds: refunds, approvedBy: approvedBy),
  );

  @override
  ConsumerState<ReprintDialog> createState() => _ReprintDialogState();
}

class _ReprintDialogState extends ConsumerState<ReprintDialog> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final session = ref.watch(sessionProvider).valueOrNull;

    return Dialog(
      backgroundColor: const Color(0xFFE9E6E0),
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: RoundedRectangleBorder(
        side: receiptPalette.emphasis,
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
                  // Previewed exactly as it will print, marking included. A
                  // preview that omitted the stamp would let somebody press
                  // Print expecting an original.
                  child: ReceiptPaper(
                    data: ReceiptData.fromOrder(
                      widget.detail,
                      refunds: widget.refunds,
                    ),
                    profile:
                        ref.watch(receiptProfileProvider).valueOrNull ??
                        const ReceiptProfile(branchId: 0),
                    tenantName: session?.tenantName ?? '',
                    terminalCode: session?.terminalCode ?? '',
                    // The person who **sold** it, not the person reprinting.
                    // The slip is a copy of what was issued, and rewriting the
                    // cashier's name would make it a different document.
                    //
                    // An order written before the till recorded a seller prints
                    // a dash rather than falling back to whoever is standing
                    // here — that fallback would put this person's name against
                    // a sale they did not make, which is a small lie on a
                    // document somebody may keep.
                    cashierName: widget.detail.order.servedByName ?? '—',
                    tenderMethods:
                        ref.watch(tenderTypesProvider).valueOrNull ??
                        TenderMethod.seeded,
                    logo: ref.watch(receiptLogoProvider).valueOrNull,
                  ),
                ),
              ),
              const SizedBox(height: PosSpace.md),
              Text(
                strings.receiptReprintExplain,
                textAlign: TextAlign.center,
                style: PosText.ui(size: 12, color: receiptPalette.body),
              ),
              const SizedBox(height: PosSpace.md),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      height: 48,
                      border: Border.fromBorderSide(
                        BorderSide(color: receiptPalette.inkWarm),
                      ),
                      onPressed: _busy
                          ? null
                          // Null, not an outcome: nothing was attempted, so
                          // there is nothing to tell the cashier about paper.
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      label: strings.receiptReprintConfirm,
                      height: 48,
                      background: receiptPalette.ink,
                      foreground: Colors.white,
                      onPressed: _busy ? null : _print,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _print() async {
    // The person acting — see `actingStaffProvider`. A copy printed from the
    // back office is the administrator's, whoever is signed in at the till.
    final by = ref.read(actingStaffProvider);
    if (by == null) return;
    setState(() => _busy = true);

    // The logo this till holds now (decided: a reprint is not a snapshot of the
    // original's). Read **before** the reprint is recorded, never between the
    // record and the print: a dialog dismissed in that gap would leave a
    // reprint on the ledger that never came out of the printer. Never throws;
    // none is a slip without one.
    final logo = await ref
        .read(receiptLogoProvider.future)
        .catchError((Object _) => null);
    if (!mounted) return;

    final order = widget.detail.order;
    try {
      await ref
          .read(auditRepositoryProvider)
          .record(
            by: by,
            approvedBy: widget.approvedBy,
            action: AuditAction.receiptReprinted,
            entityType: 'order',
            entityId: '${order.id}',
            after: {
              'invoice_number': order.invoiceNumber,
              'total_minor': order.total.minor,
            },
          );
    } on Object {
      // The ledger is unreachable. The receipt is **not** printed: an
      // unrecorded reprint is precisely the one somebody wanted, and a missing
      // printer is a smaller problem than a missing record.
      if (!mounted) return;
      setState(() => _busy = false);
      posToast(context, context.strings.reprintCouldNotBeRecorded);
      return;
    }

    // Recorded first, printed second, and deliberately in that order: a job
    // that reaches the printer and then fails to be recorded is the copy
    // somebody wanted off the books.
    //
    // Down the same path as a settlement — same document, same raster, same
    // queue. A reprint that took a different route would be the one that
    // printed differently, and the whole point of the stamp is that this slip
    // is recognisably the same document as the original.
    final session = ref.read(sessionProvider).valueOrNull;
    final outcome = await ref
        .read(receiptPrinterProvider)
        .printReceipt(
          ReceiptDocument.of(
            ReceiptData.fromOrder(widget.detail, refunds: widget.refunds),
            strings: ref.read(stringsProvider),
            profile:
                ref.read(receiptProfileProvider).valueOrNull ??
                const ReceiptProfile(branchId: 0),
            tenantName: session?.tenantName ?? '',
            terminalCode: session?.terminalCode ?? '',
            // The person who sold it, not the person reprinting — see the
            // preview above.
            cashierName: order.servedByName ?? '—',
            tenderMethods:
                ref.read(tenderTypesProvider).valueOrNull ??
                TenderMethod.seeded,
            logo: logo,
          ),
          isReprint: true,
          // A reprint never kicks the drawer. No money is moving, and a drawer
          // that springs open on a copy of an old receipt is a drawer standing
          // open for nobody.
          orderId: order.id,
          invoiceNumber: order.invoiceNumber,
        );

    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }
}

/// Permission, preview, record, print.
abstract final class ReprintFlow {
  /// What happened to the paper, or null when the reprint did not go ahead.
  static Future<PrintOutcome?> run(
    BuildContext context,
    WidgetRef ref, {
    required OrderRecordDetail detail,
    required List<Refund> refunds,
  }) async {
    final strings = context.strings;

    final decision = await requestPermission(
      context,
      ref,
      PosCapability.receiptReprint,
      action: strings.receiptReprintTitle(detail.order.invoiceNumber),
      auditAction: AuditAction.receiptReprinted,
      entityType: 'order',
      entityId: '${detail.order.id}',
      subjectLabel: strings.receiptTotal,
      subject: detail.order.total.format(withCurrency: true),
      approveLabel: strings.receiptReprintConfirm,
    );
    if (!context.mounted || decision is! Allowed) return null;

    return ReprintDialog.show(
      context,
      detail: detail,
      refunds: refunds,
      approvedBy: decision.approvedBy,
    );
  }
}
