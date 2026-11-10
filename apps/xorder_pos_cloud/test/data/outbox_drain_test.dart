import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:xorder_pos_cloud/data/cloud/outbox_drain.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_sync_queue_repository.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

void main() {
  group('OutboxDrain.buildOrderRequest', () {
    Map<String, Object?> sample() => OutboxDrain.buildOrderRequest(
          clientTransactionId: '3f2b9d0e-1111-2222-3333-444455556666',
          branchId: 3,
          orderType: 'dine_in',
          tableId: 12,
          actingUserId: 9,
          currency: 'EGP',
          exponent: 2,
          occurredAt: DateTime.utc(2026, 9, 2, 13, 5),
          subtotalMinor: 25000,
          discountMinor: 1500,
          serviceMinor: 3000,
          vatMinor: 3920,
          totalMinor: 31920,
          catalogSyncedAt: DateTime.utc(2026, 9, 2, 8),
          lines: [
            OutboxDrain.lineJson(
              menuItemId: 101,
              clientLineId: '4471',
              nameSnapshot: 'Classic Burger',
              optionIds: [71, 72],
              quantity: 2,
              unitPriceMinor: 9500,
              note: 'no onions',
              discount: const {
                'amount_minor': 500,
                'reason': 'manager_comp',
              },
              priceOverride: const {
                'unit_price_minor': 9000,
                'reason': 'damaged',
              },
            ),
          ],
          orderDiscount: const {
            'amount_minor': 1000,
            'reason': 'staff_meal',
          },
          payments: const [
            {
              'client_transaction_id': 'p-1',
              'tender_type_id': 1,
              'amount_minor': 31920,
              'reference': null,
              'received_at': '2026-09-02T13:06:00.000Z',
            },
          ],
        );

    test('matches the agreed §006 envelope', () {
      final request = sample();

      expect(request['client_transaction_id'],
          '3f2b9d0e-1111-2222-3333-444455556666');
      expect(request['branch_id'], 3);
      expect(request['order_type'], 'dine_in');
      expect(request['table_id'], 12);
      expect(request['acting_user_id'], 9);
      expect(request['priced_offline'], isTrue);
      expect(request['created_at'], '2026-09-02T13:05:00.000Z');

      final totals = request['asserted_totals'] as Map<String, Object?>;
      expect(totals['subtotal_minor'], 25000);
      expect(totals['discount_minor'], 1500);
      expect(totals['charges_minor'], 3000);
      expect(totals['tax_minor'], 3920);
      expect(totals['total_minor'], 31920);
      // Asserted, never instructed — and every one an int, never a double.
      expect(totals.values.every((v) => v is int), isTrue);

      final line = (request['lines'] as List).single as Map<String, Object?>;
      expect(line['menu_item_id'], 101);
      // POS-BE-010: the till's own name for the line, and the only way a
      // refund built during an outage can address it.
      expect(line['client_line_id'], '4471');
      expect(line['option_ids'], [71, 72]);
      expect(line['quantity'], 2);
      expect(line['unit_price_minor'], 9500);
      expect(line['name_snapshot'], 'Classic Burger');
      expect(line['discount'], {
        'amount_minor': 500,
        'reason': 'manager_comp',
      });
      expect(line['price_override'], {
        'unit_price_minor': 9000,
        'reason': 'damaged',
      });
      expect(request['order_discount'], {
        'amount_minor': 1000,
        'reason': 'staff_meal',
      });
    });

    test('never emits a JSON float anywhere in the envelope', () {
      bool holdsNoDouble(Object? node) => switch (node) {
            double() => false,
            final Map map => map.values.every(holdsNoDouble),
            final List list => list.every(holdsNoDouble),
            _ => true,
          };
      expect(holdsNoDouble(sample()), isTrue);
    });

    test('attribution is nullable per the v1 relaxation', () {
      final request = OutboxDrain.buildOrderRequest(
        clientTransactionId: 'txn',
        branchId: 1,
        orderType: 'takeaway',
        currency: 'EGP',
        exponent: 2,
        occurredAt: DateTime.utc(2026),
        subtotalMinor: 0,
        serviceMinor: 0,
        vatMinor: 0,
        totalMinor: 0,
        lines: const [],
        payments: const [],
      );
      expect(request['acting_user_id'], isNull);
      expect(request['shift_client_id'], isNull);
      expect(request['table_id'], isNull);
      // A walk-in sends no customer at all, not a null one.
      expect(request.containsKey('customer_id'), isFalse);
    });

    test('a sale for a customer names them by the platform id (G2)', () {
      final request = OutboxDrain.buildOrderRequest(
        clientTransactionId: 'txn',
        branchId: 1,
        orderType: 'takeaway',
        currency: 'EGP',
        exponent: 2,
        occurredAt: DateTime.utc(2026),
        subtotalMinor: 0,
        serviceMinor: 0,
        vatMinor: 0,
        totalMinor: 0,
        lines: const [],
        payments: const [],
        customerId: 501,
      );
      expect(request['customer_id'], 501);
    });
  });

  group('OutboxDrain.buildRefundRequest', () {
    Map<String, Object?> sample() => OutboxDrain.buildRefundRequest(
          clientTransactionId: '9c1d0e2f-5555-4666-8777-888899990000',
          orderClientId: '3f2b9d0e-1111-2222-3333-444455556666',
          occurredAt: DateTime.utc(2026, 9, 22, 14),
          reason: 'quality',
          actingUserId: 9,
          authorizedByUserId: 4,
          shiftClientId: 'aaaa1111-2222-4333-8444-555566667777',
          lines: [
            OutboxDrain.refundLineJson(
              orderLineId: 4471,
              quantity: 1,
              amountMinor: 9500,
            ),
          ],
          tenders: const [
            {'tender_type_id': 2, 'amount_minor': 9500},
          ],
        );

    test('matches the agreed §010 envelope', () {
      final request = sample();

      expect(request['client_transaction_id'],
          '9c1d0e2f-5555-4666-8777-888899990000');
      // The ORDER'S own key, not a platform id — §010 detects the UUID by
      // format, and the platform id is the thing an offline refund has not
      // seen.
      expect(request['order_id'], '3f2b9d0e-1111-2222-3333-444455556666');
      expect(request['kind'], 'refund');
      expect(request['reason'], 'quality');
      expect(request['acting_user_id'], 9);
      expect(request['authorized_by_user_id'], 4);
      expect(request['shift_client_id'], 'aaaa1111-2222-4333-8444-555566667777');
      expect(request['occurred_at'], '2026-09-22T14:00:00.000Z');

      final line = (request['lines'] as List).single as Map<String, Object?>;
      expect(line, {
        'client_line_id': '4471',
        'quantity': 1,
        'amount_minor': 9500,
      });
      expect((request['tenders'] as List).single, {
        'tender_type_id': 2,
        'amount_minor': 9500,
      });
    });

    test('the refund line names itself exactly one way', () {
      // §010 refuses a line carrying both `order_item_id` and
      // `client_line_id`, and refuses one carrying neither.
      final line = (sample()['lines'] as List).single as Map<String, Object?>;
      expect(line.containsKey('client_line_id'), isTrue);
      expect(line.containsKey('order_item_id'), isFalse);
    });

    test('kind is never the local full/partial word', () {
      // `pos_refunds.kind` is `full | partial`; §010's axis is
      // `refund | void`, and it derives full-vs-partial from its own counters.
      // Sending the local word would be a 422 on every refund.
      expect(sample()['kind'], isNot(anyOf('full', 'partial')));
    });

    test('never emits a JSON float anywhere in the envelope', () {
      bool holdsNoDouble(Object? node) => switch (node) {
            double() => false,
            final Map map => map.values.every(holdsNoDouble),
            final List list => list.every(holdsNoDouble),
            _ => true,
          };
      expect(holdsNoDouble(sample()), isTrue);
    });

    test('attribution is nullable, as it is on a sale', () {
      final request = OutboxDrain.buildRefundRequest(
        clientTransactionId: 'txn',
        orderClientId: 'order',
        occurredAt: DateTime.utc(2026),
        lines: const [],
        tenders: const [],
      );
      expect(request['acting_user_id'], isNull);
      expect(request['authorized_by_user_id'], isNull);
      expect(request['shift_client_id'], isNull);
      expect(request['reason'], isNull);
    });
  });

  group('per-payment client ids', () {
    test('are stable across passes and distinct across rows', () {
      // A retry after a timeout must present the same key, or the platform
      // records the money twice — the exact failure POS-BE-007 exists for.
      final first = OutboxDrain.paymentClientId(
          orderClientId: 'order-a', paymentRowId: 1);
      final again = OutboxDrain.paymentClientId(
          orderClientId: 'order-a', paymentRowId: 1);
      final sibling = OutboxDrain.paymentClientId(
          orderClientId: 'order-a', paymentRowId: 2);
      final otherOrder = OutboxDrain.paymentClientId(
          orderClientId: 'order-b', paymentRowId: 1);

      expect(again, first);
      expect(sibling, isNot(first));
      expect(otherOrder, isNot(first));
      // A well-formed UUID, so the server's uuid validation accepts it.
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$')
            .hasMatch(first),
        isTrue,
      );
    });
  });

  group('OutboxDrain.classify', () {
    test('condemns the record only when the record is at fault', () {
      expect(OutboxDrain.classify('VALIDATION_FAILED'), DrainAction.quarantine);
      expect(OutboxDrain.classify('MENU_ITEM_NOT_FOUND'), DrainAction.quarantine);
      expect(OutboxDrain.classify('IDEMPOTENCY_PAYLOAD_MISMATCH'),
          DrainAction.quarantine);
      expect(OutboxDrain.classify('BRANCH_NOT_IN_TENANT'), DrainAction.quarantine);
      // §010: the platform's counters say this refund is over the ceiling, in
      // quantity or in money. The ceiling only ever comes down, so no amount
      // of waiting turns this into a yes.
      expect(OutboxDrain.classify('REFUND_EXCEEDS_SOLD'), DrainAction.quarantine);
    });

    test('a missing capability defers — a manager can still grant it', () {
      // Deliberate, and the opposite of REFUND_EXCEEDS_SOLD: the record is
      // fine and the person is not yet allowed. Granting `pos.refund` on the
      // dashboard makes the next pass succeed, so quarantining would demand a
      // second act from somebody who had already done the first.
      expect(OutboxDrain.classify('POS_CAPABILITY_MISSING'), DrainAction.defer);
    });

    test('defers tenant-, terminal- and moment-shaped refusals', () {
      expect(OutboxDrain.classify('POS_FEATURE_DISABLED'), DrainAction.defer);
      expect(OutboxDrain.classify('SUBSCRIPTION_LAPSED'), DrainAction.defer);
      expect(OutboxDrain.classify('TERMINAL_REVOKED'), DrainAction.defer);
    });

    test('an unrecognised or missing code is retried, never discarded', () {
      // The client's standing POS-BE-019 rule: a new server code must never
      // strand money on a till that predates it.
      expect(OutboxDrain.classify('SOME_FUTURE_CODE'), DrainAction.defer);
      expect(OutboxDrain.classify(null), DrainAction.defer);
    });
  });

  group('CloudReply', () {
    test('separates "said no" from "said nothing"', () {
      const refused = CloudReply(status: 422, body: {'code': 'VALIDATION_FAILED'});
      const silent = CloudReply.offline();

      expect(refused.ok, isFalse);
      expect(refused.offline, isFalse);
      expect(refused.code, 'VALIDATION_FAILED');
      expect(silent.offline, isTrue);
      expect(silent.code, isNull);
    });

    test('unwraps a Laravel data envelope and tolerates its absence', () {
      const wrapped = CloudReply(status: 201, body: {
        'data': {'id': 8814, 'invoice_number': 'MAADI-2026-001042'},
      });
      const bare = CloudReply(status: 200, body: {'id': 7});

      expect(wrapped.data['invoice_number'], 'MAADI-2026-001042');
      expect(bare.data['id'], 7);
    });
  });

  group('a 2xx that proves nothing (D4)', () {
    PosCloudApi answering(String body, int status, {String? contentType}) =>
        PosCloudApi(
          baseUrl: 'http://127.0.0.1:9',
          client: Dio(BaseOptions(validateStatus: (_) => true))
            ..httpClientAdapter = _ScriptedPlatform.always(
              body,
              status,
              contentType: contentType,
            ),
        );

    test('a body that is not a JSON object is a reply, but not a parsed one',
        () async {
      const portal = '<html><body>Sign in to Hotel Wi-Fi</body></html>';
      final page = await answering(portal, 200, contentType: 'text/html')
          .submitOrder(const {'client_transaction_id': 'txn'});
      final nothing = await answering('', 200, contentType: 'text/html')
          .submitOrder(const {'client_transaction_id': 'txn'});
      final empty = await answering('{}', 200)
          .submitOrder(const {'client_transaction_id': 'txn'});

      // `ok` keeps its meaning for every other caller; `parsed` is the news.
      expect(page.ok, isTrue);
      expect(page.offline, isFalse, reason: 'something did answer');
      expect(page.parsed, isFalse);
      expect(nothing.ok, isTrue);
      expect(nothing.parsed, isFalse);
      expect(empty.ok, isTrue);
      expect(empty.parsed, isTrue, reason: '`{}` is an object, just an empty one');
    });

    test('a refusal served as a page is still deferred, not mistaken for '
        'silence', () async {
      final reply = await answering('<html>502</html>', 502,
              contentType: 'text/html')
          .submitOrder(const {'client_transaction_id': 'txn'});

      expect(reply.offline, isFalse);
      expect(reply.ok, isFalse);
      expect(reply.code, isNull);
      expect(OutboxDrain.classify(reply.code), DrainAction.defer);
    });

    test('only the platform\'s order id acknowledges a sale', () {
      expect(
        OutboxDrain.acknowledgesOrder(const CloudReply.malformed(200)),
        isFalse,
        reason: 'a login page',
      );
      expect(
        OutboxDrain.acknowledgesOrder(const CloudReply(status: 200, body: {})),
        isFalse,
        reason: 'an object with nothing in it',
      );
      expect(
        OutboxDrain.acknowledgesOrder(
          const CloudReply(status: 201, body: {
            'data': {'invoice_number': 'MAADI-2026-001042'},
          }),
        ),
        isFalse,
        reason: 'an invoice number with no order behind it',
      );
      expect(
        OutboxDrain.acknowledgesOrder(
          const CloudReply(status: 201, body: {
            'data': {'id': 8814, 'invoice_number': null},
          }),
        ),
        isTrue,
        reason: '§006 lets the invoice number be null; the id it promises',
      );
      expect(
        OutboxDrain.acknowledgesOrder(
          const CloudReply(status: 422, body: {
            'data': {'id': 8814},
          }),
        ),
        isFalse,
        reason: 'and a refusal is never an acknowledgement, whatever it carries',
      );
    });

    test('a lifecycle record needs at least a JSON object', () {
      expect(
        OutboxDrain.acknowledgesRecord(const CloudReply.malformed(201)),
        isFalse,
      );
      expect(
        OutboxDrain.acknowledgesRecord(const CloudReply(status: 201, body: {})),
        isTrue,
        reason: 'a shift open tells the till nothing it keeps',
      );
      expect(
        OutboxDrain.acknowledgesRecord(const CloudReply.offline()),
        isFalse,
      );
    });
  });

  group('the drain on a network that answers with a page (D4)', () {
    if (PgFixture.host == null) {
      test('skipped — set POS_PG_HOST to run', () {}, skip: true);
      return;
    }

    late PgFixture pg;
    late SqlDatabase db;
    late DeploymentConfig cloud;
    late int businessId;
    var invoice = 0;

    const branchId = 3;
    const terminalId = '0c9adf1e-9e3f-4a2e-b8a5-6a1f6f0f2f10';
    const accepted =
        '{"data":{"id":8814,"invoice_number":"MAADI-2026-001042"}}';

    setUp(() async {
      pg = await PgFixture.open('outbox_drain');
      db = pg.database;
      await PosMigrator(db).migrate(pg.config);
      await pg.truncate();
      await db.query(pg.config, 'DELETE FROM pos_businesses');
      cloud = pg.config.copyWith(mode: DeploymentMode.cloud);
      businessId = (await db.query(
        pg.config,
        "INSERT INTO pos_businesses (slug, name) VALUES ('cloud', 'Cloud') "
        'RETURNING id',
      )).first[0]! as int;
    });

    tearDown(() => pg.close());

    /// One settled sale with no payments, queued — the smallest row the drain
    /// will send. Returns the outbox id and the key the platform sees.
    Future<({int outboxId, String client})> queueSale({int? customerId}) async {
      invoice++;
      final orderId = (await db.query(
        pg.config,
        '''
        INSERT INTO pos_orders (client_transaction_id, business_id, branch_id,
          terminal_id, invoice_number, order_type, currency, exponent,
          subtotal_minor, service_minor, vat_minor, total_minor, occurred_at,
          customer_id)
        VALUES (gen_random_uuid(), @r, @b, @t, @invoice, 'takeaway', 'EGP', 2,
          10000, 0, 1400, 11400, now(), @customer)
        RETURNING id
        ''',
        parameters: {
          'r': businessId,
          'b': branchId,
          't': terminalId,
          'invoice': 'MAADI-${invoice.toString().padLeft(6, '0')}',
          'customer': customerId,
        },
      )).first[0]! as int;
      final row = (await db.query(
        pg.config,
        'INSERT INTO pos_outbox (order_id, client_transaction_id, business_id, '
        '  branch_id) SELECT id, client_transaction_id, business_id, branch_id '
        'FROM pos_orders WHERE id = @o '
        'RETURNING id, client_transaction_id::text',
        parameters: {'o': orderId},
      )).first;
      return (outboxId: row[0]! as int, client: row[1]! as String);
    }

    Future<List<Object?>> outboxRow(int id) async => (await db.query(
      pg.config,
      'SELECT delivered_at, quarantined_at, last_error, attempts, '
      '       last_attempt_at, server_order_id '
      'FROM pos_outbox WHERE id = @id',
      parameters: {'id': id},
    )).first;

    Future<DrainReport> drain(_ScriptedPlatform platform) => OutboxDrain(
      database: db,
      config: cloud,
      api: PosCloudApi(
        baseUrl: 'http://127.0.0.1:9',
        client: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = platform,
      ),
    ).run();

    /// A customer in the till's directory: [platformId] null is one created at
    /// the counter that has not reached the platform; [queued] puts its record
    /// in the sync queue the way the customers repository does. Returns the
    /// local id and the key its upload carries.
    Future<({int id, String client})> customer({
      int? platformId,
      bool queued = false,
    }) async {
      final row = (await db.query(
        pg.config,
        'INSERT INTO pos_customers (business_id, platform_id, '
        '  client_transaction_id, name, phone) '
        "VALUES (@r, @p, gen_random_uuid(), 'عامر السيد', '01001234567') "
        'RETURNING id, client_transaction_id::text',
        parameters: {'r': businessId, 'p': platformId},
      )).first;
      final id = row[0]! as int;
      if (queued) {
        // The sales above never needed the branch row; the sync queue's
        // foreign key does.
        await db.query(
          pg.config,
          'INSERT INTO pos_branches (id, business_id, code, name) '
          "VALUES (@b, @r, 'MAADI', 'Maadi') ON CONFLICT (id) DO NOTHING",
          parameters: {'b': branchId, 'r': businessId},
        );
        await db.query(
          pg.config,
          'INSERT INTO pos_sync_outbox (business_id, branch_id, event_type, '
          '  source_id, client_transaction_id) '
          "SELECT business_id, @b, 'customer', id, client_transaction_id "
          'FROM pos_customers WHERE id = @id',
          parameters: {'b': branchId, 'id': id},
        );
      }
      return (id: id, client: row[1]! as String);
    }

    Map<String, Object?> orderSent(_ScriptedPlatform platform, String client) =>
        platform.sent.lastWhere(
          (body) =>
              body['client_transaction_id'] == client &&
              body.containsKey('lines'),
        );

    test('a sale names its customer by the platform id, a walk-in by none '
        '(G2)', () async {
      final known = await customer(platformId: 501);
      final forKnown = await queueSale(customerId: known.id);
      final walkIn = await queueSale();

      final platform = _ScriptedPlatform({
        forKnown.client: (accepted, Headers.jsonContentType),
        walkIn.client: (accepted, Headers.jsonContentType),
      });
      final report = await drain(platform);

      expect(report.delivered, 2);
      expect(orderSent(platform, forKnown.client)['customer_id'], 501,
          reason: 'the platform id, never the local row ${known.id}');
      expect(orderSent(platform, walkIn.client).containsKey('customer_id'),
          isFalse);
    });

    test('a sale waits behind a customer still on its way up, then names '
        'them (G2)', () async {
      final fresh = await customer(queued: true);
      final sale = await queueSale(customerId: fresh.id);

      // The customer's upload meets a captive portal: still queued, so the
      // sale must not go — and must not go with the local id either.
      final first = _ScriptedPlatform({
        fresh.client: ('<html>Wi-Fi</html>', 'text/html'),
        sale.client: (accepted, Headers.jsonContentType),
      });
      final report = await drain(first);
      expect(report.delivered, 0);
      expect(first.sent.where((b) => b.containsKey('lines')), isEmpty);
      final waiting = await outboxRow(sale.outboxId);
      expect(waiting[0], isNull, reason: 'not delivered');
      expect(waiting[1], isNull, reason: 'not held for a person');
      expect(waiting[2], OutboxDrain.customerNotYetOnPlatform);

      // Next pass the customer lands first, and the sale names them.
      final second = _ScriptedPlatform({
        fresh.client: ('{"data":{"id":777}}', Headers.jsonContentType),
        sale.client: (accepted, Headers.jsonContentType),
      });
      final next = await drain(second);
      expect(next.delivered, 2, reason: 'the customer, then the sale');
      expect(orderSent(second, sale.client)['customer_id'], 777);
      final row = await outboxRow(sale.outboxId);
      expect(row[0], isNotNull);
      expect(row[2], isNull);
    });

    test('a customer held for a person does not hold the money: the sale '
        'goes as a walk-in (G2)', () async {
      final stuck = await customer(queued: true);
      await db.query(
        pg.config,
        "UPDATE pos_sync_outbox SET quarantined_at = now(), "
        "quarantine_code = 'VALIDATION_FAILED' WHERE source_id = @id "
        "AND event_type = 'customer'",
        parameters: {'id': stuck.id},
      );
      final sale = await queueSale(customerId: stuck.id);

      final platform = _ScriptedPlatform({
        sale.client: (accepted, Headers.jsonContentType),
      });
      final report = await drain(platform);

      expect(report.delivered, 1);
      expect(orderSent(platform, sale.client).containsKey('customer_id'),
          isFalse);
    });

    test('only the reply that carries the order back marks it delivered',
        () async {
      final page = await queueSale();
      final empty = await queueSale();
      final real = await queueSale();

      final report = await drain(
        _ScriptedPlatform({
          page.client: (
            '<html><body>Sign in to Hotel Wi-Fi</body></html>',
            'text/html',
          ),
          empty.client: ('{}', Headers.jsonContentType),
          real.client: (accepted, Headers.jsonContentType),
        }),
      );

      expect(report.delivered, 1);
      expect(report.deferred, 2);
      expect(report.quarantined, 0);
      expect(report.wentOffline, isFalse, reason: 'a page is not silence');

      for (final deferred in [page, empty]) {
        final row = await outboxRow(deferred.outboxId);
        expect(row[0], isNull, reason: 'never marked delivered');
        expect(row[1], isNull, reason: 'never held for a person');
        expect(row[2], OutboxDrain.malformedAck);
        expect(row[2], 'MALFORMED_ACK');
        expect(row[3], 1, reason: 'one conversation, counted');
        expect(row[4], isNotNull);
        expect(row[5], isNull);
      }

      final delivered = await outboxRow(real.outboxId);
      expect(delivered[0], isNotNull);
      expect(delivered[2], isNull);
      expect(delivered[5], 8814);
    });

    test('a deferred sale goes on the next pass over a real connection',
        () async {
      final sale = await queueSale();

      await drain(
        _ScriptedPlatform({sale.client: ('', 'text/html')}),
      );
      expect((await outboxRow(sale.outboxId))[0], isNull);

      final report = await drain(
        _ScriptedPlatform({sale.client: (accepted, Headers.jsonContentType)}),
      );

      expect(report.delivered, 1);
      final row = await outboxRow(sale.outboxId);
      expect(row[0], isNotNull);
      expect(row[2], isNull, reason: 'the stale MALFORMED_ACK is cleared');
      expect(row[3], 2);
      expect(row[5], 8814);
    });

    test('a held sale is skipped until somebody releases it, and goes on the '
        'next pass after (D1)', () async {
      final sale = await queueSale();
      // What a pass that met `422 MENU_ITEM_NOT_FOUND` left behind: the
      // product was deleted on the dashboard after the sale was rung up.
      await db.query(
        pg.config,
        '''
        UPDATE pos_outbox
           SET quarantined_at = now(), quarantine_code = 'MENU_ITEM_NOT_FOUND',
               last_error = '422 MENU_ITEM_NOT_FOUND', attempts = 1
         WHERE id = @id
        ''',
        parameters: {'id': sale.outboxId},
      );

      // The platform would take it now — the product is back — but nobody
      // has said so, and the drain must not decide that for itself.
      final skipped = await drain(
        _ScriptedPlatform({sale.client: (accepted, Headers.jsonContentType)}),
      );
      expect(skipped.attempted, 0);
      expect((await outboxRow(sale.outboxId))[3], 1, reason: 'not tried');

      final queue = PostgresSyncQueueRepository(
        database: db,
        config: cloud,
        businessId: businessId,
        branchId: branchId,
        terminalId: terminalId,
      );
      final [held] = await queue.listHeldSync();
      final released = await queue.releaseHeldSync(
        held,
        by: const PosStaff(
          id: 0,
          name: 'Amer M.',
          role: PosRole(
            id: 1,
            code: 'owner',
            nameEn: 'Owner',
            capabilities: {PosCapability.terminalManage},
          ),
        ),
      );
      expect(released.succeeded, isTrue);

      final report = await drain(
        _ScriptedPlatform({sale.client: (accepted, Headers.jsonContentType)}),
      );

      expect(report.delivered, 1);
      final row = await outboxRow(sale.outboxId);
      expect(row[0], isNotNull, reason: 'delivered');
      expect(row[1], isNull, reason: 'no longer held');
      expect(row[3], 2, reason: 'the first refusal, and this acceptance');
      expect(row[5], 8814);
    });
  });

  // The platform answers 422 to a shift close whose count differs from the
  // expected cash IT worked out, unless a reason comes with it, and the drain
  // quarantines a 422 for good. Found in the 17 Oct 2026 audit: the till never
  // sent a reason, so the first close the two sides disagreed about stayed open
  // on the dashboard forever. The till has no note field today, so what goes
  // out has to make sense without one.
  group('OutboxDrain.shiftCloseReason', () {
    test('is the cashier\'s own words when there are some', () {
      expect(
        OutboxDrain.shiftCloseReason(
          note: 'Short 5 EGP, change given twice',
          countedMinor: 99500,
          expectedMinor: 100000,
          varianceMinor: -500,
        ),
        'Short 5 EGP, change given twice',
      );
    });

    test('trims the note, and treats an empty one as no note', () {
      expect(
        OutboxDrain.shiftCloseReason(
          note: '  counted twice  ',
          countedMinor: 1,
          expectedMinor: 0,
          varianceMinor: 1,
        ),
        'counted twice',
      );

      final blank = OutboxDrain.shiftCloseReason(
        note: '   ',
        countedMinor: 452000,
        expectedMinor: 452000,
        varianceMinor: 0,
      );
      expect(blank, isNotEmpty);
      expect(blank, contains('No cashier note'));
    });

    test('without a note, states the till\'s own figures so the platform can compare',
        () {
      final reason = OutboxDrain.shiftCloseReason(
        note: null,
        countedMinor: 452000,
        expectedMinor: 400000,
        varianceMinor: 52000,
      );

      expect(reason, contains('counted 452000'));
      expect(reason, contains('expected 400000'));
      expect(reason, contains('variance 52000'));
    });

    test('never exceeds the 255 characters the platform accepts', () {
      final reason = OutboxDrain.shiftCloseReason(
        note: 'x' * 400,
        countedMinor: 0,
        expectedMinor: 0,
        varianceMinor: 0,
      );

      expect(reason.runes.length, 255);
    });

    test('counts characters, so a long Arabic or emoji note is not cut in half', () {
      final reason = OutboxDrain.shiftCloseReason(
        note: '😀' * 300,
        countedMinor: 0,
        expectedMinor: 0,
        varianceMinor: 0,
      );

      expect(reason.runes.length, 255);
      expect(reason.runes.every((r) => r == 0x1F600), isTrue);
    });
  });
}

/// A platform — or whatever stands between the till and it — answering each
/// order by its `client_transaction_id`, always with a 200. Below Dio rather
/// than above [PosCloudApi], so the body goes through the same decoding a
/// captive portal's page would.
class _ScriptedPlatform implements HttpClientAdapter {
  _ScriptedPlatform(this.byClient) : _always = null;

  _ScriptedPlatform.always(String body, int status, {String? contentType})
    : byClient = const {},
      _always = (body, status, contentType ?? Headers.jsonContentType);

  final Map<String, (String body, String contentType)> byClient;
  final (String, int, String)? _always;

  /// Every request body this platform was sent, in order.
  final sent = <Map<String, Object?>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.data case final Map data) {
      sent.add(Map<String, Object?>.from(data));
    }
    final (body, status, contentType) =
        _always ??
        switch (byClient[(options.data as Map)['client_transaction_id']]) {
          (final scripted, final type) => (scripted, 200, type),
          // An order this script did not expect is a broken test, not a
          // platform answer: fail loudly rather than invent a reply.
          null => throw StateError('unscripted order ${options.data}'),
        };
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
