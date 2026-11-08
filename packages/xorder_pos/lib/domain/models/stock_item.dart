import '../../core/money/quantity.dart';

/// Something the business buys and counts — chicken, cooking oil, a bottle
/// of water it also sells.
///
/// **A product row, not a table of its own.** Receiving, stock movements and
/// stock levels all key on `pos_products.id`, and have since Wave P; a second
/// table would have meant a second ledger. What makes one of these different
/// from a menu item is only that it may have no category — and the till's
/// menu query joins categories, so an item without one can never reach the
/// cashier's screen.
class StockItem {
  const StockItem({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.sku,
    this.unit = QuantityUnit.each,
    this.onMenu = false,
    this.isActive = true,
  });

  final int id;
  final String nameEn;
  final String? nameAr;
  final String? sku;

  /// What it is counted and bought in.
  final QuantityUnit unit;

  /// Sold at the till as well. Its name and price are the Menu pane's to
  /// change; here only its unit is.
  final bool onMenu;

  final bool isActive;

  String displayName(String languageCode) =>
      languageCode == 'ar' && (nameAr?.trim().isNotEmpty ?? false)
      ? nameAr!.trim()
      : nameEn;

  StockItem copyWith({
    int? id,
    String? nameEn,
    String? nameAr,
    String? sku,
    QuantityUnit? unit,
    bool? isActive,
  }) => StockItem(
    id: id ?? this.id,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    sku: sku ?? this.sku,
    unit: unit ?? this.unit,
    onMenu: onMenu,
    isActive: isActive ?? this.isActive,
  );
}
