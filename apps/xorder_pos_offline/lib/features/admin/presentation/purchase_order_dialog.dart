import 'package:flutter/material.dart';

import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/mono_amount.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/domain/models/purchase_order.dart';
import 'package:shared_module/domain/models/supplier.dart';
import 'package:shared_module/features/admin_mode/admin_messages.dart';
import 'package:shared_module/domain/models/stock_item.dart';
import 'package:shared_module/domain/models/pos_unit.dart';

/// Writing what to ask a supplier for.
///
/// **The total recomputes as lines are typed**, because the number a buyer is
/// deciding about is what this will cost — not what one line costs — and a
/// figure that only appeared after saving would make them save to find out.
class PurchaseOrderDialog extends StatefulWidget {
  const PurchaseOrderDialog({
    super.key,
    required this.suppliers,
    this.order,
    this.items = const [],
    this.units = const [],
    this.onCreateItem,
  });

  final PurchaseOrder? order;
  final List<Supplier> suppliers;

  /// What the business counts, for a line to name. A line that names one is
  /// received into its stock; a line that does not — a service, packaging —
  /// moves the order along and touches no ledger.
  final List<StockItem> items;

  /// The units in use, for a line that names no item.
  final List<PosUnit> units;

  /// Adds what was typed as a new item and hands it back, or null when the
  /// buyer changed their mind. Absent where items cannot be added here — a
  /// cloud till, whose products are the platform's.
  final Future<StockItem?> Function(String name)? onCreateItem;

  static Future<PurchaseOrder?> show(
    BuildContext context, {
    required List<Supplier> suppliers,
    PurchaseOrder? order,
    List<StockItem> items = const [],
    List<PosUnit> units = const [],
    Future<StockItem?> Function(String name)? onCreateItem,
  }) => showDialog<PurchaseOrder>(
    context: context,
    builder: (_) => PurchaseOrderDialog(
      suppliers: suppliers,
      order: order,
      items: items,
      units: units,
      onCreateItem: onCreateItem,
    ),
  );

  @override
  State<PurchaseOrderDialog> createState() => _PurchaseOrderDialogState();
}

class _PurchaseOrderDialogState extends State<PurchaseOrderDialog> {
  late int _supplierId =
      widget.order?.supplierId ?? widget.suppliers.first.id;
  late final List<_LineDraft> _lines = [
    for (final line in widget.order?.lines ?? const <PurchaseOrderLine>[])
      _LineDraft.from(line),
    if (widget.order == null) _LineDraft.empty(),
  ];
  String? _problem;

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  /// The lines that are complete enough to price.
  ///
  /// A half-typed row is not an error while somebody is typing — it is the
  /// normal state of a form — so it is skipped in the running total and only
  /// complained about on save.
  List<PurchaseOrderLine> get _complete => [
    for (final draft in _lines) ?draft.toLine(),
  ];

  PurchaseOrder get _draft => PurchaseOrder(
    id: widget.order?.id ?? 0,
    supplierId: _supplierId,
    supplierName: widget.suppliers
        .firstWhere((s) => s.id == _supplierId)
        .nameEn,
    reference: widget.order?.reference ?? '',
    status: PurchaseStatus.draft,
    lines: _complete,
  );

