@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

import 'pg_fixture.dart';

/// Migration 14 — settings, the drawer and the trading day.
///
/// Asserted against PostgreSQL because these are the rules that have to hold
/// whatever writes them. Two open business days for one branch is two sets of
/// takings for one evening, and nothing downstream could tell which was which.
void main() {
  if (PgFixture.host == null) {
    test('wave B schema (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int otherBranchId;
  late int staffId;
  late int shiftId;

  const terminal = '33333333-3333-4333-8333-333333333333';

  Future<int> openDay({
    String date = '2026-09-08',
    int? branch,
    bool close = false,
    bool forced = false,
    String? forceReason,
  }) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_business_days (restaurant_id, branch_id, business_date, '
      '  opened_by, closed_at, closed_by, forced, force_reason) '
      'VALUES (@r, @b, @d::date, @by::bigint, '
      '  CASE WHEN @close::boolean THEN now() ELSE NULL END, '
      '  CASE WHEN @close::boolean THEN @by::bigint ELSE NULL END, '
      '  @forced::boolean, @reason::text) RETURNING id',
      parameters: {
        'r': restaurantId,
        'b': branch ?? branchId,
        'd': date,
        'by': staffId,
        'close': close,
        'forced': forced,
        'reason': forceReason,
      },
    );
    return rows.first[0] as int;
  }

  Future<int> movement({
    String kind = 'pay_out',
    int amount = 5000,
    int? shift,
  }) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_cash_movements (restaurant_id, branch_id, terminal_id, '
      '  shift_id, kind, amount_minor, user_id) '
      'VALUES (@r, @b, @t::uuid, @s, @kind, @amount, @staff) RETURNING id',
      parameters: {
        'r': restaurantId,
        'b': branchId,
        't': terminal,
        's': shift ?? shiftId,
        'kind': kind,
        'amount': amount,
        'staff': staffId,
      },
    );
    return rows.first[0] as int;
  }

  Future<void> setting({
    String scope = 'restaurant',
    String scopeId = '',
    String key = 'day.start_time',
    String value = '06:00',
  }) => db.query(
    pg.config,
    'INSERT INTO pos_settings (restaurant_id, scope, scope_id, key, value) '
    'VALUES (@r, @scope, @scopeId, @key, @value)',
    parameters: {
      'r': restaurantId,
      'scope': scope,
      'scopeId': scopeId,
      'key': key,
      'value': value,
    },
  );

  setUp(() async {
    pg = await PgFixture.open('wave_b_schema');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_business_days, pos_cash_movements, pos_settings, '
      '  pos_orders, pos_shifts RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_restaurants (slug, name) "
                  "VALUES ('day', 'Day') RETURNING id",
                ))
                .first[0]
            as int;
    branchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (restaurant_id, code, name) "
                  "VALUES (@r, 'DY1', 'Main') RETURNING id",
                  parameters: {'r': restaurantId},
                ))
                .first[0]
            as int;
    otherBranchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (restaurant_id, code, name) "
                  "VALUES (@r, 'DY2', 'Second') RETURNING id",
                  parameters: {'r': restaurantId},
                ))
                .first[0]
            as int;
    staffId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_users (restaurant_id, branch_id, name, '
                  "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', "
                  "  'nour', 'salt', 'hash') RETURNING id",
                  parameters: {'r': restaurantId, 'b': branchId},
                ))
                .first[0]
            as int;

    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'Counter 1') "
      'ON CONFLICT (id) DO NOTHING',
      parameters: {'t': terminal, 'r': restaurantId, 'b': branchId},
    );

    shiftId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_shifts (restaurant_id, branch_id, '
                  '  terminal_id, opened_by, opening_float_minor) '
                  'VALUES (@r, @b, @t::uuid, @by, 20000) RETURNING id',
                  parameters: {
                    'r': restaurantId,
                    'b': branchId,
                    't': terminal,
                    'by': staffId,
                  },
                ))
                .first[0]
            as int;
  });

  tearDown(() => pg.close());

  group('the business day', () {
    test('one branch may only have one day open at a time', () async {
      // Two open days is two sets of takings for one evening, and nothing
      // downstream could tell which was which.
      await openDay(date: '2026-09-08');
      await expectLater(openDay(date: '2026-09-09'), throwsA(anything));
    });

    test('a second day opens once the first is closed', () async {
      await openDay(date: '2026-09-08', close: true);
      await openDay(date: '2026-09-09');
    });

    test('another branch keeps its own open day', () async {
      // The index is per branch. One shop closing does not gate another.
      await openDay(date: '2026-09-08');
      await openDay(date: '2026-09-08', branch: otherBranchId);
    });

    test('the same date cannot be opened twice for one branch', () async {
      await openDay(date: '2026-09-08', close: true);
      await expectLater(
        openDay(date: '2026-09-08', close: true),
        throwsA(anything),
      );
    });

    test('a half-closed day is refused', () async {
      // A closing time with nobody against it is a day that says it ended and
      // refuses to say who ended it.
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_business_days (restaurant_id, branch_id, '
          "  business_date, closed_at) VALUES (@r, @b, '2026-09-08'::date, now())",
          parameters: {'r': restaurantId, 'b': branchId},
        ),
        throwsA(anything),
      );
    });

    test('a forced close must say why', () async {
      // The row somebody would want to leave.
      await expectLater(
        openDay(close: true, forced: true),
        throwsA(anything),
      );
      await expectLater(
        openDay(close: true, forced: true, forceReason: ''),
        throwsA(anything),
      );
    });

    test('a forced close with a reason is accepted', () async {
      await openDay(
        close: true,
        forced: true,
        forceReason: 'Till crashed with a table open',
      );
    });
  });

  group('cash movements', () {
    test('a pay-out is recorded', () async {
      final id = await movement(kind: 'pay_out', amount: 5000);
      final rows = await db.query(
        pg.config,
        'SELECT kind, amount_minor FROM pos_cash_movements WHERE id = @id',
        parameters: {'id': id},
      );
      expect(rows.first[0], 'pay_out');
      // Positive, with the kind carrying the direction. A negative amount under
      // `pay_out` would be negated twice by anything that reads the kind.
      expect(rows.first[1], 5000);
    });

    test('a negative amount is refused whatever the kind', () async {
      for (final kind in ['pay_in', 'pay_out', 'float_adjust']) {
        await expectLater(
          movement(kind: kind, amount: -100),
          throwsA(anything),
          reason: kind,
        );
      }
    });

    test('a movement of nothing is refused', () async {
      await expectLater(movement(kind: 'pay_in', amount: 0), throwsA(anything));
    });

    test('opening the drawer moves nothing, and must not claim to', () async {
      await movement(kind: 'drawer_open', amount: 0);
      await expectLater(
        movement(kind: 'drawer_open', amount: 100),
        throwsA(anything),
      );
    });

    test('an unknown kind is refused', () async {
      await expectLater(movement(kind: 'tip_out'), throwsA(anything));
    });

    test('cash cannot move without a shift', () async {
      // Unlike an order, which may be unattributed. A movement nobody can
      // attribute to a shift is one nothing can reconcile.
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_cash_movements (restaurant_id, branch_id, '
          "  terminal_id, kind, amount_minor, user_id) "
          "VALUES (@r, @b, @t::uuid, 'pay_in', 1000, @staff)",
          parameters: {
            'r': restaurantId,
            'b': branchId,
            't': terminal,
            'staff': staffId,
          },
        ),
        throwsA(anything),
      );
    });

    test('deleting the shift is refused, not cascaded', () async {
      await movement();
      await expectLater(
        db.query(
          pg.config,
          'DELETE FROM pos_shifts WHERE id = @id',
          parameters: {'id': shiftId},
        ),
        throwsA(anything),
      );
    });

    test('deleting the staff who moved the money is refused', () async {
      await movement();
      await expectLater(
        db.query(
          pg.config,
          'DELETE FROM pos_users WHERE id = @id',
          parameters: {'id': staffId},
        ),
        throwsA(anything),
      );
    });
  });

  group('settings', () {
    test('one value per key per scope', () async {
      await setting(value: '06:00');
      await expectLater(setting(value: '04:00'), throwsA(anything));
    });

    test('the same key may differ by scope', () async {
      // A branch that opens later than the restaurant's default.
      await setting(value: '06:00');
      await setting(scope: 'branch', scopeId: '$branchId', value: '04:00');
      await setting(scope: 'terminal', scopeId: terminal, value: '05:00');

      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_settings WHERE restaurant_id = @r '
        "AND key = 'day.start_time'",
        parameters: {'r': restaurantId},
      );
      expect(rows.first[0], 3);
    });

    test('a restaurant-scoped row names no scope', () async {
      await expectLater(
        setting(scope: 'restaurant', scopeId: '$branchId'),
        throwsA(anything),
      );
    });

    test('a narrower scope must name one', () async {
      // Otherwise the uniqueness constraint would let one empty-scoped branch
      // row exist per restaurant, meaning nothing.
      await expectLater(
        setting(scope: 'branch', scopeId: ''),
        throwsA(anything),
      );
    });

    test('an unknown scope is refused', () async {
      await expectLater(
        setting(scope: 'company', scopeId: '1'),
        throwsA(anything),
      );
    });
  });

  group('the late foreign keys', () {
    test('an order cannot name a business day that does not exist', () async {
      // The column has been a bare bigint since migration 9 so that Wave A's
      // writes could stamp it from the day this table existed.
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_orders (client_transaction_id, restaurant_id, '
          '  branch_id, terminal_id, invoice_number, order_type, currency, '
          '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
          '  occurred_at, business_day_id) '
          "VALUES (gen_random_uuid(), @r, @b, @t::uuid, 'INV-X', 'dine_in', "
          "  'EGP', 2, 1000, 0, 0, 1000, now(), 999999)",
          parameters: {'r': restaurantId, 'b': branchId, 't': terminal},
        ),
        throwsA(anything),
      );
    });

    test('a day with orders against it cannot be deleted', () async {
      final dayId = await openDay();
      await db.query(
        pg.config,
        'INSERT INTO pos_orders (client_transaction_id, restaurant_id, '
        '  branch_id, terminal_id, invoice_number, order_type, currency, '
        '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
        '  occurred_at, business_day_id) '
        "VALUES (gen_random_uuid(), @r, @b, @t::uuid, 'INV-Y', 'dine_in', "
        "  'EGP', 2, 1000, 0, 0, 1000, now(), @day)",
        parameters: {
          'r': restaurantId,
          'b': branchId,
          't': terminal,
          'day': dayId,
        },
      );

      await expectLater(
        db.query(
          pg.config,
          'DELETE FROM pos_business_days WHERE id = @id',
          parameters: {'id': dayId},
        ),
        throwsA(anything),
      );
    });

    test('a shift can name its business day', () async {
      final dayId = await openDay();
      await db.query(
        pg.config,
        'UPDATE pos_shifts SET business_day_id = @day WHERE id = @id',
        parameters: {'day': dayId, 'id': shiftId},
      );

      final rows = await db.query(
        pg.config,
        'SELECT business_day_id FROM pos_shifts WHERE id = @id',
        parameters: {'id': shiftId},
      );
      expect(rows.first[0], dayId);
    });

    test('a shift can name who approved opening it', () async {
      await db.query(
        pg.config,
        'UPDATE pos_shifts SET opened_with_approval_by = @by WHERE id = @id',
        parameters: {'by': staffId, 'id': shiftId},
      );
      final rows = await db.query(
        pg.config,
        'SELECT opened_with_approval_by FROM pos_shifts WHERE id = @id',
        parameters: {'id': shiftId},
      );
      expect(rows.first[0], staffId);
    });
  });

  group('the seeded pay-in and pay-out reasons', () {
    test('a restaurant the bootstrap seeded has both lists', () async {
      // Migration 9 provisioned both scopes and seeded neither, because nothing
      // recorded a cash movement yet. §22 does now.
      //
      // Seeded through `LocalBootstrap`, not by the migration: the migration's
      // INSERT covers restaurants that already existed when it ran, and this
      // one was created afterwards. Both paths have to work, and they are
      // different code.
      await LocalBootstrap(db).seedReasonCodes(
        pg.config,
        restaurantId,
      );

      for (final scope in ['pay_in', 'pay_out']) {
        final rows = await db.query(
          pg.config,
          'SELECT count(*) FROM pos_reason_codes WHERE scope = @scope '
          'AND restaurant_id = @r',
          parameters: {'scope': scope, 'r': restaurantId},
        );
        expect(rows.first[0], isNot(0), reason: scope);
      }
    });

    test('the cash lists are not the sale ones', () async {
      await LocalBootstrap(db).seedReasonCodes(
        pg.config,
        restaurantId,
      );

      final rows = await db.query(
        pg.config,
        "SELECT code FROM pos_reason_codes WHERE scope = 'pay_in' "
        'AND restaurant_id = @r ORDER BY sort_order',
        parameters: {'r': restaurantId},
      );
      final codes = rows.map((row) => row[0]).toList();

      // "Staff meal" and "Manager comp" are not reasons anybody puts money
      // *into* a till, and offering them would be offering nonsense.
      expect(codes, contains('float_top_up'));
      expect(codes, isNot(contains('staff_meal')));
      expect(codes, isNot(contains('manager_comp')));
    });
  });
}
