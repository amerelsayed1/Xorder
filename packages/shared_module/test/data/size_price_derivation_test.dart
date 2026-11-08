@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_catalog_repository.dart';
import 'package:shared_module/domain/models/catalog.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// The tile's price for an item with sizes, as the till reads it.
///
/// Two shapes reach this table and both must read right. The platform seeds an
/// item with its default size's regular and sale price on the item, and only
/// the charged figure on the option — so deriving from the option alone would
/// turn "90 struck to 80" into a bare 80. An offline-authored item whose price
/// no longer matches its sizes is the other shape, and that one is derived.
void main() {
  if (PgFixture.host == null) {
    test('size price derivation (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int categoryId;

  const slug = 'size-price-test';

  Future<int> insert(String sql, Map<String, Object?> parameters) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0]!
          as int;

  setUp(() async {
    pg = await PgFixture.open('size_price_derivation');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = await insert(
      "INSERT INTO pos_businesses (slug, name) VALUES (@slug, 'Sizes') "
      'RETURNING id',
      {'slug': slug},
    );
    categoryId = await insert(
      "INSERT INTO pos_categories (business_id, name_en) VALUES (@r, 'Burgers') "
      'RETURNING id',
      {'r': businessId},
    );
  });

  tearDown(() => pg.close());

  /// A burger with a Medium and a Large, laid down the way the cloud seeder
  /// writes it: one charged figure per option, no sale price column.
  Future<int> sizedBurger({required int price, int? discounted}) async {
    final product = await insert(
      'INSERT INTO pos_products (business_id, category_id, name_en, '
      '  price_minor, discounted_price_minor) '
      "VALUES (@r, @c, 'Burger', @price, @discounted) RETURNING id",
      {
        'r': businessId,
        'c': categoryId,
        'price': price,
        'discounted': discounted,
      },
    );
    final group = await insert(
      'INSERT INTO pos_modifier_groups (business_id, name_en, is_required, '
      "  is_variant) VALUES (@r, 'Size', true, true) RETURNING id",
      {'r': businessId},
    );
    for (final (name, charged, sort) in [('Medium', 8000, 1), ('Large', 11000, 2)]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_modifiers (group_id, name_en, price_delta_minor, '
        '  sort_order) VALUES (@g, @name, @charged, @sort)',
        parameters: {'g': group, 'name': name, 'charged': charged, 'sort': sort},
      );
    }
    await db.query(
      pg.config,
      'INSERT INTO pos_product_modifier_groups (product_id, group_id) '
      'VALUES (@p, @g)',
      parameters: {'p': product, 'g': group},
    );
    return product;
  }

  Future<Product> item(int id) async => (await PostgresCatalogRepository(
    database: db,
    config: pg.config.copyWith(tenantSlug: slug),
  ).load()).products.singleWhere((p) => p.id == id);

  test('a cloud-seeded item keeps its strike-through', () async {
    // Medium is 90 on sale at 80: the bundle puts 90/80 on the item and 80
    // on the option.
    final burger = await item(await sizedBurger(price: 9000, discounted: 8000));

    expect(burger.price, const Money(9000));
    expect(burger.discountedPrice, const Money(8000));
    expect(burger.effectivePrice, const Money(8000),
        reason: 'and it charges what the Medium charges');
  });

  test('an item whose price has drifted from its sizes is repriced', () async {
    // Typed as 50 before the sizes were added; the tile must say what an
    // untouched "add" charges, which is the Medium.
    final burger = await item(await sizedBurger(price: 5000));

    expect(burger.price, const Money(8000));
    expect(burger.discountedPrice, isNull);
  });
}