  void _save() {
    if (_complete.isEmpty) {
      setState(() => _problem = context.strings.purchaseNeedsALine);
      return;
    }
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final totals = _draft.totals;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.order == null
                        ? strings.purchaseOrderNew
                        : strings.purchaseOrderEdit,
                    style: PosText.ui(
                      size: 18,
                      weight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: PosSpace.md),
                  MicroLabel(strings.suppliers),
                  const SizedBox(height: PosSpace.xs),
                  Wrap(
                    spacing: PosSpace.sm,
                    runSpacing: PosSpace.sm,
                    children: [
                      for (final supplier in widget.suppliers)
                        PosButton(
                          label: supplier.displayName(strings.languageCode),
                          background: supplier.id == _supplierId
                              ? palette.ink
                              : Colors.transparent,
                          foreground: supplier.id == _supplierId
                              ? Colors.white
                              : null,
                          border: Border.fromBorderSide(palette.resting),
                          onPressed: () =>
                              setState(() => _supplierId = supplier.id),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  Row(
                    children: [
                      Expanded(flex: 4, child: MicroLabel(strings.purchaseItem)),
                      Expanded(flex: 2, child: MicroLabel(strings.purchaseQty)),
                      Expanded(flex: 2, child: MicroLabel(strings.purchaseUnit)),
                      Expanded(flex: 2, child: MicroLabel(strings.purchaseUnitCost)),
                      Expanded(flex: 2, child: MicroLabel(strings.subtotal)),
                    ],
                  ),
                  const SizedBox(height: PosSpace.sm),
                  for (var i = 0; i < _lines.length; i++)
                    _LineRow(
                      draft: _lines[i],
                      items: widget.items,
                      units: widget.units,
                      onCreateItem: widget.onCreateItem,
                      onPicked: (item) => setState(() {
                        _lines[i].pick(item);
                        _problem = null;
                      }),
                      onChanged: () => setState(() => _problem = null),
                      onRemove: _lines.length == 1
                          ? null
                          : () => setState(() {
                              _lines.removeAt(i).dispose();
                            }),
                    ),
                  const SizedBox(height: PosSpace.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: PosButton(
                      key: const Key('purchase-add-line'),
                      label: strings.purchaseAddLine,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () =>
                          setState(() => _lines.add(_LineDraft.empty())),
                    ),
                  ),
                  if (_problem != null) ...[
                    const SizedBox(height: PosSpace.md),
                    Text(
                      _problem!,
                      style: PosText.ui(size: 12.5, color: palette.danger),
                    ),
                  ],
                  const SizedBox(height: PosSpace.lg),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                border: BorderDirectional(top: palette.resting),
              ),
              child: Row(
                children: [
                  // Scaled down rather than clipped: three amounts, each with
                  // its currency, are wider than the footer in a narrow window
                  // or a long language, and a total that is cut off is worse
                  // than a small one.
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            strings.subtotal,
                            style: PosText.ui(size: 12.5, color: palette.muted),
                          ),
                          const SizedBox(width: PosSpace.sm),
                          MonoAmount(totals.subtotal, size: 13),
                          const SizedBox(width: PosSpace.lg),
                          Text(
                            strings.vat,
                            style: PosText.ui(size: 12.5, color: palette.muted),
                          ),
                          const SizedBox(width: PosSpace.sm),
                          MonoAmount(totals.tax, size: 13),
                          const SizedBox(width: PosSpace.lg),
                          MonoAmount(
                            totals.total,
                            size: 17,
                            weight: FontWeight.w800,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  PosButton(
                    label: strings.cancel,
                    border: Border.fromBorderSide(palette.resting),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  PosButton(
                    key: const Key('purchase-save'),
                    label: strings.save,
                    background: palette.ink,
                    foreground: palette.onInk,
                    padding: const EdgeInsets.symmetric(
                      horizontal: PosSpace.xl,
                    ),
                    onPressed: _save,
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

/// One row being typed. Controllers rather than a model, because a half-typed
/// line has no valid model to hold.
class _LineDraft {
  _LineDraft({
    required this.id,
    required this.productId,
    required String description,
    required String quantity,
    required String unitCost,
    required this.unit,
    required this.taxRateBp,
  }) : description = TextEditingController(text: description),
       quantity = TextEditingController(text: quantity),
       unitCost = TextEditingController(text: unitCost);

  factory _LineDraft.empty() => _LineDraft(
    id: 0,
    productId: null,
    description: '',
    quantity: '',
    unitCost: '',
    unit: QuantityUnit.each,
    taxRateBp: 0,
  );

  factory _LineDraft.from(PurchaseOrderLine line) => _LineDraft(
    id: line.id,
    productId: line.productId,
    description: line.description,
    quantity: line.ordered.format(),
    unitCost: line.unitCost.format(),
    unit: line.ordered.unit,
    taxRateBp: line.taxRateBp,
  ).._pickedName = line.productId == null ? null : line.description;

  final int id;

  /// The item this line buys, when it names one. Cleared when somebody types
  /// over the name: a line that says "Chicken" and stocks the oil is worse
  /// than a line that stocks nothing.
  int? productId;
  String? _pickedName;
  final focus = FocusNode();
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unitCost;
  QuantityUnit unit;
  int taxRateBp;

  /// Null while the row is incomplete — which is most of the time somebody is
  /// looking at it.
  PurchaseOrderLine? toLine() {
    final name = description.text.trim();
    final qty = Quantity.tryParse(quantity.text, unit: unit);
    final cost = Money.tryParse(unitCost.text);
    if (name.isEmpty || qty == null || qty.milli <= 0 || cost == null) {
      return null;
    }
    return PurchaseOrderLine(
      id: id,
      productId: productId,
      description: name,
      ordered: qty,
      unitCost: cost,
      taxRateBp: taxRateBp,
    );
  }

  /// Name this line after [item], in the unit it is counted in.
  void pick(StockItem item) {
    productId = item.id;
    _pickedName = item.nameEn;
    unit = item.unit;
    if (description.text != item.nameEn) description.text = item.nameEn;
  }

  /// Typed over a picked name: a free line again.
  void typed() {
    if (productId != null && description.text != _pickedName) {
      productId = null;
      _pickedName = null;
    }
  }

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitCost.dispose();
    focus.dispose();
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.draft,
    required this.onChanged,
    required this.onRemove,
    required this.onPicked,
    this.items = const [],
    this.units = const [],
    this.onCreateItem,
  });

  final _LineDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final ValueChanged<StockItem> onPicked;
  final List<StockItem> items;
  final List<PosUnit> units;
  final Future<StockItem?> Function(String name)? onCreateItem;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final line = draft.toLine();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _ItemField(
              draft: draft,
              items: items,
              onCreateItem: onCreateItem,
              onPicked: onPicked,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            flex: 2,
            child: TextField(
              controller: draft.quantity,
              onChanged: (_) => onChanged(),
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: PosText.mono(size: 14, color: palette.ink),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            flex: 2,
            child: _UnitPicker(
              draft: draft,
              units: units,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            flex: 2,
            child: TextField(
              controller: draft.unitCost,
              onChanged: (_) => onChanged(),
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: PosText.mono(size: 14, color: palette.ink),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            flex: 2,
            child: line == null
                ? const SizedBox.shrink()
                : MonoAmount(line.lineTotal, size: 13),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.close, size: 16, color: palette.muted),
            ),
        ],
      ),
    );
  }
}

/// One suggestion under the item box: an item, or "add this as a new one".
class _Pick {
  const _Pick.item(StockItem this.item) : newName = null;
  const _Pick.create(String this.newName) : item = null;

  final StockItem? item;
  final String? newName;
}

/// The item box: type a name, pick what the business counts, or add it.
///
/// Free text stays allowed — a delivery charge or a cleaning service is a
/// real line that stocks nothing — so a name that matches nothing is just a
/// line, and "add as a new item" is offered rather than forced.
class _ItemField extends StatelessWidget {
  const _ItemField({
    required this.draft,
    required this.items,
    required this.onPicked,
    required this.onChanged,
    this.onCreateItem,
  });

  final _LineDraft draft;
  final List<StockItem> items;
  final ValueChanged<StockItem> onPicked;
  final VoidCallback onChanged;
  final Future<StockItem?> Function(String name)? onCreateItem;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return RawAutocomplete<_Pick>(
      textEditingController: draft.description,
      focusNode: draft.focus,
      displayStringForOption: (pick) => pick.item?.nameEn ?? pick.newName!,
      optionsBuilder: (value) {
        final typed = value.text.trim();
        if (typed.isEmpty || (items.isEmpty && onCreateItem == null)) {
          return const <_Pick>[];
        }
        final lower = typed.toLowerCase();
        final matches = [
          for (final item in items)
            if (item.nameEn.toLowerCase().contains(lower) ||
                (item.nameAr?.contains(typed) ?? false) ||
                (item.sku?.toLowerCase().contains(lower) ?? false))
              _Pick.item(item),
        ];
        final exact = items.any((i) => i.nameEn.toLowerCase() == lower);
        return [
          ...matches.take(8),
          if (onCreateItem != null && !exact) _Pick.create(typed),
        ];
      },
      onSelected: (pick) async {
        if (pick.item case final item?) {
          onPicked(item);
          return;
        }
        final created = await onCreateItem!(pick.newName!);
        if (created != null) onPicked(created);
      },
      fieldViewBuilder: (context, controller, focusNode, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: (_) {
          draft.typed();
          onChanged();
        },
        style: PosText.ui(size: 14, color: palette.ink),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 4,
          color: palette.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final pick in options)
                  InkWell(
                    onTap: () => onSelected(pick),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PosSpace.md,
                        vertical: PosSpace.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              pick.item?.displayName(strings.languageCode) ??
                                  strings.purchaseAddAsItem(pick.newName!),
                              style: PosText.ui(
                                size: 13.5,
                                weight: pick.item == null
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: palette.ink,
                              ),
                            ),
                          ),
                          if (pick.item case final item?)
                            Text(
                              AdminText.unit(strings, item.unit),
                              style: PosText.mono(size: 11, color: palette.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a line is counted in.
///
/// **Fixed to the item's unit when the line names one.** Receiving writes the
/// line's unit onto the item's stock position, so a line in boxes against an
/// item counted in kilograms would quietly relabel the stock and add boxes to
/// kilograms. A line that names nothing may be in anything.
class _UnitPicker extends StatelessWidget {
  const _UnitPicker({
    required this.draft,
    required this.units,
    required this.onChanged,
  });

  final _LineDraft draft;
  final List<PosUnit> units;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    String label(QuantityUnit unit) {
      for (final named in units) {
        if (named.unit == unit) return named.displayName(strings.languageCode);
      }
      return AdminText.unit(strings, unit);
    }

    final locked = draft.productId != null;
    final choices = [
      if (!units.any((u) => u.unit == draft.unit)) draft.unit,
      for (final unit in units) unit.unit,
    ];
    final face = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.sm,
        vertical: PosSpace.md,
      ),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(palette.resting),
        color: locked ? palette.page : palette.surface,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label(draft.unit),
              overflow: TextOverflow.ellipsis,
              style: PosText.ui(size: 13, color: palette.ink),
            ),
          ),
          if (!locked)
            Icon(Icons.arrow_drop_down, size: 18, color: palette.muted),
        ],
      ),
    );

    if (locked) return KeyedSubtree(key: const Key('purchase-line-unit'), child: face);
    return PopupMenuButton<QuantityUnit>(
      key: const Key('purchase-line-unit'),
      initialValue: draft.unit,
      onSelected: (unit) {
        draft.unit = unit;
        onChanged();
      },
      itemBuilder: (_) => [
        for (final unit in choices)
          PopupMenuItem(value: unit, child: Text(label(unit))),
      ],
      child: face,
    );
  }
}
