import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/models/pos_unit.dart';
import '../../../core/money/quantity.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/destructive_confirm_dialog.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/reason_code.dart' show ReasonRequirement;
import '../../../data/postgres/pos_database.dart' show PosDbException;
import '../../../domain/models/catalog.dart';
import '../../../domain/models/content_languages.dart';
import 'content_language_ui.dart';
import '../../../domain/models/option_group.dart';
import '../../../domain/models/tax.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import 'admin_messages.dart';
import 'management_extras_pane.dart' show groupName;
import 'menu_editor_widgets.dart';
import 'menu_import_dialog.dart';

/// The menu, authored on the till.
///
/// **Offline only** — the pane is not in the rail otherwise. On a cloud
/// terminal the platform is the author and `BootstrapSeeder` overwrites this
/// database's catalogue wholesale, so an editor there would be an invitation
/// to lose an afternoon's work at the next sync.
///
/// Nothing here deletes. A category is archived because
/// `pos_products.category_id` is `ON DELETE RESTRICT`, and an item is taken
/// off sale because every past receipt still names its row.
/// Which of the two pages in the Menu tab this is.
///
/// They used to be one screen reached by two drop-down entries, "Menu" and
/// "Sections". The owner's map asks for both, so they are now two pages: the
/// Menu page is items grouped by section, with Add item inside each section; the
/// Sections page is the sections themselves, with how many items each holds.
enum MenuPaneMode { menu, sections }

class ManagementMenuPane extends ConsumerStatefulWidget {
  const ManagementMenuPane({
    required this.admin,
    this.onOpenExtras,
    this.mode = MenuPaneMode.menu,
    super.key,
  });

  final PosStaff admin;

  final MenuPaneMode mode;

  /// Switch Management to the Extras library — the item editor's "Manage
  /// extras" link. Null hides the link.
  final VoidCallback? onOpenExtras;

  @override
  ConsumerState<ManagementMenuPane> createState() => _ManagementMenuPaneState();
}

class _ManagementMenuPaneState extends ConsumerState<ManagementMenuPane> {
  int? _categoryId;

