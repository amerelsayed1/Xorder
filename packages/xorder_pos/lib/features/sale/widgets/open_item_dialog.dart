import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/services/authorization.dart';
import '../../../domain/services/ticket_engine.dart';
import '../../admin/presentation/supervisor_override.dart';
import '../../../core/ui/widgets/fold_digits_formatter.dart';

/// What the dialog came back with.
class OpenItemDraft {
  const OpenItemDraft({
    required this.name,
    required this.price,
    required this.quantity,
  });

  final String name;
  final Money price;
  final int quantity;
}

/// Charging for something that is not on the menu (§17).
///
/// A delivery fee, corkage, a birthday cake somebody brought in. It becomes an
/// ordinary ticket line — discounted, voided, taxed and printed like any other
/// — because the only unusual thing about it is that no menu item is behind it.
///
/// **The name is required and the price is not.** Zero is a real answer: a
/// comped extra still belongs on the receipt so the kitchen makes it and the
/// customer can see they were not charged. A nameless 200.00, by contrast, is a
/// line nobody can account for a week later.
class OpenItemDialog extends StatefulWidget {
  const OpenItemDialog({super.key});

  static Future<OpenItemDraft?> show(BuildContext context) =>
      showDialog<OpenItemDraft>(
        context: context,
        builder: (_) => const OpenItemDialog(),
      );

  @override
  State<OpenItemDialog> createState() => _OpenItemDialogState();
}

class _OpenItemDialogState extends State<OpenItemDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  int _quantity = 1;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Money? get _entered => Money.tryParse(_price.text);

  Money get _lineTotal => (_entered ?? Money.zero) * _quantity;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

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
          child: Padding(
            padding: const EdgeInsets.all(PosSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.openItemTitle,
                  style: PosText.ui(
                    size: 18,
                    weight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: PosSpace.lg),
                MicroLabel(strings.openItemName),
                const SizedBox(height: PosSpace.xs),
                _field(
                  controller: _name,
                  autofocus: true,
                  hint: strings.openItemNameHint,
                  palette: palette,
                ),
                const SizedBox(height: PosSpace.md),
                MicroLabel(strings.openItemPrice),
                const SizedBox(height: PosSpace.xs),
                _field(
                  controller: _price,
                  palette: palette,
                  numeric: true,
                  suffix: 'EGP',
                ),
                const SizedBox(height: PosSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.priceOverrideLineTotal,
                        style: PosText.ui(size: 12.5, color: palette.muted),
                      ),
                    ),
                    _stepper(palette),
                    const SizedBox(width: PosSpace.md),
                    MonoAmount(_lineTotal, size: 16, weight: FontWeight.w700),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: PosSpace.md),
                  Container(
                    padding: const EdgeInsets.all(PosSpace.sm),
                    color: palette.dangerSoft,
                    child: Text(
                      _message!,
                      style: PosText.ui(size: 12.5, color: palette.danger),
                    ),
                  ),
                ],
                const SizedBox(height: PosSpace.lg),
                Row(
                  children: [
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
                        label: strings.openItemAdd,
                        background: palette.accent,
                        foreground: Colors.white,
                        fontWeight: FontWeight.w700,
                        onPressed: _submit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required PosPalette palette,
    bool autofocus = false,
    bool numeric = false,
    String? hint,
    String? suffix,
  }) => SizedBox(
    height: PosSize.formControl,
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: numeric
          ? [
              const FoldDigitsFormatter(),
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ]
          : null,
      textDirection: numeric ? TextDirection.ltr : null,
      // Digits read left to right, but the figure sits on the start edge with
      // the label and the name above it: `ltr` alone put it on the left of an
      // Arabic form, with the currency on the opposite side of the box.
      textAlign: numeric
          ? (Directionality.of(context) == TextDirection.rtl
                ? TextAlign.right
                : TextAlign.left)
          : TextAlign.start,
      textAlignVertical: TextAlignVertical.center,
      maxLength: numeric ? null : 60,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      onChanged: (_) => setState(() => _message = null),
      onSubmitted: (_) => _submit(),
      style: numeric
          ? PosText.mono(size: 18, weight: FontWeight.w700, color: palette.ink)
          : PosText.ui(size: 15, color: palette.ink),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: PosText.ui(size: 14, color: palette.muted),
        suffixText: suffix,
        suffixStyle: PosText.mono(size: 13, color: palette.muted),
        // Tight, so the field fills its [PosSize.formControl] box. Left to its
        // own height it sat at the top of the box, a different height for each
        // type size, and left a gap under it that the next label then
        // stacked its own gap on.
        constraints: const BoxConstraints.tightFor(height: PosSize.formControl),
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
  );

  Widget _stepper(PosPalette palette) {
    Widget key(String label, VoidCallback? onTap) => Material(
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
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        key('−', _quantity > 1 ? () => setState(() => _quantity--) : null),
        SizedBox(
          width: 36,
          child: Center(
            // A count, not money: no currency beside it (it would wrap in 36).
            child: MonoAmount(
              Money(_quantity, exponent: 0),
              size: 15,
              weight: FontWeight.w700,
              withCurrency: false,
            ),
          ),
        ),
        key('+', () => setState(() => _quantity++)),
      ],
    );
  }

  void _submit() {
    final strings = context.strings;
    final name = _name.text.trim();
    final price = _entered;

    if (name.isEmpty) {
      setState(() => _message = strings.openItemNeedsName);
      return;
    }
    // Zero is allowed: a comped extra still belongs on the receipt so the
    // kitchen makes it and the customer sees they were not charged.
    if (price == null || price.minor < 0) {
      setState(() => _message = strings.openItemNeedsPrice);
      return;
    }

    Navigator.of(context).pop(
      OpenItemDraft(name: name, price: price, quantity: _quantity),
    );
  }
}

/// Permission, dialog, engine.
abstract final class OpenItemFlow {
  /// Returns the ticket with the charge on it, or null if nothing was added.
  static Future<Ticket?> run(
    BuildContext context,
    WidgetRef ref, {
    required Ticket ticket,
  }) async {
    final strings = context.strings;

    // Gated on `price.override`, not on a key of its own.
    //
    // "Sell at a price that is not the menu price" is literally what this is,
    // and it carries the same power: a cashier who may type any figure here can
    // ring a 200.00 dish as a 20.00 "item". Inventing `order.item.add_free_item`
    // now would be a second name for one decision, and Wave C would have to
    // reconcile them.
    final decision = await requestPermission(
      context,
      ref,
      PosCapability.priceOverride,
      action: strings.openItemTitle,
      auditAction: 'price.overridden',
      entityType: 'order_line',
      approveLabel: strings.openItemAdd,
    );
    if (!context.mounted || decision is! Allowed) return null;

    final draft = await OpenItemDialog.show(context);
    if (draft == null || !context.mounted) return null;

    final result = TicketEngine.addOpenPriceLine(
      ticket,
      name: draft.name,
      price: draft.price,
      quantity: draft.quantity,
    );
    return result.ticket;
  }
}
