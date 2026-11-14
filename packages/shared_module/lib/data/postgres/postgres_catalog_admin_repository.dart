import 'dart:convert';

import '../sql/sql.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/content_languages.dart';
import '../../domain/models/combo_draft.dart';
import '../../domain/models/option_group.dart';
import '../../domain/models/tax.dart';
import '../../domain/models/order_type_config.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/models/tender_method.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/menu_import.dart';
import '../../domain/services/table_batch.dart';
import '../../domain/services/authorization.dart';
import 'money_config_codec.dart';
import 'stock_unit_guard.dart';
import '../sql/row_reads.dart';

/// A group as stored, and which side of the library line it is on — which
/// the draft does not carry, because the editor knows it from where it
/// opened the group.
typedef _Stored = ({OptionGroupDraft group, bool isGlobal});

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
    required this.businessId,
    this.branchId,
    this.terminalId,
    this.adminAvailable = true,
    this.offline = true,
  });

  final SqlDatabase database;
  final DeploymentConfig config;
  final int businessId;
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
        CatalogRefused(CatalogProblem.categoryNameMissing),
      );
    }

    return database.runTx(config, (tx) async {
      if (category.id == 0) {
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_categories '
            '  (business_id, name_en, name_ar, slug, sort_order, is_active) '
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
          'WHERE id = @id AND business_id = @r FOR UPDATE',
        ),
        parameters: {'id': category.id, 'r': businessId},
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
          'WHERE id = @id AND business_id = @r '
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
          'WHERE id = @id AND business_id = @r '
          'RETURNING $_categoryColumns',
        ),
        parameters: {'id': category.id, 'r': businessId, 'active': restore},
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

  @override
  Future<List<Category>> inactiveCategories() async {
    final rows = await database.query(
      config,
      'SELECT $_categoryColumns FROM pos_categories '
      'WHERE business_id = @r AND NOT is_active '
      'ORDER BY sort_order, id',
      parameters: {'r': businessId},
    );
    return [for (final row in rows) _categoryFrom(row)];
  }

  @override
  Future<AdminResult<void>> deleteCategory(
    Category category, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult<void>.refused(blocked);

    return database.runTx(config, (tx) async {
      final existing = await tx.execute(
        Sql.named(
          'SELECT $_categoryColumns FROM pos_categories '
          'WHERE id = @id AND business_id = @r FOR UPDATE',
        ),
        parameters: {'id': category.id, 'r': businessId},
      );
      if (existing.isEmpty) {
        return const AdminResult<void>.refused(EditedElsewhere(0));
      }
      final stored = _categoryFrom(existing.first);

      // Counted inside the lock, archived items included: they are still rows
      // the foreign key protects, and a sale may name them.
      final held = await tx.execute(
        Sql.named(
          'SELECT (SELECT count(*) FROM pos_products WHERE category_id = @id) '
          '     + (SELECT count(*) FROM pos_combos WHERE category_id = @id)',
        ),
        parameters: {'id': category.id},
      );
      if ((held.first[0]! as int) > 0) {
        return const AdminResult<void>.refused(
          CatalogRefused(CatalogProblem.categoryHasItems),
        );
      }

      // Its links to option groups cascade; nothing else points at it.
      await tx.execute(
        Sql.named(
          'DELETE FROM pos_categories WHERE id = @id AND business_id = @r',
        ),
        parameters: {'id': category.id, 'r': businessId},
      );
      await _audit(
        tx,
        by: by,
        action: AuditAction.categoryDeleted,
        entityType: AuditAction.entityCategory,
        entityId: '${stored.id}',
        before: {'name': stored.nameEn, 'slug': stored.slug},
      );
      return const AdminResult<void>.done(null);
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
          'SELECT id, name_en FROM pos_categories WHERE business_id = @r',
        ),
        parameters: {'r': businessId},
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
            'INSERT INTO pos_categories (business_id, name_en, sort_order) '
            'VALUES (@r, @name, ('
            '  SELECT coalesce(max(sort_order), 0) + 1 FROM pos_categories '
            '   WHERE business_id = @r)) '
            'RETURNING id',
          ),
          parameters: {'r': businessId, 'name': name.trim()},
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
              '  (business_id, category_id, name_en, name_ar, price_minor, '
              '   sku, barcode, is_available, sort_order) '
              'VALUES (@r, @category, @nameEn, @nameAr, @price, @sku, '
              '        @barcode, @available, ('
              '  SELECT coalesce(max(sort_order), 0) + 1 FROM pos_products '
              '   WHERE category_id = @category)) '
              'RETURNING id',
            ),
            parameters: {
              'r': businessId,
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
            'WHERE id = @id AND business_id = @r',
          ),
          parameters: {
            'id': row.existingProductId,
            'r': businessId,
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
      return const AdminResult.refused(
        CatalogRefused(CatalogProblem.itemNameMissing),
      );
    }
    // The database checks both prices are non-negative. It does NOT check that
    // a discount is below the full price — nothing stops `discounted > price`
    // in SQL — so it is checked here, where it can be explained.
    final discounted = product.discountedPrice;
    if (discounted != null && discounted.minor > product.price.minor) {
      return const AdminResult.refused(
        CatalogRefused(CatalogProblem.offerAbovePrice),
      );
    }

    return database.runTx(config, (tx) async {
      // SKUs are unique per business (`pos_products_sku_unique`). Asked here,
      // in the transaction, so a clash is a sentence in the editor and not the
      // database's unique-violation exception reaching the dialog. A blank SKU
      // means "none" and never clashes. The index stays the backstop for two
      // tills saving the same SKU at the same moment.
      final sku = product.sku?.trim() ?? '';
      if (sku.isNotEmpty) {
        final clash = await tx.execute(
          Sql.named(
            'SELECT 1 FROM pos_products '
            'WHERE business_id = @r AND sku = @sku AND id <> @id LIMIT 1',
          ),
          parameters: {'r': businessId, 'sku': sku, 'id': product.id},
        );
        if (clash.isNotEmpty) {
          return const AdminResult<Product>.refused(
            CatalogRefused(CatalogProblem.skuTaken),
          );
        }
      }

      // The foreign key proves the category exists, not that it is ours or in
      // use. Asked here, in the transaction, for the same reason as the SKU.
      final unavailable = await _categoryUnavailable(tx, product);
      if (unavailable != null) return AdminResult<Product>.refused(unavailable);

      if (product.id == 0) {
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_products '
            '  (business_id, category_id, name_en, name_ar, price_minor, '
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
          'WHERE id = @id AND business_id = @r FOR UPDATE',
        ),
        parameters: {'id': product.id, 'r': businessId},
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
        businessId: businessId,
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
          'WHERE id = @id AND business_id = @r '
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
          'WHERE id = @id AND business_id = @r '
          'RETURNING $_productColumns',
        ),
        parameters: {'id': product.id, 'r': businessId, 'available': restore},
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
    // The default group holds the same figure below, and its table refuses
    // anything over 100% — say so here rather than as a constraint error.
    if (config.vatBp > 10000) {
      return const AdminResult.refused(
        CatalogInvalid('A rate is between 0% and 100%.'),
      );
    }

    return database.runTx(this.config, (tx) async {
      final existing = await tx.execute(
        Sql.named(
          'SELECT payload FROM pos_money_config WHERE business_id = @r',
        ),
        parameters: {'r': businessId},
      );
      // The rate the ticket actually charges, which is the default group's
      // whenever one exists — see `TaxConfig.defaultTaxGroup`.
      final groupBefore = await tx.execute(
        Sql.named(
          'SELECT rate_bp FROM pos_tax_groups '
          'WHERE business_id = @r AND is_default FOR UPDATE',
        ),
        parameters: {'r': businessId},
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
          'INSERT INTO pos_money_config (business_id, payload, synced_at) '
          'VALUES (@r, @payload::jsonb, now()) '
          'ON CONFLICT (business_id) DO UPDATE '
          '  SET payload = @payload::jsonb, synced_at = now()',
        ),
        parameters: {'r': businessId, 'payload': payload},
      );

      // **The VAT box has to move the rate the till charges.** Once a default
      // tax group exists (every offline setup seeds one at 14%) the ticket
      // prices from it and never reads `vat_bp`, so saving only the payload
      // left a business that typed 0 still charging 14%. One default group
      // per business is a unique index, so this is one row or none.
      final groupAfter = await tx.execute(
        Sql.named(
          'UPDATE pos_tax_groups SET rate_bp = @vat '
          'WHERE business_id = @r AND is_default RETURNING rate_bp',
        ),
        parameters: {'r': businessId, 'vat': config.vatBp},
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.moneyConfigChanged,
        entityType: AuditAction.entityMoney,
        entityId: '$businessId',
        before: before == null && groupBefore.isEmpty
            ? null
            : {
                if (before != null) ...{
                  'service_bp': before.serviceBp,
                  'vat_bp': before.vatBp,
                },
                if (groupBefore.isNotEmpty)
                  'default_group_rate_bp': groupBefore.first[0],
              },
        after: {
          'service_bp': config.serviceBp,
          'vat_bp': config.vatBp,
          if (groupAfter.isNotEmpty)
            'default_group_rate_bp': groupAfter.first[0],
        },
      );

      // Read back through the codec, so what is returned is what the ticket
      // will actually price with rather than what was asked for.
      return AdminResult.done(
        MoneyConfigCodec.toTaxConfig(MoneyConfigCodec.fromTaxConfig(config)),
      );
    });
  }

  // ── the floor ──────────────────────────────────────────────────────────────

  static const _tableColumns =
      'id, label, seats, area_name, is_active, sort_order';

  /// The floor plan is the ROOM, not the menu, so it answers to
  /// `settings.manage` like the money rules do.
  @override
  Future<AdminResult<ContentLanguages>> saveContentLanguages(
    ContentLanguages languages, {
    required PosStaff by,
  }) async {
    final blocked = _blockedSettings(by);
    if (blocked != null) return AdminResult.refused(blocked);

    return database.runTx(config, (tx) async {
      final before = await tx.execute(
        Sql.named(
          'SELECT content_languages FROM pos_businesses WHERE id = @r',
        ),
        parameters: {'r': businessId},
      );
      if (before.isEmpty) {
        return const AdminResult<ContentLanguages>.refused(
          CatalogInvalid('This business is not set up on this till yet.'),
        );
      }
      final was = before.first[0] as String?;
      if (was == languages.wire) return AdminResult.done(languages);

      await tx.execute(
        Sql.named(
          'UPDATE pos_businesses SET content_languages = @value WHERE id = @r',
        ),
        parameters: {'r': businessId, 'value': languages.wire},
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.contentLanguagesSaved,
        entityType: AuditAction.entityContentLanguages,
        entityId: '$businessId',
        before: {'content_languages': was},
        after: {'content_languages': languages.wire},
      );

      return AdminResult.done(languages);
    });
  }

  /// The same door as [_blockedSettings] with the order-types key (XORD-002).
  AdminRefusal? _blockedOrderTypes(PosStaff by) {
    if (!offline) return const NotPermitted(PosCapability.orderTypesManage);
    if (!adminAvailable) return const AdministratorCredentialRequired();
    if (!Authorization.check(by, PosCapability.orderTypesManage).isAllowed) {
      return const NotPermitted(PosCapability.orderTypesManage);
    }
    return null;
  }

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
            'WHERE business_id = @r AND is_default AND id <> @id',
          ),
          parameters: {'r': businessId, 'id': group.id},
        );
      }

      // Retiring the default would leave "what does an unclassified product
      // cost" with no answer, and every product that names no group is
      // unclassified.
      if (group.id != 0 && (!group.isActive || !group.isDefault)) {
        final wasDefault = await tx.execute(
          Sql.named(
            'SELECT is_default FROM pos_tax_groups '
            'WHERE id = @id AND business_id = @r FOR UPDATE',
          ),
          parameters: {'id': group.id, 'r': businessId},
        );
        if (wasDefault.isEmpty) {
          return const AdminResult<TaxGroup>.refused(EditedElsewhere(0));
        }
        if (readBool(wasDefault.first[0]) == true && !group.isDefault) {
          return const AdminResult<TaxGroup>.refused(
            CatalogInvalid(
              'Something has to be the fallback rate. Make another group the '
              'default first.',
            ),
          );
        }
        if (readBool(wasDefault.first[0]) == true && !group.isActive) {
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
        'r': businessId,
        'nameEn': group.nameEn.trim(),
        'nameAr': group.nameAr?.trim(),
        'rate': group.rateBp,
        'isDefault': group.isDefault,
        'active': group.isActive,
      };

      final rows = group.id == 0
          ? await tx.execute(
              Sql.named(
                'INSERT INTO pos_tax_groups (business_id, name_en, name_ar, '
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
                'WHERE id = @id AND business_id = @r RETURNING $columns',
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
          isDefault: row.boolean(4),
        ),
      );
    });
  }

  @override
  Future<AdminResult<OrderTypeConfig>> saveOrderType(
    OrderTypeConfig orderType, {
    required PosStaff by,
    Set<OrderType>? entitled,
  }) async {
    // Its own key since XORD-002: it used to be `settings.manage`.
    final blocked = _blockedOrderTypes(by);
    if (blocked != null) return AdminResult.refused(blocked);

    if (orderType.nameEn.trim().isEmpty) {
      return const AdminResult.refused(
        CatalogInvalid('An order type needs a name.'),
      );
    }

    return database.runTx(config, (tx) async {
      // Only what the licence includes can be switched ON. Switching OFF is
      // always allowed (the last-one rule below aside), so a type the licence
      // no longer covers can still be taken down.
      if (orderType.isActive &&
          entitled != null &&
          !entitled.contains(orderType.type)) {
        final already = await tx.execute(
          Sql.named(
            'SELECT is_active FROM pos_order_types '
            'WHERE business_id = @r AND code = @code',
          ),
          parameters: {'r': businessId, 'code': orderType.type.wire},
        );
        final wasOn = already.isNotEmpty && readBool(already.first[0]) == true;
        if (!wasOn) {
          return const AdminResult<OrderTypeConfig>.refused(
            CatalogInvalid('This order type is not included in the licence.'),
          );
        }
      }

      // A business with no active order type has a till that cannot start a
      // ticket. Refused rather than warned, like the last cash tender method:
      // the fix afterwards is a database edit by somebody who will not know
      // that is what they are doing.
      if (!orderType.isActive) {
        final remaining = await tx.execute(
          Sql.named(
            'SELECT count(*) FROM pos_order_types '
            'WHERE business_id = @r AND is_active AND code <> @code',
          ),
          parameters: {'r': businessId, 'code': orderType.type.wire},
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
      // business whose seed predates a column edits a row this build has
      // never inserted — and `OrderTypeConfig` carries no id, because the code
      // is the identity.
      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_order_types (business_id, code, name_en, name_ar, '
          '  requires_table, requires_customer, requires_address, is_active, '
          '  sort_order) '
          'VALUES (@r, @code, @nameEn, @nameAr, @table, @customer, @address, '
          '        @active, @sort) '
          'ON CONFLICT (business_id, code) DO UPDATE SET '
          '  name_en = EXCLUDED.name_en, name_ar = EXCLUDED.name_ar, '
          '  requires_table = EXCLUDED.requires_table, '
          '  requires_customer = EXCLUDED.requires_customer, '
          '  requires_address = EXCLUDED.requires_address, '
          '  is_active = EXCLUDED.is_active, sort_order = EXCLUDED.sort_order '
          'RETURNING id',
        ),
        parameters: {
          'r': businessId,
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
      // A business that retires its last cash method has a till that cannot
      // put anything in the drawer, and a cash-up that will read zero for the
      // rest of time. Refused rather than warned: the fix afterwards is a
      // database edit, and the person who did it will not know that is what
      // they did.
      if (!method.isActive || !method.countsAsCash) {
        final remaining = await tx.execute(
          Sql.named(
            'SELECT count(*) FROM pos_tender_types '
            'WHERE business_id = @r AND is_active AND counts_as_cash '
            '  AND id <> @id',
          ),
          parameters: {'r': businessId, 'id': method.id},
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
        'r': businessId,
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
                'INSERT INTO pos_tender_types (business_id, code, name_en, '
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
                'WHERE id = @id AND business_id = @r RETURNING $columns',
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
          countsAsCash: row.boolean(5),
          opensDrawer: row.boolean(6),
          requiresReference: row.boolean(7),
          refundAllowed: row.boolean(8),
          isActive: row.boolean(9),
          sortOrder: row[10]! as int,
        ),
      );
    });
  }

  @override
  Future<AdminResult<List<DiningTable>>> createTables(
    List<DiningTable> tables, {
    required PosStaff by,
  }) async {
    final blocked = _blockedSettings(by);
    if (blocked != null) return AdminResult.refused(blocked);

    if (tables.isEmpty || tables.length > TableBatch.maxQuantity) {
      return const AdminResult.refused(
        CatalogInvalid('Add between 1 and 100 tables at a time.'),
      );
    }
    final labels = [for (final t in tables) t.label.trim()];
    if (labels.any((l) => l.isEmpty)) {
      return const AdminResult.refused(
        CatalogInvalid('A table needs a label.'),
      );
    }
    if (tables.any((t) => t.seats != null && t.seats! < 1)) {
      return const AdminResult.refused(
        CatalogInvalid('A table seats at least one person.'),
      );
    }
    if (labels.toSet().length != labels.length) {
      return const AdminResult.refused(
        CatalogInvalid('Two of these tables would have the same name.'),
      );
    }
    final branch = branchId;
    if (branch == null) {
      return const AdminResult.refused(EditedElsewhere(0));
    }

    return database.runTx(config, (tx) async {
      // The unique key is `(branch_id, label)`, and it counts tables that are
      // out of service too, so this reads every row of the branch.
      final clash = await tx.execute(
        Sql.named(
          'SELECT label FROM pos_dining_tables '
          'WHERE branch_id = @branch AND label = ANY(@labels) ORDER BY label',
        ),
        parameters: {'branch': branch, 'labels': labels},
      );
      if (clash.isNotEmpty) {
        final names = [for (final row in clash.take(5)) '"${row[0]}"'];
        return AdminResult<List<DiningTable>>.refused(
          CatalogInvalid(
            'This branch already has ${names.join(', ')}'
            '${clash.length > 5 ? ' and ${clash.length - 5} more' : ''}. '
            'Nothing was added.',
          ),
        );
      }

      final created = <DiningTable>[];
      for (var i = 0; i < tables.length; i++) {
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_dining_tables '
            '  (business_id, branch_id, label, seats, area_name) '
            'VALUES (@r, @branch, @label, @seats, @area) '
            'RETURNING $_tableColumns',
          ),
          parameters: {
            'r': businessId,
            'branch': branch,
            'label': labels[i],
            'seats': tables[i].seats,
            'area': _orNull(tables[i].areaName),
          },
        );
        final table = _tableFrom(rows.first);
        created.add(table);
        await _audit(
          tx,
          by: by,
          action: AuditAction.tableCreated,
          entityType: AuditAction.entityTable,
          entityId: '${table.id}',
          after: {
            'label': table.label,
            'seats': table.seats,
            'batch': tables.length,
          },
        );
      }
      return AdminResult.done(created);
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
    if (table.seats != null && table.seats! < 1) {
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
        'r': businessId,
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

        // A new table goes to the END of the floor, not to position 0 in
        // front of everything: `sort_order` is the manager's layout, and an
        // insert must not silently rearrange it.
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_dining_tables '
            '  (business_id, branch_id, label, seats, area_name, sort_order) '
            'VALUES (@r, @branch, @label, @seats, @area, '
            '  (SELECT coalesce(max(sort_order), 0) + 1 FROM pos_dining_tables '
            '   WHERE branch_id = @branch)) '
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
          'WHERE id = @id AND business_id = @r FOR UPDATE',
        ),
        parameters: {'id': table.id, 'r': businessId},
      );
      if (existing.isEmpty) {
        return const AdminResult<DiningTable>.refused(EditedElsewhere(0));
      }
      final before = _tableFrom(existing.first);

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_dining_tables SET label = @label, seats = @seats, '
          '  area_name = @area '
          'WHERE id = @id AND business_id = @r '
          'RETURNING $_tableColumns',
        ),
        // `branch` is for the INSERT only; the driver refuses a named
        // parameter the statement does not use, which made every edit of an
        // existing table fail.
        parameters: {...parameters, 'id': table.id}..remove('branch'),
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
          'WHERE id = @id AND business_id = @r '
          'RETURNING $_tableColumns',
        ),
        parameters: {'id': table.id, 'r': businessId, 'active': restore},
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

  @override
  Future<AdminResult<void>> reorderTables(
    List<int> tableIdsInOrder, {
    required PosStaff by,
  }) async {
    final blocked = _blockedSettings(by);
    if (blocked != null) return AdminResult<void>.refused(blocked);
    final branch = branchId;
    if (branch == null) {
      return const AdminResult<void>.refused(EditedElsewhere(0));
    }
    if (tableIdsInOrder.isEmpty) return const AdminResult<void>.done(null);

    return database.runTx(config, (tx) async {
      // One UPDATE over the whole list rather than a statement per table:
      // the layout is one fact, and a failure halfway would leave the floor
      // in an order nobody chose. Tables not in the list keep their place —
      // the pane reorders within a section, and the other sections' numbers
      // are not its business.
      await tx.execute(
        Sql.named(
          'UPDATE pos_dining_tables AS t '
          'SET sort_order = v.ord '
          'FROM unnest(@ids::bigint[], @ords::int[]) AS v(id, ord) '
          'WHERE t.id = v.id AND t.restaurant_id = @r AND t.branch_id = @branch',
        ),
        parameters: {
          'ids': tableIdsInOrder,
          'ords': [for (var i = 0; i < tableIdsInOrder.length; i++) i + 1],
          'r': businessId,
          'branch': branch,
        },
      );
      await _audit(
        tx,
        by: by,
        action: AuditAction.tableUpdated,
        entityType: AuditAction.entityTable,
        entityId: 'floor',
        after: {'order': tableIdsInOrder},
      );
      return const AdminResult<void>.done(null);
    });
  }

  DiningTable _tableFrom(ResultRow row) => DiningTable(
    id: row[0]! as int,
    label: row[1]! as String,
    seats: row[2] as int?,
    areaName: row[3] as String?,
    sortOrder: row[5] as int? ?? 0,
  );

  @override
  Future<AdminResult<void>> attachModifierGroups(
    int productId,
    List<int> groupIds, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult<void>.refused(blocked);

    // **Routed through [setProductOptionGroups] rather than kept as a second
    // writer of the same links.** It used to link whatever it was given, which
    // since migration 45 includes a group typed on another item (quietly
    // sharing it) and a second set of sizes. The item's own groups travel
    // whole, so naming one here keeps it exactly as it is; duplicates
    // collapse, as the old `ON CONFLICT DO NOTHING` collapsed them.
    final own = {
      for (final ref in await productOptionGroups(productId))
        if (ref case InlineGroupRef(:final group)) group.id: group,
    };
    final result = await setProductOptionGroups(
      productId,
      [
        for (final id in {...groupIds})
          if (own[id] case final group?)
            OptionGroupRef.inline(group)
          else
            OptionGroupRef.shared(id),
      ],
      by: by,
    );
    final refusal = result.refusal;
    return refusal == null
        ? const AdminResult<void>.done(null)
        : AdminResult<void>.refused(refusal);
  }

  // ── sizes and extras ───────────────────────────────────────────────────────
  //
  // The platform's option groups, authored here with two of its behaviours
  // left out on purpose — each explained where it is held:
  //
  //  * it recreates a group's options on every save, which reissues their ids
  //    (see [_writeGroup]);
  //  * it lets an item carry two size groups and then honours only the first
  //    (see [setProductOptionGroups] and [_secondSizeFor]).

  static const _twice = OptionGroupRefused(OptionGroupProblem.groupTwice);

  @override
  Future<List<LibraryGroup>> optionLibrary() => database.runTx(config, (
    tx,
  ) async {
    final groups = await _groups(
      tx,
      where: 'g.is_global',
      orderBy: 'g.name_en, g.name_ar, g.id',
    );
    if (groups.isEmpty) return const <LibraryGroup>[];

    // By reach, not by link — see [LibraryGroup.itemCount].
    final counts = await tx.execute(
      Sql.named(
        'SELECT g.id, CASE g.apply_scope '
        "  WHEN 'all' THEN (SELECT count(*) FROM pos_products p "
        '                    WHERE p.business_id = g.business_id) '
        "  WHEN 'categories' THEN (SELECT count(*) FROM pos_products p "
        '    JOIN pos_modifier_group_categories c '
        '      ON c.category_id = p.category_id AND c.group_id = g.id) '
        '  ELSE (SELECT count(*) FROM pos_product_modifier_groups l '
        '         WHERE l.group_id = g.id) END '
        'FROM pos_modifier_groups g '
        'WHERE g.business_id = @r AND g.is_global',
      ),
      parameters: {'r': businessId},
    );
    final reach = {for (final row in counts) row[0]! as int: row[1]! as int};

    return [
      for (final stored in groups)
        LibraryGroup(
          group: stored.group,
          itemCount: reach[stored.group.id] ?? 0,
        ),
    ];
  });

  @override
  Future<List<OptionGroupRef>> productOptionGroups(int productId) =>
      database.runTx(config, (tx) => _productRefs(tx, productId));

  @override
  Future<AdminResult<OptionGroupDraft>> saveOptionGroup(
    OptionGroupDraft draft, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    final group = draft.normalized();
    final invalid = OptionGroupRules.refusal(group, inLibrary: true);
    if (invalid != null) {
      return AdminResult.refused(OptionGroupRefused(invalid));
    }

    return database.runTx(config, (tx) async {
      OptionGroupDraft? before;
      if (group.id != 0) {
        final (stored, refusal) = await _lockForEdit(
          tx,
          id: group.id,
          revision: group.revision,
          global: true,
        );
        if (refusal != null) {
          return AdminResult<OptionGroupDraft>.refused(refusal);
        }
        before = stored!.group;
      }

      final refusal =
          _foreignOption(group, before) ??
          await _categoriesAreOurs(tx, group.categoryIds);
      if (refusal != null) {
        return AdminResult<OptionGroupDraft>.refused(refusal);
      }

      final clash = await _secondSizeFor(tx, group);
      if (clash != null) {
        return AdminResult<OptionGroupDraft>.refused(
          OptionGroupRefused(
            OptionGroupProblem.wouldGiveSecondSizes,
            names: [clash],
          ),
        );
      }

      return AdminResult.done(
        await _writeGroup(tx, group, global: true, by: by, before: before),
      );
    });
  }

  @override
  Future<AdminResult<void>> deleteOptionGroup(
    OptionGroupDraft group, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult<void>.refused(blocked);

    return database.runTx(config, (tx) async {
      final (stored, refusal) = await _lockForEdit(
        tx,
        id: group.id,
        revision: group.revision,
        global: true,
      );
      if (refusal != null) return AdminResult<void>.refused(refusal);

      // Options, item links and category links cascade. No sale loses its
      // record: an order line keeps its own summary of what was chosen.
      await tx.execute(
        Sql.named(
          'DELETE FROM pos_modifier_groups WHERE id = @id AND business_id = @r',
        ),
        parameters: {'id': group.id, 'r': businessId},
      );
      await _audit(
        tx,
        by: by,
        action: AuditAction.optionGroupDeleted,
        entityType: AuditAction.entityOptionGroup,
        entityId: '${group.id}',
        before: _groupSummary(stored!.group, shared: true),
      );
      return const AdminResult<void>.done(null);
    });
  }

  @override
  Future<AdminResult<List<OptionGroupRef>>> setProductOptionGroups(
    int productId,
    List<OptionGroupRef> groups, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    // Everything that needs no database is settled before the transaction
    // opens, and everything that does is settled before the first write — a
    // refusal found halfway through would have to unwind what came before it,
    // and returning one from inside `runTx` commits instead.
    final refs = <OptionGroupRef>[];
    final sharedIds = <int>[];
    final inlineIds = <int>{};
    for (final ref in groups) {
      switch (ref) {
        case SharedGroupRef(:final groupId):
          if (sharedIds.contains(groupId)) return const AdminResult.refused(_twice);
          sharedIds.add(groupId);
          refs.add(ref);
        case InlineGroupRef(:final group):
          final normalized = group.normalized();
          final invalid = OptionGroupRules.refusal(normalized, inLibrary: false);
          if (invalid != null) {
            return AdminResult.refused(OptionGroupRefused(invalid));
          }
          if (normalized.id != 0 && !inlineIds.add(normalized.id)) {
            return const AdminResult.refused(_twice);
          }
          refs.add(OptionGroupRef.inline(normalized));
      }
    }

    return database.runTx(config, (tx) async {
      // Locked, so two tills arranging one item's groups queue rather than
      // interleave their deletes and inserts.
      final product = await tx.execute(
        Sql.named(
          'SELECT category_id FROM pos_products '
          'WHERE id = @id AND business_id = @r FOR UPDATE',
        ),
        parameters: {'id': productId, 'r': businessId},
      );
      if (product.isEmpty) {
        return const AdminResult<List<OptionGroupRef>>.refused(
          EditedElsewhere(0),
        );
      }
      final categoryId = product.first[0]! as int;

      final before = await _productRefs(tx, productId);
      final ownBefore = <int, OptionGroupDraft>{
        for (final ref in before)
          if (ref case InlineGroupRef(:final group)) group.id: group,
      };

      // The item's own groups being edited: still here, still its own, and
      // unchanged since they were read.
      final storedInline = <int, OptionGroupDraft>{};
      final sizes = <String>[];
      for (final ref in refs) {
        if (ref is! InlineGroupRef) continue;
        final group = ref.group;
        if (group.isVariant) sizes.add(group.nameEn);

        if (group.id == 0) {
          final foreign = _foreignOption(group, null);
          if (foreign != null) {
            return AdminResult<List<OptionGroupRef>>.refused(foreign);
          }
          continue;
        }
        final (stored, refusal) = await _lockForEdit(
          tx,
          id: group.id,
          revision: group.revision,
          global: false,
        );
        if (refusal != null) {
          return AdminResult<List<OptionGroupRef>>.refused(refusal);
        }
        if (!ownBefore.containsKey(group.id)) {
          return const AdminResult<List<OptionGroupRef>>.refused(
            OptionGroupRefused(OptionGroupProblem.typedOnAnotherItem),
          );
        }
        final foreign = _foreignOption(group, stored!.group);
        if (foreign != null) {
          return AdminResult<List<OptionGroupRef>>.refused(foreign);
        }
        storedInline[group.id] = stored.group;
      }

      if (sharedIds.isNotEmpty) {
        final rows = await tx.execute(
          Sql.named(
            'SELECT id, name_en, is_global, apply_scope, is_variant '
            'FROM pos_modifier_groups '
            'WHERE business_id = @r AND id = ANY(@ids::bigint[])',
          ),
          parameters: {'r': businessId, 'ids': sharedIds},
        );
        final found = {for (final row in rows) row[0]! as int: row};
        for (final id in sharedIds) {
          final row = found[id];
          if (row == null) {
            return const AdminResult<List<OptionGroupRef>>.refused(
              EditedElsewhere(0),
            );
          }
          final name = row[1]! as String;
          if (readBool(row[2]) != true) {
            return AdminResult<List<OptionGroupRef>>.refused(
              OptionGroupRefused(
                OptionGroupProblem.notInLibrary,
                names: [name],
              ),
            );
          }
          if (row[3] != OptionGroupScope.items.wire) {
            return AdminResult<List<OptionGroupRef>>.refused(
              OptionGroupRefused(
                OptionGroupProblem.alreadyReaches,
                names: [name],
              ),
            );
          }
          if (readBool(row[4]) == true) sizes.add(name);
        }
      }

      // **One set of sizes per item.** The platform accepts two and then
      // prices from whichever comes first, so the second is a set of sizes
      // the sheet offers and the tile never quotes — and on this till, where
      // the last size chosen prices the line, one the ticket would charge.
      // Counted with the library groups that reach this item by themselves,
      // because an item under an "every item" size group already has one.
      final reaching = await tx.execute(
        Sql.named(
          'SELECT g.name_en FROM pos_modifier_groups g '
          'WHERE g.business_id = @r AND g.is_global AND g.is_variant '
          "  AND (g.apply_scope = 'all' "
          "       OR (g.apply_scope = 'categories' AND EXISTS ("
          '         SELECT 1 FROM pos_modifier_group_categories c '
          '          WHERE c.group_id = g.id AND c.category_id = @category))) '
          'ORDER BY g.name_en, g.name_ar, g.id',
        ),
        parameters: {'r': businessId, 'category': categoryId},
      );
      sizes.addAll([for (final row in reaching) row[0]! as String]);
      if (sizes.length > 1) {
        return AdminResult<List<OptionGroupRef>>.refused(
          OptionGroupRefused(OptionGroupProblem.secondSizes, names: sizes),
        );
      }

      // ── nothing below refuses ──

      await tx.execute(
        Sql.named(
          'DELETE FROM pos_product_modifier_groups WHERE product_id = @id',
        ),
        parameters: {'id': productId},
      );

      // An item's own group that the list no longer names is gone, as it is
      // on the platform — nothing else can reach it. Unless something does:
      // migration 45 moved every group on more than one item into the library,
      // so this guard only matters for a writer that went round it, and there
      // the link is removed and the group left alone.
      final kept = {
        for (final ref in refs)
          if (ref case InlineGroupRef(:final group) when group.id != 0)
            group.id,
      };
      for (final dropped in ownBefore.values) {
        if (kept.contains(dropped.id)) continue;
        final gone = await tx.execute(
          Sql.named(
            'DELETE FROM pos_modifier_groups g '
            'WHERE g.id = @id AND g.business_id = @r AND NOT g.is_global '
            '  AND NOT EXISTS (SELECT 1 FROM pos_product_modifier_groups l '
            '                   WHERE l.group_id = g.id) '
            'RETURNING g.id',
          ),
          parameters: {'id': dropped.id, 'r': businessId},
        );
        if (gone.isEmpty) continue;
        await _audit(
          tx,
          by: by,
          action: AuditAction.optionGroupDeleted,
          entityType: AuditAction.entityOptionGroup,
          entityId: '${dropped.id}',
          before: _groupSummary(dropped, shared: false),
          after: {'product_id': productId},
        );
      }

      final after = <int>[];
      for (final ref in refs) {
        final groupId = switch (ref) {
          SharedGroupRef(:final groupId) => groupId,
          InlineGroupRef(:final group) => await _writeInline(
            tx,
            group,
            by: by,
            before: storedInline[group.id],
          ),
        };
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_product_modifier_groups '
            '  (product_id, group_id, sort_order) '
            'VALUES (@product, @group, @sort)',
          ),
          parameters: {
            'product': productId,
            'group': groupId,
            'sort': after.length,
          },
        );
        after.add(groupId);
      }

      await _audit(
        tx,
        by: by,
        action: AuditAction.productOptionsChanged,
        entityType: AuditAction.entityProduct,
        entityId: '$productId',
        before: {'option_groups': [for (final ref in before) _refId(ref)]},
        after: {'option_groups': after},
      );

      return AdminResult.done(await _productRefs(tx, productId));
    });
  }

  /// One of the item's own groups, written only if it changed.
  ///
  /// Saving an item saves every group typed on it, and rewriting the ones
  /// nobody touched would bump their revisions and put a row on the ledger
  /// for each — a manager fixing a price would appear to have edited four
  /// groups.
  Future<int> _writeInline(
    TxSession tx,
    OptionGroupDraft group, {
    required PosStaff by,
    OptionGroupDraft? before,
  }) async {
    if (before != null &&
        jsonEncode(_groupSummary(before, shared: false)) ==
            jsonEncode(_groupSummary(group, shared: false))) {
      return before.id;
    }
    final saved = await _writeGroup(
      tx,
      group,
      global: false,
      by: by,
      before: before,
    );
    return saved.id;
  }

  /// Write [group] — normalised, checked and locked already — with its
  /// options and, for a library group, its scope's links. Audited here, so a
  /// group saved in the library and one saved with its item leave the same
  /// kind of row.
  Future<OptionGroupDraft> _writeGroup(
    TxSession tx,
    OptionGroupDraft group, {
    required bool global,
    required PosStaff by,
    OptionGroupDraft? before,
  }) async {
    final parameters = <String, Object?>{
      'r': businessId,
      'nameEn': group.nameEn,
      'nameAr': group.nameAr,
      'displayEn': group.displayNameEn,
      'displayAr': group.displayNameAr,
      'required': group.isRequired,
      'max': group.maxSelect,
      'min': group.minSelect,
      'free': group.freeOptions,
      'variant': group.isVariant,
      'scope': group.scope.wire,
    };

    final int id;
    if (group.id == 0) {
      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_modifier_groups (business_id, name_en, name_ar, '
          '  display_name_en, display_name_ar, is_required, max_select, '
          '  min_select, free_options, is_variant, is_global, apply_scope) '
          'VALUES (@r, @nameEn, @nameAr, @displayEn, @displayAr, @required, '
          '        @max, @min, @free, @variant, @global, @scope) '
          'RETURNING id',
        ),
        parameters: {...parameters, 'global': global},
      );
      id = rows.first[0]! as int;
    } else {
      id = group.id;
      // The old path goes before the scope moves: migration 45 refuses a
      // scope change while links of the old kind remain, and the platform's
      // rule is that changing it clears them — a group reaches its items one
      // way at a time.
      if (group.scope != OptionGroupScope.items) {
        await tx.execute(
          Sql.named(
            'DELETE FROM pos_product_modifier_groups WHERE group_id = @id',
          ),
          parameters: {'id': id},
        );
      }
      if (group.scope != OptionGroupScope.categories) {
        await tx.execute(
          Sql.named(
            'DELETE FROM pos_modifier_group_categories WHERE group_id = @id',
          ),
          parameters: {'id': id},
        );
      }
      await tx.execute(
        Sql.named(
          'UPDATE pos_modifier_groups SET name_en = @nameEn, '
          '  name_ar = @nameAr, display_name_en = @displayEn, '
          '  display_name_ar = @displayAr, is_required = @required, '
          '  max_select = @max, min_select = @min, free_options = @free, '
          '  is_variant = @variant, apply_scope = @scope, '
          '  revision = revision + 1, updated_at = now() '
          'WHERE id = @id AND business_id = @r',
        ),
        parameters: {...parameters, 'id': id},
      );
    }

    if (group.scope == OptionGroupScope.categories) {
      await tx.execute(
        Sql.named(
          'DELETE FROM pos_modifier_group_categories '
          'WHERE group_id = @id AND NOT (category_id = ANY(@keep::bigint[]))',
        ),
        parameters: {'id': id, 'keep': group.categoryIds.toList()},
      );
      for (final category in group.categoryIds) {
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_modifier_group_categories (group_id, category_id) '
            'VALUES (@id, @category) ON CONFLICT DO NOTHING',
          ),
          parameters: {'id': id, 'category': category},
        );
      }
    }

    // **Matched by id — updated in place, added, or removed — never wiped
    // and recreated.** The platform deletes a group's options and inserts
    // them again on every save, which gives each one a new id each time. Here
    // the id is how a parked ticket and `pos_order_lines.modifier_ids` name
    // what was chosen, so a Large that became a different number because
    // somebody fixed a typo in "Small" is a Large nothing can find again.
    await tx.execute(
      Sql.named(
        'DELETE FROM pos_modifiers '
        'WHERE group_id = @id AND NOT (id = ANY(@keep::bigint[]))',
      ),
      parameters: {
        'id': id,
        'keep': [
          for (final option in group.options)
            if (option.id != 0) option.id,
        ],
      },
    );
    for (var position = 0; position < group.options.length; position++) {
      final option = group.options[position];
      final values = <String, Object?>{
        'group': id,
        'nameEn': option.nameEn,
        'nameAr': option.nameAr,
        'price': option.price.minor,
        'sale': option.salePrice?.minor,
        'available': option.isAvailable,
        'sort': position,
      };
      if (option.id == 0) {
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_modifiers (group_id, name_en, name_ar, '
            '  price_delta_minor, discounted_price_minor, is_available, '
            '  sort_order) '
            'VALUES (@group, @nameEn, @nameAr, @price, @sale, @available, '
            '        @sort)',
          ),
          parameters: values,
        );
      } else {
        await tx.execute(
          Sql.named(
            'UPDATE pos_modifiers SET name_en = @nameEn, name_ar = @nameAr, '
            '  price_delta_minor = @price, discounted_price_minor = @sale, '
            '  is_available = @available, sort_order = @sort, '
            '  revision = revision + 1, updated_at = now() '
            'WHERE id = @option AND group_id = @group',
          ),
          parameters: {...values, 'option': option.id},
        );
      }
    }

    final saved = (await _groups(
      tx,
      where: 'g.id = @id',
      parameters: {'id': id},
    )).single.group;

    await _audit(
      tx,
      by: by,
      action: _repriced(before, saved)
          ? AuditAction.optionGroupRepriced
          : AuditAction.optionGroupSaved,
      entityType: AuditAction.entityOptionGroup,
      entityId: '$id',
      before: before == null ? null : _groupSummary(before, shared: global),
      after: _groupSummary(saved, shared: global),
    );
    return saved;
  }

  /// Lock the group being edited and hand back what it says, or why it
  /// cannot be edited from here.
  ///
  /// [global] is which side is asking: the library edits only library groups,
  /// and an item edits only its own, because the same row edited from both
  /// would be a library group whose options one item could change for all.
  Future<(_Stored?, AdminRefusal?)> _lockForEdit(
    TxSession tx, {
    required int id,
    required int revision,
    required bool global,
  }) async {
    final locked = await tx.execute(
      Sql.named(
        'SELECT revision, is_global FROM pos_modifier_groups '
        'WHERE id = @id AND business_id = @r FOR UPDATE',
      ),
      parameters: {'id': id, 'r': businessId},
    );
    if (locked.isEmpty) return (null, const EditedElsewhere(0));

    final current = locked.first[0]! as int;
    final isGlobal = locked.first.boolean(1);
    if (isGlobal != global) {
      return (
        null,
        OptionGroupRefused(
          global
              ? OptionGroupProblem.belongsToOneItem
              : OptionGroupProblem.belongsToLibrary,
        ),
      );
    }
    if (current != revision) return (null, EditedElsewhere(current));

    final stored = await _groups(tx, where: 'g.id = @id', parameters: {'id': id});
    return (stored.single, null);
  }

  /// An option id [draft] names that is not one of [stored]'s — a new group
  /// has none of its own. With the revision already matched, this is not a
  /// race but a caller moving another group's option into this one, which
  /// would take it from under the group it belongs to.
  static AdminRefusal? _foreignOption(
    OptionGroupDraft draft,
    OptionGroupDraft? stored,
  ) {
    final own = {for (final option in stored?.options ?? const []) option.id};
    for (final option in draft.options) {
      if (option.id != 0 && !own.contains(option.id)) {
        return const OptionGroupRefused(OptionGroupProblem.foreignOption);
      }
    }
    return null;
  }

  /// Refuses a product whose category is another business's, or is archived
  /// and the product is new or moving into it (XORD-014). An item that already
  /// sits in a category archived since may still be repriced: refusing that
  /// would lock a price edit behind an unrelated archive.
  Future<AdminRefusal?> _categoryUnavailable(
    TxSession tx,
    Product product,
  ) async {
    const refusal = CatalogRefused(CatalogProblem.categoryUnavailable);
    final category = await tx.execute(
      Sql.named(
        'SELECT is_active FROM pos_categories '
        'WHERE id = @c AND business_id = @r',
      ),
      parameters: {'c': product.categoryId, 'r': businessId},
    );
    if (category.isEmpty) return refusal;
    if (category.first.boolean(0)) return null;

    if (product.id == 0) return refusal;
    final unchanged = await tx.execute(
      Sql.named(
        'SELECT 1 FROM pos_products '
        'WHERE id = @id AND business_id = @r AND category_id = @c',
      ),
      parameters: {
        'id': product.id,
        'r': businessId,
        'c': product.categoryId,
      },
    );
    return unchanged.isEmpty ? refusal : null;
  }

  Future<AdminRefusal?> _categoriesAreOurs(
    TxSession tx,
    Set<int> categoryIds,
  ) async {
    if (categoryIds.isEmpty) return null;
    final rows = await tx.execute(
      Sql.named(
        'SELECT count(*) FROM pos_categories '
        'WHERE business_id = @r AND id = ANY(@ids::bigint[])',
      ),
      parameters: {'r': businessId, 'ids': categoryIds.toList()},
    );
    return (rows.first[0]! as int) == categoryIds.length
        ? null
        : const OptionGroupRefused(OptionGroupProblem.foreignCategory);
  }

  /// The first item [group] would give a second set of sizes, by what it is
  /// about to reach, or null.
  ///
  /// The library side of the one-set-of-sizes rule: an "every item" size
  /// group saved over a menu where one burger already has its own sizes would
  /// otherwise do on every item at once what [setProductOptionGroups] refuses
  /// on one.
  Future<String?> _secondSizeFor(TxSession tx, OptionGroupDraft group) async {
    if (!group.isVariant) return null;

    final reach = switch (group.scope) {
      OptionGroupScope.all => 'true',
      OptionGroupScope.categories => 'p.category_id = ANY(@cats::bigint[])',
      OptionGroupScope.items =>
        'EXISTS (SELECT 1 FROM pos_product_modifier_groups l '
            '        WHERE l.product_id = p.id AND l.group_id = @id)',
    };
    final rows = await tx.execute(
      Sql.named(
        'SELECT p.name_en FROM pos_products p '
        'WHERE p.business_id = @r AND $reach '
        '  AND EXISTS (SELECT 1 FROM pos_modifier_groups g '
        '    WHERE g.business_id = @r AND g.is_variant AND g.id <> @id '
        '      AND (EXISTS (SELECT 1 FROM pos_product_modifier_groups l '
        '                    WHERE l.product_id = p.id AND l.group_id = g.id) '
        "           OR (g.is_global AND g.apply_scope = 'all') "
        "           OR (g.is_global AND g.apply_scope = 'categories' "
        '               AND EXISTS (SELECT 1 FROM pos_modifier_group_categories c '
        '                            WHERE c.group_id = g.id '
        '                              AND c.category_id = p.category_id)))) '
        'ORDER BY p.sort_order, p.id LIMIT 1',
      ),
      parameters: {
        'r': businessId,
        'id': group.id,
        if (group.scope == OptionGroupScope.categories)
          'cats': group.categoryIds.toList(),
      },
    );
    return rows.isEmpty ? null : rows.first[0]! as String;
  }

  /// The groups an item carries itself, in its order.
  Future<List<OptionGroupRef>> _productRefs(TxSession tx, int productId) async {
    final links = await tx.execute(
      Sql.named(
        'SELECT l.group_id, g.is_global FROM pos_product_modifier_groups l '
        'JOIN pos_modifier_groups g ON g.id = l.group_id '
        'JOIN pos_products p ON p.id = l.product_id '
        'WHERE l.product_id = @product AND p.business_id = @r '
        'ORDER BY l.sort_order, l.group_id',
      ),
      parameters: {'product': productId, 'r': businessId},
    );
    final ownIds = [
      for (final row in links)
        if (readBool(row[1]) != true) row[0]! as int,
    ];
    final own = <int, OptionGroupDraft>{
      if (ownIds.isNotEmpty)
        for (final stored in await _groups(
          tx,
          where: 'g.id = ANY(@ids::bigint[])',
          parameters: {'ids': ownIds},
        ))
          stored.group.id: stored.group,
    };
    return [
      for (final row in links)
        if (readBool(row[1]) == true)
          OptionGroupRef.shared(row[0]! as int)
        else if (own[row[0]! as int] case final group?)
          OptionGroupRef.inline(group),
    ];
  }

  static const _groupColumns =
      'g.id, g.revision, g.name_en, g.name_ar, g.display_name_en, '
      'g.display_name_ar, g.is_variant, g.is_required, g.max_select, '
      'g.min_select, g.free_options, g.apply_scope, g.is_global, '
      'coalesce((SELECT array_agg(c.category_id ORDER BY c.category_id) '
      '            FROM pos_modifier_group_categories c '
      "           WHERE c.group_id = g.id), '{}')";

  /// Groups of this business matching [where], with their options, as the
  /// editor holds them. [where] is always a constant in this file.
  Future<List<_Stored>> _groups(
    TxSession tx, {
    required String where,
    Map<String, Object?> parameters = const {},
    String orderBy = 'g.id',
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_groupColumns FROM pos_modifier_groups g '
        'WHERE g.business_id = @r AND ($where) ORDER BY $orderBy',
      ),
      parameters: {...parameters, 'r': businessId},
    );
    if (rows.isEmpty) return const [];

    final optionRows = await tx.execute(
      Sql.named(
        'SELECT id, group_id, name_en, name_ar, price_delta_minor, '
        '       discounted_price_minor, is_available '
        'FROM pos_modifiers WHERE group_id = ANY(@ids::bigint[]) '
        'ORDER BY sort_order, id',
      ),
      parameters: {
        'ids': [for (final row in rows) row[0]! as int],
      },
    );
    final options = <int, List<OptionDraft>>{};
    for (final row in optionRows) {
      options
          .putIfAbsent(row[1]! as int, () => [])
          .add(
            OptionDraft(
              id: row[0]! as int,
              nameEn: row[2]! as String,
              nameAr: row[3] as String?,
              price: Money(row[4]! as int),
              salePrice: row[5] == null ? null : Money(row[5]! as int),
              isAvailable: row.boolean(6),
            ),
          );
    }

    return [
      for (final row in rows)
        (
          group: OptionGroupDraft(
            id: row[0]! as int,
            revision: row[1]! as int,
            nameEn: row[2]! as String,
            nameAr: row[3] as String?,
            displayNameEn: row[4] as String?,
            displayNameAr: row[5] as String?,
            isVariant: row.boolean(6),
            isRequired: row.boolean(7),
            maxSelect: row[8]! as int,
            minSelect: row[9]! as int,
            freeOptions: row[10]! as int,
            scope: OptionGroupScope.fromWire(row[11] as String?),
            categoryIds: (row[13]! as List).whereType<int>().toSet(),
            options: options[row[0]! as int] ?? const [],
          ),
          isGlobal: row.boolean(12),
        ),
    ];
  }

  /// An option that was there before now costs something else. Adding one
  /// or taking one away is an edit; the price of one that stayed changing is
  /// a reprice.
  static bool _repriced(OptionGroupDraft? before, OptionGroupDraft after) {
    if (before == null) return false;
    final was = {for (final option in before.options) option.id: option};
    for (final option in after.options) {
      final old = was[option.id];
      if (old == null) continue;
      if (old.price.minor != option.price.minor ||
          old.salePrice?.minor != option.salePrice?.minor) {
        return true;
      }
    }
    return false;
  }

  /// What the ledger says a group was. Every field, so the row answers "what
  /// did this offer, at what price" after the group itself is gone.
  static Map<String, Object?> _groupSummary(
    OptionGroupDraft group, {
    required bool shared,
  }) => {
    'name': group.nameEn,
    'name_ar': group.nameAr,
    'display_name_en': group.displayNameEn,
    'display_name_ar': group.displayNameAr,
    'shared': shared,
    'is_variant': group.isVariant,
    'is_required': group.isRequired,
    'max_select': group.maxSelect,
    'min_select': group.minSelect,
    'free_options': group.freeOptions,
    'scope': group.scope.wire,
    'category_ids': (group.categoryIds.toList()..sort()),
    'options': [
      for (final option in group.options)
        {
          'id': option.id,
          'name': option.nameEn,
          'name_ar': option.nameAr,
          'price_minor': option.price.minor,
          'sale_price_minor': option.salePrice?.minor,
          'is_available': option.isAvailable,
        },
    ],
  };

  static int _refId(OptionGroupRef ref) => switch (ref) {
    SharedGroupRef(:final groupId) => groupId,
    InlineGroupRef(:final group) => group.id,
  };

  // ── plumbing ───────────────────────────────────────────────────────────────

  Map<String, Object?> _categoryParams(Category category) => {
    'r': businessId,
    'nameEn': category.nameEn.trim(),
    'nameAr': _orNull(category.nameAr),
    'slug': _orNull(category.slug),
    'sort': category.sortOrder,
  };

  Map<String, Object?> _productParams(Product product) => {
    'r': businessId,
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
    // business could define a zero-rated group and had no way to put anything
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
    isActive: row.boolean(5),
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
    isAvailable: row.boolean(8),
    sortOrder: row[9]! as int,
    taxGroupId: row[11] as int?,
    isStocked: row.boolean(12),
    stockUnit: row[13] == null ? null : QuantityUnit.fromWire(row[13] as String),
  );

  // ── combos ─────────────────────────────────────────────────────────────────

  @override
  Future<List<ComboDraft>> combos() =>
      database.runTx(config, (tx) => _combosIn(tx));

  /// On the caller's transaction, so a save can read back what it has written
  /// and not yet committed — a second transaction would see the old tree.
  Future<List<ComboDraft>> _combosIn(TxSession tx) async {
    final comboRows = await tx.execute(
      Sql.named(
        'SELECT id, category_id, name_en, name_ar, price_minor, '
        '       tax_group_id, sku, is_available '
        'FROM pos_combos WHERE business_id = @r '
        'ORDER BY sort_order, id',
      ),
      parameters: {'r': businessId},
    );
    if (comboRows.isEmpty) return const <ComboDraft>[];

    // Three small reads rather than one join, as the till's own catalogue
    // read does: unpicking a combo → groups → options shape from a flattened
    // result is more code than asking three times.
    final groupRows = await tx.execute(
      Sql.named(
        'SELECT g.id, g.combo_id, g.name_en, g.name_ar, g.min_select, '
        '       g.max_select '
        'FROM pos_combo_groups g '
        'JOIN pos_combos c ON c.id = g.combo_id '
        'WHERE c.business_id = @r ORDER BY g.sort_order, g.id',
      ),
      parameters: {'r': businessId},
    );
    final optionRows = await tx.execute(
      Sql.named(
        'SELECT o.combo_group_id, o.product_id, o.price_delta_minor '
        'FROM pos_combo_options o '
        'JOIN pos_combo_groups g ON g.id = o.combo_group_id '
        'JOIN pos_combos c ON c.id = g.combo_id '
        'WHERE c.business_id = @r ORDER BY o.sort_order, o.id',
      ),
      parameters: {'r': businessId},
    );

    final optionsByGroup = <int, List<ComboOptionDraft>>{};
    for (final row in optionRows) {
      optionsByGroup
          .putIfAbsent(row[0]! as int, () => [])
          .add(
            ComboOptionDraft(
              productId: row[1]! as int,
              priceDelta: Money(row[2]! as int),
            ),
          );
    }
    final groupsByCombo = <int, List<ComboGroupDraft>>{};
    for (final row in groupRows) {
      final id = row[0]! as int;
      groupsByCombo
          .putIfAbsent(row[1]! as int, () => [])
          .add(
            ComboGroupDraft(
              id: id,
              nameEn: row[2]! as String,
              nameAr: row[3] as String?,
              minSelect: row[4]! as int,
              maxSelect: row[5]! as int,
              options: optionsByGroup[id] ?? const [],
            ),
          );
    }

    return [
      for (final row in comboRows)
        ComboDraft(
          id: row[0]! as int,
          categoryId: row[1]! as int,
          nameEn: row[2]! as String,
          nameAr: row[3] as String?,
          price: Money(row[4]! as int),
          taxGroupId: row[5] as int?,
          sku: row[6] as String?,
          isAvailable: row.boolean(7),
          groups: groupsByCombo[row[0]! as int] ?? const [],
        ),
    ];
  }

  @override
  Future<AdminResult<ComboDraft>> saveCombo(
    ComboDraft combo, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    final problem = ComboRules.refusal(combo);
    if (problem != null) return AdminResult.refused(ComboRefused(problem));

    final sku = combo.sku?.trim();
    final skuOrNull = (sku == null || sku.isEmpty) ? null : sku;

    return database.runTx(config, (tx) async {
      AdminResult<ComboDraft> refuse(ComboProblem problem) =>
          AdminResult.refused(ComboRefused(problem));

      final category = await tx.execute(
        Sql.named(
          'SELECT 1 FROM pos_categories WHERE id = @id AND business_id = @r',
        ),
        parameters: {'id': combo.categoryId, 'r': businessId},
      );
      if (category.isEmpty) return refuse(ComboProblem.categoryUnknown);

      if (combo.taxGroupId != null) {
        final rate = await tx.execute(
          Sql.named(
            'SELECT 1 FROM pos_tax_groups WHERE id = @id AND business_id = @r',
          ),
          parameters: {'id': combo.taxGroupId, 'r': businessId},
        );
        if (rate.isEmpty) return refuse(ComboProblem.taxGroupUnknown);
      }

      final productIds = {
        for (final group in combo.groups)
          for (final option in group.options) option.productId,
      }.toList();
      final owned = await tx.execute(
        Sql.named(
          'SELECT id FROM pos_products '
          'WHERE business_id = @r AND id = ANY(@ids::bigint[])',
        ),
        parameters: {'r': businessId, 'ids': productIds},
      );
      if (owned.length != productIds.length) {
        return refuse(ComboProblem.productUnknown);
      }

      if (skuOrNull != null) {
        final clash = await tx.execute(
          Sql.named(
            'SELECT 1 FROM pos_combos '
            'WHERE business_id = @r AND sku = @sku AND id <> @id',
          ),
          parameters: {'r': businessId, 'sku': skuOrNull, 'id': combo.id},
        );
        if (clash.isNotEmpty) return refuse(ComboProblem.skuTaken);
      }

      final fields = <String, Object?>{
        'r': businessId,
        'category': combo.categoryId,
        'nameEn': combo.nameEn.trim(),
        'nameAr': combo.nameAr?.trim().isEmpty ?? true
            ? null
            : combo.nameAr!.trim(),
        'price': combo.price.minor,
        'taxGroup': combo.taxGroupId,
        'sku': skuOrNull,
        'available': combo.isAvailable,
      };

      int? before;
      final int comboId;
      if (combo.id == 0) {
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_combos (business_id, category_id, name_en, '
            '  name_ar, price_minor, tax_group_id, sku, is_available, '
            '  sort_order) '
            'VALUES (@r, @category, @nameEn, @nameAr, @price, @taxGroup, '
            '  @sku, @available, '
            '  (SELECT coalesce(max(sort_order), 0) + 1 FROM pos_combos '
            '    WHERE business_id = @r)) '
            'RETURNING id',
          ),
          parameters: fields,
        );
        comboId = rows.first[0]! as int;
      } else {
        final held = await tx.execute(
          Sql.named(
            'SELECT price_minor FROM pos_combos '
            'WHERE id = @id AND business_id = @r FOR UPDATE',
          ),
          parameters: {'id': combo.id, 'r': businessId},
        );
        if (held.isEmpty) {
          return const AdminResult<ComboDraft>.refused(EditedElsewhere(0));
        }
        before = held.first[0]! as int;
        await tx.execute(
          Sql.named(
            'UPDATE pos_combos SET category_id = @category, name_en = @nameEn, '
            '  name_ar = @nameAr, price_minor = @price, '
            '  tax_group_id = @taxGroup, sku = @sku, is_available = @available '
            'WHERE id = @id AND business_id = @r',
          ),
          parameters: {...fields, 'id': combo.id},
        );
        comboId = combo.id;
      }

      // Groups matched by id: updated, added, or removed — never recreated.
      final keptGroups = <int>[];
      for (var g = 0; g < combo.groups.length; g++) {
        final group = combo.groups[g];
        final groupFields = <String, Object?>{
          'nameEn': group.nameEn.trim(),
          'nameAr': group.nameAr?.trim().isEmpty ?? true
              ? null
              : group.nameAr!.trim(),
          'min': group.minSelect,
          'max': group.maxSelect,
          'sort': g,
        };

        int groupId;
        if (group.id == 0) {
          final rows = await tx.execute(
            Sql.named(
              'INSERT INTO pos_combo_groups (combo_id, name_en, name_ar, '
              '  min_select, max_select, sort_order) '
              'VALUES (@combo, @nameEn, @nameAr, @min, @max, @sort) '
              'RETURNING id',
            ),
            parameters: {...groupFields, 'combo': comboId},
          );
          groupId = rows.first[0]! as int;
        } else {
          // Scoped to this combo: a group id typed into another combo's save
          // must not move that group here.
          final rows = await tx.execute(
            Sql.named(
              'UPDATE pos_combo_groups SET name_en = @nameEn, '
              '  name_ar = @nameAr, min_select = @min, max_select = @max, '
              '  sort_order = @sort '
              'WHERE id = @id AND combo_id = @combo RETURNING id',
            ),
            parameters: {...groupFields, 'id': group.id, 'combo': comboId},
          );
          if (rows.isEmpty) {
            return const AdminResult<ComboDraft>.refused(EditedElsewhere(0));
          }
          groupId = group.id;
        }
        keptGroups.add(groupId);

        // Options are replaced as a set. Nothing refers to an option row —
        // an order line snapshots its items — so unlike a group they have no
        // identity to keep, and replacing them cannot orphan a ticket.
        await tx.execute(
          Sql.named('DELETE FROM pos_combo_options WHERE combo_group_id = @g'),
          parameters: {'g': groupId},
        );
        for (var o = 0; o < group.options.length; o++) {
          final option = group.options[o];
          await tx.execute(
            Sql.named(
              'INSERT INTO pos_combo_options '
              '  (combo_group_id, product_id, price_delta_minor, sort_order) '
              'VALUES (@g, @product, @delta, @sort)',
            ),
            parameters: {
              'g': groupId,
              'product': option.productId,
              'delta': option.priceDelta.minor,
              'sort': o,
            },
          );
        }
      }

      await tx.execute(
        Sql.named(
          'DELETE FROM pos_combo_groups '
          'WHERE combo_id = @combo AND NOT (id = ANY(@keep::bigint[]))',
        ),
        parameters: {'combo': comboId, 'keep': keptGroups},
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.comboSaved,
        entityType: AuditAction.entityCombo,
        entityId: '$comboId',
        before: before == null ? null : {'price_minor': before},
        after: {
          'name': combo.nameEn.trim(),
          'price_minor': combo.price.minor,
          'available': combo.isAvailable,
          'groups': combo.groups.length,
        },
      );

      // Read back, so what is returned is what was stored — ids included.
      final stored = (await _combosIn(tx)).where((c) => c.id == comboId);
      return AdminResult.done(stored.first);
    });
  }

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
      'INSERT INTO pos_audit_events (business_id, branch_id, terminal_id, '
      '  actor_user_id, actor_name, action, entity_type, entity_id, '
      '  before_value, after_value) '
      'VALUES (@r, @branch, @terminal, @actor, @actorName, @action, '
      '        @entityType, @entityId, @before::jsonb, @after::jsonb)',
    ),
    parameters: {
      'r': businessId,
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
