@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

import 'pg_fixture.dart';

/// XORD-058: which number a receipt may print.
///
/// A cloud till's sale is numbered by the platform (POS-BE-008). The till used
/// to print its own sequence as the invoice number, so the customer's paper
/// said BR8-…-000001 while the dashboard said BR8-…-000008. Owner decision,
/// 2026-11-07: print PROVISIONAL until the platform's number is back; an
/// offline till's own number is the invoice and is printed as before.
void main() {
  if (PgFixture.host == null) {
    test('provisional invoice (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  const terminal = '7f8c3a52-0000-4000-8000-0000000000c3';

  setUp(() async {
    pg = await PgFixture.open('provisional_invoice');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('inv', 'Inv') "
      'RETURNING id',
    )).first[0]! as int;
    branchId = (await db.query(
      pg.config,
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'BR8', 'Main') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;
    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'Counter 1')",
      parameters: {'t': terminal, 'r': businessId, 'b': branchId},
    );
  });

  tearDown(() => pg.close());

  PostgresOrdersRepository orders(DeploymentMode mode) =>
      PostgresOrdersRepository(
        database: db,
        config: mode == DeploymentMode.cloud
            ? pg.config.copyWith(mode: mode, baseUrl: 'https://xorder.io')
            : pg.config,
        context: PosWriteContext(
          businessId: businessId,
          branchId: branchId,
          terminalId: terminal,
          branchCode: 'BR8',
        ),
      );

  Ticket paidSale(String id) {
    var ticket = Ticket(id: id, orderType: OrderType.takeaway);
    ticket = TicketEngine.addLine(
      ticket,
      const Product(id: 1, categoryId: 1, nameEn: 'Tea', price: Money(4000)),
    ).ticket!;
    return TicketEngine.addTender(
      ticket,
      typeId: 1,
      label: 'Cash',
      countsAsCash: true,
    ).ticket!;
  }

  test('a cloud till prints no number until the platform has numbered it',
      () async {
    final result = await orders(DeploymentMode.cloud)
        .submit(paidSale('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'));

    expect(result.queued, isTrue);
    expect(result.invoiceNumber, isNull, reason: 'the receipt says PROVISIONAL');
    // The till's own sequence still numbers the row.
    final local = await db.query(
      pg.config,
      'SELECT invoice_number FROM pos_orders WHERE id = @id',
      parameters: {'id': result.serverId},
    );
    expect(local.single[0], isNotNull);
  });

  test("once delivered, a reprint of the sale names the platform's number",
      () async {
    const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';
    final repo = orders(DeploymentMode.cloud);
    final first = await repo.submit(paidSale(id));
    await db.query(
      pg.config,
      'UPDATE pos_outbox SET delivered_at = now(), '
      "server_invoice_number = 'BR8-2026-000008' WHERE order_id = @o",
      parameters: {'o': first.serverId},
    );

    // Paying the same ticket again (a retry) replays the recorded sale.
    final again = await repo.submit(paidSale(id));
    expect(again.serverId, first.serverId);
    expect(again.invoiceNumber, 'BR8-2026-000008');
  });

  test('an offline till prints its own number, as before', () async {
    final result = await orders(DeploymentMode.offline)
        .submit(paidSale('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'));

    expect(result.queued, isFalse);
    expect(result.invoiceNumber, startsWith('BR8-'));
  });
}
