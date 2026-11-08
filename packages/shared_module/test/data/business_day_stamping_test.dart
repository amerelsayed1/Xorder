@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Every sale, refund and shift is filed under the trading day it happened in.
///
/// Nothing wrote `business_day_id` before migrations 35 and 36 — not the two
/// order inserts, the refund insert or the shift insert — so the day close,
/// which totals by that column alone, recorded gross and net of 0 for every day
/// it closed. The history screen and the branch view had each learned to fall
/// back to the day's opening and closing times; the close had not.
///
/// A trigger does the stamping now, by the rule every reader already used: the
/// day whose window CONTAINS the moment. Migration 35's first version stamped
/// whichever day was open at the moment of writing instead, and the branch
/// view's tests caught the two rules disagreeing by one sale — so the dated
/// case below is the one that matters most.
///
/// `setUp` re-runs 35 and 36 every time, so what is tested is the migration
/// text as it stands, not whatever a persistent test database recorded the
/// first time it ever ran them.
void main() {
  if (PgFixture.host == null) {
    test(
      'trading-day stamping (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int staffId;
  late int cashTender;

  const terminal = '44444444-4444-4444-8444-444444444444';

  Future<Object?> one(
    String sql, [
    Map<String, Object?> parameters = const {},
  ]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0];

  /// A trading day at [branch], opened [hoursAgo] hours ago.
  Future<int> openDay({
    int? branch,
    String date = '2026-09-10',
    int hoursAgo = 0,
  }) async =>
      await one(
            'INSERT INTO pos_business_days (business_id, branch_id, '
            '  business_date, opened_by, opened_at) '
            'VALUES (@r, @b, @d::date, @by, '
            '  now() - make_interval(hours => @h::int)) RETURNING id',
            {
              'r': businessId,
              'b': branch ?? branchId,
              'd': date,
              'by': staffId,
              'h': hoursAgo,
            },
          )
          as int;

  Future<void> closeDay(int day, {int hoursAgo = 0}) => db.query(
    pg.config,
    'UPDATE pos_business_days '
    '   SET closed_at = now() - make_interval(hours => @h::int), '
    '       closed_by = @by '
    ' WHERE id = @id',
    parameters: {'id': day, 'by': staffId, 'h': hoursAgo},
  );

  /// A sale dated [hoursAgo] hours ago. The day is left for the database to
  /// decide unless [day] names one. Returns the row's id and the day it got.
  Future<(int, int?)> sale({
    int? branch,
    int total = 1000,
    int hoursAgo = 0,
    int? day,
    String status = 'PAID',
  }) async {
    final row = (await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, business_id, '
      '  branch_id, terminal_id, invoice_number, order_type, currency, '
      '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, business_day_id) '
      'VALUES (gen_random_uuid(), @r, @b, @t::uuid, '
      "  'INV-' || gen_random_uuid()::text, 'takeaway', 'EGP', 2, "
      '  @total, 0, 0, @total, now() - make_interval(hours => @h::int), '
      '  @status, @day::bigint) '
      'RETURNING id, business_day_id',
      parameters: {
        'r': businessId,
        'b': branch ?? branchId,
        't': terminal,
        'total': total,
        'h': hoursAgo,
        'status': status,
        'day': day,
      },
    )).first;
    return (row[0] as int, row[1] as int?);
  }

  /// A refund of 500 and the 500 tendered back, in ONE statement. The
  /// database refuses a refund that does not foot against what went back
  /// across the counter — checked at commit (`pos_refunds_tendered_in_full`),
  /// so both rows have to arrive together.
  Future<int?> refundOf(int orderId, {int hoursAgo = 0}) async =>
      await one(
            'WITH r AS ('
            '  INSERT INTO pos_refunds (client_refund_id, business_id, '
            '    branch_id, terminal_id, order_id, kind, subtotal_minor, '
            '    service_minor, vat_minor, total_minor, refunded_by, '
            '    occurred_at) '
            "  VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, 'partial', "
            '    500, 0, 0, 500, @by, now() - make_interval(hours => @h::int)) '
            '  RETURNING id, business_day_id'
            '), tendered AS ('
            '  INSERT INTO pos_refund_payments (refund_id, tender_type_id, '
            '    label, amount_minor, counts_as_cash) '
            "  SELECT id, @tt, 'Cash', 500, true FROM r"
            ') SELECT business_day_id FROM r',
            {
              'r': businessId,
              'b': branchId,
              't': terminal,
              'o': orderId,
              'by': staffId,
              'h': hoursAgo,
              'tt': cashTender,
            },
          )
          as int?;

  Future<int?> shift({int hoursAgo = 0}) async =>
      await one(
            'INSERT INTO pos_shifts (business_id, branch_id, terminal_id, '
            '  opened_by, opened_at) '
            'VALUES (@r, @b, @t::uuid, @by, '
            '  now() - make_interval(hours => @h::int)) '
            'RETURNING business_day_id',
            {
              'r': businessId,
              'b': branchId,
              't': terminal,
              'by': staffId,
              'h': hoursAgo,
            },
          )
          as int?;

  /// The day close's own formula — `postgres_business_day_repository.dart`.
  Future<int> takingsOf(int day) async =>
      await one(
            'SELECT coalesce(sum(total_minor), 0)::bigint FROM pos_orders '
            'WHERE business_day_id = @day '
            "  AND status IN ('PAID', 'CLOSED', 'PARTIALLY_REFUNDED', "
            "  'REFUNDED')",
            {'day': day},
          )
          as int;

  /// Run 35 and 36 again from their current text.
  Future<void> rerunStamping() async {
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version IN (35, 36)',
    );
    await PosMigrator(db).migrate(pg.config);
  }

  setUp(() async {
    pg = await PgFixture.open('business_day_stamping');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await rerunStamping();
    await db.query(
      pg.config,
      'TRUNCATE pos_business_days, pos_refund_payments, pos_refunds, '
      '  pos_orders, pos_shifts, pos_terminals, pos_tender_types '
      'RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        await one(
              "INSERT INTO pos_businesses (slug, name) "
              "VALUES ('stamp', 'Stamp') RETURNING id",
            )
            as int;
    branchId =
        await one(
              "INSERT INTO pos_branches (business_id, code, name) "
              "VALUES (@r, 'ST1', 'Main') RETURNING id",
              {'r': businessId},
            )
            as int;
    otherBranchId =
        await one(
              "INSERT INTO pos_branches (business_id, code, name) "
              "VALUES (@r, 'ST2', 'Second') RETURNING id",
              {'r': businessId},
            )
            as int;
    staffId =
        await one(
              'INSERT INTO pos_users (business_id, branch_id, name, '
              "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', "
              "  'nour', 'salt', 'hash') RETURNING id",
              {'r': businessId, 'b': branchId},
            )
            as int;

    cashTender =
        await one(
              'INSERT INTO pos_tender_types (business_id, code, name_en, '
              "  kind, counts_as_cash) VALUES (@r, 'cash', 'Cash', 'cash', "
              '  true) RETURNING id',
              {'r': businessId},
            )
            as int;

    // A shift names its till by foreign key; an order and a refund do not,
    // which is why only the shift case needed the till registered.
    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'POS-01')",
      parameters: {'t': terminal, 'r': businessId, 'b': branchId},
    );
  });

  tearDown(() => pg.close());

  test('a sale rung up during the day is filed under it', () async {
    final day = await openDay(hoursAgo: 2);

    final (_, filed) = await sale();

    expect(filed, day);
  });

  test('and so are its refund and the shift it was rung up on', () async {
    final day = await openDay(hoursAgo: 2);

    expect(await shift(), day);
    final (order, _) = await sale();
    expect(await refundOf(order), day);
  });

  test('the day close sees the takings — the bug itself', () async {
    // Before the trigger this was 0 for every day, because nothing filed a
    // sale under any day and the close totals by that column alone.
    final day = await openDay(hoursAgo: 2);
    await sale(total: 1000);
    await sale(total: 2500);
    await sale(total: 700, status: 'VOIDED');

    expect(await takingsOf(day), 3500, reason: 'the void is not takings');
  });

  test('nothing open, nothing filed', () async {
    final (_, filed) = await sale();

    expect(filed, isNull, reason: 'a sale outside any trading day is unfiled');
  });

  test("another branch's open day is never borrowed", () async {
    await openDay(branch: otherBranchId, hoursAgo: 2);

    final (_, filed) = await sale();

    expect(filed, isNull);
  });

  test('a sale dated into another day is filed under THAT day', () async {
    // The case the first version of the trigger got wrong: it filed by
    // whichever day was open when the row was written, so this sale went into
    // today while every reader filed it under yesterday.
    final yesterday = await openDay(date: '2026-09-09', hoursAgo: 30);
    await closeDay(yesterday, hoursAgo: 20);
    final today = await openDay(hoursAgo: 2);

    final (_, duringYesterday) = await sale(hoursAgo: 25);
    final (_, betweenTheTwo) = await sale(hoursAgo: 10);
    final (_, duringToday) = await sale(hoursAgo: 1);

    expect(duringYesterday, yesterday);
    expect(betweenTheTwo, isNull, reason: 'no day was open at that moment');
    expect(duringToday, today);
  });

  test('a row that names its day keeps it', () async {
    final earlier = await openDay(date: '2026-09-09', hoursAgo: 30);
    await closeDay(earlier, hoursAgo: 20);
    await openDay(hoursAgo: 2);

    final (_, filed) = await sale(day: earlier);

    expect(filed, earlier);
  });

  test('rows written before the trigger are filed, and the closed day '
      'recounted', () async {
    // A row from before 35 — the trigger switched off to write it the way the
    // old code did — inside a day that was then closed with the bug's 0.
    final day = await openDay(date: '2026-09-09', hoursAgo: 30);
    await db.query(
      pg.config,
      'ALTER TABLE pos_orders DISABLE TRIGGER pos_orders_business_day',
    );
    final (order, unfiled) = await sale(total: 4200, hoursAgo: 25);
    await db.query(
      pg.config,
      'ALTER TABLE pos_orders ENABLE TRIGGER pos_orders_business_day',
    );
    expect(unfiled, isNull, reason: 'written the way the old code wrote it');

    await closeDay(day, hoursAgo: 20);
    await db.query(
      pg.config,
      'UPDATE pos_business_days SET gross_minor = 0, net_minor = 0 '
      'WHERE id = @id',
      parameters: {'id': day},
    );

    await rerunStamping();

    expect(
      await one(
        'SELECT business_day_id FROM pos_orders WHERE id = @id',
        {'id': order},
      ),
      day,
    );
    expect(
      await one(
        'SELECT gross_minor FROM pos_business_days WHERE id = @id',
        {'id': day},
      ),
      4200,
      reason: 'the recorded 0 was the bug; the rows it was summed from are not',
    );
  });
}
