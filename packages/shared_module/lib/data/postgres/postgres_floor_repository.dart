import '../../core/config/deployment.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// The branch's floor plan, read from the branch server.
///
/// **Every table comes back free, and that is not a bug yet.** A table's state
/// is a property of an *open* ticket, and open tickets are still held in the
/// till's memory — `pos_orders` records sales that have already been settled, so
/// a row there means the table was closed, not that it is occupied. Inventing a
/// state from settled orders would put a plausible number on screen that no
/// query could justify, which is worse than an honest FREE.
///
/// When open-ticket persistence lands, this is the one method that changes: the
/// state, the line count and the running total all come from that table, and
/// nothing above this class moves.
class PostgresFloorRepository implements TablesRepository {
  const PostgresFloorRepository({
    required PosDatabase database,
    required this._config,
    required this._businessId,
    required this._branchId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig _config;
  final int _businessId;
  final int _branchId;

  @override
  Future<List<DiningTable>> liveFloor() async {
    final rows = await _db.query(
      _config,
      'SELECT id, label, seats, area_name FROM pos_dining_tables '
      'WHERE business_id = @business AND branch_id = @branch AND is_active '
      'ORDER BY sort_order, id',
      parameters: {'business': _businessId, 'branch': _branchId},
    );

    return [
      for (final row in rows)
        DiningTable(
          id: row[0] as int,
          label: row[1] as String,
          seats: row[2] as int?,
          areaName: row[3] as String?,
        ),
    ];
  }
}
