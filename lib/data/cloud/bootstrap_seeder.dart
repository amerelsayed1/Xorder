import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/tender_method.dart';
import '../postgres/pos_database.dart';
import 'bootstrap_bundle.dart';

/// What a seed attempt did, as data the wizard and the sync loop can act on.
class SeedReport {
  const SeedReport.applied(this.configVersion) : applied = true, reason = null;

  const SeedReport.skipped(this.reason, {this.configVersion = 0})
    : applied = false;

  final bool applied;
  final int configVersion;

  /// Why nothing was written. `stale` is the rollback refusal of POS-BE-025;
  /// `unchanged` is an equal version — both are normal operation, not errors.
  final String? reason;
}

/// Writes a bootstrap bundle into the till's local PostgreSQL.
///
/// This is how a cloud terminal gets its world: the platform authors the
/// catalog, the staff and the floor, and this seeder makes the local database —
/// which every existing repository already reads — agree with it. Nothing in
/// `domain/` or `features/` knows the seed happened; the sale screen just finds
/// the menu there, exactly as it does on a branch server.
///
/// **Platform ids are kept verbatim.** A seeded product row carries the
/// platform's `menu_item_id` as its primary key, which is what lets the drain
/// send lines the server can re-price (POS-BE-006) without an id-mapping table
/// that would have to survive every resync. Serial sequences are bumped past
/// the seeded ids afterwards so locally-authored rows can never collide.
///
/// **The catalog and floor are wiped and rewritten; people are not.** Staff
/// rows are referenced by shifts (`ON DELETE RESTRICT` — the record of who
/// counted a drawer outlives employment), so departed staff are deactivated,
/// never deleted. Catalog rows have no such history: order lines snapshot the
/// name and price at sale time precisely so the catalog can be replaced whole.
class BootstrapSeeder {
  const BootstrapSeeder({required PosDatabase database, required this.config})
    : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;

  Future<SeedReport> seed(BootstrapBundle bundle, {bool force = false}) async {
    if (!bundle.seedable) {
      return const SeedReport.skipped('incomplete');
    }
    final restaurant = bundle.restaurant!;

    return _db.runTx(config, (tx) async {
      final held = await tx.execute(
        Sql.named(
          'SELECT config_version FROM pos_cloud_state WHERE restaurant_id = @restaurant',
        ),
        parameters: {'restaurant': restaurant.id},
      );
      final cached = held.isEmpty ? -1 : held.first[0] as int;

      // The version is the sole precedence signal (POS-BE-025): an older bundle
      // is a rollback and is refused, an equal one is already applied. `force`
      // exists for a re-seed after a half-failed apply, never for precedence.
      if (!force && bundle.configVersion < cached) {
        return SeedReport.skipped('stale', configVersion: cached);
      }
      if (!force && bundle.configVersion == cached) {
        return SeedReport.skipped('unchanged', configVersion: cached);
      }

      await _seedIdentity(tx, bundle);
      await _seedMoney(tx, bundle);
      await _seedTenderTypes(tx, bundle);
      await _seedStaff(tx, bundle);
      await _seedCatalog(tx, bundle);
      await _seedTables(tx, bundle);
      await _bumpSequences(tx);

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_cloud_state (restaurant_id, config_version, bootstrap_synced_at, updated_at)
          VALUES (@restaurant, @version, @syncedAt, now())
          ON CONFLICT (restaurant_id) DO UPDATE
            SET config_version = @version, bootstrap_synced_at = @syncedAt, updated_at = now()
        '''),
        parameters: {
          'restaurant': restaurant.id,
          'version': bundle.configVersion,
          'syncedAt': (bundle.syncedAt ?? DateTime.now()).toUtc(),
        },
      );

      return SeedReport.applied(bundle.configVersion);
    });
  }

  Future<void> _seedIdentity(TxSession tx, BootstrapBundle bundle) async {
    final restaurant = bundle.restaurant!;
    final terminal = bundle.terminal!;

    await tx.execute(
      Sql.named('''
        INSERT INTO pos_restaurants (id, slug, name, name_ar, tax_number, is_active)
        VALUES (@id, @slug, @name, @nameAr, @tax, true)
        ON CONFLICT (id) DO UPDATE
          SET slug = @slug, name = @name, name_ar = @nameAr, tax_number = @tax, is_active = true
      '''),
      parameters: {
        'id': restaurant.id,
        'slug': restaurant.slug,
        'name': restaurant.name,
        'nameAr': restaurant.nameAr,
        'tax': restaurant.taxRegistrationNumber,
      },
    );

    for (final branch in bundle.branches) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_branches (id, restaurant_id, code, name, supported_order_types, is_active)
          VALUES (@id, @restaurant, @code, @name, @orderTypes, true)
          ON CONFLICT (id) DO UPDATE
            SET code = @code, name = @name, supported_order_types = @orderTypes, is_active = true
        '''),
        parameters: {
          'id': branch.id,
          'restaurant': restaurant.id,
          // The code is the invoice prefix and the local column is NOT NULL; a
          // branch the platform never gave one falls back to its id, which is
          // ugly on a receipt and unmistakably a configuration gap.
          'code': branch.code ?? 'BR${branch.id}',
          'name': branch.name,
          'orderTypes': branch.supportedOrderTypes,
        },
      );
    }
    if (bundle.branches.isNotEmpty) {
      await tx.execute(
        Sql.named(
          'UPDATE pos_branches SET is_active = false '
          'WHERE restaurant_id = @restaurant AND NOT (id = ANY(@keep))',
        ),
        parameters: {
          'restaurant': restaurant.id,
          'keep': [for (final b in bundle.branches) b.id],
        },
      );
    }

