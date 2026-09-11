import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/order_record.dart';
import '../../domain/models/receipt_profile.dart';
import '../../domain/models/refund.dart';
import 'receipt_data.dart';
import 'receipt_paper.dart';

/// A sale's receipt, on screen, exactly as it would print — and nothing more.
///
/// Not a reprint: nothing goes to the printer and nothing is recorded, so it
/// needs no permission. Looking at what a customer was given is how most
/// "what did I pay for" questions are answered, and it should not cost a
/// sheet of paper and an audit row to answer one.
class ReceiptPreviewDialog extends ConsumerWidget {
  const ReceiptPreviewDialog({
    super.key,
    required this.detail,
    required this.refunds,
  });

  final OrderRecordDetail detail;
  final List<Refund> refunds;

  static Future<void> show(
    BuildContext context, {
    required OrderRecordDetail detail,
    required List<Refund> refunds,
  }) => showDialog<void>(
    context: context,
    barrierColor: context.pos.scrimHeavy,
    builder: (_) => ReceiptPreviewDialog(detail: detail, refunds: refunds),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  child: ReceiptPaper(
                    data: ReceiptData.fromOrder(detail, refunds: refunds),
                    profile:
                        ref.watch(receiptProfileProvider).valueOrNull ??
                        const ReceiptProfile(branchId: 0),
                    tenantName: session?.tenantName ?? '',
                    terminalCode: session?.terminalCode ?? '',
                    // The person who sold it, as on the original.
                    cashierName: detail.order.servedByName ?? '—',
                  ),
                ),
              ),
              const SizedBox(height: PosSpace.md),
              Text(
                strings.receiptPreviewNote,
                textAlign: TextAlign.center,
                style: PosText.ui(size: 12, color: receiptPalette.body),
              ),
              const SizedBox(height: PosSpace.md),
              SizedBox(
                width: double.infinity,
                child: PosButton(
                  label: strings.close,
                  height: 48,
                  border: Border.fromBorderSide(
                    BorderSide(color: receiptPalette.inkWarm),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
