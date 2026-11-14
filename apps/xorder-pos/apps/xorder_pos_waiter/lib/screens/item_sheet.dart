import 'package:flutter/material.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../strings.dart';
import '../theme.dart';
import 'widgets.dart';

/// What the waiter chose for one item.
class ItemChoice {
  const ItemChoice({required this.modifierIds, required this.quantity, this.note});
  final List<int> modifierIds;
  final int quantity;
  final String? note;
}

/// An item's options, quantity and note before it goes on the check
/// (design §5.6).
///
/// The limits checked here (required groups, how many per group) are only so
/// the waiter is not sent back by the till for something the screen could
/// see; the till checks them again with its own rules.
class ItemSheet extends StatefulWidget {
  const ItemSheet({required this.product, required this.groups, required this.currency, super.key});

  final WaiterProduct product;
  final List<WaiterModifierGroup> groups;
  final WaiterCurrency currency;

  static Future<ItemChoice?> show(
    BuildContext context, {
    required WaiterProduct product,
    required List<WaiterModifierGroup> groups,
    required WaiterCurrency currency,
  }) => showModalBottomSheet<ItemChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: WaiterColors.surface,
    builder: (_) => ItemSheet(product: product, groups: groups, currency: currency),
  );

  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  late final Map<int, Set<int>> _chosen = {
    for (final g in widget.groups)
      g.id: {
        // The menu's own defaults, as the till's sale screen preselects them:
        // a marked default, else the first variant of a variant group.
        for (final m in g.modifiers)
          if (m.available && m.isDefault) m.id,
        if (g.isVariant && !g.modifiers.any((m) => m.isDefault))
          ...g.modifiers.where((m) => m.available).take(1).map((m) => m.id),
      },
  };
  int _quantity = 1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _complete => widget.groups.every((g) {
    final n = _chosen[g.id]!.length;
    return n >= g.minSelect && n <= g.maxSelect;
  });

  void _toggle(WaiterModifierGroup group, WaiterModifier modifier) {
    setState(() {
      final set = _chosen[group.id]!;
      if (set.contains(modifier.id)) {
        set.remove(modifier.id);
      } else if (group.isSingle) {
        set
          ..clear()
          ..add(modifier.id);
      } else if (set.length < group.maxSelect) {
        set.add(modifier.id);
      }
    });
  }

  /// One unit with the options chosen so far — an estimate for the button
  /// only; the check shows the till's own figure once the line exists.
  int get _unitMinor => [
    widget.product.priceMinor,
    for (final g in widget.groups)
      for (final m in g.modifiers)
        if (_chosen[g.id]!.contains(m.id)) m.deltaMinor,
  ].fold(0, (sum, x) => sum + x);

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(WaiterSpace.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(widget.product.name.pick(arabic: s.arabic), style: WaiterText.heading())),
                    const SizedBox(width: WaiterSpace.md),
                    MoneyText(widget.currency, widget.product.priceMinor, style: WaiterText.price(color: WaiterColors.body)),
                  ],
                ),
              ),
              const Divider(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: WaiterSpace.lg),
                  children: [
                    for (final g in widget.groups) ...[
                      const SizedBox(height: WaiterSpace.sm),
                      SectionHeader(
                        g.name.pick(arabic: s.arabic),
                        color: WaiterColors.body,
                        trailing: Text(
                          g.isRequired ? s.required : s.chooseUpTo(g.maxSelect),
                          style: WaiterText.meta(color: g.isRequired ? WaiterColors.warn : WaiterColors.muted),
                        ),
                      ),
                      for (final m in g.modifiers)
                        OptionRow(
                          key: Key('option-${m.id}'),
                          name: m.name.pick(arabic: s.arabic),
                          selected: _chosen[g.id]!.contains(m.id),
                          single: g.isSingle,
                          enabled: m.available,
                          trailing: m.deltaMinor == 0
                              ? null
                              : MoneyText(
                                  widget.currency,
                                  m.deltaMinor,
                                  prefix: '+',
                                  style: WaiterText.price(color: m.available ? WaiterColors.body : WaiterColors.muted),
                                ),
                          onTap: () => _toggle(g, m),
                        ),
                    ],
                    const SizedBox(height: WaiterSpace.lg),
                    TextField(
                      controller: _note,
                      maxLength: 140,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(labelText: s.note, hintText: s.noteHint),
                    ),
                  ],
                ),
              ),
              BottomBar(
                child: Row(
                  children: [
                    QuantityStepper(value: _quantity, onChanged: (v) => setState(() => _quantity = v)),
                    const SizedBox(width: WaiterSpace.md),
                    Expanded(
                      child: SizedBox(
                        height: WaiterSpace.cta,
                        child: FilledButton(
                          key: const Key('add-item'),
                          onPressed: _complete
                              ? () => Navigator.of(context).pop(ItemChoice(
                                    modifierIds: [for (final g in widget.groups) ..._chosen[g.id]!],
                                    quantity: _quantity,
                                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                                  ))
                              : null,
                          // Shrinks on a narrow phone rather than clipping the figure.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${s.addToCheck} · '),
                                MoneyText(
                                  widget.currency,
                                  _unitMinor * _quantity,
                                  prefix: '${s.estimate} ',
                                  style: WaiterText.mono(size: 15, weight: FontWeight.w700, color: WaiterColors.onAccent),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An unsent line: change how many, add a note, or take it off (design §5.7).
class LineSheet extends StatefulWidget {
  const LineSheet({required this.line, super.key});
  final WaiterLine line;

  static Future<List<WaiterOp>?> show(BuildContext context, {required WaiterLine line}) =>
      showModalBottomSheet<List<WaiterOp>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: WaiterColors.surface,
        builder: (_) => LineSheet(line: line),
      );

  @override
  State<LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<LineSheet> {
  late int _quantity = widget.line.quantity;
  late final _note = TextEditingController(text: widget.line.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<WaiterOp> _ops() => [
    if (_quantity != widget.line.quantity)
      WaiterChangeQuantity(lineKey: widget.line.key, delta: _quantity - widget.line.quantity),
    if (_note.text.trim() != (widget.line.note ?? '')) WaiterSetNote(lineKey: widget.line.key, note: _note.text.trim()),
  ];

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(WaiterSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.line.name.pick(arabic: s.arabic), style: WaiterText.heading()),
                  if (widget.line.modifiers.isNotEmpty) ...[
                    const SizedBox(height: WaiterSpace.xs),
                    Text(widget.line.modifiers.map((m) => m.pick(arabic: s.arabic)).join(s.listSeparator), style: WaiterText.meta()),
                  ],
                  const SizedBox(height: WaiterSpace.lg),
                  Row(
                    children: [
                      Expanded(child: Text(s.quantity, style: WaiterText.body())),
                      QuantityStepper(value: _quantity, onChanged: (v) => setState(() => _quantity = v)),
                    ],
                  ),
                  const SizedBox(height: WaiterSpace.md),
                  TextField(
                    controller: _note,
                    maxLength: 140,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(labelText: s.note, hintText: s.noteHint),
                  ),
                ],
              ),
            ),
            BottomBar(
              child: Row(
                children: [
                  SizedBox(
                    height: WaiterSpace.cta,
                    child: OutlinedButton(
                      key: const Key('remove-line'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: WaiterColors.danger,
                        side: const BorderSide(color: WaiterColors.danger),
                      ),
                      onPressed: () => Navigator.of(context).pop(<WaiterOp>[WaiterRemoveLine(lineKey: widget.line.key)]),
                      child: Text(s.removeLine),
                    ),
                  ),
                  const SizedBox(width: WaiterSpace.md),
                  Expanded(
                    child: PrimaryCta(key: const Key('save-line'), label: s.save, onPressed: () => Navigator.of(context).pop(_ops())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
