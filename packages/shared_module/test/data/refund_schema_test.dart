@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_orders_repository.dart'
    show PosWriteContext;
import 'package:shared_module/data/postgres/postgres_refunds_repository.dart';
import 'package:shared_module/domain/models/order_record.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/refund.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/domain/services/authorization.dart';
import 'package:shared_module/domain/services/refund_engine.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart';

/// Migration 12 — the rules a refund must not be able to break.
///
/// These are asserted against PostgreSQL rather than against Dart on purpose.
/// The claim is not "the repository checks"; it is that **nothing** can write a
/// second refund of a line that was only sold once — not a future repository,
/// not the sync path, not somebody at a psql prompt.
void main() {
  if (PgFixture.host == null) {
    test('refund schema (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late int staffId;
  late int approverId;
  late int reasonId;
  late PostgresRefundsRepository repository;

  const terminal = '11111111-1111-4111-8111-111111111111';

  /// Somebody who may give money back on their own: a supervisor. The
  /// repository asks, so a fixture holding nothing would now be refused — and
  /// a fixture holding a hand-picked grant would test a shape no business
  /// has.
  const refunder = PosRole(
    id: 1,
    code: SystemRoles.supervisorCode,
    nameEn: 'Supervisor',
    capabilities: SystemRoles.supervisor,
  );

  /// Somebody who may not, without a supervisor's approval.
  const counter = PosRole(
    id: 2,
    code: SystemRoles.cashierCode,
    nameEn: 'Cashier',
    capabilities: SystemRoles.cashier,
  );

  /// Hana's approval for one refund of [orderId], as the till's PIN prompt
  /// produces it.
  Approval approvalFor(int orderId) => (Authorization.approve(
    approver: PosStaff(id: approverId, name: 'Hana Mostafa', role: refunder),
    capability: PosCapability.orderRefund,
    subject: '$orderId',
  ) as Allowed).approval!;

  Future<int> insertOrder({
    String invoice = 'INV-1',
    int? branch,
    String status = 'PAID',
    int subtotal = 17500,
    int service = 1750,
    int vat = 2695,
    int total = 21945,
    DateTime? occurredAt,
  }) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_orders (client_transaction_id, business_id, branch_id, '
      '  terminal_id, invoice_number, order_type, currency, exponent, '
      '  subtotal_minor, discount_minor, service_minor, vat_minor, total_minor, '
      '  occurred_at, status) '
      "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @invoice, 'dine_in', 'EGP', "
      '  2, @sub, 0, @svc, @vat, @total, @at::timestamptz, @status) RETURNING id',
      parameters: {
        'r': businessId,
        'b': branch ?? branchId,
        't': terminal,
        'invoice': invoice,
        'sub': subtotal,
        'svc': service,
        'vat': vat,
        'total': total,
        'at': (occurredAt ?? DateTime.now()).toUtc(),
        'status': status,
      },
    );
    return rows.first[0] as int;
  }

  Future<int> insertLine(
    int orderId, {
    String lineKey = 'L1',
    String name = 'Mixed Grill',
    int quantity = 3,
    int unitPrice = 5000,
  }) async {
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_order_lines (order_id, line_key, name_snapshot, quantity, '
      '  unit_price_minor, line_total_minor, stage) '
      "VALUES (@o, @key, @name, @qty, @unit, @tot, 'sent') RETURNING id",
      parameters: {
        'o': orderId,
        'key': lineKey,
        'name': name,
        'qty': quantity,
        'unit': unitPrice,
        'tot': unitPrice * quantity,
      },
    );
    return rows.first[0] as int;
  }

  /// A refund written directly, so a test can ask the database a question the
  /// repository would have refused first.
  Future<int> insertRefund({
    required int orderId,
    required int total,
    int? branch,
    String kind = 'partial',
    int subtotal = 0,
    String? clientId,
    bool tender = true,
  }) async {
    // One transaction, because the tender check is a DEFERRABLE constraint
    // trigger — it fires at commit, and two `db.query` calls are two implicit
    // transactions, so the first would commit a refund nobody had tendered for
    // yet. That the schema refuses exactly that is asserted below.
    return db.runTx(pg.config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_refunds (client_refund_id, business_id, branch_id, '
          '  terminal_id, order_id, kind, subtotal_minor, service_minor, '
          '  vat_minor, total_minor, refunded_by) '
          'VALUES (COALESCE(@client::uuid, gen_random_uuid()), @r, @b, @t::uuid, '
          '  @o, @kind, @sub, 0, 0, @total, @by) RETURNING id',
        ),
        parameters: {
          'client': clientId,
          'r': businessId,
          'b': branch ?? branchId,
          't': terminal,
          'o': orderId,
          'kind': kind,
          'sub': subtotal,
          'total': total,
          'by': staffId,
        },
      );
      final id = rows.first[0] as int;
      if (tender) {
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
            "  amount_minor) VALUES (@r, 1, 'Cash', @amount)",
          ),
          parameters: {'r': id, 'amount': total},
        );
      }
      return id;
    });
  }

  Future<int> orderInt(int orderId, String column) async {
    final rows = await db.query(
      pg.config,
      'SELECT $column FROM pos_orders WHERE id = @id',
      parameters: {'id': orderId},
    );
    return rows.first[0] as int;
  }

  Future<String> orderStatus(int orderId) async {
    final rows = await db.query(
      pg.config,
      'SELECT status FROM pos_orders WHERE id = @id',
      parameters: {'id': orderId},
    );
    return rows.first[0] as String;
  }

  setUp(() async {
    pg = await PgFixture.open('refund_schema');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_refunds, pos_orders, pos_invoice_sequences '
      'RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_businesses (slug, name) "
                  "VALUES ('ref', 'Refunds') RETURNING id",
                ))
                .first[0]
            as int;
    branchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (business_id, code, name) "
                  "VALUES (@r, 'RF1', 'Main') RETURNING id",
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;
    otherBranchId =
        (await db.query(
                  pg.config,
                  "INSERT INTO pos_branches (business_id, code, name) "
                  "VALUES (@r, 'RF2', 'Second') RETURNING id",
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;

    Future<int> staff(String name, String username) async => (await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, @n, @u, 'salt', 'hash') RETURNING id",
      parameters: {
        'r': businessId,
        'b': branchId,
        'n': name,
        'u': username,
      },
    )).first[0] as int;

    staffId = await staff('Nour Adel', 'nour');
    approverId = await staff('Hana Mostafa', 'hana');

    reasonId =
        (await db.query(
                  pg.config,
                  'INSERT INTO pos_reason_codes (business_id, scope, code, '
                  "  name_en) VALUES (@r, 'refund', 'quality', 'Quality problem') "
                  'RETURNING id',
                  parameters: {'r': businessId},
                ))
                .first[0]
            as int;

    repository = PostgresRefundsRepository(
      database: db,
      config: pg.config,
      context: PosWriteContext(
        businessId: businessId,
        branchId: branchId,
        terminalId: terminal,
        branchCode: 'RF1',
      ),
    );
  });

  tearDown(() => pg.close());

  group('the line counter', () {
    test('a refund line bumps refunded_quantity', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId, quantity: 3);
      final refundId = await insertRefund(orderId: orderId, total: 5000);

      await db.query(
        pg.config,
        'INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
        "  unit_price_minor, line_total_minor, name_snapshot) "
        "VALUES (@r, @l, 1, 5000, 5000, 'Mixed Grill')",
        parameters: {'r': refundId, 'l': lineId},
      );

      final rows = await db.query(
        pg.config,
        'SELECT refunded_quantity FROM pos_order_lines WHERE id = @id',
        parameters: {'id': lineId},
      );
      expect(rows.first[0], 1);
    });

    test('refunding more of a line than was sold is refused', () async {
      // The invariant that matters most. Not "the repository checks" — the
      // database refuses the row.
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId, quantity: 2);
      final refundId = await insertRefund(orderId: orderId, total: 5000);

      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
          "  unit_price_minor, line_total_minor, name_snapshot) "
          "VALUES (@r, @l, 3, 5000, 15000, 'Mixed Grill')",
          parameters: {'r': refundId, 'l': lineId},
        ),
        throwsA(anything),
      );
    });

    test('two partial refunds cannot together exceed the quantity', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId, quantity: 2);

      Future<void> refundOne(int refundId) => db.query(
        pg.config,
        'INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
        "  unit_price_minor, line_total_minor, name_snapshot) "
        "VALUES (@r, @l, 1, 5000, 5000, 'Mixed Grill')",
        parameters: {'r': refundId, 'l': lineId},
      );

      await refundOne(await insertRefund(orderId: orderId, total: 5000));
      await refundOne(await insertRefund(orderId: orderId, total: 5000));

      // Two of two are gone. The third is the one that has to fail.
      await expectLater(
        refundOne(await insertRefund(orderId: orderId, total: 5000)),
        throwsA(anything),
      );
    });

    test('a refund line belonging to another order is refused', () async {
      // Not in the original plan. Without the `order_id` clause in the trigger,
      // a mistyped line id refunds somebody else's food and every total still
      // adds up.
      final mine = await insertOrder(invoice: 'MINE');
      final theirs = await insertOrder(invoice: 'THEIRS');
      final theirLine = await insertLine(theirs);
      final refundId = await insertRefund(orderId: mine, total: 5000);

      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
          "  unit_price_minor, line_total_minor, name_snapshot) "
          "VALUES (@r, @l, 1, 5000, 5000, 'Mixed Grill')",
          parameters: {'r': refundId, 'l': theirLine},
        ),
        throwsA(anything),
      );
    });

    test('the same line twice in one refund is refused', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId, quantity: 3);
      final refundId = await insertRefund(orderId: orderId, total: 5000);

      Future<void> add() => db.query(
        pg.config,
        'INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
        "  unit_price_minor, line_total_minor, name_snapshot) "
        "VALUES (@r, @l, 1, 5000, 5000, 'Mixed Grill')",
        parameters: {'r': refundId, 'l': lineId},
      );

      await add();
      await expectLater(add(), throwsA(anything));
    });
  });

  group('the order counter', () {
    test('a refund bumps refunded_minor', () async {
      final orderId = await insertOrder();
      await insertRefund(orderId: orderId, total: 6270);
      expect(await orderInt(orderId, 'refunded_minor'), 6270);
    });

    test('refunding more than the order took is refused', () async {
      final orderId = await insertOrder(total: 21945);
      await expectLater(
        insertRefund(orderId: orderId, total: 30000),
        throwsA(anything),
      );
    });

    test('two refunds cannot together exceed the total', () async {
      final orderId = await insertOrder(total: 10000);
      await insertRefund(orderId: orderId, total: 6000);
      await expectLater(
        insertRefund(orderId: orderId, total: 5000),
        throwsA(anything),
      );
    });

    test('a refund of exactly what is left is allowed', () async {
      final orderId = await insertOrder(total: 10000);
      await insertRefund(orderId: orderId, total: 6000);
      await insertRefund(orderId: orderId, total: 4000);
      expect(await orderInt(orderId, 'refunded_minor'), 10000);
    });
  });

  group('the order status follows the money', () {
    test('a partial refund makes the order partially refunded', () async {
      final orderId = await insertOrder(total: 10000);
      await insertRefund(orderId: orderId, total: 4000);
      expect(await orderStatus(orderId), 'PARTIALLY_REFUNDED');
    });

    test('clearing the balance makes it refunded', () async {
      final orderId = await insertOrder(total: 10000);
      await insertRefund(orderId: orderId, total: 4000);
      await insertRefund(orderId: orderId, total: 6000);
      expect(await orderStatus(orderId), 'REFUNDED');
    });

    test('a refund in one go makes it refunded outright', () async {
      final orderId = await insertOrder(total: 10000);
      await insertRefund(orderId: orderId, total: 10000, kind: 'full');
      expect(await orderStatus(orderId), 'REFUNDED');
    });

    test('nothing in Dart writes the status — the trigger derives it', () async {
      // Nothing in the INSERT above mentions status. If the trigger stopped
      // deriving it, this order would still say PAID while its money was gone.
      final orderId = await insertOrder(total: 10000);
      await insertRefund(orderId: orderId, total: 10000);
      expect(await orderStatus(orderId), isNot('PAID'));
    });
  });

  group('what cannot be refunded at all', () {
    test('a voided order — money that never arrived', () async {
      final orderId = await insertOrder(status: 'VOIDED');
      await expectLater(
        insertRefund(orderId: orderId, total: 1000),
        throwsA(anything),
      );
    });

    test('an order already fully refunded', () async {
      final orderId = await insertOrder(total: 10000);
      await insertRefund(orderId: orderId, total: 10000);
      await expectLater(
        insertRefund(orderId: orderId, total: 1),
        throwsA(anything),
      );
    });

    test('a draft order, which has taken nothing', () async {
      final orderId = await insertOrder(status: 'DRAFT');
      await expectLater(
        insertRefund(orderId: orderId, total: 1000),
        throwsA(anything),
      );
    });

    test('an order at another branch', () async {
      final orderId = await insertOrder(branch: otherBranchId);
      await expectLater(
        insertRefund(orderId: orderId, total: 1000),
        throwsA(anything),
      );
    });

    test('a refund of nothing', () async {
      final orderId = await insertOrder();
      await expectLater(
        insertRefund(orderId: orderId, total: 0),
        throwsA(anything),
      );
    });

    test('a negative refund, which is a sale wearing a disguise', () async {
      final orderId = await insertOrder();
      await expectLater(
        insertRefund(orderId: orderId, total: -1000),
        throwsA(anything),
      );
    });
  });

  group('the tender has to add up', skip: PgFixture.onSqlite ? 'a commit-time constraint trigger; on SQLite the refunds repository checks it' : false, () {
    test('a refund with no tender at all is refused at commit', () async {
      final orderId = await insertOrder();
      await expectLater(
        insertRefund(orderId: orderId, total: 5000, tender: false),
        throwsA(anything),
      );
    });

    test('tender that does not match the refund is refused', () async {
      final orderId = await insertOrder();
      await expectLater(
        db.runTx(pg.config, (tx) async {
          final rows = await tx.execute(
            Sql.named(
              'INSERT INTO pos_refunds (client_refund_id, business_id, '
              '  branch_id, terminal_id, order_id, kind, subtotal_minor, '
              '  service_minor, vat_minor, total_minor, refunded_by) '
              "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, 'partial', "
              '  5000, 0, 0, 5000, @by) RETURNING id',
            ),
            parameters: {
              'r': businessId,
              'b': branchId,
              't': terminal,
              'o': orderId,
              'by': staffId,
            },
          );
          await tx.execute(
            Sql.named(
              'INSERT INTO pos_refund_payments (refund_id, tender_type_id, '
              "  label, amount_minor) VALUES (@r, 1, 'Cash', 4000)",
            ),
            parameters: {'r': rows.first[0]},
          );
        }),
        throwsA(anything),
      );
    });

    test('split tender that adds up is accepted', () async {
      final orderId = await insertOrder();
      await db.runTx(pg.config, (tx) async {
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_refunds (client_refund_id, business_id, '
            '  branch_id, terminal_id, order_id, kind, subtotal_minor, '
            '  service_minor, vat_minor, total_minor, refunded_by) '
            "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @o, 'partial', "
            '  5000, 0, 0, 5000, @by) RETURNING id',
          ),
          parameters: {
            'r': businessId,
            'b': branchId,
            't': terminal,
            'o': orderId,
            'by': staffId,
          },
        );
        final id = rows.first[0];
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_refund_payments (refund_id, tender_type_id, '
            "  label, amount_minor) VALUES (@r, 1, 'Cash', 3000), "
            "  (@r, 2, 'Card', 2000)",
          ),
          parameters: {'r': id},
        );
      });

      expect(await orderInt(orderId, 'refunded_minor'), 5000);
    });
  });

  group('the seeded refund reasons', () {
    test('every business gets the §18 list', () async {
      final rows = await db.query(
        pg.config,
        "SELECT code FROM pos_reason_codes WHERE scope = 'refund' "
        'AND business_id = @r ORDER BY sort_order',
        parameters: {'r': businessId},
      );
      // This business was created after the migration ran, so it has only the
      // one this suite inserted — which is the honest answer, and the reason
      // the seed is written as "only where there are none".
      expect(rows, isNotEmpty);
    });
  });

  group('the repository', () {
    OrderRecord record(int id, {int total = 21945}) => OrderRecord(
      id: id,
      clientTransactionId: 'txn',
      invoiceNumber: 'INV-1',
      status: OrderStatus.paid,
      orderType: OrderType.dineIn,
      occurredAt: DateTime.now(),
      subtotal: const Money(17500),
      discount: Money.zero,
      service: const Money(1750),
      vat: const Money(2695),
      total: Money(total),
    );

    RefundQuote quote({
      int subtotal = 5000,
      int service = 500,
      int vat = 770,
      int total = 6270,
      List<RefundLineSelection> lines = const [],
      RefundKind kind = RefundKind.partial,
      bool requiresApproval = false,
    }) => RefundQuote(
      subtotal: Money(subtotal),
      discount: Money.zero,
      service: Money(service),
      vat: Money(vat),
      total: Money(total),
      kind: kind,
      lines: lines,
      requiresApproval: requiresApproval,
    );

    test('writes the refund, its lines and its tender in one go', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId, quantity: 3);

      final result = await repository.issue(
        order: record(orderId),
        quote: quote(
          lines: [
            RefundLineSelection(
              orderLineId: lineId,
              name: 'Mixed Grill',
              quantity: 1,
              unitPrice: const Money(5000),
            ),
          ],
        ),
        by: PosStaff(id: staffId, name: 'Nour Adel', role: refunder),
        tenders: const [
          RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(6270)),
        ],
        clientRefundId: '22222222-2222-4222-8222-000000000001',
        reasonId: reasonId,
        note: 'Burnt',
      );

      expect(result.replayed, isFalse);
      expect(await orderInt(orderId, 'refunded_minor'), 6270);
      expect(await orderStatus(orderId), 'PARTIALLY_REFUNDED');

      final lines = await db.query(
        pg.config,
        'SELECT refunded_quantity FROM pos_order_lines WHERE id = @id',
        parameters: {'id': lineId},
      );
      expect(lines.first[0], 1);
    });

    test('is idempotent on the client refund id', () async {
      // The contract an order has, applied to money going the other way. A till
      // that retries after a timeout must not hand it back twice.
      final orderId = await insertOrder();
      const clientId = '22222222-2222-4222-8222-000000000002';

      final first = await repository.issue(
        order: record(orderId),
        quote: quote(),
        by: PosStaff(id: staffId, name: 'Nour Adel', role: refunder),
        tenders: const [
          RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(6270)),
        ],
        clientRefundId: clientId,
      );
      final replay = await repository.issue(
        order: record(orderId),
        quote: quote(),
        by: PosStaff(id: staffId, name: 'Nour Adel', role: refunder),
        tenders: const [
          RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(6270)),
        ],
        clientRefundId: clientId,
      );

      expect(replay.replayed, isTrue);
      expect(replay.refundId, first.refundId);
      // The money moved once.
      expect(await orderInt(orderId, 'refunded_minor'), 6270);
    });

    test('reads refunds back with both names, lines and tender', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId, quantity: 3);

      await repository.issue(
        order: record(orderId),
        quote: quote(
          lines: [
            RefundLineSelection(
              orderLineId: lineId,
              name: 'Mixed Grill',
              quantity: 1,
              unitPrice: const Money(5000),
            ),
          ],
        ),
        // A cashier, on Hana's approval for this order: both names, because
        // both people answer for it.
        by: PosStaff(id: staffId, name: 'Nour Adel', role: counter),
        approval: approvalFor(orderId),
        tenders: const [
          RefundTender(
            tenderTypeId: 2,
            label: 'Card',
            amount: Money(6270),
            reference: '4821',
          ),
        ],
        clientRefundId: '22222222-2222-4222-8222-000000000003',
        reasonId: reasonId,
      );

      final refunds = await repository.forOrder(orderId);
      expect(refunds, hasLength(1));

      final refund = refunds.single;
      expect(refund.total.minor, 6270);
      expect(refund.vat.minor, 770);
      expect(refund.kind, RefundKind.partial);
      expect(refund.refundedByName, 'Nour Adel');
      expect(refund.approvedByName, 'Hana Mostafa');
      expect(refund.reasonName, 'Quality problem');
      expect(refund.lines.single.name, 'Mixed Grill');
      expect(refund.lines.single.quantity, 1);
      expect(refund.payments.single.label, 'Card');
      expect(refund.payments.single.reference, '4821');
    });

    test('a refund whose tender does not match is refused, and writes nothing',
        () async {
      final orderId = await insertOrder();

      await expectLater(
        repository.issue(
          order: record(orderId),
          quote: quote(),
          by: PosStaff(id: staffId, name: 'Nour Adel', role: refunder),
          tenders: const [
            RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(1000)),
          ],
          clientRefundId: '22222222-2222-4222-8222-000000000004',
        ),
        throwsA(anything),
      );

      // The whole transaction rolled back. A half-written refund is worse than
      // a refused one.
      expect(await orderInt(orderId, 'refunded_minor'), 0);
      expect(await orderStatus(orderId), 'PAID');
      expect(await repository.forOrder(orderId), isEmpty);
    });

    test('forOrder is empty for an order nobody refunded', () async {
      final orderId = await insertOrder();
      expect(await repository.forOrder(orderId), isEmpty);
    });

    test('refunds come back oldest first, which is the order they happened in',
        () async {
      final orderId = await insertOrder(total: 20000);
      for (var i = 1; i <= 3; i++) {
        await repository.issue(
          order: record(orderId, total: 20000),
          quote: quote(subtotal: 1000, service: 0, vat: 0, total: 1000),
          by: PosStaff(id: staffId, name: 'Nour Adel', role: refunder),
          tenders: const [
            RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(1000)),
          ],
          clientRefundId: '22222222-2222-4222-8222-00000000001$i',
        );
      }

      final refunds = await repository.forOrder(orderId);
      expect(refunds, hasLength(3));
      expect(refunds.first.id, lessThan(refunds.last.id));
      expect(await orderInt(orderId, 'refunded_minor'), 3000);
    });

    // ── Who may give money back ─────────────────────────────────────────────
    //
    // Asked by the repository, not only by the refund sheet. The sheet asks
    // first and brings a supervisor over; these are what holds when something
    // goes round the sheet.

    const cash = [
      RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(6270)),
    ];

    test('a cashier on their own is refused, and nothing is written', () async {
      final orderId = await insertOrder();

      await expectLater(
        repository.issue(
          order: record(orderId),
          quote: quote(),
          by: PosStaff(id: staffId, name: 'Nour Adel', role: counter),
          tenders: cash,
          clientRefundId: '33333333-3333-4333-8333-000000000001',
        ),
        throwsA(isA<PermissionRefused>()),
      );
      expect(await orderInt(orderId, 'refunded_minor'), 0);
      expect(await repository.forOrder(orderId), isEmpty);
    });

    test('an approval given for another order is not an approval for this one',
        () async {
      final orderId = await insertOrder();
      final elsewhere = await insertOrder(invoice: 'INV-2');

      await expectLater(
        repository.issue(
          order: record(orderId),
          quote: quote(),
          by: PosStaff(id: staffId, name: 'Nour Adel', role: counter),
          approval: approvalFor(elsewhere),
          tenders: cash,
          clientRefundId: '33333333-3333-4333-8333-000000000002',
        ),
        throwsA(isA<PermissionRefused>()),
      );
      expect(await repository.forOrder(orderId), isEmpty);
    });

    test('one approval gives back money once', () async {
      // A second refund under a new id is a second act, and needs its own yes.
      final orderId = await insertOrder(total: 20000);
      final approval = approvalFor(orderId);
      final cashier = PosStaff(id: staffId, name: 'Nour Adel', role: counter);

      await repository.issue(
        order: record(orderId, total: 20000),
        quote: quote(subtotal: 1000, service: 0, vat: 0, total: 1000),
        by: cashier,
        approval: approval,
        tenders: const [
          RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(1000)),
        ],
        clientRefundId: '33333333-3333-4333-8333-000000000003',
      );
      await expectLater(
        repository.issue(
          order: record(orderId, total: 20000),
          quote: quote(subtotal: 1000, service: 0, vat: 0, total: 1000),
          by: cashier,
          approval: approval,
          tenders: const [
            RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(1000)),
          ],
          clientRefundId: '33333333-3333-4333-8333-000000000004',
        ),
        throwsA(isA<PermissionRefused>()),
      );
      expect(await orderInt(orderId, 'refunded_minor'), 1000);
    });

    test('above the threshold even a supervisor needs a second person',
        () async {
      final orderId = await insertOrder();
      final supervisor = PosStaff(id: staffId, name: 'Nour Adel', role: refunder);

      await expectLater(
        repository.issue(
          order: record(orderId),
          quote: quote(requiresApproval: true),
          by: supervisor,
          tenders: cash,
          clientRefundId: '33333333-3333-4333-8333-000000000005',
        ),
        throwsA(isA<PermissionRefused>()),
      );

      await repository.issue(
        order: record(orderId),
        quote: quote(requiresApproval: true),
        by: supervisor,
        approval: approvalFor(orderId),
        tenders: cash,
        clientRefundId: '33333333-3333-4333-8333-000000000006',
      );
      expect(
        (await repository.forOrder(orderId)).single.approvedByName,
        'Hana Mostafa',
      );
    });
  });
}
