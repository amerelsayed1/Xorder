@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_purchase_orders_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/purchase_order.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// Purchase orders, stored.
void main() {
  if (PgFixture.host == null) {
    test('purchase orders (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresPurchaseOrdersRepository orders;
  late int restaurantId;
  late int branchId;
  late int supplierId;

  const buyer = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'buyer',
      nameEn: 'Buyer',
      capabilities: {PosCapability.purchaseManage},
    ),
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    capabilities: {PosCapability.operate},
  );

  setUp(() async {
    pg = await PgFixture.open('purchase_orders');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('po', 'PO') RETURNING id",
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

    orders = PostgresPurchaseOrdersRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  PurchaseOrder draft({List<PurchaseOrderLine>? lines, String reference = ''}) =>
      PurchaseOrder(
        id: 0,
        supplierId: supplierId,
        supplierName: 'Cairo Poultry',
        reference: reference,
        status: PurchaseStatus.draft,
        lines: lines ??
            [
              PurchaseOrderLine(
                id: 0,
                description: 'Chicken',
                ordered: const Quantity(12500, unit: QuantityUnit.kilogram),
                unitCost: const Money(4730),
                taxRateBp: 1400,
              ),
            ],
      );

  Future<PurchaseOrder> save(PurchaseOrder order) async {
    final result = await orders.saveDraft(order, by: buyer);
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  group('writing one', () {
    test('a draft round-trips, lines and all', () async {
      final saved = await save(draft());

      expect(saved.status, PurchaseStatus.draft);
      expect(saved.supplierName, 'Cairo Poultry');
      final line = saved.lines.single;
      expect(line.description, 'Chicken');
      expect(line.ordered.milli, 12500);
      expect(line.ordered.unit, QuantityUnit.kilogram);
      expect(line.unitCost.minor, 4730);
      expect(line.taxRateBp, 1400);
    });

    test('the totals are stored, not recomputed on read', () async {
      // Recomputing them from today's lines would let a cost change after the
      // fact alter what was agreed.
      final saved = await save(draft());
      final stored = await db.query(
        pg.config,
        'SELECT subtotal_minor, tax_minor, total_minor FROM pos_purchase_orders '
        'WHERE id = @id',
        parameters: {'id': saved.id},
      );

      expect(stored.first[0], 59125);
      expect(stored.first[1], 8278);
      expect(stored.first[2], 59125 + 8278);
    });

    test('a reference is claimed when none is given', () async {
      final saved = await save(draft());
      expect(saved.reference, matches(RegExp(r'^PO-\d{4}-\d{6}$')));
    });

    test('and the next one is the next number', () async {
      final first = await save(draft());
      final second = await save(draft());
      expect(second.reference, isNot(first.reference));
    });

    test('two orders cannot share a reference', () async {
      await save(draft(reference: 'PO-MANUAL-1'));
      await expectLater(
        orders.saveDraft(draft(reference: 'PO-MANUAL-1'), by: buyer),
        throwsA(isA<Object>()),
      );
    });

    test('editing a draft replaces its lines wholesale', () async {
      final saved = await save(draft());
      final edited = await save(
        saved.copyWith(
          lines: [
            PurchaseOrderLine(
              id: 0,
              description: 'Rice',
              ordered: const Quantity.of(20, unit: QuantityUnit.kilogram),
              unitCost: const Money(1800),
            ),
          ],
        ),
      );

      expect(edited.lines.single.description, 'Rice');
      expect(edited.id, saved.id, reason: 'the same order, not a new one');
    });
  });

  group('once it has gone out', () {
    test('sending stamps the date', () async {
      final saved = await save(draft());
      final at = DateTime.utc(2026, 9, 9, 8);
      final sent = await orders.setStatus(
        saved.id,
        status: PurchaseStatus.sent,
        by: buyer,
        orderedAt: at,
      );

      expect(sent.value!.status, PurchaseStatus.sent);
      expect(sent.value!.orderedAt, at);
    });

    test('it cannot be edited, and the refusal says what to do instead',
        () async {
      final saved = await save(draft());
      await orders.setStatus(
        saved.id,
        status: PurchaseStatus.sent,
        by: buyer,
        orderedAt: DateTime.utc(2026),
      );

      final result = await orders.saveDraft(
        saved.copyWith(lines: []),
        by: buyer,
      );
      expect(result.refusal, isA<CatalogInvalid>());
      expect(
        (result.refusal! as CatalogInvalid).reason,
        contains('already gone to the supplier'),
      );

      // And nothing was written.
      expect((await orders.byId(saved.id))!.lines, hasLength(1));
    });

    test('a sent order shows up as open', () async {
      final saved = await save(draft());
      expect(await orders.open(), isEmpty, reason: 'a draft is not owed yet');

      await orders.setStatus(
        saved.id,
        status: PurchaseStatus.sent,
        by: buyer,
        orderedAt: DateTime.utc(2026),
      );
      expect((await orders.open()).single.id, saved.id);
    });

    test('a cancelled one does not', () async {
      final saved = await save(draft());
      await orders.setStatus(
        saved.id,
        status: PurchaseStatus.cancelled,
        by: buyer,
      );
      expect(await orders.open(), isEmpty);
      expect(await orders.all(), hasLength(1), reason: 'but it is still there');
    });
  });

  group('what the database refuses', () {
    Future<void> line(String ordered, String cost, String tax) => db.query(
      pg.config,
      'INSERT INTO pos_purchase_order_lines (purchase_order_id, description, '
      "  ordered_milli, unit_cost_minor, tax_rate_bp) "
      "VALUES (@o, 'X', $ordered, $cost, $tax)",
      parameters: {'o': 1},
    );

    test('a line of nothing', () async {
      await save(draft());
      await expectLater(line('0', '100', '0'), throwsA(isA<Object>()));
    });

    test('a negative cost', () async {
      await save(draft());
      await expectLater(line('1000', '-1', '0'), throwsA(isA<Object>()));
    });

    test('a tax rate above 100%', () async {
      await save(draft());
      await expectLater(line('1000', '100', '10001'), throwsA(isA<Object>()));
    });

    test('an unknown status', () async {
      final saved = await save(draft());
      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_purchase_orders SET status = 'invoiced' WHERE id = @id",
          parameters: {'id': saved.id},
        ),
        throwsA(isA<Object>()),
      );
    });

    test('a sent order with no date', () async {
      final saved = await save(draft());
      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_purchase_orders SET status = 'sent' WHERE id = @id",
          parameters: {'id': saved.id},
        ),
        throwsA(isA<Object>()),
        reason: '"sent" is a fact about the order, not a flag somebody set',
      );
    });

    test('deleting a supplier somebody has ordered from', () async {
      await save(draft());
      await expectLater(
        db.query(
          pg.config,
          'DELETE FROM pos_suppliers WHERE id = @id',
          parameters: {'id': supplierId},
        ),
        throwsA(isA<Object>()),
      );
    });
  });

  group('permissions', () {
    test('a cashier cannot write a purchase order', () async {
      final result = await orders.saveDraft(draft(), by: cashier);
      expect(result.refusal, isA<NotPermitted>());
      expect(await orders.all(), isEmpty);
    });

    test('nor move one on', () async {
      final saved = await save(draft());
      final result = await orders.setStatus(
        saved.id,
        status: PurchaseStatus.cancelled,
        by: cashier,
      );
      expect(result.refusal, isA<NotPermitted>());
    });

    test('a till with no administrator credential sees nothing', () async {
      await save(draft());
      final locked = PostgresPurchaseOrdersRepository(
        database: db,
        config: pg.config,
        adminAvailable: false,
        restaurantId: restaurantId,
        branchId: branchId,
      );
      expect(await locked.all(), isEmpty);
      expect(await locked.byId(1), isNull);
    });
  });

  test('the status change is audited', () async {
    final saved = await save(draft());
    await orders.setStatus(
      saved.id,
      status: PurchaseStatus.sent,
      by: buyer,
      orderedAt: DateTime.utc(2026),
    );

    final rows = await db.query(
      pg.config,
      "SELECT action, after_value->>'status' FROM pos_audit_events "
      'WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
      parameters: {'e': AuditAction.entityPurchaseOrder},
    );
    // It is a commitment to spend money; "who sent this and when" is what a
    // disputed delivery asks.
    expect(rows.first[0], AuditAction.purchaseOrderStatusChanged);
    expect(rows.first[1], 'sent');
  });

  test('another branch does not see this one\'s orders', () async {
    await save(draft());
    final other = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'B2', 'Maadi') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    final elsewhere = PostgresPurchaseOrdersRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      restaurantId: restaurantId,
      branchId: other,
    );
    // Stock that arrived at Downtown is not stock Maadi can sell.
    expect(await elsewhere.all(), isEmpty);
  });
}
