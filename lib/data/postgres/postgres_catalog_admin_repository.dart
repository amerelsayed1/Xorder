import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/authorization.dart';
import 'money_config_codec.dart';
import 'pos_database.dart';

/// Authoring the menu, on the till, against the branch database.
///
/// **Offline only.** `BootstrapSeeder._seedCatalog` DELETEs the whole catalogue
/// and re-inserts the platform's rows, so a locally authored menu on a CLOUD
/// till survives exactly until its next bundle. The provider refuses to build
/// this outside [DeploymentMode.offline]; [adminAvailable] and [offline] are
/// both checked here as well, because a rule that lives only in a provider is
/// a rule the next caller does not know about.
///
/// Every write follows the shape `PostgresRolesRepository.save` established:
/// capability check → one transaction → `SELECT … FOR UPDATE` → refuse on a
/// lost revision race → `UPDATE … RETURNING` → audit row in the SAME
/// transaction, so a change cannot commit without the record of who made it.
class PostgresCatalogAdminRepository implements CatalogAdminRepository {
  PostgresCatalogAdminRepository({
    required this.database,
    required this.config,
    required this.restaurantId,
    this.branchId,
    this.terminalId,
    this.adminAvailable = true,
    this.offline = true,
  });

  final PosDatabase database;
  final DeploymentConfig config;
  final int restaurantId;
  final int? branchId;
  final String? terminalId;

  /// Whether an administrator database password has been supplied this session.
  final bool adminAvailable;

  /// Whether this terminal authors its own menu at all.
  final bool offline;

  static const _categoryColumns =
      'id, name_en, name_ar, slug, sort_order, is_active, revision';
  static const _productColumns =
      'id, category_id, name_en, name_ar, price_minor, discounted_price_minor, '
      'sku, barcode, is_available, sort_order, revision';

  AdminRefusal? _blocked(PosStaff by) {
    if (!offline) return const NotPermitted(PosCapability.catalogManage);
    if (!adminAvailable) return const AdministratorCredentialRequired();

    final decision = Authorization.check(by, PosCapability.catalogManage);
    if (!decision.isAllowed) {
      return const NotPermitted(PosCapability.catalogManage);
    }
    return null;
  }

  // ── categories ─────────────────────────────────────────────────────────────

