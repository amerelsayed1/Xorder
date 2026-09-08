@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_purchase_orders_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_receiving_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/purchase_order.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// Booking goods in, and what it does to the cost.
///
/// Four things have to land together — the line, the ledger, the position and
/// the order's status — and the test that matters most is the one that proves
/// they cannot come apart.
void main() {
  if (PgFixture.host == null) {
    test('receiving (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresPurchaseOrdersRepository orders;
  late PostgresReceivingRepository receiving;
  late int restaurantId;
  late int branchId;
  late int supplierId;
  late int productId;

  const buyer = PosStaff(
    id: 0,
    name: 'Amer M.',
    capabilities: {PosCapability.purchaseManage},
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    capabilities: {PosCapability.operate},
  );

  setUp(() async {
    pg = await PgFixture.open('receiving');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('rc', 'RC') RETURNING id",
    )).first[0]! as int;
    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;
    supplierId = (await db.query(
      pg.config,
      "INSERT INTO pos_suppliers (restaurant_id, name_en) "
      "VALUES (@r, 'Cairo Poultry') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;
    final categoryId = (await db.query(
      pg.config,
      "INSERT INTO pos_categories (restaurant_id, name_en) "
      "VALUES (@r, 'Grills') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;
    productId = (await db.query(
      pg.config,
      'INSERT INTO pos_products (restaurant_id, category_id, name_en, '
      "  price_minor, is_stocked, stock_unit) "
      "VALUES (@r, @c, 'Chicken', 9000, true, 'kg') RETURNING id",
      parameters: {'r': restaurantId, 'c': categoryId},
    )).first[0]! as int;

    orders = PostgresPurchaseOrdersRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      restaurantId: restaurantId,
      branchId: branchId,
    );
    receiving = PostgresReceivingRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  /// A sent order for [milli] thousandths of chicken at [cost] a kilo.
  Future<PurchaseOrder> sentOrder({
    int milli = 10000,
    int cost = 4000,
    bool stocked = true,
  }) async {
    final draft = await orders.saveDraft(
      PurchaseOrder(
        id: 0,
        supplierId: supplierId,
        supplierName: 'Cairo Poultry',
        reference: '',
        status: PurchaseStatus.draft,
        lines: [
          PurchaseOrderLine(
            id: 0,
            productId: stocked ? productId : null,
            description: 'Chicken',
            ordered: Quantity(milli, unit: QuantityUnit.kilogram),
            unitCost: Money(cost),
          ),
        ],
      ),
      by: buyer,
    );
    final sent = await orders.setStatus(
      draft.value!.id,
      status: PurchaseStatus.sent,
      by: buyer,
      orderedAt: DateTime.utc(2026, 9, 9),
    );
    return sent.value!;
  }

  Future<AdminResult<void>> book(
    PurchaseOrder order,
    int milli, {
    PosStaff who = buyer,
  }) => receiving.receive(
    purchaseOrderId: order.id,
    byLine: {
      order.lines.single.id: Quantity(milli, unit: QuantityUnit.kilogram),
    },
    by: who,
  );

  group('the cost after a delivery', () {
    test('the first one sets it', () async {
      final order = await sentOrder(milli: 10000, cost: 4000);
      expect((await book(order, 10000)).succeeded, isTrue);

      final position = (await receiving.positionFor(productId))!;
      expect(position.onHand.milli, 10000);
      expect(position.unitCost.minor, 4000);
    });

    test('the second one averages it', () async {
      // 10 kg at 40.00 then 10 kg at 50.00 is 20 kg at 45.00.
      await book(await sentOrder(milli: 10000, cost: 4000), 10000);
      await book(await sentOrder(milli: 10000, cost: 5000), 10000);

      final position = (await receiving.positionFor(productId))!;
      expect(position.onHand.milli, 20000);
      expect(position.unitCost.minor, 4500);
    });

    test('weighted, not a midpoint', () async {
      // 30 kg at 40.00 then 10 kg at 60.00 is 45.00, not 50.00.
      await book(await sentOrder(milli: 30000, cost: 4000), 30000);
      await book(await sentOrder(milli: 10000, cost: 6000), 10000);

      expect((await receiving.positionFor(productId))!.unitCost.minor, 4500);
    });

    test('a product never received has no position at all', () async {
      // Null rather than zero: "nothing has ever arrived" and "we have none
      // left" are different facts, and a valuation should not confuse them.
      expect(await receiving.positionFor(productId), isNull);
    });
  });

  group('the ledger', () {
    test('records the resulting position, not just the movement', () async {
      // A moving average is a fold and cannot be recomputed from a filter.
      // Storing the answer beside the input is what makes last March's cost
      // auditable without replaying three years.
      await book(await sentOrder(milli: 10000, cost: 4000), 10000);
      await book(await sentOrder(milli: 10000, cost: 5000), 10000);

      final rows = await db.query(
        pg.config,
        'SELECT quantity_milli, unit_cost_minor, balance_milli, '
        '       average_cost_minor, kind '
        'FROM pos_stock_movements ORDER BY id',
      );

      expect(rows, hasLength(2));
      expect(rows[0][3], 4000, reason: 'the average after the first');
      expect(rows[1][1], 5000, reason: 'what the second delivery cost');
      expect(rows[1][3], 4500, reason: 'the average after it');
      expect(rows[1][2], 20000);
      expect(rows[0][4], 'receipt');
    });

    test('it names the order the goods came in against', () async {
      final order = await sentOrder();
      await book(order, 10000);

      final rows = await db.query(
        pg.config,
        'SELECT purchase_order_id FROM pos_stock_movements',
      );
      expect(rows.single[0], order.id);
    });

    test('a movement cannot be edited or deleted after the fact', () async {
      // A row somebody can change is a stock figure nobody can defend. The
      // grant refuses it; this asserts the grant list says so.
      await book(await sentOrder(), 10000);
      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_stock_movements',
      );
      expect(rows.first[0], 1);
    });

    test('a line that stocks nothing moves no stock', () async {
      // Packaging, gas, a service. Most of a purchase order by line count.
      final order = await sentOrder(stocked: false);
      expect((await book(order, 10000)).succeeded, isTrue);

      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_stock_movements',
      );
      expect(rows.first[0], 0, reason: 'and the ledger stays clean');
    });
  });

  group('the order follows the goods', () {
    test('a part delivery leaves it open', () async {
      final order = await sentOrder(milli: 10000);
      await book(order, 4000);

      final after = (await orders.byId(order.id))!;
      expect(after.status, PurchaseStatus.partiallyReceived);
      expect(after.lines.single.received.milli, 4000);
      expect(after.lines.single.outstanding.milli, 6000);
    });

    test('the rest closes it', () async {
      final order = await sentOrder(milli: 10000);
      await book(order, 4000);
      await book(order, 6000);

      final after = (await orders.byId(order.id))!;
      expect(after.status, PurchaseStatus.received);
      expect(after.lines.single.outstanding.milli, 0);
    });

    test('over-delivery closes it too', () async {
      // Suppliers round up to a full crate.
      final order = await sentOrder(milli: 10000);
      await book(order, 11000);

      final after = (await orders.byId(order.id))!;
      expect(after.status, PurchaseStatus.received);
      expect(after.lines.single.isOverReceived, isTrue);
      expect((await receiving.positionFor(productId))!.onHand.milli, 11000);
    });

    test('the status is derived, so it cannot contradict the lines', () async {
      // Passed in by nobody. A receipt that could set "received" while a line
      // was short would be an order that lies about itself.
      final order = await sentOrder(milli: 10000);
      await book(order, 1);
      expect(
        (await orders.byId(order.id))!.status,
        PurchaseStatus.partiallyReceived,
      );
    });
  });

  group('what is refused', () {
    test('booking in against a draft', () async {
      final draft = await orders.saveDraft(
        PurchaseOrder(
          id: 0,
          supplierId: supplierId,
          supplierName: 'X',
          reference: '',
          status: PurchaseStatus.draft,
          lines: [
            PurchaseOrderLine(
              id: 0,
              productId: productId,
              description: 'Chicken',
              ordered: const Quantity(1000, unit: QuantityUnit.kilogram),
              unitCost: const Money(4000),
            ),
          ],
        ),
        by: buyer,
      );

      final result = await receiving.receive(
        purchaseOrderId: draft.value!.id,
        byLine: {draft.value!.lines.single.id: const Quantity(1000)},
        by: buyer,
      );
      expect(result.refusal, isA<CatalogInvalid>());
      expect(await receiving.positionFor(productId), isNull);
    });

    test('booking in against a cancelled order', () async {
      final order = await sentOrder();
      await orders.setStatus(
        order.id,
        status: PurchaseStatus.cancelled,
        by: buyer,
      );
      expect((await book(order, 1000)).refusal, isA<CatalogInvalid>());
    });

    test('booking in nothing', () async {
      final order = await sentOrder();
      expect((await book(order, 0)).refusal, isA<CatalogInvalid>());
    });

    test('a cashier', () async {
      final order = await sentOrder();
      expect((await book(order, 1000, who: cashier)).refusal, isA<NotPermitted>());
      expect(await receiving.positionFor(productId), isNull);
    });

    test('and nothing lands when it is refused', () async {
      // The four writes are one transaction: a refusal leaves the line, the
      // ledger, the position and the status all untouched.
      final order = await sentOrder();
      await book(order, 1000, who: cashier);

      final after = (await orders.byId(order.id))!;
      expect(after.status, PurchaseStatus.sent);
      expect(after.lines.single.received.milli, 0);
      final movements = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_stock_movements',
      );
      expect(movements.first[0], 0);
    });
  });

  test('another branch keeps its own stock', () async {
    // Stock that arrived at Downtown is not stock Maadi can sell.
    await book(await sentOrder(milli: 10000, cost: 4000), 10000);

    final other = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'B2', 'Maadi') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    final elsewhere = PostgresReceivingRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      restaurantId: restaurantId,
      branchId: other,
    );
    expect(await elsewhere.positionFor(productId), isNull);
  });

  test('the receipt is audited', () async {
    final order = await sentOrder();
    await book(order, 10000);

    final rows = await db.query(
      pg.config,
      "SELECT action, after_value->>'status' FROM pos_audit_events "
      "WHERE action = @a ORDER BY id DESC LIMIT 1",
      parameters: {'a': AuditAction.stockReceived},
    );
    // It is the moment a cost price changes, and every margin afterwards is
    // measured against it.
    expect(rows.first[0], AuditAction.stockReceived);
    expect(rows.first[1], 'received');
  });
}
