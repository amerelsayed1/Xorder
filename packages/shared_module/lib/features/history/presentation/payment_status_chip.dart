import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../domain/services/payment_status.dart';

/// Where a payment status becomes a word.
///
/// Keyed by the enum, not the wire string, so a sixth status is a compile
/// error here rather than a blank chip.
extension PaymentStatusLabel on PaymentStatus {
  String label(AppStrings s) => switch (this) {
    PaymentStatus.unpaid => s.paymentStatusUnpaid,
    PaymentStatus.partiallyPaid => s.paymentStatusPartiallyPaid,
    PaymentStatus.paid => s.paymentStatusPaid,
    PaymentStatus.partiallyRefunded => s.paymentStatusPartiallyRefunded,
    PaymentStatus.refunded => s.paymentStatusRefunded,
  };
}

/// The money half of a sale's status, drawn beside [OrderStatusChip].
///
/// Its own widget, not a second mode of the order chip: SALES-§8 asks for two
/// concepts, and one widget switching between them is how the two end up
/// rendered as one.
///
/// **Paid is quiet**, for the same reason a paid order is: it is nearly every
/// row, and the exceptions are what a person is scanning for. **Unpaid is not
/// red.** Today the only sales that take no money are voided ones, whose order
/// chip is already red — a second red chip beside it would say the same thing
/// twice and make the row look like two problems. Part paid is the one that
/// means money is still owed, so it carries the warning.
class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip(this.status, {super.key});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;

    final (Color background, Color foreground) = switch (status) {
      PaymentStatus.paid => (Colors.transparent, pos.muted),
      PaymentStatus.unpaid => (pos.accentSoft, pos.inkWarm),
      PaymentStatus.partiallyPaid ||
      PaymentStatus.partiallyRefunded ||
      PaymentStatus.refunded => (pos.warnSoft, pos.warn),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        border: background == Colors.transparent
            ? null
            : Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.label(context.strings).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PosText.mono(
          size: 10.5,
          weight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
