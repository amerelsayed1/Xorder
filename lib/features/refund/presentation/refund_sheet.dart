import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../core/ui/widgets/reason_picker.dart';
import '../../../domain/models/order_record.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/refund.dart';
import '../../../domain/services/authorization.dart';
import '../../../domain/services/refund_engine.dart';
import '../../admin/presentation/supervisor_override.dart';
import '../../../core/ui/widgets/fold_digits_formatter.dart';

const _uuid = Uuid();

/// Whether the operator is giving back items or a figure.
enum RefundBasis { items, amount }

/// Giving money back.
///
/// One dialog rather than a wizard. The specification describes five steps —
/// find the order, choose what, choose why, choose how it goes back, confirm —
/// and four of them are a single decision each. A cashier is doing this at a
/// counter with a customer in front of them, and four screens to hand back
/// 62.70 is three screens too many. The steps are sections; the running total
/// is visible throughout, which is what §18 actually asks for.
///
/// **Nothing here does arithmetic.** Every figure comes from [RefundEngine],
/// which works in shares of what the order charged and never recomputes a tax
/// rate. The dialog's job is to collect a selection and show what the engine
/// says it comes to.
class RefundSheet extends ConsumerStatefulWidget {
  const RefundSheet({
    super.key,
    required this.detail,
    required this.previous,
  });

  final OrderRecordDetail detail;

  /// Refunds already issued against this order. The engine needs them part by
  /// part, not merely as a total.
  final List<Refund> previous;

