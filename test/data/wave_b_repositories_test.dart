@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_business_day_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_cash_movements_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart'
    show PosWriteContext;
import 'package:xorder_pos/data/postgres/postgres_settings_repository.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/pos_settings.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';

import 'pg_fixture.dart';

/// Wave B's three repositories, against a real database.
void main() {
  if (PgFixture.host == null) {
    test('wave B repositories (skipped — set POS_PG_HOST)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int staffId;
  late int shiftId;
  late PostgresSettingsRepository settings;
  late PostgresBusinessDayRepository days;
  late PostgresCashMovementsRepository cash;

  const terminal = '44444444-4444-4444-8444-444444444444';
  late PosStaff nour;

  setUp(() async {
    pg = await PgFixture.open('wave_b_repos');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_business_days, pos_cash_movements, pos_settings, '
      '  pos_orders, pos_shifts, pos_parked_tickets RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_restaurants (slug, name) "
                  "VALUES ('wb', 'Wave B') RETURNING id",
                ))
                .first[0]
            as int;
    branchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (restaurant_id, code, name) "
                  "VALUES (@r, 'WB1', 'Main') RETURNING id",
                  parameters: {'r': restaurantId},
                ))
                .first[0]
            as int;
    staffId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_staff (restaurant_id, branch_id, name, '
                  "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', "
                  "  'nour', 'salt', 'hash') RETURNING id",
                  parameters: {'r': restaurantId, 'b': branchId},
                ))
                .first[0]
            as int;
    nour = PosStaff(id: staffId, name: 'Nour Adel');

    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'Counter 1') ON CONFLICT (id) DO NOTHING",
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

    final context = PosWriteContext(
      restaurantId: restaurantId,
      branchId: branchId,
      terminalId: terminal,
      branchCode: 'WB1',
    );
    settings = PostgresSettingsRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
      terminalId: terminal,
    );
    days = PostgresBusinessDayRepository(
      database: db,
      config: pg.config,
      context: context,
    );
    cash = PostgresCashMovementsRepository(
      database: db,
      config: pg.config,
      context: context,
    );
  });

  tearDown(() => pg.close());

  group('settings', () {
    test('an unconfigured restaurant resolves to the defaults', () async {
      final loaded = await settings.load();
      expect(loaded.has(SettingKey.dayStartTime), isFalse);
      expect(DayPolicy.from(loaded).startMinutes, 6 * 60);
    });

    test('saving then loading round-trips through the scopes', () async {
      await settings.save(
        key: SettingKey.dayStartTime,
        value: '06:00',
        scope: SettingScope.restaurant,
        by: nour,
      );
      await settings.save(
        key: SettingKey.dayStartTime,
        value: '04:00',
        scope: SettingScope.branch,
        scopeId: '$branchId',
        by: nour,
      );

      // The narrower answer wins, and it came back from a real query rather
      // than from a list a test built.
      expect(DayPolicy.from(await settings.load()).startMinutes, 240);
    });

    test('saving the same key twice is a change, not a second row', () async {
      await settings.save(
        key: SettingKey.cashBlindClose,
        value: 'false',
        scope: SettingScope.restaurant,
        by: nour,
      );
      await settings.save(
        key: SettingKey.cashBlindClose,
        value: 'true',
        scope: SettingScope.restaurant,
        by: nour,
      );

      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_settings WHERE restaurant_id = @r '
        'AND key = @key',
        parameters: {'r': restaurantId, 'key': SettingKey.cashBlindClose},
      );
      expect(rows.first[0], 1);
      expect(CashPolicy.from(await settings.load()).blindClose, isTrue);
    });

    test('the writer is recorded', () async {
      await settings.save(
        key: SettingKey.cashBlindClose,
        value: 'true',
        scope: SettingScope.restaurant,
        by: nour,
      );
      final rows = await db.query(
        pg.config,
        'SELECT updated_by FROM pos_settings WHERE key = @key',
        parameters: {'key': SettingKey.cashBlindClose},
      );
      expect(rows.first[0], staffId);
    });
  });

  group('the business day', () {
    test('there is none until somebody opens one', () async {
      expect(await days.current(), isNull);
    });

    test('opening one returns it, and it is open', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      expect(day.isOpen, isTrue);
      expect(day.openedByName, 'Nour Adel');
      expect(day.date.year, 2026);
      expect(day.date.month, 9);
      expect(day.date.day, 8);
    });

    test('opening twice returns the same day, not an error', () async {
      // Two tills starting the morning together is the normal case. The loser
      // of that race wants the day the winner opened, not a refusal at 7 a.m.
      final first = await days.open(date: DateTime(2026, 9, 8), by: nour);
      final again = await days.open(date: DateTime(2026, 9, 8), by: nour);
      expect(again.id, first.id);
    });

    test('a closed day is not reopened silently', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      await days.close(day: day, by: nour);

      // Resurrecting a day somebody deliberately ended is not something a till
      // may do quietly.
      await expectLater(
        days.open(date: DateTime(2026, 9, 8), by: nour),
        throwsA(isA<StateError>()),
      );
    });

    test('closing totals the day inside the same transaction', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      for (final total in [10000, 25000]) {
        await db.query(
          pg.config,
          'INSERT INTO pos_orders (client_transaction_id, restaurant_id, '
          '  branch_id, terminal_id, invoice_number, order_type, currency, '
          '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
          "  occurred_at, business_day_id, status) VALUES (gen_random_uuid(), "
          "  @r, @b, @t::uuid, @invoice, 'dine_in', 'EGP', 2, "
          '  @total, 0, 0, @total, now(), @day, \'PAID\')',
          parameters: {
            'r': restaurantId,
            'b': branchId,
            't': terminal,
            // A separate parameter from the amount: `@total::text` inside the
            // invoice would fix the parameter's type as text, and the same
            // placeholder cannot then also be a bigint.
            'invoice': 'INV-$total',
            'total': total,
            'day': day.id,
          },
        );
      }

      final closed = await days.close(day: day, by: nour);
      expect(closed.isOpen, isFalse);
      expect(closed.closedByName, 'Nour Adel');
      expect(closed.gross?.minor, 35000);
      // Nothing refunded, so net equals gross.
      expect(closed.net?.minor, 35000);
    });

    test('a voided order is not takings', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      await db.query(
        pg.config,
        'INSERT INTO pos_orders (client_transaction_id, restaurant_id, '
        '  branch_id, terminal_id, invoice_number, order_type, currency, '
        '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
        "  occurred_at, business_day_id, status, voided_at, voided_by) "
        "VALUES (gen_random_uuid(), @r, @b, @t::uuid, 'INV-V', 'dine_in', "
        "  'EGP', 2, 9000, 0, 0, 9000, now(), @day, 'VOIDED', now(), @by)",
        parameters: {
          'r': restaurantId,
          'b': branchId,
          't': terminal,
          'day': day.id,
          'by': staffId,
        },
      );

      final closed = await days.close(day: day, by: nour);
      // The food was thrown away; the money never arrived.
      expect(closed.gross?.minor, 0);
    });

    test('closing twice returns the closed day rather than throwing', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      await days.close(day: day, by: nour);
      final again = await days.close(day: day, by: nour);
      expect(again.isOpen, isFalse);
    });

    test('a forced close with no reason is refused before the database', () {
      expect(
        () => days.close(
          day: BusinessDay(
            id: 1,
            date: DateTime(2026, 9, 8),
            openedAt: DateTime(2026, 9, 8, 6),
          ),
          by: nour,
          force: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a forced close records why', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      final closed = await days.close(
        day: day,
        by: nour,
        force: true,
        forceReason: 'Till crashed with a table open',
      );
      expect(closed.forced, isTrue);
      expect(closed.forceReason, 'Till crashed with a table open');
    });
  });

  group('what blocks a close', () {
    test('nothing, on a quiet day', () async {
      await days.open(date: DateTime(2026, 9, 8), by: nour);
      // The shift opened in setUp is still open, so this is not vacuously
      // clear — it is clear once that shift is closed.
      await db.query(
        pg.config,
        'UPDATE pos_shifts SET closed_at = now(), closed_by = @by, '
        '  counted_cash_minor = 0, expected_cash_minor = 0, variance_minor = 0 '
        'WHERE id = @id',
        parameters: {'by': staffId, 'id': shiftId},
      );

      final check = await days.check();
      expect(check.isClear, isTrue);
      expect(check.needsForce, isFalse);
    });

    test('an open shift blocks it', () async {
      await days.open(date: DateTime(2026, 9, 8), by: nour);
      final check = await days.check();
      expect(
        check.blockers.map((b) => b.kind),
        contains(DayBlockerKind.openShift),
      );
      expect(check.needsForce, isTrue);
    });

    test('a seated table blocks it', () async {
      await days.open(date: DateTime(2026, 9, 8), by: nour);
      final tableId =
          (await db.query(
                    pg.config,
                    'INSERT INTO pos_dining_tables (restaurant_id, branch_id, '
                    "  label, seats) VALUES (@r, @b, 'T4', 4) RETURNING id",
                    parameters: {'r': restaurantId, 'b': branchId},
                  ))
                  .first[0]
              as int;
      await db.query(
        pg.config,
        'INSERT INTO pos_parked_tickets (restaurant_id, table_id, '
        "  client_transaction_id, payload) "
        "VALUES (@r, @t, gen_random_uuid(), '{}'::jsonb)",
        parameters: {'r': restaurantId, 't': tableId},
      );

      final check = await days.check();
      expect(
        check.blockers.map((b) => b.kind),
        contains(DayBlockerKind.parkedTicket),
      );
    });

    test('an unsettled order blocks it', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      await db.query(
        pg.config,
        'INSERT INTO pos_orders (client_transaction_id, restaurant_id, '
        '  branch_id, terminal_id, invoice_number, order_type, currency, '
        '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
        "  occurred_at, business_day_id, status) VALUES (gen_random_uuid(), "
        "  @r, @b, @t::uuid, 'INV-OPEN', 'dine_in', 'EGP', 2, 1000, 0, 0, "
        "  1000, now(), @day, 'SENT_TO_KITCHEN')",
        parameters: {
          'r': restaurantId,
          'b': branchId,
          't': terminal,
          'day': day.id,
        },
      );

      final check = await days.check();
      expect(
        check.blockers.map((b) => b.kind),
        contains(DayBlockerKind.unpaidOrder),
      );
    });

    test('a paid order does not', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      await db.query(
        pg.config,
        'INSERT INTO pos_orders (client_transaction_id, restaurant_id, '
        '  branch_id, terminal_id, invoice_number, order_type, currency, '
        '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
        "  occurred_at, business_day_id, status) VALUES (gen_random_uuid(), "
        "  @r, @b, @t::uuid, 'INV-PAID', 'dine_in', 'EGP', 2, 1000, 0, 0, "
        "  1000, now(), @day, 'PAID')",
        parameters: {
          'r': restaurantId,
          'b': branchId,
          't': terminal,
          'day': day.id,
        },
      );

      final check = await days.check();
      expect(
        check.blockers.map((b) => b.kind),
        isNot(contains(DayBlockerKind.unpaidOrder)),
      );
    });

    test('checking with no open day says so rather than returning nothing', () {
      expect(days.check(), throwsA(isA<StateError>()));
    });
  });

  group('cash movements', () {
    test('a pay-out is recorded positive, with both names', () async {
      final approver = PosStaff(id: staffId, name: 'Nour Adel');
      final movement = await cash.record(
        kind: CashMovementKind.payOut,
        amount: const Money(5000),
        by: nour,
        approvedBy: approver,
        shiftId: shiftId,
        note: 'Bread supplier',
      );

      expect(movement.amount.minor, 5000);
      expect(movement.kind, CashMovementKind.payOut);
      // The direction lives in the kind, so the stored amount stays positive.
      expect(movement.signed.minor, -5000);
    });

    test('an opening is stored as moving nothing, whatever it was passed', () async {
      // A screen passing the float by accident must not surface as a
      // constraint violation.
      final movement = await cash.record(
        kind: CashMovementKind.drawerOpen,
        amount: const Money(20000),
        by: nour,
        shiftId: shiftId,
      );
      expect(movement.amount.minor, 0);

      final rows = await db.query(
        pg.config,
        'SELECT amount_minor FROM pos_cash_movements WHERE id = @id',
        parameters: {'id': movement.id},
      );
      expect(rows.first[0], 0);
    });

    test('a movement of nothing is refused before the database', () async {
      await expectLater(
        cash.record(
          kind: CashMovementKind.payIn,
          amount: Money.zero,
          by: nour,
          shiftId: shiftId,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a shift reads back its movements, oldest first', () async {
      await cash.record(
        kind: CashMovementKind.payIn,
        amount: const Money(10000),
        by: nour,
        shiftId: shiftId,
      );
      await cash.record(
        kind: CashMovementKind.payOut,
        amount: const Money(3000),
        by: nour,
        shiftId: shiftId,
      );
      await cash.record(
        kind: CashMovementKind.drawerOpen,
        amount: Money.zero,
        by: nour,
        shiftId: shiftId,
      );

      final movements = await cash.forShift(shiftId);
      expect(movements, hasLength(3));
      expect(movements.first.kind, CashMovementKind.payIn);
      expect(movements.first.staffName, 'Nour Adel');

      final totals = CashMovementTotals.of(movements);
      expect(totals.paidIn.minor, 10000);
      expect(totals.paidOut.minor, 3000);
      expect(totals.net.minor, 7000);
      expect(totals.drawerOpens, 1);
    });

    test('another shift\'s movements are not counted', () async {
      // A second terminal, because one open shift per terminal is enforced —
      // which is itself worth knowing, and is why this is not simply a second
      // INSERT on the same till.
      const otherTerminal = '55555555-5555-4555-8555-555555555555';
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
        "VALUES (@t::uuid, @r, @b, 'Counter 2') ON CONFLICT (id) DO NOTHING",
        parameters: {
          't': otherTerminal,
          'r': restaurantId,
          'b': branchId,
        },
      );

      final other =
          (await db.query(
                    pg.config,
                    'INSERT INTO pos_shifts (restaurant_id, branch_id, '
                    '  terminal_id, opened_by, opening_float_minor) '
                    'VALUES (@r, @b, @t::uuid, @by, 0) RETURNING id',
                    parameters: {
                      'r': restaurantId,
                      'b': branchId,
                      't': otherTerminal,
                      'by': staffId,
                    },
                  ))
                  .first[0]
              as int;

      await cash.record(
        kind: CashMovementKind.payIn,
        amount: const Money(10000),
        by: nour,
        shiftId: other,
      );

      expect(await cash.forShift(shiftId), isEmpty);
      expect(await cash.forShift(other), hasLength(1));
    });

    test('a movement can name the day it belongs to', () async {
      final day = await days.open(date: DateTime(2026, 9, 8), by: nour);
      final movement = await cash.record(
        kind: CashMovementKind.payOut,
        amount: const Money(1000),
        by: nour,
        shiftId: shiftId,
        businessDayId: day.id,
      );

      final rows = await db.query(
        pg.config,
        'SELECT business_day_id FROM pos_cash_movements WHERE id = @id',
        parameters: {'id': movement.id},
      );
      expect(rows.first[0], day.id);
    });
  });
}
