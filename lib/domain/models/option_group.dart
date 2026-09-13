import '../../core/money/money.dart';

/// Authoring an item's sizes and extras — the platform's option groups — as
/// the back office edits them.
///
/// **Deliberately not `ModifierGroup`.** That class is what the till sells
/// from: its options carry the price a customer is *charged*, which for a size
/// on sale is the sale price, and it has no idea whether a group is shared or
/// how it reaches an item. An editor built on it would have to reverse the
/// first and guess the second, and a save that wrote the charged price back as
/// the regular one would quietly end every sale it touched.

/// How a library group reaches items. The platform's `apply_scope`.
enum OptionGroupScope {
  /// Linked to chosen items one by one, in each item's own order.
  items('items'),

  /// Every item in the linked categories, without a link per item.
  categories('categories'),

  /// Every item on the menu.
  all('all');

  const OptionGroupScope(this.wire);

  final String wire;

  /// An unknown scope reads as [items]: a group read that way reaches only
  /// what is linked to it, which is the direction that cannot put a charge on
  /// an item nobody chose.
  static OptionGroupScope fromWire(String? value) {
    for (final scope in values) {
      if (scope.wire == value) return scope;
    }
    return items;
  }
}

/// One option as the editor holds it. [id] `0` is a new one.
class OptionDraft {
  const OptionDraft({
    required this.nameEn,
    this.id = 0,
    this.nameAr,
    this.price = Money.zero,
    this.salePrice,
    this.isAvailable = true,
  });

  /// Carried through every edit and never reissued. A parked ticket and every
  /// `pos_order_lines.modifier_ids` name options by id, so an option that got
  /// a new one each time its group was saved — which is what the platform
  /// does — would turn yesterday's Large into a number nothing answers to.
  final int id;

  final String nameEn;
  final String? nameAr;

  /// The regular price. For an extra it is **added** to the item; for a size
  /// it **is** the item's price.
  final Money price;

  /// A size on offer. Only a size can have one: an extra's price is a delta,
  /// and a discount on a delta means nothing a customer could be told.
  final Money? salePrice;

  final bool isAvailable;

  OptionDraft copyWith({
    int? id,
    String? nameEn,
    String? nameAr,
    Money? price,
    Money? salePrice,
    bool clearSalePrice = false,
    bool? isAvailable,
  }) => OptionDraft(
    id: id ?? this.id,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    price: price ?? this.price,
    salePrice: clearSalePrice ? null : (salePrice ?? this.salePrice),
    isAvailable: isAvailable ?? this.isAvailable,
  );
}

/// One option group as the editor holds it — a library group, or one typed on
/// a single item. [id] `0` is a new one.
class OptionGroupDraft {
  const OptionGroupDraft({
    required this.nameEn,
    this.id = 0,
    this.revision = 0,
    this.nameAr,
    this.displayNameEn,
    this.displayNameAr,
    this.isVariant = false,
    this.isRequired = false,
    this.maxSelect = 1,
    this.minSelect = 0,
    this.freeOptions = 0,
    this.scope = OptionGroupScope.items,
    this.categoryIds = const <int>{},
    this.options = const [],
  });

  final int id;

  /// What the row said when this was read. A save naming an older one is
  /// refused rather than applied on top — two managers on two tills is the
  /// normal case in a branch.
  final int revision;

  /// The library name — what the back office calls it.
  final String nameEn;
  final String? nameAr;

  /// The heading the cashier sees, when it should read differently from the
  /// library name ("Burger sizes" in the library, "Size" on the sheet). Blank
  /// means use the library name.
  final String? displayNameEn;
  final String? displayNameAr;

  /// Sizes: one must be chosen, and it prices the item rather than adding to
  /// it. See [normalized].
  final bool isVariant;

  final bool isRequired;
  final int maxSelect;

  /// The till's own additions — "two toppings included" — which the platform
  /// has no column for. Kept working rather than dropped, because a
  /// restaurant already pricing pizzas this way would lose it on first save.
  final int minSelect;
  final int freeOptions;

  /// Only a library group has anything but [OptionGroupScope.items].
  final OptionGroupScope scope;

  /// Only meaningful with [OptionGroupScope.categories].
  final Set<int> categoryIds;

