@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_customer_directory_repository.dart';

import 'pg_fixture.dart';

/// The customer directory with what each has bought, against PostgreSQL.
///
/// The ledger around it, on 10 September 2026, in piastres:
///
/// | Customer | Orders that count | What does not |
/// |---|---|---|
/// | Mona (010…) | A 20,000, B 10,000 (7,500 of it refunded) | a voided order, an open one |
/// | Karim (011…) | C 5,000 at this branch | D 99,000 at ANOTHER branch |
/// | Nour (012…) | — never ordered | |
/// | Layla | at another restaurant | |
void main() {
  if (PgFixture.host == null) {
    test('customer directory (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const terminal = '40000000-0000-4000-8000-000000000001';
  const otherTerminal = '40000000-0000-4000-8000-000000000002';

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int otherBranchId;
  late int cashId;
  late int nourStaff;
  late int mona;
  late int karim;
  late int nour;
  late PostgresCustomerDirectoryRepository directory;
  var invoice = 0;

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0] as int;

  Future<int> customer(
    String name,
    String phone, {
    int? restaurant,
    String? email,
    String? address,
  }) => scalar(
    'INSERT INTO pos_customers (restaurant_id, client_transaction_id, name, '
    '  phone, email, address) '
    'VALUES (@r, gen_random_uuid(), @n, @p, @e, @a) RETURNING id',
    {
      'r': restaurant ?? restaurantId,
      'n': name,
      'p': phone,
      'e': email,
      'a': address,
    },
  );

  Future<int> order({
    required int? customerId,
    required int total,
    required DateTime at,
    String status = 'PAID',
    int? branch,
    String? onTerminal,
  }) async {
    invoice++;
    return scalar(
      'INSERT INTO pos_orders (client_transaction_id, restaurant_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, customer_id, voided_at, voided_by) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @inv, 'dine_in', 'EGP', 2, "
      '  @total, 0, 0, 0, @total, @at::timestamptz, @status, @c, '
      "  CASE WHEN @status::text = 'VOIDED' THEN @at::timestamptz END, "
      "  CASE WHEN @status::text = 'VOIDED' THEN @by::bigint END) "
      'RETURNING id',
      {
        'r': restaurantId,
        'b': branch ?? branchId,
        't': onTerminal ?? terminal,
        'inv': 'CD-$invoice',
        'total': total,
        'at': at,
        'status': status,
        'c': customerId,
        'by': nourStaff,
      },
    );
  }

  /// One transaction: the tender check is a deferred constraint trigger.
  Future<void> refund(int orderId, int total) => db.runTx(pg.config, (tx) async {
    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO pos_refunds (client_refund_id, restaurant_id, branch_id, '
        '  terminal_id, order_id, kind, subtotal_minor, service_minor, '
        '  vat_minor, total_minor, refunded_by, occurred_at) '
        'VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, '
        "  'partial', @total, 0, 0, @total, @by, now()) RETURNING id",
      ),
      parameters: {
        'r': restaurantId,
        'b': branchId,
        't': terminal,
        'o': orderId,
        'total': total,
        'by': nourStaff,
      },
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
        "  amount_minor, counts_as_cash) VALUES (@id, @tt, 'cash', @total, true)",
      ),
      parameters: {'id': rows.first[0], 'tt': cashId, 'total': total},
    );
  });

  final tenth = DateTime.utc(2026, 9, 10, 10);

  setUp(() async {
    pg = await PgFixture.open('customer_directory');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_outbox, pos_refunds, pos_orders, pos_business_days, '
      'pos_invoice_sequences RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_combos');
    await db.query(pg.config, 'DELETE FROM pos_restaurants');
    invoice = 0;

    restaurantId = await scalar(
      "INSERT INTO pos_restaurants (slug, name) VALUES ('cd', 'CD') RETURNING id",
    );
    branchId = await scalar(
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'MANS', 'Mansoura') RETURNING id",
      {'r': restaurantId},
    );
    otherBranchId = await scalar(
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'TANT', 'Tanta') RETURNING id",
      {'r': restaurantId},
    );
    nourStaff = await scalar(
      'INSERT INTO pos_users (restaurant_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', 'nour', 's', 'h') "
      'RETURNING id',
      {'r': restaurantId, 'b': branchId},
    );
    for (final (id, name, branch) in [
      (terminal, 'POS-01', branchId),
      (otherTerminal, 'TANTA-01', otherBranchId),
    ]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
        'VALUES (@id::uuid, @r, @b, @name)',
        parameters: {'id': id, 'r': restaurantId, 'b': branch, 'name': name},
      );
    }
    cashId = await scalar(
      'INSERT INTO pos_tender_types (restaurant_id, code, name_en, kind, '
      "  counts_as_cash) VALUES (@r, 'cash', 'cash', 'cash', true) RETURNING id",
      {'r': restaurantId},
    );

    mona = await customer(
      'Mona Fathy',
      '01012345678',
      email: 'mona@example.com',
      address: '12 Nile St',
    );
    karim = await customer('Karim Said', '01112345678');
    nour = await customer('Nour Hassan', '01212345678');

    final a = await order(customerId: mona, total: 20000, at: tenth);
    final b = await order(
      customerId: mona,
      total: 10000,
      at: tenth.add(const Duration(days: 1)),
    );
    await refund(b, 7500);
    await order(customerId: mona, total: 55555, at: tenth, status: 'VOIDED');
    await order(customerId: mona, total: 44444, at: tenth, status: 'OPEN');
    await order(
      customerId: karim,
      total: 5000,
      at: tenth.subtract(const Duration(days: 3)),
    );
    await order(
      customerId: karim,
      total: 99000,
      at: tenth,
      branch: otherBranchId,
      onTerminal: otherTerminal,
    );
    // An order for nobody in particular, which most are.
    await order(customerId: null, total: 12345, at: tenth);
    expect(a, isPositive);

    final other = await scalar(
      "INSERT INTO pos_restaurants (slug, name) VALUES ('ot', 'OT') RETURNING id",
    );
    await customer('Layla Other', '01312345678', restaurant: other);

    directory = PostgresCustomerDirectoryRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  group('what each customer has bought', () {
    test('settled orders, net of refunds', () async {
      final all = await directory.list();
      final m = all.singleWhere((s) => s.customer.id == mona);

      // A 200.00 and B 100.00; 75.00 of B came back.
      expect(m.orders, 2);
      expect(m.spent.minor, 30000);
      expect(m.refunded.minor, 7500);
      expect(m.net.minor, 22500);
      expect(m.averageOrder!.minor, 11250);
    });

    test('a voided order and an open one are not purchases', () async {
      final m = (await directory.list()).singleWhere((s) => s.customer.id == mona);

      // 555.55 voided and 444.44 open would add 999.99 if counted.
      expect(m.orders, 2);
      expect(m.spent.minor, 30000);
    });

    test('this branch only: another branch\'s sale is not theirs here', () async {
      final k = (await directory.list()).singleWhere((s) => s.customer.id == karim);

      expect(k.orders, 1);
      expect(k.spent.minor, 5000, reason: 'not 5,000 + 99,000');
    });

    test('somebody who has never ordered is on file with nothing bought', () async {
      final n = (await directory.list()).singleWhere((s) => s.customer.id == nour);

      expect(n.orders, 0);
      expect(n.spent.minor, 0);
      expect(n.lastOrderAt, isNull);
      expect(n.hasOrdered, isFalse);
    });

    test('the last order is the latest of the counted ones', () async {
      final m = (await directory.list()).singleWhere((s) => s.customer.id == mona);

      // B, the 11th — not the voided or open order on the 10th.
      expect(m.lastOrderAt!.toUtc(), tenth.add(const Duration(days: 1)));
    });

    test('contact details come through', () async {
      final m = (await directory.list()).singleWhere((s) => s.customer.id == mona);

      expect(m.customer.name, 'Mona Fathy');
      expect(m.customer.phone, '01012345678');
      expect(m.customer.email, 'mona@example.com');
      expect(m.customer.address, '12 Nile St');
    });
  });

  group('who is listed', () {
    test('everybody on file for this restaurant, and nobody else\'s', () async {
      final names = (await directory.list()).map((s) => s.customer.name);

      expect(names, containsAll(['Mona Fathy', 'Karim Said', 'Nour Hassan']));
      expect(names, isNot(contains('Layla Other')));
    });

    test('most recently seen first, the never-seen last, then by name', () async {
      final names = (await directory.list()).map((s) => s.customer.name).toList();

      expect(names, ['Mona Fathy', 'Karim Said', 'Nour Hassan']);
    });

    test('the limit is honoured', () async {
      expect(await directory.list(limit: 2), hasLength(2));
    });
  });

  group('search', () {
    test('by a fragment of the name, in any case', () async {
      final found = await directory.list(query: 'KARIM');

      expect(found.map((s) => s.customer.id), [karim]);
    });

    test('by the tail of a phone number', () async {
      final found = await directory.list(query: '12345678');

      // All three share the tail; the order is the directory's.
      expect(found, hasLength(3));
      expect((await directory.list(query: '0101')).map((s) => s.customer.id), [mona]);
    });

    test('by a phone typed in Arabic-Indic digits', () async {
      // ٠١١١ is 0111: the same person as at the counter, not a second rule.
      final found = await directory.list(query: '٠١١١٢٣');

      expect(found.map((s) => s.customer.id), [karim]);
    });

    test('a query that matches nobody is an empty list, not an error', () async {
      expect(await directory.list(query: 'zzzz'), isEmpty);
    });

    test('a name search does not match another restaurant\'s customer', () async {
      expect(await directory.list(query: 'Layla'), isEmpty);
    });
  });

  group('one customer\'s recent orders', () {
    test('settled, at this branch, newest first, each net of its refund', () async {
      final orders = await directory.recentOrders(mona);

      expect(orders, hasLength(2));
      expect(orders.first.total.minor, 10000);
      expect(orders.first.refunded.minor, 7500);
      expect(orders.first.net.minor, 2500);
      expect(orders.last.total.minor, 20000);
      expect(orders.last.refunded.minor, 0);
    });

    test('carries the receipt number and the time', () async {
      final first = (await directory.recentOrders(mona)).first;

      expect(first.invoiceNumber, startsWith('CD-'));
      expect(first.occurredAt.toUtc(), tenth.add(const Duration(days: 1)));
    });

    test('the limit is honoured', () async {
      expect(await directory.recentOrders(mona, limit: 1), hasLength(1));
    });

    test('a customer who never ordered has none', () async {
      expect(await directory.recentOrders(nour), isEmpty);
    });

    test('another branch\'s orders are not listed', () async {
      expect(await directory.recentOrders(karim), hasLength(1));
    });

    test('a customer of another restaurant lists nothing here', () async {
      final theirs = await scalar(
        "SELECT id FROM pos_customers WHERE name = 'Layla Other'",
      );

      expect(await directory.recentOrders(theirs), isEmpty);
    });
  });
}
