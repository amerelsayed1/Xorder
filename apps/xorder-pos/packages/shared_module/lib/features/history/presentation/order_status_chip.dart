import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../domain/models/order_record.dart';

/// Where an order's status becomes a word and a colour.
extension OrderStatusLabel on OrderStatus {
  String label(AppStrings s) => switch (this) {
    OrderStatus.draft => s.orderStatusDraft,
    OrderStatus.open => s.orderStatusOpen,
    OrderStatus.sentToKitchen => s.orderStatusSentToKitchen,
    OrderStatus.ready => s.orderStatusReady,
    OrderStatus.paid => s.orderStatusPaid,
    OrderStatus.closed => s.orderStatusClosed,
    OrderStatus.voided => s.orderStatusVoided,
    OrderStatus.cancelled => s.orderStatusCancelled,
    OrderStatus.refunded => s.orderStatusRefunded,
    OrderStatus.partiallyRefunded => s.orderStatusPartiallyRefunded,
  };
}

/// The status of one order, as a chip.
///
/// **A paid order is not coloured.** It is the overwhelming majority of every
/// list, and a list where every row is tinted green is one where nothing stands
/// out — the exceptions are what a person is scanning for, so the exceptions are
/// what carry colour. This is the same rule the sync pill follows: normal is
/// quiet.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;

    // Voided and cancelled are danger; a refund is a warning, not a failure —
    // money going back is a normal outcome that somebody nonetheless wants to
    // see. Everything in flight is neutral.
    final (Color background, Color foreground) = switch (status) {
      OrderStatus.voided || OrderStatus.cancelled => (
        pos.dangerSoft,
        pos.danger,
      ),
      OrderStatus.refunded || OrderStatus.partiallyRefunded => (
        pos.warnSoft,
        pos.warn,
      ),
      OrderStatus.paid || OrderStatus.closed => (
        Colors.transparent,
        pos.muted,
      ),
      _ => (pos.accentSoft, pos.inkWarm),
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
        style: PosText.mono(size: 10.5, weight: FontWeight.w600, color: foreground),
      ),
    );
  }
}
