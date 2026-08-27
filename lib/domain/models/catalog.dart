import '../../core/money/money.dart';

/// A sellable product as the till caches it.
///
/// Field names deliberately mirror `docs/pos/05-data-contracts.md` so the DTO
/// layer is a rename-free mapping. `sku` and `barcode` are nullable because the
/// backend does not have those columns yet — see POS-BE-004, still `PROPOSED`.
class Product {
  const Product({
    required this.id,
    required this.categoryId,
    required this.nameEn,
    required this.price,
    this.nameAr,
    this.discountedPrice,
    this.sku,
    this.barcode,
    this.isAvailable = true,
    this.modifierGroupIds = const [],
  });

  final int id;
  final int categoryId;
  final String nameEn;
  final String? nameAr;
  final Money price;
  final Money? discountedPrice;
  final String? sku;
  final String? barcode;

  /// `false` renders the tile at 50% opacity showing `OUT`, and blocks adding.
  final bool isAvailable;
  final List<int> modifierGroupIds;

  /// What the customer actually pays before modifiers.
  Money get effectivePrice => discountedPrice ?? price;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false) ? nameAr! : nameEn;
}

class Category {
  const Category({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.slug,
    this.sortOrder = 0,
  });

  final int id;
  final String nameEn;
  final String? nameAr;

  /// Drives the 4×36px colour bar on each product tile.
  final String? slug;
  final int sortOrder;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false) ? nameAr! : nameEn;
}

/// A modifier group — the server's `option_group`.
class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.nameEn,
    required this.modifiers,
    this.nameAr,
    this.isRequired = false,
    this.maxSelect = 1,
    this.isVariant = false,
  });

  final int id;
  final String nameEn;
  final String? nameAr;
  final List<Modifier> modifiers;

  /// A required group blocks "Add to ticket" until satisfied.
  final bool isRequired;

  /// `1` means single-select: picking replaces the previous choice.
  final int maxSelect;

  /// A variant group *prices* the item (size) rather than adding to it.
  final bool isVariant;

  bool get isSingleSelect => maxSelect <= 1;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false) ? nameAr! : nameEn;
}

class Modifier {
  const Modifier({
    required this.id,
    required this.groupId,
    required this.nameEn,
    required this.priceDelta,
    this.nameAr,
    this.isAvailable = true,
  });

  final int id;
  final int groupId;
  final String nameEn;
  final String? nameAr;

  /// May be zero (a "Remove onions" style option) or negative.
  final Money priceDelta;
  final bool isAvailable;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false) ? nameAr! : nameEn;
}

/// The catalog as one immutable snapshot, so the sale screen never reads a
/// half-applied delta sync.
class Catalog {
  const Catalog({
    required this.categories,
    required this.products,
    required this.modifierGroups,
    required this.syncedAt,
  });

  final List<Category> categories;
  final List<Product> products;
  final List<ModifierGroup> modifierGroups;
  final DateTime syncedAt;

  static final empty = Catalog(
    categories: const [],
    products: const [],
    modifierGroups: const [],
    syncedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  List<Product> inCategory(int? categoryId) => categoryId == null
      ? products
      : products.where((p) => p.categoryId == categoryId).toList();

  ModifierGroup? group(int id) =>
      modifierGroups.where((g) => g.id == id).firstOrNull;

  List<ModifierGroup> groupsFor(Product product) => product.modifierGroupIds
      .map(group)
      .whereType<ModifierGroup>()
      .toList();

  /// Search across name, SKU and barcode — the one lookup the F2 field and the
  /// scanner both go through, so a scan and a typed PLU behave identically.
  List<Product> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return products;

    return products.where((p) {
      return p.nameEn.toLowerCase().contains(needle) ||
          (p.nameAr?.contains(query.trim()) ?? false) ||
          (p.sku?.toLowerCase() == needle) ||
          (p.barcode == needle);
    }).toList();
  }

  /// An exact barcode match, which is what a scanner needs — a partial match
  /// would ring up the wrong product.
  Product? byBarcode(String barcode) =>
      products.where((p) => p.barcode == barcode).firstOrNull;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
