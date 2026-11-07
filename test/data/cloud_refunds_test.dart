@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/cloud/cloud_api.dart';
import 'package:xorder_pos/data/cloud/outbox_drain.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart'
    show PosWriteContext;
import 'package:xorder_pos/data/postgres/postgres_refunds_repository.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/refund_engine.dart';

import 'pg_fixture.dart';

/// A cloud till uploads its refunds (POS-BE-010).
///
/// **The defect behind this file.** Until 2026-09-22 the drain answered
/// `'refund' => null` for every queued refund, and the writer never queued one
/// — so a cloud business's platform totals counted every sale and no money
/// handed back. The reason was real: a refund names lines, and the till had
/// only its own `pos_order_lines.id` while the platform wanted
/// `order_items.id`. §010 closed it by accepting the till's own name for a
/// line on the way in (`lines[].client_line_id`) and accepting it again on the
/// way back out, so the whole mapping is now one string in two places.
void main() {
  if (PgFixture.host == null) {
    test('cloud refunds (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late DeploymentConfig cloud;
  late int businessId;
  late int branchId;
  late int staffId;
  late int approverId;
  late int reasonId;

  /// The platform's Cash, at the local row id the seeder would have given it.
  late int platformCash;

  const terminal = '5f1b0a7c-4d3e-4f2a-9b8c-1a2b3c4d5e6f';

  var invoice = 0;

  /// Somebody who may give money back on their own. A fixture with no role at
  /// all would be refused by the repository, and one with a hand-picked grant
  /// would test a shape no business has.
  const refunder = PosRole(
    id: 1,
    code: SystemRoles.supervisorCode,
    nameEn: 'Supervisor',
    capabilities: SystemRoles.supervisor,
  );

  PosStaff nour() => PosStaff(id: staffId, name: 'Nour Adel', role: refunder);

  setUp(() async {
    pg = await PgFixture.open('cloud_refunds');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(
      pg.config,
      'TRUNCATE pos_refunds, pos_orders, pos_outbox, pos_sync_outbox, '
      'pos_invoice_sequences, pos_shifts RESTART IDENTITY CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    cloud = pg.config.copyWith(mode: DeploymentMode.cloud);
    invoice = 0;

    businessId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_businesses (slug, name) "
              "VALUES ('cloudref', 'Cloud Refunds') RETURNING id",
            )).first[0]
            as int;
    branchId =
        (await db.query(
              pg.config,
              "INSERT INTO pos_branches (business_id, code, name) "
              "VALUES (@r, 'MAADI', 'Maadi') RETURNING id",
              parameters: {'r': businessId},
            )).first[0]
            as int;

    Future<int> staff(String name, String username) async => (await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, branch_id, name, username, '
      "  pin_salt, pin_hash) VALUES (@r, @b, @n, @u, 'salt', 'hash') RETURNING id",
      parameters: {'r': businessId, 'b': branchId, 'n': name, 'u': username},
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
            )).first[0]
            as int;

    // The platform's tender, written as the bootstrap seeder writes it:
    // `platform_id` set, `code = 'platform-<id>'`, and a local row id past the
    // compiled-in fallback's ceiling. Inserted rather than seeded from a
    // bundle because what the seeder does with a bundle is
    // `cloud_tenders_test`'s claim, not this file's — here it is only the
    // starting condition.
    await db.query(pg.config, "SELECT setval('pos_tender_types_id_seq', 4)");
    platformCash =
        (await db.query(
              pg.config,
              'INSERT INTO pos_tender_types (business_id, platform_id, code, '
              "  name_en, kind, counts_as_cash) "
              "VALUES (@r, 2, 'platform-2', 'Cash', 'cash', true) RETURNING id",
              parameters: {'r': businessId},
            )).first[0]
            as int;
  });

  tearDown(() => pg.close());

  // ── The local rows a cloud till would have ────────────────────────────────

  Future<int> insertOrder({int total = 20000, String status = 'PAID'}) async {
    invoice++;
    return (await db.query(
          pg.config,
          'INSERT INTO pos_orders (client_transaction_id, business_id, '
          '  branch_id, terminal_id, invoice_number, order_type, currency, '
          '  exponent, subtotal_minor, discount_minor, service_minor, '
          '  vat_minor, total_minor, occurred_at, status) '
          "VALUES (gen_random_uuid(), @r, @b, @t::uuid, @invoice, 'dine_in', "
          "  'EGP', 2, @total, 0, 0, 0, @total, now(), @status) RETURNING id",
          parameters: {
            'r': businessId,
            'b': branchId,
            't': terminal,
            'invoice': 'T1-${invoice.toString().padLeft(6, '0')}',
            'total': total,
            'status': status,
          },
        )).first[0]
        as int;
  }

  Future<int> insertLine(
    int orderId, {
    String lineKey = '101:',
    String name = 'Mixed Grill',
    int quantity = 2,
    int unitPrice = 5000,
  }) async => (await db.query(
    pg.config,
    'INSERT INTO pos_order_lines (order_id, line_key, menu_item_id, '
    '  name_snapshot, quantity, unit_price_minor, line_total_minor, stage) '
    "VALUES (@o, @key, 101, @name, @qty, @unit, @total, 'sent') RETURNING id",
    parameters: {
      'o': orderId,
      'key': lineKey,
      'name': name,
      'qty': quantity,
      'unit': unitPrice,
      'total': unitPrice * quantity,
    },
  )).first[0] as int;

  /// The sale's own outbox claim, as `PostgresOrdersRepository` writes it.
  Future<int> queueSale(int orderId, {int? tenderTypeId, int amount = 20000}) async {
    await db.query(
      pg.config,
      'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
      "  amount_minor) VALUES (@o, @type, 'Cash', @amount)",
      parameters: {
        'o': orderId,
        'type': tenderTypeId ?? platformCash,
        'amount': amount,
      },
    );
    return (await db.query(
          pg.config,
          'INSERT INTO pos_outbox (order_id, client_transaction_id, '
          '  business_id, branch_id) '
          'SELECT id, client_transaction_id, business_id, branch_id '
          'FROM pos_orders WHERE id = @o RETURNING id',
          parameters: {'o': orderId},
        )).first[0]
        as int;
  }

  PostgresRefundsRepository repositoryOn({
    PosDatabase? database,
    DeploymentConfig? config,
  }) => PostgresRefundsRepository(
    database: database ?? db,
    config: config ?? cloud,
    context: PosWriteContext(
      businessId: businessId,
      branchId: branchId,
      terminalId: terminal,
      branchCode: 'MAADI',
    ),
  );

  OrderRecord record(int id, {int total = 20000}) => OrderRecord(
    id: id,
    clientTransactionId: 'unused-by-the-writer',
    invoiceNumber: 'T1-000001',
    status: OrderStatus.paid,
    orderType: OrderType.dineIn,
    occurredAt: DateTime.now(),
    subtotal: Money(total),
    discount: Money.zero,
    service: Money.zero,
    vat: Money.zero,
    total: Money(total),
  );

  /// One refund of [quantity] off [lineId], tendered back in full.
  Future<RefundResult> issueRefund({
    required int orderId,
    int? lineId,
    int quantity = 1,
    int amount = 5000,
    int? tenderTypeId,
    String clientRefundId = '77777777-7777-4777-8777-000000000001',
    PostgresRefundsRepository? on,
  }) => (on ?? repositoryOn()).issue(
    order: record(orderId),
    quote: RefundQuote(
      subtotal: Money(amount),
      discount: Money.zero,
      service: Money.zero,
      vat: Money.zero,
      total: Money(amount),
      kind: RefundKind.partial,
      lines: [
        if (lineId != null)
          RefundLineSelection(
            orderLineId: lineId,
            name: 'Mixed Grill',
            quantity: quantity,
            unitPrice: Money(amount ~/ quantity),
          ),
      ],
      requiresApproval: false,
    ),
    by: nour(),
    tenders: [
      RefundTender(
        tenderTypeId: tenderTypeId ?? platformCash,
        label: 'Cash',
        amount: Money(amount),
      ),
    ],
    clientRefundId: clientRefundId,
    reasonId: reasonId,
    note: 'Burnt',
  );

  Future<(DrainReport, _RecordingApi)> drain({
    _RecordingApi? api,
    PosDatabase? database,
    DeploymentConfig? config,
  }) async {
    final client = api ?? _RecordingApi();
    final report = await OutboxDrain(
      database: database ?? db,
      config: config ?? cloud,
      api: client,
    ).run();
    return (report, client);
  }

  Future<List<Object?>> syncRow(String clientId) async => (await db.query(
    pg.config,
    'SELECT delivered_at, quarantined_at, quarantine_code, last_error, '
    '       attempts, event_type, source_id '
    'FROM pos_sync_outbox WHERE client_transaction_id = @c::uuid',
    parameters: {'c': clientId},
  )).first;

  // ── What goes out with a sale ─────────────────────────────────────────────

  group('an order line names itself', () {
    test('every line carries its local id as client_line_id', () async {
      final orderId = await insertOrder();
      final first = await insertLine(orderId);
      final second = await insertLine(orderId, name: 'Kofta');
      await queueSale(orderId);

      final (report, api) = await drain();

      expect(report.delivered, 1);
      final lines = (api.orders.single['lines'] as List)
          .cast<Map<String, Object?>>();
      expect(lines.map((l) => l['client_line_id']), ['$first', '$second']);
    });

    test('two lines of the same dish are told apart, which line_key cannot do',
        () async {
      // The reason `client_line_id` is the row id and not `line_key`. A sent
      // line plus a new draft of the same dish are two rows with the same key,
      // and the platform indexes unique(order_id, client_line_id) — so a key
      // here would make a perfectly valid order a constraint failure.
      final orderId = await insertOrder();
      final first = await insertLine(orderId, lineKey: '101:');
      final second = await insertLine(orderId, lineKey: '101:');
      await queueSale(orderId);

      final (_, api) = await drain();

      final lines = (api.orders.single['lines'] as List)
          .cast<Map<String, Object?>>();
      expect(lines.map((l) => l['client_line_id']), ['$first', '$second']);
      expect(first, isNot(second));
    });
  });

  // ── What goes out with a refund ───────────────────────────────────────────

  group('the refund the writer queued', () {
    test('is claimed in the same transaction as the refund itself', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      final result = await issueRefund(orderId: orderId, lineId: lineId);

      final row = await syncRow(result.clientRefundId);
      expect(row[5], 'refund');
      expect(row[6], result.refundId);
      expect(row[0], isNull, reason: 'owed, not yet delivered');
      // One key for one act: the refund's own idempotency key is the queue's,
      // so a replayed refund cannot queue a second delivery.
      expect(result.clientRefundId, '77777777-7777-4777-8777-000000000001');
    });

    test('an offline till queues nothing — there is nowhere to send it',
        () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await issueRefund(
        orderId: orderId,
        lineId: lineId,
        on: repositoryOn(config: pg.config),
      );

      expect(
        await db.query(pg.config, 'SELECT count(*) FROM pos_sync_outbox'),
        [
          [0],
        ],
      );
    });

    test('drains as §010\'s request, and nothing else', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      final orderClientId = (await db.query(
        pg.config,
        'SELECT client_transaction_id FROM pos_orders WHERE id = @o',
        parameters: {'o': orderId},
      )).first[0].toString();
      final result = await issueRefund(orderId: orderId, lineId: lineId);

      final (report, api) = await drain();

      expect(report.delivered, 2, reason: 'the sale, then the refund');
      expect(report.quarantined, 0);
      expect(report.deferred, 0);

      final sent = api.refunds.single;
      expect(sent['client_transaction_id'], result.clientRefundId);
      // The order's OWN key. The platform id is on the sale's reply, which a
      // refund written during the same outage never saw.
      expect(sent['order_id'], orderClientId);
      expect(sent['kind'], 'refund');
      expect(sent['reason'], 'quality');
      expect(sent['acting_user_id'], staffId);
      expect(sent['authorized_by_user_id'], isNull);
      expect(sent['shift_client_id'], isNull);
      expect(sent['occurred_at'], isA<String>());
      expect((sent['lines'] as List).single, {
        'client_line_id': '$lineId',
        'quantity': 1,
        'amount_minor': 5000,
      });
      // The PLATFORM's tender id, never the till's own row id — the same rule
      // a payment obeys, because a card refund booked as cash is a drawer
      // that is short.
      expect((sent['tenders'] as List).single, {
        'tender_type_id': 2,
        'amount_minor': 5000,
      });
      expect(
        platformCash,
        isNot(2),
        reason: 'otherwise the two ids agree by accident and prove nothing',
      );

      expect((await syncRow(result.clientRefundId))[0], isNotNull);
    });

    test('names both people when two of them answer for it', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      // Written straight in: the approval path itself is `refund_schema_test`'s
      // claim. What matters here is that a row with an approver puts the
      // approver on the wire.
      await db.runTx(cloud, (tx) async {
        final rows = await tx.execute(
          _insertRefundSql,
          parameters: {
            'r': businessId,
            'b': branchId,
            't': terminal,
            'o': orderId,
            'by': staffId,
            'approver': approverId,
            'client': '77777777-7777-4777-8777-000000000009',
            'total': 5000,
          },
        );
        final id = rows.first[0] as int;
        await tx.execute(
          _insertRefundPartsSql,
          parameters: {'refund': id, 'line': lineId, 'type': platformCash},
        );
        await tx.execute(_insertRefundClaimSql, parameters: {
          'r': businessId,
          'b': branchId,
          'source': id,
          'client': '77777777-7777-4777-8777-000000000009',
        });
      });

      final (_, api) = await drain();

      expect(api.refunds.single['acting_user_id'], staffId);
      expect(api.refunds.single['authorized_by_user_id'], approverId);
    });

    test('keeps the platform\'s credit note number', () async {
      // Kept for the same reason a sale keeps the platform's invoice number:
      // it comes out of the platform's own CN- sequence, so the till cannot
      // derive it, and it is what an auditor asks for.
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      final result = await issueRefund(orderId: orderId, lineId: lineId);

      await drain();

      final rows = await db.query(
        pg.config,
        'SELECT server_credit_note_number FROM pos_refunds WHERE id = @id',
        parameters: {'id': result.refundId},
      );
      expect(rows.first[0], 'CN-MAADI-2026-000001');
    });
  });

  // ── Ordering: a refund cannot precede its sale ────────────────────────────

  group('a refund waits for its sale', () {
    test('defers while the sale is still owed, and goes on the next pass',
        () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      final result = await issueRefund(orderId: orderId, lineId: lineId);

      // A refusal whose cure is time, so the sale stays queued.
      final refusing = _RecordingApi(
        orderReply: const CloudReply(status: 503, body: {}),
      );
      final (held, _) = await drain(api: refusing);

      expect(refusing.refunds, isEmpty, reason: 'nothing was said about it');
      expect(held.delivered, 0);
      expect(held.deferred, 2, reason: 'the sale, and the refund behind it');
      var row = await syncRow(result.clientRefundId);
      expect(row[1], isNull, reason: 'not held for a person');
      expect(row[4], 0, reason: 'attempts count conversations; there was none');
      expect(row[3] as String?, contains('Waiting for the sale'));

      final (through, api) = await drain();
      expect(through.delivered, 2);
      expect(api.refunds, hasLength(1));
      row = await syncRow(result.clientRefundId);
      expect(row[0], isNotNull);
    });

    test('waits, rather than being held too, when the sale is held', () async {
      // Whoever unsticks the sale should not then have to find this row as
      // well. Deferring is self-healing; quarantining would need a second act.
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      // Paid on one of the till's own tenders, which is what the order drain
      // quarantines before it sends anything.
      await queueSale(orderId, tenderTypeId: 1);
      final result = await issueRefund(orderId: orderId, lineId: lineId);

      final (report, api) = await drain();

      expect(api.orders, isEmpty);
      expect(api.refunds, isEmpty);
      expect(report.quarantined, 1, reason: 'the sale');
      expect(report.deferred, 1, reason: 'the refund');
      final row = await syncRow(result.clientRefundId);
      expect(row[1], isNull);
      expect(row[3] as String?, contains('held for a person'));
    });

    test('is held when the sale was never queued at all', () async {
      // An order taken before this till became a cloud till. Nothing will ever
      // enqueue it, so the platform will never have an order to name — and no
      // pass can cure that.
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      final result = await issueRefund(orderId: orderId, lineId: lineId);

      final (report, api) = await drain();

      expect(api.refunds, isEmpty);
      expect(report.quarantined, 1);
      final row = await syncRow(result.clientRefundId);
      expect(row[2], 'SALE_NEVER_QUEUED');
      expect(row[3] as String?, contains('never queued'));
    });
  });

  // ── Refusals ──────────────────────────────────────────────────────────────

  group('what is held rather than sent', () {
    test('REFUND_EXCEEDS_SOLD holds the refund for a person', () async {
      // The ceiling only ever comes down, so retrying is a queue that never
      // empties behind a record that will never be accepted.
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      final result = await issueRefund(orderId: orderId, lineId: lineId);

      final (report, api) = await drain(
        api: _RecordingApi(
          refundReply: const CloudReply(
            status: 422,
            body: {
              'code': 'REFUND_EXCEEDS_SOLD',
              'message': 'already refunded',
            },
          ),
        ),
      );

      expect(api.refunds, hasLength(1), reason: 'it was tried once');
      expect(report.quarantined, 1);
      final row = await syncRow(result.clientRefundId);
      expect(row[0], isNull, reason: 'never marked delivered');
      expect(row[2], 'REFUND_EXCEEDS_SOLD');
      expect(row[4], 1, reason: 'one conversation with the platform');
    });

    test('a refund given as an amount off the bill is held, not attributed',
        () async {
      // `RefundEngine.quoteForAmount` attaches no lines on purpose: nobody
      // said which food the money was for. §010 requires lines that balance
      // the tender, so the only alternative to holding it is inventing an
      // attribution — which would move `refunded_quantity` on the platform for
      // a line the operator never chose.
      final orderId = await insertOrder();
      await insertLine(orderId);
      await queueSale(orderId);
      final result = await issueRefund(orderId: orderId);

      final (report, api) = await drain();

      expect(api.refunds, isEmpty, reason: 'not even attempted');
      expect(report.quarantined, 1);
      final row = await syncRow(result.clientRefundId);
      expect(row[2], OutboxDrain.refundHasNoLines);
      expect(row[4], 0, reason: 'the platform was never asked');
      expect(row[3] as String?, contains('amount off the bill'));
    });

    test('a refund handed back on a tender the platform never sent is held',
        () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      final result = await issueRefund(
        orderId: orderId,
        lineId: lineId,
        // The compiled-in fallback Cash: a real local id on this till, and
        // meaningless to the platform.
        tenderTypeId: 1,
      );

      final (report, api) = await drain();

      expect(api.refunds, isEmpty);
      expect(report.quarantined, 1);
      final row = await syncRow(result.clientRefundId);
      expect(row[2], OutboxDrain.tenderNotFromPlatform);
      expect(row[3] as String?, contains('payment method 1 on this till'));
    });

    test('a queue row whose refund is not the one it names is held', () async {
      // A hand-written or half-migrated row. Held loudly rather than sent with
      // somebody else's money on it.
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      final result = await issueRefund(orderId: orderId, lineId: lineId);
      await db.query(
        pg.config,
        'UPDATE pos_sync_outbox SET source_id = source_id + 1000 '
        'WHERE client_transaction_id = @c::uuid',
        parameters: {'c': result.clientRefundId},
      );

      final (report, api) = await drain();

      expect(api.refunds, isEmpty);
      expect(report.quarantined, 1);
      expect((await syncRow(result.clientRefundId))[2], 'LOCAL_SOURCE_MISSING');
    });
  });

  // ── Replay ────────────────────────────────────────────────────────────────

  group('a replay is harmless', () {
    test('the same refund twice is one record, one claim, one upload',
        () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);

      final first = await issueRefund(orderId: orderId, lineId: lineId);
      final again = await issueRefund(orderId: orderId, lineId: lineId);

      expect(again.replayed, isTrue);
      expect(again.refundId, first.refundId);
      expect(
        await db.query(
          pg.config,
          "SELECT count(*) FROM pos_sync_outbox WHERE event_type = 'refund'",
        ),
        [
          [1],
        ],
      );

      final (report, api) = await drain();
      expect(report.delivered, 2);
      expect(api.refunds, hasLength(1));

      // And a second pass sends nothing: `delivered_at` is set, never cleared.
      final (quiet, second) = await drain();
      expect(second.refunds, isEmpty);
      expect(second.orders, isEmpty);
      expect(quiet.attempted, 0);
    });

    test('a platform 200 replay is a delivery like any other', () async {
      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      final result = await issueRefund(orderId: orderId, lineId: lineId);

      final (report, _) = await drain(
        api: _RecordingApi(
          // What §010 answers when the till already sent this one and lost the
          // reply — byte-identical to the 201, at status 200.
          refundReply: const CloudReply(
            status: 200,
            body: {
              'data': {
                'id': 12,
                'credit_note_number': 'CN-MAADI-2026-000001',
              },
            },
          ),
        ),
      );

      expect(report.delivered, 2);
      expect(report.quarantined, 0);
      final row = await syncRow(result.clientRefundId);
      expect(row[0], isNotNull);
      expect(
        (await db.query(
          pg.config,
          'SELECT server_credit_note_number FROM pos_refunds WHERE id = @id',
          parameters: {'id': result.refundId},
        )).first[0],
        'CN-MAADI-2026-000001',
      );
    });
  });

  // ── The credential a real install runs on ─────────────────────────────────

  // ── Which drawer the money left ───────────────────────────────────────────

  group('the shift a refund is stamped with', () {
    // The same fault the audit of 17 Oct 2026 found on sales: the repository
    // used to capture the open shift's id when it was built, and a till that
    // closes one shift and opens the next without restarting went on naming
    // the first. The repository here is built BEFORE either shift exists.
    test('is the one open when it is issued, not when the repository was built',
        () async {
      await db.query(
        pg.config,
        "INSERT INTO pos_terminals (id, business_id, branch_id, name) "
        "VALUES (@t::uuid, @r, @b, 'Counter 1')",
        parameters: {'t': terminal, 'r': businessId, 'b': branchId},
      );
      final repository = repositoryOn();

      Future<int> openShift() async => (await db.query(
        pg.config,
        'INSERT INTO pos_shifts (business_id, branch_id, terminal_id, opened_by) '
        'VALUES (@r, @b, @t::uuid, @by) RETURNING id',
        parameters: {
          'r': businessId,
          'b': branchId,
          't': terminal,
          'by': staffId,
        },
      )).first[0] as int;

      final first = await openShift();
      await db.query(
        pg.config,
        'UPDATE pos_shifts SET closed_at = now(), counted_cash_minor = 0, '
        '  expected_cash_minor = 0, variance_minor = 0, closed_by = @by '
        'WHERE id = @id',
        parameters: {'by': staffId, 'id': first},
      );
      final second = await openShift();

      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      final result = await issueRefund(
        orderId: orderId,
        lineId: lineId,
        on: repository,
      );

      final stamped = await db.query(
        pg.config,
        'SELECT shift_id FROM pos_refunds WHERE id = @id',
        parameters: {'id': result.refundId},
      );
      expect(stamped.first[0], second);
    });
  });

  group('the till\'s own credential', () {
    test('writes the claim and stores the credit note number', () async {
      // Every other test here runs as the superuser, who needs no grant, so
      // every other test would pass on an install where this is refused. The
      // refund writer now inserts into `pos_sync_outbox` and the drain now
      // UPDATEs `pos_refunds.server_credit_note_number`; neither was on the
      // till's list before today.
      final role = PgFixture.roleFor('cloud_refund_probe');
      const password = 'probe-only';
      await _dropRole(db, pg, role);
      addTearDown(() => _dropRole(db, pg, role));
      await db.query(
        pg.config,
        'CREATE ROLE "$role" LOGIN PASSWORD \'$password\'',
      );
      for (final statement in LocalBootstrap.tillGrants(
        database: pg.config.databaseName,
        role: role,
        cloudSeeding: true,
      )) {
        await db.query(pg.config, statement);
      }

      final till = PosDatabase(credentials: InMemoryPosDbCredentials(password));
      addTearDown(till.close);
      final tillConfig = cloud.copyWith(databaseUser: role);

      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      await queueSale(orderId);
      final result = await issueRefund(
        orderId: orderId,
        lineId: lineId,
        on: repositoryOn(database: till, config: tillConfig),
      );

      final (report, api) = await drain(
        database: till,
        config: tillConfig,
      );

      expect(report.delivered, 2);
      expect(api.refunds, hasLength(1));
      expect(
        (await db.query(
          pg.config,
          'SELECT server_credit_note_number FROM pos_refunds WHERE id = @id',
          parameters: {'id': result.refundId},
        )).first[0],
        'CN-MAADI-2026-000001',
      );
    });

    test('still cannot rewrite what the refund was for', () async {
      // The grant is column-scoped. If it were table-wide, a recovered till
      // credential could rewrite a refund's total or the order it names.
      final role = PgFixture.roleFor('cloud_refund_probe');
      const password = 'probe-only';
      await _dropRole(db, pg, role);
      addTearDown(() => _dropRole(db, pg, role));
      await db.query(
        pg.config,
        'CREATE ROLE "$role" LOGIN PASSWORD \'$password\'',
      );
      for (final statement in LocalBootstrap.tillGrants(
        database: pg.config.databaseName,
        role: role,
        cloudSeeding: true,
      )) {
        await db.query(pg.config, statement);
      }

      final till = PosDatabase(credentials: InMemoryPosDbCredentials(password));
      addTearDown(till.close);
      final tillConfig = cloud.copyWith(databaseUser: role);

      final orderId = await insertOrder();
      final lineId = await insertLine(orderId);
      final result = await issueRefund(
        orderId: orderId,
        lineId: lineId,
        on: repositoryOn(database: till, config: tillConfig),
      );

      await expectLater(
        till.query(
          tillConfig,
          'UPDATE pos_refunds SET total_minor = 1 WHERE id = @id',
          parameters: {'id': result.refundId},
        ),
        throwsA(anything),
      );
    });
  });
}

