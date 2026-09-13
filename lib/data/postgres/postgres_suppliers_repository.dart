import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/services/authorization.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/supplier.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// Reads and writes `pos_suppliers`.
///
/// **Entirely on the administrator connection**, unlike almost everything else
/// in this directory. A till does not buy anything: purchasing is a back-office
/// act from end to end, and giving the counter credential SELECT on who the
/// restaurant owes money to would be handing out its commercial position for no
/// operational benefit.
class PostgresSuppliersRepository implements SuppliersRepository {
  const PostgresSuppliersRepository({
    required PosDatabase database,
    required this.config,
    required this.adminAvailable,
    required this.restaurantId,
    required this.branchId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final bool adminAvailable;
  final int restaurantId;
  final int branchId;

  static const _columns =
      'id, name_en, name_ar, code, contact_name, phone, email, address, '
      'tax_number, payment_term_days, notes, is_active';

  Supplier _read(List<dynamic> row) {
    String? at(int i) {
      final value = (row[i] as String?)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    return Supplier(
      id: row[0]! as int,
      nameEn: row[1]! as String,
      nameAr: at(2),
      code: (row[3] as String?) ?? '',
      contactName: at(4),
      phone: at(5),
      email: at(6),
      address: at(7),
      taxNumber: at(8),
      paymentTermDays: row[9]! as int,
      notes: at(10),
      isActive: row[11]! as bool,
    );
  }

  @override
  Future<List<Supplier>> all({bool includeInactive = false}) async {
    if (!adminAvailable) return const [];

    final rows = await _db.query(
      config,
      'SELECT $_columns FROM pos_suppliers WHERE restaurant_id = @r '
      '${includeInactive ? '' : 'AND is_active '}'
      'ORDER BY name_en, id',
      parameters: {'r': restaurantId},
    );
    return [for (final row in rows) _read(row)];
  }

  @override
  Future<AdminResult<Supplier>> save(
    Supplier supplier, {
    required PosStaff by,
  }) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    // `Authorization.check` and not `by.capabilities`: that field holds the
    // direct grants alone, so a manager whose permission comes from their
    // role would have been refused. It also asks whether they are still
    // employed, which membership of a set does not.
    if (!Authorization.check(by, PosCapability.purchaseManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.purchaseManage),
      );
    }

    final problems = supplier.problems;
    if (problems.isNotEmpty) {
      return AdminResult.refused(CatalogInvalid(problems.first.message));
    }

    return _db.runTx(config, (tx) async {
      final parameters = <String, Object?>{
        'r': restaurantId,
        'nameEn': supplier.nameEn.trim(),
        'nameAr': supplier.nameAr?.trim(),
        'code': supplier.code.trim(),
        'contact': supplier.contactName?.trim(),
        'phone': supplier.phone?.trim(),
        'email': supplier.email?.trim(),
        'address': supplier.address?.trim(),
        'tax': supplier.taxNumber?.trim(),
        'terms': supplier.paymentTermDays,
        'notes': supplier.notes?.trim(),
        'active': supplier.isActive,
        'by': by.id == 0 ? null : by.id,
      };

      final rows = supplier.id == 0
          ? await tx.execute(
              Sql.named(
                'INSERT INTO pos_suppliers (restaurant_id, name_en, name_ar, '
                '  code, contact_name, phone, email, address, tax_number, '
                '  payment_term_days, notes, is_active, updated_by) '
                'VALUES (@r, @nameEn, @nameAr, @code, @contact, @phone, '
                '        @email, @address, @tax, @terms, @notes, @active, @by) '
                'RETURNING $_columns',
              ),
              parameters: parameters,
            )
          : await tx.execute(
              Sql.named(
                'UPDATE pos_suppliers SET name_en = @nameEn, '
                '  name_ar = @nameAr, code = @code, contact_name = @contact, '
                '  phone = @phone, email = @email, address = @address, '
                '  tax_number = @tax, payment_term_days = @terms, '
                '  notes = @notes, is_active = @active, updated_at = now(), '
                '  updated_by = @by '
                'WHERE id = @id AND restaurant_id = @r RETURNING $_columns',
              ),
              parameters: {...parameters, 'id': supplier.id},
            );

      if (rows.isEmpty) {
        return const AdminResult<Supplier>.refused(EditedElsewhere(0));
      }

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
          'action': AuditAction.supplierSaved,
          'type': AuditAction.entitySupplier,
          'entity': '${rows.first[0]}',
          'after':
              '{"name": ${_json(supplier.nameEn.trim())}, '
              '"is_active": ${supplier.isActive}}',
        },
      );

      return AdminResult.done(_read(rows.first));
    });
  }

  static String _json(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// What a terminal binds before it has an administrator credential.
class UnconfiguredSuppliersRepository implements SuppliersRepository {
  const UnconfiguredSuppliersRepository();

  @override
  Future<List<Supplier>> all({bool includeInactive = false}) async => const [];

  @override
  Future<AdminResult<Supplier>> save(
    Supplier supplier, {
    required PosStaff by,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}
