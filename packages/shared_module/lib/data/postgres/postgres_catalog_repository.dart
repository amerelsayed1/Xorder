import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/combo.dart';
import '../../domain/repositories/repositories.dart';
import 'postgres_tenant.dart';
import '../sql/sql.dart';

/// The business's actual menu, read from the branch server.
///
/// Four queries rather than one join: a product joined to its modifier groups
/// joined to their modifiers multiplies rows by both fan-outs, and reassembling
/// that in Dart costs more than the extra round trips on a LAN. The catalogue is
/// read once at setup and refreshed in the background, so this is not a hot
/// path.
///
/// Everything is returned as one immutable [Catalog], which is what lets the
/// sale screen never see a half-applied refresh.
class PostgresCatalogRepository implements CatalogRepository {
  PostgresCatalogRepository({
    required SqlDatabase database,
    required this._config,
    this.branchId,
    DateTime Function()? clock,
  }) : _db = database,
       _now = clock ?? DateTime.now;

  /// Which shop is reading. Null before the terminal is provisioned, and on a
  /// single-branch business it changes nothing — there are no override rows.
  final int? branchId;

  final SqlDatabase _db;
  final DeploymentConfig _config;
  final DateTime Function() _now;
  late final _tenant = PosTenantResolver(_db, _config);

