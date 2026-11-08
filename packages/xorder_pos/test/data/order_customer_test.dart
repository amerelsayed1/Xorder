@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_order_history_repository.dart';
import 'package:xorder_pos/domain/models/order_record.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Who a sale was for, in the sales list and its detail, against PostgreSQL.
///
/// What only a database can answer: that the customer rides along on the order
/// without multiplying rows, that a sale for nobody still appears, that a
/// customer removed from the directory leaves their orders behind rather than
/// taking them with them — and that searching the list by a customer's name or
/// number finds their sales WITHOUT letting a short run of digits, which is
/// almost always the tail of a receipt number, pull in strangers by phone.
void main() {
  if (PgFixture.host == null) {
    test('order customer (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const terminal = '50000000-0000-4000-8000-000000000001';

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int mona;
  late int karim;
  late int layla;
  late PostgresOrderHistoryRepository history;
  late Map<String, int> orders;
  var invoice = 0;

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0] as int;

  Future<int> customer(
    String name,
    String phone, {
    String? email,
  }) => scalar(
    'INSERT INTO pos_customers (business_id, client_transaction_id, name, '
    '  phone, email) VALUES (@r, gen_random_uuid(), @n, @p, @e) RETURNING id',
    {'r': businessId, 'n': name, 'p': phone, 'e': email},
  );

  Future<int> order({
    required String invoiceNumber,
    required int? customerId,
    int total = 10000,
  }) async {
    invoice++;
    return scalar(
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, customer_id) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @inv, 'dine_in', 'EGP', 2, "
      '  @total, 0, 0, 0, @total, @at::timestamptz, \'PAID\', @c) '
      'RETURNING id',
      {
        'r': businessId,
        'b': branchId,
        't': terminal,
        'inv': invoiceNumber,
        'total': total,
        'at': DateTime.utc(2026, 9, 10, 10, invoice),
        'c': customerId,
      },
    );
  }

  Future<List<String>> invoicesFor(String term) async => [
    for (final o in await history.search(OrderHistoryQuery(search: term)))
      o.invoiceNumber,
  ]..sort();

  setUp(() async {
    pg = await PgFixture.open('order_customer');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_outbox, pos_refunds, pos_orders, pos_business_days, '
      'pos_invoice_sequences RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_combos');
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    invoice = 0;

    businessId = await scalar(
      "INSERT INTO pos_businesses (slug, name) VALUES ('oc2', 'OC2') RETURNING id",
    );
    branchId = await scalar(
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      {'r': businessId},
    );
    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      "VALUES (@id::uuid, @r, @b, 'POS-01')",
      parameters: {'id': terminal, 'r': businessId, 'b': branchId},
    );

    mona = await customer('Mona Fathy', '01012345678', email: 'mona@example.com');
    karim = await customer('Karim Said', '01198765432');
    // A stranger whose phone ends in the same four digits as Karim's receipt.
    layla = await customer('Layla Nabil', '01055555432');

    orders = {
      // Mona has two sales; the first invoice ends in digits that are also the
      // tail of Karim's phone, which is the collision the 7-digit rule guards.
      'A': await order(invoiceNumber: 'INV-0001', customerId: mona),
      'B': await order(invoiceNumber: 'INV-0002', customerId: mona),
      'C': await order(invoiceNumber: 'INV-5432', customerId: karim),
      'D': await order(invoiceNumber: 'INV-0004', customerId: null),
      'E': await order(invoiceNumber: 'INV-0009', customerId: layla),
    };

    history = PostgresOrderHistoryRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  group('the record', () {
    test('carries who the sale was for', () async {
      final record = (await history.search(const OrderHistoryQuery()))
          .singleWhere((o) => o.invoiceNumber == 'INV-0001');

      expect(record.customerId, mona);
      expect(record.customerName, 'Mona Fathy');
      expect(record.customerPhone, '01012345678');
      expect(record.customerEmail, 'mona@example.com');
      expect(record.hasCustomer, isTrue);
    });

    test('a sale for nobody still appears, with no customer', () async {
      final record = (await history.search(const OrderHistoryQuery()))
          .singleWhere((o) => o.invoiceNumber == 'INV-0004');

      expect(record.customerId, isNull);
      expect(record.customerName, isNull);
      expect(record.hasCustomer, isFalse);
    });

    test('one row per sale: a customer with two orders does not double them', () async {
      final all = await history.search(const OrderHistoryQuery());

      expect(all, hasLength(5));
      expect(all.map((o) => o.invoiceNumber).toSet(), hasLength(5));
    });

    test('the detail has it too', () async {
      final detail = await history.detail(orders['A']!);

      expect(detail!.order.customerName, 'Mona Fathy');
      expect(detail.order.customerEmail, 'mona@example.com');
    });

    test('a customer removed from the directory leaves the sale, unnamed', () async {
      await db.query(
        pg.config,
        'DELETE FROM pos_customers WHERE id = @id',
        parameters: {'id': mona},
      );

      final all = await history.search(const OrderHistoryQuery());
      final a = all.singleWhere((o) => o.invoiceNumber == 'INV-0001');

      expect(all, hasLength(5), reason: 'the sales stay');
      expect(a.customerName, isNull);
      expect(a.customerId, isNull);
    });
  });

  group('searching the list', () {
    test('by the customer\'s name, in any case', () async {
      expect(await invoicesFor('mona'), ['INV-0001', 'INV-0002']);
      expect(await invoicesFor('FATHY'), ['INV-0001', 'INV-0002']);
    });

    test('by a fragment of the name', () async {
      expect(await invoicesFor('karim'), ['INV-5432']);
    });

    test('by a full-length phone number', () async {
      expect(await invoicesFor('01012345678'), ['INV-0001', 'INV-0002']);
    });

    test('by the tail of a phone, once it is long enough to be one', () async {
      // Seven digits and up.
      expect(await invoicesFor('2345678'), ['INV-0001', 'INV-0002']);
    });

    test('by a phone typed in Arabic-Indic digits', () async {
      expect(await invoicesFor('٠١٠١٢٣٤٥٦٧٨'), ['INV-0001', 'INV-0002']);
    });

    test('a short run of digits is a receipt number, not somebody\'s phone', () async {
      // 5432 is the tail of INV-5432 AND of two phones — Karim's, whose sale it
      // is, and Layla's, a stranger's, whose sale is INV-0009. Under seven
      // digits it must find the receipt only: matching phones as well would
      // list Layla's sale for a cashier who typed what was on a receipt.
      expect(await invoicesFor('5432'), ['INV-5432']);
    });

    test('and it does not find the customer by those digits either', () async {
      // Karim's own sale is INV-5432, found because of its invoice. Mona's
      // phone ends 5678, so 5678 finds nobody at all.
      expect(await invoicesFor('5678'), isEmpty);
    });

    test('the invoice and table searches still work', () async {
      expect(await invoicesFor('0004'), ['INV-0004']);
      expect(await invoicesFor('INV-0001'), ['INV-0001']);
    });

    test('a customer\'s name does not match a sale for nobody', () async {
      expect(await invoicesFor('Mona'), isNot(contains('INV-0004')));
    });

    test('a search that matches nothing is an empty list', () async {
      expect(await invoicesFor('zzzzzz'), isEmpty);
    });

    test('the summary strip counts the same sales the search lists', () async {
      const query = OrderHistoryQuery(search: 'Mona');
      final rows = await history.search(query);
      final summary = await history.summarise(query);

      expect(rows, hasLength(2));
      expect(summary.count, rows.length);
    });
  });
}
