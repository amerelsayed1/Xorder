@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/reason_code.dart';

import 'pg_fixture.dart';

/// Migration 9 — the schema a void needs.
///
/// The claims worth holding are not "the columns exist" but the invariants the
/// database is being asked to keep on the till's behalf: a void is attributed
/// or it did not happen, a line cannot be refunded more than it was sold, and
/// the lifecycle a row can be in is a closed set rather than whatever string
/// the caller passed.
void main() {
  if (PgFixture.host == null) {
    test('order lifecycle (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int staffId;

  /// A settled sale to void, refund or leave alone.
  Future<int> insertOrder({int quantity = 2}) async {
    final order = await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, restaurant_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, service_minor, vat_minor, total_minor, occurred_at) '
      "VALUES (gen_random_uuid(), @r, @b, gen_random_uuid(), 'INV-' || "
      "  floor(random() * 1000000)::text, 'dine_in', 'EGP', 2, "
      '  10000, 1200, 1568, 12768, now()) RETURNING id',
      parameters: {'r': restaurantId, 'b': branchId},
    );
    final orderId = order.first[0] as int;

    await db.query(
      pg.config,
      'INSERT INTO pos_order_lines (order_id, line_key, name_snapshot, quantity, '
      "  unit_price_minor, line_total_minor, stage) "
      "VALUES (@o, '1:', 'Mixed Grill', @q, 5000, @total, 'sent')",
      parameters: {'o': orderId, 'q': quantity, 'total': 5000 * quantity},
    );
    return orderId;
  }

  Future<int> lineOf(int orderId) async {
    final rows = await db.query(
      pg.config,
      'SELECT id FROM pos_order_lines WHERE order_id = @o',
      parameters: {'o': orderId},
    );
    return rows.first[0] as int;
  }

  setUp(() async {
    pg = await PgFixture.open('order_lifecycle');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    final restaurant = await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('lifecycle', 'Lifecycle') "
      'RETURNING id',
    );
    restaurantId = restaurant.first[0] as int;

    final branch = await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) VALUES (@r, 'LFC', 'Main') "
      'RETURNING id',
      parameters: {'r': restaurantId},
    );
    branchId = branch.first[0] as int;

    final staff = await db.query(
      pg.config,
      'INSERT INTO pos_users (restaurant_id, branch_id, name, username, pin_salt, pin_hash) '
      "VALUES (@r, @b, 'Hana Mostafa', 'hana', 'salt', 'hash') RETURNING id",
      parameters: {'r': restaurantId, 'b': branchId},
    );
    staffId = staff.first[0] as int;
  });

  tearDown(() => pg.close());

  group('order status', () {
    test('every existing sale is PAID, because every existing sale is', () async {
      final orderId = await insertOrder();
      final rows = await db.query(
        pg.config,
        'SELECT status FROM pos_orders WHERE id = @o',
        parameters: {'o': orderId},
      );

      // The default is not a guess. `pos_orders` was only ever written at
      // settlement, so PAID is what every row already meant.
      expect(rows.first[0], 'PAID');
    });

    test('refuses a status outside the lifecycle', () async {
      final orderId = await insertOrder();

      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_orders SET status = 'ALMOST_PAID' WHERE id = @o",
          parameters: {'o': orderId},
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('accepts every status the lifecycle names', () async {
      final orderId = await insertOrder();

      for (final status in const [
        'DRAFT',
        'OPEN',
        'SENT_TO_KITCHEN',
        'READY',
        'PAID',
        'CLOSED',
        'VOIDED',
        'CANCELLED',
        'REFUNDED',
        'PARTIALLY_REFUNDED',
      ]) {
        await db.query(
          pg.config,
          'UPDATE pos_orders SET status = @s WHERE id = @o',
          parameters: {'s': status, 'o': orderId},
        );
      }
    });
  });

  group('void provenance', () {
    test('a void must name who did it', () async {
      final orderId = await insertOrder();

      // The row somebody would want to leave behind: the order is gone and the
      // record declines to say by whose hand.
      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_orders SET status = 'VOIDED', voided_at = now() WHERE id = @o",
          parameters: {'o': orderId},
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('an attributed void is accepted', () async {
      final orderId = await insertOrder();

      await db.query(
        pg.config,
        "UPDATE pos_orders SET status = 'VOIDED', voided_at = now(), "
        '  voided_by = @s, void_note = @note WHERE id = @o',
        parameters: {
          'o': orderId,
          's': staffId,
          'note': 'Customer left before the food arrived',
        },
      );

      final rows = await db.query(
        pg.config,
        'SELECT status, voided_by FROM pos_orders WHERE id = @o',
        parameters: {'o': orderId},
      );
      expect(rows.first[0], 'VOIDED');
      expect(rows.first[1], staffId);
    });

    test('deleting the person keeps the record of what they voided', () async {
      final orderId = await insertOrder();
      await db.query(
        pg.config,
        "UPDATE pos_orders SET status = 'VOIDED', voided_at = now(), voided_by = @s "
        'WHERE id = @o',
        parameters: {'o': orderId, 's': staffId},
      );

      // RESTRICT, not CASCADE. Tidying up a staff list must never take the
      // evidence of a void with it.
      await expectLater(
        db.query(
          pg.config,
          'DELETE FROM pos_users WHERE id = @s',
          parameters: {'s': staffId},
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('refunded quantity', () {
    test('cannot exceed what was sold', () async {
      final orderId = await insertOrder(quantity: 2);
      final lineId = await lineOf(orderId);

      // Two were sold. Giving three back is not a refund, it is a leak.
      await expectLater(
        db.query(
          pg.config,
          'UPDATE pos_order_lines SET refunded_quantity = 3 WHERE id = @l',
          parameters: {'l': lineId},
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('a partial refund is allowed and starts at zero', () async {
      final orderId = await insertOrder(quantity: 2);
      final lineId = await lineOf(orderId);

      final before = await db.query(
        pg.config,
        'SELECT refunded_quantity FROM pos_order_lines WHERE id = @l',
        parameters: {'l': lineId},
      );
      expect(before.first[0], 0);

      await db.query(
        pg.config,
        'UPDATE pos_order_lines SET refunded_quantity = 1 WHERE id = @l',
        parameters: {'l': lineId},
      );
    });
  });

  group('reason codes', () {
    test('a restaurant that predates the migration gets the lists', () async {
      // This restaurant was inserted in setUp, after migration 9 ran, so it is
      // deliberately NOT covered by the migration's backfill — it stands in for
      // the case `seedReasonCodes` exists to handle.
      final before = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_reason_codes WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      expect(before.first[0], 0);

      final created = await LocalBootstrap(
        db,
      ).seedReasonCodes(pg.config, restaurantId);

      // Summed per scope, not multiplied: pay-in and pay-out have their own
      // lists, because "Staff meal" is not a reason anybody puts money into a
      // till. A flat multiplication was right only while every scope shared
      // one list.
      final expected = SystemReasons.seededScopes.fold<int>(
        0,
        (sum, scope) => sum + SystemReasons.seededFor(scope).length,
      );
      expect(created, expected);
    });

    test('each scope gets the list that belongs to it', () async {
      await LocalBootstrap(db).seedReasonCodes(pg.config, restaurantId);

      Future<List<Object?>> codesFor(String scope) async {
        final rows = await db.query(
          pg.config,
          'SELECT code FROM pos_reason_codes WHERE restaurant_id = @r '
          'AND scope = @scope ORDER BY sort_order',
          parameters: {'r': restaurantId, 'scope': scope},
        );
        return rows.map((row) => row[0]).toList();
      }

      expect(await codesFor('void'), contains('staff_meal'));
      expect(await codesFor('pay_in'), contains('float_top_up'));
      expect(await codesFor('pay_in'), isNot(contains('staff_meal')));
      expect(await codesFor('pay_out'), contains('bank_drop'));
    });

    test('re-seeding never resets an edited list', () async {
      final bootstrap = LocalBootstrap(db);
      await bootstrap.seedReasonCodes(pg.config, restaurantId);

      // A restaurant renames one and retires another.
      await db.query(
        pg.config,
        "UPDATE pos_reason_codes SET name_en = 'On the house' "
        "WHERE restaurant_id = @r AND code = 'manager_comp'",
        parameters: {'r': restaurantId},
      );
      await db.query(
        pg.config,
        "UPDATE pos_reason_codes SET is_active = false "
        "WHERE restaurant_id = @r AND code = 'training'",
        parameters: {'r': restaurantId},
      );

      expect(await bootstrap.seedReasonCodes(pg.config, restaurantId), 0);

      final rows = await db.query(
        pg.config,
        'SELECT code, name_en, is_active FROM pos_reason_codes '
        "WHERE restaurant_id = @r AND scope = 'void' "
        "  AND code IN ('manager_comp', 'training') ORDER BY code",
        parameters: {'r': restaurantId},
      );

      // An upgrade that quietly reinstates a choice somebody deliberately
      // retired is an upgrade nobody can trust.
      expect(rows.first[1], 'On the house');
      expect(rows.last[2], false);
    });

    test('only Other demands a note', () async {
      await LocalBootstrap(db).seedReasonCodes(pg.config, restaurantId);

      final rows = await db.query(
        pg.config,
        'SELECT code FROM pos_reason_codes '
        "WHERE restaurant_id = @r AND scope = 'void' AND requires_note",
        parameters: {'r': restaurantId},
      );

      // A property of the reason, not of the list: "Wrong item made" explains
      // itself and "Other" does not.
      expect(rows, hasLength(1));
      expect(rows.first[0], 'other');
    });

    test('refuses a scope the picker does not know', () async {
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_reason_codes (restaurant_id, scope, code, name_en) '
          "VALUES (@r, 'vibes', 'why_not', 'Why not')",
          parameters: {'r': restaurantId},
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('two restaurants keep their own vocabularies', () async {
      final other = await db.query(
        pg.config,
        "INSERT INTO pos_restaurants (slug, name) VALUES ('other', 'Other') RETURNING id",
      );
      final otherId = other.first[0] as int;

      final bootstrap = LocalBootstrap(db);
      await bootstrap.seedReasonCodes(pg.config, restaurantId);
      await bootstrap.seedReasonCodes(pg.config, otherId);

      await db.query(
        pg.config,
        "UPDATE pos_reason_codes SET name_en = 'On the house' "
        'WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );

      final rows = await db.query(
        pg.config,
        "SELECT name_en FROM pos_reason_codes WHERE restaurant_id = @r "
        "  AND scope = 'void' AND code = 'manager_comp'",
        parameters: {'r': otherId},
      );
      expect(rows.first[0], 'Manager comp');
    });
  });

  group('line events', () {
    test('tells a cancel apart from a void', () async {
      final orderId = await insertOrder();

      for (final event in const ['removed_before_send', 'voided_after_send']) {
        await db.query(
          pg.config,
          'INSERT INTO pos_order_line_events (order_id, line_key, event, user_id) '
          'VALUES (@o, @k, @e, @s)',
          parameters: {'o': orderId, 'k': '1:', 'e': event, 's': staffId},
        );
      }

      final rows = await db.query(
        pg.config,
        'SELECT event FROM pos_order_line_events WHERE order_id = @o '
        'ORDER BY occurred_at, id',
        parameters: {'o': orderId},
      );

      // Both leave the line off the bill. Only this says which happened, and
      // the second one has a cost attached — the food was already cooked.
      expect(rows.map((r) => r[0]), ['removed_before_send', 'voided_after_send']);
    });

    test('survives a line that was never persisted', () async {
      final orderId = await insertOrder();

      // No `order_line_id`: cancelling before the round is sent means there is
      // no line row to point at, which is exactly when `line_key` earns its
      // place.
      await db.query(
        pg.config,
        'INSERT INTO pos_order_line_events (order_id, line_key, event, user_id) '
        "VALUES (@o, '7:12,14', 'removed_before_send', @s)",
        parameters: {'o': orderId, 's': staffId},
      );

      final rows = await db.query(
        pg.config,
        'SELECT line_key, order_line_id FROM pos_order_line_events WHERE order_id = @o',
        parameters: {'o': orderId},
      );
      expect(rows.first[0], '7:12,14');
      expect(rows.first[1], isNull);
    });

    test('refuses an event it has no name for', () async {
      final orderId = await insertOrder();

      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_order_line_events (order_id, line_key, event, user_id) '
          "VALUES (@o, '1:', 'vanished', @s)",
          parameters: {'o': orderId, 's': staffId},
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
