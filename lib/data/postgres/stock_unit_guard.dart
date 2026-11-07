import 'package:postgres/postgres.dart';

import '../../core/money/quantity.dart';
import '../../domain/repositories/admin_repositories.dart';

/// Whether an item may change the unit it is counted in, given what it holds.
///
/// **Two editors write `pos_products.stock_unit`** — the Items pane
/// (`PostgresStockItemsRepository`) and the Menu pane
/// (`PostgresCatalogAdminRepository`) — so the question lives here once rather
/// than in each, answered slightly differently by whichever was written
/// second. Migration 44 asks it again in the database, for everybody else.
///
/// The rule: while any branch holds a non-zero quantity in one unit, the item
/// cannot move to another. There is no conversion in this product, and a
/// relabel is a conversion by 1 — ten kilos becoming ten boxes nobody bought.
abstract final class StockUnitGuard {
  /// Null when [unit] is fine; otherwise the refusal to return.
  ///
  /// Call it inside the write's transaction, before the UPDATE. The product
  /// row is locked `FOR NO KEY UPDATE` — the lock the UPDATE takes anyway —
  /// and receiving takes `FOR SHARE` on it, so a delivery and a unit change
  /// queue rather than each reading "nothing held" and both committing.
  ///
  /// Only an actual change is checked, exactly as the trigger's `WHEN` is: a
  /// branch that ran an older build may hold stock in a unit that already
  /// disagrees with the item, and refusing every rename of it until then would
  /// punish the business for a defect it did not write.
  static Future<StockHeldInAnotherUnit?> check(
    TxSession tx, {
    required int businessId,
    required int productId,
    required QuantityUnit unit,
  }) async {
    final current = await tx.execute(
      Sql.named(
        "SELECT name_en, coalesce(nullif(trim(stock_unit), ''), 'ea') "
        'FROM pos_products WHERE id = @p AND business_id = @r '
        'FOR NO KEY UPDATE',
      ),
      parameters: {'p': productId, 'r': businessId},
    );
    // Gone: the caller's UPDATE finds nothing and says so in its own words.
    if (current.isEmpty) return null;
    if (current.first[1] == unit.wire) return null;

    final held = await tx.execute(
      Sql.named(
        'SELECT quantity_milli, unit FROM pos_stock_levels '
        'WHERE product_id = @p AND business_id = @r '
        '  AND quantity_milli <> 0 AND unit <> @unit '
        'ORDER BY branch_id LIMIT 1',
      ),
      parameters: {'p': productId, 'r': businessId, 'unit': unit.wire},
    );
    if (held.isEmpty) return null;

    return StockHeldInAnotherUnit(
      item: current.first[0]! as String,
      held: Quantity(
        held.first[0]! as int,
        unit: QuantityUnit.fromWire(held.first[1] as String?),
      ),
      asked: unit,
    );
  }
}
