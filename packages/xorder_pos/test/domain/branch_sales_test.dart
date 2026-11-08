import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';

/// §3a's rules that live in Dart: rule 3's classification, rule 5's net, and
/// rule 1 as the branch being read off its rows.
void main() {
  MethodTotal method(
    TenderKind kind,
    int amount, {
    bool cash = false,
    String? label,
    int? id,
  }) => MethodTotal(
    tenderTypeId: id ?? kind.index + 1,
    label: label ?? kind.wire,
    kind: kind,
    countsAsCash: cash,
    count: 1,
    amount: Money(amount),
  );

  TerminalSales row(
    String id, {
    int orders = 0,
    int gross = 0,
    int discounts = 0,
    int refunds = 0,
    List<MethodTotal> payments = const [],
  }) => TerminalSales(
    terminalId: id,
    name: id,
    orders: orders,
    gross: Money(gross),
    discounts: Money(discounts),
    refunds: Money(refunds),
    refundCount: refunds > 0 ? 1 : 0,
    payments: payments,
  );

  group('rule 3 — which figure a payment lands in', () {
    test('on account is never collected, even if somebody flagged it as cash', () {
      expect(
        PaymentBucket.of(kind: TenderKind.account, countsAsCash: true),
        PaymentBucket.onAccount,
      );
      expect(PaymentBucket.onAccount.isCollected, isFalse);
    });

    test('card and wallet are electronic; the cash flag decides cash', () {
      expect(
        PaymentBucket.of(kind: TenderKind.card, countsAsCash: false),
        PaymentBucket.electronic,
      );
      expect(
        PaymentBucket.of(kind: TenderKind.wallet, countsAsCash: false),
        PaymentBucket.electronic,
      );
      expect(
        PaymentBucket.of(kind: TenderKind.cash, countsAsCash: true),
        PaymentBucket.cash,
      );
      // Cash is what the drawer was judged against, and that is the flag.
      expect(
        PaymentBucket.of(kind: TenderKind.cash, countsAsCash: false),
        PaymentBucket.other,
      );
      expect(
        PaymentBucket.of(kind: TenderKind.voucher, countsAsCash: false),
        PaymentBucket.other,
      );
    });

    test('a terminal collects everything except on account', () {
      final till = row(
        'POS-01',
        gross: 92345,
        payments: [
          method(TenderKind.cash, 30000, cash: true),
          method(TenderKind.card, 20000),
          method(TenderKind.wallet, 30000),
          method(TenderKind.account, 12345),
        ],
      );
      expect(till.cash, const Money(30000));
      expect(till.electronic, const Money(50000));
      expect(till.onAccount, const Money(12345));
      expect(till.collected, const Money(80000));
    });
  });

  test('rule 5 — net is gross less discounts less refunds', () {
    final till = row('POS-02', gross: 31000, discounts: 1000, refunds: 7000);
    expect(till.net, const Money(23000));
  });

  group('rule 1 — the branch is its rows', () {
    final sales = BranchSales(
      branchId: 3,
      businessDay: DateTime(2026, 9, 10),
      terminals: [
        row(
          'POS-01',
          orders: 2,
          gross: 67345,
          discounts: 5000,
          payments: [
            method(TenderKind.cash, 30000, cash: true),
            method(TenderKind.card, 20000),
            method(TenderKind.account, 12345),
          ],
        ),
        row(
          'POS-02',
          orders: 1,
          gross: 31000,
          discounts: 1000,
          refunds: 7000,
          payments: [
            method(TenderKind.card, 5000),
            method(TenderKind.wallet, 25000),
          ],
        ),
        row('POS-03'),
      ],
    );

    test('every branch figure equals the sum of the terminal rows', () {
      Money sum(Money Function(TerminalSales) f) =>
          sales.terminals.fold(Money.zero, (s, t) => s + f(t));

      expect(sales.orders, 3);
      expect(sales.gross, const Money(98345));
      expect(sales.discounts, const Money(6000));
      expect(sales.refunds, const Money(7000));
      expect(sales.net, const Money(85345));
      expect(sales.net, sales.gross - sales.discounts - sales.refunds);
      expect(sales.net, sum((t) => t.net));
      expect(sales.collected, const Money(80000));
      expect(sales.onAccount, const Money(12345));
    });

    test('payments by method merge across terminals and reconcile', () {
      final byMethod = sales.paymentsByMethod;
      final card = byMethod.singleWhere((m) => m.kind == TenderKind.card);
      expect(card.amount, const Money(25000));
      expect(card.count, 2);

      final all = byMethod.fold(Money.zero, (s, m) => s + m.amount);
      expect(
        all,
        sales.cash + sales.electronic + sales.onAccount + sales.otherTender,
      );
    });

    test('a terminal with no sales is a row of zeros, not a gap', () {
      final idle = sales.terminal('POS-03')!;
      expect(idle.gross, Money.zero);
      expect(idle.net, Money.zero);
      expect(idle.collected, Money.zero);
    });
  });

  test('a business day travels as YYYY-MM-DD', () {
    expect(businessDayWire(DateTime(2026, 9, 1, 23, 59)), '2026-09-01');
  });
}
