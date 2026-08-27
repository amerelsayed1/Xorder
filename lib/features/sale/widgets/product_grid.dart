import 'package:flutter/material.dart';

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
          'No items match.',
          style: PosText.ui(size: 14, color: PosColors.muted),
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
          barColor: PosColors.categoryBar(categorySlugs[product.categoryId]),
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
    final tile = Material(
      color: PosColors.surface,
      child: InkWell(
        // An out-of-stock tile is still tappable so the cashier gets the
        // explanatory toast; the engine is what refuses the line.
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(PosSpace.md),
          decoration: BoxDecoration(
            border: inCart
                ? const Border.fromBorderSide(PosBorders.emphasis)
                : const Border.fromBorderSide(PosBorders.resting),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 36, height: 4, color: barColor),
              const SizedBox(height: PosSpace.xs),
              Text(
                product.nameEn,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: PosColors.ink,
                  height: 1.25,
                ),
              ),
              if (product.nameAr != null)
                Text(
                  product.nameAr!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.arabic(),
                ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      product.isAvailable ? product.effectivePrice.format() : 'OUT',
                      overflow: TextOverflow.ellipsis,
                      style: PosText.mono(
                        size: 17,
                        weight: FontWeight.w600,
                        color: product.isAvailable ? PosColors.accentPressed : PosColors.warn,
                      ),
                    ),
                  ),
                  if (product.sku != null)
                    Text(
                      product.sku!,
                      style: PosText.mono(size: 10.5, color: PosColors.muted),
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
