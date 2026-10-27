@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/money_config_codec.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/menu_import.dart';

import 'pg_fixture.dart';

/// `jsonb` comes back decoded on some driver paths and as text on others.
Map<String, Object?> _payload(Object? raw) => switch (raw) {
      final Map map => map.cast<String, Object?>(),
      final String text => (jsonDecode(text) as Map).cast<String, Object?>(),
      _ => throw StateError('unreadable payload: $raw'),
    };

/// Authoring the menu on the till.
///
/// This is the feature an offline restaurant cannot trade without, and the one
/// the coordination docs previously ruled out — so what it refuses matters as
/// much as what it writes. Every test here is a question a restaurant would
/// actually ask: can I change a price, can I take something off sale without
/// losing what it sold, and can two managers on two tills overwrite each other.
void main() {
  if (PgFixture.host == null) {
    test('catalogue authoring (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresCatalogAdminRepository repository;
  late int restaurantId;
  late int categoryId;

  const slug = 'catalog-admin-test';

  /// Holds `catalog.manage`, as the owner and manager system roles do.
  const manager = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'amer',
    capabilities: {PosCapability.catalogManage},
  );

  /// Holds it not. A cashier may never reprice the food.
  const cashier = PosStaff(
    id: 2,
    name: 'Rana A.',
    username: 'rana',
    capabilities: {PosCapability.operate},
  );

  setUp(() async {
    pg = await PgFixture.open('catalog_admin');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    final restaurant = await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES (@slug, 'Catalog Test') "
      'RETURNING id',
      parameters: {'slug': slug},
    );
    restaurantId = restaurant.first[0]! as int;

    final branch = await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    );

    repository = PostgresCatalogAdminRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branch.first[0]! as int,
    );

    final saved = await repository.saveCategory(
      const Category(id: 0, nameEn: 'Hot Drinks', slug: 'hot-drinks'),
      by: manager,
    );
    categoryId = saved.value!.id;
  });

  tearDown(() => pg.close());

  Product draft({
    int id = 0,
    String name = 'Espresso',
    int price = 3500,
    Money? discounted,
    int? taxGroupId,
    String? sku,
  }) =>
      Product(
        id: id,
        categoryId: categoryId,
        nameEn: name,
        price: Money(price),
        discountedPrice: discounted,
        taxGroupId: taxGroupId,
        sku: sku,
      );

  /// A named rate to put an item on.
  ///
  /// Inserted directly rather than through `saveTaxGroup`, which needs
  /// `settings.manage` — this suite's actor holds catalogue permissions, and
  /// borrowing a second capability here would test the wrong thing. Authoring
  /// rates has its own suite in `tax_groups_admin_test.dart`.
  Future<int> taxGroup(String name, int rateBp) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_tax_groups (restaurant_id, name_en, rate_bp) '
      'VALUES (@r, @name, @rate) RETURNING id',
      parameters: {'r': restaurantId, 'name': name, 'rate': rateBp},
    );
    return rows.first[0]! as int;
  }

  group('the rate an item is taxed at', () {
    test('an item can be put on a named rate', () async {
      // **`tax_group_id` was written by no statement in the app.** The column
      // has been on this table since Wave M and the catalogue query has read it
      // ever since — `COALESCE(p.tax_group_id, c.tax_group_id)` — so a
      // restaurant could define a zero-rated group and had no way to put a
      // bottle of water on it. Every item was charged the fallback rate.
      final zero = await taxGroup('Zero-rated', 0);

      final saved = await repository.saveProduct(
        draft(name: 'Water', taxGroupId: zero),
        by: manager,
      );
      expect(saved.succeeded, isTrue, reason: '${saved.refusal}');
      expect(saved.value!.taxGroupId, zero);
    });

    test('and the till reads it back off the catalogue', () async {
      // Through the repository the sale screen uses, not by inspecting rows:
      // what matters is what the cashier's ticket is priced with.
      final zero = await taxGroup('Zero-rated', 0);
      await repository.saveProduct(
        draft(name: 'Water', taxGroupId: zero),
        by: manager,
      );

      final menu = await PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: slug),
      ).load();
      final water = menu.products.firstWhere((p) => p.nameEn == 'Water');
      expect(water.taxGroupId, zero);
    });

    test('leaving it unset means the fallback, and stays unset', () async {
      // Which is what almost every item on a menu wants.
      final saved = await repository.saveProduct(draft(), by: manager);
      expect(saved.value!.taxGroupId, isNull);
    });

    test('an item can be moved back off a rate', () async {
      // The `clearTaxGroup` path. A null that means "back to the default" and a
      // null that means "unchanged" are different intentions, and `copyWith`
      // cannot tell them apart without being told.
      final reduced = await taxGroup('Reduced', 500);
      final saved = await repository.saveProduct(
        draft(taxGroupId: reduced),
        by: manager,
      );
      expect(saved.value!.taxGroupId, reduced);

      final cleared = await repository.saveProduct(
        saved.value!.copyWith(clearTaxGroup: true),
        by: manager,
      );
      expect(cleared.value!.taxGroupId, isNull);
    });

    test('an item keeps its rate across an unrelated edit', () async {
      // The regression that matters: a reprice must not silently move an item
      // back onto the standard rate.
      final zero = await taxGroup('Zero-rated', 0);
      final saved = await repository.saveProduct(
        draft(name: 'Water', taxGroupId: zero),
        by: manager,
      );

      final repriced = await repository.saveProduct(
        saved.value!.copyWith(price: const Money(1500)),
        by: manager,
      );
      expect(repriced.value!.price, const Money(1500));
      expect(repriced.value!.taxGroupId, zero);
    });
  });

  group('what it writes', () {
    test('a category and an item reach the till catalogue', () async {
      final saved = await repository.saveProduct(draft(), by: manager);
      expect(saved.value, isNotNull);

      // Read back through the SAME repository the sale screen uses, not by
      // inspecting rows: what matters is that the cashier sees it.
      final catalog = await PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: slug),
      ).load();

      expect(catalog.categories.single.nameEn, 'Hot Drinks');
      expect(catalog.products.single.nameEn, 'Espresso');
      expect(catalog.products.single.price.minor, 3500);
    });

    test('a price change is audited as a reprice, with both amounts', () async {
      final saved = await repository.saveProduct(draft(), by: manager);
      await repository.saveProduct(
        saved.value!.copyWith(price: const Money(4000)),
        by: manager,
      );

      final rows = await db.query(
        pg.config,
        "SELECT action, before_value->>'price_minor', after_value->>'price_minor' "
        'FROM pos_audit_events WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityProduct},
      );

      // Not a generic `product.updated`: "who changed what this costs, and
      // when" is the question a disputed receipt asks, and it must be findable
      // without reading every edit ever made.
      expect(rows.first[0], AuditAction.productRepriced);
      expect(rows.first[1], '3500');
      expect(rows.first[2], '4000');
    });

    test('renaming without touching the price is not a reprice', () async {
      final saved = await repository.saveProduct(draft(), by: manager);
      await repository.saveProduct(
        saved.value!.copyWith(nameEn: 'Doppio'),
        by: manager,
      );

      final rows = await db.query(
        pg.config,
        'SELECT action FROM pos_audit_events WHERE entity_type = @e '
        'ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityProduct},
      );
      expect(rows.first[0], AuditAction.productUpdated);
    });

    group('a section: off, back on, and deleted', () {
      Future<Category> section(String name) async => (await repository
              .saveCategory(Category(id: 0, nameEn: name), by: manager))
          .value!;

      test('a section that is off is listed for the switch, and not on the till', () async {
        final spare = await section('Seasonal');
        await repository.archiveCategory(spare, by: manager);

        expect((await repository.inactiveCategories()).map((c) => c.nameEn), ['Seasonal']);
        final grid = await PostgresCatalogRepository(
          database: db,
          config: pg.config.copyWith(tenantSlug: slug),
        ).load();
        expect(grid.categories.map((c) => c.nameEn), isNot(contains('Seasonal')));

        await repository.archiveCategory(spare, by: manager, restore: true);
        expect(await repository.inactiveCategories(), isEmpty);
      });

      test('an empty section is deleted, audited, and gone', () async {
        final spare = await section('Seasonal');
        final result = await repository.deleteCategory(spare, by: manager);
        expect(result.succeeded, isTrue, reason: '${result.refusal}');

        final rows = await db.query(
          pg.config,
          'SELECT count(*) FROM pos_categories WHERE id = @id',
          parameters: {'id': spare.id},
        );
        expect(rows.first[0], 0);
        final audit = await db.query(
          pg.config,
          'SELECT action FROM pos_audit_events WHERE entity_type = @e '
          'ORDER BY id DESC LIMIT 1',
          parameters: {'e': AuditAction.entityCategory},
        );
        expect(audit.first[0], AuditAction.categoryDeleted);
      });

      test('a section that holds an item cannot be deleted, even when it is off', () async {
        final saved = await repository.saveProduct(draft(), by: manager);
        final home = Category(id: categoryId, nameEn: 'Hot Drinks');

        final live = await repository.deleteCategory(home, by: manager);
        expect(live.refusal, isA<CatalogRefused>());
        expect((live.refusal! as CatalogRefused).problem, CatalogProblem.categoryHasItems);

        // Archiving the item does not free the section: a sale may name it.
        await repository.archiveProduct(saved.value!, by: manager);
        final off = await repository.deleteCategory(home, by: manager);
        expect((off.refusal! as CatalogRefused).problem, CatalogProblem.categoryHasItems);

        final rows = await db.query(
          pg.config,
          'SELECT count(*) FROM pos_categories WHERE id = @id',
          parameters: {'id': categoryId},
        );
        expect(rows.first[0], 1, reason: 'nothing was deleted');
      });

      test('a cashier cannot delete a section', () async {
        final spare = await section('Seasonal');
        final result = await repository.deleteCategory(spare, by: cashier);
        expect(result.succeeded, isFalse);
      });
    });

    test('archiving takes it off sale and keeps the row', () async {
      final saved = await repository.saveProduct(draft(), by: manager);
      final archived =
          await repository.archiveProduct(saved.value!, by: manager);

      expect(archived.value!.isAvailable, isFalse);
      // Still there: every past sale names this row, so it is hidden, never
      // removed.
      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_products WHERE id = @id',
        parameters: {'id': saved.value!.id},
      );
      expect(rows.first[0], 1);
    });
  });

  group('what it refuses', () {
    test('a cashier cannot touch the menu', () async {
      final result = await repository.saveProduct(draft(), by: cashier);

      expect(result.value, isNull);
      expect(result.refusal, isA<NotPermitted>());
      final rows = await db.query(
        pg.config, 'SELECT count(*) FROM pos_products');
      expect(rows.first[0], 0, reason: 'and nothing was written');
    });

    test('a cloud terminal cannot author at all', () async {
      // The provider will not build this outside offline, but the rule lives
      // here too: a rule that exists only in a provider is one the next caller
      // does not know about. On a cloud till the platform is the author and
      // the bootstrap seeder would wipe whatever this wrote.
      final cloud = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        restaurantId: restaurantId,
        offline: false,
      );

      final result = await cloud.saveProduct(draft(), by: manager);
      expect(result.refusal, isA<NotPermitted>());
    });

    test('an offer above the normal price is refused, as a code', () async {
      // Valid SQL — `price_minor >= 0` holds for both — and wrong arithmetic,
      // so the database cannot catch this one.
      final result = await repository.saveProduct(
        draft(price: 3500, discounted: const Money(4000)),
        by: manager,
      );

      expect(result.refusal, isA<CatalogRefused>());
      expect(
        (result.refusal! as CatalogRefused).problem,
        CatalogProblem.offerAbovePrice,
      );
    });

    /// Report 2026-10-24, F-2: a second item typed with a SKU the first already
    /// used reached `pos_products_sku_unique` and came back as an exception, so
    /// the editor froze on "Saving…". It is now a refusal, asked inside the save.
    test('a SKU another item already uses is refused, as a code', () async {
      final first = await repository.saveProduct(
        draft(sku: 'HD-001'),
        by: manager,
      );
      expect(first.refusal, isNull);

      final clash = await repository.saveProduct(
        draft(name: 'Tea', sku: ' HD-001 '),
        by: manager,
      );
      expect(clash.refusal, isA<CatalogRefused>());
      expect(
        (clash.refusal! as CatalogRefused).problem,
        CatalogProblem.skuTaken,
      );

      // Nothing was written for the refused one.
      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_products WHERE sku = @sku',
        parameters: {'sku': 'HD-001'},
      );
      expect(rows.first[0], 1);
    });

    /// XORD-014. The foreign key proves a category row exists, not whose it is
    /// or whether it is in use, so the repository asks.
    group('the category an item sits in', () {
      CatalogProblem? problemOf(AdminResult<Product> result) =>
          (result.refusal as CatalogRefused?)?.problem;

      Future<int> otherRestaurantsCategory() async {
        final other = await db.query(
          pg.config,
          "INSERT INTO pos_restaurants (slug, name) VALUES ('other-tenant', 'Other') "
          'RETURNING id',
        );
        final category = await db.query(
          pg.config,
          "INSERT INTO pos_categories (restaurant_id, name_en) "
          "VALUES (@r, 'Foreign') RETURNING id",
          parameters: {'r': other.first[0]! as int},
        );
        return category.first[0]! as int;
      }

      test("another restaurant's category is refused, nothing written", () async {
        final foreign = await otherRestaurantsCategory();

        final result = await repository.saveProduct(
          Product(
            id: 0,
            categoryId: foreign,
            nameEn: 'Smuggled',
            price: const Money(1000),
          ),
          by: manager,
        );

        expect(problemOf(result), CatalogProblem.categoryUnavailable);
        final rows = await db.query(
          pg.config,
          "SELECT count(*) FROM pos_products WHERE name_en = 'Smuggled'",
        );
        expect(rows.first[0], 0);
      });

      test('an archived category takes no new item and no moved item', () async {
        final kept = await repository.saveProduct(draft(), by: manager);
        final spare = await repository.saveCategory(
          const Category(id: 0, nameEn: 'Retired'),
          by: manager,
        );
        await repository.archiveCategory(spare.value!, by: manager);

        final created = await repository.saveProduct(
          Product(
            id: 0,
            categoryId: spare.value!.id,
            nameEn: 'Ghost',
            price: const Money(1000),
          ),
          by: manager,
        );
        final moved = await repository.saveProduct(
          Product(
            id: kept.value!.id,
            categoryId: spare.value!.id,
            nameEn: 'Espresso',
            price: const Money(3500),
          ),
          by: manager,
        );

        expect(problemOf(created), CatalogProblem.categoryUnavailable);
        expect(problemOf(moved), CatalogProblem.categoryUnavailable);
        final rows = await db.query(
          pg.config,
          'SELECT category_id FROM pos_products WHERE id = @id',
          parameters: {'id': kept.value!.id},
        );
        expect(rows.first[0], categoryId);
      });

      test('an item already in a category archived since can still be repriced',
          () async {
        final saved = await repository.saveProduct(draft(), by: manager);
        await repository.archiveCategory(
          Category(id: categoryId, nameEn: 'Hot Drinks'),
          by: manager,
        );

        final repriced = await repository.saveProduct(
          draft(id: saved.value!.id, price: 4000),
          by: manager,
        );

        expect(repriced.refusal, isNull);
        expect(repriced.value!.price.minor, 4000);
      });
    });

    test('the item that owns a SKU can be edited without clashing with itself',
        () async {
      final first = await repository.saveProduct(
        draft(sku: 'HD-001'),
        by: manager,
      );
      final edited = await repository.saveProduct(
        first.value!.copyWith(price: const Money(3600)),
        by: manager,
      );
      expect(edited.refusal, isNull);
      expect(edited.value!.price.minor, 3600);
    });

    test('blank SKUs never clash with each other', () async {
      final a = await repository.saveProduct(draft(sku: '  '), by: manager);
      final b = await repository.saveProduct(
        draft(name: 'Tea'),
        by: manager,
      );
      expect(a.refusal, isNull);
      expect(b.refusal, isNull);
    });

    test('an item edited on another till is refused, not overwritten', () async {
      final saved = await repository.saveProduct(draft(), by: manager);

      // The other till deletes it while this one holds a stale copy.
      await db.query(
        pg.config,
        'DELETE FROM pos_products WHERE id = @id',
        parameters: {'id': saved.value!.id},
      );

      final result = await repository.saveProduct(
        saved.value!.copyWith(price: const Money(9999)),
        by: manager,
      );
      expect(result.refusal, isA<EditedElsewhere>());
    });

    test('a nameless item is refused', () async {
      final result =
          await repository.saveProduct(draft(name: '   '), by: manager);
      expect(result.refusal, isA<CatalogRefused>());
      expect(
        (result.refusal! as CatalogRefused).problem,
        CatalogProblem.itemNameMissing,
      );
    });

    test('a nameless category is refused, as a code', () async {
      final result = await repository.saveCategory(
        const Category(id: 0, nameEn: '  '),
        by: manager,
      );
      expect(result.refusal, isA<CatalogRefused>());
      expect(
        (result.refusal! as CatalogRefused).problem,
        CatalogProblem.categoryNameMissing,
      );
    });
  });

  group('money rules', () {
    /// Holds `settings.manage` — a different job from pricing a plate.
    const owner = PosStaff(
      id: 3,
      name: 'Owner',
      username: 'owner',
      capabilities: {
        PosCapability.settingsManage,
        PosCapability.catalogManage,
      },
    );

    test('what is saved is what the ticket then prices with', () async {
      // The property that matters. An offline till with nothing written here
      // silently prices from a hardcoded 12%/14% and prints `deviceConfig` on
      // every slip; a LOSSY encode would be worse still, charging an amount
      // nobody chose.
      const wanted = TaxConfig(
        serviceBp: 1000,
        vatBp: 1400,
        serviceDineInOnly: true,
      );

      final saved = await repository.saveMoneyConfig(wanted, by: owner);
      expect(saved.value, isNotNull);

      final rows = await db.query(
        pg.config,
        'SELECT payload FROM pos_money_config WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      final readBack = MoneyConfigCodec.toTaxConfig(_payload(rows.first[0]));

      expect(readBack.serviceBp, 1000);
      expect(readBack.vatBp, 1400);
      expect(readBack.serviceDineInOnly, isTrue);
      // And it is no longer the device default the receipt has to disclose.
      expect(readBack.source, TaxSource.server);
    });

    test('a service charge on every order type round-trips', () async {
      // `serviceDineInOnly` defaults to TRUE, so a takeaway-inclusive charge
      // has to say so explicitly — which is exactly the bit that has to
      // survive the encode.
      const wanted = TaxConfig(
        serviceBp: 500,
        vatBp: 0,
        serviceDineInOnly: false,
      );
      await repository.saveMoneyConfig(wanted, by: owner);

      final rows = await db.query(
        pg.config,
        'SELECT payload FROM pos_money_config WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      final readBack = MoneyConfigCodec.toTaxConfig(_payload(rows.first[0]));

      expect(readBack.serviceDineInOnly, isFalse);
      expect(readBack.vatBp, 0, reason: 'no tax configured means no tax');
    });

    /// A default tax group at [rateBp], as `LocalBootstrap.seedTaxGroup` leaves
    /// every offline restaurant (setup writes it at 14%).
    Future<void> seedDefaultGroup(int rateBp) => db.query(
          pg.config,
          'INSERT INTO pos_tax_groups (restaurant_id, name_en, rate_bp, '
          '  is_default) VALUES (@r, @name, @rate, true)',
          parameters: {'r': restaurantId, 'name': 'VAT', 'rate': rateBp},
        );

    Future<List<int>> defaultGroupRates() async {
      final rows = await db.query(
        pg.config,
        'SELECT rate_bp FROM pos_tax_groups '
        'WHERE restaurant_id = @r AND is_default',
        parameters: {'r': restaurantId},
      );
      return [for (final row in rows) row[0]! as int];
    }

    test('setting VAT to 0 reaches the rate the ticket charges (XORD-027)',
        () async {
      // The bug: the VAT box saved `vat_bp` into the payload, but a ticket
      // prices from the default tax group whenever one exists — and setup
      // seeds one at 14% — so a restaurant that typed 0 went on charging 14%.
      await seedDefaultGroup(1400);

      final saved = await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 1200, vatBp: 0),
        by: owner,
      );
      expect(saved.value, isNotNull);
      expect(await defaultGroupRates(), [0],
          reason: 'one default group, now at 0');
    });

    test('any other rate moves the default group with it', () async {
      await seedDefaultGroup(1400);
      await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 0, vatBp: 1500),
        by: owner,
      );
      expect(await defaultGroupRates(), [1500]);

      await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 0, vatBp: 1250),
        by: owner,
      );
      expect(await defaultGroupRates(), [1250], reason: 'fractions survive');
    });

    test('only the default group moves; the other named rates stay', () async {
      await seedDefaultGroup(1400);
      await taxGroup('Reduced', 500);

      await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 0, vatBp: 0),
        by: owner,
      );

      final rows = await db.query(
        pg.config,
        'SELECT name_en, rate_bp FROM pos_tax_groups '
        'WHERE restaurant_id = @r ORDER BY name_en',
        parameters: {'r': restaurantId},
      );
      expect({for (final r in rows) r[0]! as String: r[1]! as int},
          {'Reduced': 500, 'VAT': 0});
    });

    test('with no default group it still saves, as before', () async {
      final saved = await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 0, vatBp: 0),
        by: owner,
      );
      expect(saved.value, isNotNull);
      expect(await defaultGroupRates(), isEmpty,
          reason: 'saving must not invent a group');
    });

    test('a rate over 100% is refused with a message, not a constraint error',
        () async {
      await seedDefaultGroup(1400);
      final result = await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 0, vatBp: 10001),
        by: owner,
      );
      expect(result.refusal, isA<CatalogInvalid>());
      expect(await defaultGroupRates(), [1400], reason: 'nothing changed');
    });

    test('the audit event records the group rate before and after', () async {
      await seedDefaultGroup(1400);
      await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 0, vatBp: 0),
        by: owner,
      );

      final rows = await db.query(
        pg.config,
        "SELECT before_value->>'default_group_rate_bp', "
        "       after_value->>'default_group_rate_bp' "
        'FROM pos_audit_events WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityMoney},
      );
      expect(rows.first[0], '1400');
      expect(rows.first[1], '0');
    });

    test('a manager without settings.manage cannot change the rates', () async {
      // `catalog.manage` prices a plate. It does not set the tax rate.
      final result = await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 9900, vatBp: 0),
        by: manager,
      );
      expect(result.refusal, isA<NotPermitted>());
    });

    test('the change is audited with both rates', () async {
      await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 1200, vatBp: 1400),
        by: owner,
      );
      await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 0, vatBp: 1400),
        by: owner,
      );

      final rows = await db.query(
        pg.config,
        "SELECT before_value->>'service_bp', after_value->>'service_bp' "
        'FROM pos_audit_events WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityMoney},
      );
      expect(rows.first[0], '1200');
      expect(rows.first[1], '0');
    });
  });

  group('the floor', () {
    const owner = PosStaff(
      id: 3,
      name: 'Owner',
      username: 'owner',
      capabilities: {PosCapability.settingsManage},
    );

    test('a table reaches the floor the waiter sees', () async {
      final saved = await repository.saveTable(
        const DiningTable(id: 0, label: 'T1', seats: 4, areaName: 'Terrace'),
        by: owner,
      );
      expect(saved.value!.label, 'T1');

      final rows = await db.query(
        pg.config,
        'SELECT label, seats, area_name FROM pos_dining_tables '
        'WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      expect(rows.first[0], 'T1');
      expect(rows.first[1], 4);
      expect(rows.first[2], 'Terrace');
    });

    test('two tables cannot share a label in one branch', () async {
      // The label is what a waiter says out loud. Two tables called 6 is an
      // argument at the pass, so the unique key is named rather than thrown.
      await repository.saveTable(
        const DiningTable(id: 0, label: 'T1', seats: 2),
        by: owner,
      );
      final second = await repository.saveTable(
        const DiningTable(id: 0, label: 'T1', seats: 4),
        by: owner,
      );

      expect(second.refusal, isA<CatalogInvalid>());
      expect((second.refusal! as CatalogInvalid).reason, contains('already'));
    });

    test('a table with no seats is refused', () async {
      final result = await repository.saveTable(
        const DiningTable(id: 0, label: 'T9', seats: 0),
        by: owner,
      );
      expect(result.refusal, isA<CatalogInvalid>());
    });

    test('a table need not say how many it seats', () async {
      final saved = await repository.saveTable(
        const DiningTable(id: 0, label: 'Pickup', seats: null),
        by: owner,
      );
      expect(saved.succeeded, isTrue, reason: '${saved.refusal}');
      expect(saved.value!.seats, isNull);

      // And it can be given a size later, and have it taken away again.
      final sized = await repository.saveTable(
        DiningTable(id: saved.value!.id, label: 'Pickup', seats: 6),
        by: owner,
      );
      expect(sized.value!.seats, 6);
      final cleared = await repository.saveTable(
        DiningTable(id: saved.value!.id, label: 'Pickup', seats: null),
        by: owner,
      );
      expect(cleared.value!.seats, isNull);

      final rows = await db.query(
        pg.config,
        'SELECT seats FROM pos_dining_tables WHERE id = @id',
        parameters: {'id': saved.value!.id},
      );
      expect(rows.single[0], isNull);
    });

    test('a batch with no seats stored is accepted, and the floor reads it back', () async {
      final result = await repository.createTables([
        for (var n = 1; n <= 3; n++) DiningTable(id: 0, label: 'Spot $n', seats: null),
      ], by: owner);
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect(result.value!.every((t) => t.seats == null), isTrue);
    });

    test('a stated count is still positive: the CHECK constraint stands', () async {
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_dining_tables (restaurant_id, branch_id, label, seats) '
          'VALUES (@r, (SELECT id FROM pos_branches WHERE restaurant_id = @r), @l, 0)',
          parameters: {'r': restaurantId, 'l': 'Zero'},
        ),
        throwsA(anything),
      );
    });

    test('archiving keeps the row, because tickets name it', () async {
      final saved = await repository.saveTable(
        const DiningTable(id: 0, label: 'T2', seats: 2),
        by: owner,
      );
      await repository.archiveTable(saved.value!, by: owner);

      final rows = await db.query(
        pg.config,
        'SELECT is_active FROM pos_dining_tables WHERE id = @id',
        parameters: {'id': saved.value!.id},
      );
      expect(rows.first[0], isFalse, reason: 'hidden');
      expect(rows.length, 1, reason: 'and still there');
    });

    test('a manager without settings.manage cannot move the furniture', () async {
      final result = await repository.saveTable(
        const DiningTable(id: 0, label: 'T3', seats: 2),
        by: manager,
      );
      expect(result.refusal, isA<NotPermitted>());
    });

    // XORD-006 — several tables in one operation.
    group('adding several at once', () {
      List<DiningTable> batch(int from, int count, {int seats = 2, String? area}) => [
        for (var n = from; n < from + count; n++)
          DiningTable(id: 0, label: 'Table $n', seats: seats, areaName: area),
      ];

      Future<List<String>> labels() async => [
        for (final row in await db.query(
          pg.config,
          'SELECT label FROM pos_dining_tables WHERE restaurant_id = @r '
          'ORDER BY id',
          parameters: {'r': restaurantId},
        ))
          row[0]! as String,
      ];

      test('ten from one gives exactly Table 1 to Table 10, with the shared settings', () async {
        final result = await repository.createTables(batch(1, 10, seats: 4, area: 'Hall'), by: owner);
        expect(result.succeeded, isTrue, reason: '${result.refusal}');
        expect(result.value!.map((t) => t.label), [for (var n = 1; n <= 10; n++) 'Table $n']);

        expect(await labels(), [for (var n = 1; n <= 10; n++) 'Table $n']);
        final rows = await db.query(
          pg.config,
          'SELECT DISTINCT seats, area_name FROM pos_dining_tables WHERE restaurant_id = @r',
          parameters: {'r': restaurantId},
        );
        expect(rows.length, 1);
        expect((rows.first[0], rows.first[1]), (4, 'Hall'));
      });

      test('one clash refuses the whole batch and writes nothing', () async {
        await repository.saveTable(const DiningTable(id: 0, label: 'Table 5', seats: 2), by: owner);

        final result = await repository.createTables(batch(1, 10), by: owner);
        expect(result.refusal, isA<CatalogInvalid>());
        expect((result.refusal! as CatalogInvalid).reason, contains('Table 5'));
        expect(await labels(), ['Table 5'], reason: 'not even Table 1 to 4');
      });

      test('a table that is out of service still holds its name', () async {
        final old = await repository.saveTable(const DiningTable(id: 0, label: 'Table 2', seats: 2), by: owner);
        await repository.archiveTable(old.value!, by: owner);

        final result = await repository.createTables(batch(1, 3), by: owner);
        expect(result.refusal, isA<CatalogInvalid>());
        expect(await labels(), ['Table 2']);
      });

      test('repeating the same batch after it worked does not double the floor', () async {
        await repository.createTables(batch(1, 10), by: owner);
        final again = await repository.createTables(batch(1, 10), by: owner);

        expect(again.refusal, isA<CatalogInvalid>());
        expect((await labels()).length, 10);
      });

      test('a repeat inside the batch, no seats, no label or no tables are all refused', () async {
        final twice = [...batch(1, 2), const DiningTable(id: 0, label: 'Table 1', seats: 2)];
        expect((await repository.createTables(twice, by: owner)).refusal, isA<CatalogInvalid>());
        expect((await repository.createTables(batch(1, 3, seats: 0), by: owner)).refusal, isA<CatalogInvalid>());
        expect(
          (await repository.createTables([const DiningTable(id: 0, label: '  ', seats: 2)], by: owner)).refusal,
          isA<CatalogInvalid>(),
        );
        expect((await repository.createTables(const [], by: owner)).refusal, isA<CatalogInvalid>());
        expect(await labels(), isEmpty);
      });

      test('100 is the most in one go', () async {
        expect((await repository.createTables(batch(1, 101), by: owner)).refusal, isA<CatalogInvalid>());
        expect(await labels(), isEmpty);

        final hundred = await repository.createTables(batch(1, 100), by: owner);
        expect(hundred.succeeded, isTrue, reason: '${hundred.refusal}');
        expect((await labels()).length, 100);
      });

      test('every table is audited, naming the size of the batch', () async {
        Future<int> created() async {
          final rows = await db.query(
            pg.config,
            'SELECT count(*) FROM pos_audit_events WHERE action = @a',
            parameters: {'a': AuditAction.tableCreated},
          );
          return int.parse('${rows.first[0]}');
        }

        final before = await created();
        await repository.createTables(batch(1, 3), by: owner);
        expect(await created(), before + 3);

        final last = await db.query(
          pg.config,
          'SELECT after_value FROM pos_audit_events WHERE action = @a ORDER BY id DESC LIMIT 1',
          parameters: {'a': AuditAction.tableCreated},
        );
        expect(last.first[0].toString(), contains('batch'));
      });

      test('settings.manage is needed, and a cloud till may not', () async {
        expect((await repository.createTables(batch(1, 2), by: manager)).refusal, isA<NotPermitted>());

        final cloud = PostgresCatalogAdminRepository(
          database: db,
          config: pg.config,
          restaurantId: restaurantId,
          offline: false,
        );
        expect((await cloud.createTables(batch(1, 2), by: owner)).refusal, isA<NotPermitted>());
        expect(await labels(), isEmpty);
      });
    });
  });
  group('importing a spreadsheet', () {
    /// The catalogue as the sale screen would read it back.
    Future<Catalog> catalog() => PostgresCatalogRepository(
          database: db,
          config: pg.config.copyWith(tenantSlug: slug),
        ).load();

    /// Builds a plan the way the dialog does — against the live catalogue,
    /// never against rows composed by hand. A test that hand-built its plan
    /// would pass while the screen it models could not work.
    Future<MenuImportPlan> plan(List<List<String>> rows) async {
      final menu = await catalog();
      return MenuImport.read(
        rows,
        existing: menu.products,
        categories: menu.categories,
      );
    }

    final header = MenuImport.templateHeader;

    test('a file the till has never seen becomes a menu', () async {
      final result = await repository.importMenu(
        await plan([
          header,
          ['Hot Drinks', 'Espresso', 'إسبريسو', '35.00', 'E-1', '', 'yes'],
          ['Cold Drinks', 'Iced Latte', '', '55.50', 'C-1', '', 'yes'],
        ]),
        by: manager,
      );

      expect(result.value!.categoriesCreated, 1, reason: 'Cold Drinks');
      expect(result.value!.productsCreated, 2);

      final menu = await catalog();
      expect(menu.categories.map((c) => c.nameEn), contains('Cold Drinks'));
      expect(
        menu.products.singleWhere((p) => p.nameEn == 'Iced Latte').price.minor,
        5550,
        reason: 'a price never goes through a double',
      );
    });

    test('a second run of the same file changes nothing', () async {
      final rows = [
        header,
        ['Hot Drinks', 'Espresso', '', '35.00', 'E-1', '', 'yes'],
      ];
      await repository.importMenu(await plan(rows), by: manager);

      // The second plan is built against what the first one wrote, which is
      // the whole point: a restaurant re-sends the same file all the time.
      final again = await plan(rows);
      expect(again.canApply, isFalse, reason: 'nothing left to do');

      final result = await repository.importMenu(again, by: manager);
      expect(result.refusal, isA<CatalogInvalid>());
      expect((await catalog()).products, hasLength(1));
    });

    test('a price change is audited as a reprice, not a generic update',
        () async {
      await repository.importMenu(
        await plan([
          header,
          ['Hot Drinks', 'Espresso', '', '35.00', 'E-1', '', 'yes'],
        ]),
        by: manager,
      );
      await repository.importMenu(
        await plan([
          header,
          ['Hot Drinks', 'Espresso', '', '40.00', 'E-1', '', 'yes'],
        ]),
        by: manager,
      );

      final rows = await db.query(
        pg.config,
        "SELECT action, after_value->>'source' FROM pos_audit_events "
        'WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityProduct},
      );
      expect(rows.first[0], AuditAction.productRepriced);
      expect(rows.first[1], 'import', reason: 'and says where it came from');
    });

    test('an item the file never mentions is left alone', () async {
      await repository.saveProduct(draft(name: 'Turkish Coffee'), by: manager);

      await repository.importMenu(
        await plan([
          header,
          ['Hot Drinks', 'Espresso', '', '35.00', 'E-1', '', 'yes'],
        ]),
        by: manager,
      );

      final menu = await catalog();
      expect(menu.products.map((p) => p.nameEn),
          containsAll(<String>['Turkish Coffee', 'Espresso']));
    });

    test('a file with one bad row writes nothing at all', () async {
      final result = await repository.importMenu(
        await plan([
          header,
          ['Hot Drinks', 'Espresso', '', '35.00', 'E-1', '', 'yes'],
          ['Hot Drinks', 'Macchiato', '', 'thirty', 'M-1', '', 'yes'],
        ]),
        by: manager,
      );

      // Half a menu is worse than none: nobody can tell which half landed.
      expect(result.refusal, isA<CatalogInvalid>());
      expect((await catalog()).products, isEmpty);
    });

    test('a cashier cannot import a menu', () async {
      final result = await repository.importMenu(
        await plan([
          header,
          ['Hot Drinks', 'Espresso', '', '35.00', 'E-1', '', 'yes'],
        ]),
        by: cashier,
      );
      expect(result.refusal, isA<NotPermitted>());
      expect((await catalog()).products, isEmpty);
    });

    test('a re-import that moves an item carries it to the new category',
        () async {
      await repository.importMenu(
        await plan([
          header,
          ['Hot Drinks', 'Espresso', '', '35.00', 'E-1', '', 'yes'],
        ]),
        by: manager,
      );
      await repository.importMenu(
        await plan([
          header,
          ['Cold Drinks', 'Espresso', '', '35.00', 'E-1', '', 'yes'],
        ]),
        by: manager,
      );

      final menu = await catalog();
      final cold = menu.categories.singleWhere((c) => c.nameEn == 'Cold Drinks');
      expect(menu.products.single.categoryId, cold.id);
    });
  });
}
