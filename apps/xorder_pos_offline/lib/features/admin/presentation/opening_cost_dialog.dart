import 'package:flutter/material.dart';

import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/domain/models/stock_level.dart';

/// The first cost of an item nothing has costed.
///
/// Says what it will and will not do before asking for a number: the stock is
/// valued and sales from now on are costed, but sales already made stay at the
/// zero they were recorded at, and the quantity is not touched. A manager who
/// expects last month's profit to change should find out here, not afterwards.
///
/// Returns the cost, in major units parsed without a double (`Money.tryParse`),
/// and only a cost that is more than zero — zero is the very state being left.
class OpeningCostDialog extends StatefulWidget {
  const OpeningCostDialog({
    required this.level,
    required this.unitName,
    super.key,
  });

  final StockLevel level;

  /// The unit the business calls it, for "12.5 Kilogram".
  final String unitName;

  static Future<Money?> show(
    BuildContext context, {
    required StockLevel level,
    required String unitName,
  }) => showDialog<Money>(
    context: context,
    builder: (_) => OpeningCostDialog(level: level, unitName: unitName),
  );

  @override
  State<OpeningCostDialog> createState() => _OpeningCostDialogState();
}

class _OpeningCostDialogState extends State<OpeningCostDialog> {
  final _cost = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _cost.dispose();
    super.dispose();
  }

  void _save() {
    final strings = context.strings;
    final cost = Money.tryParse(_cost.text);
    if (cost == null) {
      setState(() => _problem = strings.priceIsNotANumber);
      return;
    }
    if (cost.minor <= 0) {
      setState(() => _problem = strings.refusalOpeningCostNotPositive);
      return;
    }
    Navigator.of(context).pop(cost);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final level = widget.level;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.stockOpeningCostTitle(
                  level.displayName(strings.languageCode),
                ),
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                '${level.onHand.format()} ${widget.unitName}',
                style: PosText.mono(size: 13, color: palette.muted),
              ),
              const SizedBox(height: PosSpace.md),
              Text(
                strings.stockOpeningCostHint,
                style: PosText.ui(size: 12.5, color: palette.muted, height: 1.5),
              ),
              const SizedBox(height: PosSpace.lg),
              MicroLabel(strings.stockOpeningCostField),
              const SizedBox(height: PosSpace.xs),
              TextField(
                key: const Key('opening-cost-field'),
                controller: _cost,
                autofocus: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _problem = null),
                onSubmitted: (_) => _save(),
                style: PosText.mono(size: 15, color: palette.ink),
              ),
              if (_problem != null) ...[
                const SizedBox(height: PosSpace.md),
                Text(
                  _problem!,
                  key: const Key('opening-cost-problem'),
                  style: PosText.ui(size: 12.5, color: palette.danger),
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
                    child: PosButton(
                      key: const Key('opening-cost-save'),
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
