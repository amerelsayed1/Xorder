import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/tax.dart';
import '../../domain/models/order_type_config.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/models/tender_method.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/menu_import.dart';
import '../../domain/services/authorization.dart';
import 'money_config_codec.dart';
import 'pos_database.dart';
import 'stock_unit_guard.dart';

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
      'sku, barcode, is_available, sort_order, revision, tax_group_id, '
      'is_stocked, stock_unit';

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
  Future<AdminResult<MenuImportOutcome>> importMenu(
    MenuImportPlan plan, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    // Re-checked here, not trusted from the screen. The preview is a courtesy;
    // this is the thing that must not write half a menu.
    if (!plan.canApply) {
      return const AdminResult.refused(
        CatalogInvalid('That file has problems that have to be fixed first.'),
      );
    }

    return database.runTx(config, (tx) async {
      // Categories first: a product cannot be written without one.
      final categoryIds = <String, int>{};
      final existing = await tx.execute(
        Sql.named(
          'SELECT id, name_en FROM pos_categories WHERE restaurant_id = @r',
        ),
        parameters: {'r': restaurantId},
      );
      for (final row in existing) {
        categoryIds[(row[1]! as String).trim().toLowerCase()] = row[0]! as int;
      }

      var categoriesCreated = 0;
      for (final name in plan.newCategories) {
        final key = name.trim().toLowerCase();
        if (categoryIds.containsKey(key)) continue;

        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_categories (restaurant_id, name_en, sort_order) '
            'VALUES (@r, @name, ('
            '  SELECT coalesce(max(sort_order), 0) + 1 FROM pos_categories '
            '   WHERE restaurant_id = @r)) '
            'RETURNING id',
          ),
          parameters: {'r': restaurantId, 'name': name.trim()},
        );
        categoryIds[key] = rows.first[0]! as int;
        categoriesCreated++;

        await _audit(
          tx,
          by: by,
          action: AuditAction.categoryCreated,
          entityType: AuditAction.entityCategory,
          entityId: '${categoryIds[key]}',
          after: {'name': name.trim(), 'source': 'import'},
        );
      }

      var created = 0;
      var updated = 0;

      for (final row in plan.rows) {
        if (row.action == MenuImportAction.unchanged) continue;

        final categoryId = categoryIds[row.categoryName.trim().toLowerCase()];
        // Cannot happen — the plan lists every category it names — but a null
        // here would become a constraint violation halfway through the file,
        // and "category missing on line 47" is a far better sentence.
        if (categoryId == null) {
          throw StateError(
            'Line ${row.lineNumber} names a category that could not be created.',
          );
        }

        if (row.action == MenuImportAction.create) {
          final inserted = await tx.execute(
            Sql.named(
              'INSERT INTO pos_products '
              '  (restaurant_id, category_id, name_en, name_ar, price_minor, '
              '   sku, barcode, is_available, sort_order) '
              'VALUES (@r, @category, @nameEn, @nameAr, @price, @sku, '
              '        @barcode, @available, ('
              '  SELECT coalesce(max(sort_order), 0) + 1 FROM pos_products '
              '   WHERE category_id = @category)) '
              'RETURNING id',
            ),
            parameters: {
              'r': restaurantId,
              'category': categoryId,
              'nameEn': row.nameEn,
              'nameAr': row.nameAr,
              'price': row.price.minor,
              'sku': row.sku,
              'barcode': row.barcode,
              'available': row.isAvailable,
            },
          );
          created++;

          await _audit(
            tx,
            by: by,
            action: AuditAction.productCreated,
            entityType: AuditAction.entityProduct,
            entityId: '${inserted.first[0]}',
            after: {
              'name': row.nameEn,
              'price_minor': row.price.minor,
              'source': 'import',
            },
          );
          continue;
        }

        // An update. `sort_order` and any discounted price are deliberately
        // untouched: the file said nothing about them, and an import that
        // silently reordered a grid or cleared an offer would be changing
        // things nobody asked it to.
        await tx.execute(
          Sql.named(
            'UPDATE pos_products SET category_id = @category, '
            '  name_en = @nameEn, name_ar = @nameAr, price_minor = @price, '
            '  barcode = @barcode, is_available = @available, '
            // Only ever filled in, never cleared: a file with no SKU column is
            // silent about SKUs, not an instruction to forget them.
            '  sku = coalesce(@sku, sku) '
            'WHERE id = @id AND restaurant_id = @r',
          ),
          parameters: {
            'id': row.existingProductId,
            'r': restaurantId,
            'category': categoryId,
            'nameEn': row.nameEn,
            'nameAr': row.nameAr,
            'price': row.price.minor,
            'sku': row.sku,
            'barcode': row.barcode,
            'available': row.isAvailable,
          },
        );
        updated++;

        await _audit(
          tx,
          by: by,
          // A changed price is its own action everywhere else in this file,
          // because "who changed what this costs, and when" is the question a
          // disputed receipt asks. A bulk import is no exception.
          action: row.changes.contains('price')
              ? AuditAction.productRepriced
              : AuditAction.productUpdated,
          entityType: AuditAction.entityProduct,
          entityId: '${row.existingProductId}',
          after: {
            'name': row.nameEn,
            'price_minor': row.price.minor,
            'changed': row.changes.join(', '),
            'source': 'import',
          },
        );
      }

      return AdminResult.done(
        MenuImportOutcome(
          categoriesCreated: categoriesCreated,
          productsCreated: created,
          productsUpdated: updated,
        ),
      );
    });
  }

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
            '   discounted_price_minor, sku, barcode, is_available, sort_order, '
            '   tax_group_id, is_stocked, stock_unit) '
            'VALUES (@r, @category, @nameEn, @nameAr, @price, @discounted, '
            '        @sku, @barcode, @available, @sort, @taxGroup, @stocked, '
            '        @stockUnit) '
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

      // The Menu pane is the second writer of `stock_unit`, so it asks the
      // same question the Items pane does. Without it, migration 44's trigger
      // would still refuse — as an exception on a price edit, not a sentence.
      final held = await StockUnitGuard.check(
        tx,
        restaurantId: restaurantId,
        productId: product.id,
        unit: product.stockUnit ?? QuantityUnit.each,
      );
      if (held != null) return AdminResult<Product>.refused(held);

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_products SET category_id = @category, name_en = @nameEn, '
          '  name_ar = @nameAr, price_minor = @price, '
          '  discounted_price_minor = @discounted, sku = @sku, '
          '  barcode = @barcode, is_available = @available, sort_order = @sort, '
          '  tax_group_id = @taxGroup, is_stocked = @stocked, '
          '  stock_unit = @stockUnit, '
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
  Future<AdminResult<TaxGroup>> saveTaxGroup(
    TaxGroup group, {
    required PosStaff by,
  }) async {
    final blocked = _blockedSettings(by);
    if (blocked != null) return AdminResult.refused(blocked);

    if (group.nameEn.trim().isEmpty) {
      return const AdminResult.refused(
        CatalogInvalid('A rate needs a name — it is what an accountant '
            'reconciles against.'),
      );
    }
    if (group.rateBp < 0 || group.rateBp > 10000) {
      return const AdminResult.refused(
        CatalogInvalid('A rate is between 0% and 100%.'),
      );
    }

    return database.runTx(config, (tx) async {
      // **One default, and the database holds it too** — a partial unique index
      // since Wave M. Cleared here rather than left to the constraint so the
      // manager gets a saved rate instead of a constraint violation: making a
      // second group the default means the first one stops being it.
      if (group.isDefault) {
        await tx.execute(
          Sql.named(
            'UPDATE pos_tax_groups SET is_default = false '
            'WHERE restaurant_id = @r AND is_default AND id <> @id',
          ),
          parameters: {'r': restaurantId, 'id': group.id},
        );
      }

      // Retiring the default would leave "what does an unclassified product
      // cost" with no answer, and every product that names no group is
      // unclassified.
      if (group.id != 0 && (!group.isActive || !group.isDefault)) {
        final wasDefault = await tx.execute(
          Sql.named(
            'SELECT is_default FROM pos_tax_groups '
            'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
          ),
          parameters: {'id': group.id, 'r': restaurantId},
        );
        if (wasDefault.isEmpty) {
          return const AdminResult<TaxGroup>.refused(EditedElsewhere(0));
        }
        if (wasDefault.first[0] == true && !group.isDefault) {
          return const AdminResult<TaxGroup>.refused(
            CatalogInvalid(
              'Something has to be the fallback rate. Make another group the '
              'default first.',
            ),
          );
        }
        if (wasDefault.first[0] == true && !group.isActive) {
          return const AdminResult<TaxGroup>.refused(
            CatalogInvalid(
              'The fallback rate cannot be retired. Make another group the '
              'default first.',
            ),
          );
        }
      }

      const columns = 'id, name_en, name_ar, rate_bp, is_default, is_active';
      final parameters = <String, Object?>{
        'r': restaurantId,
        'nameEn': group.nameEn.trim(),
        'nameAr': group.nameAr?.trim(),
        'rate': group.rateBp,
        'isDefault': group.isDefault,
        'active': group.isActive,
      };

      final rows = group.id == 0
          ? await tx.execute(
              Sql.named(
                'INSERT INTO pos_tax_groups (restaurant_id, name_en, name_ar, '
                '  rate_bp, is_default, is_active) '
                'VALUES (@r, @nameEn, @nameAr, @rate, @isDefault, @active) '
                'RETURNING $columns',
              ),
              parameters: parameters,
            )
          : await tx.execute(
              Sql.named(
                'UPDATE pos_tax_groups SET name_en = @nameEn, '
                '  name_ar = @nameAr, rate_bp = @rate, '
                '  is_default = @isDefault, is_active = @active '
                'WHERE id = @id AND restaurant_id = @r RETURNING $columns',
              ),
              parameters: {...parameters, 'id': group.id},
            );

      if (rows.isEmpty) {
        return const AdminResult<TaxGroup>.refused(EditedElsewhere(0));
      }

      await _audit(
        tx,
        by: by,
        action: AuditAction.taxGroupSaved,
        entityType: AuditAction.entityTaxGroup,
        entityId: '${rows.first[0]}',
        after: {
          'name': group.nameEn.trim(),
          // The figure a filing is reconciled against.
          'rate_bp': group.rateBp,
          'is_default': group.isDefault,
          'is_active': group.isActive,
        },
      );

      final row = rows.first;
      return AdminResult.done(
        TaxGroup(
          id: row[0]! as int,
          nameEn: row[1]! as String,
          nameAr: row[2] as String?,
          rateBp: row[3]! as int,
          isDefault: row[4]! as bool,
        ),
      );
    });
  }

  @override
  Future<AdminResult<OrderTypeConfig>> saveOrderType(
    OrderTypeConfig orderType, {
    required PosStaff by,
  }) async {
    final blocked = _blockedSettings(by);
    if (blocked != null) return AdminResult.refused(blocked);

    if (orderType.nameEn.trim().isEmpty) {
      return const AdminResult.refused(
        CatalogInvalid('An order type needs a name.'),
      );
    }

    return database.runTx(config, (tx) async {
      // A restaurant with no active order type has a till that cannot start a
      // ticket. Refused rather than warned, like the last cash tender method:
      // the fix afterwards is a database edit by somebody who will not know
      // that is what they are doing.
      if (!orderType.isActive) {
        final remaining = await tx.execute(
          Sql.named(
            'SELECT count(*) FROM pos_order_types '
            'WHERE restaurant_id = @r AND is_active AND code <> @code',
          ),
          parameters: {'r': restaurantId, 'code': orderType.type.wire},
        );
        if ((remaining.first[0]! as int) == 0) {
          return const AdminResult<OrderTypeConfig>.refused(
            CatalogInvalid(
              'Something has to be sellable. This is the last order type left '
              'on.',
            ),
          );
        }
      }

      // **Upsert on the code, not on an id.** The four rows are seeded, so a
      // restaurant whose seed predates a column edits a row this build has
      // never inserted — and `OrderTypeConfig` carries no id, because the code
      // is the identity.
      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_order_types (restaurant_id, code, name_en, name_ar, '
          '  requires_table, requires_customer, requires_address, is_active, '
          '  sort_order) '
          'VALUES (@r, @code, @nameEn, @nameAr, @table, @customer, @address, '
          '        @active, @sort) '
          'ON CONFLICT (restaurant_id, code) DO UPDATE SET '
          '  name_en = EXCLUDED.name_en, name_ar = EXCLUDED.name_ar, '
          '  requires_table = EXCLUDED.requires_table, '
          '  requires_customer = EXCLUDED.requires_customer, '
          '  requires_address = EXCLUDED.requires_address, '
          '  is_active = EXCLUDED.is_active, sort_order = EXCLUDED.sort_order '
          'RETURNING id',
        ),
        parameters: {
          'r': restaurantId,
          'code': orderType.type.wire,
          'nameEn': orderType.nameEn.trim(),
          'nameAr': orderType.nameAr?.trim(),
          'table': orderType.requiresTable,
          'customer': orderType.requiresCustomer,
          'address': orderType.requiresAddress,
          'active': orderType.isActive,
          'sort': orderType.sortOrder,
        },
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.orderTypeSaved,
        entityType: AuditAction.entityOrderType,
        entityId: '${rows.first[0]}',
        after: {
          'code': orderType.type.wire,
          'name': orderType.nameEn.trim(),
          // The two with consequences beyond a label: one decides whether the
          // floor plan is offered, the other whether the type can be sold.
          'requires_table': orderType.requiresTable,
          'is_active': orderType.isActive,
        },
      );

      return AdminResult.done(orderType);
    });
  }

  @override
  Future<AdminResult<TenderMethod>> saveTenderType(
    TenderMethod method, {
    required PosStaff by,
  }) async {
    final blocked = _blockedSettings(by);
    if (blocked != null) return AdminResult.refused(blocked);

    if (method.nameEn.trim().isEmpty) {
      return const AdminResult.refused(
        CatalogInvalid('A payment method needs a name.'),
      );
    }
    if (method.code.trim().isEmpty) {
      return const AdminResult.refused(
        CatalogInvalid('A payment method needs a code.'),
      );
    }

    return database.runTx(config, (tx) async {
      // A restaurant that retires its last cash method has a till that cannot
      // put anything in the drawer, and a cash-up that will read zero for the
      // rest of time. Refused rather than warned: the fix afterwards is a
      // database edit, and the person who did it will not know that is what
      // they did.
      if (!method.isActive || !method.countsAsCash) {
        final remaining = await tx.execute(
          Sql.named(
            'SELECT count(*) FROM pos_tender_types '
            'WHERE restaurant_id = @r AND is_active AND counts_as_cash '
            '  AND id <> @id',
          ),
          parameters: {'r': restaurantId, 'id': method.id},
        );
        if ((remaining.first[0]! as int) == 0) {
          return const AdminResult<TenderMethod>.refused(
            CatalogInvalid(
              'Something has to count as cash, or the drawer can never be '
              'counted.',
            ),
          );
        }
      }

      // `id` is added only for the UPDATE: `Sql.named` refuses a parameter the
      // statement does not use, and the INSERT does not name one.
      final parameters = <String, Object?>{
        'r': restaurantId,
        'code': method.code.trim(),
        'nameEn': method.nameEn.trim(),
        'nameAr': method.nameAr?.trim(),
        'kind': method.kind.wire,
        'cash': method.countsAsCash,
        'drawer': method.opensDrawer,
        'reference': method.requiresReference,
        'refund': method.refundAllowed,
        'active': method.isActive,
        'sort': method.sortOrder,
      };

      const columns =
          'id, code, name_en, name_ar, kind, counts_as_cash, opens_drawer, '
          'requires_reference, refund_allowed, is_active, sort_order';

      final rows = method.id == 0
          ? await tx.execute(
              Sql.named(
                'INSERT INTO pos_tender_types (restaurant_id, code, name_en, '
                '  name_ar, kind, counts_as_cash, opens_drawer, '
                '  requires_reference, refund_allowed, is_active, sort_order) '
                'VALUES (@r, @code, @nameEn, @nameAr, @kind, @cash, @drawer, '
                '        @reference, @refund, @active, @sort) '
                'RETURNING $columns',
              ),
              parameters: parameters,
            )
          : await tx.execute(
              Sql.named(
                'UPDATE pos_tender_types SET code = @code, name_en = @nameEn, '
                '  name_ar = @nameAr, kind = @kind, counts_as_cash = @cash, '
                '  opens_drawer = @drawer, requires_reference = @reference, '
                '  refund_allowed = @refund, is_active = @active, '
                '  sort_order = @sort '
                'WHERE id = @id AND restaurant_id = @r RETURNING $columns',
              ),
              parameters: {...parameters, 'id': method.id},
            );

      if (rows.isEmpty) {
        return const AdminResult<TenderMethod>.refused(EditedElsewhere(0));
      }

      await _audit(
        tx,
        by: by,
        action: AuditAction.tenderTypeSaved,
        entityType: AuditAction.entityTenderType,
        entityId: '${rows.first[0]}',
        after: {
          'code': method.code.trim(),
          'name': method.nameEn.trim(),
          // The field worth being able to find later: changing it changes what
          // every future cash-up expects to be in the drawer.
          'counts_as_cash': method.countsAsCash,
          'is_active': method.isActive,
        },
      );

      final row = rows.first;
      return AdminResult.done(
        TenderMethod(
          id: row[0]! as int,
          code: row[1]! as String,
          nameEn: row[2]! as String,
          nameAr: row[3] as String?,
          kind: TenderKind.fromWire(row[4] as String?),
          countsAsCash: row[5]! as bool,
          opensDrawer: row[6]! as bool,
          requiresReference: row[7]! as bool,
          refundAllowed: row[8]! as bool,
          isActive: row[9]! as bool,
          sortOrder: row[10]! as int,
        ),
      );
    });
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
    // **Written for the first time here.** The column has existed since Wave M
    // and the catalogue query has read it since — `COALESCE(p.tax_group_id,
    // c.tax_group_id)` — but no statement in the app ever set it, so a
    // restaurant could define a zero-rated group and had no way to put anything
    // on it. Null means "whatever the category says, or the fallback rate".
    'taxGroup': product.taxGroupId,
    // Written with the rest, so saving a menu item never quietly stops it
    // being counted.
    'stocked': product.isStocked,
    'stockUnit': product.stockUnit?.wire,
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
    taxGroupId: row[11] as int?,
    isStocked: row[12]! as bool,
    stockUnit: row[13] == null ? null : QuantityUnit.fromWire(row[13] as String),
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
