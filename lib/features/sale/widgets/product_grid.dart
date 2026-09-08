import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../domain/models/catalog.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../domain/models/combo.dart';

/// Auto-fill product grid — 132 tall tiles, 10px gutters, vertical scroll only.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.categorySlugs,
    required this.inCartProductIds,
    required this.onTap,
    this.combos = const [],
    this.onTapCombo,
  });

  final List<Product> products;

  /// category id → slug, for the tile's colour bar.
  final Map<int, String?> categorySlugs;

  /// Products already on the ticket get a 2px ink border.
  final Set<int> inCartProductIds;
  final ValueChanged<Product> onTap;

  /// Meals, shown **before** the products in the same category.
  ///
  /// First because that is what a restaurant selling meals wants sold: a combo
  /// buried under forty items is a combo nobody rings up, and the reason it
  /// exists is that it is the thing the shop would rather sell.
  final List<Combo> combos;
  final ValueChanged<Combo>? onTapCombo;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty && combos.isEmpty) {
      return Center(
        child: Text(
          context.strings.noItemsMatch,
          style: PosText.ui(size: 14, color: context.pos.muted),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.s14,
        vertical: PosSpace.md,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: PosSize.productGridMaxExtent,
        mainAxisExtent: PosSize.productTile,
        crossAxisSpacing: PosSize.productGridGutter,
        mainAxisSpacing: PosSize.productGridGutter,
      ),
      itemCount: combos.length + products.length,
      itemBuilder: (context, index) {
        if (index < combos.length) {
          final combo = combos[index];
          return ComboTile(
            combo: combo,
            barColor: context.pos.categoryBar(categorySlugs[combo.categoryId]),
            onTap: () => onTapCombo?.call(combo),
          );
        }

        final product = products[index - combos.length];
        return ProductTile(
          product: product,
          barColor: context.pos.categoryBar(categorySlugs[product.categoryId]),
          inCart: inCartProductIds.contains(product.id),
          onTap: () => onTap(product),
        );
      },
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.barColor,
    required this.inCart,
    required this.onTap,
  });

  final Product product;
  final Color barColor;
  final bool inCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The menu is bilingual data, so the tile leads with the till's language
    // and keeps the other name underneath. A cashier reading العربية and a
    // supplier's English printout are looking at the same item, and the tile
    // is where those two vocabularies have to meet.
    final language = context.strings.languageCode;
    final primary = product.displayName(language);
    final alternate = language == 'ar' ? product.nameEn : product.nameAr;

    final tile = Material(
      color: context.pos.surface,
      child: InkWell(
        // An out-of-stock tile is still tappable so the cashier gets the
        // explanatory toast; the engine is what refuses the line.
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(PosSpace.md),
          decoration: BoxDecoration(
            border: inCart
                ? Border.fromBorderSide(context.pos.emphasis)
                : Border.fromBorderSide(context.pos.resting),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 36, height: 4, color: barColor),
              const SizedBox(height: PosSpace.xs),
              Text(
                primary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: context.pos.ink,
                  height: 1.25,
                ),
              ),
              if (alternate != null && alternate != primary)
                Text(
                  alternate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // The Arabic face only when the line is actually Arabic —
                  // in an Arabic till this second line is the English name.
                  style: language == 'ar'
                      ? PosText.ui(size: 12.5, color: context.pos.muted)
                      : PosText.arabic(color: context.pos.muted),
                ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      product.isAvailable
                          ? product.effectivePrice.format()
                          : context.strings.outOfStockBadge,
                      overflow: TextOverflow.ellipsis,
                      style: PosText.mono(
                        size: 17,
                        weight: FontWeight.w600,
                        color: product.isAvailable
                            ? context.pos.accentPressed
                            : context.pos.warn,
                      ),
                    ),
                  ),
                  if (product.sku != null)
                    Text(
                      product.sku!,
                      style: PosText.mono(size: 10.5, color: context.pos.muted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return product.isAvailable ? tile : Opacity(opacity: 0.5, child: tile);
  }
}

/// A meal on the grid.
///
/// It borrows the product tile's shape so the grid still reads as one grid,
/// and differs by a `MEAL` badge and an accent bar — enough to be picked out,
/// not so much that it looks like a different kind of control.
class ComboTile extends StatelessWidget {
  const ComboTile({
    super.key,
    required this.combo,
    required this.barColor,
    required this.onTap,
  });

  final Combo combo;
  final Color barColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final language = context.strings.languageCode;

    return Opacity(
      opacity: combo.isAvailable ? 1 : 0.5,
      child: Material(
        color: palette.surface,
        child: InkWell(
          onTap: combo.isAvailable ? onTap : null,
          child: Container(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(palette.resting),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 3, color: barColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(PosSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.strings.comboBadge,
                          style: PosText.mono(
                            size: 9.5,
                            weight: FontWeight.w700,
                            color: palette.accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Expanded(
                          child: Text(
                            combo.displayName(language),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: PosText.ui(
                              size: 14,
                              weight: FontWeight.w600,
                              color: palette.ink,
                            ),
                          ),
                        ),
                        MonoAmount(
                          combo.price,
                          size: 15,
                          weight: FontWeight.w700,
                          color: palette.accent,
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
