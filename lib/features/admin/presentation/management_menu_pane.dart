import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/catalog.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import 'admin_messages.dart';
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
class ManagementMenuPane extends ConsumerStatefulWidget {
  const ManagementMenuPane({required this.admin, super.key});

  final PosStaff admin;

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
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(catalogAdminRepositoryProvider);
    final catalog = ref.watch(catalogProvider);
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
        final categories = menu.categories;
        final selected =
            _categoryId ?? (categories.isEmpty ? null : categories.first.id);
        final products = selected == null
            ? const <Product>[]
            : menu.products.where((p) => p.categoryId == selected).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(
              summary: strings.menuSummary(
                categories.length,
                menu.products.length,
              ),
              onImport: _import,
              onAddCategory: () => _editCategory(repository, null),
              onAddProduct: selected == null
                  ? null
                  : () => _editProduct(repository, null, selected),
            ),
            Expanded(
              child: categories.isEmpty
                  ? _Centred(text: strings.noCategoriesYet)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CategoryList(
                          categories: categories,
                          selected: selected,
                          onPick: (id) => setState(() => _categoryId = id),
                          onEdit: (category) =>
                              _editCategory(repository, category),
                          onArchive: (category) => _write(
                            () => repository.archiveCategory(
                              category,
                              by: widget.admin,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _ProductList(
                            products: products,
                            onEdit: (product) => _editProduct(
                              repository,
                              product,
                              product.categoryId,
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
      builder: (context) => _CategoryDialog(category: existing),
    );
    if (edited == null) return;
    await _write(() => repository.saveCategory(edited, by: widget.admin));
  }

  Future<void> _editProduct(
    CatalogAdminRepository repository,
    Product? existing,
    int categoryId,
  ) async {
    final edited = await showDialog<Product>(
      context: context,
      builder: (context) =>
          _ProductDialog(product: existing, categoryId: categoryId),
    );
    if (edited == null) return;
    await _write(() => repository.saveProduct(edited, by: widget.admin));
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.summary,
    required this.onImport,
    required this.onAddCategory,
    required this.onAddProduct,
  });

  final String summary;
  final VoidCallback onImport;
  final VoidCallback onAddCategory;
  final VoidCallback? onAddProduct;

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
        PosButton(
          label: context.strings.menuImportAction,
          border: Border.fromBorderSide(context.pos.resting),
          onPressed: onImport,
        ),
        const SizedBox(width: PosSpace.md),
        PosButton(
          label: context.strings.addCategory,
          border: Border.fromBorderSide(context.pos.resting),
          onPressed: onAddCategory,
        ),
        const SizedBox(width: PosSpace.md),
        PosButton(
          label: context.strings.addItem,
          background: context.pos.ink,
          foreground: Colors.white,
          onPressed: onAddProduct,
        ),
      ],
    ),
  );
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.selected,
    required this.onPick,
    required this.onEdit,
    required this.onArchive,
  });

  final List<Category> categories;
  final int? selected;
  final ValueChanged<int> onPick;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onArchive;

  @override
  Widget build(BuildContext context) => Container(
    width: 260,
    decoration: BoxDecoration(border: Border(right: context.pos.hairline)),
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
                    child: Text(
                      category.displayName(context.strings.languageCode),
                      style: PosText.ui(
                        size: 14,
                        weight: FontWeight.w600,
                        color: context.pos.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    tooltip: context.strings.rename,
                    onPressed: () => onEdit(category),
                  ),
                  IconButton(
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    // Never "delete": products point at this row, and so
                    // does every sale that ever named it.
                    tooltip: context.strings.takeOffTheRail,
                    onPressed: () => onArchive(category),
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
    required this.products,
    required this.onEdit,
    required this.onToggle,
  });

  final List<Product> products;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onToggle;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    if (products.isEmpty) {
      return _Centred(text: strings.nothingInCategoryYet);
    }

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
                    product.price.format(),
                    style: PosText.mono(
                      size: 12.5,
                      color: context.pos.muted,
                    ).copyWith(decoration: TextDecoration.lineThrough),
                  ),
                  const SizedBox(width: PosSpace.sm),
                ],
                Text(
                  product.effectivePrice.format(),
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
  const _CategoryDialog({this.category});

  final Category? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?.nameEn ?? '');
  late final _nameAr = TextEditingController(
    text: widget.category?.nameAr ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _nameAr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Dialog(
    title: widget.category == null
        ? context.strings.newCategory
        : context.strings.renameCategory,
    onSave: () => Navigator.of(context).pop(
      (widget.category ?? const Category(id: 0, nameEn: '')).copyWith(
        nameEn: _name.text,
        nameAr: _nameAr.text,
      ),
    ),
    children: [
      _Input(controller: _name, label: context.strings.fieldName),
      const SizedBox(height: PosSpace.md),
      _Input(
        controller: _nameAr,
        label: context.strings.fieldNameArabic,
        optional: true,
      ),
    ],
  );
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.categoryId, this.product});

  final Product? product;
  final int categoryId;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final _name = TextEditingController(text: widget.product?.nameEn ?? '');
  late final _nameAr = TextEditingController(
    text: widget.product?.nameAr ?? '',
  );
  late final _price = TextEditingController(
    text: widget.product?.price.format(),
  );
  late final _offer = TextEditingController(
    text: widget.product?.discountedPrice?.format(),
  );
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');

  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _nameAr.dispose();
    _price.dispose();
    _offer.dispose();
    _sku.dispose();
    super.dispose();
  }

  void _save() {
    // Through `Money.tryParse`, which reads a major-unit string WITHOUT going
    // via a double — 19.99 is 1999 minor units, never 1998.9999999999998.
    final price = Money.tryParse(_price.text);
    if (price == null) {
      setState(() => _error = context.strings.priceIsNotANumber);
      return;
    }

    final offerText = _offer.text.trim();
    final offer = offerText.isEmpty ? null : Money.tryParse(offerText);
    if (offerText.isNotEmpty && offer == null) {
      setState(() => _error = context.strings.offerPriceIsNotANumber);
      return;
    }

    final base =
        widget.product ??
        Product(id: 0, categoryId: widget.categoryId, nameEn: '', price: price);

    Navigator.of(context).pop(
      base.copyWith(
        nameEn: _name.text,
        nameAr: _nameAr.text,
        price: price,
        discountedPrice: offer,
        // A cleared box means "no offer", which `copyWith` cannot infer from a
        // null it also uses for "unchanged".
        clearDiscount: offer == null,
        sku: _sku.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _Dialog(
    title: widget.product == null
        ? context.strings.newItem
        : context.strings.editItem,
    error: _error,
    onSave: _save,
    children: [
      _Input(controller: _name, label: context.strings.fieldName),
      const SizedBox(height: PosSpace.md),
      _Input(
        controller: _nameAr,
        label: context.strings.fieldNameArabic,
        optional: true,
      ),
      const SizedBox(height: PosSpace.md),
      _Input(controller: _price, label: context.strings.fieldPrice, mono: true),
      const SizedBox(height: PosSpace.md),
      _Input(
        controller: _offer,
        label: context.strings.fieldOfferPrice,
        mono: true,
        optional: true,
      ),
      const SizedBox(height: PosSpace.md),
      _Input(
        controller: _sku,
        label: context.strings.fieldSku,
        mono: true,
        optional: true,
      ),
    ],
  );
}

class _Dialog extends StatelessWidget {
  const _Dialog({
    required this.title,
    required this.onSave,
    required this.children,
    this.error,
  });

  final String title;
  final VoidCallback onSave;
  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pos.surface,
    shape: RoundedRectangleBorder(side: context.pos.emphasis),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: PosText.panelTitle(color: context.pos.ink)),
            const SizedBox(height: PosSpace.lg),
            ...children,
            if (error != null) ...[
              const SizedBox(height: PosSpace.md),
              Text(
                error!,
                style: PosText.ui(size: 12.5, color: context.pos.danger),
              ),
            ],
            const SizedBox(height: PosSpace.xl),
            Row(
              children: [
                Expanded(
                  child: PosButton(
                    label: context.strings.cancel,
                    border: Border.fromBorderSide(context.pos.resting),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: PosSpace.md),
                Expanded(
                  child: PosButton(
                    label: context.strings.save,
                    background: context.pos.ink,
                    foreground: Colors.white,
                    onPressed: onSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    this.mono = false,
    this.optional = false,
  });

  final TextEditingController controller;
  final String label;
  final bool mono;
  final bool optional;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(optional ? context.strings.optionalField(label) : label),
      const SizedBox(height: PosSpace.sm),
      TextField(
        controller: controller,
        style: mono
            ? PosText.mono(size: 14, color: context.pos.ink)
            : PosText.ui(size: 14, color: context.pos.ink),
      ),
    ],
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
