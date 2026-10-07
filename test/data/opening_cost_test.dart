@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_receiving_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/stock_costing.dart';

import 'pg_fixture.dart';

/// The first cost of an item nothing has costed, against the ledger it writes.
///
/// What only a database can answer: that the movement is a real row with a
/// quantity of zero (which migration 52 permits for `opening` alone), that the
/// level row is created or updated without its quantity moving, that a second
/// attempt finds the item costed, and that nothing at all is written on a
/// refusal.
void main() {
  if (PgFixture.host == null) {
    test('opening cost (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresReceivingRepository stock;
  late int restaurantId;
  late int branchId;
  late int ketchup; // stocked, never received: no level row at all
  late int mayo; //    stocked, 5 on hand, never costed
  late int cola; //    stocked, already costed at 5.00
  late int burger; //  not counted
  late int theirs; //  another restaurant's

  const manager = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.purchaseManage},
    ),
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.operate},
    ),
  );

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0] as int;

  Future<int> product(int restaurant, String name, {required bool stocked}) =>
      scalar(
        'INSERT INTO pos_products (restaurant_id, category_id, name_en, '
        '  price_minor, is_stocked) '
        'VALUES (@r, (SELECT id FROM pos_categories WHERE restaurant_id = @r), '
        '  @n, 1000, @s) RETURNING id',
        {'r': restaurant, 'n': name, 's': stocked},
      );

  Future<void> level(int productId, int milli, int cost) => db.query(
    pg.config,
    'INSERT INTO pos_stock_levels (restaurant_id, branch_id, product_id, '
    '  quantity_milli, unit, average_cost_minor) '
    "VALUES (@r, @b, @p, @q, 'ea', @c)",
    parameters: {
      'r': restaurantId,
      'b': branchId,
      'p': productId,
      'q': milli,
      'c': cost,
    },
  );

  PostgresReceivingRepository repository({bool admin = true}) =>
      PostgresReceivingRepository(
        database: db,
        config: pg.config,
        adminAvailable: admin,
        restaurantId: restaurantId,
        branchId: branchId,
      );

  Future<List<List<Object?>>> movements(int productId) async => [
    for (final r in await db.query(
      pg.config,
      'SELECT kind, quantity_milli, unit_cost_minor, balance_milli, '
      '       average_cost_minor, created_by '
      'FROM pos_stock_movements WHERE product_id = @p ORDER BY id',
      parameters: {'p': productId},
    ))
      r.toList(),
  ];

  Future<List<Object?>> levelOf(int productId) async {
    final rows = await db.query(
      pg.config,
      'SELECT quantity_milli, average_cost_minor, unit FROM pos_stock_levels '
      'WHERE branch_id = @b AND product_id = @p',
      parameters: {'b': branchId, 'p': productId},
    );
    return rows.isEmpty ? const [] : rows.first.toList();
  }

  Future<int> audits() async => scalar(
    'SELECT count(*) FROM pos_audit_events '
    'WHERE restaurant_id = @r AND action = @a',
    {'r': restaurantId, 'a': AuditAction.stockCostSet},
  );

  Future<OpeningCostProblem?> refusedWith(
    int productId,
    int cost, {
    PosStaff by = manager,
  }) async {
    final result = await stock.setOpeningCost(
      productId: productId,
      unitCost: Money(cost),
      by: by,
    );
    final refusal = result.refusal;
    return refusal is OpeningCostRefused ? refusal.problem : null;
  }

  setUp(() async {
    pg = await PgFixture.open('opening_cost');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_combos');
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = await scalar(
      "INSERT INTO pos_restaurants (slug, name) VALUES ('oc', 'OC') RETURNING id",
    );
    branchId = await scalar(
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      {'r': restaurantId},
    );
    await db.query(
      pg.config,
      'INSERT INTO pos_categories (restaurant_id, name_en, slug) '
      "VALUES (@r, 'Menu', 'menu')",
      parameters: {'r': restaurantId},
    );
    ketchup = await product(restaurantId, 'Ketchup', stocked: true);
    mayo = await product(restaurantId, 'Mayo', stocked: true);
    cola = await product(restaurantId, 'Cola', stocked: true);
    burger = await product(restaurantId, 'Burger', stocked: false);
    await level(mayo, 5000, 0);
    await level(cola, 48000, 500);

    final other = await scalar(
      "INSERT INTO pos_restaurants (slug, name) VALUES ('ot', 'OT') RETURNING id",
    );
    await db.query(
      pg.config,
      'INSERT INTO pos_categories (restaurant_id, name_en, slug) '
      "VALUES (@r, 'Theirs', 'theirs')",
      parameters: {'r': other},
    );
    theirs = await product(other, 'Secret', stocked: true);

    stock = repository();
  });

  tearDown(() => pg.close());

  group('an item on the shelf with no cost', () {
    test('gets its cost, and its quantity does not move', () async {
      final result = await stock.setOpeningCost(
        productId: mayo,
        unitCost: const Money(350),
        by: manager,
      );

      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect(result.value!.unitCost.minor, 350);
      expect(result.value!.onHand.milli, 5000);
      expect((await levelOf(mayo)).take(2), [5000, 350]);
    });

    test('is recorded as an opening movement of nothing, with the position', () async {
      await stock.setOpeningCost(
        productId: mayo,
        unitCost: const Money(350),
        by: manager,
        note: 'counted on the way in',
      );

      final rows = await movements(mayo);
      expect(rows, hasLength(1));
      // kind, quantity, unit cost, resulting balance, resulting average.
      expect(rows.single.take(5), ['opening', 0, 350, 5000, 350]);
    });

    test('and is audited, with what it was and what it became', () async {
      await stock.setOpeningCost(
        productId: mayo,
        unitCost: const Money(350),
        by: manager,
      );

      final rows = await db.query(
        pg.config,
        'SELECT entity_type, entity_id, actor_name, before_value, after_value '
        'FROM pos_audit_events WHERE restaurant_id = @r AND action = @a',
        parameters: {'r': restaurantId, 'a': AuditAction.stockCostSet},
      );
      expect(rows, hasLength(1));
      expect(rows.first[0], AuditAction.entityProduct);
      expect(rows.first[1], '$mayo');
      expect(rows.first[2], 'Amer M.');
      expect((rows.first[3]! as Map)['average_cost_minor'], 0);
      expect((rows.first[4]! as Map)['average_cost_minor'], 350);
      expect((rows.first[4]! as Map)['on_hand_milli'], 5000);
    });
  });

  group('an item that has never been received', () {
    test('has no level row until it is given a cost, then has one', () async {
      expect(await levelOf(ketchup), isEmpty);

      final result = await stock.setOpeningCost(
        productId: ketchup,
        unitCost: const Money(120),
        by: manager,
      );

      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect((await levelOf(ketchup)).take(2), [0, 120]);
      expect((await movements(ketchup)).single.take(5), ['opening', 0, 120, 0, 120]);
    });
  });

  group('what is refused, and leaves nothing behind', () {
    test('an item that already has a cost', () async {
      expect(await refusedWith(cola, 600), OpeningCostProblem.alreadyCosted);

      expect((await levelOf(cola)).take(2), [48000, 500], reason: 'unchanged');
      expect(await movements(cola), isEmpty);
      expect(await audits(), 0);
    });

    test('a second attempt on one just costed', () async {
      await stock.setOpeningCost(
        productId: mayo,
        unitCost: const Money(350),
        by: manager,
      );

      expect(await refusedWith(mayo, 999), OpeningCostProblem.alreadyCosted);
      expect((await levelOf(mayo))[1], 350);
      expect(await movements(mayo), hasLength(1));
      expect(await audits(), 1);
    });

    test('a cost of zero or less', () async {
      expect(await refusedWith(mayo, 0), OpeningCostProblem.notPositive);
      expect(await refusedWith(mayo, -5), OpeningCostProblem.notPositive);

      expect((await levelOf(mayo))[1], 0);
      expect(await movements(mayo), isEmpty);
    });

    test('an item that is not counted here', () async {
      expect(await refusedWith(burger, 300), OpeningCostProblem.itemUnknown);
      expect(await levelOf(burger), isEmpty);
    });

    test('an item that does not exist', () async {
      expect(await refusedWith(999999, 300), OpeningCostProblem.itemUnknown);
    });

    test("another restaurant's item", () async {
      expect(await refusedWith(theirs, 300), OpeningCostProblem.itemUnknown);
      expect(await levelOf(theirs), isEmpty);
    });
  });

  group('who may', () {
    test('somebody without purchase.manage may not', () async {
      final result = await stock.setOpeningCost(
        productId: mayo,
        unitCost: const Money(350),
        by: cashier,
      );

      expect(result.refusal, isA<NotPermitted>());
      expect((await levelOf(mayo))[1], 0);
      expect(await movements(mayo), isEmpty);
    });

    test('without the administrator credential nothing is written', () async {
      final result = await repository(admin: false).setOpeningCost(
        productId: mayo,
        unitCost: const Money(350),
        by: manager,
      );

      expect(result.refusal, isA<AdministratorCredentialRequired>());
      expect(await movements(mayo), isEmpty);
    });
  });

  group('migration 52', () {
    // The constraint was relaxed for `opening` alone. Every other kind still
    // refuses a movement of nothing: a receipt of nothing is a mistake.
    Future<void> insertMovement(String kind, int milli) => db.query(
      pg.config,
      'INSERT INTO pos_stock_movements (restaurant_id, branch_id, product_id, '
      '  kind, quantity_milli, balance_milli, average_cost_minor) '
      'VALUES (@r, @b, @p, @k, @q, 0, 0)',
      parameters: {
        'r': restaurantId,
        'b': branchId,
        'p': cola,
        'k': kind,
        'q': milli,
      },
    );

    test('a zero-quantity opening row is accepted', () async {
      await insertMovement('opening', 0);

      expect(await movements(cola), hasLength(1));
    });

    test('a zero-quantity row of any other kind is still refused', () async {
      for (final kind in ['receipt', 'sale', 'waste', 'adjustment']) {
        await expectLater(
          insertMovement(kind, 0),
          throwsA(anything),
          reason: '$kind of nothing',
        );
      }
      expect(await movements(cola), isEmpty);
    });

    test('a real movement is unaffected', () async {
      await insertMovement('receipt', 1000);

      expect(await movements(cola), hasLength(1));
    });
  });
}
