@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_admin_repositories.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_refunds_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_shift_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/refund_engine.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

import 'pg_fixture.dart';

/// Which shift a sale, a refund and an audit row are stamped with — R-SALE-1.
///
/// The app builds each of these repositories ONCE, and nothing rebuilds them
/// when a shift opens or closes. They used to take the shift id as an `int?`
/// at construction, so the first sale of the day fixed it for the life of the
/// process: a till that sold before opening its shift stamped NULL on every
/// sale after it, and a till that cashed up and opened the next shift kept
/// stamping the closed one. Either way the money fell out of the open drawer's
/// Z report and its expected cash.
///
/// Every test here builds the repository the way `providers.dart` does —
/// once, up front, with a resolver that answers null — and only then opens
/// the shift. A captured id cannot pass these; a resolver asked at the write
/// can.
void main() {
  if (PgFixture.host == null) {
    test(
      'shift attribution (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late String terminalId;
  late PosStaff sara;

  /// What `shiftProvider` would answer right now. The repositories under test
  /// read this through a function, exactly as the provider closure does.
  int? openShift;

  setUp(() async {
    pg = await PgFixture.open('shift_attribution');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_restaurants');
    openShift = null;

    restaurantId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_restaurants (slug, name) "
                  "VALUES ('shift-attr', 'Shift Attribution') RETURNING id",
                ))
                .first[0]
            as int;
    branchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (restaurant_id, code, name) "
                  "VALUES (@r, 'SAT', 'Main') RETURNING id",
                  parameters: {'r': restaurantId},
                ))
                .first[0]
            as int;
    terminalId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
                  "VALUES (gen_random_uuid(), @r, @b, 'Counter 1') "
                  'RETURNING id::text',
                  parameters: {'r': restaurantId, 'b': branchId},
                ))
                .first[0]
            as String;
    final staffId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_staff (restaurant_id, branch_id, name, '
                  "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Sara M.', "
                  "  'sara', 'salt', 'hash') RETURNING id",
                  parameters: {'r': restaurantId, 'b': branchId},
                ))
                .first[0]
            as int;
    // A supervisor: may open and close her own drawer and give money back
    // without a second PIN, so nothing here is about permissions.
    sara = PosStaff(
      id: staffId,
      name: 'Sara M.',
      role: const PosRole(
        id: 1,
        code: SystemRoles.supervisorCode,
        nameEn: 'Supervisor',
        capabilities: SystemRoles.supervisor,
      ),
    );
  });

  tearDown(() => pg.close());

  PosWriteContext context() => PosWriteContext(
    restaurantId: restaurantId,
    branchId: branchId,
    terminalId: terminalId,
    branchCode: 'SAT',
  );

  PostgresShiftRepository shifts() => PostgresShiftRepository(
    database: db,
    config: pg.config,
    restaurantId: restaurantId,
    branchId: branchId,
    terminalId: terminalId,
  );

  Ticket paidTicket({int priceMinor = 10000}) {
    var ticket = Ticket(id: const Uuid().v4(), orderType: OrderType.takeaway);
    ticket = TicketEngine.addLine(
      ticket,
      Product(id: 1, categoryId: 1, nameEn: 'Thing', price: Money(priceMinor)),
    ).ticket!;
    return TicketEngine.addTender(
      ticket,
      typeId: 1,
      label: 'Cash',
      countsAsCash: true,
    ).ticket!;
  }

  Future<int?> orderShift(int orderId) async =>
      (await db.query(
            pg.config,
            'SELECT shift_id FROM pos_orders WHERE id = @id',
            parameters: {'id': orderId},
          )).first[0]
          as int?;

  group('a sale', () {
    test('carries the shift opened after the repository was built', () async {
      // Built before any shift exists — the till's first screen, at 8am.
      final orders = PostgresOrdersRepository(
        database: db,
        config: pg.config,
        context: context(),
        shiftId: () => openShift,
      );

      final shift = await shifts().open(by: sara, openingFloat: const Money(20000));
      openShift = shift.id;

      final sold = await orders.submit(paidTicket(), servedBy: sara);

      expect(await orderShift(sold.serverId!), shift.id);
      // The claim that matters to the manager: it is IN the Z report.
      final summary = await shifts().summarise(shift);
      expect(summary.saleCount, 1);
    });

    test('carries the NEXT shift after one is closed and another opened', () async {
      final orders = PostgresOrdersRepository(
        database: db,
        config: pg.config,
        context: context(),
        shiftId: () => openShift,
      );

      final morning = await shifts().open(by: sara, openingFloat: const Money(20000));
      openShift = morning.id;
      final first = await orders.submit(paidTicket(), servedBy: sara);

      await shifts().close(shift: morning, by: sara, countedCash: const Money(31400));
      final evening = await shifts().open(by: sara, openingFloat: const Money(20000));
      openShift = evening.id;
      final second = await orders.submit(paidTicket(), servedBy: sara);

      expect(await orderShift(first.serverId!), morning.id);
      expect(
        await orderShift(second.serverId!),
        evening.id,
        reason: 'a captured id would have stamped the closed morning shift',
      );
    });
  });

  test('a refund carries the shift opened after the repository was built', () async {
    final refunds = PostgresRefundsRepository(
      database: db,
      config: pg.config,
      context: context(),
      shiftId: () => openShift,
    );
    final orders = PostgresOrdersRepository(
      database: db,
      config: pg.config,
      context: context(),
      shiftId: () => openShift,
    );

    final shift = await shifts().open(by: sara, openingFloat: const Money(20000));
    openShift = shift.id;
    // 100.00 takeaway, VAT 14% on top: 114.00.
    final sold = await orders.submit(paidTicket(), servedBy: sara);
    final orderId = sold.serverId!;

    final result = await refunds.issue(
      order: OrderRecord(
        id: orderId,
        clientTransactionId: sold.clientTransactionId,
        invoiceNumber: sold.invoiceNumber!,
        status: OrderStatus.paid,
        orderType: OrderType.takeaway,
        occurredAt: DateTime.now(),
        subtotal: const Money(10000),
        discount: Money.zero,
        service: Money.zero,
        vat: const Money(1400),
        total: const Money(11400),
      ),
      quote: const RefundQuote(
        subtotal: Money(1000),
        discount: Money.zero,
        service: Money.zero,
        vat: Money(140),
        total: Money(1140),
        kind: RefundKind.partial,
        lines: [],
        requiresApproval: false,
      ),
      by: sara,
      tenders: const [
        RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(1140)),
      ],
      clientRefundId: const Uuid().v4(),
    );

    final rows = await db.query(
      pg.config,
      'SELECT shift_id FROM pos_refunds WHERE id = @id',
      parameters: {'id': result.refundId},
    );
    expect(rows.first[0], shift.id);
  });

  test('an audit row carries the shift open when it was written', () async {
    final audit = PostgresAuditRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
      terminalId: terminalId,
      shiftId: () => openShift,
    );

    final shift = await shifts().open(by: sara, openingFloat: const Money(20000));
    openShift = shift.id;
    await audit.record(
      by: sara,
      action: AuditAction.receiptReprinted,
      entityType: AuditAction.entityShift,
      entityId: 'attribution-${shift.id}',
    );

    final rows = await db.query(
      pg.config,
      'SELECT shift_id FROM pos_audit_events '
      'WHERE restaurant_id = @r AND entity_id = @e',
      parameters: {'r': restaurantId, 'e': 'attribution-${shift.id}'},
    );
    expect(rows.single[0], shift.id);
  });
}
