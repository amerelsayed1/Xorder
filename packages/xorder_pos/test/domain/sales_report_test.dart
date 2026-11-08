import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/domain/models/ticket.dart' show OrderType;

/// The reports' rules that live in Dart: the range a filter covers, the one
/// rounding point for shares and for the average, and on account kept out of
/// the tender bar.
void main() {
  MethodTotal method(TenderKind kind, int amount, {bool cash = false}) =>
      MethodTotal(
        tenderTypeId: kind.index + 1,
        label: kind.wire,
        kind: kind,
        countsAsCash: cash,
        count: 1,
        amount: Money(amount),
      );

  SalesReport report({
    int orders = 0,
    int gross = 0,
    int refunds = 0,
    List<MethodTotal> payments = const [],
  }) => SalesReport(
    filter: ReportFilter.day(DateTime(2026, 9, 10)),
    terminals: [
      TerminalSales(
        terminalId: 'pos-01',
        name: 'POS-01',
        orders: orders,
        gross: Money(gross),
        discounts: Money.zero,
        refunds: Money(refunds),
        refundCount: refunds > 0 ? 1 : 0,
        payments: payments,
      ),
    ],
    days: const [],
  );

  group('basisPointShares — one rounding point, and it adds up', () {
    test('three equal tenders share 10,000 exactly, not 9,999', () {
      final shares = basisPointShares([100, 100, 100]);
      expect(shares, [3334, 3333, 3333]);
      expect(shares.reduce((a, b) => a + b), 10000);
    });

    test('the basis point left over goes to the largest remainder', () {
      // 54,000 / 20,000 / 30,000 of 104,000: floors 5,192 + 1,923 + 2,884 =
      // 9,999, and the wallet's remainder (.615) is the largest.
      expect(basisPointShares([54000, 20000, 30000]), [5192, 1923, 2885]);
    });

    test('nothing collected shares nothing, rather than dividing by zero', () {
      expect(basisPointShares([0, 0]), [0, 0]);
      expect(basisPointShares([]), isEmpty);
    });

    test('one tender is the whole bar', () {
      expect(basisPointShares([12345]), [10000]);
    });

    test('a negative amount is refused, not shared', () {
      expect(() => basisPointShares([100, -1]), throwsArgumentError);
    });
  });

  group('ReportFilter', () {
    test('cuts both ends to the date, so now() means today', () {
      final filter = ReportFilter.day(DateTime(2026, 9, 10, 14, 7));
      expect(filter.from, DateTime(2026, 9, 10));
      expect(filter.to, DateTime(2026, 9, 11));
      expect(filter.dates, [DateTime(2026, 9, 10)]);
    });

    test('steps by calendar day across the change to summer time', () {
      // Egypt moves its clocks on the last Friday of April. Every date is
      // still local midnight — no 23:00 of the day before.
      final filter = ReportFilter(
        from: DateTime(2026, 4, 23),
        to: DateTime(2026, 4, 27),
      );
      expect(filter.dates, [
        DateTime(2026, 4, 23),
        DateTime(2026, 4, 24),
        DateTime(2026, 4, 25),
        DateTime(2026, 4, 26),
      ]);
    });

    test('an empty or backwards range is refused', () {
      final day = DateTime(2026, 9, 10);
      expect(() => ReportFilter(from: day, to: day), throwsArgumentError);
      expect(
        () => ReportFilter(from: day, to: DateTime(2026, 9, 9)),
        throwsArgumentError,
      );
    });

    test('the previous period is the same length, just before, same filters', () {
      final week = ReportFilter(
        from: DateTime(2026, 9, 7),
        to: DateTime(2026, 9, 14),
        terminalId: 'pos-02',
        orderTypes: {OrderType.takeaway},
      );
      final previous = week.previous;
      expect(previous.from, DateTime(2026, 8, 31));
      expect(previous.to, DateTime(2026, 9, 7));
      expect(previous.terminalId, 'pos-02');
      expect(previous.orderTypes, {OrderType.takeaway});
    });

    test('drills into the settled sales of the same range and filters', () {
      final filter = ReportFilter(
        from: DateTime(2026, 9, 9),
        to: DateTime(2026, 9, 12),
        terminalId: 'pos-01',
        servedByStaffId: 4,
        orderTypes: {OrderType.dineIn},
      );
      final query = filter.historyQuery();
      expect(query.from, filter.from);
      expect(query.to, filter.to);
      expect(query.statuses, settledStatuses);
      expect(query.statuses, isNot(contains(OrderStatus.voided)));
      expect(query.terminalId, 'pos-01');
      expect(query.servedByStaffId, 4);
      expect(query.orderTypes, {OrderType.dineIn});
    });

    test('two filters built alike are one family key', () {
      ReportFilter build() => ReportFilter(
        from: DateTime(2026, 9, 9),
        to: DateTime(2026, 9, 12),
        orderTypes: {OrderType.takeaway, OrderType.delivery},
      );
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });
  });

  group('SalesReport', () {
    test('the average order is net per order, rounded half-up once', () {
      expect(report(orders: 2, gross: 1001).averageOrder, const Money(501));
      expect(report(orders: 3, gross: 1000).averageOrder, const Money(333));
    });

    test('a day of refunds of older sales can average below zero, half away', () {
      expect(
        report(orders: 2, gross: 1000, refunds: 2001).averageOrder,
        const Money(-501),
      );
    });

    test('no orders is no average, not an average of zero', () {
      expect(report().averageOrder, isNull);
    });

    test("a day's average is the same rule as the period's, rounded once", () {
      ReportDay day({required int orders, int gross = 0, int refunds = 0}) =>
          ReportDay(
            date: DateTime(2026, 9, 10),
            orders: orders,
            gross: Money(gross),
            discounts: const Money(100),
            refunds: Money(refunds),
            refundCount: refunds > 0 ? 1 : 0,
          );
      // (1101 − 100) ÷ 2 = 500.5 → 501, as the period rounds it.
      expect(day(orders: 2, gross: 1101).averageOrder, const Money(501));
      expect(
        day(orders: 2, gross: 1100, refunds: 2001).averageOrder,
        const Money(-501),
      );
      // A shut day is a gap in the average line, not a dip to zero.
      expect(day(orders: 0).averageOrder, isNull);
    });

    test('on account is owed, so it has no slice of the tender bar', () {
      final shares = report(
        orders: 3,
        gross: 50000,
        payments: [
          method(TenderKind.cash, 30000, cash: true),
          method(TenderKind.card, 10000),
          method(TenderKind.account, 10000),
        ],
      ).tenderShares;

      expect(shares.map((s) => s.method.kind), [
        TenderKind.cash,
        TenderKind.card,
      ]);
      expect(shares.map((s) => s.basisPoints), [7500, 2500]);
    });
  });
}
