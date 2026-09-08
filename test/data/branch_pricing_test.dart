@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_repository.dart';

import 'pg_fixture.dart';

/// Migration 17 — what a branch charges.
///
/// Delivery prices differ from dine-in almost universally, and a two-branch
/// group rarely prices both shops the same. The schema had one price per
/// product per restaurant and no way to say otherwise.
void main() {
  if (PgFixture.host == null) {
    test('branch pricing (skipped — set POS_PG_HOST)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int mainId;
  late int secondId;
  late int categoryId;
  late int productId;

  Future<void> override({
    required int? branch,
    String? orderType,
    int? price,
    bool available = true,
  }) => db.query(
    pg.config,
    'INSERT INTO pos_product_prices (product_id, branch_id, order_type, '
    '  price_minor, is_available) VALUES (@p, @b, @t, @price, @avail)',
    parameters: {
      'p': productId,
      'b': branch,
      't': orderType,
      'price': price,
      'avail': available,
    },
  );

  setUp(() async {
    pg = await PgFixture.open('branch_pricing');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_restaurants (slug, name) "
                  "VALUES ('bp', 'Branch Pricing') RETURNING id",
                ))
                .first[0]
            as int;

    mainId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (restaurant_id, code, name) "
                  "VALUES (@r, 'BP1', 'Main') RETURNING id",
                  parameters: {'r': restaurantId},
                ))
                .first[0]
            as int;
    secondId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (restaurant_id, code, name) "
                  "VALUES (@r, 'BP2', 'Second') RETURNING id",
                  parameters: {'r': restaurantId},
                ))
                .first[0]
            as int;
    categoryId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_categories (restaurant_id, name_en) '
                  "VALUES (@r, 'Mains') RETURNING id",
                  parameters: {'r': restaurantId},
                ))
                .first[0]
            as int;
    productId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_products (restaurant_id, category_id, '
                  "  name_en, price_minor) VALUES (@r, @c, 'Koshari', 5000) "
                  'RETURNING id',
                  parameters: {'r': restaurantId, 'c': categoryId},
                ))
                .first[0]
            as int;
  });

  tearDown(() => pg.close());

  Future<int> priceAt(int? branch) async {
    final catalog = await PostgresCatalogRepository(
      database: db,
      // The slug is how a till names its restaurant — every read repository
      // resolves the tenant from it before it can ask anything.
      config: pg.config.copyWith(tenantSlug: 'bp'),
      branchId: branch,
    ).load();
    return catalog.products.single.price.minor;
  }

  Future<bool> availableAt(int? branch) async {
    final catalog = await PostgresCatalogRepository(
      database: db,
      config: pg.config.copyWith(tenantSlug: 'bp'),
      branchId: branch,
    ).load();
    return catalog.products.single.isAvailable;
  }

  group('resolution', () {
    test('no override means the menu price, everywhere', () async {
      expect(await priceAt(mainId), 5000);
      expect(await priceAt(secondId), 5000);
    });

    test('a branch override applies at that branch only', () async {
      await override(branch: secondId, price: 6500);
      expect(await priceAt(mainId), 5000);
      expect(await priceAt(secondId), 6500);
    });

    test('a branch can withdraw a product without deleting it', () async {
      // Run out for the season at one shop; the others still sell it.
      await override(branch: secondId, price: 5000, available: false);
      expect(await availableAt(mainId), isTrue);
      expect(await availableAt(secondId), isFalse);
    });

    test('a product unavailable on the menu stays unavailable everywhere', () async {
      await db.query(
        pg.config,
        'UPDATE pos_products SET is_available = false WHERE id = @id',
        parameters: {'id': productId},
      );
      // An override can withdraw, never reinstate: the menu's answer is the
      // ceiling, and a branch quietly selling something head office pulled is
      // the wrong direction to be wrong in.
      await override(branch: mainId, price: 5000);
      expect(await availableAt(mainId), isFalse);
    });

    test('an unprovisioned terminal falls back to the menu price', () async {
      await override(branch: mainId, price: 9999);
      expect(await priceAt(null), 5000);
    });
  });

  group('what the schema refuses', () {
    test('two branch-wide prices for one product', () async {
      // NULLs are distinct in a UNIQUE constraint, so this needs its own
      // partial index — without it a product could carry two prices at one
      // branch and nothing would say which was meant.
      await override(branch: mainId, price: 6000);
      await expectLater(
        override(branch: mainId, price: 7000),
        throwsA(anything),
      );
    });

    test('two prices for one branch and channel', () async {
      await override(branch: mainId, orderType: 'delivery', price: 6000);
      await expectLater(
        override(branch: mainId, orderType: 'delivery', price: 7000),
        throwsA(anything),
      );
    });

    test('a branch price and a channel price coexist', () async {
      await override(branch: mainId, price: 6000);
      await override(branch: mainId, orderType: 'delivery', price: 7000);
    });

    test('an unknown order type', () async {
      await expectLater(
        override(branch: mainId, orderType: 'catering', price: 6000),
        throwsA(anything),
      );
    });

    test('a negative price', () async {
      await expectLater(
        override(branch: mainId, price: -100),
        throwsA(anything),
      );
    });

    test('a row that overrides nothing', () async {
      // A row somebody would later wonder about.
      await expectLater(override(branch: mainId), throwsA(anything));
    });

    test('deleting a branch takes its overrides with it', () async {
      await override(branch: secondId, price: 6500);
      await db.query(
        pg.config,
        'DELETE FROM pos_branches WHERE id = @id',
        parameters: {'id': secondId},
      );
      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_product_prices WHERE product_id = @p',
        parameters: {'p': productId},
      );
      expect(rows.first[0], 0);
    });
  });
}