  /// Run a write, report a refusal, and refresh what the till shows.
  ///
  /// `catalogProvider` is invalidated by exactly one thing today — a cloud sync
  /// that re-seeded — and that never fires offline. Without this the sale
  /// screen would keep showing yesterday's prices until the app restarted.
  Future<void> _write(Future<AdminResult<Object?>> Function() action) async {
    final result = await action();
    if (!mounted) return;

    final refusal = result.refusal;
    if (refusal != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminText.refusal(context.strings, refusal))),
      );
      return;
    }
    ref.invalidate(catalogProvider);
    ref.invalidate(inactiveCategoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read, so the menu languages are resolved by the time a dialog
    // opens and asks for them (XORD-005); a read in the dialog's builder would
    // find the provider still loading and fall back to "both".
    ref.watch(contentLanguagesProvider);
    final repository = ref.watch(catalogAdminRepositoryProvider);
    final catalog = ref.watch(catalogProvider);

    // **Watched here, not read when the dialog opens.** A `read` on a
    // `FutureProvider` nobody has watched returns no value, so the rate picker
    // was absent until something else happened to load the list — which on a
    // real till is never, because this is the only screen that wants it. Watched
    // at pane level the request starts with the pane and the value is there by
    // the time an editor opens; passing it down keeps the dialog from rebuilding
    // on a change and throwing away what somebody typed.
    final taxGroups = ref.watch(taxGroupsAllProvider).valueOrNull ?? const [];
    final units = ref.watch(unitsProvider).valueOrNull ?? const <PosUnit>[];
    final strings = context.strings;
    if (repository == null) {
      return _Centred(text: strings.menuComesFromPlatform);
    }

    return catalog.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => _Centred(text: '$error'),
      data: (menu) {
        // Off sections stay in the list (dimmed, switch off) so they can be
        // switched back on; the till's own catalogue never carries them.
        final categories = [
          ...menu.categories,
          ...?ref.watch(inactiveCategoriesProvider).valueOrNull,
        ]..sort((a, b) {
            final bySort = a.sortOrder.compareTo(b.sortOrder);
            return bySort != 0 ? bySort : a.id.compareTo(b.id);
          });
        final selected =
            _categoryId ?? (categories.isEmpty ? null : categories.first.id);
        final products = selected == null
            ? const <Product>[]
            : menu.products.where((p) => p.categoryId == selected).toList();
        final counts = {
          for (final category in categories)
            category.id: menu.products
                .where((p) => p.categoryId == category.id)
                .length,
        };
        final sectionsPage = widget.mode == MenuPaneMode.sections;
        Category? current;
        for (final category in categories) {
          if (category.id == selected) current = category;
        }

        // One switch: on puts it back on the rail, off takes it off.
        Future<void> toggleCategory(Category category) => _write(
          () => repository.archiveCategory(
            category,
            by: widget.admin,
            restore: !category.isActive,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(
              summary: strings.menuSummary(
                categories.length,
                menu.products.length,
              ),
              // Importing builds sections AND items: a Menu-page action.
              onImport: sectionsPage ? null : _import,
              onAddCategory: () => _editCategory(repository, null),
            ),
            Expanded(
              child: categories.isEmpty
                  ? _Centred(text: strings.noCategoriesYet)
                  : sectionsPage
                  // The sections alone, across the page: nothing to pick,
                  // because there is no item list beside them.
                  ? _CategoryList(
                      categories: categories,
                      counts: counts,
                      selected: null,
                      onPick: (_) {},
                      onEdit: (category) => _editCategory(repository, category),
                      onToggle: toggleCategory,
                      onDelete: (category) =>
                          _deleteCategory(repository, category),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CategoryList(
                          categories: categories,
                          counts: counts,
                          width: 260,
                          selected: selected,
                          onPick: (id) => setState(() => _categoryId = id),
                          onEdit: (category) =>
                              _editCategory(repository, category),
                          onToggle: toggleCategory,
                          onDelete: (category) =>
                              _deleteCategory(repository, category),
                        ),
                        Expanded(
                          child: _ProductList(
                            sectionName:
                                current?.displayName(strings.languageCode) ??
                                '',
                            // Add item belongs to the section being looked at.
                            onAdd: selected == null
                                ? null
                                : () => _editProduct(
                                    repository,
                                    null,
                                    selected,
                                    taxGroups,
                                    units,
                                  ),
                            products: products,
                            onEdit: (product) => _editProduct(
                              repository,
                              product,
                              product.categoryId,
                              taxGroups,
                              units,
                            ),
                            onToggle: (product) => _write(
                              () => repository.archiveProduct(
                                product,
                                by: widget.admin,
                                restore: !product.isAvailable,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Import a spreadsheet.
  ///
  /// Deliberately not routed through [_write]: the dialog owns its own preview,
  /// its own refusal and its own invalidation, because it can fail three
  /// different ways before a write is even attempted.
  Future<void> _import() async {
    final outcome = await MenuImportDialog.show(context, admin: widget.admin);
    if (outcome == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.strings.menuImportDone(outcome.productsCreated,
          outcome.productsUpdated,),
        ),
      ),
    );
  }

  Future<void> _editCategory(
    CatalogAdminRepository repository,
    Category? existing,
  ) async {
    final edited = await showDialog<Category>(
      context: context,
      builder: (context) => _CategoryDialog(
        category: existing,
        languages: ref.read(contentLanguagesNowProvider),
      ),
    );
    if (edited == null) return;
    await _write(() => repository.saveCategory(edited, by: widget.admin));
  }

  Future<void> _deleteCategory(
    CatalogAdminRepository repository,
    Category category,
  ) async {
    final strings = context.strings;
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: strings.deleteSectionTitle(
        category.displayName(strings.languageCode),
      ),
      confirmLabel: strings.deleteLabel,
      keepLabel: strings.cancel,
      requirement: ReasonRequirement.disabled,
    );
    if (confirmed == null || !mounted) return;
    await _write(() => repository.deleteCategory(category, by: widget.admin));
    // The rail may have been showing the section that is gone.
    if (mounted && _categoryId == category.id) {
      setState(() => _categoryId = null);
    }
  }

  Future<void> _editProduct(
    CatalogAdminRepository repository,
    Product? existing,
    int categoryId,
    List<TaxGroup> taxGroups,
    List<PosUnit> units,
  ) async {
    // Read before the dialog opens rather than inside it. A failure here is
    // an error, not an empty list: an editor that showed "no groups" for an
    // item that has three would delete all three the first time somebody
    // added a fourth.
    final groups = existing == null
        ? const <OptionGroupRef>[]
        : await repository.productOptionGroups(existing.id);
    final library = await repository.optionLibrary();
    if (!mounted) return;

    await showDialog<bool>(
      context: context,
      builder: (context) => _ProductDialog(
        languages: ref.read(contentLanguagesNowProvider),
        product: existing,
        categoryId: categoryId,
        taxGroups: taxGroups,
        units: units,
        groups: groups,
        library: library,
        onSave: (product, groups) => _saveProduct(repository, product, groups),
        onManageExtras: widget.onOpenExtras,
      ),
    );
  }

  /// The item, then its groups.
  ///
  /// **In that order because a new item has no id** until the first write
  /// returns one, and its groups are linked by it. Two writes rather than one
  /// transaction: they are two repository calls with their own checks, and a
  /// refusal of the second leaves an item saved with its old groups — which
  /// the dialog keeps open, holding the saved item so the retry updates it.
  ///
  /// Not through [_write]: its refusal is a snackbar behind the dialog's
  /// barrier, after the dialog — and everything typed in it — has gone.
  Future<_Saved> _saveProduct(
    CatalogAdminRepository repository,
    Product product,
    List<OptionGroupRef>? groups,
  ) async {
    final saved = await repository.saveProduct(product, by: widget.admin);
    final refusal = saved.refusal;
    if (refusal != null) return (product: null, refusal: refusal);
    final stored = saved.value!;
    if (mounted) ref.invalidate(catalogProvider);
    if (groups == null) return (product: stored, refusal: null);

    final attached = await repository.setProductOptionGroups(
      stored.id,
      groups,
      by: widget.admin,
    );
    if (mounted) ref.invalidate(catalogProvider);
    return (product: stored, refusal: attached.refusal);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.summary,
    required this.onImport,
    required this.onAddCategory,
  });

  final String summary;

  /// Null on the Sections page, which has nothing to import into.
  final VoidCallback? onImport;
  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(PosSpace.xl),
    decoration: BoxDecoration(
      border: Border(bottom: context.pos.hairline),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            summary,
            style: PosText.ui(size: 13, color: context.pos.muted),
          ),
        ),
        if (onImport != null) ...[
          PosButton(
            label: context.strings.menuImportAction,
            border: Border.fromBorderSide(context.pos.resting),
            onPressed: onImport,
          ),
          const SizedBox(width: PosSpace.md),
        ],
        PosButton(
          label: context.strings.addCategory,
          border: Border.fromBorderSide(context.pos.resting),
          onPressed: onAddCategory,
        ),
      ],
    ),
  );
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.counts,
    required this.selected,
    required this.onPick,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    this.width,
  });

  final List<Category> categories;

  /// Items per section id, shown under each name.
  final Map<int, int> counts;

  /// Null fills the page (the Sections page); a number is the Menu page's rail.
  final double? width;
  final int? selected;
  final ValueChanged<int> onPick;
  final ValueChanged<Category> onEdit;
  /// The on/off switch: turns the section on if it is off, and off if it is on.
  final ValueChanged<Category> onToggle;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    decoration: BoxDecoration(
      border: width == null ? null : Border(right: context.pos.hairline),
    ),
    child: ListView(
      children: [
        for (final category in categories)
          InkWell(
            onTap: () => onPick(category.id),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PosSpace.lg,
                vertical: PosSpace.md,
              ),
              color: category.id == selected
                  ? context.pos.accentSoft
                  : Colors.transparent,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.displayName(context.strings.languageCode),
                          style: PosText.ui(
                            size: 14,
                            weight: FontWeight.w600,
                            // Off reads as off before anyone looks at the switch.
                            color: category.isActive
                                ? context.pos.ink
                                : context.pos.muted,
                          ),
                        ),
                        const SizedBox(height: PosSpace.xs),
                        Text(
                          context.strings.sectionItemCount(
                            counts[category.id] ?? 0,
                          ),
                          style: PosText.ui(size: 12, color: context.pos.muted),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: category.isActive
                        ? context.strings.takeOffTheRail
                        : context.strings.putBackOnTheRail,
                    child: Switch(
                      key: Key('category-${category.id}-active'),
                      value: category.isActive,
                      onChanged: (_) => onToggle(category),
                    ),
                  ),
                  IconButton(
                    key: Key('category-${category.id}-edit'),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    tooltip: context.strings.edit,
                    onPressed: () => onEdit(category),
                  ),
                  // Refused by the repository while the section holds an item
                  // (live or archived): products point at this row, and so does
                  // every sale that named them. Such a section is switched off.
                  IconButton(
                    key: Key('category-${category.id}-delete'),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: context.pos.danger,
                    ),
                    tooltip: context.strings.deleteLabel,
                    onPressed: () => onDelete(category),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.sectionName,
    required this.onAdd,
    required this.products,
    required this.onEdit,
    required this.onToggle,
  });

  /// The section whose items these are, said in the header above them.
  final String sectionName;

  /// Add an item to that section. Null only when there is no section.
  final VoidCallback? onAdd;
  final List<Product> products;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onToggle;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Add item lives HERE, with the items it adds to, not in the toolbar
        // far above: the header says which section it is, and the button is
        // there whether the section holds forty items or none.
        Container(
          key: const Key('menu-section-header'),
          padding: const EdgeInsets.symmetric(
            horizontal: PosSpace.xl,
            vertical: PosSpace.md,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: context.pos.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        sectionName,
                        overflow: TextOverflow.ellipsis,
                        style: PosText.ui(
                          size: 15,
                          weight: FontWeight.w700,
                          color: context.pos.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: PosSpace.md),
                    Text(
                      strings.sectionItemCount(products.length),
                      style: PosText.ui(size: 12.5, color: context.pos.muted),
                    ),
                  ],
                ),
              ),
              KeyedSubtree(
                key: const Key('menu-add-item'),
                child: PosButton(
                  label: strings.addItem,
                  background: context.pos.ink,
                  foreground: context.pos.onInk,
                  onPressed: onAdd,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? _Centred(text: strings.nothingInCategoryYet)
              : _items(context, strings),
        ),
      ],
    );
  }

  Widget _items(BuildContext context, AppStrings strings) {
    return ListView(
      children: [
        for (final product in products)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PosSpace.xl,
              vertical: PosSpace.md,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: context.pos.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    product.displayName(strings.languageCode),
                    style: PosText.ui(
                      size: 14,
                      weight: FontWeight.w600,
                      // An unavailable item stays legible but reads as off.
                      color: product.isAvailable
                          ? context.pos.ink
                          : context.pos.muted,
                    ),
                  ),
                ),
                if (product.discountedPrice != null) ...[
                  Text(
                    product.price.format(withCurrency: true),
                    style: PosText.mono(
                      size: 12.5,
                      color: context.pos.muted,
                    ).copyWith(decoration: TextDecoration.lineThrough),
                  ),
                  const SizedBox(width: PosSpace.sm),
                ],
                Text(
                  product.effectivePrice.format(withCurrency: true),
                  style: PosText.mono(size: 13.5, color: context.pos.ink),
                ),
                const SizedBox(width: PosSpace.lg),
                PosButton(
                  label: product.isAvailable
                      ? strings.offSale
                      : strings.backOnSale,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: () => onToggle(product),
                ),
                const SizedBox(width: PosSpace.sm),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: strings.edit,
                  onPressed: () => onEdit(product),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    this.category,
    this.languages = ContentLanguages.both,
  });

  final Category? category;

  /// The languages the menu is written in (XORD-005): which name fields to ask
  /// for. The other one keeps whatever it holds.
  final ContentLanguages languages;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?.nameEn ?? '');
  late final _nameAr = TextEditingController(
    text: initialArabicName(
      languages: widget.languages,
      nameAr: widget.category?.nameAr,
      nameEn: widget.category?.nameEn,
    ),
  );

  @override
  void dispose() {
    _name.dispose();
    _nameAr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languages = widget.languages;
    final cs = languages.nameStrings(context.strings);
    return MenuDialog(
      title: widget.category == null
          ? context.strings.newCategory
          : context.strings.renameCategory,
      onSave: () {
        final names = resolveNames(
          languages: languages,
          typedEn: _name.text,
          typedAr: _nameAr.text,
          previousEn: widget.category?.nameEn,
          previousAr: widget.category?.nameAr,
        );
        Navigator.of(context).pop(
          (widget.category ?? const Category(id: 0, nameEn: '')).copyWith(
            nameEn: names.nameEn,
            nameAr: names.nameAr,
          ),
        );
      },
      children: [
        if (languages.showsEnglish) ...[
          NameDirection(
            languages: languages,
            child: MenuInput(controller: _name, label: cs.fieldName),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        if (languages.showsArabic)
          NameDirection(
            languages: languages,
            child: MenuInput(
              controller: _nameAr,
              // Required when it is the only language; optional beside English.
              label: languages == ContentLanguages.arabic
                  ? cs.fieldName
                  : context.strings.fieldNameArabic,
              optional: languages == ContentLanguages.both,
              arabic: true,
            ),
          ),
      ],
    );
  }
}

/// What saving the item came to: the item as stored — kept by the dialog even
/// when its groups were then refused, so the retry updates it rather than
/// making a second one — and why it stopped, if it did.
typedef _Saved = ({Product? product, AdminRefusal? refusal});

/// One entry in the item's list of groups, as the editor holds it.
///
/// Sealed for the reason `OptionGroupRef` is: the cards and the save both
/// switch over it, and a third kind has to fail to compile in both.
sealed class _Entry {}

/// A library group on this item: shown, never edited here.
final class _SharedEntry extends _Entry {
  _SharedEntry(this.groupId, this.snapshot);

  final int groupId;

  /// The library's copy, for the card and for mirroring a shared size's
  /// price. Null only when the group left the library between the two reads;
  /// the card then names its id and the save is refused for it.
  final OptionGroupDraft? snapshot;

  bool get isVariant => snapshot?.isVariant ?? false;
}

/// A group typed on this item alone.
final class _InlineEntry extends _Entry {
  _InlineEntry(this.group);

  final EditableGroup group;
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    this.languages = ContentLanguages.both,
    required this.categoryId,
    required this.taxGroups,
    required this.onSave,
    this.product,
    this.units = const [],
    this.groups = const [],
    this.library = const [],
    this.onManageExtras,
  });

  final Product? product;
  final int categoryId;

  /// The languages the menu is written in (XORD-005).
  final ContentLanguages languages;

  /// The units in use, for counting it in when it is tracked.
  final List<PosUnit> units;

  /// The business's named rates, for the picker. Empty on a business that
  /// has configured none, in which case the picker is absent rather than
  /// offering a single choice that means nothing.
  final List<TaxGroup> taxGroups;

  /// The groups the item carries itself, in its order. Empty for a new item.
  final List<OptionGroupRef> groups;

  /// The Extras library, for "Add from library" and for the shared cards.
  final List<LibraryGroup> library;

  final Future<_Saved> Function(Product product, List<OptionGroupRef>? groups)
  onSave;

  /// Off to the Extras pane. Null hides the link.
  final VoidCallback? onManageExtras;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final _name = TextEditingController(text: widget.product?.nameEn ?? '');
  late final _nameAr = TextEditingController(
    text: initialArabicName(
      languages: widget.languages,
      nameAr: widget.product?.nameAr,
      nameEn: widget.product?.nameEn,
    ),
  );
  late final _price = TextEditingController(
    text: widget.product?.price.format(),
  );
  late final _offer = TextEditingController(
    text: widget.product?.discountedPrice?.format(),
  );
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');

  /// Null means *follow the category, or the fallback rate* — which is what the
  /// catalogue query means by `COALESCE(p.tax_group_id, c.tax_group_id)`, and
  /// what almost every item on a menu wants.
  late int? _taxGroupId = widget.product?.taxGroupId;

  late bool _stocked = widget.product?.isStocked ?? false;
  late QuantityUnit _stockUnit =
      widget.product?.stockUnit ?? QuantityUnit.each;

  late final List<_Entry> _entries = [
    for (final ref in widget.groups)
      switch (ref) {
        SharedGroupRef(:final groupId) => _SharedEntry(
          groupId,
          _libraryGroup(groupId),
        ),
        InlineGroupRef(:final group) => _InlineEntry(
          EditableGroup.from(group, languages: widget.languages),
        ),
      },
  ];

  /// Whether anything about the groups changed. Untouched, they are not
  /// written: `setProductOptionGroups` puts a row on the ledger every time it
  /// runs, and a manager correcting a price should not appear to have
  /// rearranged the item's extras.
  bool _groupsTouched = false;

  /// The item as the first successful write returned it. See [_Saved].
  Product? _saved;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Immediately, as the cloud's watcher is: an item whose stored price has
    // drifted from its default size — a shared size repriced in the library
    // since — opens quoting what it will actually charge.
    _mirror();
  }

  @override
  void dispose() {
    _name.dispose();
    _nameAr.dispose();
    _price.dispose();
    _offer.dispose();
    _sku.dispose();
    for (final entry in _entries) {
      if (entry is _InlineEntry) entry.group.dispose();
    }
    super.dispose();
  }

  OptionGroupDraft? _libraryGroup(int id) {
    for (final entry in widget.library) {
      if (entry.group.id == id) return entry.group;
    }
    return null;
  }

  static bool _isSizes(_Entry entry) => switch (entry) {
    _SharedEntry() => entry.isVariant,
    _InlineEntry(:final group) => group.isVariant,
  };

  /// The group that prices the item. The first, as on the platform — and the
  /// only one, since a second is refused.
  _Entry? get _sizes => _entries.where(_isSizes).firstOrNull;

  /// Put the default size's price into the item's two price fields.
  ///
  /// **Why the item's price is written at all, when the size decides it.** The
  /// till's tile, the reports and the platform's own menu card all quote the
  /// item's row. The cloud keeps that row equal to the default size on every
  /// save; nothing in this repository re-derives it, so this form is where it
  /// happens. The default is the first *available* size, the one the till
  /// opens the sheet on.
  void _mirror() {
    final sizes = _sizes;
    switch (sizes) {
      case null:
        // No sizes: the item's own price stands, and stays where it was left.
        return;
      case _SharedEntry(:final snapshot):
        final size = snapshot?.options.where((o) => o.isAvailable).firstOrNull;
        if (size == null) return;
        _price.text = size.price.format();
        _offer.text = size.salePrice?.format() ?? '';
      case _InlineEntry(:final group):
        final size = group.defaultSize;
        if (size == null) return;
        // A blank price is saved as zero, so it is quoted as zero.
        _price.text = _typed(size.price.text, blankIsZero: true);
        _offer.text = _typed(size.sale.text, blankIsZero: false);
    }
  }

  /// A typed amount as the price field should show it: formatted when it is
  /// one, and left exactly as typed when it is not, so the refusal on save
  /// quotes what the owner can see.
  static String _typed(String text, {required bool blankIsZero}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return blankIsZero ? Money.zero.format() : '';
    return Money.tryParse(trimmed)?.format() ?? trimmed;
  }

  void _changed() => setState(() {
    _groupsTouched = true;
    _mirror();
  });

  /// Switch a typed group to sizes, or back.
  ///
  /// Turning sizes on hands the pricing to its options, so the price already
  /// typed above is carried into the first size — otherwise it would vanish
  /// the moment the field turned read-only. Only when that size has no price
  /// of its own, so an owner switching back and forth loses nothing either
  /// way.
  void _toggleVariant(EditableGroup group, bool on) {
    group.isVariant = on;
    if (on) {
      if (group.options.isEmpty) group.options.add(EditableOption.blank());
      final first = group.options.first;
      if (first.price.text.trim().isEmpty) {
        first.price.text = _price.text;
        first.sale.text = _offer.text;
      }
    }
    _changed();
  }

  void _remove(_Entry entry) {
    _entries.remove(entry);
    _changed();
    // After the frame: the card's fields still hold the controllers until the
    // rebuild that removes them.
    if (entry is _InlineEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) => entry.group.dispose());
    }
  }

  Future<void> _save() async {
    final strings = context.strings;
    // Through `Money.tryParse`, which reads a major-unit string WITHOUT going
    // via a double — 19.99 is 1999 minor units, never 1998.9999999999998.
    final price = Money.tryParse(_price.text);
    if (price == null) {
      setState(() => _error = strings.priceIsNotANumber);
      return;
    }

    final offerText = _offer.text.trim();
    final offer = offerText.isEmpty ? null : Money.tryParse(offerText);
    if (offerText.isNotEmpty && offer == null) {
      setState(() => _error = strings.offerPriceIsNotANumber);
      return;
    }

    List<OptionGroupRef>? groups;
    if (_groupsTouched) {
      groups = [];
      for (final entry in _entries) {
        switch (entry) {
          case _SharedEntry(:final groupId):
            groups.add(OptionGroupRef.shared(groupId));
          case _InlineEntry(:final group):
            final (:draft, :error) = group.toDraft(
              strings,
              languages: widget.languages,
            );
            if (draft == null) {
              setState(() => _error = error);
              return;
            }
            groups.add(OptionGroupRef.inline(draft));
        }
      }
    }

    final base =
        _saved ??
        widget.product ??
        Product(id: 0, categoryId: widget.categoryId, nameEn: '', price: price);
    final names = resolveNames(
      languages: widget.languages,
      typedEn: _name.text,
      typedAr: _nameAr.text,
      previousEn: base.nameEn,
      previousAr: base.nameAr,
    );
    final product = base.copyWith(
      nameEn: names.nameEn,
      nameAr: names.nameAr,
      price: price,
      discountedPrice: offer,
      // A cleared box means "no offer", which `copyWith` cannot infer from a
      // null it also uses for "unchanged".
      clearDiscount: offer == null,
      sku: _sku.text,
      taxGroupId: _taxGroupId,
      // Same problem, same shape: "back to the default rate" is a null the
      // caller means, not a null it omitted.
      clearTaxGroup: _taxGroupId == null,
      isStocked: _stocked,
      stockUnit: _stockUnit,
    );

    setState(() {
      _saving = true;
      _error = null;
    });
    final _Saved result;
    try {
      result = await widget.onSave(product, groups);
    } on PosDbException {
      // A database failure the repository had no refusal for. Without this the
      // await never returned: the editor stayed on "Saving…" with Save and
      // Cancel both disabled, and only Esc got out, losing everything typed
      // (report 2026-10-24, F-2). Said in a sentence; the owner keeps the form.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = strings.refusalSaveFailed;
      });
      return;
    }
    if (!mounted) return;
    _saved = result.product ?? _saved;
    final refusal = result.refusal;
    if (refusal != null) {
      setState(() {
        _saving = false;
        _error = AdminText.refusal(strings, refusal);
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final pricedBySizes = _sizes != null;
    return MenuDialog(
      title: widget.product == null
          ? context.strings.newItem
          : context.strings.editItem,
      error: _error,
      saving: _saving,
      maxWidth: 720,
      onSave: _save,
      children: [
        if (widget.languages.showsEnglish) ...[
          NameDirection(
            languages: widget.languages,
            child: MenuInput(
              controller: _name,
              label: widget.languages.nameStrings(context.strings).fieldName,
            ),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        if (widget.languages.showsArabic) ...[
          NameDirection(
            languages: widget.languages,
            child: MenuInput(
              controller: _nameAr,
              label: widget.languages == ContentLanguages.arabic
                  ? widget.languages.nameStrings(context.strings).fieldName
                  : context.strings.fieldNameArabic,
              optional: widget.languages == ContentLanguages.both,
              arabic: true,
            ),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        // Once the item has sizes these two are no longer the owner's to set:
        // they mirror the default size, which is what the tile quotes and what
        // an untouched add charges. See [_mirror].
        MenuInput(
          fieldKey: const Key('product-price'),
          controller: _price,
          label: context.strings.fieldPrice,
          mono: true,
          readOnly: pricedBySizes,
        ),
        const SizedBox(height: PosSpace.md),
        MenuInput(
          fieldKey: const Key('product-offer'),
          controller: _offer,
          label: context.strings.fieldOfferPrice,
          mono: true,
          optional: true,
          readOnly: pricedBySizes,
        ),
        if (pricedBySizes) ...[
          const SizedBox(height: PosSpace.xs),
          Text(
            context.strings.itemPricedBySize,
            key: const Key('product-priced-by-sizes'),
            style: PosText.ui(
              size: 11.5,
              color: context.pos.muted,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: PosSpace.md),
        MenuInput(
          controller: _sku,
          label: context.strings.fieldSku,
          mono: true,
          optional: true,
        ),

        // Counted in stock — the bottled water a business also sells. Its
        // purchases and sales then move a number somebody can check.
        const SizedBox(height: PosSpace.md),
        SwitchListTile(
          key: const Key('product-track-stock'),
          value: _stocked,
          onChanged: (v) => setState(() => _stocked = v),
          contentPadding: EdgeInsets.zero,
          title: Text(
            context.strings.fieldTrackStock,
            style: PosText.ui(size: 13.5, color: context.pos.body),
          ),
          subtitle: Text(
            context.strings.fieldTrackStockHint,
            style: PosText.ui(size: 11.5, color: context.pos.muted),
          ),
        ),
        if (_stocked && widget.units.isNotEmpty)
          Wrap(
            spacing: PosSpace.sm,
            runSpacing: PosSpace.sm,
            children: [
              for (final unit in widget.units)
                PosButton(
                  key: Key('product-unit-${unit.code}'),
                  label: unit.displayName(context.strings.languageCode),
                  background: unit.unit == _stockUnit
                      ? context.pos.ink
                      : Colors.transparent,
                  foreground: unit.unit == _stockUnit
                      ? context.pos.onInk
                      : null,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: () => setState(() => _stockUnit = unit.unit),
                ),
            ],
          ),

        // **The picker that made the named rates usable.** `tax_group_id` has
        // been on this table since Wave M and read by the catalogue query ever
        // since; nothing wrote it, so a business could define a zero-rated
        // group and had no way to put a bottle of water on it.
        //
        // Absent where no groups are configured: a picker whose only option is
        // "the default" is a question with one answer.
        if (widget.taxGroups.isNotEmpty) ...[
          const SizedBox(height: PosSpace.md),
          MicroLabel(context.strings.fieldTaxGroup),
          const SizedBox(height: PosSpace.xs),
          Text(
            context.strings.fieldTaxGroupHint,
            style: PosText.ui(
              size: 11.5,
              color: context.pos.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: PosSpace.sm),
          Wrap(
            spacing: PosSpace.sm,
            runSpacing: PosSpace.sm,
            children: [
              PosButton(
                key: const Key('product-tax-default'),
                label: context.strings.fieldTaxGroupDefault,
                background: _taxGroupId == null
                    ? context.pos.ink
                    : Colors.transparent,
                foreground: _taxGroupId == null ? Colors.white : null,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: () => setState(() => _taxGroupId = null),
              ),
              for (final group in widget.taxGroups)
                PosButton(
                  key: Key('product-tax-${group.id}'),
                  label:
                      '${group.displayName(context.strings.languageCode)} · '
                      '${AdminText.rateBp(group.rateBp)}',
                  background: _taxGroupId == group.id
                      ? context.pos.ink
                      : Colors.transparent,
                  foreground: _taxGroupId == group.id ? Colors.white : null,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: () => setState(() => _taxGroupId = group.id),
                ),
            ],
          ),
        ],

        ..._optionGroups(context),
      ],
    );
  }

  /// "Options & add-ons" — the cloud item form's second card.
  ///
  /// No reordering, as on the cloud: a group goes to the end of the list when
  /// it is added, and that order is the one the till shows. A size group's
  /// options are the exception that matters — their order picks the default —
  /// and the "Default" pill is how the editor says so.
  List<Widget> _optionGroups(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    final sizes = _sizes;

    return [
      const SizedBox(height: PosSpace.lg),
      Container(height: 1, color: pos.line),
      const SizedBox(height: PosSpace.lg),
      Row(
        children: [
          Expanded(child: MicroLabel(s.itemOptions)),
          _libraryPicker(s, pos),
          const SizedBox(width: PosSpace.sm),
          PosButton(
            key: const Key('product-add-group'),
            label: '+ ${s.itemAddGroup}',
            height: 36,
            border: Border.fromBorderSide(pos.resting),
            onPressed: () {
              _entries.add(_InlineEntry(EditableGroup.blank()));
              _changed();
            },
          ),
        ],
      ),
      const SizedBox(height: PosSpace.sm),
      if (_entries.isEmpty)
        Text(s.itemNoOptions, style: PosText.ui(size: 12, color: pos.muted)),
      for (final (i, entry) in _entries.indexed)
        Padding(
          key: ObjectKey(entry),
          padding: const EdgeInsets.only(bottom: PosSpace.md),
          child: switch (entry) {
            _SharedEntry() => _sharedCard(i, entry, s, pos),
            _InlineEntry() => _inlineCard(
              i,
              entry,
              s,
              pos,
              markDefault: identical(entry, sizes),
            ),
          },
        ),
      if (widget.onManageExtras case final open?)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GestureDetector(
            key: const Key('product-manage-extras'),
            // Leaving throws away what is typed here, as the cloud's link
            // does; the library is a different page on both.
            onTap: () {
              Navigator.of(context).pop();
              open();
            },
            child: Text(
              '${s.itemManageLibrary} →',
              style: PosText.ui(size: 12, color: pos.muted),
            ),
          ),
        ),
    ];
  }

  /// Library groups that can be put on an item by hand: those that reach
  /// items one link at a time, and are not on this one already. A group that
  /// applies by category or everywhere reaches the item by itself.
  Widget _libraryPicker(AppStrings s, PosPalette pos) {
    final attached = {
      for (final entry in _entries)
        if (entry is _SharedEntry) entry.groupId,
    };
    final linkable = [
      for (final entry in widget.library)
        if (entry.group.scope == OptionGroupScope.items) entry,
    ];
    final hasSizes = _sizes != null;

    return PopupMenuButton<LibraryGroup>(
      key: const Key('product-add-from-library'),
      tooltip: '',
      color: pos.surface,
      shape: RoundedRectangleBorder(side: pos.resting),
      onSelected: (entry) {
        _entries.add(_SharedEntry(entry.group.id, entry.group));
        _changed();
      },
      itemBuilder: (_) => [
        if (linkable.isEmpty)
          PopupMenuItem<LibraryGroup>(
            enabled: false,
            child: Text(s.itemLibraryEmpty),
          ),
        for (final entry in linkable)
          if (!attached.contains(entry.group.id))
            PopupMenuItem<LibraryGroup>(
              key: Key('library-pick-${entry.group.id}'),
              value: entry,
              // **Offered, but not pickable, once the item has sizes.** The
              // save refuses a second set; letting it be picked would only
              // move that refusal to after everything else was arranged.
              enabled: !(entry.group.isVariant && hasSizes),
              child: Text(groupName(entry.group, s.languageCode)),
            ),
      ],
      child: IgnorePointer(
        child: PosButton(
          label: '+ ${s.itemAddFromLibrary}',
          height: 36,
          border: Border.fromBorderSide(pos.resting),
          onPressed: () {},
        ),
      ),
    );
  }

  /// A library group on this item: read-only, edited in the library.
  Widget _sharedCard(
    int index,
    _SharedEntry entry,
    AppStrings s,
    PosPalette pos,
  ) {
    final snapshot = entry.snapshot;
    final lang = s.languageCode;
    final options = [
      for (final option in snapshot?.options ?? const <OptionDraft>[])
        if (lang == 'ar' && (option.nameAr?.isNotEmpty ?? false))
          option.nameAr!
        else
          option.nameEn,
    ].where((name) => name.isNotEmpty);

    return Container(
      key: Key('product-group-$index'),
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: pos.accentSoft,
        border: Border.all(color: pos.accent),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 15, color: pos.accent),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot == null
                      ? '#${entry.groupId}'
                      : groupName(snapshot, lang),
                  style: PosText.ui(
                    size: 14,
                    weight: FontWeight.w600,
                    color: pos.ink,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: s.itemFromLibrary,
                        style: TextStyle(color: pos.accent),
                      ),
                      // The cloud joins with the Arabic comma in both
                      // languages; so does this.
                      TextSpan(text: '  ${options.join('، ')}'),
                    ],
                  ),
                  style: PosText.ui(size: 12, color: pos.muted),
                ),
              ],
            ),
          ),
          if (entry.isVariant) MenuPill(s.itemVariant),
          IconButton(
            key: Key('group-$index-remove'),
            icon: Icon(Icons.close, size: 16, color: pos.danger),
            tooltip: s.deleteLabel,
            onPressed: () => _remove(entry),
          ),
        ],
      ),
    );
  }

  /// A group typed on this item: names, rules and options, all editable.
  Widget _inlineCard(
    int index,
    _InlineEntry entry,
    AppStrings s,
    PosPalette pos, {
    required bool markDefault,
  }) {
    final group = entry.group;
    final prefix = 'group-$index';
    // **One set of sizes per item.** The switch is off-limits on every other
    // group while one is sizes — the repository refuses a second set, and a
    // switch that can be flipped only to be refused at Save is a trap.
    final canBeSizes = group.isVariant || _sizes == null;

    return Container(
      key: Key('product-group-$index'),
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: pos.page,
        border: Border.all(color: pos.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (widget.languages.showsEnglish)
                Expanded(
                  child: NameDirection(
                    languages: widget.languages,
                    child: _groupName(
                      Key('$prefix-name'),
                      group.nameEn,
                      widget.languages.nameStrings(s).itemGroupNameEn,
                    ),
                  ),
                ),
              if (widget.languages == ContentLanguages.both)
                const SizedBox(width: PosSpace.sm),
              if (widget.languages.showsArabic)
                Expanded(
                  child: NameDirection(
                    languages: widget.languages,
                    child: _groupName(
                      Key('$prefix-name-ar'),
                      group.nameAr,
                      widget.languages.nameStrings(s).itemGroupNameAr,
                      arabic: true,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: PosSpace.sm),
          GroupRulesRow(
            group: group,
            keyPrefix: prefix,
            onVariant: canBeSizes ? (on) => _toggleVariant(group, on) : null,
            onChanged: _changed,
            trailing: IconButton(
              key: Key('$prefix-remove'),
              icon: Icon(Icons.delete_outline, size: 16, color: pos.danger),
              tooltip: s.deleteLabel,
              onPressed: () => _remove(entry),
            ),
          ),
          const SizedBox(height: PosSpace.sm),
          OptionRows(
            group: group,
            keyPrefix: prefix,
            onChanged: _changed,
            markDefault: markDefault,
            languages: widget.languages,
          ),
        ],
      ),
    );
  }

  Widget _groupName(
    Key key,
    TextEditingController controller,
    String hint, {
    bool arabic = false,
  }) => TextField(
    key: key,
    controller: controller,
    onChanged: (_) => _changed(),
    textDirection: arabic ? TextDirection.rtl : null,
    style: PosText.ui(size: 13.5, color: context.pos.ink),
    decoration: InputDecoration(hintText: hint, isDense: true),
  );
}

class _Centred extends StatelessWidget {
  const _Centred({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: PosText.ui(size: 13, color: context.pos.muted),
      ),
    ),
  );
}
