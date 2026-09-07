import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/ticket.dart';

OrderRecord _order({
  int id = 1,
  OrderStatus status = OrderStatus.paid,
  int total = 10000,
  int refunded = 0,
}) => OrderRecord(
  id: id,
  clientTransactionId: 'txn-$id',
  invoiceNumber: 'INV-$id',
  status: status,
  orderType: OrderType.dineIn,
  occurredAt: DateTime(2026, 9, 7, 13, 5),
  subtotal: Money(total),
  discount: Money.zero,
  service: Money.zero,
  vat: Money.zero,
  total: Money(total),
  refundedTotal: Money(refunded),
);

OrderRecordLine _line({
  int id = 1,
  int quantity = 2,
  int refunded = 0,
  DateTime? voidedAt,
}) => OrderRecordLine(
  id: id,
  lineKey: 'line-$id',
  name: 'Koshari',
  quantity: quantity,
  unitPrice: const Money(5000),
  lineTotal: Money(5000 * quantity),
  refundedQuantity: refunded,
  voidedAt: voidedAt,
);

void main() {
  group('OrderStatus', () {
    test('every member round-trips through its wire value', () {
      for (final status in OrderStatus.values) {
        expect(OrderStatus.fromWire(status.wire), status, reason: status.name);
      }
    });

    test('the wire values are exactly migration 9\'s CHECK constraint', () {
      // Hand-written rather than derived from the enum, deliberately: this test
      // exists to fail when somebody adds a member without adding it to the
      // database, and a list generated from the enum could never do that.
      expect(OrderStatus.values.map((s) => s.wire).toSet(), {
        'DRAFT',
        'OPEN',
        'SENT_TO_KITCHEN',
        'READY',
        'PAID',
        'CLOSED',
        'VOIDED',
        'CANCELLED',
        'REFUNDED',
        'PARTIALLY_REFUNDED',
      });
    });

    test('an unknown wire value is null, not a wrong guess', () {
      expect(OrderStatus.fromWire('SETTLED'), isNull);
      expect(OrderStatus.fromWire(''), isNull);
    });

    test('tookMoney is the set a refund may be issued against', () {
      expect(OrderStatus.paid.tookMoney, isTrue);
      expect(OrderStatus.closed.tookMoney, isTrue);
      // Part of it went back; the rest is still refundable.
      expect(OrderStatus.partiallyRefunded.tookMoney, isTrue);

      expect(OrderStatus.refunded.tookMoney, isFalse);
      expect(OrderStatus.voided.tookMoney, isFalse);
      expect(OrderStatus.draft.tookMoney, isFalse);
      expect(OrderStatus.sentToKitchen.tookMoney, isFalse);
    });

    test('isDead and tookMoney never both hold', () {
      for (final status in OrderStatus.values) {
        expect(
          status.isDead && status.tookMoney,
          isFalse,
          reason: '${status.name} claims to be both',
        );
      }
    });
  });

  group('OrderRecord', () {
    test('netTotal subtracts what has gone back', () {
      expect(_order(total: 10000, refunded: 2500).netTotal.minor, 7500);
    });

    test('netTotal keeps the order currency', () {
      final order = OrderRecord(
        id: 1,
        clientTransactionId: 'txn',
        invoiceNumber: 'INV-1',
        status: OrderStatus.paid,
        orderType: OrderType.takeaway,
        occurredAt: DateTime(2026, 9, 7),
        subtotal: const Money(1000, currency: 'SAR', exponent: 2),
        discount: Money.zero,
        service: Money.zero,
        vat: Money.zero,
        total: const Money(1000, currency: 'SAR', exponent: 2),
        refundedTotal: const Money(400, currency: 'SAR', exponent: 2),
      );
      expect(order.netTotal.currency, 'SAR');
      expect(order.netTotal.minor, 600);
    });

    test('a fully refunded order nets to nothing', () {
      final order = _order(status: OrderStatus.refunded, refunded: 10000);
      expect(order.netTotal.minor, 0);
    });
  });

  group('OrderRecordLine', () {
    test('refundable is what is left after previous refunds', () {
      expect(_line(quantity: 3, refunded: 1).refundableQuantity, 2);
    });

    test('a fully refunded line offers nothing more', () {
      expect(_line(quantity: 2, refunded: 2).refundableQuantity, 0);
    });

    test('a voided line is never refundable', () {
      // Nobody paid for it, so there is nothing to give back. Offering it would
      // hand money over for food that was never charged for.
      final line = _line(quantity: 2, voidedAt: DateTime(2026, 9, 7));
      expect(line.isVoided, isTrue);
      expect(line.refundableQuantity, 0);
    });

    test('a refunded_quantity beyond the line cannot go negative', () {
      // The database forbids this. If it ever arrives anyway, the answer is
      // "nothing left", not a negative quantity that a refund screen would
      // happily turn into money going the wrong way.
      expect(_line(quantity: 2, refunded: 5).refundableQuantity, 0);
    });
  });

  group('OrderRecordDetail', () {
    test('chargedLines omits the voided ones', () {
      final detail = OrderRecordDetail(
        order: _order(),
        lines: [
          _line(id: 1),
          _line(id: 2, voidedAt: DateTime(2026, 9, 7)),
        ],
        payments: const [],
        discounts: const [],
      );
      expect(detail.chargedLines.map((l) => l.id), [1]);
    });

    test('a voided order has nothing refundable, whatever its lines say', () {
      final detail = OrderRecordDetail(
        order: _order(status: OrderStatus.voided),
        lines: [_line(id: 1)],
        payments: const [],
        discounts: const [],
      );
      expect(detail.hasRefundableLines, isFalse);
    });

    test('a paid order with an unrefunded line is refundable', () {
      final detail = OrderRecordDetail(
        order: _order(),
        lines: [_line(id: 1, quantity: 1)],
        payments: const [],
        discounts: const [],
      );
      expect(detail.hasRefundableLines, isTrue);
    });
  });

  group('OrderHistoryQuery', () {
    test('today is midnight to midnight, local', () {
      final query = OrderHistoryQuery.today(
        now: DateTime(2026, 9, 7, 23, 58),
      );
      expect(query.from, DateTime(2026, 9, 7));
      expect(query.to, DateTime(2026, 9, 8));
    });

    test('today at one minute past midnight is still that new day', () {
      final query = OrderHistoryQuery.today(now: DateTime(2026, 9, 8, 0, 1));
      expect(query.from, DateTime(2026, 9, 8));
    });

    test('a date window alone is not a filter', () {
      // Otherwise the empty state would offer "clear filters" on a list that
      // has none, and clearing them would change nothing.
      expect(OrderHistoryQuery.today().isFiltered, isFalse);
    });

    test('whitespace is not a search term', () {
      expect(const OrderHistoryQuery(search: '   ').isFiltered, isFalse);
      expect(const OrderHistoryQuery(search: '24').isFiltered, isTrue);
    });

    test('each filter dimension counts', () {
      expect(
        const OrderHistoryQuery(statuses: {OrderStatus.voided}).isFiltered,
        isTrue,
      );
      expect(
        const OrderHistoryQuery(orderTypes: {OrderType.delivery}).isFiltered,
        isTrue,
      );
      expect(const OrderHistoryQuery(servedByStaffId: 4).isFiltered, isTrue);
    });

    test('copyWith clears rather than merges when asked', () {
      const query = OrderHistoryQuery(servedByStaffId: 7);
      expect(query.copyWith(clearServedBy: true).servedByStaffId, isNull);
      // Without the flag, null means "leave it alone" — otherwise every
      // copyWith that did not mention staff would silently drop the filter.
      expect(query.copyWith().servedByStaffId, 7);
    });
  });
}
