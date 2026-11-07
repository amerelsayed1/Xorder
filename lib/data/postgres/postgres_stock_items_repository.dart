import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/money/quantity.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/pos_unit.dart';
import '../../domain/models/stock_item.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';
import 'stock_unit_guard.dart';

/// What the business buys and counts: the stocked rows of `pos_products`.
///
/// Read on the till's credential, written on the administrator's. A new item
/// is written with no category (migration 40), which is what keeps it off the
/// cashier's menu; an item that IS on the menu changes only its unit here.
class PostgresStockItemsRepository implements StockItemsRepository {
  const PostgresStockItemsRepository({
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
      'id, name_en, name_ar, sku, stock_unit, category_id IS NOT NULL, '
      'is_available';

  @override
  Future<List<StockItem>> all({bool includeInactive = false}) async {
    final rows = await _tillDb.query(
      readConfig,
      'SELECT $_columns FROM pos_products '
      'WHERE business_id = @r AND is_stocked '
      '${includeInactive ? '' : 'AND is_available '}'
      'ORDER BY lower(name_en), id',
      parameters: {'r': businessId},
    );
    return [for (final row in rows) _read(row)];
  }

  StockItem _read(List<dynamic> row) => StockItem(
    id: row[0]! as int,
    nameEn: row[1]! as String,
    nameAr: row[2] as String?,
    sku: row[3] as String?,
    unit: QuantityUnit.fromWire(row[4] as String?),
    onMenu: row[5]! as bool,
    isActive: row[6]! as bool,
  );

  @override
  Future<AdminResult<StockItem>> save(
    StockItem item, {
    required PosStaff by,
  }) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    // What is bought is the buyer's, like the units it is counted in.
    if (!Authorization.check(by, PosCapability.purchaseManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.purchaseManage),
      );
    }
    if (item.nameEn.trim().isEmpty && !item.onMenu) {
      return const AdminResult.refused(CatalogInvalid('An item needs a name.'));
    }
    if (!PosUnit.codePattern.hasMatch(item.unit.wire)) {
      return const AdminResult.refused(
        CatalogInvalid('Choose the unit it is counted in.'),
      );
    }

    String? orNull(String? value) =>
        (value?.trim().isEmpty ?? true) ? null : value!.trim();

    try {
      return await _db.runTx(config, (tx) async {
        // Before anything is written, so a refusal needs no rollback.
        if (item.id != 0) {
          final held = await StockUnitGuard.check(
            tx,
            businessId: businessId,
            productId: item.id,
            unit: item.unit,
          );
          if (held != null) return AdminResult<StockItem>.refused(held);
        }

        final Result rows;
        if (item.id == 0) {
          rows = await tx.execute(
            Sql.named(
              'INSERT INTO pos_products (business_id, category_id, name_en, '
              '  name_ar, price_minor, sku, is_available, is_stocked, '
              '  stock_unit) '
              // No category, no price: it is not for sale.
              'VALUES (@r, NULL, @nameEn, @nameAr, 0, @sku, @active, true, '
              '        @unit) '
              'RETURNING $_columns',
            ),
            parameters: {
              'r': businessId,
              'nameEn': item.nameEn.trim(),
              'nameAr': orNull(item.nameAr),
              'sku': orNull(item.sku),
              'active': item.isActive,
              'unit': item.unit.wire,
            },
          );
        } else if (!item.onMenu) {
          rows = await tx.execute(
            Sql.named(
              'UPDATE pos_products SET name_en = @nameEn, name_ar = @nameAr, '
              '  sku = @sku, is_available = @active, stock_unit = @unit, '
              '  revision = revision + 1, updated_at = now() '
              'WHERE id = @id AND business_id = @r AND is_stocked '
              '  AND category_id IS NULL '
              'RETURNING $_columns',
            ),
            parameters: {
              'id': item.id,
              'r': businessId,
              'nameEn': item.nameEn.trim(),
              'nameAr': orNull(item.nameAr),
              'sku': orNull(item.sku),
              'active': item.isActive,
              'unit': item.unit.wire,
            },
          );
        } else {
          // On the menu: the unit only. Its name and price are the Menu
          // pane's, and changing them from here would be a second door to a
          // reprice with none of that door's audit.
          rows = await tx.execute(
            Sql.named(
              'UPDATE pos_products SET stock_unit = @unit, '
              '  revision = revision + 1, updated_at = now() '
              'WHERE id = @id AND business_id = @r AND is_stocked '
              '  AND category_id IS NOT NULL '
              'RETURNING $_columns',
            ),
            parameters: {'id': item.id, 'r': businessId, 'unit': item.unit.wire},
          );
        }

        if (rows.isEmpty) {
          return const AdminResult<StockItem>.refused(EditedElsewhere(0));
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
            'action': AuditAction.stockItemSaved,
            'type': AuditAction.entityProduct,
            'entity': '${saved.id}',
            'after': jsonEncode({
              'name': saved.nameEn,
              'unit': saved.unit.wire,
              'on_menu': saved.onMenu,
              'active': saved.isActive,
            }),
          },
        );
        return AdminResult.done(saved);
      });
    } on PosDbException catch (error) {
      // The one refusal worth its own sentence: a SKU already in use. Any
      // other failure is a real one and goes on up.
      if (error.raw is ServerException &&
          (error.raw as ServerException).code == '23505') {
        return AdminResult.refused(
          CatalogInvalid('Another item already has the SKU "${item.sku}".'),
        );
      }
      rethrow;
    }
  }
}

/// No database on this terminal: nothing counted, nowhere to write.
class UnconfiguredStockItemsRepository implements StockItemsRepository {
  const UnconfiguredStockItemsRepository();

  @override
  Future<List<StockItem>> all({bool includeInactive = false}) async => const [];

  @override
  Future<AdminResult<StockItem>> save(
    StockItem item, {
    required PosStaff by,
  }) async => const AdminResult.refused(AdministratorCredentialRequired());
}
