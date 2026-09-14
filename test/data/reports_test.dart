@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_branch_sales_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_order_history_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_reports_repository.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/models/ticket.dart' show OrderType;

import 'pg_fixture.dart';

/// Wave G's reports against PostgreSQL (plan 19 BO-5).
///
/// The range is business dates 9–11 September, in piastres:
///
/// | | POS-01 | POS-02 | POS-03 |
/// |---|---|---|---|
/// | 9th (a closed day) | — | y1 20,000 cash (Falafel ×4) | — |
/// | 10th (06:00Z → 01:00Z on the 11th) | o1 55,000 less 5,000, cash 30,000 + card 20,000 (Koshari ×2 @15,000, Grill ×1, a voided Grill); o2 12,345 on account at 22:30Z — past midnight in Cairo, still the 10th | o3 31,000 less 1,000, wallet, takeaway (Koshari ×2 @15,500) | — |
/// | 11th (no day opened) | o4 4,000 cash (Tea) | — | — |
/// | refunds issued | R2 2,000 on the 10th, against POS-02's y1 | R1 15,000 on the 10th, one Koshari off o1 | — |
///
/// Around it, everything that must NOT count: a void, an open order, a sale on
/// the 8th, R3 issued on the 12th against o4, and another branch's till.
void main() {
  if (PgFixture.host == null) {
    test('reports (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const pos01 = '20000000-0000-4000-8000-000000000001';
  const pos02 = '20000000-0000-4000-8000-000000000002';
  const pos03 = '20000000-0000-4000-8000-000000000003';
  const tanta = '20000000-0000-4000-8000-000000000009';

  const koshari = 101;
  const falafel = 102;
  const tea = 103;
  const grill = 104;

  final range = ReportFilter(
    from: DateTime(2026, 9, 9),
    to: DateTime(2026, 9, 12),
  );

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int otherBranchId;
  late int nour;
  late int hana;
  late Map<String, int> tender;
  late Map<String, int> orders;
  late PostgresReportsRepository reports;
  late PostgresOrderHistoryRepository history;
  var invoice = 0;

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0] as int;

  Future<int> sale({
    required String terminal,
    required int total,
    required DateTime at,
    required int servedBy,
    int discount = 0,
    int? day,
    int? branch,
    String status = 'PAID',
    String type = 'dine_in',
    List<(String, int)> payments = const [],
    List<(int?, String, int, int, bool)> lines = const [],
  }) async {
    invoice++;
    final id = await scalar(
      'INSERT INTO pos_orders (client_transaction_id, restaurant_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, business_day_id, served_by, voided_at, voided_by) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @inv, @type, 'EGP', 2, "
      '  @sub, @disc, 0, 0, @total, @at::timestamptz, @status, @day::bigint, '
      '  @served, '
      "  CASE WHEN @status::text = 'VOIDED' THEN @at::timestamptz END, "
      "  CASE WHEN @status::text = 'VOIDED' THEN @served::bigint END) "
      'RETURNING id',
      {
        'r': restaurantId,
        'b': branch ?? branchId,
        't': terminal,
        'inv': 'RP-$invoice',
        'type': type,
        'sub': total + discount,
        'disc': discount,
        'total': total,
        'at': at,
        'status': status,
        'day': day,
        'served': servedBy,
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
    var key = 0;
    for (final (item, name, quantity, unit, voided) in lines) {
      key++;
      await db.query(
        pg.config,
        'INSERT INTO pos_order_lines (order_id, line_key, menu_item_id, '
        '  name_snapshot, quantity, unit_price_minor, line_total_minor, stage, '
        '  voided_at, voided_by) '
        "VALUES (@o, @key, @item::bigint, @name, @q, @unit, @line, 'sent', "
        '  CASE WHEN @voided THEN @at::timestamptz END, '
        '  CASE WHEN @voided THEN @by::bigint END)',
        parameters: {
          'o': id,
          'key': 'l$key',
          'item': item,
          'name': name,
          'q': quantity,
          'unit': unit,
          'line': unit * quantity,
          'voided': voided,
          'at': at,
          'by': servedBy,
        },
      );
    }
    return id;
  }

  /// One transaction: the tender check is a deferred constraint trigger.
  Future<void> refund({
    required int orderId,
    required String issuedAt,
    required int total,
    required DateTime at,
    required int by,
    List<(String, int)> lines = const [],
  }) => db.runTx(pg.config, (tx) async {
    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO pos_refunds (client_refund_id, restaurant_id, branch_id, '
        '  terminal_id, order_id, kind, subtotal_minor, service_minor, '
        '  vat_minor, total_minor, refunded_by, occurred_at) '
        'VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, '
        "  'partial', @total, 0, 0, @total, @by, @at::timestamptz) RETURNING id",
      ),
      parameters: {
        'r': restaurantId,
        'b': branchId,
        't': issuedAt,
        'o': orderId,
        'total': total,
        'by': by,
        'at': at,
      },
    );
    final refundId = rows.first[0];
    for (final (name, quantity) in lines) {
      await tx.execute(
        Sql.named(
          'INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
          '  unit_price_minor, line_total_minor, name_snapshot) '
          // `::int` on both: one untyped parameter read as a quantity and as a
          // factor of a bigint is two types to PostgreSQL, and it refuses.
          'SELECT @id, l.id, @q::int, l.unit_price_minor, '
          '       l.unit_price_minor * @q::int, '
          '       l.name_snapshot '
          '  FROM pos_order_lines l '
          ' WHERE l.order_id = @o AND l.name_snapshot = @name '
          '   AND l.voided_at IS NULL',
        ),
        parameters: {'id': refundId, 'q': quantity, 'o': orderId, 'name': name},
      );
    }
    await tx.execute(
      Sql.named(
        'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
        "  amount_minor, counts_as_cash) VALUES (@id, @tt, 'cash', @total, true)",
      ),
      parameters: {'id': refundId, 'tt': tender['cash'], 'total': total},
    );
  });

  setUp(() async {
    pg = await PgFixture.open('reports');
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
      "INSERT INTO pos_restaurants (slug, name) VALUES ('rp', 'Reports') "
      'RETURNING id',
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
    Future<int> person(String name, String username) => scalar(
      'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, @name, @user, 'salt', 'hash') "
      'RETURNING id',
      {'r': restaurantId, 'b': branchId, 'name': name, 'user': username},
    );
    nour = await person('Nour Adel', 'nour');
    hana = await person('Hana Mostafa', 'hana');

    // Migration 23 seeds tender types for restaurants that existed when it
    // ran; this one did not.
    tender = {};
    for (final (code, kind, cash) in [
      ('cash', 'cash', true),
      ('card', 'card', false),
      ('wallet', 'wallet', false),
      ('account', 'account', false),
    ]) {
      tender[code] = await scalar(
        'INSERT INTO pos_tender_types (restaurant_id, code, name_en, kind, '
        '  counts_as_cash) VALUES (@r, @code, @code, @kind, @cash) RETURNING id',
        {'r': restaurantId, 'code': code, 'kind': kind, 'cash': cash},
      );
    }

    for (final (id, name, branch) in [
      (pos01, 'POS-01', branchId),
      (pos02, 'POS-02', branchId),
      (pos03, 'POS-03', branchId),
      (tanta, 'TANTA-01', otherBranchId),
    ]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
        'VALUES (@id::uuid, @r, @b, @name)',
        parameters: {'id': id, 'r': restaurantId, 'b': branch, 'name': name},
      );
    }

    // Both closed, so the trigger (migrations 35–36) files by window, and a
    // sale on the 11th finds no day at all.
    Future<int> day(String date, DateTime opened, DateTime closed) => scalar(
      'INSERT INTO pos_business_days (restaurant_id, branch_id, business_date, '
      '  opened_at, closed_at, closed_by) '
      'VALUES (@r, @b, @d::date, @o::timestamptz, @c::timestamptz, @by) '
      'RETURNING id',
      {
        'r': restaurantId,
        'b': branchId,
        'd': date,
        'o': opened,
        'c': closed,
        'by': nour,
      },
    );
    final ninth = await day(
      '2026-09-09',
      DateTime.utc(2026, 9, 9, 6),
      DateTime.utc(2026, 9, 9, 23),
    );
    await day(
      '2026-09-10',
      DateTime.utc(2026, 9, 10, 6),
      DateTime.utc(2026, 9, 11, 1),
    );

    orders = {
      'y1': await sale(
        terminal: pos02,
        total: 20000,
        day: ninth,
        at: DateTime.utc(2026, 9, 9, 12),
        servedBy: nour,
        payments: [('cash', 20000)],
        lines: [(falafel, 'Falafel', 4, 5000, false)],
      ),
      'o1': await sale(
        terminal: pos01,
        total: 50000,
        discount: 5000,
        at: DateTime.utc(2026, 9, 10, 10),
        servedBy: nour,
        payments: [('cash', 30000), ('card', 20000)],
        lines: [
          (koshari, 'Koshari', 2, 15000, false),
          (grill, 'Mixed grill', 1, 25000, false),
          (grill, 'Mixed grill', 1, 25000, true),
        ],
      ),
      'o2': await sale(
        terminal: pos01,
        total: 12345,
        at: DateTime.utc(2026, 9, 10, 22, 30),
        servedBy: nour,
        payments: [('account', 12345)],
        lines: [(tea, 'Tea', 1, 12345, false)],
      ),
      'o3': await sale(
        terminal: pos02,
        total: 30000,
        discount: 1000,
        type: 'takeaway',
        at: DateTime.utc(2026, 9, 10, 11),
        servedBy: hana,
        payments: [('wallet', 30000)],
        lines: [(koshari, 'Koshari', 2, 15500, false)],
      ),
      'void': await sale(
        terminal: pos02,
        total: 9999,
        status: 'VOIDED',
        at: DateTime.utc(2026, 9, 10, 12),
        servedBy: nour,
        lines: [(grill, 'Mixed grill', 1, 9999, false)],
      ),
      'open': await sale(
        terminal: pos02,
        total: 5555,
        status: 'OPEN',
        at: DateTime.utc(2026, 9, 10, 13),
        servedBy: nour,
      ),
      // Noon UTC, so the local calendar date is the 11th in any zone a till
      // is in. No day is open: filed by the calendar, as the sales list files it.
      'o4': await sale(
        terminal: pos01,
        total: 4000,
        at: DateTime.utc(2026, 9, 11, 12),
        servedBy: hana,
        payments: [('cash', 4000)],
        lines: [(tea, 'Tea', 1, 4000, false)],
      ),
      'before': await sale(
        terminal: pos01,
        total: 7777,
        at: DateTime.utc(2026, 9, 8, 12),
        servedBy: nour,
        payments: [('cash', 7777)],
      ),
      'tanta': await sale(
        terminal: tanta,
        branch: otherBranchId,
        total: 88888,
        at: DateTime.utc(2026, 9, 10, 12),
        servedBy: nour,
        payments: [('cash', 88888)],
      ),
    };

    // R1: at POS-02, one Koshari off POS-01's sale.
    await refund(
      orderId: orders['o1']!,
      issuedAt: pos02,
      total: 15000,
      at: DateTime.utc(2026, 9, 10, 14),
      by: hana,
      lines: [('Koshari', 1)],
    );
    // R2: at POS-01 on the 10th, against POS-02's sale of the 9th.
    await refund(
      orderId: orders['y1']!,
      issuedAt: pos01,
      total: 2000,
      at: DateTime.utc(2026, 9, 10, 15),
      by: nour,
    );
    // R3: issued on the 12th — outside the range, though its sale is inside.
    await refund(
      orderId: orders['o4']!,
      issuedAt: pos01,
      total: 1000,
      at: DateTime.utc(2026, 9, 12, 12),
      by: nour,
    );

    reports = PostgresReportsRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
    );
    history = PostgresOrderHistoryRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  /// What a sales figure drills into: plan 17 S1's list, for the filter.
  Future<List<OrderRecord>> listed(ReportFilter filter) =>
      history.search(filter.historyQuery(limit: 1000));

  Money grossOf(List<OrderRecord> rows) =>
      rows.fold(Money.zero, (sum, o) => sum + o.total + o.discount);
  Money discountsOf(List<OrderRecord> rows) =>
      rows.fold(Money.zero, (sum, o) => sum + o.discount);

  test('the period totals, as the table above says', () async {
    final report = await reports.sales(range);

    expect(report.orders, 5, reason: 'y1, o1, o2, o3, o4 — no void, no open');
    expect(report.gross, const Money(122345));
    expect(report.discounts, const Money(6000));
    expect(report.refunds, const Money(17000), reason: 'R1 + R2; R3 is the 12th');
    expect(report.refundCount, 2);
    expect(report.net, const Money(99345));
    expect(report.averageOrder, const Money(19869));
  });

  test('every sales figure is the sum of the sales its drill-down lists', () async {
    final report = await reports.sales(range);
    final rows = await listed(range);

    expect(report.orders, rows.length);
    expect(report.gross, grossOf(rows));
    expect(report.discounts, discountsOf(rows));

    for (final terminal in report.terminals) {
      final drilled = await listed(
        ReportFilter(
          from: range.from,
          to: range.to,
          terminalId: terminal.terminalId,
        ),
      );
      expect(terminal.orders, drilled.length, reason: terminal.name);
      expect(terminal.gross, grossOf(drilled), reason: terminal.name);
      expect(terminal.discounts, discountsOf(drilled), reason: terminal.name);
    }

    for (final day in report.days) {
      final drilled = await listed(ReportFilter.day(day.date));
      expect(day.orders, drilled.length, reason: '${day.date}');
      expect(day.gross, grossOf(drilled), reason: '${day.date}');
      expect(day.discounts, discountsOf(drilled), reason: '${day.date}');
    }
  });

  test('each tender is the sum of the payment rows of the sales listed', () async {
    final report = await reports.sales(range);
    final paid = <int, (int, Money)>{};
    for (final order in await listed(range)) {
      for (final payment in (await history.detail(order.id))!.payments) {
        final (count, amount) = paid[payment.tenderTypeId!] ?? (0, Money.zero);
        paid[payment.tenderTypeId!] = (count + 1, amount + payment.amount);
      }
    }

    expect(
      {
        for (final m in report.paymentsByMethod)
          m.tenderTypeId!: (m.count, m.amount),
      },
      paid,
    );
    expect(report.onAccount, const Money(12345));
    expect(report.collected, const Money(104000));
    expect(
      {for (final s in report.tenderShares) s.method.label: s.basisPoints},
      {'card': 1923, 'cash': 5192, 'wallet': 2885},
      reason: 'on account has no slice; the slices make 10,000',
    );
  });

  test('top products are the kept units of the lines listed, voids left out', () async {
    final kept = <String, (int, Money)>{};
    for (final order in await listed(range)) {
      for (final line in (await history.detail(order.id))!.lines) {
        if (line.voidedAt != null) continue;
        final units = line.quantity - line.refundedQuantity;
        final (quantity, amount) = kept[line.name] ?? (0, Money.zero);
        kept[line.name] = (quantity + units, amount + line.unitPrice * units);
      }
    }

    final byQuantity = await reports.topProducts(
      range,
      by: ProductRanking.quantity,
      limit: 10,
    );
    expect(
      {for (final p in byQuantity) p.name: (p.quantity, p.amount)},
      kept,
    );
    expect(byQuantity.map((p) => p.name), [
      'Falafel', // 4
      'Koshari', // 2 + 2, less the one R1 took back
      'Tea', // 2
      'Mixed grill', // 1 — the voided one and the voided sale's are not sales
    ]);
    expect(byQuantity[1].amount, const Money(46000));

    final byAmount = await reports.topProducts(
      range,
      by: ProductRanking.amount,
      limit: 2,
    );
    expect(byAmount.map((p) => (p.menuItemId, p.amount)), [
      (koshari, const Money(46000)),
      (grill, const Money(25000)),
    ]);
  });

  test('the terminals sum to the branch to the piastre, the idle one listed', () async {
    final report = await reports.sales(range);

    expect(report.terminals.map((t) => t.name), ['POS-01', 'POS-02', 'POS-03']);
    final one = report.terminal(pos01)!;
    final two = report.terminal(pos02)!;
    final idle = report.terminal(pos03)!;
    expect((one.orders, one.gross, one.discounts, one.refunds), (
      3,
      const Money(71345),
      const Money(5000),
      const Money(2000),
    ));
    expect((two.orders, two.gross, two.discounts, two.refunds), (
      2,
      const Money(51000),
      const Money(1000),
      const Money(15000),
    ));
    expect((idle.orders, idle.gross, idle.refunds), (0, Money.zero, Money.zero));
    expect(idle.payments, isEmpty);
    expect(report.terminal(tanta), isNull, reason: 'another branch');

    expect(one.net + two.net + idle.net, report.net);
    expect(report.net, const Money(99345));
  });

  test('a refund sits on the terminal that issued it, on the day it was issued', () async {
    final report = await reports.sales(range);

    expect(
      report.terminal(pos01)!.refunds,
      const Money(2000),
      reason: "R2 — the sale was POS-02's and the 9th's; POS-01's drawer paid it",
    );
    expect(report.terminal(pos02)!.refunds, const Money(15000));
    expect(report.days.map((d) => d.refunds), [
      Money.zero,
      const Money(17000),
      Money.zero,
    ], reason: "both on the 10th; the 9th's sale does not take R2 back a day");

    final twelfth = await reports.sales(ReportFilter.day(DateTime(2026, 9, 12)));
    expect(twelfth.refunds, const Money(1000), reason: 'R3, whose sale was the 11th');
    expect(twelfth.orders, 0);
  });

  test('a night past midnight is one business day; a day nobody opened is the calendar\'s', () async {
    final report = await reports.sales(range);

    expect(report.days.map((d) => d.date), range.dates);
    expect(report.days.map((d) => d.orders), [1, 3, 1],
        reason: "o2 at 22:30Z is the 10th's; o4 with no day is the 11th's");
    expect(report.days.map((d) => d.gross), [
      const Money(20000),
      const Money(98345),
      const Money(4000),
    ]);
    expect(
      report.days.fold(Money.zero, (sum, d) => sum + d.net),
      report.net,
      reason: 'the trend sums to the tiles',
    );
  });

  test('one business day agrees with the branch view, terminal by terminal', () async {
    final tenth = DateTime(2026, 9, 10);
    final branch = (await PostgresBranchSalesRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
    ).summary(tenth)).sales!;
    final report = await reports.sales(ReportFilter.day(tenth));

    expect(report.terminals.map((t) => t.terminalId),
        branch.terminals.map((t) => t.terminalId));
    for (final day in branch.terminals) {
      final ours = report.terminal(day.terminalId)!;
      expect(
        (ours.orders, ours.gross, ours.discounts, ours.refunds, ours.refundCount),
        (day.orders, day.gross, day.discounts, day.refunds, day.refundCount),
        reason: day.name,
      );
      expect(
        ours.payments.map((m) => (m.label, m.count, m.amount)),
        day.payments.map((m) => (m.label, m.count, m.amount)),
        reason: day.name,
      );
    }
    expect(report.net, branch.net);
  });

  test('filters narrow sales and refunds alike', () async {
    final atTwo = await reports.sales(
      ReportFilter(from: range.from, to: range.to, terminalId: pos02),
    );
    expect(atTwo.terminals.map((t) => t.terminalId), [pos02]);
    expect((atTwo.orders, atTwo.gross, atTwo.refunds), (
      2,
      const Money(51000),
      const Money(15000),
    ), reason: 'y1 and o3; R1 was issued here');

    final byHana = await reports.sales(
      ReportFilter(from: range.from, to: range.to, servedByStaffId: hana),
    );
    expect((byHana.orders, byHana.gross, byHana.refunds), (
      2,
      const Money(35000),
      const Money(15000),
    ), reason: 'o3 and o4 she rang up; R1 she issued');

    final takeaway = await reports.sales(
      ReportFilter(
        from: range.from,
        to: range.to,
        orderTypes: {OrderType.takeaway},
      ),
    );
    expect((takeaway.orders, takeaway.gross, takeaway.refunds), (
      1,
      const Money(31000),
      Money.zero,
    ), reason: 'o3; both refunds were against dine-in sales');
    expect(takeaway.orders, (await listed(takeaway.filter)).length);
  });

  test('a range with nothing in it lists every terminal and every day at zero', () async {
    final quiet = await reports.sales(
      ReportFilter(from: DateTime(2026, 9, 13), to: DateTime(2026, 9, 15)),
    );

    expect(quiet.terminals, hasLength(3));
    expect(quiet.days, hasLength(2));
    expect(quiet.gross, Money.zero);
    expect(quiet.averageOrder, isNull);
    expect(quiet.tenderShares, isEmpty);
    expect(
      await reports.topProducts(
        ReportFilter.day(DateTime(2026, 9, 13)),
        by: ProductRanking.amount,
      ),
      isEmpty,
    );
  });

  test("the till's own credential can run every report", () async {
    // Every suite here runs as a role that needs no grant, which is how six
    // tables once went ungranted with every test green. This one does not.
    final role = PgFixture.roleFor('reports_probe');
    const password = 'probe-only';
    Future<void> dropRole() async {
      for (final statement in [
        'DROP OWNED BY "$role"',
        'DROP ROLE IF EXISTS "$role"',
      ]) {
        try {
          await db.query(pg.config, statement);
        } on Object {
          // Nothing to revoke, or nothing to drop.
        }
      }
    }

    await dropRole();
    await db.query(pg.config, 'CREATE ROLE "$role" LOGIN PASSWORD \'$password\'');
    final probe = PosDatabase(credentials: InMemoryPosDbCredentials(password));
    try {
      for (final statement in LocalBootstrap.tillGrants(
        database: pg.config.databaseName,
        role: role,
      )) {
        await db.query(pg.config, statement);
      }
      final asTill = PostgresReportsRepository(
        database: probe,
        config: DeploymentConfig(
          mode: DeploymentMode.offline,
          databaseHost: pg.config.databaseHost,
          verifyTls: false,
          databaseName: pg.config.databaseName,
          databaseUser: role,
          databasePort: pg.config.databasePort,
        ),
        restaurantId: restaurantId,
        branchId: branchId,
      );

      expect((await asTill.sales(range)).net, const Money(99345));
      expect(
        await asTill.topProducts(range, by: ProductRanking.quantity),
        hasLength(4),
      );
    } finally {
      await probe.close();
      await dropRole();
    }
  });
}
