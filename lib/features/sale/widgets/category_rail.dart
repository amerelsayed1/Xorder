import 'package:flutter/material.dart';

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
    required this.onOpenTickets,
    required this.onTables,
    this.openTicketCount = 0,
  });

  final Catalog catalog;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  final VoidCallback onOpenTickets;
  final VoidCallback onTables;
  final int openTicketCount;

  @override
  Widget build(BuildContext context) {
    final categories = [...catalog.categories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Container(
      width: PosSize.categoryRail,
      decoration: const BoxDecoration(
        color: PosColors.surface,
        border: Border(right: PosBorders.emphasis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(PosSpace.s14, PosSpace.md, PosSpace.s14, PosSpace.sm),
            child: MicroLabel('Categories'),
          ),
          Expanded(
            child: ListView(
              children: [
                _row(null, 'All items', catalog.products.length),
                for (final category in categories)
                  _row(
                    category.id,
                    category.nameEn,
                    catalog.inCategory(category.id).length,
                  ),
              ],
            ),
          ),
          // Pinned section with a 2px ink top border.
          Container(
            decoration: const BoxDecoration(border: Border(top: PosBorders.emphasis)),
            padding: const EdgeInsets.all(PosSpace.sm),
            child: Column(
              children: [
                PosButton(
                  label: 'Open tickets',
                  border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
                  alignLeft: true,
                  trailing: Text(
                    '$openTicketCount',
                    style: PosText.mono(size: 12, weight: FontWeight.w600, color: PosColors.danger),
                  ),
                  onPressed: onOpenTickets,
                ),
                const SizedBox(height: PosSpace.sm),
                PosButton(
                  label: 'Tables',
                  foreground: PosColors.body,
                  border: const Border.fromBorderSide(PosBorders.hairline),
                  onPressed: onTables,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int? id, String label, int count) {
    final active = id == selectedId;

    return Material(
      color: active ? PosColors.accent : Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(id),
        child: Container(
          height: PosSize.categoryRow,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
          decoration: const BoxDecoration(border: Border(top: PosBorders.hairline)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(
                    size: 14,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? Colors.white : PosColors.inkWarm,
                  ),
                ),
              ),
              Opacity(
                opacity: 0.75,
                child: Text(
                  '$count',
                  style: PosText.mono(
                    size: 11.5,
                    color: active ? Colors.white : PosColors.inkWarm,
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
