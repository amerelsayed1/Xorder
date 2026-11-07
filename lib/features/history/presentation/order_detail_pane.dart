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
import '../../admin/presentation/admin_messages.dart';
import '../../receipt/receipt_printing.dart';
import '../../receipt/receipt_preview_dialog.dart';
import '../../receipt/reprint_dialog.dart';
import '../../refund/presentation/refund_sheet.dart';
import 'history_widgets.dart' show reasonInReaderLanguage;
import 'order_status_chip.dart';
import 'payment_status_chip.dart';

/// One order, opened from the list.
///
/// Everything here is **read**. There is no `totals` recomputation anywhere in
/// this file: the subtotal, service, VAT and total are the numbers written at
/// sale time, printed on a receipt somebody may be holding. Recomputing them
/// from today's tax configuration would quietly produce a different bill from
/// the one that was paid, which is the failure history exists to prevent.
///
/// A7 (reprint) and A5 (refund) attach their actions to the footer.
///
/// Below the money: every refund against the sale with what it took back, and
/// the sale's activity — printed, reprinted, voided, refunded — so "did the
/// customer get a receipt, and who gave the money back" is answered on one
/// pane rather than in the audit screen with a date filter (plan 17 S1).
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
              if (detail.events.isNotEmpty) ...[
                const SizedBox(height: PosSpace.md),
                MicroLabel(strings.orderDetailActivity),
                const SizedBox(height: PosSpace.xs),
                for (final event in detail.events) SaleEventRow(event: event),
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
              const SizedBox(width: 6),
              PaymentStatusChip(order.paymentStatus),
            ],
          ),
          const SizedBox(height: PosSpace.xs),
          Text(where, style: PosText.ui(size: 12.5, color: pos.muted)),
          if (order.businessDate != null || order.terminalName != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                if (order.terminalName case final till?)
                  Expanded(
                    child: Text(
                      '${strings.orderDetailTerminal}: $till',
                      overflow: TextOverflow.ellipsis,
                      style: PosText.ui(size: 12.5, color: pos.muted),
                    ),
                  )
                else
                  const Spacer(),
                // The trading day, when it differs in meaning from the stamp
                // below: a sale at 01:30 belongs to the night before, and
                // this is the line that says so.
                if (order.businessDate case final day?) ...[
                  Text(
                    '${strings.orderDetailBusinessDay} ',
                    style: PosText.ui(size: 12.5, color: pos.muted),
                  ),
                  MonoCode(_date(day), size: 11.5),
                ],
              ],
            ),
          ],
          // Who it was for, when it was for anybody: name and phone on one line,
          // the email under it. Absent for the sale to nobody in particular,
          // which is most of them — a "Customer: —" line on every sale would be
          // noise on the screen that is read for the money.
          if (order.customerName case final customer?) ...[
            const SizedBox(height: 2),
            Row(
              key: const Key('order-detail-customer'),
              children: [
                Expanded(
                  child: Text(
                    '${strings.customersColumnCustomer}: $customer',
                    overflow: TextOverflow.ellipsis,
                    style: PosText.ui(size: 12.5, color: pos.muted),
                  ),
                ),
                if (order.customerPhone case final phone?)
                  MonoCode(phone, size: 11.5),
              ],
            ),
            if (order.customerEmail case final email?
                when email.trim().isNotEmpty)
              Text(
                email,
                key: const Key('order-detail-customer-email'),
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(size: 12, color: pos.muted),
              ),
          ],
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
  /// A business that never filled in the Arabic name should still see the
  /// English on an Arabic till — a blank where a reason belongs looks like a
  /// void nobody gave a reason for, which is the opposite of the truth.
  static String? _reasonFor(BuildContext context, OrderRecord order) =>
      reasonInReaderLanguage(
        context,
        english: order.voidReason,
        arabic: order.voidReasonAr,
      );

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

  Widget _refundHead(BuildContext context, AppStrings strings, Refund refund) {
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

  /// A refund, with what it took back and where the money went.
  ///
  /// The lines are the refund's own snapshot — the quantity and price given
  /// back, not the order line's — so a partial refund reads as the part it
  /// was. An amount-only refund has no lines and shows none; its tenders are
  /// still the answer to "back to the card, or cash?".
  Widget _refund(BuildContext context, AppStrings strings, Refund refund) {
    final pos = context.pos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _refundHead(context, strings, refund),
        for (final line in refund.lines)
          Padding(
            key: ValueKey('refund-line-${refund.id}-${line.orderLineId}'),
            padding: const EdgeInsetsDirectional.only(start: PosSpace.md),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: MonoCode('${line.quantity}', size: 11.5),
                ),
                Expanded(
                  child: Text(
                    line.name,
                    overflow: TextOverflow.ellipsis,
                    style: PosText.ui(size: 11.5, color: pos.body),
                  ),
                ),
                MonoAmount(-line.lineTotal, size: 11.5, color: pos.muted),
              ],
            ),
          ),
        for (final (index, tender) in refund.payments.indexed)
          Padding(
            key: ValueKey('refund-tender-${refund.id}-$index'),
            padding: const EdgeInsetsDirectional.only(start: PosSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tenderName(tender.tenderTypeId, tender.label, strings),
                    overflow: TextOverflow.ellipsis,
                    style: PosText.ui(size: 11.5, color: pos.muted),
                  ),
                ),
                MonoAmount(tender.amount, size: 11.5, color: pos.muted),
              ],
            ),
          ),
      ],
    );
  }

  /// The refund's reason in the reader's language, same fallback rule as a
  /// void's.
  static String? _reasonOf(BuildContext context, Refund refund) =>
      reasonInReaderLanguage(
        context,
        english: refund.reasonName,
        arabic: refund.reasonNameAr,
      );

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
    // Asked of the person ACTING, not `canProvider`'s till operator: inside
    // the back office's Sales tab that is whoever came through Admin Mode's
    // door, and the till behind it may be locked with nobody signed in. The
    // same permissions as before — only the person they are asked of moved.
    final by = ref.watch(actingStaffProvider);
    final mayRefund =
        Authorization.check(by, PosCapability.orderRefund) is! Denied;
    final anythingLeft =
        detail.order.status.tookMoney &&
        detail.order.total.minor >
            refunds.fold<int>(0, (sum, r) => sum + r.total.minor);

    final mayReprint =
        Authorization.check(by, PosCapability.receiptReprint) is! Denied;

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        border: BorderDirectional(top: context.pos.hairline),
      ),
      child: Row(
        children: [
          // Looking costs nothing — no paper, no audit row — so anybody who
          // can open the order can see its receipt.
          // Weighted by what each says: "Reprint the invoice" is the longest
          // label and was cut to "إعادة طباعة الفا…" in three equal thirds.
          Expanded(
            flex: 5,
            child: PosButton(
              key: const Key('order-receipt-preview'),
              label: strings.receiptPreviewAction,
              border: Border.fromBorderSide(pos.resting),
              onPressed: () => ReceiptPreviewDialog.show(
                context,
                detail: detail,
                refunds: refunds,
              ),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          if (mayReprint)
            Expanded(
              flex: 9,
              child: PosButton(
                label: strings.receiptReprintAction,
                border: Border.fromBorderSide(pos.resting),
                onPressed: () => _reprintFlow(context, ref, refunds),
              ),
            ),
          if (mayReprint && mayRefund) const SizedBox(width: PosSpace.sm),
          if (mayRefund)
            Expanded(
              flex: 5,
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
            ),
        ],
      ),
    );
  }

  /// A reprint is offered on **any** order, including a voided one.
  ///
  /// Somebody asking for a copy of a slip that was voided is asking a fair
  /// question, and the paper answers it — the void is on the record and the
  /// stamp says the document is a copy. Withholding it would only send them to
  /// the manager.
  Future<void> _reprintFlow(
    BuildContext context,
    WidgetRef ref,
    List<Refund> refunds,
  ) async {
    final outcome = await ReprintFlow.run(
      context,
      ref,
      detail: detail,
      refunds: refunds,
    );
    if (outcome == null || !context.mounted) return;
    // What happened to the paper, not "sent, and recorded". Half of that
    // sentence was a guess made when nothing in the product printed at all.
    posToast(context, printOutcomeMessage(context.strings, outcome));
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
    // And the figures over it: a refund turns PAID into PART REFUNDED, and a
    // full one takes the sale out of the total.
    ref.invalidate(orderHistorySummaryProvider);
    // And Returns, which has a row more.
    ref.invalidate(refundHistoryProvider);
    ref.invalidate(refundHistorySummaryProvider);
    posToast(context, context.strings.refundIssued(given.format(withCurrency: true)));
  }

  static String _stamp(DateTime at) =>
      '${_date(at)} ${_two(at.hour)}:${_two(at.minute)}';

  static String _date(DateTime at) =>
      '${at.year}-${_two(at.month)}-${_two(at.day)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// One line of a sale's activity.
