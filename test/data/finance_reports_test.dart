@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_order_history_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_reports_repository.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/models/tax.dart';

import 'pg_fixture.dart';

/// Finance's taxes and payments against PostgreSQL (plan 19 BO-9).
///
/// The range is business dates 10–11 September, in piastres:
///
/// | sale | at | VAT on the order | `pos_order_taxes` | paid |
/// |---|---|---|---|---|
/// | s0 | POS-01, the 9th — before the range | 1,400 | VAT 14% on 10,000 = 1,400 | cash |
/// | s1 | POS-01, the 10th | 1,400 | VAT 14% on 10,000 = 1,400; Zero-rated 0% on 1,400 | cash |
/// | s2 | POS-02, the 10th | 2,950 | VAT 14% on 20,000 = 2,800; Reduced 5% on 3,000 = 150 | card + wallet |
/// | s3 | POS-01, the 11th (no day open) | 700 | VAT 14% on 5,000 = 700 | on account |
/// | s4 | POS-02, the 10th | 500 | none — a sale with no breakdown | cash |
///
/// | refund | issued | VAT | split |
/// |---|---|---|---|
/// | R1 | POS-02, the 10th, off s2 | 1,000 | VAT 949, Reduced 51 |
/// | R2 | POS-01, the 10th, off s0 (the 9th's) | 700 | VAT 700 |
/// | R4 | POS-01, the 11th, off s1 | 700 | VAT 700, Zero-rated 0 |
/// | R5 | POS-02, the 10th, off s4 | 300 | no rate to give it |
/// | R6 | POS-01, the 11th, off s3 | 0 | nothing |
///
/// Around it, what must NOT count: a void and an open order with tax rows,
/// another branch's sale, a sale on the 13th and R3 issued on the 13th.
void main() {
  if (PgFixture.host == null) {
    test('finance reports (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const pos01 = '30000000-0000-4000-8000-000000000001';
  const pos02 = '30000000-0000-4000-8000-000000000002';
  const tanta = '30000000-0000-4000-8000-000000000009';

  final range = ReportFilter(
    from: DateTime(2026, 9, 10),
    to: DateTime(2026, 9, 12),
  );

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int otherBranchId;
  late int nour;
  late Map<String, int> tender;
  late Map<String, int> orders;
  late Map<String, int> refunds;
  late PostgresReportsRepository reports;
  late PostgresOrderHistoryRepository history;
  var invoice = 0;

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0] as int;

  Future<int> sale({
    required String terminal,
    required int total,
    required int vat,
    required DateTime at,
    int? branch,
    String status = 'PAID',
    List<(String, int)> payments = const [],
    List<(String, int, int, int)> taxes = const [],
  }) async {
    invoice++;
    final id = await scalar(
      'INSERT INTO pos_orders (client_transaction_id, restaurant_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, served_by, voided_at, voided_by) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @inv, 'dine_in', 'EGP', 2, "
      '  @sub, 0, 0, @vat, @total, @at::timestamptz, @status, @served, '
      "  CASE WHEN @status::text = 'VOIDED' THEN @at::timestamptz END, "
      "  CASE WHEN @status::text = 'VOIDED' THEN @served::bigint END) "
      'RETURNING id',
      {
        'r': restaurantId,
        'b': branch ?? branchId,
        't': terminal,
        'inv': 'FN-$invoice',
        'sub': total - vat,
        'vat': vat,
        'total': total,
        'at': at,
        'status': status,
        'served': nour,
      },
    );
    for (final (code, amount) in payments) {
      // The payment's own time, as a settlement writes it: the ledger is
      // ordered by it, and the column's default is the moment of the INSERT.
      await db.query(
        pg.config,
        'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
        '  amount_minor, counts_as_cash, occurred_at) '
        'VALUES (@o, @tt, @label, @amount, @cash, @at::timestamptz)',
        parameters: {
          'o': id,
          'tt': tender[code],
          'label': code,
          'amount': amount,
          'cash': code == 'cash',
          'at': at,
        },
      );
    }
    for (final (name, rate, base, amount) in taxes) {
      await db.query(
        pg.config,
        'INSERT INTO pos_order_taxes (order_id, name_snapshot, rate_bp, '
        '  base_minor, amount_minor) VALUES (@o, @name, @rate, @base, @amount)',
        parameters: {
          'o': id,
          'name': name,
          'rate': rate,
          'base': base,
          'amount': amount,
        },
      );
    }
    return id;
  }

  /// One transaction: the tender check is a deferred constraint trigger.
  Future<int> refund({
    required int orderId,
    required String issuedAt,
    required int total,
    required int vat,
    required DateTime at,
  }) => db.runTx(pg.config, (tx) async {
    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO pos_refunds (client_refund_id, restaurant_id, branch_id, '
        '  terminal_id, order_id, kind, subtotal_minor, service_minor, '
        '  vat_minor, total_minor, refunded_by, occurred_at) '
        'VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, '
        "  'partial', @sub, 0, @vat, @total, @by, @at::timestamptz) RETURNING id",
      ),
      parameters: {
        'r': restaurantId,
        'b': branchId,
        't': issuedAt,
        'o': orderId,
        'sub': total - vat,
        'vat': vat,
        'total': total,
        'by': nour,
        'at': at,
      },
    );
    final refundId = rows.first[0]! as int;
    await tx.execute(
      Sql.named(
        'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
        "  amount_minor, counts_as_cash) VALUES (@id, @tt, 'cash', @total, true)",
      ),
      parameters: {'id': refundId, 'tt': tender['cash'], 'total': total},
    );
    return refundId;
  });

  setUp(() async {
    pg = await PgFixture.open('finance_reports');
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
      "INSERT INTO pos_restaurants (slug, name) VALUES ('fn', 'Finance') "
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
    nour = await scalar(
      'INSERT INTO pos_users (restaurant_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', 'nour', 'salt', "
      "  'hash') RETURNING id",
      {'r': restaurantId, 'b': branchId},
    );

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
      (tanta, 'TANTA-01', otherBranchId),
    ]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
        'VALUES (@id::uuid, @r, @b, @name)',
        parameters: {'id': id, 'r': restaurantId, 'b': branch, 'name': name},
      );
    }

    // The 10th, closed, so the 10th's rows file by its window. The 11th has
    // no day: its rows file by the calendar, as the sales list files them.
    await scalar(
      'INSERT INTO pos_business_days (restaurant_id, branch_id, business_date, '
      '  opened_at, closed_at, closed_by) '
      "VALUES (@r, @b, '2026-09-10'::date, @o::timestamptz, @c::timestamptz, "
      '  @by) RETURNING id',
      {
        'r': restaurantId,
        'b': branchId,
        'o': DateTime.utc(2026, 9, 10, 6),
        'c': DateTime.utc(2026, 9, 11, 1),
        'by': nour,
      },
    );

    const vat = 'VAT';
    orders = {
      's0': await sale(
        terminal: pos01,
        total: 11400,
        vat: 1400,
        at: DateTime.utc(2026, 9, 9, 12),
        payments: [('cash', 11400)],
        taxes: [(vat, 1400, 10000, 1400)],
      ),
      's1': await sale(
        terminal: pos01,
        total: 12800,
        vat: 1400,
        at: DateTime.utc(2026, 9, 10, 10),
        payments: [('cash', 12800)],
        taxes: [(vat, 1400, 10000, 1400), ('Zero-rated', 0, 1400, 0)],
      ),
      's2': await sale(
        terminal: pos02,
        total: 25950,
        vat: 2950,
        at: DateTime.utc(2026, 9, 10, 11),
        payments: [('card', 20000), ('wallet', 5950)],
        taxes: [(vat, 1400, 20000, 2800), ('Reduced', 500, 3000, 150)],
      ),
      's3': await sale(
        terminal: pos01,
        total: 5700,
        vat: 700,
        at: DateTime.utc(2026, 9, 11, 12),
        payments: [('account', 5700)],
        taxes: [(vat, 1400, 5000, 700)],
      ),
      's4': await sale(
        terminal: pos02,
        total: 3500,
        vat: 500,
        at: DateTime.utc(2026, 9, 10, 12),
        payments: [('cash', 3500)],
      ),
      'void': await sale(
        terminal: pos01,
        total: 11400,
        vat: 1400,
        status: 'VOIDED',
        at: DateTime.utc(2026, 9, 10, 13),
        taxes: [(vat, 1400, 10000, 1400)],
      ),
      'open': await sale(
        terminal: pos02,
        total: 11400,
        vat: 1400,
        status: 'OPEN',
        at: DateTime.utc(2026, 9, 10, 14),
        taxes: [(vat, 1400, 10000, 1400)],
      ),
      'tanta': await sale(
        terminal: tanta,
        branch: otherBranchId,
        total: 11400,
        vat: 1400,
        at: DateTime.utc(2026, 9, 10, 12),
        payments: [('cash', 11400)],
        taxes: [(vat, 1400, 10000, 1400)],
      ),
      'after': await sale(
        terminal: pos01,
        total: 11400,
        vat: 1400,
        at: DateTime.utc(2026, 9, 13, 12),
        payments: [('cash', 11400)],
        taxes: [(vat, 1400, 10000, 1400)],
      ),
    };

    refunds = {
      'R1': await refund(
        orderId: orders['s2']!,
        issuedAt: pos02,
        total: 5000,
        vat: 1000,
        at: DateTime.utc(2026, 9, 10, 15),
      ),
      'R2': await refund(
        orderId: orders['s0']!,
        issuedAt: pos01,
        total: 2000,
        vat: 700,
        at: DateTime.utc(2026, 9, 10, 16),
      ),
      'R4': await refund(
        orderId: orders['s1']!,
        issuedAt: pos01,
        total: 1000,
        vat: 700,
        at: DateTime.utc(2026, 9, 11, 12, 30),
      ),
      'R5': await refund(
        orderId: orders['s4']!,
        issuedAt: pos02,
        total: 1000,
        vat: 300,
        at: DateTime.utc(2026, 9, 10, 17),
      ),
      'R6': await refund(
        orderId: orders['s3']!,
        issuedAt: pos01,
        total: 200,
        vat: 0,
        at: DateTime.utc(2026, 9, 11, 13),
      ),
      'R3': await refund(
        orderId: orders['s3']!,
        issuedAt: pos01,
        total: 500,
        vat: 50,
        at: DateTime.utc(2026, 9, 13, 12),
      ),
    };

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

  /// The sales the figures drill into: the list, for the filter.
  Future<List<int>> listed(ReportFilter filter) async => [
    for (final order in await history.search(filter.historyQuery(limit: 1000)))
      order.id,
  ];

  test('the taxes, as the tables above say', () async {
    final taxes = await reports.taxes(range);

    expect(
      [
        for (final r in taxes.rates)
          (r.name, r.rateBp, r.orders, r.base, r.charged, r.refunded, r.net),
      ],
      [
        ('VAT', 1400, 3, const Money(35000), const Money(4900),
            const Money(2349), const Money(2551)),
        ('Reduced', 500, 1, const Money(3000), const Money(150),
            const Money(51), const Money(99)),
        ('Zero-rated', 0, 1, const Money(1400), Money.zero, Money.zero,
            Money.zero),
      ],
      reason: 'highest rate first; R2 is in, though its sale was the 9th',
    );
    expect(taxes.unattributedRefunds, const Money(300), reason: 'R5');
    expect(taxes.charged, const Money(5050));
    expect(taxes.refunded, const Money(2700));
    expect(taxes.net, const Money(2350));
  });

  test('tax charged per rate is the sum of pos_order_taxes for the sales '
      'listed', () async {
    final taxes = await reports.taxes(range);
    final ids = await listed(range);
    expect(ids.toSet(), {
      orders['s1'],
      orders['s2'],
      orders['s3'],
      orders['s4'],
    }, reason: 'no void, no open order, no other branch, nothing outside');

    final rows = await db.query(
      pg.config,
      'SELECT rate_bp, name_snapshot, count(*), sum(base_minor)::bigint, '
      '       sum(amount_minor)::bigint '
      '  FROM pos_order_taxes WHERE order_id = ANY(@ids::bigint[]) '
      ' GROUP BY rate_bp, name_snapshot',
      parameters: {'ids': ids},
    );
    expect(
      {
        for (final r in taxes.rates)
          if (r.orders > 0) (r.rateBp, r.name): (r.orders, r.base, r.charged),
      },
      {
        for (final row in rows)
          (row[0]! as int, row[1]! as String): (
            row[2]! as int,
            Money(row[3]! as int),
            Money(row[4]! as int),
          ),
      },
    );
  });

  test('tax refunded per rate is each refund issued in the range, split as '
      'its credit note splits it', () async {
    final taxes = await reports.taxes(range);

    final byRate = <(int, String), int>{};
    var unattributed = 0;
    var issuedVat = 0;
    for (final name in ['R1', 'R2', 'R4', 'R5', 'R6']) {
      final head = (await db.query(
        pg.config,
        'SELECT f.vat_minor, o.vat_minor, f.order_id FROM pos_refunds f '
        'JOIN pos_orders o ON o.id = f.order_id WHERE f.id = @id',
        parameters: {'id': refunds[name]},
      )).first;
      final vat = head[0]! as int;
      issuedVat += vat;
      final rates = await db.query(
        pg.config,
        'SELECT rate_bp, name_snapshot, amount_minor FROM pos_order_taxes '
        'WHERE order_id = @o ORDER BY id',
        parameters: {'o': head[2]},
      );
      if (rates.isEmpty) {
        unattributed += vat;
        continue;
      }
      final shares = TaxEngine.refundShares(
        saleAmounts: [for (final r in rates) r[2]! as int],
        saleVat: head[1]! as int,
        refundVat: vat,
      );
      for (final (i, r) in rates.indexed) {
        final key = (r[0]! as int, r[1]! as String);
        byRate[key] = (byRate[key] ?? 0) + shares[i];
      }
    }

    expect(
      {for (final r in taxes.rates) (r.rateBp, r.name): r.refunded.minor},
      byRate,
    );
    expect(taxes.unattributedRefunds, Money(unattributed));
    expect(
      taxes.refunded,
      Money(issuedVat),
      reason: 'to the piastre: the split loses nothing and invents nothing',
    );
  });

  test('a refund belongs to the day it was given, not its sale\'s', () async {
    final thirteenth = await reports.taxes(
      ReportFilter.day(DateTime(2026, 9, 13)),
    );
    expect(
      [for (final r in thirteenth.rates) (r.name, r.charged, r.refunded)],
      [('VAT', const Money(1400), const Money(50))],
      reason: "the 13th's sale, and R3 — whose sale was the 11th",
    );
  });

  test('filters narrow the taxes as they narrow the sales', () async {
    final atTwo = await reports.taxes(
      ReportFilter(from: range.from, to: range.to, terminalId: pos02),
    );
    expect(
      [for (final r in atTwo.rates) (r.name, r.charged, r.refunded)],
      [
        ('VAT', const Money(2800), const Money(949)),
        ('Reduced', const Money(150), const Money(51)),
      ],
      reason: 's2 was rung up here, and R1 given back here',
    );
    expect(atTwo.unattributedRefunds, const Money(300), reason: 'R5, here');
  });

  test('every payment of the sales listed, one row each, and by method '
      'they are the report\'s', () async {
    final ledger = await reports.payments(range);
    final report = await reports.sales(range);
    final ids = await listed(range);

    expect(ledger.truncated, isFalse);
    final count = await scalar(
      'SELECT count(*)::int FROM pos_order_payments '
      'WHERE order_id = ANY(@ids::bigint[])',
      {'ids': ids},
    );
    expect(ledger.entries, hasLength(count));
    expect(ledger.entries.map((e) => e.orderId).toSet(), ids.toSet());

    final byMethod = <int, (int, Money)>{};
    for (final e in ledger.entries) {
      final (n, amount) = byMethod[e.tenderTypeId!] ?? (0, Money.zero);
      byMethod[e.tenderTypeId!] = (n + 1, amount + e.amount);
    }
    expect(byMethod, {
      for (final m in report.paymentsByMethod)
        m.tenderTypeId!: (m.count, m.amount),
    });
    expect(ledger.total, report.collected + report.onAccount);

    // Newest first, by when the money was taken.
    for (var i = 1; i < ledger.entries.length; i++) {
      expect(
        ledger.entries[i].occurredAt.isAfter(ledger.entries[i - 1].occurredAt),
        isFalse,
      );
    }
    final account = ledger.entries.firstWhere(
      (e) => e.orderId == orders['s3'],
    );
    expect(account.bucket, PaymentBucket.onAccount);
    expect(
      ledger.entries.where((e) => e.orderId == orders['s2']).map(
        (e) => (e.terminalName, e.label),
      ),
      unorderedEquals([('POS-02', 'card'), ('POS-02', 'wallet')]),
    );
  });

  test('the ledger says when it was cut short', () async {
    final cut = await reports.payments(range, limit: 2);
    expect(cut.truncated, isTrue);
    expect(cut.entries.map((e) => e.orderId), [orders['s3'], orders['s4']]);

    final whole = await reports.payments(range, limit: 5);
    expect(whole.truncated, isFalse, reason: 'exactly five payments');
    expect(whole.entries, hasLength(5));
  });

  test("the till's own credential can read the taxes and the ledger", () async {
    // Every suite here runs as a role that needs no grant; this one does not.
    final role = PgFixture.roleFor('finance_probe');
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
          allowInsecureLan: true,
          databaseName: pg.config.databaseName,
          databaseUser: role,
          databasePort: pg.config.databasePort,
        ),
        restaurantId: restaurantId,
        branchId: branchId,
      );

      expect((await asTill.taxes(range)).net, const Money(2350));
      expect((await asTill.payments(range)).entries, hasLength(5));
    } finally {
      await probe.close();
      await dropRole();
    }
  });
}
