@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_purchase_orders_repository.dart';
import 'package:shared_module/data/postgres/postgres_receiving_repository.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/purchase_order.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

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
  late int businessId;
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
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('po', 'PO') RETURNING id",
    )).first[0]! as int;
    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;
    supplierId = (await db.query(
      pg.config,
      "INSERT INTO pos_suppliers (business_id, name_en) "
      "VALUES (@r, 'Cairo Poultry') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;

    orders = PostgresPurchaseOrdersRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      businessId: businessId,
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

  Future<PurchaseOrder> send(PurchaseOrder saved) async {
    final result = await orders.setStatus(
      saved.id,
      status: PurchaseStatus.sent,
      by: buyer,
      orderedAt: DateTime.utc(2026, 9, 9),
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  /// Goods booked in against [order]'s one line — from "another session", as
  /// far as any screen holding [order] is concerned.
  Future<void> book(PurchaseOrder order, int milli) async {
    final result = await PostgresReceivingRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      businessId: businessId,
      branchId: branchId,
    ).receive(
      purchaseOrderId: order.id,
      byLine: {
        order.lines.single.id: Quantity(milli, unit: QuantityUnit.kilogram),
      },
      by: buyer,
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
  }

  Future<PurchaseStatus> statusOf(int id) async =>
      (await orders.byId(id))!.status;

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

  group('where it may go next', () {
    // The Purchasing pane holds a snapshot of the order and sends whatever its
    // buttons say. These are the moves a stale snapshot gets wrong, so the
    // answer has to come from the row as it is now, not from the screen.
    Matcher refusedBecause<T extends PurchaseRefusal>() =>
        isA<PurchaseRefused>().having((r) => r.reason, 'reason', isA<T>());

    test('goods booked in from another session stop a cancel', () async {
      // The screen rendered this order as sent, with Cancel showing. Between
      // render and tap, somebody at the back door booked in four kilos.
      final shown = await send(await save(draft()));
      await book(shown, 4000);

      final result = await orders.setStatus(
        shown.id,
        status: PurchaseStatus.cancelled,
        by: buyer,
      );
      expect(result.refusal, refusedBecause<OrderAlreadyClosed>());
      expect(await statusOf(shown.id), PurchaseStatus.partiallyReceived);
    });

    test('nor once all of it has arrived', () async {
      final order = await send(await save(draft()));
      await book(order, 12500);

      final result = await orders.setStatus(
        order.id,
        status: PurchaseStatus.cancelled,
        by: buyer,
      );
      expect(result.refusal, refusedBecause<OrderAlreadyClosed>());
      expect(await statusOf(order.id), PurchaseStatus.received);
    });

    test('an order with nothing on it cannot be sent', () async {
      final empty = await save(draft(lines: const []));
      final result = await orders.setStatus(
        empty.id,
        status: PurchaseStatus.sent,
        by: buyer,
        orderedAt: DateTime.utc(2026),
      );
      expect(result.refusal, refusedBecause<OrderHasNoLines>());
      expect(await statusOf(empty.id), PurchaseStatus.draft);
    });

    test('an order cannot be sent twice', () async {
      // The second send would restamp the date the supplier was committed to.
      final order = await send(await save(draft()));
      final again = await orders.setStatus(
        order.id,
        status: PurchaseStatus.sent,
        by: buyer,
        orderedAt: DateTime.utc(2027),
      );
      expect(again.refusal, refusedBecause<OrderNotEditable>());
      expect((await orders.byId(order.id))!.orderedAt, DateTime.utc(2026, 9, 9));
    });

    test('a cancelled order stays cancelled', () async {
      final saved = await save(draft());
      await orders.setStatus(
        saved.id,
        status: PurchaseStatus.cancelled,
        by: buyer,
      );
      final revived = await orders.setStatus(
        saved.id,
        status: PurchaseStatus.sent,
        by: buyer,
        orderedAt: DateTime.utc(2026),
      );
      expect(revived.refusal, refusedBecause<OrderNotEditable>());
      expect(await statusOf(saved.id), PurchaseStatus.cancelled);
    });

    test('received is what the goods say, not what the caller says', () async {
      final order = await send(await save(draft()));
      for (final status in const [
        PurchaseStatus.received,
        PurchaseStatus.partiallyReceived,
        PurchaseStatus.draft,
      ]) {
        final result = await orders.setStatus(
          order.id,
          status: status,
          by: buyer,
        );
        expect(
          result.refusal,
          refusedBecause<StatusFollowsTheGoods>(),
          reason: status.wire,
        );
      }
      expect(await statusOf(order.id), PurchaseStatus.sent);
    });

    test('a refused move leaves no audit row claiming it happened', () async {
      final empty = await save(draft(lines: const []));
      await orders.setStatus(
        empty.id,
        status: PurchaseStatus.sent,
        by: buyer,
        orderedAt: DateTime.utc(2026),
      );
      final rows = await db.query(
        pg.config,
        // By entity: the audit ledger outlives each test's business.
        'SELECT count(*) FROM pos_audit_events '
        'WHERE action = @a AND entity_id = @e',
        parameters: {
          'a': AuditAction.purchaseOrderStatusChanged,
          'e': '${empty.id}',
        },
      );
      expect(rows.first[0], 0);
    });
  });

  group('and the database refuses the same moves, round the repository', () {
    // The second writer — a script, a restore, the cloud sync when it comes —
    // does not go through `setStatus`, so the rule is a trigger too.
    Future<void> move(int id, String status) => db.query(
      pg.config,
      'UPDATE pos_purchase_orders SET status = @s, '
      '  ordered_at = coalesce(ordered_at, now()) WHERE id = @id',
      parameters: {'id': id, 's': status},
    );

    Matcher refusedSaying(String words) => throwsA(
      isA<PosDbException>().having((e) => '${e.raw}', 'message', contains(words)),
    );

    test('cancelling an order goods have arrived against', () async {
      final order = await send(await save(draft()));
      await book(order, 4000);
      await expectLater(
        move(order.id, 'cancelled'),
        refusedSaying('cannot be cancelled'),
      );
      expect(await statusOf(order.id), PurchaseStatus.partiallyReceived);
    });

    test('sending an order with no lines', () async {
      final empty = await save(draft(lines: const []));
      await expectLater(move(empty.id, 'sent'), refusedSaying('no lines'));
    });

    test('reopening a closed order', () async {
      final saved = await save(draft());
      await move(saved.id, 'cancelled');
      await expectLater(move(saved.id, 'sent'), refusedSaying('does not reopen'));
    });

    test('going backwards', () async {
      final order = await send(await save(draft()));
      await expectLater(
        move(order.id, 'draft'),
        refusedSaying('only moves forward'),
      );
    });

    test('while the moves that are allowed still are', () async {
      final saved = await save(draft());
      await move(saved.id, 'sent');
      await move(saved.id, 'cancelled');
      expect(await statusOf(saved.id), PurchaseStatus.cancelled);
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
        businessId: businessId,
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
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'B2', 'Maadi') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;

    final elsewhere = PostgresPurchaseOrdersRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      businessId: businessId,
      branchId: other,
    );
    // Stock that arrived at Downtown is not stock Maadi can sell.
    expect(await elsewhere.all(), isEmpty);
  });
}
