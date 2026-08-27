@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/ticket.dart';

import 'pg_fixture.dart';

/// Exercises the real SQL against a real PostgreSQL.
///
/// Skipped unless `POS_PG_HOST` is set, so `flutter test` stays green on a
/// machine with no database. Untested SQL is the biggest risk in this layer —
/// idempotency and invoice sequencing are enforced by constraints and row locks,
/// and neither can be verified by a unit test.
///
///   docker run -d --rm --name xorder-pos-itest \
///     -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=xorder_pos \
///     -p 55432:5432 postgres:16-alpine
///   POS_PG_HOST=127.0.0.1 POS_PG_PORT=55432 POS_PG_PASSWORD=postgres \
///     flutter test test/data/postgres_integration_test.dart
void main() {
  if (PgFixture.host == null) {
    test('postgres integration (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;

  setUp(() async {
    pg = await PgFixture.open('orders');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
  });

  tearDown(() => pg.close());

  PostgresOrdersRepository repository() => PostgresOrdersRepository(
        database: db,
        config: pg.config,
        context: const PosWriteContext(
          restaurantId: 1,
          branchId: 13,
          terminalId: '7f1c9a52-3b64-4f0e-9a11-0c2d5e8b7a10',
          branchCode: 'MAADI',
        ),
        clock: () => DateTime.utc(2026, 8, 26, 12),
      );

  test('migrations are idempotent and run once', () async {
    final second = await PosMigrator(db).migrate(pg.config);
    expect(second, isEmpty, reason: 'a second till booting must not re-run the schema');
  });

  test('a settled ticket writes order, lines and payments in one transaction', () async {
    final result = await repository().submit(_ticket('11111111-1111-4111-8111-111111111111'));

    expect(result.serverId, isNotNull);
    expect(result.invoiceNumber, 'MAADI-2026-000001');

    final rows = await db.query(pg.config, '''
      SELECT o.total_minor, o.currency,
             (SELECT count(*) FROM pos_order_lines l WHERE l.order_id = o.id),
             (SELECT count(*) FROM pos_order_payments p WHERE p.order_id = o.id)
      FROM pos_orders o
    ''');
    expect(rows.length, 1);
    // 2 × (10.00 + 1.50) = 23.00 subtotal; +12% service = 2.76; +14% VAT on
    // 25.76 = 3.61 (half-up, the single rounding point); total 29.37.
    expect(rows.first[0], 2937);
    expect(rows.first[1], 'EGP');
    expect(rows.first[2], 1, reason: 'one line');
    expect(rows.first[3], 2, reason: 'split tender is two payment rows, not two columns');
  });

  test('replaying a client transaction id returns the original, and issues no second number',
      () async {
    const id = '22222222-2222-4222-8222-222222222222';
    final first = await repository().submit(_ticket(id));
    final replay = await repository().submit(_ticket(id));

    expect(replay.serverId, first.serverId);
    expect(replay.invoiceNumber, first.invoiceNumber);

    final count = await db.query(pg.config, 'SELECT count(*) FROM pos_orders');
    expect(count.first[0], 1, reason: 'five submissions must create exactly one sale');

    final seq = await db.query(pg.config, 'SELECT next_value FROM pos_invoice_sequences');
    expect(seq.first[0], 2, reason: 'a replay must not consume an invoice number');
  });

  test('concurrent settlements never share an invoice number', () async {
    // The case a MAX(number)+1 scan gets wrong, and the reason the sequence row
    // is locked FOR UPDATE inside the same transaction as the insert.
    final results = await Future.wait([
      for (var i = 0; i < 8; i++)
        repository().submit(_ticket('33333333-3333-4333-8333-00000000000$i')),
    ]);

    final numbers = results.map((r) => r.invoiceNumber).toSet();
    expect(numbers.length, 8, reason: 'eight tills, eight distinct numbers');
    expect(results.map((r) => r.serverId).toSet().length, 8);
  });

  test('the database refuses money that should be impossible', () async {
    // Constraints, not client-side hope. A negative payment is a refund and has
    // its own record type; it must never arrive as a tender.
    await expectLater(
      db.runTx(pg.config, (tx) async {
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_order_payments (order_id, tender_type_id, label, amount_minor)
            VALUES (@order, 1, 'Cash', -500)
          '''),
          parameters: {'order': 1},
        );
      }),
      throwsA(isA<PosDbException>()),
    );
  });
}

Ticket _ticket(String id) {
  const product = Product(
    id: 501,
    categoryId: 9,
    nameEn: 'Mixed Grill',
    price: Money(1000),
  );
  const extra = Modifier(id: 77, groupId: 4, nameEn: 'Extra bread', priceDelta: Money(150));

  return Ticket(
    id: id,
    orderType: OrderType.dineIn,
    tableId: 4,
    tableLabel: 'T4',
    guestCount: 2,
    lines: [TicketLine(product: product, quantity: 2, modifiers: const [extra])],
    tenders: const [
      Tender(typeId: 1, label: 'Cash', amount: Money(2000)),
      Tender(typeId: 2, label: 'Card', amount: Money(937), reference: 'AUTH-4471'),
    ],
  );
}
