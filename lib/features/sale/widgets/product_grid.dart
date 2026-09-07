import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../domain/models/catalog.dart';

/// Auto-fill product grid — 132 tall tiles, 10px gutters, vertical scroll only.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.categorySlugs,
    required this.inCartProductIds,
    required this.onTap,
  });

  final List<Product> products;

  /// category id → slug, for the tile's colour bar.
  final Map<int, String?> categorySlugs;

  /// Products already on the ticket get a 2px ink border.
  final Set<int> inCartProductIds;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
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
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
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