  /// In the order shown. The first available one of a size group is the
  /// item's default, so reordering sizes changes the price on the tile — the
  /// platform's rule, and the one the editor has to say out loud.
  final List<OptionDraft> options;

  /// What the rules make of it before anything is checked or written.
  ///
  /// **Forced, not refused**, the way the platform does it: a size is always
  /// required and single-select — "no size" and "two sizes" are both
  /// meaningless when the size *is* the price — and an extra's sale price is
  /// dropped. Refusing either would put an error in front of a manager for a
  /// box the editor should not have offered.
  OptionGroupDraft normalized() {
    final required = isVariant || isRequired;
    return OptionGroupDraft(
      id: id,
      revision: revision,
      nameEn: nameEn.trim(),
      nameAr: _blankToNull(nameAr),
      displayNameEn: _blankToNull(displayNameEn),
      displayNameAr: _blankToNull(displayNameAr),
      isVariant: isVariant,
      isRequired: required,
      maxSelect: isVariant ? 1 : maxSelect,
      // A required group needs at least one — migration 22 states it once in
      // the data, and a group saved here must not be the row that disagrees.
      minSelect: isVariant ? 1 : (required && minSelect < 1 ? 1 : minSelect),
      // A free size would be a free item.
      freeOptions: isVariant ? 0 : freeOptions,
      scope: scope,
      categoryIds: scope == OptionGroupScope.categories
          ? categoryIds
          : const <int>{},
      options: [
        for (final option in options)
          OptionDraft(
            id: option.id,
            nameEn: option.nameEn.trim(),
            nameAr: _blankToNull(option.nameAr),
            price: option.price,
            salePrice: isVariant ? option.salePrice : null,
            isAvailable: option.isAvailable,
          ),
      ],
    );
  }

  OptionGroupDraft copyWith({
    int? id,
    int? revision,
    String? nameEn,
    String? nameAr,
    String? displayNameEn,
    String? displayNameAr,
    bool? isVariant,
    bool? isRequired,
    int? maxSelect,
    int? minSelect,
    int? freeOptions,
    OptionGroupScope? scope,
    Set<int>? categoryIds,
    List<OptionDraft>? options,
  }) => OptionGroupDraft(
    id: id ?? this.id,
    revision: revision ?? this.revision,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    displayNameEn: displayNameEn ?? this.displayNameEn,
    displayNameAr: displayNameAr ?? this.displayNameAr,
    isVariant: isVariant ?? this.isVariant,
    isRequired: isRequired ?? this.isRequired,
    maxSelect: maxSelect ?? this.maxSelect,
    minSelect: minSelect ?? this.minSelect,
    freeOptions: freeOptions ?? this.freeOptions,
    scope: scope ?? this.scope,
    categoryIds: categoryIds ?? this.categoryIds,
    options: options ?? this.options,
  );

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// One entry in an item's ordered list of groups.
///
/// Sealed, so the repository's switch over it is exhaustive: a third kind of
/// entry fails to compile everywhere it would otherwise be silently skipped.
sealed class OptionGroupRef {
  const OptionGroupRef();

  /// A library group, by id. Its options are edited in the library, never
  /// here, because the same row is on every item that uses it.
  const factory OptionGroupRef.shared(int groupId) = SharedGroupRef;

  /// A group that belongs to this item alone, written with it.
  const factory OptionGroupRef.inline(OptionGroupDraft group) = InlineGroupRef;
}

final class SharedGroupRef extends OptionGroupRef {
  const SharedGroupRef(this.groupId);

  final int groupId;
}

final class InlineGroupRef extends OptionGroupRef {
  const InlineGroupRef(this.group);

  final OptionGroupDraft group;
}

/// A library group, and how many items it reaches.
class LibraryGroup {
  const LibraryGroup({required this.group, required this.itemCount});

  final OptionGroupDraft group;

