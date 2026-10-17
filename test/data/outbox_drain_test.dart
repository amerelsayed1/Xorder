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
