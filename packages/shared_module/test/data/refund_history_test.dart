@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_order_history_repository.dart';
import 'package:shared_module/domain/models/order_record.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/refund.dart';
import 'package:shared_module/domain/models/refund_history.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/features/history/history_scope.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart';

/// Sales › Returns, Invoices and Cancelled orders, against PostgreSQL.
///
/// **Returns' claim is that its rows and its strip are `pos_refunds`.** So the
/// list is compared with the table read straight, the strip with a sum
/// written here independently of the repository's SQL, and both with each
/// other over every page, under every filter. A cashier's Returns are the
/// refunds against their own sales — including one a colleague gave, and
/// excluding one they gave on a colleague's sale — because the scope is the
/// sales list's.
///
/// The two presets are the sales list's own query with a status locked on,
/// so what is held here is only what the preset adds: the right rows, and
/// Cancelled orders' voided total.
void main() {
  if (PgFixture.host == null) {
    test('refund history (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int nourId;
  late int samiId;
  late int reasonId;
  late PostgresOrderHistoryRepository repository;

  const counter = '11111111-1111-4111-8111-111111111111';
  const upstairs = '22222222-2222-4222-8222-222222222222';
  const elsewhere = '33333333-3333-4333-8333-333333333333';

  Future<int> insertOrder({
    required String invoice,
    required DateTime occurredAt,
    required int total,
    int? branch,
    String status = 'PAID',
    String terminal = counter,
    int? servedBy,
    int? businessDayId,
  }) async {
    final voided = status == 'VOIDED';
    final id =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_orders (client_transaction_id, business_id, '
                  '  branch_id, terminal_id, invoice_number, order_type, '
                  '  currency, exponent, subtotal_minor, discount_minor, '
                  '  service_minor, vat_minor, total_minor, occurred_at, status, '
                  '  served_by, business_day_id, voided_by, voided_at, '
                  '  void_reason_id) '
                  'VALUES (gen_random_uuid(), @r, @b, @terminal::uuid, '
                  "  @invoice, 'takeaway', 'EGP', 2, @total, 0, 0, 0, @total, "
                  '  @at::timestamptz, @status, @served, @day, @voidedBy, '
                  '  @voidedAt::timestamptz, @reason) RETURNING id',
                  parameters: {
                    'r': businessId,
                    'b': branch ?? branchId,
                    'terminal': terminal,
                    'invoice': invoice,
                    'total': total,
                    'at': occurredAt.toUtc(),
                    'status': status,
                    'served': servedBy,
                    'day': businessDayId,
                    'voidedBy': voided ? samiId : null,
                    'voidedAt': voided ? occurredAt.toUtc() : null,
                    'reason': voided ? reasonId : null,
                  },
                ))
                .first[0]
            as int;
    if (!voided) {
      await db.query(
        pg.config,
        'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
        "  amount_minor) VALUES (@o, 1, 'Cash', @amount)",
        parameters: {'o': id, 'amount': total},
      );
    }
    return id;
  }

  Future<int> insertLine(int orderId, {required int unitPrice}) async =>
      (await db.query(
            pg.config,
            'INSERT INTO pos_order_lines (order_id, line_key, name_snapshot, '
            '  quantity, unit_price_minor, line_total_minor, stage) '
            "VALUES (@o, 'L1', 'Koshari', 2, @unit, @total, 'sent') RETURNING id",
            parameters: {'o': orderId, 'unit': unitPrice, 'total': unitPrice * 2},
          ))
          .first[0]
          as int;

  /// A refund, its tender and its lines in one transaction — the tender
  /// check is deferred to commit, and a refund with no tender is refused.
  Future<int> refund(
    int orderId,
    int amount, {
    required DateTime at,
    required int by,
    int? approvedBy,
    int? dayId,
    int? branch,
    String terminal = counter,
    String kind = 'partial',
    bool withReason = false,
    List<int> lines = const [],
  }) => db.runTx(pg.config, (tx) async {
    final id =
        (await tx.execute(
                  Sql.named(
                    'INSERT INTO pos_refunds (client_refund_id, business_id, '
                    '  branch_id, terminal_id, order_id, business_day_id, kind, '
                    '  subtotal_minor, service_minor, vat_minor, total_minor, '
                    '  reason_id, refunded_by, approved_by_id, occurred_at) '
                    'VALUES (gen_random_uuid(), @r, @b, @terminal::uuid, @o, '
                    '  @day, @kind, @amount, 0, 0, @amount, @reason, @by, '
                    '  @approver, @at::timestamptz) RETURNING id',
                  ),
                  parameters: {
                    'r': businessId,
                    'b': branch ?? branchId,
                    'terminal': terminal,
                    'o': orderId,
                    'day': dayId,
                    'kind': kind,
                    'amount': amount,
                    'reason': withReason ? reasonId : null,
                    'by': by,
                    'approver': approvedBy,
                    'at': at.toUtc(),
                  },
                ))
                .first[0]
            as int;
    await tx.execute(
      Sql.named(
        'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
        "  amount_minor) VALUES (@id, 1, 'Cash', @amount)",
      ),
      parameters: {'id': id, 'amount': amount},
    );
    for (final line in lines) {
      await tx.execute(
        Sql.named(
          'INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
          '  unit_price_minor, line_total_minor, name_snapshot) '
          'SELECT @id, l.id, 1, l.unit_price_minor, l.unit_price_minor, '
          '       l.name_snapshot FROM pos_order_lines AS l WHERE l.id = @line',
        ),
        parameters: {'id': id, 'line': line},
      );
    }
    return id;
  });

  Future<int> closedDay(DateTime date, DateTime opened, DateTime closed) async =>
      (await db.query(
            pg.config,
            'INSERT INTO pos_business_days (business_id, branch_id, '
            '  business_date, opened_at, closed_at, closed_by) '
            'VALUES (@r, @b, @date::date, @opened::timestamptz, '
            '  @closed::timestamptz, @by) RETURNING id',
            parameters: {
              'r': businessId,
              'b': branchId,
              'date':
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}',
              'opened': opened.toUtc(),
              'closed': closed.toUtc(),
              'by': samiId,
            },
          ))
          .first[0]
          as int;

  /// Every page of [query], [limit] rows at a time — what Next does.
  Future<List<RefundRecord>> everyPage(
    RefundHistoryQuery query, {
    required int limit,
  }) async {
    final rows = <RefundRecord>[];
    int? after;
    for (var turned = 0; turned < 200; turned++) {
      final page = await repository.refunds(
        query.copyWith(
          afterRefundId: after,
          clearAfter: after == null,
          limit: limit,
        ),
      );
      rows.addAll(page);
      if (page.length < limit) return rows;
      after = page.last.id;
    }
    fail('paging did not come to an end');
  }

  setUp(() async {
    pg = await PgFixture.open('refund_history');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_businesses (slug, name) "
                  "VALUES ('returns', 'Returns') RETURNING id",
                ))
                .first[0]
            as int;
    Future<int> branch(String code) async =>
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_branches (business_id, code, name) '
                  'VALUES (@r, @code, @code) RETURNING id',
                  parameters: {'r': businessId, 'code': code},
                ))
                .first[0]
            as int;
    branchId = await branch('RTN');
    otherBranchId = await branch('RT2');

    Future<void> terminal(String id, String name, int branch) => db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      'VALUES (@id::uuid, @r, @b, @name)',
      parameters: {'id': id, 'r': businessId, 'b': branch, 'name': name},
    );
    await terminal(counter, 'Counter', branchId);
    await terminal(upstairs, 'Upstairs', branchId);
    await terminal(elsewhere, 'Their till', otherBranchId);

    Future<int> staff(String name, String username) async =>
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_users (business_id, branch_id, name, '
                  "  username, pin_salt, pin_hash) VALUES (@r, @b, @n, @u, "
                  "  'salt', 'hash') RETURNING id",
                  parameters: {
                    'r': businessId,
                    'b': branchId,
                    'n': name,
                    'u': username,
                  },
                ))
                .first[0]
            as int;
    nourId = await staff('Nour Adel', 'nour');
    samiId = await staff('Sami Farid', 'sami');

    reasonId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_reason_codes (business_id, scope, code, '
                  "  name_en, name_ar) VALUES (@r, 'void', 'wrong_order', "
                  "  'Wrong order', 'طلب خاطئ') RETURNING id",
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;

    repository = PostgresOrderHistoryRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  /// The refunds, by name, so a test can say which it means.
  late Map<String, int> ids;

  /// Six refunds at this branch and one at another, chosen so each filter
  /// matches some and misses others:
  ///
  /// | refund | sale  | seller | given by | amount | filed under |
  /// |--------|-------|--------|----------|--------|-------------|
  /// | R1     | A-01  | Nour   | Nour     |  50.00 | the 9th     |
  /// | R2     | A-02  | Sami   | Sami     | 200.00 | the 9th, rung at 01:30 on the 10th |
  /// | R3     | B-01  | Nour   | Sami     |  50.00 | the 10th    |
  /// | R4     | A-01  | Nour   | Nour     |  20.00 | the 11th, no day open |
  /// | R5     | C-01  | Sami   | Nour     |  80.00 | the 12th, no day, tied with R6 |
  /// | R6     | B-01  | Nour   | Sami     |  10.00 | the 12th, no day, tied with R5 |
  Future<void> seed() async {
    final dayA = await closedDay(
      DateTime(2026, 9, 9),
      DateTime(2026, 9, 9, 8),
      DateTime(2026, 9, 10, 2),
    );
    final dayB = await closedDay(
      DateTime(2026, 9, 10),
      DateTime(2026, 9, 10, 8),
      DateTime(2026, 9, 11, 2),
    );

    final a01 = await insertOrder(
      invoice: 'A-01',
      occurredAt: DateTime(2026, 9, 9, 12),
      businessDayId: dayA,
      total: 10000,
      servedBy: nourId,
    );
    final a01Line = await insertLine(a01, unitPrice: 5000);
    final a02 = await insertOrder(
      invoice: 'A-02',
      occurredAt: DateTime(2026, 9, 9, 13),
      businessDayId: dayA,
      total: 20000,
      servedBy: samiId,
    );
    final b01 = await insertOrder(
      invoice: 'B-01',
      occurredAt: DateTime(2026, 9, 10, 9),
      businessDayId: dayB,
      total: 30000,
      servedBy: nourId,
    );
    final c01 = await insertOrder(
      invoice: 'C-01',
      occurredAt: DateTime(2026, 9, 12, 9),
      total: 8000,
      servedBy: samiId,
      terminal: upstairs,
    );
    // Two voids for Cancelled orders, and a paid sale nothing refunds.
    await insertOrder(
      invoice: 'A-03',
      occurredAt: DateTime(2026, 9, 9, 14),
      businessDayId: dayA,
      status: 'VOIDED',
      total: 5000,
      servedBy: nourId,
    );
    await insertOrder(
      invoice: 'B-02',
      occurredAt: DateTime(2026, 9, 10, 10),
      businessDayId: dayB,
      status: 'VOIDED',
      total: 7000,
      servedBy: samiId,
    );
    await insertOrder(
      invoice: 'B-03',
      occurredAt: DateTime(2026, 9, 10, 11),
      businessDayId: dayB,
      total: 4000,
      servedBy: samiId,
    );
    final x01 = await insertOrder(
      invoice: 'X-01',
      occurredAt: DateTime(2026, 9, 9, 12),
      branch: otherBranchId,
      terminal: elsewhere,
      total: 999900,
    );

    final tie = DateTime(2026, 9, 12, 12, 0, 0, 0, 321);
    ids = {
      'R1': await refund(
        a01,
        5000,
        at: DateTime(2026, 9, 9, 14),
        by: nourId,
        dayId: dayA,
        withReason: true,
        lines: [a01Line],
      ),
      'R2': await refund(
        a02,
        20000,
        at: DateTime(2026, 9, 10, 1, 30),
        by: samiId,
        dayId: dayA,
        kind: 'full',
      ),
      'R3': await refund(
        b01,
        5000,
        at: DateTime(2026, 9, 10, 12),
        by: samiId,
        approvedBy: nourId,
        dayId: dayB,
      ),
      'R4': await refund(a01, 2000, at: DateTime(2026, 9, 11, 10), by: nourId),
      'R5': await refund(
        c01,
        8000,
        at: tie,
        by: nourId,
        terminal: upstairs,
      ),
      'R6': await refund(b01, 1000, at: tie, by: samiId),
      // Larger than everything above together: in no row and no figure, or
      // the branch scope is broken.
      'RX': await refund(
        x01,
        999900,
        at: DateTime(2026, 9, 9, 15),
        by: samiId,
        branch: otherBranchId,
        terminal: elsewhere,
      ),
    };
  }

  /// The count and total `pos_refunds` holds for this branch, straight from
  /// the table — written here, not borrowed from the repository, so the two
  /// are held to each other rather than to themselves.
  Future<(int, int)> straight({
    int? servedBy,
    List<String>? only,
  }) async {
    final rows = await db.query(
      pg.config,
      'SELECT count(*)::bigint, coalesce(sum(r.total_minor), 0)::bigint '
      'FROM pos_refunds AS r JOIN pos_orders AS o ON o.id = r.order_id '
      'WHERE r.branch_id = @b '
      '  AND (@served::bigint IS NULL OR o.served_by = @served::bigint) '
      '  AND (@only::bigint[] IS NULL OR r.id = ANY(@only::bigint[]))',
      parameters: {
        'b': branchId,
        'served': servedBy,
        'only': only == null ? null : [for (final name in only) ids[name]!],
      },
    );
    return (rows.first[0] as int, rows.first[1] as int);
  }

  group('the list', () {
    test('is pos_refunds at this branch: one row per refund, newest first, '
        'each as it was written', () async {
      await seed();
      final listed = await repository.refunds(
        const RefundHistoryQuery(limit: 1000),
      );

      final table = await db.query(
        pg.config,
        'SELECT id FROM pos_refunds WHERE branch_id = @b '
        'ORDER BY occurred_at DESC, id DESC',
        parameters: {'b': branchId},
      );
      expect(listed.map((r) => r.id), [for (final row in table) row[0]]);
      expect(listed.map((r) => r.id), isNot(contains(ids['RX'])));

      RefundRecord named(String name) =>
          listed.singleWhere((r) => r.id == ids[name]);

      final r1 = named('R1');
      expect(r1.invoiceNumber, 'A-01');
      expect(r1.total.minor, 5000);
      expect(r1.total.currency, 'EGP');
      expect(r1.lineCount, 1);
      expect(r1.reasonName, 'Wrong order');
      expect(r1.reasonNameAr, 'طلب خاطئ');
      expect(r1.refundedByName, 'Nour Adel');
      expect(r1.servedByStaffId, nourId);
      expect(r1.terminalName, 'Counter');
      expect(r1.kind, RefundKind.partial);
      expect(r1.businessDate, DateTime(2026, 9, 9));

      // Given at 01:30 on the 10th, in the 9th's night: filed there.
      final r2 = named('R2');
      expect(r2.kind, RefundKind.full);
      expect(r2.lineCount, 0);
      expect(r2.businessDate, DateTime(2026, 9, 9));

      // Given by Sami on Nour's sale, with Nour's approval.
      final r3 = named('R3');
      expect(r3.refundedByName, 'Sami Farid');
      expect(r3.approvedByName, 'Nour Adel');
      expect(r3.servedByStaffId, nourId);

      final r5 = named('R5');
      expect(r5.terminalName, 'Upstairs');
      expect(r5.businessDate, isNull);
    });

    test('a line count is the refund\'s lines, not its sale\'s', () async {
      await seed();
      final counted = await db.query(
        pg.config,
        'SELECT r.id, count(l.id)::bigint FROM pos_refunds AS r '
        'LEFT JOIN pos_refund_lines AS l ON l.refund_id = r.id '
        'WHERE r.branch_id = @b GROUP BY r.id',
        parameters: {'b': branchId},
      );
      final listed = await repository.refunds(
        const RefundHistoryQuery(limit: 1000),
      );
      expect(
        {for (final r in listed) r.id: r.lineCount},
        {for (final row in counted) row[0] as int: row[1] as int},
      );
    });

    test('keyset pages never repeat or skip a refund, across a tie', () async {
      await seed();
      final whole = await repository.refunds(
        const RefundHistoryQuery(limit: 1000),
      );
      // R5 and R6 share a microsecond; by id, newest id first.
      expect(
        whole.take(2).map((r) => r.id),
        [ids['R6'], ids['R5']],
      );
      for (var limit = 1; limit <= 4; limit++) {
        expect(
          (await everyPage(const RefundHistoryQuery(), limit: limit))
              .map((r) => r.id),
          whole.map((r) => r.id),
          reason: 'pages of $limit',
        );
      }
    });

    test('a cursor that names no refund is an empty page, and another '
        'branch\'s refund is no way into it', () async {
      await seed();
      expect(
        await repository.refunds(
          const RefundHistoryQuery(afterRefundId: 999999),
        ),
        isEmpty,
      );
      final after = await repository.refunds(
        RefundHistoryQuery(afterRefundId: ids['RX'], limit: 1000),
      );
      expect(after, isNotEmpty);
      expect(after.map((r) => r.id), isNot(contains(ids['RX'])));
    });
  });

  group('the strip', () {
    test('the unfiltered figures are pos_refunds, by hand and read '
        'straight', () async {
      await seed();
      final summary = await repository.summariseRefunds(
        const RefundHistoryQuery(),
      );
      // 50 + 200 + 50 + 20 + 80 + 10.
      expect(summary.count, 6);
      expect(summary.total.minor, 41000);
      expect(summary.total.currency, 'EGP');
      final (count, total) = await straight();
      expect((summary.count, summary.total.minor), (count, total));
    });

    test('equals pos_refunds and the sum of every page, for each filter and '
        'every combination of them', () async {
      await seed();
      final r3 = ids['R3']!;

      // Each filter, the refunds it should admit (null: every one).
      final ranges = <(String, DateTime?, DateTime?, Set<String>?)>[
        ('any date', null, null, null),
        // R2, rung after midnight, is the 9th's.
        ('the 9th', DateTime(2026, 9, 9), DateTime(2026, 9, 10), {'R1', 'R2'}),
        // No day covers the 11th: filed by the calendar.
        ('the 11th', DateTime(2026, 9, 11), DateTime(2026, 9, 12), {'R4'}),
        (
          'the 9th to the 12th',
          DateTime(2026, 9, 9),
          DateTime(2026, 9, 13),
          null,
        ),
      ];
      final sellers = <(int?, Set<String>?)>[
        (null, null),
        // R3 and R6 were given by Sami, on Nour's sale: hers. R5 was given
        // by Nour, on Sami's sale: not.
        (nourId, {'R1', 'R3', 'R4', 'R6'}),
      ];
      final searches = <(String?, Set<String>?)>[
        (null, null),
        ('A-0', {'R1', 'R2', 'R4'}),
        ('#$r3', {'R3'}),
        ('$r3', {'R3'}),
        ('nothing like it', <String>{}),
      ];

      var combinations = 0;
      var nonEmpty = 0;
      for (final (rangeName, from, to, inRange) in ranges) {
        for (final (seller, bySeller) in sellers) {
          for (final (search, bySearch) in searches) {
            final query = RefundHistoryQuery(
              from: from,
              to: to,
              servedByStaffId: seller,
              search: search,
            );
            final label = '$rangeName, seller $seller, search $search';
            final expected = <String>{
              for (final name in ['R1', 'R2', 'R3', 'R4', 'R5', 'R6'])
                if ((inRange?.contains(name) ?? true) &&
                    (bySeller?.contains(name) ?? true) &&
                    (bySearch?.contains(name) ?? true))
                  name,
            };

            final paged = await everyPage(query, limit: 2);
            final summary = await repository.summariseRefunds(query);
            expect(
              paged.map((r) => r.id).toSet(),
              {for (final name in expected) ids[name]},
              reason: label,
            );
            expect(summary, RefundHistorySummary.of(paged), reason: label);
            final (count, total) = await straight(only: expected.toList());
            expect(
              (summary.count, summary.total.minor),
              (count, total),
              reason: '$label, against pos_refunds',
            );
            // The cursor and the page size are the list's, not the strip's.
            if (paged.isNotEmpty) {
              expect(
                await repository.summariseRefunds(
                  query.copyWith(afterRefundId: paged.first.id, limit: 1),
                ),
                summary,
                reason: '$label, from page two',
              );
              nonEmpty++;
            }
            combinations++;
          }
        }
      }
      expect(combinations, 4 * 2 * 5);
      expect(nonEmpty, greaterThan(combinations ~/ 3));
    });
  });

  group('whose refunds', () {
    // Through the role, as every fixture must be: a rule that read
    // `PosStaff.capabilities` would see no grant here either way.
    PosStaff cashier() => PosStaff(
      id: nourId,
      name: 'Nour Adel',
      role: const PosRole(
        id: 2,
        code: 'cashier',
        nameEn: 'Cashier',
        capabilities: {PosCapability.operate},
      ),
    );
    PosStaff supervisor() => PosStaff(
      id: samiId,
      name: 'Sami Farid',
      role: const PosRole(
        id: 3,
        code: 'supervisor',
        nameEn: 'Supervisor',
        capabilities: {PosCapability.operate, PosCapability.orderViewAll},
      ),
    );

    test('without order.view_all, the refunds on the cashier\'s own sales — '
        'rows and figures both', () async {
      await seed();
      final own = HistoryScope.scopeRefunds(
        const RefundHistoryQuery(),
        cashier(),
      )!;
      expect(own.servedByStaffId, nourId);

      final rows = await everyPage(own, limit: 2);
      expect(
        rows.map((r) => r.id).toSet(),
        {ids['R1'], ids['R3'], ids['R4'], ids['R6']},
      );
      expect(rows.map((r) => r.servedByStaffId), everyElement(nourId));

      final summary = await repository.summariseRefunds(own);
      // 50 + 50 + 20 + 10.
      expect(summary.count, 4);
      expect(summary.total.minor, 13000);
      final (count, total) = await straight(servedBy: nourId);
      expect((summary.count, summary.total.minor), (count, total));
    });

    test('a query that arrived asking for somebody else\'s is narrowed, not '
        'honoured', () async {
      await seed();
      final scoped = HistoryScope.scopeRefunds(
        RefundHistoryQuery(servedByStaffId: samiId),
        cashier(),
      )!;
      expect(scoped.servedByStaffId, nourId);
      expect(
        (await repository.refunds(scoped)).map((r) => r.servedByStaffId),
        everyElement(nourId),
      );
    });

    test('with order.view_all through the role, the branch; nobody signed '
        'in, nothing', () async {
      await seed();
      final branch = HistoryScope.scopeRefunds(
        const RefundHistoryQuery(),
        supervisor(),
      )!;
      expect(branch.servedByStaffId, isNull);
      expect((await repository.summariseRefunds(branch)).count, 6);
      expect(
        HistoryScope.scopeRefunds(const RefundHistoryQuery(), null),
        isNull,
      );
    });
  });

  group('the presets', () {
    test('Invoices is the settled sales: paid, or refunded in part', () async {
      await seed();
      final listed = await repository.search(
        HistoryPreset.invoices.apply(const OrderHistoryQuery(limit: 1000)),
      );
      final table = await db.query(
        pg.config,
        'SELECT invoice_number FROM pos_orders WHERE branch_id = @b '
        "  AND status IN ('PAID', 'CLOSED', 'PARTIALLY_REFUNDED')",
        parameters: {'b': branchId},
      );
      expect(
        listed.map((o) => o.invoiceNumber).toSet(),
        {for (final row in table) row[0] as String},
      );
      // A-02 and C-01 went back in full (R2, R5) and A-03 and B-02 were
      // voided: none are here. A-01 and B-01 were refunded in part and are.
      expect(listed.map((o) => o.invoiceNumber).toSet(), {
        'A-01',
        'B-01',
        'B-03',
      });
    });

    test('Cancelled orders is the voids, and its strip is their count and '
        'what they came to', () async {
      await seed();
      final query = HistoryPreset.voided.apply(const OrderHistoryQuery());
      final summary = await repository.summarise(query);
      final table = await db.query(
        pg.config,
        'SELECT count(*)::bigint, coalesce(sum(total_minor), 0)::bigint '
        "FROM pos_orders WHERE branch_id = @b AND status = 'VOIDED'",
        parameters: {'b': branchId},
      );
      expect(summary.count, table.first[0]);
      expect(summary.deadTotal.minor, table.first[1]);
      // 50 + 70, by hand; and nothing in the live figures, because every
      // row is struck through.
      expect(summary.deadTotal.minor, 12000);
      expect(summary.total.minor, 0);

      final rows = await repository.search(query);
      expect(summary, OrderHistorySummary.of(rows));
      final a03 = rows.singleWhere((o) => o.invoiceNumber == 'A-03');
      expect(a03.voidedByName, 'Sami Farid');
      expect(a03.voidReason, 'Wrong order');
      expect(a03.voidedAt, isNotNull);
    });
  });
}
