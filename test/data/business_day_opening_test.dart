@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_business_day_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart'
    show PosWriteContext;
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/pos_settings.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/business_day_service.dart';

import 'pg_fixture.dart';

/// Opening the trading day against the real database (report 2026-10-24,
/// Part 4): the one-open-day index, the closed-date refusal and the trigger that
/// stamps a shift from the open day.
///
/// **Written but not yet run** — it needs a dedicated PostgreSQL, and the
/// shared server was left in doubt by the missing-databases incident in the
/// report. Run it with `POS_PG_HOST` pointing at a server you can afford to
/// lose; it creates and uses only its own `xorder_pos_business_day_opening_*`
/// database.
void main() {
  if (PgFixture.host == null) {
    test('business day opening (skipped — set POS_PG_HOST)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late PostgresBusinessDayRepository days;
  late PosStaff nour;

  const terminal = '55555555-5555-4555-8555-555555555555';
  const policy = DayPolicy(); // 06:00 roll-over

  setUp(() async {
    pg = await PgFixture.open('business_day_opening');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_business_days, pos_orders, pos_shifts, '
      '  pos_parked_tickets RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_restaurants (slug, name) "
              "VALUES ('bdo', 'Day Opening') RETURNING id",
            )).first[0]
            as int;
    branchId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_branches (restaurant_id, code, name) "
              "VALUES (@r, 'BD1', 'Main') RETURNING id",
              parameters: {'r': restaurantId},
            )).first[0]
            as int;
    final staffId =
        (await db.query(
              pg.config,
              'INSERT INTO pos_staff (restaurant_id, branch_id, name, '
              "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', "
              "  'nour', 'salt', 'hash') RETURNING id",
              parameters: {'r': restaurantId, 'b': branchId},
            )).first[0]
            as int;
    nour = PosStaff(
      id: staffId,
      name: 'Nour Adel',
      role: const PosRole(
        id: 1,
        code: SystemRoles.managerCode,
        nameEn: 'Manager',
        capabilities: SystemRoles.manager,
      ),
    );
    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'Counter 1') ON CONFLICT (id) DO NOTHING",
      parameters: {'t': terminal, 'r': restaurantId, 'b': branchId},
    );

    days = PostgresBusinessDayRepository(
      database: db,
      config: pg.config,
      context: PosWriteContext(
        restaurantId: restaurantId,
        branchId: branchId,
        terminalId: terminal,
        branchCode: 'BD1',
      ),
    );
  });

  tearDown(() => pg.close());

  Future<Object?> shiftDay() async => (await db.query(
    pg.config,
    'INSERT INTO pos_shifts (restaurant_id, branch_id, terminal_id, opened_by, '
    '  opening_float_minor) VALUES (@r, @b, @t::uuid, @by, 0) '
    'RETURNING business_day_id',
    parameters: {
      'r': restaurantId,
      'b': branchId,
      't': terminal,
      'by': nour.id,
    },
  )).first[0];

  test('opens a day, and a shift written after it is filed under it', () async {
    final result = await ensureBusinessDay(
      days: days,
      policy: policy,
      now: DateTime(2026, 10, 24, 14),
      by: nour,
    );
    expect(result.outcome, BusinessDayOutcome.opened);

    expect(await shiftDay(), result.day!.id);

    // Opened on behalf of the person opening, and filed by its own window
    // (migration 36): the day's `opened_at` is not after the shift's.
    final row = (await db.query(
      pg.config,
      'SELECT opened_by, business_date::text FROM pos_business_days',
    )).first;
    expect(row[0], nour.id);
    expect(row[1], '2026-10-24');
  });

  test('a shift written with no day open stays unfiled, as before', () async {
    expect(await shiftDay(), isNull);
  });

  test('asking twice opens one day', () async {
    final now = DateTime(2026, 10, 24, 14);
    await ensureBusinessDay(days: days, policy: policy, now: now, by: nour);
    final again = await ensureBusinessDay(
      days: days,
      policy: policy,
      now: now,
      by: nour,
    );

    expect(again.outcome, BusinessDayOutcome.reused);
    final rows = await db.query(
      pg.config,
      'SELECT count(*) FROM pos_business_days',
    );
    expect(rows.first[0], 1);
  });

  test('a day left open from an earlier date is used, not doubled', () async {
    // The one-open-day index would refuse a second row; the service must not
    // even try.
    await days.open(date: DateTime(2026, 10, 22), by: nour);
    final result = await ensureBusinessDay(
      days: days,
      policy: policy,
      now: DateTime(2026, 10, 24, 9),
      by: nour,
    );

    expect(result.outcome, BusinessDayOutcome.reused);
    expect(result.day!.date.day, 22);
    final rows = await db.query(
      pg.config,
      'SELECT count(*) FROM pos_business_days',
    );
    expect(rows.first[0], 1);
  });

  test('two tills opening together end up in the same single day', () async {
    final now = DateTime(2026, 10, 24, 6);
    final results = await Future.wait([
      for (var i = 0; i < 4; i++)
        ensureBusinessDay(days: days, policy: policy, now: now, by: nour),
    ]);

    expect(
      results.map((r) => r.outcome),
      everyElement(anyOf(BusinessDayOutcome.opened, BusinessDayOutcome.reused)),
    );
    expect(results.map((r) => r.day!.id).toSet(), hasLength(1));
    final rows = await db.query(
      pg.config,
      'SELECT count(*) FROM pos_business_days',
    );
    expect(rows.first[0], 1);
  });

  test('tills straddling the 06:00 roll-over end in one day, not an error', () async {
    // 05:59 belongs to yesterday and 06:00 to today, so two tills starting at
    // the roll-over ask for DIFFERENT dates at once. Both inserts target other
    // rows, so `ON CONFLICT` does not catch the loser: the one-open-day index
    // does. The service must take the winner's day.
    final results = await Future.wait([
      ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 24, 5, 59),
        by: nour,
      ),
      ensureBusinessDay(
        days: days,
        policy: policy,
        now: DateTime(2026, 10, 24, 6),
        by: nour,
      ),
    ]);

    expect(
      results.map((r) => r.outcome),
      everyElement(anyOf(BusinessDayOutcome.opened, BusinessDayOutcome.reused)),
    );
    expect(results.map((r) => r.day!.id).toSet(), hasLength(1));
    final rows = await db.query(
      pg.config,
      'SELECT count(*) FROM pos_business_days',
    );
    expect(rows.first[0], 1);
  });

  test('a closed date is reported, and nothing is reopened', () async {
    final day = await days.open(date: DateTime(2026, 10, 24), by: nour);
    await days.close(day: day, by: nour);

    final result = await ensureBusinessDay(
      days: days,
      policy: policy,
      now: DateTime(2026, 10, 24, 23, 30),
      by: nour,
    );

    expect(result.outcome, BusinessDayOutcome.dateAlreadyClosed);
    expect(await days.current(), isNull);
  });
}
