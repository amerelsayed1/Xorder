import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/money/quantity.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/purchase_order.dart';
import '../../../domain/models/supplier.dart';

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
  });

  final PurchaseOrder? order;
  final List<Supplier> suppliers;

  static Future<PurchaseOrder?> show(
    BuildContext context, {
    required List<Supplier> suppliers,
    PurchaseOrder? order,
  }) => showDialog<PurchaseOrder>(
    context: context,
    builder: (_) => PurchaseOrderDialog(suppliers: suppliers, order: order),
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
                      Expanded(flex: 2, child: MicroLabel(strings.purchaseUnitCost)),
                      Expanded(flex: 2, child: MicroLabel(strings.subtotal)),
                    ],
                  ),
                  const SizedBox(height: PosSpace.sm),
                  for (var i = 0; i < _lines.length; i++)
                    _LineRow(
                      draft: _lines[i],
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
                  MonoAmount(totals.total, size: 17, weight: FontWeight.w800),
                  const Spacer(),
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
                    foreground: Colors.white,
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
  );

  final int id;
  final int? productId;
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

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitCost.dispose();
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  final _LineDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

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
            child: TextField(
              controller: draft.description,
              onChanged: (_) => onChanged(),
              style: PosText.ui(size: 14, color: palette.ink),
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
