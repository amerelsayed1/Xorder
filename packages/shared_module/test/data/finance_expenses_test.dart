@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/security/pin_hash.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_cash_movements_repository.dart';
import 'package:shared_module/data/postgres/postgres_orders_repository.dart'
    show PosWriteContext;
import 'package:shared_module/data/postgres/postgres_shift_repository.dart';
import 'package:shared_module/data/postgres/postgres_supplier_invoices_repository.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/finance_report.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/sales_report.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/supplier_invoice.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Finance's expenses, bills due and drawers against PostgreSQL (plan 19
/// BO-10). Local times throughout, so the dates hold in any zone.
///
/// The range is business dates 10–11 September. The 10th has a closed day,
/// 08:00 to 01:30 the next morning; the 11th has none.
///
/// | pay-out | till | at | filed | counted |
/// |---|---|---|---|---|
/// | P1 1,500 | POS-01 | 10th 13:00, stamped with the day | 10th | yes |
/// | P2 2,000 | POS-01 | 11th 00:30, unstamped | 10th, by the window | yes |
/// | P3 700 | POS-02 | 11th 12:00 | 11th, by the calendar | yes |
/// | P4 900 / P5 400 | POS-01 | 12th / 9th | outside | no |
/// | P6 pay-in 5,000, P7 drawer open | POS-01 | 10th | not a pay-out | no |
/// | P8 3,000 | Tanta | 10th | another branch | no |
/// | M3 3,000 | POS-01 | 10th 16:00 | S3's own | as S3 |
/// | M5 1,200 | POS-02 | 11th 10:00 | S5's own, S5 voided | no |
///
/// | payment | paid | how | counted |
/// |---|---|---|---|
/// | S1 10,000 on I1 | 10th | transfer | yes |
/// | S2 2,500 on account | 11th | transfer | yes |
/// | S3 3,000 on I2 | 10th | out of POS-01's drawer (M3) | yes, once |
/// | S4 1,000 on I10 | 10th | transfer, then voided | no |
/// | S5 1,200 on I5 | 11th | out of POS-02's drawer (M5), then voided | no |
/// | S6 5,000 / S7 800 | 12th / 9th | transfer | outside |
///
/// Expenses: pay-outs 1,500 + 2,000 + 700 = 4,200, supplier payments
/// 10,000 + 2,500 + 3,000 = 15,500 — 19,700.
void main() {
  if (PgFixture.host == null) {
    test(
      'finance expenses, bills and drawers (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  const pos01 = '40000000-0000-4000-8000-000000000001';
  const pos02 = '40000000-0000-4000-8000-000000000002';
  const pos03 = '40000000-0000-4000-8000-000000000003';
  const tanta = '40000000-0000-4000-8000-000000000009';

  final range = ReportFilter(
    from: DateTime(2026, 9, 10),
    to: DateTime(2026, 9, 12),
  );
  final businessDate = DateTime(2026, 9, 14);

  // Everything the suite's writes ask for, through the role — as a real
  // manager holds it. `PosStaff.capabilities` is direct grants only.
  const managerRole = PosRole(
    id: 3,
    code: 'manager',
    nameEn: 'Manager',
    capabilities: {
      PosCapability.purchaseManage,
      PosCapability.cashMovement,
      PosCapability.shiftClose,
      PosCapability.reportsView,
    },
  );

  // Roles are cluster-wide; one per checkout, as `till_grants_enforced_test`
  // names its probe.
  final tillRole = PgFixture.roleFor('finance_till');
  final officeRole = PgFixture.roleFor('finance_office');
  const rolePassword = 'probe-only';

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int supplierId;
  late int day10;
  late PosStaff manager;
  late Map<String, int> tender;
  late PostgresSupplierInvoicesRepository ledger;
  late PostgresCashMovementsRepository drawers;
  late Map<String, PostgresShiftRepository> tills;
  late Map<String, PosShift> shifts;
  late Map<String, int> moves;
  late Map<String, SupplierInvoice> bills;
  late Map<String, SupplierPayment> paid;
  var invoice = 0;

  Future<int> scalar(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0]! as int;

  Future<void> dropRole(String role) async {
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

  setUpAll(() async {
    pg = await PgFixture.open('finance_expenses');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);

    // The till's grant list and nothing else; and the back office's, which is
    // given both lists as `pos_migrate --grant-admin-to` gives them.
    for (final role in [tillRole, officeRole]) {
      await dropRole(role);
      await db.query(
        pg.config,
        'CREATE ROLE "$role" LOGIN PASSWORD \'$rolePassword\'',
      );
      for (final statement in LocalBootstrap.tillGrants(
        database: pg.config.databaseName,
        role: role,
      )) {
        await db.query(pg.config, statement);
      }
    }
    for (final statement in LocalBootstrap.administrativeGrants(
      role: officeRole,
    )) {
      await db.query(pg.config, statement);
    }
  });

  tearDownAll(() async {
    await dropRole(tillRole);
    await dropRole(officeRole);
    await pg.close();
  });

  PostgresShiftRepository till(String terminal, {int? branch}) =>
      PostgresShiftRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: branch ?? branchId,
        terminalId: terminal,
      );

  /// A movement as the drawer writes it, at a time of the test's choosing —
  /// `record` stamps `now()`, and this suite is about dates.
  Future<int> movement(
    String terminal,
    String kind,
    int amount,
    DateTime at, {
    int? day,
    String? reason = 'petty_expense',
  }) => scalar(
    'INSERT INTO pos_cash_movements (business_id, branch_id, terminal_id, '
    '  shift_id, business_day_id, kind, amount_minor, reason_id, user_id, '
    '  occurred_at) '
    'SELECT @r, t.branch_id, t.id, @s, @d, @k, @a, '
    '  (SELECT id FROM pos_reason_codes WHERE business_id = @r '
    '     AND scope = @scope AND code = @code ORDER BY id LIMIT 1), '
    '  @staff, @at::timestamptz '
    'FROM pos_terminals t WHERE t.id = @t::uuid RETURNING id',
    {
      'r': businessId,
      't': terminal,
      's': shifts[terminal]!.id,
      'd': day,
      'k': kind,
      'a': amount,
      'scope': kind == 'pay_in' ? 'pay_in' : 'pay_out',
      'code': reason,
      'staff': manager.id,
      'at': at,
    },
  );

  Future<int> sale(
    String terminal, {
    required int total,
    List<(String, int)> payments = const [],
    String status = 'PAID',
  }) async {
    invoice++;
    final id = await scalar(
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, shift_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, served_by, voided_at, voided_by) '
      'SELECT gen_random_uuid(), @r, t.branch_id, t.id, @s, @inv, '
      "  'dine_in', 'EGP', 2, @total, 0, 0, 0, @total, now(), @status, @by, "
      "  CASE WHEN @status::text = 'VOIDED' THEN now() END, "
      "  CASE WHEN @status::text = 'VOIDED' THEN @by::bigint END "
      'FROM pos_terminals t WHERE t.id = @t::uuid RETURNING id',
      {
        'r': businessId,
        't': terminal,
        's': shifts[terminal]!.id,
        'inv': 'FE-$invoice',
        'total': total,
        'status': status,
        'by': manager.id,
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

  Future<SupplierInvoice> enter(
    String number,
    int total, {
    required DateTime due,
    DateTime? issued,
  }) async {
    final result = await ledger.save(
      SupplierInvoice(
        id: 0,
        supplierId: supplierId,
        number: number,
        total: Money(total),
        issuedAt: issued ?? DateTime(2026, 9, 1),
        dueAt: due,
      ),
      by: manager,
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  /// A payment; [drawer] pays it out of that till's open shift, and the
  /// movement is then moved to [at] — the office writes it at `now()`, and a
  /// suite about dates needs it on the date the payment says.
  Future<SupplierPayment> settle(
    int amount,
    DateTime at, {
    SupplierInvoice? against,
    String? drawer,
  }) async {
    final result = await ledger.pay(
      SupplierPayment(
        id: 0,
        supplierId: supplierId,
        invoiceId: against?.id,
        amount: Money(amount),
        method: drawer == null
            ? SupplierPaymentMethod.bankTransfer
            : SupplierPaymentMethod.cash,
        reference: drawer == null ? 'TRF-$amount' : null,
        paidAt: at,
      ),
      by: manager,
      fromShiftId: drawer == null ? null : shifts[drawer]!.id,
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    final payment = result.value!;
    if (payment.cashMovementId case final moved?) {
      await db.query(
        pg.config,
        'UPDATE pos_cash_movements SET occurred_at = @at::timestamptz '
        'WHERE id = @id',
        parameters: {'at': at, 'id': moved},
      );
    }
    return payment;
  }

  Future<int> reason(String scope, String code) => scalar(
    'SELECT id FROM pos_reason_codes WHERE business_id = @r '
    'AND scope = @scope AND code = @code',
    {'r': businessId, 'scope': scope, 'code': code},
  );

  setUp(() async {
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    invoice = 0;

    businessId = await scalar(
      "INSERT INTO pos_businesses (slug, name) VALUES ('fe', 'Finance') "
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
    // `supplier` for a drawer payment, `correction` to put it back, and the
    // pay-out reasons the till offers — as a real install seeds them.
    await LocalBootstrap(db).seedReasonCodes(pg.config, businessId);

    final salt = PinHash.newSalt();
    manager = PosStaff(
      id: await scalar(
        'INSERT INTO pos_users (business_id, branch_id, name, username, '
        '  pin_salt, pin_hash) VALUES (@r, @b, @n, @u, @s, @h) RETURNING id',
        {
          'r': businessId,
          'b': branchId,
          'n': 'Hoda K.',
          'u': 'hoda',
          's': salt,
          'h': await PinHash.hash('1111', salt),
        },
      ),
      name: 'Hoda K.',
      role: managerRole,
    );

    for (final (id, name, branch) in [
      (pos01, 'POS-01', branchId),
      (pos02, 'POS-02', branchId),
      (pos03, 'POS-03', branchId),
      (tanta, 'TANTA-01', otherBranchId),
    ]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
        'VALUES (@id::uuid, @r, @b, @name)',
        parameters: {'id': id, 'r': businessId, 'b': branch, 'name': name},
      );
    }

    tender = {};
    for (final (code, cash) in [('cash', true), ('card', false)]) {
      tender[code] = await scalar(
        'INSERT INTO pos_tender_types (business_id, code, name_en, kind, '
        '  counts_as_cash) VALUES (@r, @code, @code, @code, @cash) RETURNING id',
        {'r': businessId, 'code': code, 'cash': cash},
      );
    }

    day10 = await scalar(
      'INSERT INTO pos_business_days (business_id, branch_id, business_date, '
      '  opened_at, closed_at, closed_by) '
      "VALUES (@r, @b, '2026-09-10'::date, @o::timestamptz, @c::timestamptz, "
      '  @by) RETURNING id',
      {
        'r': businessId,
        'b': branchId,
        'o': DateTime(2026, 9, 10, 8),
        'c': DateTime(2026, 9, 11, 1, 30),
        'by': manager.id,
      },
    );

    supplierId = await scalar(
      'INSERT INTO pos_suppliers (business_id, name_en, payment_term_days) '
      "VALUES (@r, 'Nile Dairy', 30) RETURNING id",
      {'r': businessId},
    );

    ledger = PostgresSupplierInvoicesRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      businessId: businessId,
      branchId: branchId,
    );
    drawers = PostgresCashMovementsRepository(
      database: db,
      config: pg.config,
      context: PosWriteContext(
        businessId: businessId,
        branchId: branchId,
        terminalId: pos01,
        branchCode: 'MANS',
      ),
    );

    // ── Drawers: two open here, one counted, one at another branch ────────
    tills = {
      pos01: till(pos01),
      pos02: till(pos02),
      pos03: till(pos03),
      tanta: till(tanta, branch: otherBranchId),
    };
    shifts = {};
    for (final (terminal, float) in [
      (pos01, 20000),
      (pos02, 10000),
      (pos03, 5000),
      (tanta, 7000),
    ]) {
      shifts[terminal] = await tills[terminal]!.open(
        by: manager,
        openingFloat: Money(float),
      );
    }
    await sale(pos03, total: 1000, payments: [('cash', 1000)]);
    await tills[pos03]!.close(
      shift: shifts[pos03]!,
      by: manager,
      countedCash: const Money(6000),
    );

    await sale(pos01, total: 11400, payments: [('cash', 11400)]);
    await sale(pos01, total: 5000, payments: [('card', 5000)]);
    await sale(pos01, total: 3000, status: 'VOIDED');
    await sale(pos02, total: 3500, payments: [('cash', 3500)]);
    await sale(tanta, total: 9900, payments: [('cash', 9900)]);

    moves = {
      'P1': await movement(
        pos01,
        'pay_out',
        1500,
        DateTime(2026, 9, 10, 13),
        day: day10,
      ),
      'P2': await movement(pos01, 'pay_out', 2000, DateTime(2026, 9, 11, 0, 30)),
      'P3': await movement(pos02, 'pay_out', 700, DateTime(2026, 9, 11, 12)),
      'P4': await movement(pos01, 'pay_out', 900, DateTime(2026, 9, 12, 10)),
      'P5': await movement(pos01, 'pay_out', 400, DateTime(2026, 9, 9, 18)),
      'P6': await movement(
        pos01,
        'pay_in',
        5000,
        DateTime(2026, 9, 10, 14),
        day: day10,
        reason: 'correction',
      ),
      'P7': await movement(
        pos01,
        'drawer_open',
        0,
        DateTime(2026, 9, 10, 15),
        day: day10,
        reason: null,
      ),
      'P8': await movement(tanta, 'pay_out', 3000, DateTime(2026, 9, 10, 13)),
    };

    // ── The ledger ────────────────────────────────────────────────────────
    bills = {
      for (final (number, total, due, issued) in [
        ('I1', 10000, DateTime(2026, 9, 10), null),
        ('I2', 8000, DateTime(2026, 9, 13, 23, 30), null),
        ('I3', 4000, DateTime(2026, 9, 14), null),
        ('I4', 6000, DateTime(2026, 9, 14, 23, 59), null),
        ('I5', 2000, DateTime(2026, 9, 15, 12), DateTime(2026, 9, 10, 9)),
        ('I6', 3000, DateTime(2026, 9, 21, 23), DateTime(2026, 9, 11, 9)),
        ('I7', 7000, DateTime(2026, 9, 22, 0, 30), null),
        ('I8', 1500, DateTime(2026, 9, 20), DateTime(2026, 9, 10, 10)),
        ('I9', 9000, DateTime(2026, 10, 30), null),
        ('I10', 5000, DateTime(2026, 9, 1, 12), DateTime(2026, 9, 1, 9)),
        ('I11', 5000, DateTime(2026, 9, 7), null),
        ('I12', 800, DateTime(2026, 9, 5), null),
      ])
        number: await enter(number, total, due: due, issued: issued),
    };
    final voided = await ledger.voidInvoice(
      bills['I8']!.id,
      reasonId: await reason('invoice_void', 'entered_twice'),
      by: manager,
    );
    expect(voided.succeeded, isTrue, reason: '${voided.refusal}');

    paid = {
      'S1': await settle(10000, DateTime(2026, 9, 10, 11), against: bills['I1']),
      'S2': await settle(2500, DateTime(2026, 9, 11, 10)),
      'S3': await settle(
        3000,
        DateTime(2026, 9, 10, 16),
        against: bills['I2'],
        drawer: pos01,
      ),
      'S4': await settle(1000, DateTime(2026, 9, 10, 12), against: bills['I10']),
      'S5': await settle(
        1200,
        DateTime(2026, 9, 11, 10),
        against: bills['I5'],
        drawer: pos02,
      ),
      'S6': await settle(5000, DateTime(2026, 9, 12, 9), against: bills['I11']),
      'S7': await settle(800, DateTime(2026, 9, 9, 9), against: bills['I12']),
    };
    final wrongInvoice = await reason('payment_void', 'wrong_invoice');
    for (final name in ['S4', 'S5']) {
      // S5 came out of an open drawer, so the void puts the cash back with a
      // pay-in on that shift — which the drawer counts and no expense does.
      final undone = await ledger.voidPayment(
        paid[name]!.id,
        reasonId: wrongInvoice,
        by: manager,
      );
      expect(undone.succeeded, isTrue, reason: '${undone.refusal}');
    }
  });

  int moved(String payment) => paid[payment]!.cashMovementId!;

  test('the range read files pay-outs by business date, at this branch, '
      'newest first', () async {
    final read = await drawers.between(range);

    expect(
      {for (final m in read) m.id},
      {moves['P1'], moves['P2'], moves['P3'], moved('S3'), moved('S5')},
    );
    expect({for (final m in read) m.kind}, {CashMovementKind.payOut});
    for (var i = 1; i < read.length; i++) {
      expect(read[i].occurredAt.isAfter(read[i - 1].occurredAt), isFalse);
    }
    final p3 = read.singleWhere((m) => m.id == moves['P3']);
    expect(p3.terminalName, 'POS-02');
    expect(p3.amount, const Money(700));
    expect(
      read.singleWhere((m) => m.id == moves['P1']).reasonName,
      'Petty expense',
    );

    // Other kinds on request, and one till on request.
    expect(
      {
        for (final m in await drawers.between(
          range,
          kinds: {CashMovementKind.payIn},
        ))
          m.id,
      },
      {moves['P6']},
    );
    expect(
      {
        for (final m in await drawers.between(
          ReportFilter(from: range.from, to: range.to, terminalId: pos02),
        ))
          m.id,
      },
      {moves['P3'], moved('S5')},
    );
  });

  test("the ledger's range: voids kept and marked, and the pay-outs that "
      'are a payment\'s own', () async {
    final spent = await ledger.spending(range);

    expect({for (final i in spent.invoices) i.number}, {'I5', 'I6', 'I8'});
    expect(
      spent.invoices.singleWhere((i) => i.number == 'I8').isVoided,
      isTrue,
    );
    expect({for (final p in spent.payments) p.id}, {
      for (final name in ['S1', 'S2', 'S3', 'S4', 'S5']) paid[name]!.id,
    });
    expect(
      {for (final p in spent.payments.where((p) => p.isVoided)) p.id},
      {paid['S4']!.id, paid['S5']!.id},
    );
    expect(spent.drawerMovementIds, {moved('S3'), moved('S5')});
  });

  test('expenses equal the pay-outs plus the supplier payments not voided — '
      'a supplier paid from a drawer counted once', () async {
    final payOuts = await drawers.between(range);
    final report = ExpenseReport(
      filter: range,
      payOuts: payOuts,
      supplierFigures: SupplierFigures.included,
      suppliers: await ledger.spending(range),
    );

    expect(
      {for (final p in report.drawerPayOuts) p.id},
      {moves['P1'], moves['P2'], moves['P3']},
    );
    expect(
      {for (final p in report.supplierPayments) p.id},
      {paid['S1']!.id, paid['S2']!.id, paid['S3']!.id},
    );
    expect(report.payOutTotal, const Money(4200));
    expect(report.supplierTotal, const Money(15500));
    expect(report.total, const Money(19700));

    // The same sum asked of the tables themselves, round both repositories:
    // every pay-out in the range, less those a payment records as its own,
    // plus the live payments paid in the range.
    final ids = [for (final p in payOuts) p.id];
    final allPayOuts = await scalar(
      'SELECT coalesce(sum(amount_minor), 0)::bigint FROM pos_cash_movements '
      'WHERE id = ANY(@ids::bigint[])',
      {'ids': ids},
    );
    final ownedByPayments = await scalar(
      'SELECT coalesce(sum(m.amount_minor), 0)::bigint '
      'FROM pos_cash_movements m WHERE m.id = ANY(@ids::bigint[]) AND m.id IN '
      '  (SELECT cash_movement_id FROM pos_supplier_payments '
      '    WHERE cash_movement_id IS NOT NULL)',
      {'ids': ids},
    );
    final livePayments = await scalar(
      'SELECT coalesce(sum(amount_minor), 0)::bigint FROM pos_supplier_payments '
      'WHERE business_id = @r AND voided_at IS NULL '
      '  AND paid_at >= @from::timestamptz AND paid_at < @to::timestamptz',
      {'r': businessId, 'from': range.from, 'to': range.to},
    );
    expect(allPayOuts, 8400);
    expect(ownedByPayments, 4200);
    expect(livePayments, 15500);
    expect(report.total.minor, allPayOuts - ownedByPayments + livePayments);

    // Without the ledger — a cloud till, or somebody who may not read it —
    // nothing is taken away: every pay-out is money out of a drawer, counted
    // once, as itself.
    final payOutsOnly = ExpenseReport(
      filter: range,
      payOuts: payOuts,
      supplierFigures: SupplierFigures.notPermitted,
    );
    expect(payOutsOnly.total, const Money(8400));
  });

  test('the bills-due groups partition the unpaid invoices exactly, by due '
      'date against the business date', () async {
    final unpaid = await ledger.unpaid();
    final due = BillsDue.of(unpaid, businessDate: businessDate);

    // Every unpaid invoice in one group, and in one only.
    final grouped = [
      for (final bucket in BillsDueBucket.values)
        for (final bill in due.inBucket(bucket)) bill.id,
    ];
    expect(grouped, hasLength(unpaid.length));
    expect(grouped.toSet(), {for (final bill in unpaid) bill.id});

    // Where each date puts it: the 13th at 23:30 is overdue on the 14th, the
    // 14th at midnight and at 23:59 are both today, the 21st is the seventh
    // day and the 22nd the eighth. Settled (I1, I11, I12) and voided (I8)
    // bills are in no group; on-account money clears no bill (I9).
    expect(
      {
        for (final bucket in BillsDueBucket.values)
          bucket: {for (final bill in due.inBucket(bucket)) bill.number},
      },
      {
        BillsDueBucket.overdue: {'I2', 'I10'},
        BillsDueBucket.dueToday: {'I3', 'I4'},
        BillsDueBucket.nextSevenDays: {'I5', 'I6'},
        BillsDueBucket.later: {'I7', 'I9'},
      },
    );
    expect([for (final b in BillsDueBucket.values) due.amount(b)], const [
      Money(10000),
      Money(10000),
      Money(5000),
      Money(16000),
    ]);

    // The groups add up to the total, and the total is what the tables say
    // is still owed — asked of them directly, not through the repository.
    expect(
      BillsDueBucket.values.fold(Money.zero, (sum, b) => sum + due.amount(b)),
      due.total,
    );
    final owed = await scalar(
      'SELECT coalesce(sum(i.total_minor - live.paid), 0)::bigint '
      'FROM pos_supplier_invoices i '
      'CROSS JOIN LATERAL (SELECT coalesce(sum(p.amount_minor), 0) AS paid '
      '  FROM pos_supplier_payments p '
      '  WHERE p.invoice_id = i.id AND p.voided_at IS NULL) live '
      'WHERE i.business_id = @r AND i.voided_at IS NULL '
      '  AND i.total_minor > live.paid',
      {'r': businessId},
    );
    expect(owed, 41000);
    expect(due.total.minor, owed);
  });

  test("each open drawer is expected to hold what its Z report counts it "
      'against, and what the cash-up stores', () async {
    final open = await tills[pos01]!.openDrawers();

    // POS-03's is counted and Tanta's is another branch's.
    expect([for (final d in open) d.terminalName], ['POS-01', 'POS-02']);
    expect(
      [for (final d in open) d.shift.id],
      [shifts[pos01]!.id, shifts[pos02]!.id],
    );
    // POS-01: 20,000 + 11,400 cash + 5,000 in − (1,500 + 2,000 + 900 + 400 +
    // 3,000 out); the card sale and the void are not in the drawer, and the
    // pay-outs of every date are, because the drawer does not keep dates.
    // POS-02: 10,000 + 3,500 + 1,200 put back − (700 + 1,200).
    expect(
      [for (final d in open) d.expectedCash],
      const [Money(28600), Money(12800)],
    );

    for (final drawer in open) {
      final z = await tills[drawer.terminalId]!.summarise(drawer.shift);
      expect(drawer.expectedCash, z.expectedCash);
      expect(drawer.summary.cashTaken, z.cashTaken);
      expect(drawer.summary.cashIn, z.cashIn);
      expect(drawer.summary.cashOut, z.cashOut);
    }

    for (final drawer in open) {
      final closed = await tills[drawer.terminalId]!.close(
        shift: drawer.shift,
        by: manager,
        countedCash: drawer.expectedCash,
      );
      expect(closed.variance, Money.zero);
      expect(
        await scalar(
          'SELECT expected_cash_minor FROM pos_shifts WHERE id = @id',
          {'id': drawer.shift.id},
        ),
        drawer.expectedCash.minor,
      );
    }
    expect(await tills[pos01]!.openDrawers(), isEmpty);
  });

  group('credentials', () {
    PosDatabase connectAs(String role) {
      final database = PosDatabase(
        credentials: InMemoryPosDbCredentials(rolePassword),
      );
      addTearDown(database.close);
      return database;
    }

    Future<String?> refusalFor(String role, String sql) async {
      final connection = await Connection.open(
        Endpoint(
          host: pg.config.databaseHost,
          port: pg.config.databasePort,
          database: pg.config.databaseName,
          username: role,
          password: rolePassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      try {
        await connection.execute(sql);
        return null;
      } on ServerException catch (error) {
        return error.code;
      } finally {
        await connection.close();
      }
    }

    test("the till's half runs on the till's grants alone", () async {
      final config = pg.config.copyWith(databaseUser: tillRole);
      final database = connectAs(tillRole);

      final asTill = PostgresCashMovementsRepository(
        database: database,
        config: config,
        context: PosWriteContext(
          businessId: businessId,
          branchId: branchId,
          terminalId: pos01,
          branchCode: 'MANS',
        ),
      );
      expect(
        {for (final m in await asTill.between(range)) m.id},
        {moves['P1'], moves['P2'], moves['P3'], moved('S3'), moved('S5')},
      );

      final drawersAsTill = await PostgresShiftRepository(
        database: database,
        config: config,
        businessId: businessId,
        branchId: branchId,
        terminalId: pos01,
      ).openDrawers();
      expect(
        [for (final d in drawersAsTill) d.expectedCash],
        const [Money(28600), Money(12800)],
      );
    });

    test('the supplier ledger is read through the back office credential, '
        'never the till\'s', () async {
      // The till is refused the tables outright…
      for (final table in ['pos_supplier_invoices', 'pos_supplier_payments']) {
        expect(
          await refusalFor(tillRole, 'SELECT 1 FROM $table'),
          '42501',
          reason: '$table — insufficient_privilege',
        );
      }
      // …and so a ledger bound to its connection cannot answer at all.
      final onTheTill = PostgresSupplierInvoicesRepository(
        database: connectAs(tillRole),
        config: pg.config.copyWith(databaseUser: tillRole),
        adminAvailable: true,
        businessId: businessId,
        branchId: branchId,
      );
      await expectLater(onTheTill.spending(range), throwsA(anything));

      // The back office's credential reads both halves.
      final office = PostgresSupplierInvoicesRepository(
        database: connectAs(officeRole),
        config: pg.config.copyWith(databaseUser: officeRole),
        adminAvailable: true,
        businessId: businessId,
        branchId: branchId,
      );
      final spent = await office.spending(range);
      expect(spent.drawerMovementIds, {moved('S3'), moved('S5')});
      expect(
        BillsDue.of(await office.unpaid(), businessDate: businessDate).total,
        const Money(41000),
      );
    });
  });
}