  /// [since] is ignored: the branch database is on the same network and the
  /// whole menu is a few hundred rows, so a delta would add a
  /// cache-invalidation bug for no measurable gain. The parameter stays because
  /// an HTTP implementation against POS-BE-012 will want it.
  @override
  Future<Catalog> load({DateTime? since}) async {
    final tenant = await _tenant.resolve();

    final categories = await _db.query(
      _config,
      'SELECT id, name_en, name_ar, slug, sort_order FROM pos_categories '
      'WHERE business_id = @business AND is_active '
      'ORDER BY sort_order, id',
      parameters: {'business': tenant.id},
    );

    final products = await _db.query(
      _config,
      // Branch overrides applied here, at the read, rather than carried into
      // the ticket. A price is a property of the menu this shop is selling
      // from, so the catalogue is the honest place to resolve it — and a
      // business with one price everywhere writes no override rows and pays
      // nothing for the join.
      //
      // Only branch-wide rows (`order_type IS NULL`). Per-channel pricing needs
      // the price to vary with the *ticket's* order type, which a catalogue
      // read cannot know; the column exists and nothing authors one yet.
      'SELECT p.id, p.category_id, p.name_en, p.name_ar, '
      '       COALESCE(o.price_minor, p.price_minor), '
      '       p.discounted_price_minor, p.sku, p.barcode, '
      '       p.is_available AND COALESCE(o.is_available, true), '
      // A product that names no tax group falls back to its category's (§37).
      // Resolved here rather than in the ticket, because the ticket holds a
      // product and not the category it came from — and a fallback the engine
      // could not see would be a rate that applied on paper and not in the
      // bill.
      '       COALESCE(p.tax_group_id, c.tax_group_id), '
      // Read so the Menu pane's editor holds them: saving a product it built
      // from this row writes both back, and a row without them would quietly
      // stop a tracked item being counted.
      '       p.is_stocked, p.stock_unit '
      'FROM pos_products p '
      'JOIN pos_categories c ON c.id = p.category_id '
      'LEFT JOIN pos_product_prices o '
      '  ON o.product_id = p.id AND o.branch_id = @branch '
      '  AND o.order_type IS NULL '
      'WHERE p.business_id = @business '
      'ORDER BY p.sort_order, p.id',
      parameters: {'business': tenant.id, 'branch': branchId},
    );

    // Scoped through the product so a group belonging to another business
    // cannot be attached by a stray join.
    final attachments = await _db.query(
      _config,
      'SELECT pmg.product_id, pmg.group_id FROM pos_product_modifier_groups pmg '
      'JOIN pos_products p ON p.id = pmg.product_id '
      'WHERE p.business_id = @business '
      'ORDER BY pmg.sort_order, pmg.group_id',
      parameters: {'business': tenant.id},
    );

    final groups = await _db.query(
      _config,
      'SELECT id, name_en, name_ar, is_required, max_select, is_variant, '
      '       min_select, free_options, display_name_en, display_name_ar '
      'FROM pos_modifier_groups WHERE business_id = @business '
      'ORDER BY sort_order, id',
      parameters: {'business': tenant.id},
    );

    // Library groups that reach items with no link: every item, or every item
    // in their categories (migration 45). They have no position on any one
    // item, so they trail its own groups in the order the library lists them —
    // by name, then id — which is the platform's order too, and so the order a
    // diner's phone shows for the same item.
    final autoGroups = await _db.query(
      _config,
      'SELECT g.id, g.apply_scope, '
      '       coalesce(array_agg(c.category_id) '
      "                FILTER (WHERE c.category_id IS NOT NULL), '{}') "
      'FROM pos_modifier_groups g '
      'LEFT JOIN pos_modifier_group_categories c ON c.group_id = g.id '
      'WHERE g.business_id = @business AND g.is_global '
      "  AND g.apply_scope <> 'items' "
      'GROUP BY g.id '
      'ORDER BY g.name_en, g.name_ar, g.id',
      parameters: {'business': tenant.id},
    );

    final modifiers = await _db.query(
      _config,
      'SELECT m.id, m.group_id, m.name_en, m.name_ar, m.price_delta_minor, m.is_available, '
      '       g.is_variant, m.discounted_price_minor, m.is_default '
      'FROM pos_modifiers m '
      'JOIN pos_modifier_groups g ON g.id = m.group_id '
      'WHERE g.business_id = @business '
      'ORDER BY m.sort_order, m.id',
      parameters: {'business': tenant.id},
    );

    final byGroup = <int, List<Modifier>>{};
    // Each size group's default — its first AVAILABLE option — as the regular
    // price and the sale price. Out of stock is skipped because the sheet
    // skips it: the default is what an untouched "add" charges, and nothing
    // charges for a size that cannot be chosen.
    final defaultSize = <int, ({int regular, int? sale})>{};
    for (final row in modifiers) {
      final groupId = row[1] as int;
      final isVariant = row[6] as bool;
      final regular = row[4] as int;
      final sale = row[7] as int?;
      final isAvailable = row[5] as bool;

      byGroup
          .putIfAbsent(groupId, () => [])
          .add(
            Modifier(
              id: row[0] as int,
              groupId: groupId,
              nameEn: row[2] as String,
              nameAr: row[3] as String?,
              // A size charges its sale price when it has one. An extra never
              // does: only a size can be on sale, and an extra's stray value
              // is ignored here rather than trusted.
              priceDelta: _money(isVariant ? (sale ?? regular) : regular),
              isAvailable: isAvailable,
              isVariant: isVariant,
              // Read at last: the column has existed since Wave M and the sheet
              // honours it, but nothing ever selected it. Sizes ignore it — see
              // `TicketEngine.defaultSelection`.
              isDefault: row[8] as bool,
            ),
          );
      if (isVariant && isAvailable) {
        defaultSize.putIfAbsent(groupId, () => (regular: regular, sale: sale));
      }
    }

    final variantGroups = {
      for (final row in groups)
        if (row[5] as bool) row[0] as int,
    };

    final groupIdsByProduct = <int, List<int>>{};
    for (final row in attachments) {
      groupIdsByProduct.putIfAbsent(row[0] as int, () => []).add(row[1] as int);
    }

    final autos = [
      for (final row in autoGroups)
        (
          id: row[0]! as int,
          everywhere: row[1] == 'all',
          categories: (row[2]! as List).whereType<int>().toSet(),
        ),
    ];

    /// An item's groups, in the order its sheet shows them: its own — typed
    /// on it or linked from the library — by position, then the library groups
    /// that reach it by themselves. `orderedOptionGroups()` on the platform.
    ///
    /// Once each. A group reaching an item by two paths is one group on the
    /// sheet, at its own position; migration 45 refuses the second path, and
    /// this holds for the rows written before it.
    List<int> resolvedGroups(int productId, int categoryId) {
      final ids = <int>[];
      for (final id in groupIdsByProduct[productId] ?? const <int>[]) {
        if (!ids.contains(id)) ids.add(id);
      }
      for (final auto in autos) {
        if (!auto.everywhere && !auto.categories.contains(categoryId)) continue;
        if (!ids.contains(auto.id)) ids.add(auto.id);
      }
      return ids;
    }

    // Combos, and the products they are built from. Three small reads rather
    // than one join: a combo has groups which have options, and unpicking that
    // shape from a flattened result is more code than asking three times.
    final comboRows = await _db.query(
      _config,
      'SELECT id, category_id, name_en, name_ar, price_minor, tax_group_id, '
      '       sku, is_available '
      'FROM pos_combos WHERE business_id = @business '
      'ORDER BY sort_order, id',
      parameters: {'business': tenant.id},
    );

    final comboGroupRows = comboRows.isEmpty
        ? const []
        : await _db.query(
            _config,
            'SELECT g.id, g.combo_id, g.name_en, g.name_ar, g.min_select, '
            '       g.max_select '
            'FROM pos_combo_groups g '
            'JOIN pos_combos c ON c.id = g.combo_id '
            'WHERE c.business_id = @business '
            'ORDER BY g.sort_order, g.id',
            parameters: {'business': tenant.id},
          );

    final comboOptionRows = comboRows.isEmpty
        ? const []
        : await _db.query(
            _config,
            'SELECT o.id, o.combo_group_id, o.product_id, o.price_delta_minor '
            'FROM pos_combo_options o '
            'JOIN pos_combo_groups g ON g.id = o.combo_group_id '
            'JOIN pos_combos c ON c.id = g.combo_id '
            'WHERE c.business_id = @business '
            'ORDER BY o.sort_order, o.id',
            parameters: {'business': tenant.id},
          );

    // Indexed once. A combo option names a product id, and looking each one
    // up by walking the list would be quadratic on a large menu.
    final productsById = <int, Product>{};
    for (final row in products) {
      final id = row[0]! as int;
      final categoryId = row[1]! as int;
      final groupIds = resolvedGroups(id, categoryId);

      // **An item with sizes is priced by its default size, derived here on
      // every read** — the first available option of its first size group, as
      // the regular price and the sale price together. Never the pair from two
      // sources: a size's price beside the item's own discount would draw a
      // strike-through that no selection ever charges.
      //
      // Derived rather than stored, which is the platform's approach inverted
      // on purpose. It copies the default size into the item's price columns
      // on each write, and every writer that forgets leaves them wrong:
      // deleting a shared size group, or importing items, leaves an item
      // advertising a size it no longer has. Here nothing is copied, so there
      // is nothing to go stale — delete the size group and the item is back on
      // its own price at the next read.
      //
      // It wins over a branch override as well. The size is what the ticket
      // charges (`priceWithOptions`), so a tile quoting the override would
      // quote a figure the till then does not take.
      int? sizeGroup;
      for (final groupId in groupIds) {
        if (variantGroups.contains(groupId)) {
          sizeGroup = groupId;
          break;
        }
      }
      // A first size group with nothing available prices nothing, and the
      // item falls back to its own price — the platform does the same, rather
      // than reaching past it to a second size group it would not show first.
      var size = sizeGroup == null ? null : defaultSize[sizeGroup];

      final ownPrice = row[4]! as int;
      final ownDiscount = row[5] as int?;
      // …unless the item's own pair already charges what its default size
      // does. That is every item the platform seeds: it sends the size's
      // regular and sale price on the item, but only the charged figure on the
      // option, so deriving from the option would turn "90 struck to 80" into a
      // bare 80. The pair is kept when it agrees, and replaced when it has gone
      // stale — which is the case the derivation exists for.
      if (size != null && (ownDiscount ?? ownPrice) == (size.sale ?? size.regular)) {
        size = null;
      }

      productsById[id] = Product(
        id: id,
        categoryId: categoryId,
        nameEn: row[2]! as String,
        nameAr: row[3] as String?,
        price: _money(size?.regular ?? ownPrice),
        discountedPrice: size != null
            ? (size.sale == null ? null : _money(size.sale!))
            : (ownDiscount == null ? null : _money(ownDiscount)),
        sku: row[6] as String?,
        barcode: row[7] as String?,
        isAvailable: row[8]! as bool,
        taxGroupId: row[9] as int?,
        modifierGroupIds: groupIds,
        isStocked: row[10]! as bool,
        stockUnit: row[11] == null
            ? null
            : QuantityUnit.fromWire(row[11] as String),
      );
    }

    return Catalog(
      syncedAt: _now(),
      categories: [
        for (final row in categories)
          Category(
            id: row[0] as int,
            nameEn: row[1] as String,
            nameAr: row[2] as String?,
            slug: row[3] as String?,
            sortOrder: row[4] as int,
          ),
      ],
      // Built once above and reused, rather than constructed twice.
      products: productsById.values.toList(growable: false),
      modifierGroups: [
        for (final row in groups)
          ModifierGroup(
            id: row[0] as int,
            nameEn: row[1] as String,
            nameAr: row[2] as String?,
            isRequired: row[3] as bool,
            maxSelect: row[4] as int,
            isVariant: row[5] as bool,
            modifiers: byGroup[row[0] as int] ?? const [],
            minSelect: row[6] as int? ?? 0,
            freeOptions: row[7] as int? ?? 0,
            displayNameEn: row[8] as String?,
            displayNameAr: row[9] as String?,
          ),
      ],
      combos: _combos(
        comboRows,
        comboGroupRows,
        comboOptionRows,
        productsById,
      ),
    );
  }

