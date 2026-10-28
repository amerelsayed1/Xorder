@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_orders_repository.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// The count of orders in a trading day, shared by every till of the branch.
///
/// The invoice number is the legal number and is not under test here except to
/// say it is untouched. This is the number a cashier calls out: 1, 2, 3 ... for
/// the day, the same sequence whichever till rang the sale, starting again with
/// the next trading day, kept by voided orders, and absent (never invented)
/// when no trading day is open.
void main() {
  if (PgFixture.host == null) {
    test(
      'day order number (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int staffId;

  const tillA = '44444444-4444-4444-8444-444444444444';
  const tillB = '55555555-5555-4555-8555-555555555555';

  Future<Object?> one(
    String sql, [
    Map<String, Object?> parameters = const {},
  ]) async => (await db.query(pg.config, sql, parameters: parameters)).first[0];

  Future<int> openDay({int? branch, String date = '2026-09-10'}) async =>
      await one(
        'INSERT INTO pos_business_days (business_id, branch_id, '
        '  business_date, opened_by, opened_at) '
        "VALUES (@r, @b, @d::date, @by, now() - interval '2 hours') "
        'RETURNING id',
        {'r': businessId, 'b': branch ?? branchId, 'd': date, 'by': staffId},
      ) as int;

  Future<void> closeDay(int day) => db.query(
    pg.config,
    "UPDATE pos_business_days SET closed_at = now() - interval '1 hour', "
    'closed_by = @by WHERE id = @id',
    parameters: {'id': day, 'by': staffId},
  );

  /// One order. Returns (order number, invoice number).
  Future<(int?, String)> order({
    String till = tillA,
    int? branch,
    String status = 'PAID',
    String? invoice,
  }) async {
    final row = (await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, business_id, '
      '  branch_id, terminal_id, invoice_number, order_type, currency, '
      '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status) '
      'VALUES (gen_random_uuid(), @r, @b, @t::uuid, '
      "  coalesce(@inv, 'INV-' || gen_random_uuid()::text), 'takeaway', "
      "  'EGP', 2, 1000, 0, 0, 1000, now(), @status) "
      'RETURNING id, invoice_number',
      parameters: {
        'r': businessId,
        'b': branch ?? branchId,
        't': till,
        'status': status,
        'inv': invoice,
      },
    )).first;
    // Read back rather than RETURNING it: a cloud till's SQLite stamps the
    // number in an AFTER trigger, which RETURNING does not see.
    final number = await one(
      'SELECT day_order_number FROM pos_orders WHERE id = @id',
      {'id': row[0]},
    );
    return (number as int?, row[1] as String);
  }

  /// Only this suite's own business, so a leftover from another suite in the
  /// shared database cannot break this one, and this one leaves nothing behind
  /// for the next. Orders first: a business day an order still points at
  /// cannot be deleted.
  Future<void> removeMine() async {
    const mine = "(SELECT id FROM pos_businesses WHERE slug = 'dayno')";
    for (final sql in [
      'DELETE FROM pos_orders WHERE business_id IN $mine',
      'DELETE FROM pos_business_days WHERE business_id IN $mine',
      'DELETE FROM pos_users WHERE business_id IN $mine',
      'DELETE FROM pos_branches WHERE business_id IN $mine',
      "DELETE FROM pos_businesses WHERE slug = 'dayno'",
    ]) {
      await db.query(pg.config, sql);
    }
  }

  setUp(() async {
    pg = await PgFixture.open('day_order_number');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    // Re-run 67 from its current text, as the stamping suite does for 35/36.
    // PostgreSQL only: its statements are written to be run again, while a
    // cloud till's SQLite upgrade adds a column and is recorded once.
    if (!PgFixture.onSqlite) {
      await db.query(
        pg.config,
        'DELETE FROM schema_migrations WHERE version = 67',
      );
      await PosMigrator(db).migrate(pg.config);
    }
    await removeMine();

    businessId = await one(
      "INSERT INTO pos_businesses (slug, name) "
      "VALUES ('dayno', 'Day No') RETURNING id",
    ) as int;
    branchId = await one(
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'DN1', 'Main') RETURNING id",
      {'r': businessId},
    ) as int;
    otherBranchId = await one(
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'DN2', 'Second') RETURNING id",
      {'r': businessId},
    ) as int;
    staffId = await one(
      'INSERT INTO pos_users (business_id, branch_id, name, '
      "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', "
      "  'nour', 'salt', 'hash') RETURNING id",
      {'r': businessId, 'b': branchId},
    ) as int;
  });

  tearDown(() async {
    await removeMine();
    await pg.close();
  });

  test('the first order of a day is 1 and the next is 2', () async {
    await openDay();

    expect((await order()).$1, 1);
    expect((await order()).$1, 2);
    expect((await order()).$1, 3);
  });

  test('every till of the branch draws from the same count', () async {
    await openDay();

    expect((await order(till: tillA)).$1, 1);
    expect((await order(till: tillB)).$1, 2);
    expect((await order(till: tillA)).$1, 3);
  });

  test(
    'two tills settling at the same instant get different numbers',
    () async {
      await openDay();

      final both = await Future.wait([
        for (var i = 0; i < 12; i++) order(till: i.isEven ? tillA : tillB),
      ]);

      final numbers = both.map((o) => o.$1!).toList()..sort();
      expect(numbers, [for (var i = 1; i <= 12; i++) i]);
    },
  );

  test('the next trading day starts again at 1', () async {
    final first = await openDay();
    await order();
    await order();
    await closeDay(first);
    await openDay(date: '2026-09-11');

    expect((await order()).$1, 1);
  });

  test('the invoice number is whatever the writer gave, untouched', () async {
    await openDay();

    final (n, invoice) = await order(invoice: 'MAIN-2026-000042');

    expect(n, 1);
    expect(invoice, 'MAIN-2026-000042');
  });

  test(
    'a voided order keeps its number and the next is not renumbered',
    () async {
      await openDay();

      expect((await order()).$1, 1);
      expect((await order(status: 'VOIDED')).$1, 2);
      expect((await order()).$1, 3);
    },
  );

  test(
    'with no trading day open there is no number, not an invented one',
    () async {
      expect((await order()).$1, isNull);

      await openDay();
      expect((await order()).$1, 1, reason: 'the gap did not consume a number');
    },
  );

  test('another branch has its own count', () async {
    await openDay();
    await openDay(branch: otherBranchId);

    expect((await order()).$1, 1);
    expect((await order(branch: otherBranchId)).$1, 1);
    expect((await order()).$1, 2);
  });

  test('a writer that names a number keeps it', () async {
    await openDay();

    final row = await one(
      'INSERT INTO pos_orders (client_transaction_id, business_id, '
      '  branch_id, terminal_id, invoice_number, order_type, currency, '
      '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, day_order_number) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, 'X-1', 'takeaway', 'EGP', "
      '  2, 1000, 0, 0, 1000, now(), \'PAID\', 77) RETURNING day_order_number',
      {'r': businessId, 'b': branchId, 't': tillA},
    );
    expect(row, 77);
  });

  test('orders that existed before migration 67 keep a null number', () async {
    await openDay();
    await db.query(pg.config, 'DROP TRIGGER pos_orders_number ON pos_orders');
    await order();
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 67',
    );
    await PosMigrator(db).migrate(pg.config);

    final before = await one(
      'SELECT day_order_number FROM pos_orders ORDER BY id LIMIT 1',
    );
    expect(before, isNull);
    expect((await order()).$1, 1);
  }, skip: PgFixture.onSqlite ? 'drops a PostgreSQL trigger by name' : null);

  test('the number trigger runs after the one that picks the day', () async {
    final names = (await db.query(
      pg.config,
      'SELECT tgname FROM pg_trigger '
      "WHERE tgrelid = 'pos_orders'::regclass AND NOT tgisinternal "
      "  AND tgname IN ('pos_orders_business_day', 'pos_orders_number') "
      'ORDER BY tgname',
    )).map((r) => r[0] as String).toList();

    // Fired in name order: the day is stamped before the number reads it.
    expect(names, ['pos_orders_business_day', 'pos_orders_number']);
  }, skip: PgFixture.onSqlite ? 'reads pg_trigger; SQLite has its own' : null);

  // ── Through the repository: what the till actually calls ──────────────────

  /// A sale paid in cash, no service or tax, so the tender is the price.
  Ticket sale(String id, {LineStage stage = LineStage.draft}) => Ticket(
    id: id,
    orderType: OrderType.takeaway,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
    lines: [
      TicketLine(
        product: const Product(
          id: 501,
          categoryId: 9,
          nameEn: 'Koshari',
          price: Money(5000),
        ),
        quantity: 1,
        stage: stage,
        roundNumber: stage == LineStage.sent ? 1 : null,
      ),
    ],
    tenders: const [Tender(typeId: 1, label: 'Cash', amount: Money(5000))],
  );

  PostgresOrdersRepository till(String terminal) => PostgresOrdersRepository(
    database: db,
    config: pg.config,
    context: PosWriteContext(
      businessId: businessId,
      branchId: branchId,
      terminalId: terminal,
      branchCode: 'DN1',
    ),
  );

  group('through the repository', () {
    test('two tills of one branch get 1 then 2, and the invoice numbers go on '
        'as they did', () async {
      await openDay();

      final a = await till(tillA)
          .submit(sale('a1111111-1111-4111-8111-111111111111'));
      final b = await till(tillB)
          .submit(sale('b2222222-2222-4222-8222-222222222222'));

      expect(a.dayOrderNumber, 1);
      expect(b.dayOrderNumber, 2);
      expect(a.invoiceNumber, endsWith('-000001'));
      expect(b.invoiceNumber, endsWith('-000002'));
      expect(a.invoiceNumber, startsWith('DN1-'));
    });

    test('a replay returns the same number and spends none', () async {
      await openDay();
      const id = 'c3333333-3333-4333-8333-333333333333';

      final first = await till(tillA).submit(sale(id));
      final replay = await till(tillB).submit(sale(id));
      final next = await till(tillA)
          .submit(sale('d4444444-4444-4444-8444-444444444444'));

      expect(replay.dayOrderNumber, first.dayOrderNumber);
      expect(replay.invoiceNumber, first.invoiceNumber);
      expect(next.dayOrderNumber, 2, reason: 'the replay consumed nothing');
    });

    test(
      'a voided order keeps a number and the next order follows it',
      () async {
        await openDay();
        final manager = PosStaff(
          id: staffId,
          name: 'Nour Adel',
          role: const PosRole(
            id: 1,
            code: SystemRoles.supervisorCode,
            nameEn: 'Supervisor',
            capabilities: SystemRoles.supervisor,
          ),
        );

        final voided = await till(tillA).voidOrder(
          sale('e5555555-5555-4555-8555-555555555555', stage: LineStage.sent),
          by: manager,
        );
        final after = await till(tillB)
            .submit(sale('f6666666-6666-4666-8666-666666666666'));

        expect(voided.dayOrderNumber, 1);
        expect(after.dayOrderNumber, 2);
      },
    );

    test('with no trading day open the result carries no number', () async {
      final result = await till(tillA)
          .submit(sale('a7777777-7777-4777-8777-777777777777'));

      expect(result.dayOrderNumber, isNull);
      expect(result.invoiceNumber, isNotNull);
    });
  });
}