///
/// Public so a test can find the rows by type and read the kind off them,
/// rather than matching words that also appear in the status chips above.
class SaleEventRow extends StatelessWidget {
  const SaleEventRow({super.key, required this.event});

  final SaleEvent event;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final who = [
      ?event.actorName,
      if (event.approvedByName case final approver?)
        strings.orderDetailApprovedBy(approver),
    ].join(' · ');
    final at = event.at;
    String two(int value) => value.toString().padLeft(2, '0');

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
                  label(strings, event),
                  style: PosText.ui(
                    size: 12.5,
                    color: _pending ? pos.warn : pos.ink,
                  ),
                ),
                if (who.isNotEmpty)
                  Text(who, style: PosText.ui(size: 11.5, color: pos.muted)),
              ],
            ),
          ),
          if (event.amount case final amount?) ...[
            MonoAmount(-amount, size: 12.5, color: pos.warn),
            const SizedBox(width: PosSpace.sm),
          ],
          MonoCode(
            '${at.year}-${two(at.month)}-${two(at.day)} '
            '${two(at.hour)}:${two(at.minute)}',
            size: 11.5,
          ),
        ],
      ),
    );
  }

  /// Paper still owed to a customer is the one row here that wants action.
  bool get _pending => switch (event.kind) {
    SaleEventKind.printPending || SaleEventKind.reprintPending => true,
    SaleEventKind.printed ||
    SaleEventKind.reprinted ||
    SaleEventKind.reprintRequested ||
    SaleEventKind.voided ||
    SaleEventKind.refunded ||
    SaleEventKind.audit => false,
  };

  /// Keyed by the enum, so a new kind is a compile error here. An audit row
  /// takes the Activity pane's own label for its action — one wording for one
  /// act, whichever screen shows it.
  static String label(AppStrings s, SaleEvent event) => switch (event.kind) {
    SaleEventKind.printed => s.saleEventPrinted,
    SaleEventKind.printPending => s.saleEventPrintPending,
    SaleEventKind.reprinted => s.saleEventReprinted,
    SaleEventKind.reprintPending => s.saleEventReprintPending,
    SaleEventKind.reprintRequested => s.saleEventReprintRequested,
    SaleEventKind.voided => s.saleEventVoided,
    SaleEventKind.refunded => s.saleEventRefunded,
    SaleEventKind.audit => AdminText.auditAction(s, event.auditAction ?? ''),
  };
}
