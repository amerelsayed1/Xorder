@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_stock_levels_repository.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// What each counted item stands at in one branch.
void main() {
  if (PgFixture.host == null) {
    test('stock levels (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int categoryId;
  late PostgresStockLevelsRepository levels;

  Future<int> id(String sql, Map<String, Object?> p) async =>
      (await db.query(pg.config, sql, parameters: p)).first[0]! as int;

  Future<int> product(
    String name, {
    bool onMenu = false,
    bool stocked = true,
    String? unit,
  }) => id(
    'INSERT INTO pos_products (business_id, category_id, name_en, '
    '  price_minor, is_stocked, stock_unit) '
    'VALUES (@r, @c, @n, 0, @s, @u) RETURNING id',
    {
      'r': businessId,
      'c': onMenu ? categoryId : null,
      'n': name,
      's': stocked,
      'u': unit,
    },
  );

  Future<void> holds(int productId, int branch, int milli, String unit, int cost) =>
      db.query(
        pg.config,
        'INSERT INTO pos_stock_levels (business_id, branch_id, product_id, '
        '  quantity_milli, unit, average_cost_minor) '
        'VALUES (@r, @b, @p, @q, @u, @c)',
        parameters: {
          'r': businessId,
          'b': branch,
          'p': productId,
          'q': milli,
          'u': unit,
          'c': cost,
        },
      );

  setUp(() async {
    pg = await PgFixture.open('stock_levels');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'TRUNCATE pos_stock_levels, pos_stock_movements');
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = await id(
      "INSERT INTO pos_businesses (slug, name) VALUES ('levels', 'Levels') "
      'RETURNING id',
      {},
    );
    branchId = await id(
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'L1', 'Main') RETURNING id",
      {'r': businessId},
    );
    otherBranchId = await id(
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'L2', 'Second') RETURNING id",
      {'r': businessId},
    );
    categoryId = await id(
      "INSERT INTO pos_categories (business_id, name_en) "
      "VALUES (@r, 'Drinks') RETURNING id",
      {'r': businessId},
    );
    levels = PostgresStockLevelsRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  test('what is here, in its unit, valued at its average', () async {
    final chicken = await product('Chicken', unit: 'kg');
    await holds(chicken, branchId, 12500, 'kg', 9500);

    final level = (await levels.all()).single;
    expect(level.nameEn, 'Chicken');
    expect(level.onHand, const Quantity(12500, unit: QuantityUnit.kilogram));
    expect(level.value, const Money(118750), reason: '12.5 × 95.00');
  });

  test('counted and never received stands at nothing, in its unit', () async {
    await product('Bottled water', onMenu: true, unit: 'ea');

    final level = (await levels.all()).single;
    expect(level.onHand.isZero, isTrue);
    expect(level.onHand.unit, QuantityUnit.each);
    expect(level.onMenu, isTrue);
  });

  test('a menu item nobody counts is not on the list', () async {
    await product('Espresso', onMenu: true, stocked: false);
    expect(await levels.all(), isEmpty);
  });

  test('another branch\'s stock is its own', () async {
    final water = await product('Bottled water', onMenu: true, unit: 'ea');
    await holds(water, otherBranchId, 10000, 'ea', 500);

    expect((await levels.all()).single.onHand.isZero, isTrue);
  });

  test('stock that exists is reported, even once it stops being counted',
      () async {
    final water = await product('Bottled water', onMenu: true, unit: 'ea');
    await holds(water, branchId, 6000, 'ea', 500);
    await db.query(
      pg.config,
      'UPDATE pos_products SET is_stocked = false WHERE id = @id',
      parameters: {'id': water},
    );

    expect((await levels.all()).single.onHand.milli, 6000);
  });
}
