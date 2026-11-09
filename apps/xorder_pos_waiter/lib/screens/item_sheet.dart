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

/// An item's options, quantity and note before it goes on the check.
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

  /// One unit with the options chosen so far.
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
                child: Text(
                  widget.product.name.pick(arabic: s.arabic),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WaiterColors.ink),
                ),
              ),
              const Divider(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: WaiterSpace.lg),
                  children: [
                    for (final g in widget.groups) ...[
                      const SizedBox(height: WaiterSpace.md),
                      Row(children: [
                        Expanded(
                          child: Text(g.name.pick(arabic: s.arabic),
                              style: const TextStyle(fontWeight: FontWeight.w700, color: WaiterColors.ink)),
                        ),
                        Text(
                          g.isRequired ? s.required : s.chooseUpTo(g.maxSelect),
                          style: TextStyle(fontSize: 12, color: g.isRequired ? WaiterColors.warn : WaiterColors.muted),
                        ),
                      ]),
                      const SizedBox(height: WaiterSpace.xs),
                      Wrap(
                        spacing: WaiterSpace.sm,
                        runSpacing: WaiterSpace.sm,
                        children: [
                          for (final m in g.modifiers)
                            FilterChip(
                              key: Key('option-${m.id}'),
                              label: Text(m.deltaMinor == 0
                                  ? m.name.pick(arabic: s.arabic)
                                  : '${m.name.pick(arabic: s.arabic)}  +${moneyText(widget.currency, m.deltaMinor, arabic: s.arabic)}'),
                              selected: _chosen[g.id]!.contains(m.id),
                              onSelected: m.available ? (_) => _toggle(g, m) : null,
                              showCheckmark: false,
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                              selectedColor: WaiterColors.accentSoft,
                              side: BorderSide(
                                color: _chosen[g.id]!.contains(m.id) ? WaiterColors.accent : WaiterColors.lineStrong,
                                width: _chosen[g.id]!.contains(m.id) ? 2 : 1,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: WaiterSpace.lg),
                    TextField(
                      controller: _note,
                      maxLength: 140,
                      decoration: InputDecoration(labelText: s.note, hintText: s.noteHint),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(WaiterSpace.md),
                child: Row(children: [
                  OutlinedButton(
                    onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    child: const Icon(Icons.remove),
                  ),
                  SizedBox(width: 48, child: Text('$_quantity', textAlign: TextAlign.center, style: waiterMono(size: 20))),
                  OutlinedButton(
                    onPressed: _quantity < 99 ? () => setState(() => _quantity++) : null,
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(width: WaiterSpace.md),
                  Expanded(
                    child: FilledButton(
                      key: const Key('add-item'),
                      onPressed: _complete
                          ? () => Navigator.of(context).pop(ItemChoice(
                                modifierIds: [for (final g in widget.groups) ..._chosen[g.id]!],
                                quantity: _quantity,
                                note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                              ))
                          : null,
                      // An estimate for the button only: the check shows the
                      // till's own figure once it is added.
                      child: Text('${s.addToCheck} · ${moneyText(widget.currency, _unitMinor * _quantity, arabic: s.arabic)}'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An unsent line: change how many, add a note, or take it off.
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
        child: Padding(
          padding: const EdgeInsets.all(WaiterSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.line.name.pick(arabic: s.arabic),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WaiterColors.ink)),
              const SizedBox(height: WaiterSpace.lg),
              Row(children: [
                Text(s.quantity, style: const TextStyle(color: WaiterColors.body)),
                const Spacer(),
                OutlinedButton(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  child: const Icon(Icons.remove),
                ),
                SizedBox(width: 48, child: Text('$_quantity', textAlign: TextAlign.center, style: waiterMono(size: 20))),
                OutlinedButton(
                  onPressed: _quantity < 99 ? () => setState(() => _quantity++) : null,
                  child: const Icon(Icons.add),
                ),
              ]),
              const SizedBox(height: WaiterSpace.md),
              TextField(controller: _note, maxLength: 140, decoration: InputDecoration(labelText: s.note, hintText: s.noteHint)),
              const SizedBox(height: WaiterSpace.sm),
              Row(children: [
                OutlinedButton(
                  key: const Key('remove-line'),
                  style: OutlinedButton.styleFrom(foregroundColor: WaiterColors.danger),
                  onPressed: () => Navigator.of(context).pop(<WaiterOp>[WaiterRemoveLine(lineKey: widget.line.key)]),
                  child: Text(s.removeLine),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('save-line'),
                  onPressed: () => Navigator.of(context).pop(_ops()),
                  child: Text(s.save),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
