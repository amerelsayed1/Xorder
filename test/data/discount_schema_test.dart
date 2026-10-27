@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

import 'pg_fixture.dart';

/// Migration 10 — the schema a discount needs.
///
/// The claims here are the ones the database is being asked to keep on the
/// till's behalf, so that no future repository, sync path or psql prompt can
/// write a discount that nothing can price or that charges a customer a
/// negative amount.
void main() {
  if (PgFixture.host == null) {
    test('discount schema (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int staffId;

  Future<void> insertDiscount({
    String code = 'lunch',
    String kind = 'percentage',
    int? valueBp = 1000,
    int? valueMinor,
    String scope = 'order',
    int? maxDiscountMinor,
    String? daysOfWeek,
  }) => db.query(
    pg.config,
    'INSERT INTO pos_discounts (restaurant_id, code, name_en, kind, value_bp, '
    '  value_minor, scope, max_discount_minor, days_of_week) '
    'VALUES (@r, @code, @name, @kind, @bp, @minor, @scope, @cap, '
    "  COALESCE(@days::smallint[], '{}'::smallint[]))",
    parameters: {
      'r': restaurantId,
      'code': code,
      'name': 'Lunch offer',
      'kind': kind,
      'bp': valueBp,
      'minor': valueMinor,
      'scope': scope,
      'cap': maxDiscountMinor,
      'days': daysOfWeek,
    },
  );

  Future<int> insertOrder({int subtotal = 10000, int discount = 0}) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, restaurant_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, service_minor, vat_minor, total_minor, discount_minor, '
      '  occurred_at) '
      "VALUES (gen_random_uuid(), @r, @b, gen_random_uuid(), "
      "  'INV-' || floor(random() * 1000000)::text, 'dine_in', 'EGP', 2, "
      '  @sub, 0, 0, @sub, @disc, now()) RETURNING id',
      parameters: {
        'r': restaurantId,
        'b': branchId,
        'sub': subtotal,
        'disc': discount,
      },
    );
    return rows.first[0] as int;
  }

  setUp(() async {
    pg = await PgFixture.open('discount_schema');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    final restaurant = await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('disc', 'Disc') RETURNING id",
    );
    restaurantId = restaurant.first[0] as int;

    final branch = await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) VALUES (@r, 'DSC', 'Main') "
      'RETURNING id',
      parameters: {'r': restaurantId},
    );
    branchId = branch.first[0] as int;

    final staff = await db.query(
      pg.config,
      'INSERT INTO pos_users (restaurant_id, branch_id, name, username, pin_salt, pin_hash) '
      "VALUES (@r, @b, 'Nour Adel', 'nour', 'salt', 'hash') RETURNING id",
      parameters: {'r': restaurantId, 'b': branchId},
    );
    staffId = staff.first[0] as int;
  });

  tearDown(() => pg.close());

  test('a restaurant starts with no discounts at all', () async {
    final rows = await db.query(
      pg.config,
      'SELECT count(*) FROM pos_discounts WHERE restaurant_id = @r',
      parameters: {'r': restaurantId},
    );

    // A discount is a commercial decision. A till that arrived with somebody
    // else's promotion configured would be inventing one.
    expect(rows.first[0], 0);
  });

  group('the value has to match the kind', () {
    test('a percentage carries basis points', () async {
      await insertDiscount(kind: 'percentage', valueBp: 1250);
    });

    test('a fixed amount carries minor units', () async {
      await insertDiscount(kind: 'fixed', valueBp: null, valueMinor: 5000);
    });

    test('a percentage with a fixed amount is refused', () async {
      // A row nothing can price. 1250 is 12.5% and 1250 is also 12.50 EGP, and
      // a value that disagrees with its kind is indistinguishable from either.
      await expectLater(
        insertDiscount(kind: 'percentage', valueBp: null, valueMinor: 1250),
        throwsA(isA<Exception>()),
      );
    });

    test('a fixed amount with basis points is refused', () async {
      await expectLater(
        insertDiscount(kind: 'fixed', valueBp: 1250, valueMinor: 5000),
        throwsA(isA<Exception>()),
      );
    });

    test('carrying both is refused', () async {
      await expectLater(
        insertDiscount(kind: 'percentage', valueBp: 1000, valueMinor: 5000),
        throwsA(isA<Exception>()),
      );
    });

    test('carrying neither is refused', () async {
      await expectLater(
        insertDiscount(kind: 'percentage', valueBp: null),
        throwsA(isA<Exception>()),
      );
    });

    test('a kind nobody can price is refused', () async {
      await expectLater(
        insertDiscount(kind: 'buy_one_get_one'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('values that are not values', () {
    test('over 100% is refused', () async {
      await expectLater(
        insertDiscount(valueBp: 10001),
        throwsA(isA<Exception>()),
      );
    });

    test('exactly 100% is allowed — a comp is a real thing', () async {
      await insertDiscount(valueBp: 10000);
    });

    test('a zero discount is refused', () async {
      // A discount that takes nothing off is a row somebody will apply and then
      // wonder about.
      await expectLater(insertDiscount(valueBp: 0), throwsA(isA<Exception>()));
    });

    test('a negative discount is refused', () async {
      await expectLater(
        insertDiscount(kind: 'fixed', valueBp: null, valueMinor: -500),
        throwsA(isA<Exception>()),
      );
    });

    test('a zero cap is refused, an absent one is not', () async {
      await insertDiscount(code: 'no-cap');
      await expectLater(
        insertDiscount(code: 'zero-cap', maxDiscountMinor: 0),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('the days a discount runs', () {
    test('empty means every day', () async {
      await insertDiscount(code: 'everyday');
      final rows = await db.query(
        pg.config,
        "SELECT days_of_week FROM pos_discounts WHERE code = 'everyday'",
      );
      expect(rows.first[0], isEmpty);
    });

    test('ISO day numbers are accepted', () async {
      await insertDiscount(code: 'weekend', daysOfWeek: '{5,6,7}');
    });

    test('a day that is not a day is refused', () async {
      // 0 and 8 are the two an off-by-one produces.
      await expectLater(
        insertDiscount(code: 'zero', daysOfWeek: '{0,1}'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insertDiscount(code: 'eight', daysOfWeek: '{8}'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('the order total', () {
    test('a discount larger than the goods is refused', () async {
      // Not a discount — a negative sale.
      await expectLater(
        insertOrder(subtotal: 10000, discount: 10001),
        throwsA(isA<Exception>()),
      );
    });

    test('a discount equal to the goods is allowed', () async {
      await insertOrder(subtotal: 10000, discount: 10000);
    });

    test('a negative discount is refused', () async {
      await expectLater(
        insertOrder(discount: -100),
        throwsA(isA<Exception>()),
      );
    });

    test('every order written before this migration has no discount', () async {
      final orderId = await insertOrder();
      final rows = await db.query(
        pg.config,
        'SELECT discount_minor FROM pos_orders WHERE id = @o',
        parameters: {'o': orderId},
      );
      expect(rows.first[0], 0);
    });
  });

  group('what was actually taken off', () {
    Future<void> applyDiscount({
      int? orderLineId,
      int? discountId,
      int amount = 1000,
      required int orderId,
    }) => db.query(
      pg.config,
      'INSERT INTO pos_order_discounts (order_id, order_line_id, discount_id, '
      '  name_snapshot, kind, value_bp, amount_minor, applied_by) '
      "VALUES (@o, @l, @d, 'Lunch offer', 'percentage', 1000, @amt, @by)",
      parameters: {
        'o': orderId,
        'l': orderLineId,
        'd': discountId,
        'amt': amount,
        'by': staffId,
      },
    );

    test('an order-level discount has no line', () async {
      final orderId = await insertOrder(discount: 1000);
      await applyDiscount(orderId: orderId);

      final rows = await db.query(
        pg.config,
        'SELECT order_line_id FROM pos_order_discounts WHERE order_id = @o',
        parameters: {'o': orderId},
      );

      // Null is the signal the cart panel reads: an order discount belongs in
      // the totals block, a line discount inside its line.
      expect(rows.first[0], isNull);
    });

    test('deleting the configured discount keeps the record of what it gave away',
        () async {
      await insertDiscount(code: 'retired');
      final discount = await db.query(
        pg.config,
        "SELECT id FROM pos_discounts WHERE code = 'retired'",
      );
      final discountId = discount.first[0] as int;

      final orderId = await insertOrder(discount: 1000);
      await applyDiscount(orderId: orderId, discountId: discountId);

      // No foreign key, deliberately. A restaurant retiring a promotion must
      // not take the record of what it cost with it.
      await db.query(
        pg.config,
        'DELETE FROM pos_discounts WHERE id = @d',
        parameters: {'d': discountId},
      );

      final rows = await db.query(
        pg.config,
        'SELECT name_snapshot, amount_minor FROM pos_order_discounts '
        'WHERE order_id = @o',
        parameters: {'o': orderId},
      );
      expect(rows.first[0], 'Lunch offer');
      expect(rows.first[1], 1000);
    });

    test('renaming the discount does not rewrite what a customer was charged',
        () async {
      await insertDiscount(code: 'lunch');
      final orderId = await insertOrder(discount: 1000);
      await applyDiscount(orderId: orderId);

      await db.query(
        pg.config,
        "UPDATE pos_discounts SET name_en = 'Midday special' WHERE code = 'lunch'",
      );

      final rows = await db.query(
        pg.config,
        'SELECT name_snapshot FROM pos_order_discounts WHERE order_id = @o',
        parameters: {'o': orderId},
      );
      // The same rule the food already follows: a receipt printed in March says
      // what it said in March.
      expect(rows.first[0], 'Lunch offer');
    });

    test('a discount that took nothing off is refused', () async {
      final orderId = await insertOrder();
      await expectLater(
        applyDiscount(orderId: orderId, amount: 0),
        throwsA(isA<Exception>()),
      );
    });

    test('voiding the order takes its discounts with it', () async {
      final orderId = await insertOrder(discount: 1000);
      await applyDiscount(orderId: orderId);

      // CASCADE here, unlike the configuration: these rows describe one order
      // and mean nothing without it.
      await db.query(
        pg.config,
        'DELETE FROM pos_orders WHERE id = @o',
        parameters: {'o': orderId},
      );

      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_order_discounts WHERE order_id = @o',
        parameters: {'o': orderId},
      );
      expect(rows.first[0], 0);
    });
  });

  group('what a role may take off by hand', () {
    test('every existing role is unlimited, not zero', () async {
      await db.query(
        pg.config,
        "INSERT INTO pos_roles (restaurant_id, code, name_en) "
        "VALUES (@r, 'cashier', 'Cashier')",
        parameters: {'r': restaurantId},
      );

      final rows = await db.query(
        pg.config,
        'SELECT max_discount_bp, max_discount_minor FROM pos_roles '
        'WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );

      // NULL means unlimited. Reading a missing cap as zero would have left
      // every role — the owner's included — unable to discount anything the
      // moment this migration ran.
      expect(rows.first[0], isNull);
      expect(rows.first[1], isNull);
    });

    test('a limit over 100% is refused', () async {
      await db.query(
        pg.config,
        "INSERT INTO pos_roles (restaurant_id, code, name_en) "
        "VALUES (@r, 'manager', 'Manager')",
        parameters: {'r': restaurantId},
      );

      await expectLater(
        db.query(
          pg.config,
          'UPDATE pos_roles SET max_discount_bp = 10001 WHERE restaurant_id = @r',
          parameters: {'r': restaurantId},
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('a zero limit is allowed — it means "may not discount"', () async {
      await db.query(
        pg.config,
        "INSERT INTO pos_roles (restaurant_id, code, name_en) "
        "VALUES (@r, 'kitchen', 'Kitchen')",
        parameters: {'r': restaurantId},
      );

      // Distinct from NULL, and the distinction is the point: nobody set a
      // limit versus somebody set it to nothing.
      await db.query(
        pg.config,
        'UPDATE pos_roles SET max_discount_bp = 0 WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
    });
  });
}
