import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/customer.dart';
import 'package:shared_module/domain/models/customer_summary.dart';

/// What a customer has bought, as the back office reads it.
void main() {
  const person = PosCustomer(id: 1, name: 'Mona', phone: '01012345678');

  CustomerSummary summary({
    int orders = 0,
    int spent = 0,
    int refunded = 0,
    DateTime? last,
  }) => CustomerSummary(
    customer: person,
    orders: orders,
    spent: Money(spent),
    refunded: Money(refunded),
    lastOrderAt: last,
  );

  test('net is what was spent less what was given back', () {
    final s = summary(orders: 3, spent: 30000, refunded: 4500);

    expect(s.net.minor, 25500);
  });

  test('somebody who has never ordered has no purchases and no average', () {
    final s = summary();

    expect(s.hasOrdered, isFalse);
    expect(s.averageOrder, isNull, reason: 'a zero average claims orders');
    expect(s.lastOrderAt, isNull);
  });

  test('the average order is net over orders, rounded once, half-up', () {
    // 100.00 net over 3 orders is 33.333… -> 33.33.
    expect(summary(orders: 3, spent: 10000).averageOrder!.minor, 3333);
    // 100.01 over 2 is 50.005 -> 50.01, half-up.
    expect(summary(orders: 2, spent: 10001).averageOrder!.minor, 5001);
  });

  test('the average is of what they kept, not of what the receipts said', () {
    final s = summary(orders: 2, spent: 20000, refunded: 6000);

    expect(s.averageOrder!.minor, 7000);
  });

  test('refunds beyond what was spent read as negative, not clamped', () {
    // A customer whose refunds exceed this branch's sales — they bought at
    // another branch — is shown as it is rather than hidden.
    final s = summary(orders: 1, spent: 1000, refunded: 1500);

    expect(s.net.minor, -500);
    expect(s.averageOrder!.minor, -500);
  });

  test('one order of a customer is net of its own refund', () {
    final order = CustomerOrder(
      orderId: 9,
      invoiceNumber: 'POS-9',
      occurredAt: DateTime(2026, 9, 10),
      total: const Money(8500),
      refunded: const Money(2500),
    );

    expect(order.net.minor, 6000);
  });
}
