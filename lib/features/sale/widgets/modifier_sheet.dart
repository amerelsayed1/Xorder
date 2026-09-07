import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
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
  }) => showDialog<ModifierSelection>(
    context: context,
    barrierColor: context.pos.scrim,
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
      posToast(
        context,
        context.strings.modifierGroupFull(
          group.displayName(context.strings.languageCode),
          group.maxSelect,
        ),
      );
      return;
    }
    setState(() => _selected = next);
  }

  void _confirm() {
    final refusal = TicketEngine.validateSelection(widget.groups, _selected);

    if (refusal case RequiredGroupUnsatisfied(:final group)) {
      posToast(
        context,
        context.strings.pickGroupFirst(
          group.displayName(context.strings.languageCode),
        ),
      );
      return;
    }
    Navigator.of(context).pop(ModifierSelection(_selected, _quantity));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pos.surface,
    insetPadding: const EdgeInsets.all(PosSpace.s24),
    shape: RoundedRectangleBorder(
      side: context.pos.emphasis,
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

  Widget _header() {
    final language = context.strings.languageCode;
    final alternate = language == 'ar'
        ? widget.product.nameEn
        : widget.product.nameAr;

    return Container(
      color: context.pos.ink,
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
                  widget.product.displayName(language),
                  style: PosText.ui(
                    size: 20,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  [
                    alternate,
                    widget.product.sku,
                  ].whereType<String>().join(' · '),
                  style: language == 'ar'
                      ? PosText.ui(size: 13, color: context.pos.shellLineMeta)
                      : PosText.arabic(
                          size: 13,
                          color: context.pos.shellLineMeta,
                        ),
                ),
              ],
            ),
          ),
          Text(
            widget.product.effectivePrice.format(),
            style: PosText.mono(
              size: 22,
              weight: FontWeight.w600,
              color: context.pos.accent,
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Material(
            color: context.pos.shellCard,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: SizedBox(
                width: 38,
                height: 38,
                child: Center(
                  child: Text(
                    '×',
                    style: PosText.ui(size: 20, color: context.pos.shellText),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(ModifierGroup group) {
    final strings = context.strings;
    final chipText = group.isRequired
        ? strings.requiredPick(group.maxSelect)
        : strings.maxPick(group.maxSelect);

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
                group.displayName(strings.languageCode),
                style: PosText.ui(color: context.pos.inkWarm, size: 13, weight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: PosSpace.sm,
                  vertical: 3,
                ),
                color: group.isRequired
                    ? context.pos.dangerSoft
                    : context.pos.chipBg,
                child: Text(
                  chipText,
                  style: PosText.mono(
                    size: 10,
                    weight: FontWeight.w600,
                    color: group.isRequired
                        ? context.pos.danger
                        : context.pos.chipText,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: context.pos.line,
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
                ColoredBox(color: context.pos.surface),
            ],
          ),
        ),
      ],
    );
  }

  Widget _option(ModifierGroup group, Modifier modifier) {
    final selected = _selected.any((m) => m.id == modifier.id);
    final name = modifier.displayName(context.strings.languageCode);

    return Material(
      color: selected ? context.pos.accentSoft : context.pos.surface,
      child: InkWell(
        onTap: () => _toggle(group, modifier),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected ? '✓ $name' : name,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(
                    size: 13.5,
                    color: selected ? context.pos.warn : context.pos.inkWarm,
                  ),
                ),
              ),
              if (!modifier.priceDelta.isZero)
                Text(
                  '+${modifier.priceDelta.format()}',
                  style: PosText.mono(
                    size: 13,
                    color: selected ? context.pos.warn : context.pos.muted,
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
    decoration: BoxDecoration(border: Border(top: context.pos.emphasis)),
    child: Row(
      children: [
        Container(
          decoration: BoxDecoration(border: Border.all(color: context.pos.ink)),
          child: Row(
            children: [
              _step(
                '−',
                () => setState(() => _quantity = (_quantity - 1).clamp(1, 99)),
              ),
              SizedBox(
                width: 56,
                child: Center(
                  child: Text('$_quantity', style: PosText.mono(color: context.pos.inkWarm, size: 20)),
                ),
              ),
              _step(
                '+',
                () => setState(() => _quantity = (_quantity + 1).clamp(1, 99)),
              ),
            ],
          ),
        ),
        const SizedBox(width: PosSpace.md),
        Expanded(
          child: PosButton(
            label: context.strings.addToTicket,
            height: PosSize.secondaryAction,
            alignLeft: true,
            background: context.pos.accent,
            foreground: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            trailing: Text(
              (_unitPrice * _quantity).format(),
              style: PosText.mono(
                size: 15,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
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
      child: Center(child: Text(glyph, style: PosText.ui(color: context.pos.inkWarm, size: 18))),
    ),
  );
}
