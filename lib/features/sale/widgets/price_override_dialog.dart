import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../core/ui/widgets/reason_picker.dart';
import '../../../domain/models/discount.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/authorization.dart';
import '../../../domain/services/ticket_engine.dart';
import '../../admin/presentation/supervisor_override.dart';
import '../../../core/ui/widgets/fold_digits_formatter.dart';

/// What the dialog came back with.
///
/// The price and the reason travel together on purpose. An earlier draft
/// returned only the price and left the reason on the dialog's state, where
/// nothing could reach it — a required field that is collected and discarded is
/// worse than one that was never asked for, because the screen looks compliant.
class PriceOverrideChoice {
  const PriceOverrideChoice({required this.price, required this.reason});

  final Money price;
  final ReasonSelection reason;
}

/// Selling one line at a price somebody set by hand.
///
/// **A deviation from the design brief, stated.** The brief asks for this
/// inline on the cart line. The half that must be inline *is*: a repriced line
/// shows its menu price struck through above what is being charged, which is
/// the sentence a cashier reads to a customer. The editing is a dialog, because
/// a reason is required and a reason picker does not fit in a 378px panel — and
/// a required field that has nowhere to go is how a required field quietly
/// becomes optional.
///
/// The price entered is the **whole unit price**, modifiers folded in. "Make it
/// 40" means the customer pays 40 for that item, not 40 plus the extras.
class PriceOverrideDialog extends ConsumerStatefulWidget {
  const PriceOverrideDialog({
    super.key,
    required this.line,
    required this.limit,
  });

  final TicketLine line;

  /// What this person may give away. Null once a supervisor has approved this
  /// particular reduction — the same retry the discount sheet makes.
  final DiscountLimit? limit;

  /// Returns the price agreed and why, or null if nothing changed.
  ///
  /// A zero price is a real answer — a comp — so the caller must not treat one
  /// as "nothing happened".
  static Future<PriceOverrideChoice?> show(
    BuildContext context, {
    required TicketLine line,
    required DiscountLimit? limit,
  }) => showDialog<PriceOverrideChoice>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => PriceOverrideDialog(line: line, limit: limit),
  );

  @override
  ConsumerState<PriceOverrideDialog> createState() =>
      _PriceOverrideDialogState();
}

class _PriceOverrideDialogState extends ConsumerState<PriceOverrideDialog> {
  late final TextEditingController _price = TextEditingController(
    // Pre-filled with what is being charged now, selected, so the common case
    // is type-over rather than clear-then-type. An empty field would make the
    // dialog ask "what price?" without saying what the price is.
    text: widget.line.unitPrice.format(),
  );

  ReasonCode? _reason;
  String _note = '';
  String? _message;

  TicketLine get _line => widget.line;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Money? get _entered => Money.tryParse(
    _price.text,
    currency: _line.unitPrice.currency,
    exponent: _line.unitPrice.exponent,
  );

