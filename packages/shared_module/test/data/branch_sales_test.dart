@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_branch_sales_repository.dart';
import 'package:shared_module/domain/models/branch_sales.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// §3a against PostgreSQL — the shared-database branch view.
///
/// The day, in piastres:
///
/// | | POS-01 | POS-02 | POS-03 |
/// |---|---|---|---|
/// | sales | 50,000 (5,000 off; 30,000 cash + 20,000 card) and 12,345 on account after midnight | 30,000 (1,000 off; wallet) | — |
/// | refunds issued | — | 7,000, against POS-01's sale | — |
///
/// Around it, everything that must NOT count: a void, an open order, a sale
/// stamped yesterday, an unstamped sale inside yesterday's window, yesterday's
/// refund, and another branch's till.
void main() {
  if (PgFixture.host == null) {
    test('branch sales (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const pos01 = '10000000-0000-4000-8000-000000000001';
  const pos02 = '10000000-0000-4000-8000-000000000002';
  const pos03 = '10000000-0000-4000-8000-000000000003';
  const elsewhere = '10000000-0000-4000-8000-000000000009';
  const stranger = '10000000-0000-4000-8000-00000000000f';

  final businessDay = DateTime(2026, 9, 10);

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int staffId;
  late int today;
  late int yesterday;
  late Map<String, int> tender;
  late Map<String, int> orders;
  late PostgresBranchSalesRepository repository;
  var invoice = 0;

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0] as int;

  Future<int> sale({
    required String terminal,
    required int total,
    required DateTime at,
    int discount = 0,
    int? day,
    int? branch,
    String status = 'PAID',
    List<(String, int)> payments = const [],
  }) async {
    invoice++;
    final id = await scalar(
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, business_day_id, voided_at, voided_by) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @inv, 'dine_in', 'EGP', 2, "
      '  @sub, @disc, 0, 0, @total, @at::timestamptz, @status, @day::bigint, '
      "  CASE WHEN @status::text = 'VOIDED' THEN @at::timestamptz END, "
      "  CASE WHEN @status::text = 'VOIDED' THEN @staff::bigint END) "
      'RETURNING id',
      {
        'r': businessId,
        'b': branch ?? branchId,
        't': terminal,
        'inv': 'BS-$invoice',
        'sub': total + discount,
        'disc': discount,
        'total': total,
        'at': at,
        'status': status,
        'day': day,
        'staff': staffId,
      },
    );
    for (final (code, amount) in payments) {
      await db.query(
        pg.config,
        'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
        '  amount_minor, counts_as_cash) VALUES (@o, @tt, @label, @amount, @cash)',
        parameters: {
          'o': id,
          'tt': tender[code],
          'label': code,
          'amount': amount,
          'cash': code == 'cash',
        },
      );
    }
    return id;
  }

  /// One transaction: the tender check is a deferred constraint trigger.
  Future<void> refund({
    required int orderId,
    required String issuedBy,
    required int total,
    required DateTime at,
    int? day,
  }) => db.runTx(pg.config, (tx) async {
    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO pos_refunds (client_refund_id, business_id, branch_id, '
        '  terminal_id, order_id, business_day_id, kind, subtotal_minor, '
        '  service_minor, vat_minor, total_minor, refunded_by, occurred_at) '
        'VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, @day::bigint, '
        "  'partial', @total, 0, 0, @total, @by, @at::timestamptz) RETURNING id",
      ),
      parameters: {
        'r': businessId,
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
      parameters: {'id': rows.first[0], 'tt': tender['cash'], 'total': total},
    );
  });

  setUp(() async {
    pg = await PgFixture.open('branch_sales');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_outbox, pos_refunds, pos_orders, pos_business_days, '
      'pos_invoice_sequences RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    invoice = 0;

    businessId = await scalar(
      "INSERT INTO pos_businesses (slug, name) VALUES ('bs', 'Branch sales') "
      'RETURNING id',
    );
    branchId = await scalar(
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'MANS', 'Mansoura') RETURNING id",
      {'r': businessId},
    );
    otherBranchId = await scalar(
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'TANT', 'Tanta') RETURNING id",
      {'r': businessId},
    );
    staffId = await scalar(
      'INSERT INTO pos_users (business_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', 'nour', 'salt', "
      "  'hash') RETURNING id",
      {'r': businessId, 'b': branchId},
    );

    // Migration 23 seeds tender types for businesses that existed when it
    // ran; this one did not.
    tender = {};
    for (final (code, kind, cash) in [
      ('cash', 'cash', true),
      ('card', 'card', false),
      ('wallet', 'wallet', false),
      ('account', 'account', false),
    ]) {
      tender[code] = await scalar(
        'INSERT INTO pos_tender_types (business_id, code, name_en, kind, '
        '  counts_as_cash) VALUES (@r, @code, @code, @kind, @cash) RETURNING id',
        {'r': businessId, 'code': code, 'kind': kind, 'cash': cash},
      );
    }

    for (final (id, name, branch) in [
      (pos01, 'POS-01', branchId),
      (pos02, 'POS-02', branchId),
      (pos03, 'POS-03', branchId),
      (elsewhere, 'TANTA-01', otherBranchId),
    ]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
        'VALUES (@id::uuid, @r, @b, @name)',
        parameters: {'id': id, 'r': businessId, 'b': branch, 'name': name},
      );
    }

    Future<int> openDay(int branch, String date, DateTime opened,
        {DateTime? closed}) => scalar(
      'INSERT INTO pos_business_days (business_id, branch_id, business_date, '
      '  opened_at, closed_at, closed_by) '
      'VALUES (@r, @b, @d::date, @o::timestamptz, @c::timestamptz, @by::bigint) '
      'RETURNING id',
      {
        'r': businessId,
        'b': branch,
        'd': date,
        'o': opened,
        'c': closed,
        'by': closed == null ? null : staffId,
      },
    );

    yesterday = await openDay(
      branchId,
      '2026-09-09',
      DateTime.utc(2026, 9, 9, 6),
      closed: DateTime.utc(2026, 9, 9, 23),
    );
    today = await openDay(branchId, '2026-09-10', DateTime.utc(2026, 9, 10, 6));
    final tantaToday = await openDay(
      otherBranchId,
      '2026-09-10',
      DateTime.utc(2026, 9, 10, 6),
    );

    orders = {
      'o1': await sale(
        terminal: pos01,
        total: 50000,
        discount: 5000,
        day: today,
        at: DateTime.utc(2026, 9, 10, 10),
        payments: [('cash', 30000), ('card', 20000)],
      ),
      // Unstamped, and 01:30 in Cairo on the 11th: still the 10th's trading
      // day, because the 10th's day was still open.
      'o2': await sale(
        terminal: pos01,
        total: 12345,
        at: DateTime.utc(2026, 9, 10, 22, 30),
        payments: [('account', 12345)],
      ),
      'o3': await sale(
        terminal: pos02,
        total: 30000,
        discount: 1000,
        day: today,
        at: DateTime.utc(2026, 9, 10, 11),
        payments: [('wallet', 30000)],
      ),
      'void': await sale(
        terminal: pos02,
        total: 9999,
        day: today,
        status: 'VOIDED',
        at: DateTime.utc(2026, 9, 10, 12),
      ),
      'open': await sale(
        terminal: pos02,
        total: 5555,
        day: today,
        status: 'OPEN',
        at: DateTime.utc(2026, 9, 10, 13),
      ),
      'yesterday': await sale(
        terminal: pos02,
        total: 77777,
        day: yesterday,
        at: DateTime.utc(2026, 9, 9, 12),
        payments: [('cash', 77777)],
      ),
      'yesterdayUnstamped': await sale(
        terminal: pos01,
        total: 4444,
        at: DateTime.utc(2026, 9, 9, 12),
        payments: [('cash', 4444)],
      ),
      'tanta': await sale(
        terminal: elsewhere,
        branch: otherBranchId,
        total: 88888,
        day: tantaToday,
        at: DateTime.utc(2026, 9, 10, 12),
        payments: [('cash', 88888)],
      ),
    };

    // Issued at POS-02 against POS-01's sale; unstamped, inside today.
    await refund(
      orderId: orders['o1']!,
      issuedBy: pos02,
      total: 7000,
      at: DateTime.utc(2026, 9, 10, 14),
    );
    // Yesterday's refund, at POS-01 — not today's figure on any row.
    await refund(
      orderId: orders['yesterday']!,
      issuedBy: pos01,
      total: 1000,
      day: yesterday,
      at: DateTime.utc(2026, 9, 9, 15),
    );

    repository = PostgresBranchSalesRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  Future<BranchSales> read([DateTime? day]) async =>
      (await repository.summary(day ?? businessDay)).sales!;

  test('every terminal of the branch is listed, zeros included, and only this branch', () async {
    final sales = await read();

    expect(sales.terminals.map((t) => t.terminalId), [pos01, pos02, pos03]);
    final idle = sales.terminal(pos03)!;
    expect(idle.name, 'POS-03');
    expect(idle.orders, 0);
    expect(idle.gross, Money.zero);
    expect(idle.payments, isEmpty);
    expect(sales.terminal(elsewhere), isNull);
  });

  test('the branch total is the sum of its terminal rows, to the piastre', () async {
    final sales = await read();
    final one = sales.terminal(pos01)!;
    final two = sales.terminal(pos02)!;

    // The rows, independently of anything the model derives.
    expect(one.orders, 2);
    expect(one.gross, const Money(67345), reason: '55,000 before discount + 12,345');
    expect(one.discounts, const Money(5000));
    expect(two.orders, 1);
    expect(two.gross, const Money(31000));
    expect(two.discounts, const Money(1000));

    expect(sales.orders, 3);
    expect(sales.gross, const Money(98345));
    expect(sales.discounts, const Money(6000));
    expect(sales.refunds, const Money(7000));
    expect(sales.net, const Money(85345));
    expect(
      sales.gross,
      sales.terminals.fold(Money.zero, (sum, t) => sum + t.gross),
    );
  });

  test('net is gross less discounts less refunds, per row and for the branch', () async {
    final sales = await read();

    expect(sales.terminal(pos01)!.net, const Money(62345));
    expect(sales.terminal(pos02)!.net, const Money(23000));
    expect(sales.net, sales.gross - sales.discounts - sales.refunds);
  });

  test('on account is its own figure and never counted as collected', () async {
    final sales = await read();
    final one = sales.terminal(pos01)!;

    expect(one.cash, const Money(30000));
    expect(one.electronic, const Money(20000));
    expect(one.onAccount, const Money(12345));
    expect(one.collected, const Money(50000));
    expect(sales.terminal(pos02)!.electronic, const Money(30000), reason: 'wallet');

    expect(sales.cash, const Money(30000));
    expect(sales.electronic, const Money(50000));
    expect(sales.onAccount, const Money(12345));
    expect(sales.collected, const Money(80000));
    // And the three reconcile to every payment row of the day's sales.
    expect(
      sales.cash + sales.electronic + sales.onAccount + sales.otherTender,
      const Money(92345),
    );
  });

  test('a refund lands on the terminal that issued it, in the day it was issued', () async {
    final sales = await read();

    expect(sales.terminal(pos02)!.refunds, const Money(7000));
    expect(sales.terminal(pos02)!.refundCount, 1);
    expect(
      sales.terminal(pos01)!.refunds,
      Money.zero,
      reason: "the sale was POS-01's; the drawer the money left was POS-02's, "
          "and POS-01's own refund was yesterday",
    );
  });

  test('a till that took money here without being registered is still listed', () async {
    final before = await read();
    await sale(
      terminal: stranger,
      total: 2500,
      day: today,
      at: DateTime.utc(2026, 9, 10, 16),
      payments: [('cash', 2500)],
    );
    final after = await read();

    final row = after.terminal(stranger)!;
    expect(row.isRegistered, isFalse);
    expect(row.gross, const Money(2500));
    expect(after.gross - before.gross, const Money(2500));
    expect(after.terminals.last.terminalId, stranger, reason: 'after the named ones');
  });

  test('a day nobody opened shows every terminal at zero rather than nothing', () async {
    final sales = await read(DateTime(2026, 9, 12));

    expect(sales.terminals.map((t) => t.terminalId), [pos01, pos02, pos03]);
    expect(sales.gross, Money.zero);
  });

  test("this till's undelivered sales are counted per terminal and day", () async {
    Future<void> enqueue(String key, {bool delivered = false}) => db.query(
      pg.config,
      'INSERT INTO pos_outbox (order_id, client_transaction_id, business_id, '
      '  branch_id, delivered_at) '
      'SELECT id, client_transaction_id, business_id, branch_id, '
      '  CASE WHEN @delivered THEN now() END FROM pos_orders WHERE id = @id',
      parameters: {'id': orders[key], 'delivered': delivered},
    );
    await enqueue('o1', delivered: true);
    await enqueue('o2');
    await enqueue('yesterday');

    expect(await repository.unsyncedSalesOn(businessDay, terminalId: pos01), 1);
    expect(
      await repository.unsyncedSalesOn(businessDay, terminalId: pos02),
      0,
      reason: "POS-02's undelivered sale is yesterday's",
    );
  });
}