  /// Assemble combos from their three reads.
  ///
  /// An option whose product is gone is **dropped**, and a group left with no
  /// options is dropped with it: the foreign key is `RESTRICT` so this should
  /// not happen, and a combo offering a choice nobody can pick would be worse
  /// than one that quietly offers fewer.
  List<Combo> _combos(
    List<dynamic> comboRows,
    List<dynamic> groupRows,
    List<dynamic> optionRows,
    Map<int, Product> productsById,
  ) {
    final optionsByGroup = <int, List<ComboOption>>{};
    for (final raw in optionRows) {
      final row = (raw as dynamic).toList() as List<Object?>;
      final product = productsById[row[2] as int];
      if (product == null) continue;
      optionsByGroup.putIfAbsent(row[1] as int, () => []).add(
        ComboOption(
          id: row[0] as int,
          product: product,
          priceDelta: _money(row[3] as int),
        ),
      );
    }

    final groupsByCombo = <int, List<ComboGroup>>{};
    for (final raw in groupRows) {
      final row = (raw as dynamic).toList() as List<Object?>;
      final options = optionsByGroup[row[0] as int] ?? const <ComboOption>[];
      if (options.isEmpty) continue;
      groupsByCombo.putIfAbsent(row[1] as int, () => []).add(
        ComboGroup(
          id: row[0] as int,
          nameEn: row[2] as String,
          nameAr: row[3] as String?,
          minSelect: row[4] as int,
          maxSelect: row[5] as int,
          options: options,
        ),
      );
    }

    return [
      for (final raw in comboRows)
        if ((raw as dynamic).toList() case final List<Object?> row)
          if (groupsByCombo[row[0] as int] case final groups?)
            Combo(
              id: row[0] as int,
              categoryId: row[1] as int,
              nameEn: row[2] as String,
              nameAr: row[3] as String?,
              price: _money(row[4] as int),
              taxGroupId: row[5] as int?,
              sku: row[6] as String?,
              isAvailable: row[7] as bool,
              groups: groups,
            ),
    ];
  }

  /// Currency and exponent come from the terminal's own configuration, as they
  /// do everywhere else in the till. When the server owns tax and currency
  /// (POS-BE-013) this reads them from the business row instead.
  Money _money(int minor) => Money(minor);
}
