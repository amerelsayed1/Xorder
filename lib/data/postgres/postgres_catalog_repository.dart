import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/catalog.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';
import 'postgres_tenant.dart';

/// The restaurant's actual menu, read from the branch server.
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
    required PosDatabase database,
    required this._config,
    DateTime Function()? clock,
  }) : _db = database,
       _now = clock ?? DateTime.now;

  final PosDatabase _db;
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
      'WHERE restaurant_id = @restaurant AND is_active '
      'ORDER BY sort_order, id',
      parameters: {'restaurant': tenant.id},
    );

    final products = await _db.query(
      _config,
      'SELECT id, category_id, name_en, name_ar, price_minor, '
      '       discounted_price_minor, sku, barcode, is_available '
      'FROM pos_products WHERE restaurant_id = @restaurant '
      'ORDER BY sort_order, id',
      parameters: {'restaurant': tenant.id},
    );

    // Scoped through the product so a group belonging to another restaurant
    // cannot be attached by a stray join.
    final attachments = await _db.query(
      _config,
      'SELECT pmg.product_id, pmg.group_id FROM pos_product_modifier_groups pmg '
      'JOIN pos_products p ON p.id = pmg.product_id '
      'WHERE p.restaurant_id = @restaurant '
      'ORDER BY pmg.sort_order, pmg.group_id',
      parameters: {'restaurant': tenant.id},
    );

    final groups = await _db.query(
      _config,
      'SELECT id, name_en, name_ar, is_required, max_select, is_variant '
      'FROM pos_modifier_groups WHERE restaurant_id = @restaurant '
      'ORDER BY sort_order, id',
      parameters: {'restaurant': tenant.id},
    );

    final modifiers = await _db.query(
      _config,
      'SELECT m.id, m.group_id, m.name_en, m.name_ar, m.price_delta_minor, m.is_available '
      'FROM pos_modifiers m '
      'JOIN pos_modifier_groups g ON g.id = m.group_id '
      'WHERE g.restaurant_id = @restaurant '
      'ORDER BY m.sort_order, m.id',
      parameters: {'restaurant': tenant.id},
    );

    final byGroup = <int, List<Modifier>>{};
    for (final row in modifiers) {
      final groupId = row[1] as int;
      byGroup
          .putIfAbsent(groupId, () => [])
          .add(
            Modifier(
              id: row[0] as int,
              groupId: groupId,
              nameEn: row[2] as String,
              nameAr: row[3] as String?,
              priceDelta: _money(row[4] as int),
              isAvailable: row[5] as bool,
            ),
          );
    }

    final groupIdsByProduct = <int, List<int>>{};
    for (final row in attachments) {
      groupIdsByProduct.putIfAbsent(row[0] as int, () => []).add(row[1] as int);
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
      products: [
        for (final row in products)
          Product(
            id: row[0] as int,
            categoryId: row[1] as int,
            nameEn: row[2] as String,
            nameAr: row[3] as String?,
            price: _money(row[4] as int),
            discountedPrice: row[5] == null ? null : _money(row[5] as int),
            sku: row[6] as String?,
            barcode: row[7] as String?,
            isAvailable: row[8] as bool,
            modifierGroupIds: groupIdsByProduct[row[0] as int] ?? const [],
          ),
      ],
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
          ),
      ],
    );
  }

  /// Currency and exponent come from the terminal's own configuration, as they
  /// do everywhere else in the till. When the server owns tax and currency
  /// (POS-BE-013) this reads them from the restaurant row instead.
  Money _money(int minor) => Money(minor);
}
