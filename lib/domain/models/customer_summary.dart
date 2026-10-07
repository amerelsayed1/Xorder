/// A customer as the back office reads them: who they are, and what they have
/// bought here.
///
/// **This branch's sales only, and settled ones.** A till reads its own branch
/// and no other, so the order count and what was spent are the sales rung up at
/// this branch; a voided or open order is not a purchase. Refunds are taken off
/// what was spent rather than ignored: a regular who returned half of last
/// week's order has not spent what the receipt said.
library;

import '../../core/money/money.dart';
import 'customer.dart';

class CustomerSummary {
  const CustomerSummary({
    required this.customer,
    required this.orders,
    required this.spent,
    required this.refunded,
    this.lastOrderAt,
  });

  final PosCustomer customer;

  /// Settled orders at this branch that name this customer.
  final int orders;

  /// What those orders came to, before refunds.
  final Money spent;

  /// What was given back against them.
  final Money refunded;

  /// When they last bought here. Null for a customer who has never ordered —
  /// somebody added to the directory by a phone call, or arrived in the
  /// platform's bundle — which is shown as "never", not as a date.
  final DateTime? lastOrderAt;

  /// [spent] less [refunded]: what they actually left with the restaurant.
  Money get net => spent - refunded;

  bool get hasOrdered => orders > 0;

  /// What an average order of theirs came to, net, half-up and rounded once.
  /// Null with no orders: a zero average is a claim about orders, and there
  /// were none.
  Money? get averageOrder => orders == 0
      ? null
      : net.copyWith(minor: _halfUp(net.minor, orders));

  static int _halfUp(int numerator, int denominator) => numerator >= 0
      ? (numerator * 2 + denominator) ~/ (denominator * 2)
      : -((-numerator * 2 + denominator) ~/ (denominator * 2));
}

/// One order of a customer's, for the list under their name.
class CustomerOrder {
  const CustomerOrder({
    required this.orderId,
    required this.invoiceNumber,
    required this.occurredAt,
    required this.total,
    required this.refunded,
  });

  final int orderId;

  /// What is printed on the receipt. May be a provisional, terminal-scoped
  /// reference while the platform's number has not come back.
  final String invoiceNumber;

  final DateTime occurredAt;
  final Money total;
  final Money refunded;

  Money get net => total - refunded;
}