    await tx.execute(
      Sql.named('''
        INSERT INTO pos_terminals (id, restaurant_id, branch_id, name, sync_policy, claimed_at)
        VALUES (@id, @restaurant, @branch, @name, @policy, now())
        ON CONFLICT (id) DO UPDATE
          SET branch_id = @branch, name = @name, sync_policy = @policy,
              claimed_at = COALESCE(pos_terminals.claimed_at, now())
      '''),
      parameters: {
        'id': terminal.id,
        'restaurant': restaurant.id,
        'branch': terminal.branchId,
        'name': terminal.name,
        'policy': switch (terminal.syncPolicy) {
          'manual' => 'manual',
          _ => 'automatic',
        },
      },
    );
  }

  /// The platform's tax rules, charges and tender types — the answer to "how
  /// much is owed" (POS-BE-013). Stored verbatim: a rule shape this build
  /// predates still round-trips, and the codec decides what the engine can
  /// currently express.
  Future<void> _seedMoney(TxSession tx, BootstrapBundle bundle) async {
    await tx.execute(
      Sql.named('''
        INSERT INTO pos_money_config (restaurant_id, payload, synced_at)
        VALUES (@restaurant, @payload, now())
        ON CONFLICT (restaurant_id) DO UPDATE
          SET payload = @payload, synced_at = now()
      '''),
      parameters: {
        'restaurant': bundle.restaurant!.id,
        'payload': jsonEncode(bundle.money),
      },
    );
  }

  /// The platform's payment methods, as the rows the payment screen reads.
  ///
  /// `tender_types` also stays inside the verbatim payload above, where
  /// nothing reads it; the payment screen and the drain read these rows.
  ///
  /// **Keyed on `platform_id`, not on the primary key** — the one place this
  /// seeder does not keep a platform id as the local key. Migration 41 says
  /// why: the till's own rows 1–4 were here first, and a queued payment names
  /// its tender by local id, so overwriting them in place would re-mean those
  /// payments as whichever platform tender shared the number. Every column is
  /// rewritten on conflict, so no flag of an earlier row survives into the
  /// platform's.
  ///
  /// Retired, never deleted, like people: `pos_order_payments.tender_type_id`
  /// has no foreign key onto this table, so a DELETE would orphan a payment in
  /// silence where a retired row stays readable.
  Future<void> _seedTenderTypes(TxSession tx, BootstrapBundle bundle) async {
    final restaurantId = bundle.restaurant!.id;
    final tenders = bundle.tenderTypes;

    // An empty list leaves the table as it is. Retiring everything would drop
    // the payment screen onto its compiled-in fallback, and every payment
    // taken on that would be held by the drain anyway — no better than what
    // is here, and a crash would be worse than both. The platform guarantees
    // a POS restaurant is never delivered an empty list; this is the till not
    // relying on that.
    if (tenders.isEmpty) return;

    // Past the compiled-in ids before anything is inserted. Migration 41's
    // CHECK refuses a platform row at 1–4; this is what stops the serial from
    // offering one.
    await tx.execute(
      Sql.named(
        "SELECT setval(pg_get_serial_sequence('pos_tender_types', 'id'), "
        'GREATEST(COALESCE((SELECT MAX(id) FROM pos_tender_types), 0), '
        '@floor), true)',
      ),
      parameters: {'floor': TenderMethod.seededIdCeiling},
    );

    for (final tender in tenders) {
      final kind = tender.kind;
      // Only cash is notes in the drawer. An unknown kind counts as nothing,
      // which is the safe direction for a drawer and the same default
      // `Tender.countsAsCash` has.
      final cash = kind == PlatformTenderKind.cash;

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_tender_types (restaurant_id, platform_id, code,
            name_en, name_ar, kind, counts_as_cash, opens_drawer,
            requires_reference, refund_allowed, is_active, sort_order)
          VALUES (@restaurant, @platformId, @code, @name, NULL, @kind, @cash,
            @cash, false, true, @active, @sort)
          ON CONFLICT (restaurant_id, platform_id) DO UPDATE
            SET code = @code, name_en = @name, name_ar = NULL, kind = @kind,
                counts_as_cash = @cash, opens_drawer = @cash,
                requires_reference = false, refund_allowed = true,
                is_active = @active, sort_order = @sort
        '''),
        parameters: {
          'restaurant': restaurantId,
          'platformId': tender.id,
          // Unique by construction: platform_id is unique per restaurant, and
          // migration 41 keeps the prefix off every row the platform did not
          // send.
          'code': 'platform-${tender.id}',
          // One name comes over the wire. `name_ar` stays null rather than a
          // copy of it, so `displayName` falls back openly instead of
          // claiming a translation nobody wrote.
          'name': tender.name,
          'kind': (kind?.tillKind ?? TenderKind.other).wire,
          'cash': cash,
          // `requires_reference` is false for all of them. The platform has
          // nowhere to say a tender wants one, and nothing at the counter reads
          // the flag today — so setting it here would be a rule the owner can
          // neither see on the dashboard nor switch off there, waiting for the
          // day the payment screen starts enforcing it. `refund_allowed` is
          // true for the matching reason: refusing a refund the owner never
          // refused is the worse error at a counter.
          'active': tender.isActive,
          'sort': tender.sortOrder,
        },
      );
    }

    // Everything the bundle did not name is switched off — the till's own four
    // included. On a cloud till those were never the platform's, and a payment
    // taken on one is exactly what the drain now refuses to send.
    await tx.execute(
      Sql.named(
        'UPDATE pos_tender_types SET is_active = false '
        'WHERE restaurant_id = @restaurant '
        '  AND (platform_id IS NULL OR NOT (platform_id = ANY(@keep)))',
      ),
      parameters: {
        'restaurant': restaurantId,
        'keep': [for (final t in tenders) t.id],
      },
    );
  }

  Future<void> _seedStaff(TxSession tx, BootstrapBundle bundle) async {
    final restaurantId = bundle.restaurant!.id;

    for (final member in bundle.staff) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_staff (id, restaurant_id, name, username, pin_salt, pin_hash, capabilities, is_active)
          VALUES (@id, @restaurant, @name, @username, @salt, @hash, @capabilities, @active)
          ON CONFLICT (id) DO UPDATE
            SET name = @name, username = @username,
                pin_salt = @salt, pin_hash = @hash,
                capabilities = @capabilities, is_active = @active
        '''),
        parameters: {
          'id': member.id,
          'restaurant': restaurantId,
          'name': member.name,
          'username': member.username,
          // Empty strings, not nulls: the columns are NOT NULL, and an empty
          // verifier can never match any PIN — "no PIN set" means "cannot sign
          // in offline", exactly as the contract states.
          'salt': member.pin?.salt ?? '',
          'hash': member.pin?.hash ?? '',
          // The platform speaks `pos.*` tenant-capability strings; the local
          // rows speak the till's canonical names. One translation, on the way
          // in, through the same map every other reader uses.
          'capabilities': PosCapability.canonicalAll(
            member.capabilities.toSet(),
          ).toList()..sort(),
          'active': member.isActive,
        },
      );
    }

    // Departed staff are switched off, never deleted — their shifts reference
    // them. Platform-authored rows are authoritative for who works here.
    if (bundle.staff.isNotEmpty) {
      await tx.execute(
        Sql.named(
          'UPDATE pos_staff SET is_active = false '
          'WHERE restaurant_id = @restaurant AND NOT (id = ANY(@keep))',
        ),
        parameters: {
          'restaurant': restaurantId,
          'keep': [for (final s in bundle.staff) s.id],
        },
      );
    }
  }

  Future<void> _seedCatalog(TxSession tx, BootstrapBundle bundle) async {
    final restaurantId = bundle.restaurant!.id;

    // Children before parents; the platform's catalog replaces the local one
    // whole. Order lines snapshot name and price at sale time, so history
    // survives the wipe by construction.
    await tx.execute(
      Sql.named(
        'DELETE FROM pos_product_modifier_groups WHERE product_id IN '
        '(SELECT id FROM pos_products WHERE restaurant_id = @restaurant)',
      ),
      parameters: {'restaurant': restaurantId},
    );
    await tx.execute(
      Sql.named(
        'DELETE FROM pos_modifiers WHERE group_id IN '
        '(SELECT id FROM pos_modifier_groups WHERE restaurant_id = @restaurant)',
      ),
      parameters: {'restaurant': restaurantId},
    );
    // `pos_modifier_group_categories` goes with the groups and the categories
    // — it cascades from both (migration 45). Deliberately not deleted by
    // name: a cascade needs no grant, and a cloud till whose grants predate
    // the table would be refused a DELETE on it and lose the whole seed.
    for (final table in [
      'pos_products',
      'pos_modifier_groups',
      'pos_categories',
    ]) {
      await tx.execute(
        Sql.named('DELETE FROM $table WHERE restaurant_id = @restaurant'),
        parameters: {'restaurant': restaurantId},
      );
    }

    for (final category in bundle.categories) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_categories (id, restaurant_id, name_en, name_ar, slug, sort_order, is_active)
          VALUES (@id, @restaurant, @nameEn, @nameAr, @slug, @sort, @active)
        '''),
        parameters: {
          'id': category.id,
          'restaurant': restaurantId,
          'nameEn': category.nameEn,
          'nameAr': category.nameAr,
          'slug': category.slug,
          'sort': category.sortOrder,
          'active': category.isActive,
        },
      );
    }

    for (final group in bundle.optionGroups) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_modifier_groups (id, restaurant_id, name_en, name_ar, is_required, max_select, is_variant, sort_order)
          VALUES (@id, @restaurant, @nameEn, @nameAr, @required, @maxSelect, @variant, @sort)
        '''),
        parameters: {
          'id': group.id,
          'restaurant': restaurantId,
          'nameEn': group.nameEn,
          'nameAr': group.nameAr,
          'required': group.isRequired,
          'maxSelect': group.maxSelect < 1 ? 1 : group.maxSelect,
          'variant': group.isVariant,
          'sort': group.sortOrder,
        },
      );
      for (final option in group.options) {
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_modifiers (id, group_id, name_en, name_ar, price_delta_minor, is_available, sort_order)
            VALUES (@id, @group, @nameEn, @nameAr, @delta, @available, @sort)
          '''),
          parameters: {
            'id': option.id,
            'group': group.id,
            'nameEn': option.nameEn,
            'nameAr': option.nameAr,
            'delta': option.priceDeltaMinor,
            'available': option.isAvailable,
            'sort': option.sortOrder,
          },
        );
      }
    }

    final knownCategories = {for (final c in bundle.categories) c.id};
    final knownGroups = {for (final g in bundle.optionGroups) g.id};
    for (final product in bundle.products) {
      // A product naming a category the bundle did not carry would trip the FK
      // and roll back the whole seed. Dropping the one product keeps the other
      // two hundred sellable, which is the trade a till wants.
      if (!knownCategories.contains(product.categoryId)) continue;

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_products (id, restaurant_id, category_id, name_en, name_ar,
                                    price_minor, discounted_price_minor, sku, barcode,
                                    is_available, sort_order)
          VALUES (@id, @restaurant, @category, @nameEn, @nameAr,
                  @price, @discounted, @sku, @barcode, @available, @sort)
        '''),
        parameters: {
          'id': product.id,
          'restaurant': restaurantId,
          'category': product.categoryId,
          'nameEn': product.nameEn,
          'nameAr': product.nameAr,
          'price': product.priceMinor,
          'discounted': product.discountedPriceMinor,
          'sku': product.sku,
          'barcode': product.barcode,
          'available': product.isAvailable,
          'sort': product.sortOrder,
        },
      );

      var position = 0;
      for (final groupId in product.optionGroupIds) {
        if (!knownGroups.contains(groupId)) continue;
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_product_modifier_groups (product_id, group_id, sort_order)
            VALUES (@product, @group, @sort)
            ON CONFLICT (product_id, group_id) DO NOTHING
          '''),
          parameters: {
            'product': product.id,
            'group': groupId,
            'sort': position++,
          },
        );
      }
    }
  }

  Future<void> _seedTables(TxSession tx, BootstrapBundle bundle) async {
    final restaurantId = bundle.restaurant!.id;
    final knownBranches = {for (final b in bundle.branches) b.id};

    await tx.execute(
      Sql.named(
        'DELETE FROM pos_dining_tables WHERE restaurant_id = @restaurant',
      ),
      parameters: {'restaurant': restaurantId},
    );
    for (final table in bundle.tables) {
      if (!knownBranches.contains(table.branchId)) continue;
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_dining_tables (id, restaurant_id, branch_id, label, seats, area_name, is_active)
          VALUES (@id, @restaurant, @branch, @label, @seats, @area, @active)
        '''),
        parameters: {
          'id': table.id,
          'restaurant': restaurantId,
          'branch': table.branchId,
          'label': table.label,
          'seats': table.seats,
          'area': table.areaName,
          'active': table.isActive,
        },
      );
    }
  }

  /// Push every serial past the platform ids just written, so a locally
  /// authored row can never be assigned an id the next resync will also use.
  Future<void> _bumpSequences(TxSession tx) async {
    const tables = [
      'pos_restaurants',
      'pos_branches',
      'pos_staff',
      'pos_categories',
      'pos_modifier_groups',
      'pos_modifiers',
      'pos_products',
      'pos_dining_tables',
    ];
    for (final table in tables) {
      await tx.execute(
        "SELECT setval(pg_get_serial_sequence('$table', 'id'), "
        'GREATEST(COALESCE((SELECT MAX(id) FROM $table), 0), 1), true)',
      );
    }
  }
}