/// A refund written straight in, for the one test that needs an approver on the
/// row without going through the approval flow.
final _insertRefundSql = Sql.named(
  'INSERT INTO pos_refunds (client_refund_id, business_id, branch_id, '
  '  terminal_id, order_id, kind, subtotal_minor, service_minor, vat_minor, '
  '  total_minor, refunded_by, approved_by_id) '
  "VALUES (@client::uuid, @r, @b, @t::uuid, @o, 'partial', @total, 0, 0, "
  '  @total, @by, @approver) RETURNING id',
);

final _insertRefundPartsSql = Sql.named(
  'WITH line AS ('
  '  INSERT INTO pos_refund_lines (refund_id, order_line_id, quantity, '
  '    unit_price_minor, line_total_minor, name_snapshot) '
  "  VALUES (@refund, @line, 1, 5000, 5000, 'Mixed Grill') RETURNING 1) "
  'INSERT INTO pos_refund_payments (refund_id, tender_type_id, label, '
  "  amount_minor) SELECT @refund, @type, 'Cash', 5000 FROM line",
);

final _insertRefundClaimSql = Sql.named(
  'INSERT INTO pos_sync_outbox (business_id, branch_id, event_type, '
  "  source_id, client_transaction_id) "
  "VALUES (@r, @b, 'refund', @source, @client::uuid)",
);

/// Records what would have gone to the platform, and answers as configured.
class _RecordingApi extends PosCloudApi {
  _RecordingApi({this.orderReply, this.refundReply})
    : super(baseUrl: 'http://127.0.0.1:9');

  final CloudReply? orderReply;
  final CloudReply? refundReply;

  final orders = <Map<String, Object?>>[];
  final refunds = <Map<String, Object?>>[];

  @override
  Future<CloudReply> submitOrder(Map<String, Object?> request) async {
    orders.add(request);
    return orderReply ??
        CloudReply(
          status: 201,
          body: {
            'data': {
              'id': 8800 + orders.length,
              'invoice_number': 'MAADI-2026-001042',
            },
          },
        );
  }

  @override
  Future<CloudReply> submitRefund(Map<String, Object?> request) async {
    refunds.add(request);
    return refundReply ??
        const CloudReply(
          status: 201,
          body: {
            'data': {
              'id': 12,
              'credit_note_number': 'CN-MAADI-2026-000001',
            },
          },
        );
  }
}

/// Same as the grant suites': grants must go before the role can.
Future<void> _dropRole(PosDatabase db, PgFixture pg, String role) async {
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
