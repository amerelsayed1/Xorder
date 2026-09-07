import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/order_record.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/refund.dart';
import '../../../domain/services/authorization.dart';
import '../../refund/presentation/refund_sheet.dart';
import 'order_status_chip.dart';

/// One order, opened from the list.
///
/// Everything here is **read**. There is no `totals` recomputation anywhere in
/// this file: the subtotal, service, VAT and total are the numbers written at
/// sale time, printed on a receipt somebody may be holding. Recomputing them
/// from today's tax configuration would quietly produce a different bill from
/// the one that was paid, which is the failure history exists to prevent.
///
/// A7 (reprint) and A5 (refund) attach their actions to the footer.
class OrderDetailPane extends ConsumerWidget {
  const OrderDetailPane({super.key, required this.orderId});

  /// Null when nothing is selected.
  final int? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final id = orderId;
    if (id == null) return _placeholder(context, strings.orderHistoryPickAnOrder);

    return ref
        .watch(orderDetailProvider(id))
        .when(
          loading: () => Center(
            child: CircularProgressIndicator(color: context.pos.accent),
          ),
          error: (error, _) => _placeholder(context, '$error'),
          // Null means the row is no longer there — somebody else's till may
          // have been mid-something. A "gone" reads better than an exception.
          data: (detail) => detail == null
              ? _placeholder(context, strings.orderHistoryPickAnOrder)
              : _Detail(detail: detail),
        );
  }

  Widget _placeholder(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.xl),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: PosText.ui(size: 13.5, color: context.pos.muted),
      ),
    ),
  );
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.detail});

  final OrderRecordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final order = detail.order;
    final refunds =
        ref.watch(refundsForOrderProvider(order.id)).valueOrNull ??
        const <Refund>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _head(context, strings, order),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              PosSpace.md,
              PosSpace.md,
              PosSpace.md,
              PosSpace.xl,
            ),
            children: [
              if (order.isVoided) _voidBand(context, strings, order),
              MicroLabel(strings.orderDetailLines),
              const SizedBox(height: PosSpace.xs),
              for (final line in detail.lines) _line(context, strings, line),
              if (detail.discounts.isNotEmpty) ...[
                const SizedBox(height: PosSpace.md),
                MicroLabel(strings.orderDetailDiscounts),
                const SizedBox(height: PosSpace.xs),
                for (final discount in detail.discounts)
                  _discount(context, strings, discount),
              ],
              const SizedBox(height: PosSpace.md),
              _totals(context, strings, order),
              const SizedBox(height: PosSpace.md),
              MicroLabel(strings.orderDetailPayments),
              const SizedBox(height: PosSpace.xs),
              if (detail.payments.isEmpty)
                Text(
                  strings.orderDetailNoPayments,
                  style: PosText.ui(size: 12.5, color: context.pos.muted),
                )
              else
                for (final payment in detail.payments)
                  _payment(context, payment),
              if (refunds.isNotEmpty) ...[
                const SizedBox(height: PosSpace.md),
                MicroLabel(strings.refundsAlreadyGiven),
                const SizedBox(height: PosSpace.xs),
                for (final refund in refunds) _refund(context, strings, refund),
              ],
            ],
          ),
        ),
        _actions(context, ref, strings, refunds),
      ],
    );
  }

  Widget _head(BuildContext context, AppStrings strings, OrderRecord order) {
    final pos = context.pos;
    final where = [
      order.orderType.label(strings),
      if (order.tableLabel != null) order.tableLabel!,
      if (order.guestCount != null) strings.orderDetailGuests(order.guestCount!),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        border: BorderDirectional(bottom: context.pos.resting),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: MonoCode(
                  order.invoiceNumber,
                  size: 15,
                  weight: FontWeight.w600,
                  color: pos.ink,
                ),
              ),
              OrderStatusChip(order.status),
            ],
          ),
          const SizedBox(height: PosSpace.xs),
          Text(where, style: PosText.ui(size: 12.5, color: pos.muted)),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${strings.orderDetailServedBy}: '
                  '${order.servedByName ?? strings.orderDetailServedByUnknown}',
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(size: 12.5, color: pos.muted),
                ),
              ),
              MonoCode(_stamp(order.occurredAt), size: 11.5),
            ],
          ),
        ],
      ),
    );
  }

  Widget _voidBand(
    BuildContext context,
    AppStrings strings,
    OrderRecord order,
  ) {
    final pos = context.pos;
    final reason = _reasonFor(context, order);
    return Container(
      margin: const EdgeInsets.only(bottom: PosSpace.md),
      padding: const EdgeInsets.all(PosSpace.sm),
      decoration: BoxDecoration(
        color: pos.dangerSoft,
        border: BorderDirectional(
          start: BorderSide(color: pos.danger, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.orderDetailVoidedBy(order.voidedByName ?? '—'),
            style: PosText.ui(size: 12.5, weight: FontWeight.w600, color: pos.danger),
          ),
          if (reason != null)
            Text(reason, style: PosText.ui(size: 12.5, color: pos.body)),
          if (order.voidNote != null && order.voidNote!.trim().isNotEmpty)
            Text(
              order.voidNote!,
              style: PosText.ui(size: 12.5, color: pos.muted),
            ),
        ],
      ),
    );
  }

  /// The reason in the reader's language, falling back to the other one.
  ///
  /// A restaurant that never filled in the Arabic name should still see the
  /// English on an Arabic till — a blank where a reason belongs looks like a
  /// void nobody gave a reason for, which is the opposite of the truth.
  static String? _reasonFor(BuildContext context, OrderRecord order) {
    final arabic = Directionality.of(context) == TextDirection.rtl;
    final preferred = arabic ? order.voidReasonAr : order.voidReason;
    final fallback = arabic ? order.voidReason : order.voidReasonAr;
    final chosen = (preferred?.trim().isNotEmpty ?? false)
        ? preferred
        : fallback;
    return (chosen?.trim().isNotEmpty ?? false) ? chosen : null;
  }

  Widget _line(BuildContext context, AppStrings strings, OrderRecordLine line) {
    final pos = context.pos;
    final voided = line.isVoided;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: MonoCode(
              '${line.quantity}',
              size: 12.5,
              color: voided ? pos.muted : pos.ink,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: PosText.ui(
                    size: 12.5,
                    color: voided ? pos.muted : pos.ink,
                  ).copyWith(
                    decoration: voided ? TextDecoration.lineThrough : null,
                    decorationColor: pos.danger,
                  ),
                ),
                if (line.modifierSummary != null &&
                    line.modifierSummary!.isNotEmpty)
                  Text(
                    line.modifierSummary!,
                    style: PosText.ui(size: 11.5, color: pos.muted),
                  ),
                if (line.note != null && line.note!.trim().isNotEmpty)
                  Text(
                    line.note!,
                    style: PosText.ui(size: 11.5, color: pos.muted),
                  ),
                if (voided)
                  Text(
                    line.voidedByName == null
                        ? strings.orderDetailVoidedLine
                        : '${strings.orderDetailVoidedLine} · '
                              '${line.voidedByName}',
                    style: PosText.mono(size: 10.5, color: pos.danger),
                  ),
              ],
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          MonoAmount(
            line.lineTotal,
            size: 12.5,
            color: voided ? pos.muted : pos.ink,
          ),
        ],
      ),
    );
  }

  Widget _discount(
    BuildContext context,
    AppStrings strings,
    OrderRecordDiscount discount,
  ) {
    final pos = context.pos;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  discount.name,
                  style: PosText.ui(size: 12.5, color: pos.ink),
                ),
                // Both people, when there were two. A discount somebody had to
                // authorise is the one a manager will ask about later, and the
                // approver's name is the answer.
                if (discount.approvedByName != null)
                  Text(
                    strings.orderDetailApprovedBy(discount.approvedByName!),
                    style: PosText.ui(size: 11.5, color: pos.muted),
                  )
                else if (discount.appliedByName != null)
                  Text(
                    discount.appliedByName!,
                    style: PosText.ui(size: 11.5, color: pos.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          MonoAmount(-discount.amount, size: 12.5, color: pos.danger),
        ],
      ),
    );
  }

  Widget _totals(BuildContext context, AppStrings strings, OrderRecord order) {
    final pos = context.pos;
    Widget row(String label, Money value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PosText.ui(
                size: strong ? 13.5 : 12.5,
                weight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? pos.ink : pos.muted,
              ),
            ),
          ),
          MonoAmount(
            value,
            size: strong ? 15 : 12.5,
            weight: strong ? FontWeight.w700 : FontWeight.w400,
            color: pos.ink,
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      decoration: BoxDecoration(
        border: BorderDirectional(top: pos.hairline, bottom: pos.hairline),
      ),
      child: Column(
        children: [
          row(strings.orderDetailSubtotal, order.subtotal),
          if (order.discount.minor != 0)
            row(strings.orderDetailDiscount, -order.discount),
          if (order.service.minor != 0)
            row(strings.orderDetailService, order.service),
          row(strings.orderDetailVat, order.vat),
          const SizedBox(height: 2),
          row(strings.orderDetailTotal, order.total, strong: true),
        ],
      ),
    );
  }

  Widget _payment(BuildContext context, OrderRecordPayment payment) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            payment.label,
            style: PosText.ui(size: 12.5, color: context.pos.ink),
          ),
        ),
        MonoAmount(payment.amount, size: 12.5),
      ],
    ),
  );

  Widget _refund(BuildContext context, AppStrings strings, Refund refund) {
    final pos = context.pos;
    final who = refund.refundedByName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _reasonOf(context, refund) ?? strings.refundAction,
                  style: PosText.ui(size: 12.5, color: pos.ink),
                ),
                Text(
                  [
                    _stamp(refund.occurredAt),
                    if (who != null) strings.refundGivenBy(who),
                    // The approver, when there was one. A refund somebody had
                    // to authorise is the one a manager asks about later.
                    if (refund.approvedByName != null)
                      strings.orderDetailApprovedBy(refund.approvedByName!),
                  ].join(' · '),
                  style: PosText.ui(size: 11.5, color: pos.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          MonoAmount(-refund.total, size: 12.5, color: pos.warn),
        ],
      ),
    );
  }

  /// The refund's reason in the reader's language, same fallback rule as a
  /// void's.
  static String? _reasonOf(BuildContext context, Refund refund) {
    final arabic = Directionality.of(context) == TextDirection.rtl;
    final preferred = arabic ? refund.reasonNameAr : refund.reasonName;
    final fallback = arabic ? refund.reasonName : refund.reasonNameAr;
    final chosen = (preferred?.trim().isNotEmpty ?? false)
        ? preferred
        : fallback;
    return (chosen?.trim().isNotEmpty ?? false) ? chosen : null;
  }

  /// What can still be done to this order.
  ///
  /// Refund is offered only when there is something to refund and the person at
  /// the till may do it. Hidden rather than greyed for a cashier who never
  /// holds `order.refund` — but *disabled* when the order simply has nothing
  /// left, because that is a fact about this order rather than about them, and
  /// a control that vanishes teaches nothing.
  Widget _actions(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
    List<Refund> refunds,
  ) {
    final pos = context.pos;
    final mayRefund =
        ref.watch(canProvider(PosCapability.orderRefund)) is! Denied;
    final anythingLeft =
        detail.order.status.tookMoney &&
        detail.order.total.minor >
            refunds.fold<int>(0, (sum, r) => sum + r.total.minor);

    // Nothing to offer and nothing to explain: a footer bar with a sentence
    // about a permission somebody does not hold is a footer bar that is there
    // all day saying nothing useful. A7's reprint lands here next.
    if (!mayRefund) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        border: BorderDirectional(top: context.pos.hairline),
      ),
      child: PosButton(
        label: strings.refundAction,
        border: Border.fromBorderSide(
          anythingLeft ? BorderSide(color: pos.danger) : pos.resting,
        ),
        foreground: anythingLeft ? pos.danger : pos.muted,
        fontWeight: FontWeight.w700,
        onPressed: anythingLeft
            ? () => _refundFlow(context, ref, refunds)
            : null,
      ),
    );
  }

  Future<void> _refundFlow(
    BuildContext context,
    WidgetRef ref,
    List<Refund> refunds,
  ) async {
    final given = await RefundSheet.show(
      context,
      detail: detail,
      previous: refunds,
    );
    if (given == null || !context.mounted) return;

    // Both are stale now: the order's status and its lines' refunded quantities
    // changed underneath us, and the refund list gained a row. Re-read rather
    // than patching what is on screen — the database is what the next refund
    // will be checked against.
    ref.invalidate(refundsForOrderProvider(detail.order.id));
    ref.invalidate(orderDetailProvider(detail.order.id));
    // The whole family, because the list beside this pane is keyed by whatever
    // filters are set and this pane does not know which entry is on screen. A
    // row still reading PAID next to an order that has just been refunded is
    // the kind of stale that gets refunded twice.
    ref.invalidate(orderHistoryProvider);
    posToast(context, context.strings.refundIssued(given.format(withCurrency: true)));
  }

  static String _stamp(DateTime at) =>
      '${at.year}-${_two(at.month)}-${_two(at.day)} '
      '${_two(at.hour)}:${_two(at.minute)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
