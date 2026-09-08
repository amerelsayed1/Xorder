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
    this.sortOrder = 0,
    this.modifierGroupIds = const [],
    this.isOpenPrice = false,
    this.taxGroupId,
  });

  /// A one-off item somebody typed a price for (§17 open item).
  ///
  /// It is a `Product` because everything downstream — the merge key, the line
  /// total, discounts, voids, the receipt — already works in terms of one, and
  /// giving `TicketLine` a second shape would mean touching all of it to gain
  /// nothing. What it is *not* is a menu item, which is why [isOpenPrice] is a
  /// flag rather than a convention about the id: `menu_item_id` must be written
  /// NULL, and a rule like "negative ids are custom" is one every future reader
  /// has to be told.
  ///
  /// [id] is negative and unique per line so two custom items on one ticket do
  /// not merge into each other — `TicketLine.keyFor` keys on the product id,
  /// and two different one-off charges are two different things.
  factory Product.openPrice({
    required int id,
    required String name,
    required Money price,
  }) => Product(
    id: id,
    // No category: it belongs to no part of the menu, and putting it in one
    // would make it appear on a grid nobody added it to.
    categoryId: 0,
    nameEn: name,
    price: price,
    isOpenPrice: true,
  );

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

  /// Where it sits on the grid. The column has always existed and the read
  /// query has always ordered by it; the model simply never carried it, which
  /// made "move this up" impossible to express.
  final int sortOrder;

  final List<int> modifierGroupIds;

  /// This line has no menu item behind it. See [Product.openPrice].
  final bool isOpenPrice;

  /// Which rate this attracts. Null means the restaurant's default.
  ///
  /// Nullable rather than defaulted, because "nobody has said" and "somebody
  /// chose the standard rate" are different facts: the first follows the
  /// restaurant if it changes its default, and the second does not.
  final int? taxGroupId;

  /// What the customer actually pays before modifiers.
  Money get effectivePrice => discountedPrice ?? price;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// Editing needs to change one field and keep the rest.
  ///
  /// `discountedPrice` is deliberately awkward: it is nullable AND clearable,
  /// so a plain `Money?` argument could not tell "leave it" from "remove it".
  /// [clearDiscount] is how a form says the second one.
  Product copyWith({
    int? id,
    int? categoryId,
    String? nameEn,
    String? nameAr,
    Money? price,
    Money? discountedPrice,
    bool clearDiscount = false,
    String? sku,
    String? barcode,
    bool? isAvailable,
    int? sortOrder,
    List<int>? modifierGroupIds,
    int? taxGroupId,
    bool clearTaxGroup = false,
  }) => Product(
    id: id ?? this.id,
    categoryId: categoryId ?? this.categoryId,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    price: price ?? this.price,
    discountedPrice: clearDiscount
        ? null
        : (discountedPrice ?? this.discountedPrice),
    sku: sku ?? this.sku,
    barcode: barcode ?? this.barcode,
    isAvailable: isAvailable ?? this.isAvailable,
    sortOrder: sortOrder ?? this.sortOrder,
    modifierGroupIds: modifierGroupIds ?? this.modifierGroupIds,
    // Carried, never edited: a copy of an open-price line is still not a menu
    // item, and an edit that quietly made it one would write a `menu_item_id`
    // pointing at nothing.
    isOpenPrice: isOpenPrice,
    taxGroupId: clearTaxGroup ? null : (taxGroupId ?? this.taxGroupId),
  );
}

class Category {
  const Category({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.slug,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final int id;
  final String nameEn;
  final String? nameAr;

  /// Drives the 4×36px colour bar on each product tile.
  final String? slug;
  final int sortOrder;

  /// Archived categories keep their products and their history.
  ///
  /// `pos_products.category_id` is `ON DELETE RESTRICT`, so a category that
  /// ever held anything cannot be deleted — which is the right answer, because
  /// deleting one would orphan every sale that named it. The read query
  /// already filters on this; the model never carried it.
  final bool isActive;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  Category copyWith({
    int? id,
    String? nameEn,
    String? nameAr,
    String? slug,
    int? sortOrder,
    bool? isActive,
  }) => Category(
    id: id ?? this.id,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    slug: slug ?? this.slug,
    sortOrder: sortOrder ?? this.sortOrder,
    isActive: isActive ?? this.isActive,
  );
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
    this.minSelect = 0,
    this.freeOptions = 0,
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

  /// How many must be chosen. [isRequired] is the same statement in coarser
  /// words, and a required group has a minimum of at least one.
  final int minSelect;

  /// How many are included before the option prices start applying.
  ///
  /// "Two toppings included, then 5.00 each" is how half the market prices a
  /// pizza, and it was inexpressible: the schema had a price per option and no
  /// way to say the first two are free.
  final int freeOptions;

  bool get isSingleSelect => maxSelect <= 1;

  /// The smallest number this group will accept.
  int get effectiveMinimum => isRequired && minSelect < 1 ? 1 : minSelect;

  /// What [chosen] costs, once the free allowance is taken off.
  ///
  /// **The cheapest options are the free ones.** A customer who picks two
  /// toppings with one included should be charged for the dearer, not the
  /// nearer-to-hand — anything else makes the price depend on tap order, which
  /// is the sort of thing a customer notices and a cashier cannot explain.
  List<Modifier> chargeable(List<Modifier> chosen) {
    if (freeOptions <= 0 || chosen.length <= freeOptions) {
      return freeOptions <= 0 ? chosen : const [];
    }
    final sorted = [...chosen]
      ..sort((a, b) => a.priceDelta.minor.compareTo(b.priceDelta.minor));
    return sorted.sublist(freeOptions);
  }

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;
}

class Modifier {
  const Modifier({
    required this.id,
    required this.groupId,
    required this.nameEn,
    required this.priceDelta,
    this.nameAr,
    this.isAvailable = true,
    this.isDefault = false,
  });

  final int id;
  final int groupId;
  final String nameEn;
  final String? nameAr;

  /// May be zero (a "Remove onions" style option) or negative.
  final Money priceDelta;
  final bool isAvailable;

  /// Ticked when the sheet opens. "Regular size" already chosen is the
  /// difference between three taps and one.
  final bool isDefault;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;
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

  List<ModifierGroup> groupsFor(Product product) =>
      product.modifierGroupIds.map(group).whereType<ModifierGroup>().toList();

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
