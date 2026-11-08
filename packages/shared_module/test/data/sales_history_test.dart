@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_order_history_repository.dart';
import 'package:shared_module/domain/models/order_record.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:shared_module/domain/services/payment_status.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// The sales list and sale details, against PostgreSQL (plan 17 S1).
///
/// The claims a wrong query would get subtly wrong: that the payment status the
/// SQL derives is the one the rows add up to, that a sale past midnight is
/// filed under the night it belongs to, that the filters narrow and combine
/// without a split bill appearing twice, and that a sale's activity comes back
/// from four tables in the order it happened.
void main() {
  if (PgFixture.host == null) {
    test('sales history (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int nourId;
  late int samiId;
  late PostgresOrderHistoryRepository repository;

  const counter = '11111111-1111-4111-8111-111111111111';
  const upstairs = '22222222-2222-4222-8222-222222222222';
  const elsewhere = '33333333-3333-4333-8333-333333333333';

  Future<int> insertOrder({
    required String invoice,
    required DateTime occurredAt,
    String status = 'PAID',
    int total = 26800,
    String terminal = counter,
    int? servedBy,
    int? businessDayId,
    int? voidedBy,
  }) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status, served_by, business_day_id, voided_by, '
      '  voided_at) '
      "VALUES (gen_random_uuid(), @r, @b, @terminal::uuid, @invoice, 'takeaway', "
      "  'EGP', 2, @total, 0, 0, 0, @total, @at::timestamptz, @status, @served, "
      '  @day, @voidedBy, @voidedAt::timestamptz) RETURNING id',
      parameters: {
        'r': businessId,
        'b': branchId,
        'terminal': terminal,
        'invoice': invoice,
        'total': total,
        'at': occurredAt.toUtc(),
        'status': status,
        'served': servedBy,
        'day': businessDayId,
        'voidedBy': voidedBy,
        'voidedAt': voidedBy == null ? null : occurredAt.toUtc(),
      },
    );
    return rows.first[0] as int;
  }

  Future<void> pay(int orderId, int tenderTypeId, int amount) => db.query(
    pg.config,
    'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
    '  amount_minor) VALUES (@o, @t, @label, @amount)',
    parameters: {
      'o': orderId,
      't': tenderTypeId,
      'label': tenderTypeId == 1 ? 'Cash' : 'Card',
      'amount': amount,
    },
  );

  /// A refund and the tender it went back in, in one statement — the tender
  /// check is deferred to commit, and a refund with no tender row is refused.
  Future<void> refund(int orderId, int amount, {DateTime? at}) => db.query(
    pg.config,
    'WITH given AS ( '
    '  INSERT INTO pos_refunds (client_refund_id, business_id, branch_id, '
    '    terminal_id, order_id, kind, subtotal_minor, service_minor, '
    '    vat_minor, total_minor, refunded_by, occurred_at) '
    "  VALUES (gen_random_uuid(), @r, @b, @terminal::uuid, @o, 'partial', "
    '    @amount, 0, 0, @amount, @by, @at::timestamptz) RETURNING id) '
    'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
    "  amount_minor) SELECT id, 1, 'Cash', @amount FROM given",
    parameters: {
      'r': businessId,
      'b': branchId,
      'terminal': counter,
      'o': orderId,
      'amount': amount,
      'by': nourId,
      'at': (at ?? DateTime(2026, 9, 10, 14)).toUtc(),
    },
  );

  Future<int> businessDay(
    DateTime date, {
    required DateTime openedAt,
    DateTime? closedAt,
  }) async =>
      (await db.query(
            pg.config,
            'INSERT INTO pos_business_days (business_id, branch_id, '
            '  business_date, opened_at, closed_at, closed_by) '
            'VALUES (@r, @b, @date::date, @opened::timestamptz, '
            '  @closed::timestamptz, @closedBy) RETURNING id',
            parameters: {
              'r': businessId,
              'b': branchId,
              'date':
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}',
              'opened': openedAt.toUtc(),
              'closed': closedAt?.toUtc(),
              'closedBy': closedAt == null ? null : samiId,
            },
          ))
          .first[0]
          as int;

  Future<List<String>> invoices(OrderHistoryQuery query) async =>
      (await repository.search(query)).map((o) => o.invoiceNumber).toList();

  setUp(() async {
    pg = await PgFixture.open('sales_history');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_businesses (slug, name) "
                  "VALUES ('sales', 'Sales') RETURNING id",
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
    branchId = await branch('SLS');
    otherBranchId = await branch('SL2');

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

  group('payment status', () {
    // Each case is the rows a sale would really have, and the expectation is
    // checked three ways: against the word the case names, against the SQL's
    // answer on the record, and against the Dart rule fed the rows read back.
    // The SQL and the Dart rule are two copies of one rule; this is where they
    // are held to each other.
    final cases = <(String, int, List<int>, List<int>, PaymentStatus)>[
      ('UNPAID', 26800, [], [], PaymentStatus.unpaid),
      ('PART', 26800, [10000], [], PaymentStatus.partiallyPaid),
      ('SPLIT', 26800, [20000, 6800], [], PaymentStatus.paid),
      ('COMP', 0, [], [], PaymentStatus.paid),
      ('PARTREF', 26800, [26800], [5000], PaymentStatus.partiallyRefunded),
      ('ALLBACK', 26800, [20000, 6800], [6800, 20000], PaymentStatus.refunded),
    ];

    test('the SQL answers what the rows add up to', () async {
      for (final (invoice, total, payments, refunds, _) in cases) {
        final id = await insertOrder(
          invoice: invoice,
          occurredAt: DateTime(2026, 9, 10, 12),
          // The refund trigger only accepts a sale that took money.
          status: payments.isEmpty ? 'OPEN' : 'PAID',
          total: total,
        );
        for (final (index, amount) in payments.indexed) {
          await pay(id, index == 0 ? 1 : 2, amount);
        }
        for (final amount in refunds) {
          await refund(id, amount);
        }
      }

      final records = {
        for (final order in await repository.search(const OrderHistoryQuery()))
          order.invoiceNumber: order,
      };

      for (final (invoice, _, _, _, expected) in cases) {
        final record = records[invoice]!;
        // The rows as they are in the table now, not as this test meant to
        // write them — the sum is the acceptance criterion.
        final paid = await db.query(
          pg.config,
          'SELECT amount_minor FROM pos_order_payments WHERE order_id = @id',
          parameters: {'id': record.id},
        );
        final back = await db.query(
          pg.config,
          'SELECT total_minor FROM pos_refunds WHERE order_id = @id',
          parameters: {'id': record.id},
        );
        final fromRows = paymentStatusOf(
          totalMinor: record.total.minor,
          paymentsMinor: paid.map((row) => row[0] as int),
          refundsMinor: back.map((row) => row[0] as int),
        );

        expect(record.paymentStatus, expected, reason: invoice);
        expect(record.paymentStatus, fromRows, reason: invoice);
      }
    });

    test('a split bill with two refunds is counted once each way', () async {
      // The lateral sums exist for this. A join of payments and refunds to the
      // order would multiply them: two tenders × two refunds is each counted
      // twice, and the sale reads as having taken 536.00.
      final id = await insertOrder(
        invoice: 'SPLIT-BACK',
        occurredAt: DateTime(2026, 9, 10, 12),
      );
      await pay(id, 1, 20000);
      await pay(id, 2, 6800);
      await refund(id, 1000);
      await refund(id, 2000);

      final record = (await repository.search(const OrderHistoryQuery())).single;
      expect(record.paidTotal.minor, 26800);
      expect(record.refundedTotal.minor, 3000);
      expect(record.paymentStatus, PaymentStatus.partiallyRefunded);
    });

    test('the detail carries the same status as the list', () async {
      final id = await insertOrder(
        invoice: 'D',
        occurredAt: DateTime(2026, 9, 10, 12),
        status: 'OPEN',
      );
      await pay(id, 1, 10000);
      final detail = await repository.detail(id);
      expect(detail!.order.paymentStatus, PaymentStatus.partiallyPaid);
    });
  });

  group('the business day', () {
    test('a sale past midnight is filed under the night it belongs to', () async {
      // Open at ten in the morning of the 10th, closed at two on the 11th.
      await businessDay(
        DateTime(2026, 9, 10),
        openedAt: DateTime(2026, 9, 10, 10),
        closedAt: DateTime(2026, 9, 11, 2),
      );
      await insertOrder(invoice: 'EVENING', occurredAt: DateTime(2026, 9, 10, 20));
      await insertOrder(invoice: 'NIGHT', occurredAt: DateTime(2026, 9, 11, 1, 30));
      // After the close, before anybody opened the next day: no business day
      // covers it, so it is filed by its calendar date.
      await insertOrder(invoice: 'LATE', occurredAt: DateTime(2026, 9, 11, 3));

      expect(
        await invoices(
          OrderHistoryQuery(from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 11)),
        ),
        ['NIGHT', 'EVENING'],
      );
      expect(
        await invoices(
          OrderHistoryQuery(from: DateTime(2026, 9, 11), to: DateTime(2026, 9, 12)),
        ),
        ['LATE'],
      );

      final night = (await repository.search(const OrderHistoryQuery()))
          .firstWhere((o) => o.invoiceNumber == 'NIGHT');
      expect(night.businessDate, DateTime(2026, 9, 10));
    });

    test('an open day files everything since it opened', () async {
      await businessDay(
        DateTime(2026, 9, 10),
        openedAt: DateTime(2026, 9, 10, 10),
      );
      await insertOrder(invoice: 'STILL-OPEN', occurredAt: DateTime(2026, 9, 11, 4));

      expect(
        await invoices(
          OrderHistoryQuery(from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 11)),
        ),
        ['STILL-OPEN'],
      );
    });

    test('a stamped business_day_id wins over the window', () async {
      // Nothing stamps it today; the day something does, the stamp must be the
      // answer, not whichever window the timestamp happens to fall in.
      final tenth = await businessDay(
        DateTime(2026, 9, 10),
        openedAt: DateTime(2026, 9, 10, 10),
        closedAt: DateTime(2026, 9, 11, 2),
      );
      await businessDay(
        DateTime(2026, 9, 12),
        openedAt: DateTime(2026, 9, 12, 10),
      );
      await insertOrder(
        invoice: 'STAMPED',
        occurredAt: DateTime(2026, 9, 12, 12),
        businessDayId: tenth,
      );

      expect(
        await invoices(
          OrderHistoryQuery(from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 11)),
        ),
        ['STAMPED'],
      );
      expect(
        await invoices(
          OrderHistoryQuery(from: DateTime(2026, 9, 12), to: DateTime(2026, 9, 13)),
        ),
        isEmpty,
      );
    });

    test('another branch\'s business day files nothing here', () async {
      await db.query(
        pg.config,
        'INSERT INTO pos_business_days (business_id, branch_id, '
        "  business_date, opened_at) VALUES (@r, @b, '2026-09-09', "
        '  @opened::timestamptz)',
        parameters: {
          'r': businessId,
          'b': otherBranchId,
          'opened': DateTime(2026, 9, 9, 10).toUtc(),
        },
      );
      await insertOrder(invoice: 'MINE', occurredAt: DateTime(2026, 9, 10, 12));

      final mine = (await repository.search(const OrderHistoryQuery())).single;
      expect(mine.businessDate, isNull);
      expect(
        await invoices(
          OrderHistoryQuery(from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 11)),
        ),
        ['MINE'],
      );
    });
  });

  group('the payment column (BO-2)', () {
    // Aggregated by the search itself, one entry per method in the order it
    // was first taken — so these ask `search`, not `detail`.
    Future<List<(int, String)>> methodsOf(
      String invoice, [
      OrderHistoryQuery query = const OrderHistoryQuery(),
    ]) async => [
      for (final tender
          in (await repository.search(query))
              .singleWhere((o) => o.invoiceNumber == invoice)
              .tenders)
        (tender.tenderTypeId, tender.label),
    ];

    test('a split bill lists every method, in the order it was taken', () async {
      final id = await insertOrder(
        invoice: 'SPLIT',
        occurredAt: DateTime(2026, 9, 10, 11),
      );
      await pay(id, 2, 6800);
      await pay(id, 1, 20000);

      expect(await methodsOf('SPLIT'), [(2, 'Card'), (1, 'Cash')]);
    });

    test('the same method taken twice is named once', () async {
      final id = await insertOrder(
        invoice: 'TWICE',
        occurredAt: DateTime(2026, 9, 10, 11),
      );
      await pay(id, 1, 10000);
      await pay(id, 2, 6800);
      await pay(id, 1, 10000);

      expect(await methodsOf('TWICE'), [(1, 'Cash'), (2, 'Card')]);
    });

    test('a method renamed between payments keeps each name it was taken '
        'under', () async {
      // Grouped on the label as well as the id: the receipt says what the
      // payment row says, and the list must not say something else.
      final id = await insertOrder(
        invoice: 'RENAMED',
        occurredAt: DateTime(2026, 9, 10, 11),
      );
      await pay(id, 2, 10000);
      await db.query(
        pg.config,
        'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
        "  amount_minor) VALUES (@o, 2, 'Visa', 16800)",
        parameters: {'o': id},
      );

      expect(await methodsOf('RENAMED'), [(2, 'Card'), (2, 'Visa')]);
    });

    test('a sale that took no money names none, and still lists', () async {
      await insertOrder(
        invoice: 'VOIDED',
        occurredAt: DateTime(2026, 9, 10, 11),
        status: 'VOIDED',
        voidedBy: samiId,
      );

      expect(await methodsOf('VOIDED'), isEmpty);
    });

    test('filtering by one method still names all of a split bill\'s', () async {
      // The filter chooses rows; the column describes the row. A split bill
      // found by "Card" that then said only "Card" would hide the cash half.
      final id = await insertOrder(
        invoice: 'SPLIT',
        occurredAt: DateTime(2026, 9, 10, 11),
      );
      await pay(id, 1, 20000);
      await pay(id, 2, 6800);

      expect(
        await methodsOf('SPLIT', const OrderHistoryQuery(tenderTypeId: 2)),
        [(1, 'Cash'), (2, 'Card')],
      );
    });

    test('the invoice lookup and the detail carry the same list', () async {
      final id = await insertOrder(
        invoice: 'SPLIT',
        occurredAt: DateTime(2026, 9, 10, 11),
      );
      await pay(id, 1, 20000);
      await pay(id, 2, 6800);

      List<(int, String)> pairs(OrderRecord order) => [
        for (final t in order.tenders) (t.tenderTypeId, t.label),
      ];
      expect(pairs((await repository.byInvoiceNumber('SPLIT'))!), [
        (1, 'Cash'),
        (2, 'Card'),
      ]);
      expect(pairs((await repository.detail(id))!.order), [
        (1, 'Cash'),
        (2, 'Card'),
      ]);
    });
  });

  group('filters', () {
    late int cashAtCounter;
    late int splitAtCounter;
    late int cardUpstairs;

    setUp(() async {
      cashAtCounter = await insertOrder(
        invoice: 'CASH-COUNTER',
        occurredAt: DateTime(2026, 9, 10, 10),
        servedBy: nourId,
      );
      splitAtCounter = await insertOrder(
        invoice: 'SPLIT-COUNTER',
        occurredAt: DateTime(2026, 9, 10, 11),
        servedBy: nourId,
      );
      cardUpstairs = await insertOrder(
        invoice: 'CARD-UPSTAIRS',
        occurredAt: DateTime(2026, 9, 10, 12),
        terminal: upstairs,
        servedBy: samiId,
      );
      await pay(cashAtCounter, 1, 26800);
      await pay(splitAtCounter, 1, 20000);
      await pay(splitAtCounter, 2, 6800);
      await pay(cardUpstairs, 2, 26800);
    });

    test('by payment method, a split bill once', () async {
      // EXISTS, not a join: the split sale has a card row and must appear, and
      // appear once.
      expect(await invoices(const OrderHistoryQuery(tenderTypeId: 2)), [
        'CARD-UPSTAIRS',
        'SPLIT-COUNTER',
      ]);
      expect(await invoices(const OrderHistoryQuery(tenderTypeId: 1)), [
        'SPLIT-COUNTER',
        'CASH-COUNTER',
      ]);
    });

    test('by terminal, with the terminal named on the record', () async {
      final upstairsOnly = await repository.search(
        const OrderHistoryQuery(terminalId: upstairs),
      );
      expect(upstairsOnly.map((o) => o.invoiceNumber), ['CARD-UPSTAIRS']);
      expect(upstairsOnly.single.terminalName, 'Upstairs');
      expect(upstairsOnly.single.terminalId, upstairs);
    });

    test('they combine', () async {
      expect(
        await invoices(
          const OrderHistoryQuery(tenderTypeId: 2, terminalId: counter),
        ),
        ['SPLIT-COUNTER'],
      );
      expect(
        await invoices(
          OrderHistoryQuery(
            tenderTypeId: 2,
            terminalId: counter,
            servedByStaffId: samiId,
          ),
        ),
        isEmpty,
      );
      expect(
        await invoices(
          OrderHistoryQuery(tenderTypeId: 1, servedByStaffId: nourId),
        ),
        ['SPLIT-COUNTER', 'CASH-COUNTER'],
      );
    });

    test('a malformed terminal id is an empty list, not an error', () async {
      expect(
        await invoices(const OrderHistoryQuery(terminalId: 'not-a-uuid')),
        isEmpty,
      );
    });

    test('the terminal list is this branch\'s tills', () async {
      final tills = await repository.terminals();
      expect(tills.map((t) => t.name), ['Counter', 'Upstairs']);
      expect(tills.map((t) => t.id), [counter, upstairs]);
    });
  });

  group('activity', () {
    Future<void> printJob(
      int orderId, {
      required String kind,
      required DateTime queuedAt,
      DateTime? printedAt,
      int? branch,
    }) => db.query(
      pg.config,
      'INSERT INTO pos_print_jobs (business_id, branch_id, terminal_id, '
      '  order_id, printer_name, kind, payload, status, queued_at, printed_at) '
      "VALUES (@r, @b, 'T1', @o, 'Front', @kind, decode('00', 'hex'), "
      '  @status, @queued::timestamptz, @printed::timestamptz)',
      parameters: {
        'r': businessId,
        'b': branch ?? branchId,
        'o': orderId,
        'kind': kind,
        'status': printedAt == null ? 'pending' : 'printed',
        'queued': queuedAt.toUtc(),
        'printed': printedAt?.toUtc(),
      },
    );

    Future<void> audit(
      int orderId,
      String action, {
      required DateTime at,
      required String actor,
      String? approver,
    }) => db.query(
      pg.config,
      'INSERT INTO pos_audit_events (business_id, branch_id, actor_name, '
      '  approved_by_name, action, entity_type, entity_id, occurred_at) '
      'VALUES (@r, @b, @actor, @approver, @action, @entity, @id, '
      '  @at::timestamptz)',
      parameters: {
        'r': businessId,
        'b': branchId,
        'actor': actor,
        'approver': approver,
        'action': action,
        'entity': AuditAction.entityOrder,
        'id': '$orderId',
        'at': at.toUtc(),
      },
    );

    test('comes back from four tables in the order it happened', () async {
      final id = await insertOrder(
        invoice: 'EVENTS',
        occurredAt: DateTime(2026, 9, 10, 12),
      );
      final other = await insertOrder(
        invoice: 'OTHER',
        occurredAt: DateTime(2026, 9, 10, 12),
      );
      await pay(id, 1, 26800);

      await printJob(
        id,
        kind: 'receipt',
        queuedAt: DateTime(2026, 9, 10, 12),
        printedAt: DateTime(2026, 9, 10, 12, 0, 5),
      );
      await audit(
        id,
        AuditAction.permissionOverridden,
        at: DateTime(2026, 9, 10, 12, 58),
        actor: 'Nour Adel',
        approver: 'Sami Farid',
      );
      await audit(
        id,
        AuditAction.receiptReprinted,
        at: DateTime(2026, 9, 10, 12, 59),
        actor: 'Nour Adel',
      );
      await printJob(id, kind: 'reprint', queuedAt: DateTime(2026, 9, 10, 13));
      await refund(id, 5000, at: DateTime(2026, 9, 10, 14));
      // Noise that must not appear: another order's audit row and paper.
      await audit(
        other,
        AuditAction.receiptReprinted,
        at: DateTime(2026, 9, 10, 12, 30),
        actor: 'Sami Farid',
      );
      await printJob(
        other,
        kind: 'receipt',
        queuedAt: DateTime(2026, 9, 10, 12, 30),
      );

      final events = (await repository.detail(id))!.events;
      expect(events.map((e) => e.kind), [
        SaleEventKind.printed,
        SaleEventKind.audit,
        SaleEventKind.reprintRequested,
        SaleEventKind.reprintPending,
        SaleEventKind.refunded,
      ]);

      final lent = events[1];
      expect(lent.auditAction, AuditAction.permissionOverridden);
      expect(lent.actorName, 'Nour Adel');
      expect(lent.approvedByName, 'Sami Farid');
      // The paper's time, not the queue's: "printed at 12:00:05" is the claim.
      expect(events.first.at, DateTime(2026, 9, 10, 12, 0, 5));
      expect(events.last.amount!.minor, 5000);
      expect(events.last.actorName, 'Nour Adel');
    });

    test('a void is on the record with who did it', () async {
      final id = await insertOrder(
        invoice: 'VOIDED',
        occurredAt: DateTime(2026, 9, 10, 12),
        status: 'VOIDED',
        voidedBy: samiId,
      );
      final events = (await repository.detail(id))!.events;
      expect(events.map((e) => e.kind), [SaleEventKind.voided]);
      expect(events.single.actorName, 'Sami Farid');
    });

    test('paper printed at another branch for the same id is not ours', () async {
      final id = await insertOrder(
        invoice: 'SCOPED',
        occurredAt: DateTime(2026, 9, 10, 12),
      );
      await printJob(
        id,
        kind: 'receipt',
        queuedAt: DateTime(2026, 9, 10, 12),
        branch: otherBranchId,
      );
      expect((await repository.detail(id))!.events, isEmpty);
    });
  });
}