  /// Every item this group is on, by whichever path it reaches them — linked
  /// one by one, through a category, or everywhere.
  ///
  /// Counted by reach rather than by link, unlike the platform's count, which
  /// reads zero for a group on every item because it has no links. "Used by 0
  /// items" beside the group that prices the whole menu is the sentence that
  /// gets a group deleted.
  final int itemCount;
}

/// Why an option group, or an item's list of them, cannot be saved.
///
/// **A code, not a sentence.** These used to travel as English inside
/// `CatalogInvalid`, which is fine on the importer that owns that refusal and
/// wrong here: the editor is used in Arabic, and a refusal that arrives as a
/// finished English sentence has nothing left to translate. Enum-keyed so the
/// switch that words them (`AdminText.optionGroupProblem`) is exhaustive — a
/// reason added here without both languages fails to compile.
///
/// The ones that name something — a group, an item, several sizes — carry the
/// names beside them on `OptionGroupRefused`, not in the code.
enum OptionGroupProblem {
  nameMissing,
  scopeNeedsLibrary,
  categoriesMissing,
  choicesOutOfRange,
  negativeCounts,
  needsMoreThanAllows,
  tooManyOptions,
  requiredButEmpty,
  optionNameMissing,
  optionTwice,
  negativePrice,
  saleNotBelowPrice,

  /// The same group twice in one item's list.
  groupTwice,

  /// An item's own group, named in another item's list.
  typedOnAnotherItem,

  /// A group typed on one item, offered as a library group. Names the group.
  notInLibrary,

  /// A library group that already reaches the item by category or everywhere.
  /// Names the group.
  alreadyReaches,

  /// The item would carry more than one set of sizes. Names every one of them.
  secondSizes,

  /// A library size group that would give an item a second set. Names the
  /// first such item.
  wouldGiveSecondSizes,

  /// A library write aimed at a group that belongs to one item.
  belongsToOneItem,

  /// An item write aimed at a library group.
  belongsToLibrary,

  foreignOption,
  foreignCategory,
}

/// What makes an option group savable, asked of its [OptionGroupDraft.normalized]
/// form.
///
/// Pure, so the rules the platform enforces can be tested without a database;
/// the repository asks the questions only it can answer — whose categories,
/// whose options, and whether an item would end up with two sets of sizes.
abstract final class OptionGroupRules {
  /// The platform's own limits, so a group authored here can be sent up
  /// unchanged once offline menus sync.
  static const maxOptions = 50;
  static const maxChoices = 50;

  /// Why [group] cannot be saved as written, or null if it can.
  ///
  /// [inLibrary] is whether it is a library group; only those may reach items
  /// by category or everywhere.
  static OptionGroupProblem? refusal(
    OptionGroupDraft group, {
    required bool inLibrary,
  }) {
    if (group.nameEn.isEmpty) return OptionGroupProblem.nameMissing;
    if (!inLibrary && group.scope != OptionGroupScope.items) {
      return OptionGroupProblem.scopeNeedsLibrary;
    }
    if (group.scope == OptionGroupScope.categories &&
        group.categoryIds.isEmpty) {
      return OptionGroupProblem.categoriesMissing;
    }
    if (group.maxSelect < 1 || group.maxSelect > maxChoices) {
      return OptionGroupProblem.choicesOutOfRange;
    }
    if (group.minSelect < 0 || group.freeOptions < 0) {
      return OptionGroupProblem.negativeCounts;
    }
    if (group.minSelect > group.maxSelect) {
      return OptionGroupProblem.needsMoreThanAllows;
    }
    if (group.options.length > maxOptions) {
      return OptionGroupProblem.tooManyOptions;
    }
    // The platform allows it; the till cannot sell it. A required group with
    // nothing in it can never be satisfied, so the item it is on could never
    // be added to a ticket.
    if (group.isRequired && group.options.isEmpty) {
      return OptionGroupProblem.requiredButEmpty;
    }

    final seen = <int>{};
    for (final option in group.options) {
      if (option.nameEn.isEmpty) return OptionGroupProblem.optionNameMissing;
      if (option.id != 0 && !seen.add(option.id)) {
        return OptionGroupProblem.optionTwice;
      }
      if (option.price.minor < 0) return OptionGroupProblem.negativePrice;
      final sale = option.salePrice;
      if (sale != null && (sale.minor < 0 || sale.minor >= option.price.minor)) {
        return OptionGroupProblem.saleNotBelowPrice;
      }
    }
    return null;
  }
}
