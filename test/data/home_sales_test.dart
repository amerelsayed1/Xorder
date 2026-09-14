@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_branch_sales_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_business_day_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart'
    show PosWriteContext;
import 'package:xorder_pos/domain/models/home_sales.dart';
import 'package:xorder_pos/features/admin/application/back_office_home.dart';

import 'pg_fixture.dart';

/// Home's tiles against PostgreSQL (BO-4, plan 19 §2.1).
///
/// The two days, in piastres (UTC):
///
/// | | yesterday (06:00–23:00) | today (opened 06:00) |
/// |---|---|---|
/// | 07:00 | | POS-01 sells 15,000 (500 off) |
/// | 08:00 | POS-01 sells 10,000 (1,000 off) | |
/// | 09:00 | | POS-02 sells 30,000 |
/// | 09:30 | POS-02 refunds 500 | |
/// | 09:45 | | POS-01 refunds 2,000 |
/// | 11:00 | POS-02 sells 20,000 | |
/// | 20:00 | POS-01 sells 40,000 | |
///
/// "Now" is today at 10:00 — four hours in — so yesterday is cut at 10:00:
/// one sale and one refund, not the whole 70,000.
void main() {
  if (PgFixture.host == null) {
    test('home sales (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const pos01 = '20000000-0000-4000-8000-000000000001';
  const pos02 = '20000000-0000-4000-8000-000000000002';
  final now = DateTime.utc(2026, 9, 10, 10);

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int quietBranchId;
  late int staffId;
  late int cash;
  late int yesterday;
  late int today;
  late PostgresBranchSalesRepository sales;
  late PostgresBusinessDayRepository days;
  var invoice = 0;

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0] as int;

  Future<int> sale({
    required String terminal,
    required int total,
    required int day,
    required DateTime at,
    int discount = 0,
  }) async {
    invoice++;
    final id = await scalar(
      'INSERT INTO pos_orders (client_transaction_id, restaurant_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, business_day_id) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @inv, 'dine_in', 'EGP', 2, "
      "  @sub, @disc, 0, 0, @total, @at::timestamptz, 'PAID', @day) "
      'RETURNING id',
      {
        'r': restaurantId,
        'b': branchId,
        't': terminal,
        'inv': 'HS-$invoice',
        'sub': total + discount,
        'disc': discount,
        'total': total,
        'at': at,
        'day': day,
      },
    );
    await db.query(
      pg.config,
      'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
      "  amount_minor, counts_as_cash) VALUES (@o, @tt, 'cash', @amount, true)",
      parameters: {'o': id, 'tt': cash, 'amount': total},
    );
    return id;
  }

  /// One transaction: the tender check is a deferred constraint trigger.
  Future<void> refund({
    required int orderId,
    required String issuedBy,
    required int total,
    required int day,
    required DateTime at,
  }) => db.runTx(pg.config, (tx) async {
    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO pos_refunds (client_refund_id, restaurant_id, branch_id, '
        '  terminal_id, order_id, business_day_id, kind, subtotal_minor, '
        '  service_minor, vat_minor, total_minor, refunded_by, occurred_at) '
        'VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, @day, '
        "  'partial', @total, 0, 0, @total, @by, @at::timestamptz) RETURNING id",
      ),
      parameters: {
        'r': restaurantId,
        'b': branchId,
        't': issuedBy,
        'o': orderId,
        'day': day,
        'total': total,
        'by': staffId,
        'at': at,
      },
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
        "  amount_minor, counts_as_cash) VALUES (@id, @tt, 'cash', @total, true)",
      ),
      parameters: {'id': rows.first[0], 'tt': cash, 'total': total},
    );
  });

  Future<int> day(String date, DateTime opened, {DateTime? closed}) => scalar(
    'INSERT INTO pos_business_days (restaurant_id, branch_id, business_date, '
    '  opened_at, closed_at, closed_by) '
    'VALUES (@r, @b, @d::date, @o::timestamptz, @c::timestamptz, @by::bigint) '
    'RETURNING id',
    {
      'r': restaurantId,
      'b': branchId,
      'd': date,
      'o': opened,
      'c': closed,
      'by': closed == null ? null : staffId,
    },
  );

  PostgresBusinessDayRepository daysAt(int branch) =>
      PostgresBusinessDayRepository(
        database: db,
        config: pg.config,
        context: PosWriteContext(
          restaurantId: restaurantId,
          branchId: branch,
          terminalId: pos01,
          branchCode: 'HOME',
        ),
      );

  setUp(() async {
    pg = await PgFixture.open('home_sales');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_outbox, pos_refunds, pos_orders, pos_business_days, '
      'pos_invoice_sequences RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_restaurants');
    invoice = 0;

    restaurantId = await scalar(
      "INSERT INTO pos_restaurants (slug, name) VALUES ('hs', 'Home sales') "
      'RETURNING id',
    );
    branchId = await scalar(
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'HOME', 'Zamalek') RETURNING id",
      {'r': restaurantId},
    );
    quietBranchId = await scalar(
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'NEW', 'New Cairo') RETURNING id",
      {'r': restaurantId},
    );
    staffId = await scalar(
      'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', 'nour', 'salt', "
      "  'hash') RETURNING id",
      {'r': restaurantId, 'b': branchId},
    );
    cash = await scalar(
      'INSERT INTO pos_tender_types (restaurant_id, code, name_en, kind, '
      "  counts_as_cash) VALUES (@r, 'cash', 'Cash', 'cash', true) RETURNING id",
      {'r': restaurantId},
    );
    for (final (id, name) in [(pos01, 'POS-01'), (pos02, 'POS-02')]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
        'VALUES (@id::uuid, @r, @b, @name)',
        parameters: {'id': id, 'r': restaurantId, 'b': branchId, 'name': name},
      );
    }

    yesterday = await day(
      '2026-09-09',
      DateTime.utc(2026, 9, 9, 6),
      closed: DateTime.utc(2026, 9, 9, 23),
    );
    today = await day('2026-09-10', DateTime.utc(2026, 9, 10, 6));

    final early = await sale(
      terminal: pos01,
      total: 10000,
      discount: 1000,
      day: yesterday,
      at: DateTime.utc(2026, 9, 9, 8),
    );
    await refund(
      orderId: early,
      issuedBy: pos02,
      total: 500,
      day: yesterday,
      at: DateTime.utc(2026, 9, 9, 9, 30),
    );
    await sale(
      terminal: pos02,
      total: 20000,
      day: yesterday,
      at: DateTime.utc(2026, 9, 9, 11),
    );
    await sale(
      terminal: pos01,
      total: 40000,
      day: yesterday,
      at: DateTime.utc(2026, 9, 9, 20),
    );

    final first = await sale(
      terminal: pos01,
      total: 15000,
      discount: 500,
      day: today,
      at: DateTime.utc(2026, 9, 10, 7),
    );
    await sale(
      terminal: pos02,
      total: 30000,
      day: today,
      at: DateTime.utc(2026, 9, 10, 9),
    );
    await refund(
      orderId: first,
      issuedBy: pos01,
      total: 2000,
      day: today,
      at: DateTime.utc(2026, 9, 10, 9, 45),
    );

    sales = PostgresBranchSalesRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
    );
    days = daysAt(branchId);
  });

  tearDown(() => pg.close());

  test('each tile is BranchSales for the current business day', () async {
    final home = (await readHomeSales(days: days, sales: sales, now: now))!;
    final direct = (await sales.summary(DateTime(2026, 9, 10))).sales!;

    expect(home.day.id, today);
    expect(home.isOpen, isTrue);
    expect(home.sales.net, direct.net);
    expect(home.sales.orders, direct.orders);
    expect(home.average, averageOrder(direct));

    // And what those are: 45,000 taken, 2,000 back, over two sales.
    expect(direct.net.minor, 43000);
    expect(direct.orders, 2);
    expect(home.average!.minor, 21500);
  });

  test('the delta is against the previous day cut at the same time since '
      'opening — not the whole day', () async {
    final home = (await readHomeSales(days: days, sales: sales, now: now))!;
    final whole = (await sales.summary(DateTime(2026, 9, 9))).sales!;

    expect(home.previousDay!.id, yesterday);
    // By 10:00 yesterday: the 08:00 sale and the 09:30 refund, and nothing
    // after. 11,000 gross − 1,000 off − 500 back.
    expect(home.previous!.orders, 1);
    expect(home.previous!.net.minor, 9500);
    expect(whole.orders, 3, reason: 'the whole day is not what is compared');

    expect(home.ordersDeltaBp, 10000);
    expect(home.netDeltaBp, deltaBp(43000, 9500));
  });

  test('the cut is the same statement: at the close it is the whole day, '
      'before the opening it is nothing — and every terminal is still '
      'listed', () async {
    final day = DateTime(2026, 9, 9);
    final whole = (await sales.summary(day)).sales!;
    final atClose = (await sales.summary(
      day,
      until: DateTime.utc(2026, 9, 9, 23),
    )).sales!;
    final beforeOpening = (await sales.summary(
      day,
      until: DateTime.utc(2026, 9, 9, 6),
    )).sales!;

    expect(atClose.net, whole.net);
    expect(atClose.orders, whole.orders);
    expect(atClose.collected, whole.collected);
    expect(beforeOpening.orders, 0);
    expect(beforeOpening.net.minor, 0);
    expect(beforeOpening.terminals.map((t) => t.terminalId), [pos01, pos02]);
  });

  test('with no day open: the last closed day, held against the same span '
      'of the one before it', () async {
    // Today closed at noon: six hours long.
    await db.query(
      pg.config,
      'UPDATE pos_business_days SET closed_at = @at::timestamptz, closed_by = @by '
      'WHERE id = @id',
      parameters: {
        'at': DateTime.utc(2026, 9, 10, 12),
        'by': staffId,
        'id': today,
      },
    );

    final home = (await readHomeSales(
      days: days,
      sales: sales,
      now: DateTime.utc(2026, 9, 11, 9),
    ))!;

    expect(home.day.id, today);
    expect(home.isOpen, isFalse);
    expect(home.sales.net.minor, 43000);
    // Yesterday to 12:00: both morning sales and the refund, not the 20:00.
    expect(home.previous!.orders, 2);
    expect(home.previous!.net.minor, 29500);
  });

  test('the day before is by business date, not by when it was closed', () async {
    // The 8th, force-closed after the 9th was. Ordered by `closed_at` it
    // would be "the last closed day"; it is the day before yesterday.
    await day(
      '2026-09-08',
      DateTime.utc(2026, 9, 8, 6),
      closed: DateTime.utc(2026, 9, 9, 23, 30),
    );

    expect((await days.lastClosed())!.id, yesterday);
    expect(
      (await days.lastClosed(before: DateTime(2026, 9, 10)))!.id,
      yesterday,
    );
    final home = (await readHomeSales(days: days, sales: sales, now: now))!;
    expect(home.previousDay!.id, yesterday);
  });

  test('a branch that has never traded has no day, and no zeros', () async {
    final quiet = PostgresBranchSalesRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: quietBranchId,
    );
    expect(
      await readHomeSales(days: daysAt(quietBranchId), sales: quiet, now: now),
      isNull,
    );
  });
}
