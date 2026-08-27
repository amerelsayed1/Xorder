import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/catalog.dart';
import '../../../domain/services/ticket_engine.dart';

/// What the sheet returns when the cashier confirms.
class ModifierSelection {
  const ModifierSelection(this.modifiers, this.quantity);

  final List<Modifier> modifiers;
  final int quantity;
}

/// Required and optional modifier groups, shown before the line is added.
///
/// Centred modal, 620 wide, `surface` with a 2px ink border. Add is blocked —
/// with a toast naming the unsatisfied group — until every required group has a
/// selection.
class ModifierSheet extends StatefulWidget {
  const ModifierSheet({super.key, required this.product, required this.groups});

  final Product product;
  final List<ModifierGroup> groups;

  static Future<ModifierSelection?> show(
    BuildContext context, {
    required Product product,
    required List<ModifierGroup> groups,
  }) =>
      showDialog<ModifierSelection>(
        context: context,
        barrierColor: PosColors.scrim,
        builder: (_) => ModifierSheet(product: product, groups: groups),
      );

  @override
  State<ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends State<ModifierSheet> {
  List<Modifier> _selected = [];
  int _quantity = 1;

  Money get _unitPrice => _selected.fold(
        widget.product.effectivePrice,
        (total, m) => total + m.priceDelta,
      );

  void _toggle(ModifierGroup group, Modifier modifier) {
    final next = TicketEngine.toggleModifier(_selected, group, modifier);

    if (identical(next, _selected)) {
      posToast(context, '${group.nameEn} allows at most ${group.maxSelect}.');
      return;
    }
    setState(() => _selected = next);
  }

  void _confirm() {
    final refusal = TicketEngine.validateSelection(widget.groups, _selected);

    if (refusal case RequiredGroupUnsatisfied(:final group)) {
      posToast(context, 'Pick a ${group.nameEn.toLowerCase()} first.');
      return;
    }
    Navigator.of(context).pop(ModifierSelection(_selected, _quantity));
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: PosColors.surface,
        insetPadding: const EdgeInsets.all(PosSpace.s24),
        shape: const RoundedRectangleBorder(
          side: PosBorders.emphasis,
          borderRadius: PosBorders.radius,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final group in widget.groups) _group(group)],
                ),
              ),
              _footer(),
            ],
          ),
        ),
      );

  Widget _header() => Container(
        color: PosColors.ink,
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.xl,
          vertical: PosSpace.lg,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.nameEn,
                    style: PosText.ui(size: 20, weight: FontWeight.w800, color: Colors.white),
                  ),
                  Text(
                    [widget.product.nameAr, widget.product.sku]
                        .whereType<String>()
                        .join(' · '),
                    style: PosText.arabic(size: 13, color: PosColors.shellLineMeta),
                  ),
                ],
              ),
            ),
            Text(
              widget.product.effectivePrice.format(),
              style: PosText.mono(size: 22, weight: FontWeight.w600, color: PosColors.accent),
            ),
            const SizedBox(width: PosSpace.md),
            Material(
              color: PosColors.shellCard,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: Text('×', style: PosText.ui(size: 20, color: PosColors.shellText)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _group(ModifierGroup group) {
    final chipText = group.isRequired
        ? 'REQUIRED · PICK ${group.maxSelect}'
        : 'MAX ${group.maxSelect}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PosSpace.xl,
            vertical: PosSpace.s14,
          ),
          child: Row(
            children: [
              Text(
                group.nameEn,
                style: PosText.ui(size: 13, weight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm, vertical: 3),
                color: group.isRequired ? PosColors.dangerSoft : PosColors.chipBg,
                child: Text(
                  chipText,
                  style: PosText.mono(
                    size: 10,
                    weight: FontWeight.w600,
                    color: group.isRequired ? PosColors.danger : PosColors.chipText,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: PosColors.line,
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 1,
            crossAxisSpacing: 1,
            childAspectRatio: 310 / 56,
            children: [
              for (final modifier in group.modifiers) _option(group, modifier),
              // An odd number of options leaves the trailing cell showing the
              // grid's own line colour, which reads as a rendering fault
              // rather than an empty slot.
              if (group.modifiers.length.isOdd)
                const ColoredBox(color: PosColors.surface),
            ],
          ),
        ),
      ],
    );
  }

  Widget _option(ModifierGroup group, Modifier modifier) {
    final selected = _selected.any((m) => m.id == modifier.id);

    return Material(
      color: selected ? PosColors.accentSoft : PosColors.surface,
      child: InkWell(
        onTap: () => _toggle(group, modifier),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected ? '✓ ${modifier.nameEn}' : modifier.nameEn,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(
                    size: 13.5,
                    color: selected ? PosColors.warn : PosColors.inkWarm,
                  ),
                ),
              ),
              if (!modifier.priceDelta.isZero)
                Text(
                  '+${modifier.priceDelta.format()}',
                  style: PosText.mono(
                    size: 13,
                    color: selected ? PosColors.warn : PosColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer() => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.xl,
          vertical: PosSpace.s14,
        ),
        decoration: const BoxDecoration(border: Border(top: PosBorders.emphasis)),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(border: Border.all(color: PosColors.ink)),
              child: Row(children: [
                _step('−', () => setState(() => _quantity = (_quantity - 1).clamp(1, 99))),
                SizedBox(
                  width: 56,
                  child: Center(
                    child: Text('$_quantity', style: PosText.mono(size: 20)),
                  ),
                ),
                _step('+', () => setState(() => _quantity = (_quantity + 1).clamp(1, 99))),
              ]),
            ),
            const SizedBox(width: PosSpace.md),
            Expanded(
              child: PosButton(
                label: 'Add to ticket',
                height: PosSize.secondaryAction,
                alignLeft: true,
                background: PosColors.accent,
                foreground: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                trailing: Text(
                  (_unitPrice * _quantity).format(),
                  style: PosText.mono(size: 15, weight: FontWeight.w600, color: Colors.white),
                ),
                onPressed: _confirm,
              ),
            ),
          ],
        ),
      );

  Widget _step(String glyph, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: PosSize.secondaryAction,
          child: Center(child: Text(glyph, style: PosText.ui(size: 18))),
        ),
      );
}
