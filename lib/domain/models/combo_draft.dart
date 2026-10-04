/// Authoring a combo — a meal at one price — as the back office edits it.
///
/// **Deliberately not [Combo].** That class is what the till sells from: its
/// options carry whole `Product`s so a cashier's picker can draw them, and it
/// has no notion of a group that has not been saved yet. An editor built on it
/// would have to carry a product object around to remember one id, and would
/// have nowhere to hold a group typed a second ago. This holds ids and the
/// numbers somebody typed, and nothing else.
library;

import '../../core/money/money.dart';
import 'combo.dart';

/// One choice inside a group, as the editor holds it.
class ComboOptionDraft {
  const ComboOptionDraft({
    required this.productId,
    this.priceDelta = Money.zero,
  });

  /// A real menu item. A combo's components are what the kitchen makes and
  /// the receipt lists, so this names a product rather than copying its name.
  final int productId;

  /// The upgrade — large chips instead of regular, +5.00. Usually zero, and
  /// never negative: a discount on one component is the combo's own price.
  final Money priceDelta;
}

/// "Choose a sandwich." [id] `0` is a group nobody has saved yet.
class ComboGroupDraft {
  const ComboGroupDraft({
    required this.nameEn,
    required this.options,
    this.id = 0,
    this.nameAr,
    this.minSelect = 1,
    this.maxSelect = 1,
  });

  /// Carried through every edit and never reissued, for the reason an option
  /// group's options are: nothing else names a group by its id today, but a
  /// group that got a new one each save would be the first thing that did.
  final int id;

  final String nameEn;
  final String? nameAr;
  final int minSelect;
  final int maxSelect;
  final List<ComboOptionDraft> options;
}

/// A combo as the editor holds it. [id] `0` is a new one.
class ComboDraft {
  const ComboDraft({
    required this.categoryId,
    required this.nameEn,
    required this.price,
    required this.groups,
    this.id = 0,
    this.nameAr,
    this.taxGroupId,
    this.sku,
    this.isAvailable = true,
  });

  /// The editor's starting point for an existing combo.
  factory ComboDraft.of(Combo combo) => ComboDraft(
    id: combo.id,
    categoryId: combo.categoryId,
    nameEn: combo.nameEn,
    nameAr: combo.nameAr,
    price: combo.price,
    taxGroupId: combo.taxGroupId,
    sku: combo.sku,
    isAvailable: combo.isAvailable,
    groups: [
      for (final group in combo.groups)
        ComboGroupDraft(
          id: group.id,
          nameEn: group.nameEn,
          nameAr: group.nameAr,
          minSelect: group.minSelect,
          maxSelect: group.maxSelect,
          options: [
            for (final option in group.options)
              ComboOptionDraft(
                productId: option.product.id,
                priceDelta: option.priceDelta,
              ),
          ],
        ),
    ],
  );

  final int id;
  final int categoryId;
  final String nameEn;
  final String? nameAr;

  /// What the meal costs. Not derived from its components — the point of a
  /// combo is that this is less than their sum.
  final Money price;

  final int? taxGroupId;
  final String? sku;

  /// Whether the till offers it. A combo is retired by clearing this rather
  /// than deleted, because an order line names it and a reprint next year
  /// still has to say what was sold.
  final bool isAvailable;

  final List<ComboGroupDraft> groups;

  ComboDraft copyWith({bool? isAvailable}) => ComboDraft(
    id: id,
    categoryId: categoryId,
    nameEn: nameEn,
    nameAr: nameAr,
    price: price,
    taxGroupId: taxGroupId,
    sku: sku,
    isAvailable: isAvailable ?? this.isAvailable,
    groups: groups,
  );
}

/// Why a combo cannot be saved. Data, not a sentence: the screen words each
/// one in its own language, and a reason added here is a compile error there.
enum ComboProblem {
  /// The English name is blank. It is the one the kitchen ticket prints.
  nameMissing,

  /// No category, so it would appear nowhere on the grid.
  categoryMissing,

  /// Below zero. The database checks it too; refused here so the manager gets
  /// a sentence rather than a constraint name.
  priceNegative,

  /// A combo with nothing to choose or make is an empty line on a docket.
  noGroups,

  /// A group with no name cannot be asked of a cashier.
  groupNameMissing,

  /// A group with no options cannot be completed, so neither can the meal.
  groupEmpty,

  /// Minimum above maximum, a minimum below zero, or a maximum below one.
  /// Migration 18 checks the same thing.
  selectionRange,

  /// The group demands more choices than it offers. A meal nobody can finish.
  minAboveOptions,

  /// The same product twice in one group. `(combo_group_id, product_id)` is
  /// unique in the database; refused here first.
  duplicateOption,

  /// An upgrade below zero.
  deltaNegative,

  // The four below are only knowable against the database, so only the
  // repository says them.

  /// The category is not this restaurant's.
  categoryUnknown,

  /// The tax group is not this restaurant's.
  taxGroupUnknown,

  /// An option names a product that is not this restaurant's.
  productUnknown,

  /// Another combo already carries this SKU.
  skuTaken,
}

/// The rules a combo is checked against before the database is asked.
///
/// Pure, so the same answer comes back on a till and in a unit test. Returns
/// the first thing wrong, or null.
abstract final class ComboRules {
  static ComboProblem? refusal(ComboDraft draft) {
    if (draft.nameEn.trim().isEmpty) return ComboProblem.nameMissing;
    if (draft.categoryId <= 0) return ComboProblem.categoryMissing;
    if (draft.price.minor < 0) return ComboProblem.priceNegative;
    if (draft.groups.isEmpty) return ComboProblem.noGroups;

    for (final group in draft.groups) {
      if (group.nameEn.trim().isEmpty) return ComboProblem.groupNameMissing;
      if (group.options.isEmpty) return ComboProblem.groupEmpty;
      if (group.minSelect < 0 ||
          group.maxSelect < 1 ||
          group.minSelect > group.maxSelect) {
        return ComboProblem.selectionRange;
      }
      if (group.minSelect > group.options.length) {
        return ComboProblem.minAboveOptions;
      }

      final seen = <int>{};
      for (final option in group.options) {
        if (option.priceDelta.minor < 0) return ComboProblem.deltaNegative;
        if (!seen.add(option.productId)) return ComboProblem.duplicateOption;
      }
    }
    return null;
  }
}
