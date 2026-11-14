import '../../core/config/deployment.dart';
import '../../domain/models/tender_method.dart';
import '../../domain/repositories/repositories.dart';
import '../sql/sql.dart';
import '../sql/row_reads.dart';

/// Reads `pos_tender_types`.
///
/// Read-only for the till, like the menu and for the same reason: a cashier
/// takes a payment method, they do not invent one. Editing belongs to
/// Management.
class PostgresTenderTypesRepository implements TenderTypesRepository {
  const PostgresTenderTypesRepository({
    required SqlDatabase database,
    required this.config,
    required this.businessId,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final int businessId;

  @override
  Future<List<TenderMethod>> all({bool includeInactive = false}) async {
    final rows = await _db.query(
      config,
      'SELECT id, code, name_en, name_ar, kind, counts_as_cash, opens_drawer, '
      '       requires_reference, refund_allowed, is_active, sort_order '
      'FROM pos_tender_types WHERE business_id = @r '
      '${includeInactive ? '' : 'AND is_active '}'
      'ORDER BY sort_order, id',
      parameters: {'r': businessId},
    );

    // A business with no rows is one whose migration has not run, not one
    // that takes no money. Falling back to the seed keeps the till selling —
    // and the seed is what the migration would have written anyway.
    if (rows.isEmpty) return TenderMethod.seeded;

    return [
      for (final row in rows)
        TenderMethod(
          id: row[0]! as int,
          code: row[1]! as String,
          nameEn: row[2]! as String,
          nameAr: row[3] as String?,
          kind: TenderKind.fromWire(row[4] as String?),
          countsAsCash: row.boolean(5),
          opensDrawer: row.boolean(6),
          requiresReference: row.boolean(7),
          refundAllowed: row.boolean(8),
          isActive: row.boolean(9),
          sortOrder: row[10]! as int,
        ),
    ];
  }
}

/// What a till binds before it has a database.
///
/// The seeded four rather than nothing: a payment screen with no methods on it
/// is a till that cannot take money, and the four are what the first migration
/// writes anyway. This is the one place the old hardcoded list still lives, and
/// it is a fallback rather than a definition.
class UnconfiguredTenderTypesRepository implements TenderTypesRepository {
  const UnconfiguredTenderTypesRepository();

  @override
  Future<List<TenderMethod>> all({bool includeInactive = false}) async =>
      TenderMethod.seeded;
}