  Money get _zero => _line.unitPrice.copyWith(minor: 0);

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final reasons =
        ref.watch(reasonCodesProvider(ReasonScope.priceOverride)).valueOrNull ??
        const <ReasonCode>[];
    final entered = _entered;
    final total = (entered ?? _zero) * _line.quantity;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogReason),
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
                        _prices(strings, palette, total),
                        const SizedBox(height: PosSpace.lg),
                        ReasonPicker(
                          reasons: reasons,
                          requirement: ReasonRequirement.required,
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
                _footer(strings, palette, entered),
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
    child: Text(
      strings.priceOverrideTitle(
        _line.product.displayName(strings.languageCode),
      ),
      style: PosText.ui(size: 18, weight: FontWeight.w800, color: palette.ink),
    ),
  );

  Widget _prices(AppStrings strings, PosPalette palette, Money total) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              strings.priceOverrideMenuPrice,
              style: PosText.ui(size: 12.5, color: palette.muted),
            ),
          ),
          // Struck through here as well as in the cart, so the dialog says what
          // is being replaced without the cashier having to look behind it.
          DefaultTextStyle.merge(
            style: const TextStyle(decoration: TextDecoration.lineThrough),
            child: MonoAmount(_line.menuUnitPrice, size: 13, color: palette.muted),
          ),
        ],
      ),
      const SizedBox(height: PosSpace.md),
      MicroLabel(strings.priceOverrideNewPrice),
      const SizedBox(height: PosSpace.xs),
      SizedBox(
        height: PosSize.formControl,
        child: TextField(
          controller: _price,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            const FoldDigitsFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          textDirection: TextDirection.ltr,
          onChanged: (_) => setState(() => _message = null),
          style: PosText.mono(size: 20, weight: FontWeight.w700, color: palette.ink),
          decoration: InputDecoration(
            isDense: true,
            prefixText: '${_line.unitPrice.currency} ',
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
      if (_line.quantity > 1) ...[
        const SizedBox(height: PosSpace.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                '${strings.priceOverrideLineTotal} · ${_line.quantity}×',
                style: PosText.ui(size: 12.5, color: palette.muted),
              ),
            ),
            MonoAmount(total, size: 15, weight: FontWeight.w700),
          ],
        ),
      ],
    ],
  );

  Widget _footer(AppStrings strings, PosPalette palette, Money? entered) {
    final ready =
        entered != null &&
        entered.minor >= 0 &&
        entered.minor != _line.unitPrice.minor;

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(border: BorderDirectional(top: palette.resting)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_message != null) ...[
            Container(
              padding: const EdgeInsets.all(PosSpace.sm),
              color: palette.dangerSoft,
              child: Text(
                _message!,
                style: PosText.ui(size: 12.5, color: palette.danger),
              ),
            ),
            const SizedBox(height: PosSpace.md),
          ],
          Row(
            children: [
              // Only offered on a line that has an override to remove. A
              // permanently dead "back to menu price" on every other line is
              // clutter in a dialog that is already asking two questions.
              if (_line.isRepriced)
                Expanded(
                  child: PosButton(
                    label: strings.priceOverrideRestore,
                    border: Border.fromBorderSide(palette.resting),
                    onPressed: () => Navigator.of(context).pop(
                      PriceOverrideChoice(
                        price: _line.menuUnitPrice,
                        reason: _selection,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: PosButton(
                    label: strings.cancel,
                    border: Border.fromBorderSide(palette.resting),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              const SizedBox(width: PosSpace.sm),
              Expanded(
                flex: 2,
                child: PosButton(
                  label: strings.priceOverrideAction,
                  background: ready ? palette.accent : palette.ctaDisabled,
                  foreground: Colors.white,
                  fontWeight: FontWeight.w700,
                  onPressed: ready ? _confirm : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Trimmed, and empty becomes null — the shape [ReasonSelection] documents.
  ReasonSelection get _selection => ReasonSelection(
    reason: _reason,
    note: _note.trim().isEmpty ? null : _note.trim(),
  );

  void _confirm() {
    final strings = context.strings;
    final entered = _entered;
    if (entered == null) return;

    if (entered.minor < 0) {
      setState(() => _message = strings.priceOverrideBelowZero);
      return;
    }
    if (entered.minor == _line.unitPrice.minor) {
      setState(() => _message = strings.priceOverrideUnchanged);
      return;
    }
    if (!ReasonPicker.isSatisfied(
      requirement: ReasonRequirement.required,
      reason: _reason,
      note: _note,
    )) {
      setState(() => _message = strings.refundReasonNeeded);
      return;
    }

    Navigator.of(context).pop(
      PriceOverrideChoice(
        price: entered,
        reason: _selection,
      ),
    );
  }
}

/// Runs the whole act: permission, dialog, engine, and the supervisor retry.
///
/// Lives beside the dialog rather than in the sale screen because the retry —
/// refused for a limit, approved, applied with `limit: null` — is the part
/// somebody re-implementing this from the screen would get wrong.
abstract final class PriceOverrideFlow {
  /// Returns the new ticket, or null if nothing changed.
  static Future<Ticket?> run(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
    required TicketLine line,
  }) async {
    final strings = context.strings;

    final decision = await requestPermission(
      context,
      ref,
      PosCapability.priceOverride,
      action: strings.priceOverrideTitle(
        line.product.displayName(strings.languageCode),
      ),
      auditAction: 'price.overridden',
      entityType: 'order_line',
      entityId: line.key,
      subjectLabel: strings.priceOverrideMenuPrice,
      subject: line.menuUnitPrice.format(withCurrency: true),
      approveLabel: strings.priceOverrideAction,
    );
    if (!context.mounted || decision is! Allowed) return null;

    final by = ref.read(signedInStaffProvider);
    if (by == null) return null;

    final limit = ref.read(discountLimitProvider).valueOrNull;
    final choice = await PriceOverrideDialog.show(
      context,
      line: line,
      limit: limit,
    );
    if (choice == null || !context.mounted) return null;
    final price = choice.price;

    // Restoring the menu price is its own act, and needs no ceiling — giving
    // *less* away cannot breach one.
    if (line.isRepriced && price.minor == line.menuUnitPrice.minor) {
      final restored = TicketEngine.clearPriceOverride(
        ticket,
        line.key,
        by: by.id,
        now: DateTime.now(),
      );
      return restored.ticket;
    }

    final discounts = ref.read(discountsRepositoryProvider);
    var approver = decision.approvedBy;
    var result = _apply(
      ticket,
      line: line,
      price: price,
      by: by,
      approver: approver,
      // Lent for the act, so the reduction is the lender's to allow — up to
      // THEIR ceiling, not without one.
      limit: approver == null ? limit : await discounts.limitFor(approver),
      // The reason the cashier gave in the dialog, not whatever the permission
      // prompt happened to collect. They are different questions.
      reason: choice.reason,
    );

    if (result.refusal is PriceBelowLimit) {
      final refusal = result.refusal! as PriceBelowLimit;
      if (!context.mounted) return null;

      // Straight to a supervisor, not through `requestPermission`. That answers
      // "allowed" at once for a cashier who holds the permission — which is
      // every cashier who reaches this line, since the limit is what refused
      // them — and the retry then ran with no ceiling at all. The cashier's
      // own limit was undone by the prompt meant to enforce it.
      final outcome = await SupervisorOverrideDialog.show(
        context,
        capability: PosCapability.priceOverride,
        action: strings.priceOverrideTitle(
          line.product.displayName(strings.languageCode),
        ),
        requestedBy: by.name,
        subjectLabel: strings.priceOverrideNewPrice,
        subject: price.format(withCurrency: true),
        limitNote: strings.priceOverrideAboveLimit(
          refusal.reduction.format(withCurrency: true),
          (limit?.maxAmount ?? refusal.base).format(withCurrency: true),
        ),
        approveLabel: strings.priceOverrideAction,
      );
      if (!context.mounted || outcome == null) return null;

      await recordApproval(
        ref,
        approver: outcome.approver,
        capability: PosCapability.priceOverride,
        auditAction: 'price.overridden.above_limit',
        entityType: 'order_line',
        entityId: line.key,
        reason: outcome.reason,
      );
      approver = outcome.approver;
      // Retried under the approver's ceiling: they have looked at this exact
      // reduction and said yes, as far as they themselves may go.
      final approverLimit = await discounts.limitFor(outcome.approver);
      if (!context.mounted) return null;
      result = _apply(
        ticket,
        line: line,
        price: price,
        by: by,
        approver: approver,
        limit: approverLimit,
        reason: choice.reason,
      );
    }

    return result.ticket;
  }

  static TicketResult _apply(
    Ticket ticket, {
    required TicketLine line,
    required Money price,
    required PosStaff by,
    required PosStaff? approver,
    required DiscountLimit? limit,
    required ReasonSelection reason,
  }) => TicketEngine.overridePrice(
    ticket,
    line.key,
    price,
    by: by.id,
    now: DateTime.now(),
    limit: limit,
    reasonId: reason.reasonId,
    // Already trimmed, and already null rather than empty — see
    // [ReasonSelection.note].
    note: reason.note,
    approvedByStaffId: approver?.id,
    approvedByName: approver?.name,
  );
}