  @override
  Future<AdminResult<Category>> saveCategory(
    Category category, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    if (category.nameEn.trim().isEmpty) {
      return const AdminResult.refused(
        CatalogInvalid('A category needs a name.'),
      );
    }

    return database.runTx(config, (tx) async {
      if (category.id == 0) {
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_categories '
            '  (restaurant_id, name_en, name_ar, slug, sort_order, is_active) '
            'VALUES (@r, @nameEn, @nameAr, @slug, @sort, true) '
            'RETURNING $_categoryColumns',
          ),
          parameters: _categoryParams(category),
        );
        final created = _categoryFrom(rows.first);
        await _audit(
          tx,
          by: by,
          action: AuditAction.categoryCreated,
          entityType: AuditAction.entityCategory,
          entityId: '${created.id}',
          after: {'name': created.nameEn, 'slug': created.slug},
        );
        return AdminResult.done(created);
      }

      final existing = await tx.execute(
        Sql.named(
          'SELECT $_categoryColumns FROM pos_categories '
          'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
        ),
        parameters: {'id': category.id, 'r': restaurantId},
      );
      if (existing.isEmpty) {
        return const AdminResult.refused(EditedElsewhere(0));
      }
      final before = _categoryFrom(existing.first);

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_categories SET name_en = @nameEn, name_ar = @nameAr, '
          '  slug = @slug, sort_order = @sort, '
          '  revision = revision + 1, updated_at = now() '
          'WHERE id = @id AND restaurant_id = @r '
          'RETURNING $_categoryColumns',
        ),
        parameters: {..._categoryParams(category), 'id': category.id},
      );
      final saved = _categoryFrom(rows.first);
      await _audit(
        tx,
        by: by,
        action: AuditAction.categoryUpdated,
        entityType: AuditAction.entityCategory,
        entityId: '${saved.id}',
        before: {'name': before.nameEn, 'slug': before.slug},
        after: {'name': saved.nameEn, 'slug': saved.slug},
      );
      return AdminResult.done(saved);
    });
  }

  @override
  Future<AdminResult<Category>> archiveCategory(
    Category category, {
    required PosStaff by,
    bool restore = false,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    return database.runTx(config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_categories SET is_active = @active, '
          '  revision = revision + 1, updated_at = now() '
          'WHERE id = @id AND restaurant_id = @r '
          'RETURNING $_categoryColumns',
        ),
        parameters: {'id': category.id, 'r': restaurantId, 'active': restore},
      );
      if (rows.isEmpty) return const AdminResult.refused(EditedElsewhere(0));

      final saved = _categoryFrom(rows.first);
      await _audit(
        tx,
        by: by,
        action: restore
            ? AuditAction.categoryRestored
            : AuditAction.categoryArchived,
        entityType: AuditAction.entityCategory,
        entityId: '${saved.id}',
        after: {'name': saved.nameEn},
      );
      return AdminResult.done(saved);
    });
  }

  // ── products ───────────────────────────────────────────────────────────────

  @override
  Future<AdminResult<Product>> saveProduct(
    Product product, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    if (product.nameEn.trim().isEmpty) {
      return const AdminResult.refused(CatalogInvalid('An item needs a name.'));
    }
    // The database checks both prices are non-negative. It does NOT check that
    // a discount is below the full price — nothing stops `discounted > price`
    // in SQL — so it is checked here, where it can be explained.
    final discounted = product.discountedPrice;
    if (discounted != null && discounted.minor > product.price.minor) {
      return const AdminResult.refused(
        CatalogInvalid('The offer price is higher than the normal price.'),
      );
    }

    return database.runTx(config, (tx) async {
      if (product.id == 0) {
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_products '
            '  (restaurant_id, category_id, name_en, name_ar, price_minor, '
            '   discounted_price_minor, sku, barcode, is_available, sort_order) '
            'VALUES (@r, @category, @nameEn, @nameAr, @price, @discounted, '
            '        @sku, @barcode, @available, @sort) '
            'RETURNING $_productColumns',
          ),
          parameters: _productParams(product),
        );
        final created = _productFrom(rows.first);
        await _audit(
          tx,
          by: by,
          action: AuditAction.productCreated,
          entityType: AuditAction.entityProduct,
          entityId: '${created.id}',
          after: {'name': created.nameEn, 'price_minor': created.price.minor},
        );
        return AdminResult.done(created);
      }

      final existing = await tx.execute(
        Sql.named(
          'SELECT $_productColumns FROM pos_products '
          'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
        ),
        parameters: {'id': product.id, 'r': restaurantId},
      );
      if (existing.isEmpty) {
        return const AdminResult.refused(EditedElsewhere(0));
      }
      final before = _productFrom(existing.first);

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_products SET category_id = @category, name_en = @nameEn, '
          '  name_ar = @nameAr, price_minor = @price, '
          '  discounted_price_minor = @discounted, sku = @sku, '
          '  barcode = @barcode, is_available = @available, sort_order = @sort, '
          '  revision = revision + 1, updated_at = now() '
          'WHERE id = @id AND restaurant_id = @r '
          'RETURNING $_productColumns',
        ),
        parameters: {..._productParams(product), 'id': product.id},
      );
      final saved = _productFrom(rows.first);

      // A price change is its own action. "Who changed what this costs, and
      // when" is the question a disputed receipt asks, and finding it inside a
      // generic `product.updated` means reading every edit ever made.
      final repriced =
          before.price.minor != saved.price.minor ||
          before.discountedPrice?.minor != saved.discountedPrice?.minor;

      await _audit(
        tx,
        by: by,
        action: repriced
            ? AuditAction.productRepriced
            : AuditAction.productUpdated,
        entityType: AuditAction.entityProduct,
        entityId: '${saved.id}',
        before: {
          'name': before.nameEn,
          'price_minor': before.price.minor,
          'discounted_price_minor': before.discountedPrice?.minor,
        },
        after: {
          'name': saved.nameEn,
          'price_minor': saved.price.minor,
          'discounted_price_minor': saved.discountedPrice?.minor,
        },
      );
      return AdminResult.done(saved);
    });
  }

  @override
  Future<AdminResult<Product>> archiveProduct(
    Product product, {
    required PosStaff by,
    bool restore = false,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    return database.runTx(config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_products SET is_available = @available, '
          '  revision = revision + 1, updated_at = now() '
          'WHERE id = @id AND restaurant_id = @r '
          'RETURNING $_productColumns',
        ),
        parameters: {'id': product.id, 'r': restaurantId, 'available': restore},
      );
      if (rows.isEmpty) return const AdminResult.refused(EditedElsewhere(0));

      final saved = _productFrom(rows.first);
      await _audit(
        tx,
        by: by,
        action: restore
            ? AuditAction.productRestored
            : AuditAction.productArchived,
        entityType: AuditAction.entityProduct,
        entityId: '${saved.id}',
        after: {'name': saved.nameEn},
      );
      return AdminResult.done(saved);
    });
  }

  @override
  Future<AdminResult<TaxConfig>> saveMoneyConfig(
    TaxConfig config, {
    required PosStaff by,
  }) async {
    // A different capability from the menu: what a plate costs and what the
    // government takes are different jobs, and the role editor has separate
    // boxes for them.
    if (!offline) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.settingsManage),
      );
    }
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    if (!Authorization.check(by, PosCapability.settingsManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.settingsManage),
      );
    }
    if (config.serviceBp < 0 || config.vatBp < 0) {
      return const AdminResult.refused(
        CatalogInvalid('A rate cannot be negative.'),
      );
    }

    return database.runTx(this.config, (tx) async {
      final existing = await tx.execute(
        Sql.named(
          'SELECT payload FROM pos_money_config WHERE restaurant_id = @r',
        ),
        parameters: {'r': restaurantId},
      );
      final beforePayload = existing.isEmpty
          ? null
          : _payload(existing.first[0]);
      final before = beforePayload == null
          ? null
          : MoneyConfigCodec.toTaxConfig(beforePayload);

      final payload = jsonEncode(MoneyConfigCodec.fromTaxConfig(config));
      await tx.execute(
        Sql.named(
          'INSERT INTO pos_money_config (restaurant_id, payload, synced_at) '
          'VALUES (@r, @payload::jsonb, now()) '
          'ON CONFLICT (restaurant_id) DO UPDATE '
          '  SET payload = @payload::jsonb, synced_at = now()',
        ),
        parameters: {'r': restaurantId, 'payload': payload},
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.moneyConfigChanged,
        entityType: AuditAction.entityMoney,
        entityId: '$restaurantId',
        before: before == null
            ? null
            : {'service_bp': before.serviceBp, 'vat_bp': before.vatBp},
        after: {'service_bp': config.serviceBp, 'vat_bp': config.vatBp},
      );

      // Read back through the codec, so what is returned is what the ticket
      // will actually price with rather than what was asked for.
      return AdminResult.done(
        MoneyConfigCodec.toTaxConfig(MoneyConfigCodec.fromTaxConfig(config)),
      );
    });
  }

  // ── the floor ──────────────────────────────────────────────────────────────

  static const _tableColumns = 'id, label, seats, area_name, is_active';

  /// The floor plan is the ROOM, not the menu, so it answers to
  /// `settings.manage` like the money rules do.
  AdminRefusal? _blockedSettings(PosStaff by) {
    if (!offline) return const NotPermitted(PosCapability.settingsManage);
    if (!adminAvailable) return const AdministratorCredentialRequired();
    if (!Authorization.check(by, PosCapability.settingsManage).isAllowed) {
      return const NotPermitted(PosCapability.settingsManage);
    }
    return null;
  }

  @override
  Future<AdminResult<DiningTable>> saveTable(
    DiningTable table, {
    required PosStaff by,
  }) async {
    final blocked = _blockedSettings(by);
    if (blocked != null) return AdminResult.refused(blocked);

    if (table.label.trim().isEmpty) {
      return const AdminResult.refused(
        CatalogInvalid('A table needs a label.'),
      );
    }
    if (table.seats < 1) {
      return const AdminResult.refused(
        CatalogInvalid('A table seats at least one person.'),
      );
    }
    final branch = branchId;
    if (branch == null) {
      return const AdminResult.refused(EditedElsewhere(0));
    }

    return database.runTx(config, (tx) async {
      final parameters = {
        'r': restaurantId,
        'branch': branch,
        'label': table.label.trim(),
        'seats': table.seats,
        'area': _orNull(table.areaName),
      };

      if (table.id == 0) {
        // The unique key is `(branch_id, label)`. A duplicate is an operator
        // mistake with an obvious fix, so it is named rather than thrown.
        final clash = await tx.execute(
          Sql.named(
            'SELECT 1 FROM pos_dining_tables '
            'WHERE branch_id = @branch AND label = @label',
          ),
          parameters: {'branch': branch, 'label': table.label.trim()},
        );
        if (clash.isNotEmpty) {
          return AdminResult<DiningTable>.refused(
            CatalogInvalid(
              'There is already a table called '
              '"${table.label.trim()}" in this branch.',
            ),
          );
        }

        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_dining_tables '
            '  (restaurant_id, branch_id, label, seats, area_name) '
            'VALUES (@r, @branch, @label, @seats, @area) '
            'RETURNING $_tableColumns',
          ),
          parameters: parameters,
        );
        final created = _tableFrom(rows.first);
        await _audit(
          tx,
          by: by,
          action: AuditAction.tableCreated,
          entityType: AuditAction.entityTable,
          entityId: '${created.id}',
          after: {'label': created.label, 'seats': created.seats},
        );
        return AdminResult.done(created);
      }

      final existing = await tx.execute(
        Sql.named(
          'SELECT $_tableColumns FROM pos_dining_tables '
          'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
        ),
        parameters: {'id': table.id, 'r': restaurantId},
      );
      if (existing.isEmpty) {
        return const AdminResult<DiningTable>.refused(EditedElsewhere(0));
      }
      final before = _tableFrom(existing.first);

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_dining_tables SET label = @label, seats = @seats, '
          '  area_name = @area '
          'WHERE id = @id AND restaurant_id = @r '
          'RETURNING $_tableColumns',
        ),
        parameters: {...parameters, 'id': table.id},
      );
      final saved = _tableFrom(rows.first);
      await _audit(
        tx,
        by: by,
        action: AuditAction.tableUpdated,
        entityType: AuditAction.entityTable,
        entityId: '${saved.id}',
        before: {'label': before.label, 'seats': before.seats},
        after: {'label': saved.label, 'seats': saved.seats},
      );
      return AdminResult.done(saved);
    });
  }

  @override
  Future<AdminResult<DiningTable>> archiveTable(
    DiningTable table, {
    required PosStaff by,
    bool restore = false,
  }) async {
    final blocked = _blockedSettings(by);
    if (blocked != null) return AdminResult.refused(blocked);

    return database.runTx(config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_dining_tables SET is_active = @active '
          'WHERE id = @id AND restaurant_id = @r '
          'RETURNING $_tableColumns',
        ),
        parameters: {'id': table.id, 'r': restaurantId, 'active': restore},
      );
      if (rows.isEmpty) {
        return const AdminResult<DiningTable>.refused(EditedElsewhere(0));
      }

      final saved = _tableFrom(rows.first);
      await _audit(
        tx,
        by: by,
        action: restore ? AuditAction.tableRestored : AuditAction.tableArchived,
        entityType: AuditAction.entityTable,
        entityId: '${saved.id}',
        after: {'label': saved.label},
      );
      return AdminResult.done(saved);
    });
  }

  DiningTable _tableFrom(ResultRow row) => DiningTable(
    id: row[0]! as int,
    label: row[1]! as String,
    seats: row[2]! as int,
    areaName: row[3] as String?,
  );

  @override
  Future<AdminResult<void>> attachModifierGroups(
    int productId,
    List<int> groupIds, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult<void>.refused(blocked);

    return database.runTx(config, (tx) async {
      // Scoped delete: the product must belong to this restaurant, or a
      // mistyped id could unpick somebody else's menu on a shared server.
      final owned = await tx.execute(
        Sql.named(
          'SELECT 1 FROM pos_products WHERE id = @id AND restaurant_id = @r',
        ),
        parameters: {'id': productId, 'r': restaurantId},
      );
      if (owned.isEmpty) {
        return const AdminResult<void>.refused(EditedElsewhere(0));
      }

      await tx.execute(
        Sql.named(
          'DELETE FROM pos_product_modifier_groups WHERE product_id = @id',
        ),
        parameters: {'id': productId},
      );

      for (var position = 0; position < groupIds.length; position++) {
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_product_modifier_groups '
            '  (product_id, group_id, sort_order) '
            'VALUES (@product, @group, @sort) '
            'ON CONFLICT (product_id, group_id) DO NOTHING',
          ),
          parameters: {
            'product': productId,
            'group': groupIds[position],
            'sort': position,
          },
        );
      }

      await _audit(
        tx,
        by: by,
        action: AuditAction.productUpdated,
        entityType: AuditAction.entityProduct,
        entityId: '$productId',
        after: {'modifier_groups': groupIds},
      );
      return const AdminResult<void>.done(null);
    });
  }

  // ── plumbing ───────────────────────────────────────────────────────────────

  Map<String, Object?> _categoryParams(Category category) => {
    'r': restaurantId,
    'nameEn': category.nameEn.trim(),
    'nameAr': _orNull(category.nameAr),
    'slug': _orNull(category.slug),
    'sort': category.sortOrder,
  };

  Map<String, Object?> _productParams(Product product) => {
    'r': restaurantId,
    'category': product.categoryId,
    'nameEn': product.nameEn.trim(),
    'nameAr': _orNull(product.nameAr),
    'price': product.price.minor,
    'discounted': product.discountedPrice?.minor,
    // Empty strings would collide under the unique constraints, where
    // multiple NULLs are fine. A blank box means "not set", not "".
    'sku': _orNull(product.sku),
    'barcode': _orNull(product.barcode),
    'available': product.isAvailable,
    'sort': product.sortOrder,
  };

  /// `jsonb` arrives from the driver already decoded on some paths and as a
  /// string on others. Both are the same document.
  static Map<String, Object?>? _payload(Object? raw) => switch (raw) {
    final Map<String, Object?> map => map,
    final Map map => map.cast<String, Object?>(),
    final String text => (jsonDecode(text) as Map).cast<String, Object?>(),
    _ => null,
  };

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Category _categoryFrom(ResultRow row) => Category(
    id: row[0]! as int,
    nameEn: row[1]! as String,
    nameAr: row[2] as String?,
    slug: row[3] as String?,
    sortOrder: row[4]! as int,
    isActive: row[5]! as bool,
  );

  Product _productFrom(ResultRow row) => Product(
    id: row[0]! as int,
    categoryId: row[1]! as int,
    nameEn: row[2]! as String,
    nameAr: row[3] as String?,
    price: Money(row[4]! as int),
    discountedPrice: row[5] == null ? null : Money(row[5]! as int),
    sku: row[6] as String?,
    barcode: row[7] as String?,
    isAvailable: row[8]! as bool,
    sortOrder: row[9]! as int,
  );

  /// One ledger row, on the open transaction.
  ///
  /// Deliberately not `PostgresAuditRepository`: that opens its own, and a
  /// change that committed without its audit row — or an audit row for a
  /// change that rolled back — is exactly what this must not allow.
  Future<void> _audit(
    TxSession tx, {
    required PosStaff by,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) => tx.execute(
    Sql.named(
      'INSERT INTO pos_audit_events (restaurant_id, branch_id, terminal_id, '
      '  actor_staff_id, actor_name, action, entity_type, entity_id, '
      '  before_value, after_value) '
      'VALUES (@r, @branch, @terminal, @actor, @actorName, @action, '
      '        @entityType, @entityId, @before::jsonb, @after::jsonb)',
    ),
    parameters: {
      'r': restaurantId,
      'branch': branchId,
      'terminal': terminalId,
      'actor': by.id,
      'actorName': by.name,
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'before': before == null ? null : jsonEncode(before),
      'after': after == null ? null : jsonEncode(after),
    },
  );
}
