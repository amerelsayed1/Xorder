/// A meal at one price.
///
/// **A combo is not a product with modifiers.** Its components are real menu
/// items that a kitchen has to make and a receipt has to list; a modifier is an
/// adjustment to one item. Flattening the components into modifiers would price
/// correctly and hand the kitchen a docket for a sandwich with "chips" written
/// on the side of it.
///
/// It is also not the sum of its parts. The whole point of a combo is that
/// 85.00 is less than 45 + 25 + 20, so [Combo.price] is what is charged and the
/// components' own prices are never consulted.
library;

import '../../core/money/money.dart';
import 'catalog.dart';

class Combo {
  const Combo({
    required this.id,
    required this.categoryId,
    required this.nameEn,
    required this.price,
    required this.groups,
    this.nameAr,
    this.taxGroupId,
    this.sku,
    this.isAvailable = true,
    this.sortOrder = 0,
  });

  final int id;
  final int categoryId;
  final String nameEn;
  final String? nameAr;

  /// What the meal costs, before any upgrades.
  final Money price;

  /// Which rate it attracts. Null means the business's default — a combo is
  /// taxed like anything else.
  final int? taxGroupId;

  final String? sku;
  final bool isAvailable;
  final int sortOrder;
  final List<ComboGroup> groups;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// Whether anything has to be asked at all.
  ///
  /// A combo whose every group offers one option and demands one is a fixed
  /// meal: there is nothing to choose, and putting a picker in front of a
  /// cashier for it is three taps to say the only thing that could be said.
  bool get isFixed => groups.every(
    (g) => g.options.length <= 1 && g.minSelect >= g.options.length,
  );

  /// The only possible selection, for a [isFixed] combo.
  List<ComboOption> get fixedSelection => [
    for (final group in groups)
      if (group.options.isNotEmpty) group.options.first,
  ];
}

/// "Choose a sandwich." A group offering one option and demanding one is a
/// fixed component nobody is asked about.
class ComboGroup {
  const ComboGroup({
    required this.id,
    required this.nameEn,
    required this.options,
    this.nameAr,
    this.minSelect = 1,
    this.maxSelect = 1,
    this.sortOrder = 0,
  });

  final int id;
  final String nameEn;
  final String? nameAr;
  final int minSelect;
  final int maxSelect;
  final int sortOrder;
  final List<ComboOption> options;

  bool get isSingleSelect => maxSelect <= 1;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;
}

/// One choice within a group. The product is real; the delta is the upgrade.
class ComboOption {
  const ComboOption({
    required this.id,
    required this.product,
    this.priceDelta = Money.zero,
  });

  final int id;
  final Product product;

  /// Large chips instead of regular, +5.00. Usually zero.
  final Money priceDelta;
}

/// What a cashier chose, and what it comes to.
///
/// A snapshot, like every other price on a ticket: a combo repriced next week
/// must not reprice a table that is still sitting there.
class ComboSelection {
  const ComboSelection({
    required this.comboId,
    required this.nameEn,
    required this.price,
    required this.items,
    this.nameAr,
    this.taxGroupId,
  });

  final int comboId;
  final String nameEn;
  final String? nameAr;

  /// The combo's own price at the moment it was rung up.
  final Money price;

  final int? taxGroupId;

  /// The components, in the order they were chosen.
  final List<ComboItem> items;

  /// The combo price plus every upgrade.
  Money get unitPrice =>
      items.fold(price, (sum, item) => sum + item.priceDelta);

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// What the kitchen is being asked to make.
  String summary(String locale) =>
      items.map((i) => i.displayName(locale)).join(' · ');
}

/// One component of a combo as it was sold.
class ComboItem {
  const ComboItem({
    required this.nameEn,
    this.menuItemId,
    this.nameAr,
    this.priceDelta = Money.zero,
    this.quantity = 1,
  });

  /// Null once the product is deleted. The name is snapshotted for exactly
  /// that reason — a receipt printed in January must still read the same in
  /// March.
  final int? menuItemId;

  final String nameEn;
  final String? nameAr;
  final Money priceDelta;
  final int quantity;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;
}
