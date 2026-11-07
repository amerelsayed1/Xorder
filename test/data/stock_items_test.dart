@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_stock_items_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/stock_item.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// What the business buys and counts (migration 40).
///
/// The claims worth a real database: a bought-only item is counted and never
/// reaches the cashier's menu; a menu item that is counted stays counted when
/// the Menu pane saves it; and an item on the menu changes only its unit from
/// the stock side.
void main() {
  if (PgFixture.host == null) {
    test('stock items (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const slug = 'stock-items-test';

  // Both, as an owner holds: the menu and the buying.
  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'amer',
    capabilities: {PosCapability.catalogManage, PosCapability.purchaseManage},
  );
  // The menu, not the buying.
  const menuOnly = PosStaff(
    id: 2,
    name: 'Nour A.',
    username: 'nour',
    capabilities: {PosCapability.catalogManage},
  );

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int categoryId;
  late PostgresCatalogAdminRepository menu;
  late PostgresStockItemsRepository stock;

  Future<Catalog> tillMenu() => PostgresCatalogRepository(
    database: db,
    config: pg.config.copyWith(tenantSlug: slug),
  ).load();

  setUp(() async {
    pg = await PgFixture.open('stock_items');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_businesses (slug, name) VALUES (@slug, 'Stock') "
              'RETURNING id',
              parameters: {'slug': slug},
            )).first[0]!
            as int;
    branchId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_branches (business_id, code, name) "
              "VALUES (@r, 'MAIN', 'Main') RETURNING id",
              parameters: {'r': businessId},
            )).first[0]!
            as int;

    menu = PostgresCatalogAdminRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
    stock = PostgresStockItemsRepository(
      database: db,
      config: pg.config,
      readDatabase: db,
      readConfig: pg.config,
      adminAvailable: true,
      businessId: businessId,
      branchId: branchId,
    );
    categoryId = (await menu.saveCategory(
      const Category(id: 0, nameEn: 'Drinks', slug: 'drinks'),
      by: owner,
    )).value!.id;
  });

  tearDown(() => pg.close());

  test('a bought-only item is counted, and never on the cashier\'s menu', () async {
    final saved = await stock.save(
      const StockItem(
        id: 0,
        nameEn: 'Chicken',
        nameAr: 'فراخ',
        unit: QuantityUnit.kilogram,
      ),
      by: owner,
    );
    expect(saved.succeeded, isTrue, reason: '${saved.refusal}');

    final counted = await stock.all();
    expect(counted.single.nameEn, 'Chicken');
    expect(counted.single.unit, QuantityUnit.kilogram);
    expect(counted.single.onMenu, isFalse);

    final products = (await tillMenu()).products;
    expect(
      products.map((p) => p.nameEn),
      isNot(contains('Chicken')),
      reason: 'no category, so the menu query cannot reach it',
    );
  });

  test('a menu item that is counted stays counted when the Menu pane saves it',
      () async {
    // The Menu pane builds its editor from the till's catalogue. If that row
    // did not carry the stock fields, saving the price would quietly stop the
    // water being counted.
    await menu.saveProduct(
      Product(
        id: 0,
        categoryId: categoryId,
        nameEn: 'Bottled water',
        price: const Money(1000),
        isStocked: true,
        stockUnit: QuantityUnit.each,
      ),
      by: owner,
    );

    final fromTill = (await tillMenu()).products.single;
    expect(fromTill.isStocked, isTrue);

    await menu.saveProduct(
      fromTill.copyWith(price: const Money(1200)),
      by: owner,
    );

    final counted = await stock.all();
    expect(counted.single.nameEn, 'Bottled water');
    expect(counted.single.onMenu, isTrue);
  });

  test('from the stock side, a menu item changes only its unit', () async {
    final water = (await menu.saveProduct(
      Product(
        id: 0,
        categoryId: categoryId,
        nameEn: 'Bottled water',
        price: const Money(1000),
        isStocked: true,
      ),
      by: owner,
    )).value!;

    await stock.save(
      StockItem(
        id: water.id,
        nameEn: 'Renamed from the wrong door',
        unit: QuantityUnit.pack,
        onMenu: true,
      ),
      by: owner,
    );

    final after = (await stock.all()).single;
    expect(after.unit, QuantityUnit.pack);
    expect(after.nameEn, 'Bottled water');
  });

  test('an uncategorised product must be a counted one', () async {
    // Otherwise it is a row nobody can find — not on the menu, not in stock.
    await expectLater(
      db.query(
        pg.config,
        'INSERT INTO pos_products (business_id, category_id, name_en, '
        "  price_minor) VALUES (@r, NULL, 'Lost', 0)",
        parameters: {'r': businessId},
      ),
      throwsA(isA<PosDbException>()),
    );
  });

  test('what is bought is the buyer\'s', () async {
    final result = await stock.save(
      const StockItem(id: 0, nameEn: 'Oil', unit: QuantityUnit.litre),
      by: menuOnly,
    );
    expect(result.refusal, isA<NotPermitted>());
  });

  test('a SKU already in use is said as a sentence', () async {
    await stock.save(
      const StockItem(id: 0, nameEn: 'Oil', sku: 'OIL-1'),
      by: owner,
    );
    final clash = await stock.save(
      const StockItem(id: 0, nameEn: 'More oil', sku: 'OIL-1'),
      by: owner,
    );
    expect(clash.refusal, isA<CatalogInvalid>());
  });

  group('the unit, once stock is held in it', () {
    // 10 kilos relabelled as boxes is 10 boxes nobody bought. There is no
    // conversion, so while stock is held the unit it is held in is the unit.
    Future<void> hold(int productId, int milli, QuantityUnit unit) => db.query(
      pg.config,
      'INSERT INTO pos_stock_levels (business_id, branch_id, product_id, '
      '  quantity_milli, unit, average_cost_minor) '
      'VALUES (@r, @b, @p, @q, @u, 4000)',
      parameters: {
        'r': businessId,
        'b': branchId,
        'p': productId,
        'q': milli,
        'u': unit.wire,
      },
    );

    Future<StockItem> chicken() async => (await stock.save(
      const StockItem(id: 0, nameEn: 'Chicken', unit: QuantityUnit.kilogram),
      by: owner,
    )).value!;

    test('an item holding stock keeps its unit', () async {
      final item = await chicken();
      await hold(item.id, 10000, QuantityUnit.kilogram);

      final result = await stock.save(
        StockItem(id: item.id, nameEn: 'Chicken', unit: QuantityUnit.box),
        by: owner,
      );
      expect(
        result.refusal,
        isA<StockHeldInAnotherUnit>()
            .having((r) => r.item, 'item', 'Chicken')
            .having((r) => r.held.milli, 'held', 10000)
            .having((r) => r.held.unit, 'held in', QuantityUnit.kilogram)
            .having((r) => r.asked, 'asked', QuantityUnit.box),
      );
      expect((await stock.all()).single.unit, QuantityUnit.kilogram);
    });

    test('and renaming it is still allowed', () async {
      final item = await chicken();
      await hold(item.id, 10000, QuantityUnit.kilogram);

      final result = await stock.save(
        StockItem(
          id: item.id,
          nameEn: 'Chicken breast',
          unit: QuantityUnit.kilogram,
        ),
        by: owner,
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
    });

    test('from the menu side too', () async {
      // The Menu pane writes `stock_unit` as well — a second door to the same
      // mistake.
      final water = (await menu.saveProduct(
        Product(
          id: 0,
          categoryId: categoryId,
          nameEn: 'Bottled water',
          price: const Money(1000),
          isStocked: true,
          stockUnit: QuantityUnit.each,
        ),
        by: owner,
      )).value!;
      await hold(water.id, 24000, QuantityUnit.each);

      final fromStock = await stock.save(
        StockItem(
          id: water.id,
          nameEn: 'Bottled water',
          unit: QuantityUnit.pack,
          onMenu: true,
        ),
        by: owner,
      );
      expect(fromStock.refusal, isA<StockHeldInAnotherUnit>());

      final fromMenu = await menu.saveProduct(
        water.copyWith(stockUnit: QuantityUnit.pack),
        by: owner,
      );
      expect(fromMenu.refusal, isA<StockHeldInAnotherUnit>());

      // A price change on the same item is not a unit change, and passes.
      final repriced = await menu.saveProduct(
        water.copyWith(price: const Money(1200)),
        by: owner,
      );
      expect(repriced.succeeded, isTrue, reason: '${repriced.refusal}');
      expect((await stock.all()).single.unit, QuantityUnit.each);
    });

    test('once none is held, it can change', () async {
      final item = await chicken();
      await hold(item.id, 0, QuantityUnit.kilogram);

      final result = await stock.save(
        StockItem(id: item.id, nameEn: 'Chicken', unit: QuantityUnit.box),
        by: owner,
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect((await stock.all()).single.unit, QuantityUnit.box);
    });

    test('the database refuses it round the repository', () async {
      final item = await chicken();
      await hold(item.id, 10000, QuantityUnit.kilogram);

      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_products SET stock_unit = 'box' WHERE id = @id",
          parameters: {'id': item.id},
        ),
        throwsA(
          isA<PosDbException>().having(
            (e) => '${e.raw}',
            'message',
            contains('unit cannot change'),
          ),
        ),
      );
      expect((await stock.all()).single.unit, QuantityUnit.kilogram);
    });
  });

  test('every save is on the audit trail', () async {
    await stock.save(
      const StockItem(id: 0, nameEn: 'Gas cylinder', unit: QuantityUnit.box),
      by: owner,
    );
    final rows = await db.query(
      pg.config,
      "SELECT after_value->>'name' FROM pos_audit_events "
      'WHERE business_id = @r AND action = @a',
      parameters: {'r': businessId, 'a': AuditAction.stockItemSaved},
    );
    expect(rows.single.single, 'Gas cylinder');
  });
}
