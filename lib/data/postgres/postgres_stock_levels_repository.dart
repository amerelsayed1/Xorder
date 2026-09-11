import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../../domain/models/stock_level.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// What each counted item stands at in this branch (`pos_stock_levels`).
///
/// On the administrator's credential: the till is granted nothing on stock
/// levels, and this is only ever read from the back office.
class PostgresStockLevelsRepository implements StockLevelsRepository {
  const PostgresStockLevelsRepository({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    required this.branchId,
    this.currency = 'EGP',
    this.exponent = 2,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;
  final int branchId;
  final String currency;
  final int exponent;

  @override
  Future<List<StockLevel>> all() async {
    final rows = await _db.query(
      config,
      // Every counted item, and anything with a position here even if it has
      // since stopped being counted: stock that exists is stock to report.
      // An item counted but never received reads as nothing on hand, in the
      // unit it is counted in.
      'SELECT p.id, p.name_en, p.name_ar, p.category_id IS NOT NULL, '
      '       coalesce(l.quantity_milli, 0), '
      "       coalesce(l.unit, p.stock_unit, 'ea'), "
      '       coalesce(l.average_cost_minor, 0) '
      'FROM pos_products p '
      'LEFT JOIN pos_stock_levels l '
      '  ON l.product_id = p.id AND l.branch_id = @branch '
      'WHERE p.restaurant_id = @restaurant '
      '  AND (p.is_stocked OR l.product_id IS NOT NULL) '
      'ORDER BY lower(p.name_en), p.id',
      parameters: {'restaurant': restaurantId, 'branch': branchId},
    );
    return [
      for (final row in rows)
        StockLevel(
          productId: row[0]! as int,
          nameEn: row[1]! as String,
          nameAr: row[2] as String?,
          onMenu: row[3]! as bool,
          onHand: Quantity(
            row[4]! as int,
            unit: QuantityUnit.fromWire(row[5] as String?),
          ),
          unitCost: Money(
            row[6]! as int,
            currency: currency,
            exponent: exponent,
          ),
        ),
    ];
  }
}

/// No database on this terminal: nothing to report.
class UnconfiguredStockLevelsRepository implements StockLevelsRepository {
  const UnconfiguredStockLevelsRepository();

  @override
  Future<List<StockLevel>> all() async => const [];
}
