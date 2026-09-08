import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/services/authorization.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/service_charge.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// Reads and writes `pos_service_charges` (§38).
class PostgresServiceChargesRepository implements ServiceChargesRepository {
  const PostgresServiceChargesRepository({
    required PosDatabase database,
    required this.config,
    required PosDatabase readDatabase,
    required this.readConfig,
    required this.adminAvailable,
    required this.restaurantId,
    required this.branchId,
  }) : _db = database,
       _tillDb = readDatabase;

  final PosDatabase _db;
  final DeploymentConfig config;

  /// Reads on the till's credential: pricing a ticket needs this on every sale.
  final PosDatabase _tillDb;
  final DeploymentConfig readConfig;

  final bool adminAvailable;
  final int restaurantId;
  final int branchId;

  static const _columns =
      'id, name_en, name_ar, rate_bp, fixed_minor, order_types, is_taxable, '
      'is_automatic, is_optional, is_active, sort_order';

  @override
  Future<List<ServiceCharge>> all({bool includeInactive = false}) async {
    final rows = await _tillDb.query(
      readConfig,
      'SELECT $_columns FROM pos_service_charges WHERE restaurant_id = @r '
      '${includeInactive ? '' : 'AND is_active '}'
      'ORDER BY sort_order, id',
      parameters: {'r': restaurantId},
    );
    return [for (final row in rows) _read(row)];
  }

  ServiceCharge _read(List<dynamic> row) => ServiceCharge(
    id: row[0]! as int,
    nameEn: row[1]! as String,
    nameAr: row[2] as String?,
    rateBp: row[3] as int?,
    fixedMinor: row[4] as int?,
    orderTypes: {
      for (final value in (row[5] as List? ?? const []))
        // An order type this build does not understand is dropped rather than
        // throwing. A restaurant that adds one on a newer binary must not stop
        // an older till from selling.
        ?OrderType.fromWire('$value'),
    },
    isTaxable: row[6]! as bool,
    isAutomatic: row[7]! as bool,
    isOptional: row[8]! as bool,
    isActive: row[9]! as bool,
    sortOrder: row[10]! as int,
  );

  @override
  Future<AdminResult<ServiceCharge>> save(
    ServiceCharge charge, {
    required PosStaff by,
  }) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    // `Authorization.check` and not `by.capabilities`: that field holds the
    // direct grants alone, so a manager whose permission comes from their
    // role would have been refused. It also asks whether they are still
    // employed, which membership of a set does not.
    if (!Authorization.check(by, PosCapability.settingsManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.settingsManage),
      );
    }
    if (charge.nameEn.trim().isEmpty) {
      return const AdminResult.refused(
        CatalogInvalid('A charge needs a name — it goes on the bill.'),
      );
    }
    // Checked here as well as by the CHECK constraint, because the message a
    // person can act on is worth more than the one PostgreSQL writes.
    if ((charge.rateBp == null) == (charge.fixedMinor == null)) {
      return const AdminResult.refused(
        CatalogInvalid('A charge is either a percentage or a fixed amount.'),
      );
    }

    return _db.runTx(config, (tx) async {
      final parameters = <String, Object?>{
        'r': restaurantId,
        'nameEn': charge.nameEn.trim(),
        'nameAr': charge.nameAr?.trim(),
        'rate': charge.rateBp,
        'fixed': charge.fixedMinor,
        'types': [for (final type in charge.orderTypes) type.wire],
        'taxable': charge.isTaxable,
        'automatic': charge.isAutomatic,
        'optional': charge.isOptional,
        'active': charge.isActive,
        'sort': charge.sortOrder,
        'by': by.id == 0 ? null : by.id,
      };

      final rows = charge.id == 0
          ? await tx.execute(
              Sql.named(
                'INSERT INTO pos_service_charges (restaurant_id, name_en, '
                '  name_ar, rate_bp, fixed_minor, order_types, is_taxable, '
                '  is_automatic, is_optional, is_active, sort_order, '
                '  updated_by) '
                'VALUES (@r, @nameEn, @nameAr, @rate, @fixed, @types, '
                '        @taxable, @automatic, @optional, @active, @sort, @by) '
                'RETURNING $_columns',
              ),
              parameters: parameters,
            )
          : await tx.execute(
              Sql.named(
                'UPDATE pos_service_charges SET name_en = @nameEn, '
                '  name_ar = @nameAr, rate_bp = @rate, fixed_minor = @fixed, '
                '  order_types = @types, is_taxable = @taxable, '
                '  is_automatic = @automatic, is_optional = @optional, '
                '  is_active = @active, sort_order = @sort, '
                '  updated_at = now(), updated_by = @by '
                'WHERE id = @id AND restaurant_id = @r RETURNING $_columns',
              ),
              parameters: {...parameters, 'id': charge.id},
            );

      if (rows.isEmpty) {
        return const AdminResult<ServiceCharge>.refused(EditedElsewhere(0));
      }

      // Its own audit action for the same reason a reprice has one: this
      // changes what every future customer pays, and "who added 12% and when"
      // is the question a complaint asks.
      await tx.execute(
        Sql.named('''
        INSERT INTO pos_audit_events
          (restaurant_id, branch_id, actor_staff_id, actor_name, action,
           entity_type, entity_id, after_value)
        VALUES (@restaurant, @branch, @by, @actor, @action, @type, @entity,
                @after::jsonb)
        '''),
        parameters: {
          'restaurant': restaurantId,
          'branch': branchId,
          'by': by.id == 0 ? null : by.id,
          'actor': by.name,
          'action': AuditAction.serviceChargeSaved,
          'type': AuditAction.entityServiceCharge,
          'entity': '${rows.first[0]}',
          'after':
              '{"name": ${_json(charge.nameEn.trim())}, '
              '"rate_bp": ${charge.rateBp ?? 'null'}, '
              '"fixed_minor": ${charge.fixedMinor ?? 'null'}, '
              '"is_active": ${charge.isActive}}',
        },
      );

      return AdminResult.done(_read(rows.first));
    });
  }

  static String _json(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// What a till binds before it has a database.
///
/// Nothing, and no charges — which resolves to the device tax config's single
/// rate, exactly as it did before §38. Inventing a service charge here would be
/// adding money to a bill nobody configured.
class UnconfiguredServiceChargesRepository implements ServiceChargesRepository {
  const UnconfiguredServiceChargesRepository();

  @override
  Future<List<ServiceCharge>> all({bool includeInactive = false}) async =>
      const [];

  @override
  Future<AdminResult<ServiceCharge>> save(
    ServiceCharge charge, {
    required PosStaff by,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}
