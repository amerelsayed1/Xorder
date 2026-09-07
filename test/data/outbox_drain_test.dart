import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/cloud/cloud_api.dart';
import 'package:xorder_pos/data/cloud/outbox_drain.dart';

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
          serviceMinor: 3000,
          vatMinor: 3920,
          totalMinor: 31920,
          catalogSyncedAt: DateTime.utc(2026, 9, 2, 8),
          lines: [
            OutboxDrain.lineJson(
              menuItemId: 101,
              nameSnapshot: 'Classic Burger',
              optionIds: [71, 72],
              quantity: 2,
              unitPriceMinor: 9500,
              note: 'no onions',
            ),
          ],
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
      expect(totals['charges_minor'], 3000);
      expect(totals['tax_minor'], 3920);
      expect(totals['total_minor'], 31920);
      // Asserted, never instructed — and every one an int, never a double.
      expect(totals.values.every((v) => v is int), isTrue);

      final line = (request['lines'] as List).single as Map<String, Object?>;
      expect(line['menu_item_id'], 101);
      expect(line['option_ids'], [71, 72]);
      expect(line['quantity'], 2);
      expect(line['unit_price_minor'], 9500);
      expect(line['name_snapshot'], 'Classic Burger');
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
}
