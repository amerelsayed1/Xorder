@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_order_history_repository.dart';
import 'package:shared_module/domain/models/order_record.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/history/history_scope.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart';

/// The sales list's summary strip and its pages, against PostgreSQL (BO-3).
///
/// One claim, from three sides. The four figures are the sums of the rows the
/// list shows — so `summarise` must equal the Dart rule applied to every page
/// of `search`, under every filter and every combination of them. The pages
/// must be the list — every row once, in order, with a tie on the instant
/// straddling a page boundary. And a cashier's figures are their own sales',
/// because the scope that narrows their list narrows their totals.
///
/// The unfiltered figures are also worked out by hand below, so the SQL is
/// held to arithmetic and not only to its Dart twin — two copies of one wrong
/// rule would otherwise agree with each other all day.
void main() {
  if (PgFixture.host == null) {
    test(
      'order history paging (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int nourId;
  late int samiId;
  late PostgresOrderHistoryRepository repository;

  const counter = '11111111-1111-4111-8111-111111111111';
  const upstairs = '22222222-2222-4222-8222-222222222222';
  const elsewhere = '33333333-3333-4333-8333-333333333333';
  const cash = 1;
  const card = 2;

  /// Six sales on one instant, to the microsecond.
  final tie = DateTime(2026, 9, 9, 13, 0, 0, 0, 123);

  Future<int> insertOrder({
    required String invoice,
    required DateTime occurredAt,
    int? branch,
    String status = 'PAID',
    String type = 'takeaway',
    required int total,
    String terminal = counter,
    int? servedBy,
    int? businessDayId,
    String? table,
    List<(int, int)> payments = const [],
  }) async {
    final id =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_orders (client_transaction_id, business_id, '
                  '  branch_id, terminal_id, invoice_number, order_type, '
                  '  table_label, currency, exponent, subtotal_minor, '
                  '  discount_minor, service_minor, vat_minor, total_minor, '
                  '  occurred_at, status, served_by, business_day_id, '
                  '  voided_by, voided_at) '
                  'VALUES (gen_random_uuid(), @r, @b, @terminal::uuid, '
                  "  @invoice, @type, @table, 'EGP', 2, @total, 0, 0, 0, "
                  '  @total, @at::timestamptz, @status, @served, @day, '
                  '  @voidedBy, @voidedAt::timestamptz) RETURNING id',
                  parameters: {
                    'r': businessId,
                    'b': branch ?? branchId,
                    'terminal': terminal,
                    'invoice': invoice,
                    'type': type,
                    'table': table,
                    'total': total,
                    'at': occurredAt.toUtc(),
                    'status': status,
                    'served': servedBy,
                    'day': businessDayId,
                    'voidedBy': status == 'VOIDED' ? samiId : null,
                    'voidedAt': status == 'VOIDED' ? occurredAt.toUtc() : null,
                  },
                ))
                .first[0]
            as int;
    for (final (tender, amount) in payments) {
      await db.query(
        pg.config,
        'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
        '  amount_minor) VALUES (@o, @t, @label, @amount)',
        parameters: {
          'o': id,
          't': tender,
          'label': tender == cash ? 'Cash' : 'Card',
          'amount': amount,
        },
      );
    }
    return id;
  }

  /// A refund and the tender it went back in, in one transaction — the
  /// tender check is deferred to commit on PostgreSQL, so both rows must land
  /// before it. Two statements rather than a writing CTE, which SQLite (the
  /// cloud till's engine) does not have.
  Future<void> refund(int orderId, int amount) =>
      db.runTx(pg.config, (tx) async {
        final given = await tx.execute(
          Sql.named(
            'INSERT INTO pos_refunds (client_refund_id, business_id, branch_id, '
            '  terminal_id, order_id, kind, subtotal_minor, service_minor, '
            '  vat_minor, total_minor, refunded_by, occurred_at) '
            "VALUES (gen_random_uuid(), @r, @b, @terminal::uuid, @o, 'partial', "
            '  @amount, 0, 0, @amount, @by, @at::timestamptz) RETURNING id',
          ),
          parameters: {
            'r': businessId,
            'b': branchId,
            'terminal': counter,
            'o': orderId,
            'amount': amount,
            'by': nourId,
            'at': DateTime.utc(2026, 9, 10, 14),
          },
        );
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_refund_payments (refund_id, tender_type_id, '
            "  label, amount_minor) VALUES (@refund, 1, 'Cash', @amount)",
          ),
          parameters: {'refund': given.first[0], 'amount': amount},
        );
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

  /// Every page of [query], [limit] rows at a time, each after the last row of
  /// the one before — what the screen's Next does.
  Future<List<OrderRecord>> everyPage(
    OrderHistoryQuery query, {
    required int limit,
  }) async {
    final rows = <OrderRecord>[];
    int? after;
    for (var turned = 0; turned < 200; turned++) {
      final page = await repository.search(
        query.copyWith(afterOrderId: after, clearAfter: after == null, limit: limit),
      );
      rows.addAll(page);
      if (page.length < limit) return rows;
      after = page.last.id;
    }
    fail('paging did not come to an end');
  }

  setUp(() async {
    pg = await PgFixture.open('order_history_paging');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_businesses (slug, name) "
                  "VALUES ('paging', 'Paging') RETURNING id",
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
    branchId = await branch('PGN');
    otherBranchId = await branch('PG2');

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

    repository = PostgresOrderHistoryRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  /// The branch's trading, chosen so every filter below matches some rows
  /// and misses others, and every money case is present: paid, split,
  /// unpaid, part paid, part refunded, refunded in full, voided.
  ///
  /// Both days are closed, so the stamping trigger leaves a row's day as
  /// given: the 12th has no day at all and is filed by its calendar date.
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

    await insertOrder(
      invoice: 'A-01',
      occurredAt: DateTime(2026, 9, 9, 12),
      businessDayId: dayA,
      type: 'dine_in',
      total: 10000,
      servedBy: nourId,
      table: 'T1',
      payments: [(cash, 10000)],
    );
    await insertOrder(
      invoice: 'A-02',
      occurredAt: tie,
      businessDayId: dayA,
      total: 20000,
      servedBy: samiId,
      payments: [(card, 20000)],
    );
    await insertOrder(
      invoice: 'A-03',
      occurredAt: tie,
      businessDayId: dayA,
      total: 30000,
      servedBy: nourId,
      terminal: upstairs,
      // Split: an EXISTS on either tender finds it, and finds it once.
      payments: [(cash, 10000), (card, 20000)],
    );
    await insertOrder(
      invoice: 'A-04',
      occurredAt: tie,
      businessDayId: dayA,
      status: 'VOIDED',
      type: 'dine_in',
      total: 5000,
      servedBy: samiId,
      table: 'T2',
    );
    await insertOrder(
      invoice: 'A-05',
      occurredAt: tie,
      businessDayId: dayA,
      type: 'dine_in',
      total: 8000,
      servedBy: nourId,
      table: 'T3',
    );
    await insertOrder(
      invoice: 'A-06',
      occurredAt: tie,
      businessDayId: dayA,
      total: 12000,
      payments: [(cash, 4000)],
    );
    // Written PAID and moved by the refund, as a real one is: the refund
    // trigger derives the status from the money and refuses an order that
    // already reads refunded.
    final partRefunded = await insertOrder(
      invoice: 'A-07',
      occurredAt: tie,
      businessDayId: dayA,
      type: 'dine_in',
      total: 15000,
      servedBy: nourId,
      terminal: upstairs,
      table: 'T1',
      payments: [(card, 15000)],
    );
    await refund(partRefunded, 5000);
    final refunded = await insertOrder(
      invoice: 'A-08',
      occurredAt: DateTime(2026, 9, 9, 23, 30),
      businessDayId: dayA,
      total: 9000,
      servedBy: samiId,
      terminal: upstairs,
      payments: [(cash, 9000)],
    );
    await refund(refunded, 9000);
    // Past midnight, still the 9th's night: a date filter must file it there.
    await insertOrder(
      invoice: 'B-01',
      occurredAt: DateTime(2026, 9, 10, 1, 30),
      businessDayId: dayA,
      type: 'dine_in',
      total: 7000,
      servedBy: samiId,
      payments: [(cash, 7000)],
    );
    // A second tie, on the 10th.
    await insertOrder(
      invoice: 'B-02',
      occurredAt: DateTime(2026, 9, 10, 9),
      businessDayId: dayB,
      total: 11000,
      servedBy: nourId,
      payments: [(card, 11000)],
    );
    await insertOrder(
      invoice: 'B-03',
      occurredAt: DateTime(2026, 9, 10, 9),
      businessDayId: dayB,
      total: 6000,
      servedBy: nourId,
      terminal: upstairs,
      payments: [(cash, 3000)],
    );
    await insertOrder(
      invoice: 'B-04',
      occurredAt: DateTime(2026, 9, 10, 10),
      businessDayId: dayB,
      status: 'VOIDED',
      total: 4000,
      servedBy: nourId,
    );
    await insertOrder(
      invoice: 'B-05',
      occurredAt: DateTime(2026, 9, 10, 11),
      businessDayId: dayB,
      type: 'dine_in',
      total: 25000,
      servedBy: samiId,
      terminal: upstairs,
      table: 'T9',
      payments: [(cash, 25000)],
    );
    await insertOrder(
      invoice: 'C-01',
      occurredAt: DateTime(2026, 9, 12, 12),
      total: 13000,
      servedBy: nourId,
      payments: [(card, 13000)],
    );
    await insertOrder(
      invoice: 'C-02',
      occurredAt: DateTime(2026, 9, 12, 12),
      type: 'dine_in',
      total: 2000,
      servedBy: samiId,
      terminal: upstairs,
    );
    // Another branch's sale, larger than everything above together. It is in
    // no figure, or the branch scope is broken.
    await insertOrder(
      invoice: 'X-01',
      occurredAt: DateTime(2026, 9, 9, 12),
      branch: otherBranchId,
      terminal: elsewhere,
      total: 999900,
      payments: [(cash, 999900)],
    );
  }

  group('summarise', () {
    test('the unfiltered figures, by hand', () async {
      await seed();
      final summary = await repository.summarise(const OrderHistoryQuery());

      // Fifteen rows at this branch; A-04, A-08 and B-04 are struck through.
      expect(summary.count, 15);
      expect(summary.dead, 3);
      // The twelve live totals: 100 + 200 + 300 + 80 + 120 + 150 + 70 + 110
      // + 60 + 250 + 130 + 20.
      expect(summary.total.minor, 159000);
      // Taken on those twelve: the unpaid A-05 and C-02 took nothing, A-06
      // took 40 of 120 and B-03 30 of 60. A-07's refund is not taken off.
      expect(summary.paid.minor, 138000);
      // Owed: A-05 80, A-06 80, B-03 30, C-02 20. Not the voids, which read
      // UNPAID and owe nothing; not A-07, which was paid in full.
      expect(summary.outstanding.minor, 21000);
      expect(summary.total.currency, 'EGP');
    });

    test('equals the sum of every page, for each filter and every '
        'combination of them', () async {
      await seed();

      // Each dimension's values, the first always "not set".
      final ranges = <(String, DateTime?, DateTime?)>[
        ('any date', null, null),
        // The 9th's business date — B-01, rung up after midnight, included.
        ('the 9th', DateTime(2026, 9, 9), DateTime(2026, 9, 10)),
      ];
      final statuses = <Set<OrderStatus>>[
        const {},
        const {OrderStatus.voided},
        const {OrderStatus.paid, OrderStatus.partiallyRefunded},
      ];
      final types = <Set<OrderType>>[
        const {},
        const {OrderType.takeaway},
      ];
      final sellers = <int?>[null, nourId];
      final tenders = <int?>[null, cash, card];
      final terminals = <String?>[null, upstairs];
      final searches = <String?>[null, 'B-', 't1'];

      var combinations = 0;
      var nonEmpty = 0;
      var owing = 0;
      for (final (rangeName, from, to) in ranges) {
        for (final status in statuses) {
          for (final type in types) {
            for (final seller in sellers) {
              for (final tender in tenders) {
                for (final terminal in terminals) {
                  for (final search in searches) {
                    final query = OrderHistoryQuery(
                      from: from,
                      to: to,
                      statuses: status,
                      orderTypes: type,
                      servedByStaffId: seller,
                      tenderTypeId: tender,
                      terminalId: terminal,
                      search: search,
                    );
                    final label =
                        '$rangeName, statuses ${status.map((s) => s.wire)}, '
                        'types ${type.map((t) => t.wire)}, seller $seller, '
                        'tender $tender, terminal $terminal, search $search';

                    final paged = await everyPage(query, limit: 3);
                    final summary = await repository.summarise(query);
                    expect(
                      summary,
                      OrderHistorySummary.of(paged),
                      reason: label,
                    );
                    expect(summary.count, paged.length, reason: label);

                    // The cursor and the page size are the list's, not the
                    // total's: a summary asked from page two is the same.
                    if (paged.isNotEmpty) {
                      expect(
                        await repository.summarise(
                          query.copyWith(
                            afterOrderId: paged.first.id,
                            limit: 1,
                          ),
                        ),
                        summary,
                        reason: '$label, from page two',
                      );
                      nonEmpty++;
                    }
                    if (summary.outstanding.minor > 0) owing++;
                    combinations++;
                  }
                }
              }
            }
          }
        }
      }

      // Not vacuous: a filter that matched nothing everywhere would pass all
      // of the above.
      expect(combinations, 2 * 3 * 2 * 2 * 3 * 2 * 3);
      expect(nonEmpty, greaterThan(combinations ~/ 4));
      expect(owing, greaterThan(10));
    });

    test('a cashier without order.view_all is summed over their own sales '
        'only', () async {
      await seed();
      // Through the role, as every fixture must be: a rule that read
      // `PosStaff.capabilities` would see no grant here either way.
      final cashier = PosStaff(
        id: nourId,
        name: 'Nour Adel',
        role: const PosRole(
          id: 2,
          code: 'cashier',
          nameEn: 'Cashier',
          capabilities: {PosCapability.operate},
        ),
      );
      final supervisor = PosStaff(
        id: samiId,
        name: 'Sami Farid',
        role: const PosRole(
          id: 3,
          code: 'supervisor',
          nameEn: 'Supervisor',
          capabilities: {PosCapability.operate, PosCapability.orderViewAll},
        ),
      );

      final own = HistoryScope.scope(const OrderHistoryQuery(), cashier)!;
      final summary = await repository.summarise(own);
      // Nour's eight: A-01, A-03, A-05, A-07, B-02, B-03, B-04 (void), C-01.
      expect(summary.count, 8);
      expect(summary.dead, 1);
      expect(summary.total.minor, 93000);
      expect(summary.paid.minor, 82000);
      expect(summary.outstanding.minor, 11000);
      expect(
        (await everyPage(own, limit: 2)).map((o) => o.servedByStaffId),
        everyElement(nourId),
      );

      // The same filter, asked for somebody who may see the branch.
      final branch = await repository.summarise(
        HistoryScope.scope(const OrderHistoryQuery(), supervisor)!,
      );
      expect(branch.count, 15);
    });

    test('a branch with no sales in the window is zeros, not an error', () async {
      await seed();
      final summary = await repository.summarise(
        OrderHistoryQuery(from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 2)),
      );
      expect(summary.count, 0);
      expect(summary.total.minor, 0);
      expect(summary.outstanding.minor, 0);
    });
  });

  group('keyset pages', () {
    test('never repeat or skip a row where sales share a timestamp', () async {
      await seed();
      final whole = await repository.search(
        const OrderHistoryQuery(limit: 1000),
      );
      expect(whole, hasLength(15));

      // The six on one microsecond come out by id, newest id first — the
      // tie-break that gives each row exactly one place.
      final tied = [
        for (final o in whole)
          if (o.occurredAt == tie) o.invoiceNumber,
      ];
      expect(tied, ['A-07', 'A-06', 'A-05', 'A-04', 'A-03', 'A-02']);

      // Every page size, so a boundary falls at every position in the tie.
      for (var limit = 1; limit <= 7; limit++) {
        final paged = await everyPage(const OrderHistoryQuery(), limit: limit);
        expect(
          paged.map((o) => o.id),
          whole.map((o) => o.id),
          reason: 'pages of $limit',
        );
      }
    });

    test('a sale rung up while somebody reads page one does not move page '
        'two', () async {
      // What an offset would get wrong: page two by `OFFSET 3` after a new
      // sale arrives starts one row earlier, and shows again the row that
      // ended page one.
      await seed();
      const size = OrderHistoryQuery(limit: 3);
      final first = await repository.search(size);
      final second = await repository.search(
        size.copyWith(afterOrderId: first.last.id),
      );

      await insertOrder(
        invoice: 'NEW-1',
        occurredAt: DateTime(2026, 9, 13, 12),
        total: 1000,
        payments: [(cash, 1000)],
      );

      final again = await repository.search(
        size.copyWith(afterOrderId: first.last.id),
      );
      expect(
        again.map((o) => o.invoiceNumber),
        second.map((o) => o.invoiceNumber),
      );
    });

    test('a cursor that names no order is an empty page, not an error', () async {
      await seed();
      expect(
        await repository.search(const OrderHistoryQuery(afterOrderId: 999999)),
        isEmpty,
      );
    });

    test('never crosses into another branch through its cursor', () async {
      await seed();
      final theirs =
          (await db.query(
                    pg.config,
                    "SELECT id FROM pos_orders WHERE invoice_number = 'X-01'",
                  ))
                  .first[0]
              as int;
      // The cursor is a position, and the branch scope still holds after it.
      final page = await repository.search(
        OrderHistoryQuery(afterOrderId: theirs, limit: 1000),
      );
      expect(page.map((o) => o.invoiceNumber), isNot(contains('X-01')));
      expect(page, isNotEmpty);
    });
  });
}
