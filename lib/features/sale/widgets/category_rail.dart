import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/catalog.dart';

/// 186px rail on surface with a 2px ink right border.
class CategoryRail extends StatelessWidget {
  const CategoryRail({
    super.key,
    required this.catalog,
    required this.selectedId,
    required this.onSelect,
    required this.onTables,
    this.onOrders,
    this.openTicketCount = 0,
  });

  final Catalog catalog;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  final VoidCallback onTables;

  /// Order history. Null when the person at the till may not see it — the
  /// button is then absent rather than greyed, because a control that is dead
  /// for a cashier's whole shift is clutter in a rail they use all day.
  final VoidCallback? onOrders;
  final int openTicketCount;

  @override
  Widget build(BuildContext context) {
    final categories = [...catalog.categories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final strings = context.strings;

    return Container(
      width: PosSize.categoryRail,
      decoration: BoxDecoration(
        color: context.pos.surface,
        border: Border(right: context.pos.emphasis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PosSpace.s14,
              PosSpace.md,
              PosSpace.s14,
              PosSpace.sm,
            ),
            child: MicroLabel(strings.categories),
          ),
          Expanded(
            child: ListView(
              children: [
                _row(null, strings.allItems, catalog.products.length, pos: context.pos),
                for (final category in categories)
                  _row(
                    category.id,
                    // The category comes from the menu, not from this file —
                    // its own Arabic name if the branch entered one.
                    category.displayName(strings.languageCode),
                    catalog.inCategory(category.id).length,
                  pos: context.pos),
              ],
            ),
          ),
          // Pinned section with a 2px ink top border.
          Container(
            decoration: BoxDecoration(
              border: Border(top: context.pos.emphasis),
            ),
            padding: const EdgeInsets.all(PosSpace.sm),
            child: Column(
              children: [
                // "Open tickets" used to sit here, above Tables, toasting
                // "not built yet". It was a second door to the same room: an
                // open ticket in this product is a seated table, and Tables is
                // where they are. The count it carried is not lost — it moved
                // on to the Tables button, where it belongs.
                PosButton(
                  label: strings.tables,
                  trailing: openTicketCount == 0
                      ? null
                      : Text(
                          '$openTicketCount',
                          style: PosText.mono(
                            size: 12,
                            weight: FontWeight.w600,
                            color: context.pos.danger,
                          ),
                        ),
                  alignLeft: openTicketCount > 0,
                  foreground: context.pos.body,
                  border: Border.fromBorderSide(context.pos.hairline),
                  onPressed: onTables,
                ),
                if (onOrders != null) ...[
                  const SizedBox(height: PosSpace.sm),
                  PosButton(
                    label: strings.orderHistoryTitle,
                    foreground: context.pos.body,
                    border: Border.fromBorderSide(context.pos.hairline),
                    alignLeft: true,
                    trailing: const KeyChip('F7'),
                    onPressed: onOrders,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int? id, String label, int count, {required PosPalette pos}) {
    final active = id == selectedId;

    return Material(
      color: active ? pos.accent : Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(id),
        // No hover, splash or press overlay. Material's defaults paint a pale
        // wash OVER the accent fill, which turns the selected row's white
        // label into grey-on-peach — unreadable at a glance, which is the one
        // thing a category rail cannot afford. Selection is shown by the fill
        // itself, the same way elevation here is a border rather than a
        // shadow.
        // Redundant now that the theme sets all three, and kept because a
        // rail row is the densest list in the product — if the global ever
        // moves, this one must not.
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Container(
          height: PosSize.categoryRow,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
          decoration: BoxDecoration(
            border: Border(top: pos.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(
                    size: 14,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? Colors.white : pos.inkWarm,
                  ),
                ),
              ),
              Opacity(
                opacity: 0.75,
                child: Text(
                  '$count',
                  style: PosText.mono(
                    size: 11.5,
                    color: active ? Colors.white : pos.inkWarm,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
