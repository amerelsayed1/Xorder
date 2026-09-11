import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/money/quantity.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/pos_unit.dart';
import '../../../domain/models/stock_item.dart';
import 'admin_messages.dart';

/// Adding or editing one thing the restaurant buys and counts.
///
/// An item on the menu shows its name and SKU but will not change them: those
/// are the Menu pane's, and only the unit it is counted in is set here.
class StockItemDialog extends StatefulWidget {
  const StockItemDialog({
    super.key,
    required this.units,
    this.item,
    this.initialName,
  });

  /// Null adds a new one — bought, counted, not sold.
  final StockItem? item;

  /// The units in use, to count it in.
  final List<PosUnit> units;

  /// What somebody had already typed — on a purchase line, before asking to
  /// add it as a new item.
  final String? initialName;

  static Future<StockItem?> show(
    BuildContext context, {
    required List<PosUnit> units,
    StockItem? item,
    String? initialName,
  }) => showDialog<StockItem>(
    context: context,
    builder: (_) =>
        StockItemDialog(units: units, item: item, initialName: initialName),
  );

  @override
  State<StockItemDialog> createState() => _StockItemDialogState();
}

class _StockItemDialogState extends State<StockItemDialog> {
  late final _nameEn = TextEditingController(
    text: widget.item?.nameEn ?? widget.initialName ?? '',
  );
  late final _nameAr = TextEditingController(text: widget.item?.nameAr ?? '');
  late final _sku = TextEditingController(text: widget.item?.sku ?? '');
  late QuantityUnit _unit = widget.item?.unit ?? QuantityUnit.each;
  late bool _isActive = widget.item?.isActive ?? true;

  bool get _onMenu => widget.item?.onMenu ?? false;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    _sku.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      StockItem(
        id: widget.item?.id ?? 0,
        nameEn: _nameEn.text.trim(),
        nameAr: _nameAr.text.trim().isEmpty ? null : _nameAr.text.trim(),
        sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
        unit: _unit,
        onMenu: _onMenu,
        isActive: _isActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    // The unit it is counted in now stays choosable even if it has since been
    // retired: an item cannot be left counted in nothing.
    final choices = [
      if (!widget.units.any((u) => u.unit == _unit)) _unit,
      for (final unit in widget.units) unit.unit,
    ];
    String label(QuantityUnit unit) {
      for (final named in widget.units) {
        if (named.unit == unit) return named.displayName(strings.languageCode);
      }
      return AdminText.unit(strings, unit);
    }

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.item == null ? strings.itemNew : strings.itemEdit,
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              if (_onMenu) ...[
                const SizedBox(height: PosSpace.sm),
                Text(
                  strings.itemOnMenuHint,
                  style: PosText.ui(size: 12.5, color: palette.muted),
                ),
              ],
              const SizedBox(height: PosSpace.lg),
              _Field(
                name: 'name',
                label: strings.itemName,
                controller: _nameEn,
                enabled: !_onMenu,
              ),
              _Field(
                name: 'name_ar',
                label: strings.itemNameAr,
                controller: _nameAr,
                optional: true,
                enabled: !_onMenu,
              ),
              _Field(
                name: 'sku',
                label: strings.fieldSku,
                controller: _sku,
                optional: true,
                mono: true,
                enabled: !_onMenu,
              ),
              MicroLabel(strings.itemUnit),
              const SizedBox(height: PosSpace.xs),
              Wrap(
                spacing: PosSpace.sm,
                runSpacing: PosSpace.sm,
                children: [
                  for (final unit in choices)
                    PosButton(
                      key: Key('item-unit-${unit.wire}'),
                      label: label(unit),
                      background: unit == _unit
                          ? palette.ink
                          : Colors.transparent,
                      foreground: unit == _unit ? palette.onInk : null,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => setState(() => _unit = unit),
                    ),
                ],
              ),
              if (widget.item != null && !_onMenu)
                SwitchListTile(
                  key: const Key('item-active'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.unitActive,
                    style: PosText.ui(size: 13.5, color: palette.body),
                  ),
                ),
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
                    child: PosButton(
                      key: const Key('item-save'),
                      label: strings.save,
                      background: palette.ink,
                      foreground: palette.onInk,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.name,
    required this.label,
    required this.controller,
    this.optional = false,
    this.mono = false,
    this.enabled = true,
  });

  final String name;
  final String label;
  final TextEditingController controller;
  final bool optional;
  final bool mono;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PosSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(optional ? context.strings.optionalField(label) : label),
        const SizedBox(height: PosSpace.xs),
        TextField(
          key: Key('item-$name'),
          controller: controller,
          enabled: enabled,
          textDirection: mono ? TextDirection.ltr : null,
          decoration: const InputDecoration(),
          style: mono
              ? PosText.mono(size: 15, color: context.pos.ink)
              : PosText.ui(size: 15, color: context.pos.ink),
        ),
      ],
    ),
  );
}
