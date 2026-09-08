import '../../core/config/deployment.dart';
import '../../domain/models/order_type_config.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// Reads `pos_order_types` (§31).
class PostgresOrderTypesRepository implements OrderTypesRepository {
  const PostgresOrderTypesRepository({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;

  @override
  Future<List<OrderTypeConfig>> all({bool includeInactive = false}) async {
    final rows = await _db.query(
      config,
      'SELECT code, name_en, name_ar, requires_table, requires_customer, '
      '       requires_address, is_active, sort_order '
      'FROM pos_order_types WHERE restaurant_id = @r '
      '${includeInactive ? '' : 'AND is_active '}'
      'ORDER BY sort_order, id',
      parameters: {'r': restaurantId},
    );

    return [
      for (final row in rows)
        // A code this build does not know is dropped rather than throwing. It
        // has nowhere to be rendered — see the note on [OrderTypeConfig] — and
        // a till must not refuse to sell because a newer binary added one.
        if (OrderType.fromWire(row[0]! as String) case final type?)
          OrderTypeConfig(
            type: type,
            nameEn: row[1]! as String,
            nameAr: row[2] as String?,
            requiresTable: row[3]! as bool,
            requiresCustomer: row[4]! as bool,
            requiresAddress: row[5]! as bool,
            isActive: row[6]! as bool,
            sortOrder: row[7]! as int,
          ),
    ];
  }
}
