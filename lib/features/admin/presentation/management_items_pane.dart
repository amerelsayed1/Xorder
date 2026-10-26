import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/pos_unit.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/stock_item.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';
import 'stock_item_dialog.dart';

/// What the restaurant buys and counts — on the menu or not.
///
/// Chicken, cooking oil, gas cylinders: bought from suppliers, received into
/// stock, never rung up at the till. And the bottled water it also sells,
/// which is counted the same way. Adding one here is what lets a purchase
/// order name it and a delivery raise its stock.
class ManagementItemsPane extends ConsumerStatefulWidget {
  const ManagementItemsPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementItemsPane> createState() =>
      _ManagementItemsPaneState();
}

class _ManagementItemsPaneState extends ConsumerState<ManagementItemsPane> {
  bool _busy = false;
  String? _note;

  Future<void> _edit(StockItem? item, List<PosUnit> units) async {
    final edited = await StockItemDialog.show(
      context,
      units: units,
      item: item,
      languages: ref.read(contentLanguagesNowProvider),
    );
    if (edited == null || !mounted) return;

    setState(() => _busy = true);
    final result = await ref
        .read(stockItemsRepositoryProvider)
        .save(edited, by: widget.admin);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _note = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });
    if (result.succeeded) {
      ref
        ..invalidate(stockItemsProvider)
        ..invalidate(stockItemsAllProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    // Watched at pane level so the list is loaded before a dialog wants it.
    final units = ref.watch(unitsProvider).valueOrNull ?? const <PosUnit>[];
    final named = {
      for (final unit in ref.watch(unitsAllProvider).valueOrNull ?? const [])
        unit.code: unit.displayName(strings.languageCode),
    };

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneItems, hint: strings.paneItemsBlurb),
        ...ref
            .watch(stockItemsAllProvider)
            .when(
              loading: () => const [SizedBox(height: 40)],
              error: (error, _) => [
                Text(
                  '$error',
                  style: PosText.ui(size: 13, color: context.pos.danger),
                ),
              ],
              data: (items) => items.isEmpty
                  ? [
                      Text(
                        strings.itemsEmpty,
                        style: PosText.ui(size: 13, color: context.pos.muted),
                      ),
                    ]
                  : [
                      for (final item in items)
                        _ItemRow(
                          item: item,
                          unitName:
                              named[item.unit.wire] ??
                              AdminText.unit(strings, item.unit),
                          onEdit: () => _edit(item, units),
                        ),
                    ],
            ),
        if (_note != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(_note!, style: PosText.ui(size: 12.5, color: context.pos.danger)),
        ],
        const SizedBox(height: PosSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PosButton(
            key: const Key('item-new'),
            label: strings.itemNew,
            border: Border.fromBorderSide(context.pos.resting),
            onPressed: _busy ? null : () => _edit(null, units),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.unitName,
    required this.onEdit,
  });

  final StockItem item;
  final String unitName;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return InkWell(
      key: Key('item-row-${item.id}'),
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
        decoration: BoxDecoration(
          border: BorderDirectional(bottom: palette.hairline),
        ),
        child: Opacity(
          opacity: item.isActive ? 1 : 0.5,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.displayName(strings.languageCode),
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
              ),
              if (item.onMenu)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: PosSpace.sm,
                    vertical: 2,
                  ),
                  color: palette.accentSoft,
                  child: Text(
                    strings.itemOnMenu,
                    style: PosText.ui(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: palette.ink,
                    ),
                  ),
                ),
              if (!item.isActive)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  child: Text(
                    strings.unitRetired,
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ),
              SizedBox(
                width: 110,
                child: Text(
                  unitName,
                  style: PosText.ui(size: 12.5, color: palette.body),
                ),
              ),
              if (item.sku case final sku?) MonoCode(sku),
            ],
          ),
        ),
      ),
    );
  }
}
