@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/security/pin_hash.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_orders_repository.dart';
import 'package:shared_module/data/postgres/postgres_shift_repository.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/authorization.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// People › Shifts and Finance › Settlements, against the rows they read.
///
/// Three claims, each held to `pos_shifts` itself rather than to the
/// repository's own arithmetic: the list is exactly the rows the filter names;
/// over/short is the count less what the Z report expected; and the
/// Settlements strip is its rows summed. Run on the till's credential, so a
/// table the query names without a grant fails here and not in a business.
void main() {
  if (PgFixture.host == null) {
    test('shift history (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int branchId;
  late String counter1;
  late String counter2;
  late PosStaff sara;
  late PosStaff omar;

  // Today, by the calendar: no business day is opened here, so every shift is
  // filed by its local date — the rule the sales list uses for a row no day
  // covers.
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  final to = DateTime(now.year, now.month, now.day + 1);

  Future<String> terminal(String name, int branch) async {
    final row = await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      'VALUES (gen_random_uuid(), @r, @b, @n) RETURNING id::text',
      parameters: {'r': businessId, 'b': branch, 'n': name},
    );
    return row.first[0]! as String;
  }

  setUp(() async {
    pg = await PgFixture.open('shift_history');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) "
      "VALUES ('shift-history', 'Shift History') RETURNING id",
    )).first[0]! as int;
    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'SHH', 'Shifts') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;
    counter1 = await terminal('Counter 1', branchId);
    counter2 = await terminal('Counter 2', branchId);

    Future<PosStaff> staff(String name, String username) async {
      final salt = PinHash.newSalt();
      final row = await db.query(
        pg.config,
        'INSERT INTO pos_users (business_id, branch_id, name, username, '
        'pin_salt, pin_hash) VALUES (@r, @b, @n, @u, @s, @h) RETURNING id',
        parameters: {
          'r': businessId,
          'b': branchId,
          'n': name,
          'u': username,
          's': salt,
          'h': await PinHash.hash('1111', salt),
        },
      );
      // Cashiers, through the role: each may close the drawer they opened.
      return PosStaff(
        id: row.first[0]! as int,
        name: name,
        role: const PosRole(
          id: 1,
          code: SystemRoles.cashierCode,
          nameEn: 'Cashier',
          capabilities: SystemRoles.cashier,
        ),
      );
    }

    sara = await staff('Sara M.', 'sara');
    omar = await staff('Omar T.', 'omar');
  });

  tearDown(() => pg.close());

  PostgresShiftRepository on(String terminalId) => PostgresShiftRepository(
    database: db,
    config: pg.config,
    businessId: businessId,
    branchId: branchId,
    terminalId: terminalId,
  );

  /// A sale into [shift] on [terminalId]; returns the order total, VAT in.
  Future<int> sell(
    String terminalId,
    PosShift shift, {
    required int priceMinor,
    int typeId = 1,
    String label = 'Cash',
  }) async {
    var ticket = Ticket(id: const Uuid().v4(), orderType: OrderType.takeaway);
    ticket = TicketEngine.addLine(
      ticket,
      Product(id: 1, categoryId: 1, nameEn: 'Thing', price: Money(priceMinor)),
    ).ticket!;
    ticket = TicketEngine.addTender(
      ticket,
      typeId: typeId,
      label: label,
      countsAsCash: TenderMethod.isCash(typeId),
    ).ticket!;
    await PostgresOrdersRepository(
      database: db,
      config: pg.config,
      context: PosWriteContext(
        businessId: businessId,
        branchId: branchId,
        terminalId: terminalId,
        branchCode: 'SHH',
      ),
    ).submit(ticket);
    return ticket.totals.total.minor;
  }

  Future<void> movement(
    String terminalId,
    PosShift shift,
    String kind,
    int minor,
  ) => db.query(
    pg.config,
    'INSERT INTO pos_cash_movements (business_id, branch_id, terminal_id, '
    '  shift_id, kind, amount_minor, user_id) '
    'VALUES (@r, @b, @t::uuid, @s, @k, @a, @by)',
    parameters: {
      'r': businessId,
      'b': branchId,
      't': terminalId,
      's': shift.id,
      'k': kind,
      'a': minor,
      'by': shift.openedById,
    },
  );

  /// Count [shift] at [delta] from what its Z report expects.
  Future<void> countOut(
    String terminalId,
    PosShift shift,
    PosStaff by, {
    int delta = 0,
    Approval? approval,
  }) async {
    final expected = (await on(terminalId).summarise(shift)).expectedCash;
    await on(terminalId).close(
      shift: shift,
      by: by,
      countedCash: expected + Money(delta),
      approval: approval,
    );
  }

  Approval managerFor(PosShift shift) =>
      (Authorization.approve(
                approver: const PosStaff(
                  id: 99,
                  name: 'Hana M.',
                  role: PosRole(
                    id: 2,
                    code: SystemRoles.managerCode,
                    nameEn: 'Manager',
                    capabilities: SystemRoles.manager,
                  ),
                ),
                capability: PosCapability.shiftClose,
                subject: '${shift.id}',
              )
              as Allowed)
          .approval!;

  Future<void> backdate(PosShift shift) => db.query(
    pg.config,
    "UPDATE pos_shifts SET opened_at = opened_at - interval '40 days', "
    "  closed_at = closed_at - interval '40 days' WHERE id = @id",
    parameters: {'id': shift.id},
  );

  /// Five shifts here and one at another branch:
  ///
  /// * **e** — Counter 2, Omar, counted 40 days ago: out of the dates.
  /// * **a** — Counter 1, Sara, a cash sale, balanced.
  /// * **b** — Counter 2, Omar, 5.00 short.
  /// * **c** — Counter 1, Sara's drawer counted by Omar on Hana's approval,
  ///   2.50 over: force-closed.
  /// * **d** — Counter 1, Sara, opened 40 days ago and still open: listed.
  Future<({PosShift a, PosShift b, PosShift c, PosShift d, PosShift e})>
  scene() async {
    final e = await on(counter2).open(by: omar, openingFloat: Money.zero);
    await countOut(counter2, e, omar);
    await backdate(e);

    final a = await on(counter1).open(by: sara, openingFloat: Money(20000));
    await sell(counter1, a, priceMinor: 10000);
    await countOut(counter1, a, sara);

    final b = await on(counter2).open(by: omar, openingFloat: Money(10000));
    await countOut(counter2, b, omar, delta: -500);

    final c = await on(counter1).open(by: sara, openingFloat: Money(5000));
    await countOut(counter1, c, omar, delta: 250, approval: managerFor(c));
    // The close's ledger row, as `CloseShiftDialog` writes it.
    await db.query(
      pg.config,
      'INSERT INTO pos_audit_events (business_id, branch_id, actor_user_id, '
      '  actor_name, approved_by_id, approved_by_name, action, entity_type, '
      '  entity_id) '
      "VALUES (@r, @b, @by, 'Omar T.', 99, 'Hana M.', 'shift.closed', "
      "  'shift', @id)",
      parameters: {
        'r': businessId,
        'b': branchId,
        'by': omar.id,
        'id': '${c.id}',
      },
    );

    final d = await on(counter1).open(by: sara, openingFloat: Money.zero);
    await backdate(d);

    // Another branch, opened today: a query that forgot the branch lists it.
    final elsewhere = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'OTH', 'Other') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;
    await db.query(
      pg.config,
      'INSERT INTO pos_shifts (business_id, branch_id, terminal_id, opened_by) '
      'VALUES (@r, @b, @t::uuid, @s)',
      parameters: {
        'r': businessId,
        'b': elsewhere,
        't': await terminal('Other 1', elsewhere),
        's': sara.id,
      },
    );
    return (a: a, b: b, c: c, d: d, e: e);
  }

  /// `pos_shifts`, asked directly: the branch, open or opened in the dates,
  /// [extra] on top, in the list's order.
  Future<List<int>> rowsWhere(
    String extra, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final rows = await db.query(
      pg.config,
      'SELECT id FROM pos_shifts '
      'WHERE business_id = @r AND branch_id = @b '
      '  AND (closed_at IS NULL OR (opened_at >= @from AND opened_at < @to)) '
      '  $extra '
      'ORDER BY (closed_at IS NULL) DESC, opened_at DESC, id DESC',
      parameters: {
        'r': businessId,
        'b': branchId,
        'from': from.toUtc(),
        'to': to.toUtc(),
        ...parameters,
      },
    );
    return [for (final row in rows) row[0]! as int];
  }

  Future<List<int>> listed(ShiftHistoryQuery query) async => [
    for (final record in (await on(counter2).history(query)).shifts)
      record.shift.id,
  ];

  test('every filter lists exactly the pos_shifts rows it names', () async {
    final s = await scene();
    ShiftHistoryQuery q({
      String? terminalId,
      int? staffId,
      Set<ShiftStatus> statuses = const {},
    }) => ShiftHistoryQuery(
      from: from,
      to: to,
      terminalId: terminalId,
      staffId: staffId,
      statuses: statuses,
    );

    final cases =
        <(String, ShiftHistoryQuery, String, Map<String, Object?>, List<int>)>[
          ('no filter', q(), '', {}, [s.d.id, s.c.id, s.b.id, s.a.id]),
          (
            'Counter 1',
            q(terminalId: counter1),
            'AND terminal_id::text = @t',
            {'t': counter1},
            [s.d.id, s.c.id, s.a.id],
          ),
          (
            'Counter 2',
            q(terminalId: counter2),
            'AND terminal_id::text = @t',
            {'t': counter2},
            [s.b.id],
          ),
          (
            "Sara's drawers, whoever counted them",
            q(staffId: sara.id),
            'AND opened_by = @s',
            {'s': sara.id},
            [s.d.id, s.c.id, s.a.id],
          ),
          (
            "Omar's",
            q(staffId: omar.id),
            'AND opened_by = @s',
            {'s': omar.id},
            [s.b.id],
          ),
          (
            'open',
            q(statuses: {ShiftStatus.open}),
            'AND closed_at IS NULL',
            {},
            [s.d.id],
          ),
          (
            'closed by the opener',
            q(statuses: {ShiftStatus.closed}),
            'AND closed_at IS NOT NULL AND closed_by = opened_by',
            {},
            [s.b.id, s.a.id],
          ),
          (
            'force-closed',
            q(statuses: {ShiftStatus.forceClosed}),
            'AND closed_at IS NOT NULL AND closed_by <> opened_by',
            {},
            [s.c.id],
          ),
          (
            'every cash-up',
            q(statuses: {ShiftStatus.closed, ShiftStatus.forceClosed}),
            'AND closed_at IS NOT NULL',
            {},
            [s.c.id, s.b.id, s.a.id],
          ),
          (
            'Counter 1 and force-closed',
            q(terminalId: counter1, statuses: {ShiftStatus.forceClosed}),
            'AND terminal_id::text = @t AND closed_by <> opened_by',
            {'t': counter1},
            [s.c.id],
          ),
        ];

    for (final (name, query, extra, parameters, ids) in cases) {
      final rows = await rowsWhere(extra, parameters);
      expect(await listed(query), rows, reason: name);
      // And the rows are the ones the scene meant — so a filter that matched
      // the raw SQL by being wrong the same way would still fail.
      expect(rows, ids, reason: name);
    }

    // The choices the filters offer are the dates', whatever is chosen.
    final history = await on(counter1).history(
      q(terminalId: counter2, statuses: {ShiftStatus.open}),
    );
    expect(history.shifts, isEmpty);
    expect(history.tills.toSet(), {
      (counter1, 'Counter 1'),
      (counter2, 'Counter 2'),
    });
    expect(history.staff.toSet(), {(sara.id, 'Sara M.'), (omar.id, 'Omar T.')});
    expect(history.cut, isFalse);
  });

  test('over/short is the count less what the Z report expected', () async {
    final shift = await on(counter1).open(by: sara, openingFloat: Money(20000));
    final cash = await sell(counter1, shift, priceMinor: 10000);
    await sell(counter1, shift, priceMinor: 30000, typeId: 2, label: 'Card');
    await movement(counter1, shift, 'pay_in', 3000);
    await movement(counter1, shift, 'pay_out', 1200);

    // Open: the live figure, by the Z report's rule, and no difference yet.
    final z = await on(counter1).summarise(shift);
    expect(z.expectedCash.minor, 20000 + cash + 3000 - 1200);
    final open = (await on(counter2).history(
      ShiftHistoryQuery(from: from, to: to),
    )).shifts.single;
    expect(open.status, ShiftStatus.open);
    expect(open.expectedCash, z.expectedCash);
    expect(open.overShort, isNull);

    await countOut(counter1, shift, sara, delta: -700);
    final record = (await on(counter2).history(
      ShiftHistoryQuery(from: from, to: to),
    )).shifts.single;
    final stored = (await db.query(
      pg.config,
      'SELECT counted_cash_minor, expected_cash_minor, variance_minor '
      'FROM pos_shifts WHERE id = @id',
      parameters: {'id': shift.id},
    )).first;

    expect(record.expectedCash, z.expectedCash);
    expect(record.expectedCash.minor, stored[1]);
    expect(record.countedCash!.minor, stored[0]);
    expect(record.overShort!.minor, -700);
    expect(record.overShort, record.countedCash! - z.expectedCash);
    expect(record.overShort!.minor, stored[2]);
    // The columns beside it are the same report's.
    expect(record.shift.openingFloat, z.shift.openingFloat);
    expect(record.summary.cashTaken, z.cashTaken);
    expect(record.summary.cashIn.minor, 3000);
    expect(record.summary.cashOut.minor, 1200);
    expect(record.closedByName, 'Sara M.');
    expect(record.status, ShiftStatus.closed);
  });

  test('the Settlements strip is its rows summed, and pos_shifts agrees',
      () async {
    await scene();
    final rows = (await on(counter1).history(
      ShiftHistoryQuery(
        from: from,
        to: to,
        statuses: {ShiftStatus.closed, ShiftStatus.forceClosed},
      ),
    )).shifts;
    final totals = CashUpTotals.of(rows);

    final raw = (await db.query(
      pg.config,
      'SELECT count(*), '
      '  coalesce(sum(variance_minor) FILTER (WHERE variance_minor > 0), 0)::bigint, '
      '  coalesce(sum(variance_minor) FILTER (WHERE variance_minor < 0), 0)::bigint, '
      '  coalesce(sum(variance_minor), 0)::bigint '
      'FROM pos_shifts '
      'WHERE business_id = @r AND branch_id = @b AND closed_at IS NOT NULL '
      '  AND opened_at >= @from AND opened_at < @to',
      parameters: {
        'r': businessId,
        'b': branchId,
        'from': from.toUtc(),
        'to': to.toUtc(),
      },
    )).first;

    expect(totals.count, rows.length);
    expect(totals.count, raw[0]);
    expect(totals.over.minor, raw[1]);
    expect(totals.short.minor, raw[2]);
    expect(totals.net.minor, raw[3]);
    // What the scene put there: 0, −5.00 and +2.50.
    expect(totals.count, 3);
    expect(totals.over.minor, 250);
    expect(totals.short.minor, -500);
    expect(totals.net.minor, -250);
    expect(
      totals.net,
      rows.fold(Money.zero, (sum, r) => sum + r.overShort!),
    );
  });

  test('a force-closed shift names who counted and who approved', () async {
    final s = await scene();
    final rows = {
      for (final r in (await on(counter1).history(
        ShiftHistoryQuery(from: from, to: to),
      )).shifts)
        r.shift.id: r,
    };

    expect(rows[s.c.id]!.status, ShiftStatus.forceClosed);
    expect(rows[s.c.id]!.shift.openedByName, 'Sara M.');
    expect(rows[s.c.id]!.closedByName, 'Omar T.');
    expect(rows[s.c.id]!.approvedByName, 'Hana M.');
    expect(rows[s.c.id]!.terminalName, 'Counter 1');
    expect(rows[s.a.id]!.approvedByName, isNull, reason: 'nobody approved it');
    expect(rows[s.a.id]!.status, ShiftStatus.closed);
  });
}
