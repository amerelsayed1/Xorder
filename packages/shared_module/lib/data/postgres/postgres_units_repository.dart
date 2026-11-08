import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/pos_unit.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';

/// Reads and writes `pos_units` (migration 39).
///
/// Read on the till's credential — a purchase line and a stock row are labelled
/// from it — and written on the administrator's, like every other list the
/// back office authors.
class PostgresUnitsRepository implements UnitsRepository {
  const PostgresUnitsRepository({
    required PosDatabase database,
    required this.config,
    required PosDatabase readDatabase,
    required this.readConfig,
    required this.adminAvailable,
    required this.businessId,
    required this.branchId,
  }) : _db = database,
       _tillDb = readDatabase;

  final PosDatabase _db;
  final DeploymentConfig config;
  final PosDatabase _tillDb;
  final DeploymentConfig readConfig;
  final bool adminAvailable;
  final int businessId;
  final int branchId;

  static const _columns =
      'id, code, name_en, name_ar, eta_unit_type, allows_fraction, is_active, '
      'sort_order';

  @override
  Future<List<PosUnit>> all({bool includeInactive = false}) async {
    final rows = await _tillDb.query(
      readConfig,
      'SELECT $_columns FROM pos_units WHERE business_id = @r '
      '${includeInactive ? '' : 'AND is_active '}'
      'ORDER BY sort_order, id',
      parameters: {'r': businessId},
    );
    return [for (final row in rows) _read(row)];
  }

  PosUnit _read(List<dynamic> row) => PosUnit(
    id: row[0]! as int,
    code: row[1]! as String,
    nameEn: row[2]! as String,
    nameAr: row[3] as String?,
    etaUnitType: row[4]! as String,
    allowsFraction: row[5]! as bool,
    isActive: row[6]! as bool,
    sortOrder: row[7]! as int,
  );

  @override
  Future<AdminResult<PosUnit>> save(PosUnit unit, {required PosStaff by}) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    // Units exist for buying and counting stock, so they are the buyer's.
    if (!Authorization.check(by, PosCapability.purchaseManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.purchaseManage),
      );
    }
    final problem = validate(unit);
    if (problem != null) return AdminResult.refused(CatalogInvalid(problem));

    return _db.runTx(config, (tx) async {
      final parameters = <String, Object?>{
        'r': businessId,
        'code': unit.code.trim(),
        'nameEn': unit.nameEn.trim(),
        'nameAr': (unit.nameAr?.trim().isEmpty ?? true)
            ? null
            : unit.nameAr!.trim(),
        'eta': unit.etaUnitType.trim().toUpperCase(),
        'fraction': unit.allowsFraction,
        'active': unit.isActive,
        'sort': unit.sortOrder,
      };

      final rows = unit.id == 0
          ? await tx.execute(
              Sql.named(
                'INSERT INTO pos_units (business_id, code, name_en, name_ar, '
                '  eta_unit_type, allows_fraction, is_active, sort_order) '
                'VALUES (@r, @code, @nameEn, @nameAr, @eta, @fraction, '
                '        @active, @sort) '
                'ON CONFLICT (business_id, code) DO NOTHING '
                'RETURNING $_columns',
              ),
              parameters: parameters,
            )
          // The code is not in the SET list: purchase lines and stock rows
          // store it, and renaming it would orphan every one of them.
          : await tx.execute(
              Sql.named(
                'UPDATE pos_units SET name_en = @nameEn, name_ar = @nameAr, '
                '  eta_unit_type = @eta, allows_fraction = @fraction, '
                '  is_active = @active, sort_order = @sort, updated_at = now() '
                'WHERE id = @id AND business_id = @r RETURNING $_columns',
              ),
              // Without `code`: it is not in the SET list, and the driver
              // refuses a parameter the statement does not use.
              parameters: {...parameters, 'id': unit.id}..remove('code'),
            );

      if (rows.isEmpty) {
        return AdminResult<PosUnit>.refused(
          unit.id == 0
              ? CatalogInvalid(
                  'There is already a unit with the code "${unit.code}".',
                )
              : const EditedElsewhere(0),
        );
      }
      final saved = _read(rows.first);

      await tx.execute(
        Sql.named('''
        INSERT INTO pos_audit_events
          (business_id, branch_id, actor_user_id, actor_name, action,
           entity_type, entity_id, after_value)
        VALUES (@business, @branch, @by, @actor, @action, @type, @entity,
                @after::jsonb)
        '''),
        parameters: {
          'business': businessId,
          'branch': branchId,
          'by': by.id == 0 ? null : by.id,
          'actor': by.name,
          'action': AuditAction.unitSaved,
          'type': AuditAction.entityUnit,
          'entity': '${saved.id}',
          'after': jsonEncode({
            'code': saved.code,
            'name': saved.nameEn,
            'eta_unit_type': saved.etaUnitType,
            'allows_fraction': saved.allowsFraction,
            'active': saved.isActive,
          }),
        },
      );
      return AdminResult.done(saved);
    });
  }

  /// Why [unit] cannot be saved, or null. Checked here as well as by the
  /// database's CHECKs, because this sentence is one a person can act on.
  static String? validate(PosUnit unit) {
    if (unit.nameEn.trim().isEmpty) return 'A unit needs a name.';
    if (!PosUnit.codePattern.hasMatch(unit.code.trim())) {
      return 'A unit code is lowercase letters and digits, starting with a '
          'letter — kg, tray, box6.';
    }
    if (!PosUnit.etaPattern.hasMatch(unit.etaUnitType.trim().toUpperCase())) {
      return 'The tax authority code is up to six capital letters or digits — '
          'EA, KGM, LTR.';
    }
    return null;
  }
}

/// No database on this terminal: no units to read, nowhere to write one.
class UnconfiguredUnitsRepository implements UnitsRepository {
  const UnconfiguredUnitsRepository();

  @override
  Future<List<PosUnit>> all({bool includeInactive = false}) async => const [];

  @override
  Future<AdminResult<PosUnit>> save(PosUnit unit, {required PosStaff by}) async =>
      const AdminResult.refused(AdministratorCredentialRequired());
}