  /// Returns the amount given back, or null if nothing was.
  static Future<Money?> show(
    BuildContext context, {
    required OrderRecordDetail detail,
    required List<Refund> previous,
  }) => showDialog<Money>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => RefundSheet(detail: detail, previous: previous),
  );

  @override
  ConsumerState<RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<RefundSheet> {
  RefundBasis _basis = RefundBasis.items;
  final Map<int, int> _quantities = {};
  final _amount = TextEditingController();

  ReasonCode? _reason;
  String _note = '';
  int? _tenderTypeId;

  /// Generated once, when the dialog opens.
  ///
  /// Not per attempt: if the write times out and the cashier presses again, the
  /// second call must carry the *same* id so the database recognises a replay.
  /// A fresh id per press is how a customer gets paid twice.
  final String _clientRefundId = _uuid.v4();

  bool _busy = false;
  String? _message;

  OrderRecord get _order => widget.detail.order;

  @override
  void initState() {
    super.initState();
    // Money goes back the way it came. The selected method is the preferred
    // starting point, not permission to put a split bill's whole refund onto
    // one tender; [_refundTenders] allocates any remainder safely.
    final payments = widget.detail.payments;
    _tenderTypeId = payments.firstOrNull?.tenderTypeId;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Money get _zero => Money(
    0,
    currency: _order.total.currency,
    exponent: _order.total.exponent,
  );

  Money get _remaining {
    var given = _zero;
    for (final refund in widget.previous) {
      given += refund.total;
    }
    return (_order.total - given).clampToZero();
  }

  /// Allocate a refund across the order's original payments without returning
  /// more through any tender than it received.  Existing refunds consume a
  /// tender's balance first, so a second partial refund cannot silently undo
  /// the split of the first.
  List<RefundTender>? _refundTenders(Money total) {
    final preferred = _tenderTypeId;
    final payments = [
      for (final payment in widget.detail.payments)
        if (payment.tenderTypeId != null) payment,
    ]..sort((a, b) {
        final aPreferred = a.tenderTypeId == preferred;
        final bPreferred = b.tenderTypeId == preferred;
        if (aPreferred == bPreferred) return 0;
        return aPreferred ? -1 : 1;
      });
    if (payments.isEmpty) return null;

    final alreadyReturned = <int, int>{};
    for (final refund in widget.previous) {
      for (final payment in refund.payments) {
        alreadyReturned.update(
          payment.tenderTypeId,
          (amount) => amount + payment.amount.minor,
          ifAbsent: () => payment.amount.minor,
        );
      }
    }

    var left = total.minor;
    final allocated = <RefundTender>[];
    for (final payment in payments) {
      final typeId = payment.tenderTypeId!;
      final returned = alreadyReturned[typeId] ?? 0;
      final available = (payment.amount.minor - returned).clamp(
        0,
        payment.amount.minor,
      );
      alreadyReturned[typeId] = (returned - payment.amount.minor).clamp(
        0,
        returned,
      );
      final amount = left.clamp(0, available);
      if (amount == 0) continue;
      allocated.add(
        RefundTender(
          tenderTypeId: typeId,
          label: payment.label,
          amount: Money(
            amount,
            currency: total.currency,
            exponent: total.exponent,
          ),
          reference: payment.reference,
        ),
      );
      left -= amount;
      if (left == 0) return allocated;
    }
    return null;
  }

  /// What the engine says this selection comes to, or why it will not.
  (RefundQuote?, RefundRefusal?) get _quote {
    final policy = ref.read(refundPolicyProvider);
    final now = DateTime.now();

    if (_basis == RefundBasis.amount) {
      final typed = Money.tryParse(
        _amount.text,
        currency: _order.total.currency,
        exponent: _order.total.exponent,
      );
      if (typed == null) return (null, const NothingSelected());
      return RefundEngine.quoteForAmount(
        detail: widget.detail,
        gross: typed,
        previous: widget.previous,
        policy: policy,
        at: now,
        sameShift: _sameShift,
      );
    }

    return RefundEngine.quoteForLines(
      detail: widget.detail,
      quantities: _quantities,
      previous: widget.previous,
      policy: policy,
      at: now,
      sameShift: _sameShift,
    );
  }

  /// Whether the sale happened on the shift that is open now.
  ///
  /// A shift is a row the policy object cannot see, so the question is answered
  /// here and passed in. An order sold before the open shift started is not on
  /// it, whatever the clock says.
  bool get _sameShift {
    final shift = ref.read(shiftProvider).valueOrNull;
    if (shift == null) return false;
    return !_order.occurredAt.isBefore(shift.openedAt);
  }

  void _setQuantity(OrderRecordLine line, int quantity) {
    setState(() {
      _message = null;
      if (quantity <= 0) {
        _quantities.remove(line.id);
      } else {
        _quantities[line.id] = quantity.clamp(0, line.refundableQuantity);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final reasons =
        ref.watch(reasonCodesProvider(ReasonScope.refund)).valueOrNull ??
        const <ReasonCode>[];
    final (quote, refusal) = _quote;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.all(PosSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogRefund),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(strings, palette),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(PosSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _basisTabs(strings, palette),
                        const SizedBox(height: PosSpace.lg),
                        if (_basis == RefundBasis.items)
                          _items(strings, palette)
                        else
                          _amountField(strings, palette),
                        const SizedBox(height: PosSpace.lg),
                        _totals(strings, palette, quote),
                        const SizedBox(height: PosSpace.lg),
                        MicroLabel(strings.refundReturnTo),
                        const SizedBox(height: PosSpace.sm),
                        _tenders(strings, palette),
                        const SizedBox(height: PosSpace.lg),
                        ReasonPicker(
                          reasons: reasons,
                          requirement: ref.watch(refundPolicyProvider).reasonRequired
                              ? ReasonRequirement.required
                              : ReasonRequirement.optional,
                          selected: _reason,
                          note: _note,
                          compact: true,
                          autofocus: false,
                          onChanged: (reason, note) => setState(() {
                            _reason = reason;
                            _note = note;
                            _message = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                _footer(strings, palette, quote, refusal),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppStrings strings, PosPalette palette) => Container(
    padding: const EdgeInsets.all(PosSpace.lg),
    decoration: BoxDecoration(
      border: BorderDirectional(bottom: palette.resting),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.refundTitle(_order.invoiceNumber),
                style: PosText.ui(size: 20, weight: FontWeight.w800, color: palette.ink),
              ),
              if (ref.read(refundPolicyProvider).receiptRequired) ...[
                const SizedBox(height: PosSpace.xs),
                Text(
                  strings.refundReceiptRequiredNote,
                  style: PosText.ui(size: 12.5, color: palette.muted),
                ),
              ],
            ],
          ),
        ),
        // The number §18 asks to be visible at every step. Not a footnote: a
        // cashier who cannot see it discovers they have over-refunded when the
        // till refuses, in front of the customer.
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MicroLabel(strings.refundRemaining),
            const SizedBox(height: 2),
            MonoAmount(_remaining, size: 20, weight: FontWeight.w700),
          ],
        ),
      ],
    ),
  );

  Widget _basisTabs(AppStrings strings, PosPalette palette) => Row(
    children: [
      _tab(strings.refundByItems, RefundBasis.items, palette),
      const SizedBox(width: PosSpace.sm),
      _tab(strings.refundByAmount, RefundBasis.amount, palette),
    ],
  );

  Widget _tab(String label, RefundBasis basis, PosPalette palette) {
    final selected = _basis == basis;
    return Expanded(
      child: Material(
        color: selected ? palette.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: () => setState(() {
            _basis = basis;
            _message = null;
          }),
          child: Container(
            height: PosSize.filterChip,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                selected ? palette.accentBorder : palette.resting,
              ),
            ),
            child: Text(
              label,
              style: PosText.ui(
                size: 13,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? palette.inkWarm : palette.body,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _items(AppStrings strings, PosPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final line in widget.detail.lines)
        _LineRow(
          line: line,
          taking: _quantities[line.id] ?? 0,
          onChanged: (value) => _setQuantity(line, value),
        ),
    ],
  );

  Widget _amountField(AppStrings strings, PosPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(strings.refundAmountLabel),
      const SizedBox(height: PosSpace.sm),
      SizedBox(
        height: PosSize.formControl,
        child: TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            const FoldDigitsFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          textDirection: TextDirection.ltr,
          style: PosText.mono(size: 18, weight: FontWeight.w600, color: palette.ink),
          onChanged: (_) => setState(() => _message = null),
          decoration: InputDecoration(
            isDense: true,
            prefixText: '${_order.total.currency} ',
            prefixStyle: PosText.mono(size: 13, color: palette.muted),
            contentPadding: const EdgeInsets.symmetric(horizontal: PosSpace.sm),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: palette.resting,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: palette.resting,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: palette.accentBorder,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _tenders(AppStrings strings, PosPalette palette) {
    // The order's own payments, not a generic list. Money goes back the way it
    // came in — refunding a card sale to cash empties a drawer that never held
    // the money.
    final payments = widget.detail.payments;
    if (payments.isEmpty) {
      return Text(
        strings.orderDetailNoPayments,
        style: PosText.ui(size: 12.5, color: palette.muted),
      );
    }

    return Wrap(
      spacing: PosSpace.sm,
      runSpacing: PosSpace.sm,
      children: [
        for (final payment in payments)
          _TenderChip(
            label: tenderName(payment.tenderTypeId, payment.label, strings),
            amount: payment.amount,
            selected: _tenderTypeId == payment.tenderTypeId,
            onTap: () =>
                setState(() => _tenderTypeId = payment.tenderTypeId),
          ),
      ],
    );
  }

  Widget _totals(AppStrings strings, PosPalette palette, RefundQuote? quote) {
    Widget row(String label, Money value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PosText.ui(
                size: strong ? 14 : 12.5,
                weight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? palette.ink : palette.muted,
              ),
            ),
          ),
          MonoAmount(
            value,
            size: strong ? 20 : 12.5,
            weight: strong ? FontWeight.w700 : FontWeight.w400,
          ),
        ],
      ),
    );

    final subtotal = quote?.subtotal ?? _zero;
    final discount = quote?.discount ?? _zero;
    final service = quote?.service ?? _zero;
    final vat = quote?.vat ?? _zero;
    final total = quote?.total ?? _zero;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      decoration: BoxDecoration(
        border: BorderDirectional(top: palette.hairline, bottom: palette.hairline),
      ),
      child: Column(
        children: [
          row(strings.refundSubtotal, subtotal),
          if (discount.minor != 0) row(strings.refundDiscount, -discount),
          if (service.minor != 0) row(strings.refundService, service),
          row(strings.refundVat, vat),
          const SizedBox(height: 2),
          row(strings.refundTotal, total, strong: true),
        ],
      ),
    );
  }

  Widget _footer(
    AppStrings strings,
    PosPalette palette,
    RefundQuote? quote,
    RefundRefusal? refusal,
  ) {
    final allocation = quote == null ? null : _refundTenders(quote.total);
    final blocked =
        _message ??
        (refusal == null ? null : _explain(refusal, strings)) ??
        (quote != null && allocation == null ? strings.refundTenderNeeded : null);
    final ready =
        quote != null && !quote.isEmpty && allocation != null && !_busy;

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(
        border: BorderDirectional(top: palette.resting),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (blocked != null) ...[
            Container(
              padding: const EdgeInsets.all(PosSpace.sm),
              color: palette.dangerSoft,
              child: Text(
                blocked,
                style: PosText.ui(size: 12.5, color: palette.danger),
              ),
            ),
            const SizedBox(height: PosSpace.md),
          ] else if (quote != null && quote.requiresApproval) ...[
            Container(
              padding: const EdgeInsets.all(PosSpace.sm),
              color: palette.warnSoft,
              child: Text(
                strings.refundNeedsApproval,
                style: PosText.ui(size: 12.5, color: palette.warn),
              ),
            ),
            const SizedBox(height: PosSpace.md),
          ],
          Row(
            children: [
              Expanded(
                child: PosButton(
                  label: strings.cancel,
                  border: Border.fromBorderSide(palette.resting),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: PosSpace.sm),
              Expanded(
                flex: 2,
                child: PosButton(
                  label: strings.refundConfirm(
                    (quote?.total ?? _zero).format(withCurrency: true),
                  ),
                  background: ready ? palette.danger : palette.ctaDisabled,
                  foreground: Colors.white,
                  fontWeight: FontWeight.w700,
                  onPressed: ready ? () => _issue(quote) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _explain(RefundRefusal refusal, AppStrings strings) => switch (refusal) {
    RefundsDisabled() => strings.refundDisabled,
    OutsideRefundWindow(:final window) => strings.refundOutsideWindow(
      _windowName(window, strings),
    ),
    NothingLeftToRefund() => strings.refundNothingLeft,
    NothingSelected() => strings.refundNothingSelected,
    LineNotOnOrder() => strings.refundNothingSelected,
    MoreThanRemains(:final asked, :final remaining) =>
      strings.refundMoreThanRemains(asked, remaining),
    AboveRemainingValue(:final remaining) => strings.refundAboveRemaining(
      remaining.format(withCurrency: true),
    ),
    AboveRefundLimit(:final limit) => strings.refundAboveLimit(
      limit.format(withCurrency: true),
    ),
    RefundReasonRequired() => strings.refundReasonNeeded,
  };

  static String _windowName(RefundWindow window, AppStrings s) => switch (window) {
    RefundWindow.sameShift => s.refundWindowSameShift,
    RefundWindow.sameDay => s.refundWindowSameDay,
    RefundWindow.days7 => s.refundWindow7Days,
    RefundWindow.days30 => s.refundWindow30Days,
    RefundWindow.unlimited => s.refundWindowUnlimited,
  };

  Future<void> _issue(RefundQuote? quote) async {
    if (quote == null) return;
    final strings = context.strings;
    final policy = ref.read(refundPolicyProvider);

    if (policy.reasonRequired &&
        !ReasonPicker.isSatisfied(
          requirement: ReasonRequirement.required,
          reason: _reason,
          note: _note,
        )) {
      setState(() => _message = strings.refundReasonNeeded);
      return;
    }

    final tenders = _refundTenders(quote.total);
    if (tenders == null || tenders.isEmpty) {
      setState(() => _message = strings.refundTenderNeeded);
      return;
    }

    // The capability first, then the amount. Both can summon the same dialog,
    // and asking twice for one refund is how a supervisor learns to hand over
    // their PIN instead of walking over.
    final decision = await requestPermission(
      context,
      ref,
      PosCapability.orderRefund,
      action: strings.refundTitle(_order.invoiceNumber),
      auditAction: 'refund.issued',
      entityType: 'order',
      entityId: '${_order.id}',
      subjectLabel: strings.refundTotal,
      subject: quote.total.format(withCurrency: true),
      approveLabel: strings.refundAction,
    );
    if (!mounted) return;
    if (decision is! Allowed) return;

    // The approval itself, not only a name: the repository asks for it, spends
    // it on this refund, and refuses a second refund on it.
    var approval = decision.approval;

    // The person acting: in the back office's Sales tab, whoever came through
    // Admin Mode's door — not the cashier still signed in at the till, who
    // would otherwise be booked for the owner's refund.
    final by = ref.read(actingStaffProvider);
    if (by == null) return;

    // Above the threshold a second person says yes, whoever is refunding. This
    // used to go through [requestPermission], which answers "allowed" at once
    // for somebody who holds the permission — so a supervisor's large refund
    // was never shown to anybody, and went on the books with no approver.
    if (quote.requiresApproval && approval == null) {
      final outcome = await SupervisorOverrideDialog.show(
        context,
        capability: PosCapability.orderRefund,
        action: strings.refundTitle(_order.invoiceNumber),
        requestedBy: by.name,
        subjectLabel: strings.refundTotal,
        subject: quote.total.format(withCurrency: true),
        limitNote: strings.refundNeedsApproval,
        approveLabel: strings.refundAction,
      );
      if (!mounted || outcome == null) return;
      // A second person is a second person: the repository refuses a refunder
      // approving their own, so the sheet says so rather than failing later.
      if (outcome.approver.id == by.id) {
        setState(() => _message = strings.refundNeedsApproval);
        return;
      }
      final lent = Authorization.approve(
        approver: outcome.approver,
        capability: PosCapability.orderRefund,
        subject: '${_order.id}',
      );
      if (lent is! Allowed) return;
      approval = lent.approval;
      await recordApproval(
        ref,
        approver: outcome.approver,
        capability: PosCapability.orderRefund,
        auditAction: 'refund.above_threshold',
        entityType: 'order',
        entityId: '${_order.id}',
      );
      if (!mounted) return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await ref
          .read(refundsRepositoryProvider)
          .issue(
            order: _order,
            quote: quote,
            by: by,
            approval: approval,
            reasonId: _reason?.id,
            note: _note.trim().isEmpty ? null : _note.trim(),
            tenders: tenders,
            clientRefundId: _clientRefundId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(quote.total);
    } on Object {
      if (!mounted) return;
      // The ticket equivalent of keeping the cart on screen: no money has moved,
      // the selection is still here, and pressing again replays the same id
      // rather than issuing a second refund.
      setState(() {
        _busy = false;
        _message = strings.refundCouldNotBeIssued;
      });
    }
  }

}

/// One order line, with how much of it is coming back.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.taking,
    required this.onChanged,
  });

  final OrderRecordLine line;
  final int taking;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final strings = context.strings;
    final remaining = line.refundableQuantity;
    // Nothing left to give back, or nothing was ever charged for it. Shown
    // rather than hidden: a line missing from the list looks like a bug, and
    // "already refunded" is the answer somebody is looking for.
    final spent = remaining <= 0;

    return Opacity(
      opacity: spent ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    style: PosText.ui(size: 13.5, color: palette.ink),
                  ),
                  Row(
                    children: [
                      MonoCode('${line.unitPrice.format()} × ${line.quantity}'),
                      if (spent) ...[
                        const SizedBox(width: PosSpace.sm),
                        Text(
                          line.isVoided
                              ? strings.orderDetailVoidedLine
                              : strings.refundAlreadyRefunded,
                          style: PosText.mono(size: 10.5, color: palette.muted),
                        ),
                      ] else if (line.refundedQuantity > 0) ...[
                        const SizedBox(width: PosSpace.sm),
                        Text(
                          '$remaining ${strings.refundItemsRemaining}',
                          style: PosText.mono(size: 10.5, color: palette.warn),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!spent)
              _Stepper(
                value: taking,
                max: remaining,
                onChanged: onChanged,
              ),
            const SizedBox(width: PosSpace.sm),
            SizedBox(
              width: 84,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: MonoAmount(
                  line.unitPrice * taking,
                  size: 13,
                  weight: FontWeight.w600,
                  color: taking > 0 ? palette.ink : palette.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;

    Widget key(String label, VoidCallback? onTap, {String? semantics}) =>
        Semantics(
          label: semantics,
          button: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(palette.resting),
                ),
                child: Text(
                  label,
                  style: PosText.mono(
                    size: 16,
                    color: onTap == null ? palette.muted : palette.ink,
                  ),
                ),
              ),
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        key('−', value > 0 ? () => onChanged(value - 1) : null, semantics: 'less'),
        SizedBox(
          width: 40,
          child: Center(
            child: MonoAmount(
              Money(value, exponent: 0),
              size: 15,
              weight: FontWeight.w700,
              color: value > 0 ? palette.ink : palette.muted,
            ),
          ),
        ),
        key('+', value < max ? () => onChanged(value + 1) : null, semantics: 'more'),
      ],
    );
  }
}

class _TenderChip extends StatelessWidget {
  const _TenderChip({
    required this.label,
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Money amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    return Material(
      color: selected ? palette.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: PosSize.filterChip,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              selected ? palette.accentBorder : palette.resting,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: PosText.ui(
                  size: 12.5,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? palette.inkWarm : palette.body,
                ),
              ),
              const SizedBox(width: PosSpace.sm),
              MonoAmount(amount, size: 11.5, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}
