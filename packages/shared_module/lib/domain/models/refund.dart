/// Money going back to a customer.
///
/// A refund is not a negative sale. It references the sale it reverses, it can
/// only ever give back what that sale took, and it carries its own reason and
/// its own two names — who issued it and, above the threshold, who allowed it.
/// Every one of those is a property the database holds rather than a promise
/// this file makes; see migration 12.
library;

import '../../core/money/money.dart';
import 'pos_settings.dart';

/// Whether this refund clears the order or only part of it.
///
/// Derived, never chosen: it is `full` when nothing is left to give back
/// afterwards. Letting an operator declare it would allow a "full" refund of
/// half a bill, which is exactly the row a report would then mis-total.
enum RefundKind {
  full('full'),
  partial('partial');

  const RefundKind(this.wire);

  final String wire;

  static RefundKind? fromWire(String value) {
    for (final kind in RefundKind.values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// How long after a sale a refund may still be issued (§18).
enum RefundWindow {
  sameShift('same_shift'),
  sameDay('same_day'),
  days7('7d'),
  days30('30d'),
  unlimited('unlimited');

  const RefundWindow(this.wire);

  final String wire;

  static RefundWindow? fromWire(String value) {
    for (final window in RefundWindow.values) {
      if (window.wire == value) return window;
    }
    return null;
  }
}

/// The business's refund rules.
///
/// §18 specifies these as **settings**, scoped to the business. The scoped
/// `pos_settings` table is Wave D, so this is a value object with the SRS's own
/// defaults today and a single place to change when it exists — rather than six
/// literals spread across a dialog. Nothing else in the product should ask
/// "what is the refund limit"; it should ask this.
class RefundPolicy {
  const RefundPolicy({
    this.enabled = true,
    this.window = RefundWindow.days7,
    this.maxValue,
    this.approvalThreshold,
    this.receiptRequired = false,
    this.reasonRequired = true,
  });

  /// The shape a business gets before anybody configures anything.
  ///
  /// A 7-day window rather than `unlimited`: the specification offers both, and
  /// the safe default for money leaving a drawer is the one that expires.
  static const defaults = RefundPolicy();

  /// Read from what the business configured, falling back to [defaults] key
  /// by key.
  ///
  /// Partial configuration is the normal case — somebody sets a ceiling and
  /// nothing else — so every key falls back on its own rather than the whole
  /// object reverting when one is missing.
  factory RefundPolicy.from(PosSettings settings) => RefundPolicy(
    enabled: settings.boolean(SettingKey.refundEnabled, orElse: true),
    window:
        RefundWindow.fromWire(settings.text(SettingKey.refundWindow) ?? '') ??
        RefundWindow.days7,
    maxValue: settings.money(SettingKey.refundMaxValue),
    approvalThreshold: settings.money(SettingKey.refundApprovalThreshold),
    receiptRequired: settings.boolean(
      SettingKey.refundReceiptRequired,
      orElse: false,
    ),
    reasonRequired: settings.boolean(
      SettingKey.refundReasonRequired,
      orElse: true,
    ),
  );

  final bool enabled;
  final RefundWindow window;

  /// The most one refund may give back. Null means no ceiling.
  final Money? maxValue;

  /// Above this, somebody else has to say yes. Null means never.
  final Money? approvalThreshold;

  /// The original receipt has to be produced. Not enforceable by software —
  /// carried so the dialog can say it, which is the whole of what a till can do
  /// about a piece of paper.
  final bool receiptRequired;

  final bool reasonRequired;

  /// Whether [issuedAt] is still inside the window for a sale at [soldAt].
  ///
  /// [sameShift] is answered by the caller, because a shift is a row this
  /// object cannot see. Passing it in rather than guessing keeps the one
  /// question that needs a database out of a value object that needs none.
  bool allowsAt(
    DateTime soldAt, {
    required DateTime issuedAt,
    bool sameShift = false,
  }) {
    if (!enabled) return false;
    return switch (window) {
      RefundWindow.unlimited => true,
      RefundWindow.sameShift => sameShift,
      RefundWindow.sameDay =>
        soldAt.year == issuedAt.year &&
            soldAt.month == issuedAt.month &&
            soldAt.day == issuedAt.day,
      RefundWindow.days7 => !issuedAt.isAfter(
        soldAt.add(const Duration(days: 7)),
      ),
      RefundWindow.days30 => !issuedAt.isAfter(
        soldAt.add(const Duration(days: 30)),
      ),
    };
  }

  bool needsApproval(Money amount) {
    final threshold = approvalThreshold;
    return threshold != null && amount.minor > threshold.minor;
  }

  bool permits(Money amount) {
    final ceiling = maxValue;
    return ceiling == null || amount.minor <= ceiling.minor;
  }
}

/// One line, and how much of it is coming back.
class RefundLineSelection {
  const RefundLineSelection({
    required this.orderLineId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  /// `pos_order_lines.id`. The refund references the row, not the line key —
  /// two orders can carry the same key and only one of them is being refunded.
  final int orderLineId;

  /// The snapshot, carried forward again so a refund receipt reads like the
  /// sale receipt did.
  final String name;

  final int quantity;
  final Money unitPrice;

  Money get lineTotal => unitPrice * quantity;
}

/// Where the money went back to.
class RefundTender {
  const RefundTender({
    required this.tenderTypeId,
    required this.label,
    required this.amount,
    this.reference,
  });

  final int tenderTypeId;
  final String label;
  final Money amount;
  final String? reference;
}

/// A refund, read back from the ledger.
class Refund {
  const Refund({
    required this.id,
    required this.clientRefundId,
    required this.orderId,
    required this.kind,
    required this.subtotal,
    required this.discount,
    required this.service,
    required this.vat,
    required this.total,
    required this.occurredAt,
    this.reasonName,
    this.reasonNameAr,
    this.note,
    this.refundedByName,
    this.approvedByName,
    this.lines = const [],
    this.payments = const [],
  });

  final int id;
  final String clientRefundId;
  final int orderId;
  final RefundKind kind;

  final Money subtotal;
  final Money discount;
  final Money service;
  final Money vat;
  final Money total;

  final DateTime occurredAt;
  final String? reasonName;
  final String? reasonNameAr;
  final String? note;
  final String? refundedByName;

  /// Set only when the amount was above the threshold and somebody else said
  /// yes. That it is usually null is what makes the times it is not worth
  /// reading.
  final String? approvedByName;

  final List<RefundLineSelection> lines;
  final List<RefundTender> payments;

  /// A refund with no lines — an amount given back against the bill as a whole
  /// rather than against particular items.
  bool get isAmountOnly => lines.isEmpty;
}
