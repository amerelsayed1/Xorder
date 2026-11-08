@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_catalog_repository.dart';
import 'package:shared_module/data/postgres/postgres_orders_repository.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// Migration 18 — a meal at one price.
void main() {
  if (PgFixture.host == null) {
    test('combo schema (skipped — set POS_PG_HOST)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int branchId;
  late int categoryId;
  late int sandwichId;
  late int chipsId;
  late int comboId;
  const terminal = '88888888-8888-4888-8888-888888888888';

  Future<int> insertProduct(String name, int price) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_products (business_id, category_id, name_en, '
      '  price_minor) VALUES (@r, @c, @n, @p) RETURNING id',
      parameters: {
        'r': businessId,
        'c': categoryId,
        'n': name,
        'p': price,
      },
    );
    return rows.first[0] as int;
  }

  Future<int> insertGroup(int combo, String name, {int min = 1, int max = 1}) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_combo_groups (combo_id, name_en, min_select, '
      '  max_select) VALUES (@c, @n, @min, @max) RETURNING id',
      parameters: {'c': combo, 'n': name, 'min': min, 'max': max},
    );
    return rows.first[0] as int;
  }

  Future<void> insertOption(int groupId, int productId, {int delta = 0}) =>
      db.query(
        pg.config,
        'INSERT INTO pos_combo_options (combo_group_id, product_id, '
        '  price_delta_minor) VALUES (@g, @p, @d)',
        parameters: {'g': groupId, 'p': productId, 'd': delta},
      );

  setUp(() async {
    pg = await PgFixture.open('combo_schema');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    // Combos first, explicitly. `pos_combo_options.product_id` is RESTRICT —
    // deliberately, so deleting a product cannot silently empty a combo group
    // — and that also blocks the cascade from `DELETE FROM pos_businesses`,
    // because Postgres has no way to know this one is a teardown.
    await db.query(
      pg.config,
      'TRUNCATE pos_combos, pos_orders, pos_invoice_sequences '
      'RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_businesses (slug, name) "
                  "VALUES ('cb', 'Combos') RETURNING id",
                ))
                .first[0]
            as int;
    branchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (business_id, code, name) "
                  "VALUES (@r, 'CB1', 'Main') RETURNING id",
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;
    categoryId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_categories (business_id, name_en) '
                  "VALUES (@r, 'Meals') RETURNING id",
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;

    sandwichId = await insertProduct('Chicken sandwich', 4500);
    chipsId = await insertProduct('Chips', 2500);

    comboId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_combos (business_id, category_id, '
                  "  name_en, price_minor) VALUES (@r, @c, 'Lunch meal', 6000) "
                  'RETURNING id',
                  parameters: {'r': businessId, 'c': categoryId},
                ))
                .first[0]
            as int;

    final mains = await insertGroup(comboId, 'Sandwich');
    await insertOption(mains, sandwichId);
    final sides = await insertGroup(comboId, 'Side');
    await insertOption(sides, chipsId, delta: 500);
  });

  tearDown(() => pg.close());

  group('the schema', () {
    test('an option cannot appear twice in one group', () async {
      final extra = await insertGroup(comboId, 'Extra');
      await insertOption(extra, sandwichId);
      await expectLater(insertOption(extra, sandwichId), throwsA(anything));
    });

    test('a minimum above the maximum is refused', () async {
      await expectLater(
        insertGroup(comboId, 'Impossible', min: 3, max: 2),
        throwsA(anything),
      );
    });

    test('a negative combo price is refused', () async {
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_combos (business_id, category_id, name_en, '
          "  price_minor) VALUES (@r, @c, 'Free lunch', -1)",
          parameters: {'r': businessId, 'c': categoryId},
        ),
        throwsA(anything),
      );
    });

    test('deleting a product used by a combo is refused', () async {
      // RESTRICT, not CASCADE: it would silently empty a group and leave a
      // meal nobody can complete.
      await expectLater(
        db.query(
          pg.config,
          'DELETE FROM pos_products WHERE id = @id',
          parameters: {'id': sandwichId},
        ),
        throwsA(anything),
      );
    });

    test('deleting a combo takes its groups and options with it', () async {
      await db.query(
        pg.config,
        'DELETE FROM pos_combos WHERE id = @id',
        parameters: {'id': comboId},
      );
      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_combo_groups WHERE combo_id = @id',
        parameters: {'id': comboId},
      );
      expect(rows.first[0], 0);
    });
  });

  group('the catalogue', () {
    test('loads a combo with its groups and options', () async {
      final catalog = await PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: 'cb'),
        branchId: branchId,
      ).load();

      expect(catalog.combos, hasLength(1));
      final combo = catalog.combos.single;
      expect(combo.nameEn, 'Lunch meal');
      expect(combo.price.minor, 6000);
      expect(combo.groups, hasLength(2));
      expect(combo.groups.first.options.single.product.nameEn,
          'Chicken sandwich');
      expect(combo.groups.last.options.single.priceDelta.minor, 500);
    });

    test('a combo appears on its category, beside the products', () async {
      final catalog = await PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: 'cb'),
        branchId: branchId,
      ).load();

      expect(catalog.combosIn(categoryId), hasLength(1));
      expect(catalog.combosIn(999), isEmpty);
      expect(catalog.combosIn(null), hasLength(1));
    });
  });

  group('settling a meal', () {
    test('writes the combo price and what it was made of', () async {
      final catalog = await PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: 'cb'),
        branchId: branchId,
      ).load();
      final combo = catalog.combos.single;

      var ticket = Ticket(
        id: '99999999-9999-4999-8999-000000000001',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
      );
      ticket = TicketEngine.addComboLine(
        ticket,
        combo,
        chosen: [
          combo.groups.first.options.single,
          combo.groups.last.options.single,
        ],
      ).ticket!;
      ticket = ticket.copyWith(
        tenders: const [
          Tender(typeId: 1, label: 'Cash', amount: Money(6500)),
        ],
      );

      final result = await PostgresOrdersRepository(
        database: db,
        config: pg.config,
        context: PosWriteContext(
          businessId: businessId,
          branchId: branchId,
          terminalId: terminal,
          branchCode: 'CB1',
        ),
      ).submit(ticket);

      final lines = await db.query(
        pg.config,
        'SELECT id, menu_item_id, combo_id, name_snapshot, unit_price_minor '
        'FROM pos_order_lines WHERE order_id = @id',
        parameters: {'id': result.serverId},
      );
      expect(lines, hasLength(1));

      // 60.00 for the meal plus a 5.00 upgrade — not 70.00, which is what the
      // parts cost.
      expect(lines.first[4], 6500);
      // No menu item: a meal is not one of them.
      expect(lines.first[1], isNull);
      expect(lines.first[2], comboId);
      expect(lines.first[3], 'Lunch meal');

      final items = await db.query(
        pg.config,
        'SELECT menu_item_id, name_snapshot FROM pos_order_line_items '
        'WHERE order_line_id = @id ORDER BY sort_order',
        parameters: {'id': lines.first[0]},
      );
      // So the kitchen knows what to make.
      expect(items, hasLength(2));
      expect(items.first[0], sandwichId);
      expect(items.first[1], 'Chicken sandwich');
      expect(items.last[1], 'Chips');
    });
  });
}
