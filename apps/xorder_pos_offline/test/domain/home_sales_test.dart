import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/home_sales.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_home_pane.dart';

Money _egp(int minor) => Money(minor, currency: 'EGP', exponent: 2);

BranchSales _day({required int net, required int orders}) => BranchSales(
  branchId: 1,
  businessDay: DateTime(2026, 9, 10),
  terminals: [
    TerminalSales(
      terminalId: 't',
      name: 'POS-01',
      orders: orders,
      gross: _egp(net),
      discounts: _egp(0),
      refunds: _egp(0),
      refundCount: 0,
    ),
  ],
);

/// Home's arithmetic (BO-4): one division, one comparison, one cut — each
/// rounded once, in integers.
void main() {
  group('the average order', () {
    test('is net over orders, half up, in minor units', () {
      expect(averageOrder(_day(net: 100, orders: 3))!.minor, 33);
      expect(averageOrder(_day(net: 101, orders: 2))!.minor, 51);
      // Half away from zero, as every other rounding in the till.
      expect(averageOrder(_day(net: -101, orders: 2))!.minor, -51);
    });

    test('is nothing, not zero, with no orders', () {
      expect(averageOrder(_day(net: 0, orders: 0)), isNull);
    });
  });

  group('the delta', () {
    test('is in basis points, rounded once', () {
      expect(deltaBp(150, 100), 5000);
      expect(deltaBp(50, 100), -5000);
      expect(deltaBp(1, 3), -6667);
      expect(deltaBp(100, 100), 0);
    });

    test('has no percentage over a zero day', () {
      expect(deltaBp(100, 0), isNull);
    });

    test('over a negative day, recovering reads as up', () {
      // A refund-heavy morning at −100 net, now +100.
      expect(deltaBp(100, -100), 20000);
    });

    test('prints as a person reads it, to the basis point', () {
      expect(formatDeltaBp(1250), '+12.50%');
      expect(formatDeltaBp(-307), '-3.07%');
      expect(formatDeltaBp(5), '+0.05%');
      expect(formatDeltaBp(0), '0.00%');
    });
  });

  group('the cut', () {
    final yesterday = BusinessDay(
      id: 1,
      date: DateTime(2026, 9, 9),
      openedAt: DateTime(2026, 9, 9, 8),
      closedAt: DateTime(2026, 9, 9, 23),
    );

    test('is as long after the previous opening as today has been open', () {
      // Open at 10 today, noon now: two hours in. Yesterday opened at 8, so
      // yesterday is cut at 10 — not at noon, which would hand it two hours
      // of trade today never had.
      final today = BusinessDay(
        id: 2,
        date: DateTime(2026, 9, 10),
        openedAt: DateTime(2026, 9, 10, 10),
      );
      expect(
        comparisonCut(
          day: today,
          previous: yesterday,
          now: DateTime(2026, 9, 10, 12),
        ),
        DateTime(2026, 9, 9, 10),
      );
    });

    test('a closed day is held against the same span of the one before', () {
      final closed = BusinessDay(
        id: 2,
        date: DateTime(2026, 9, 10),
        openedAt: DateTime(2026, 9, 10, 6),
        closedAt: DateTime(2026, 9, 10, 22),
      );
      expect(
        comparisonCut(
          day: closed,
          previous: yesterday,
          now: DateTime(2026, 9, 11, 9),
        ),
        DateTime(2026, 9, 9, 8 + 16),
      );
    });

    test('a clock behind the opening cuts at the opening', () {
      final today = BusinessDay(
        id: 2,
        date: DateTime(2026, 9, 10),
        openedAt: DateTime(2026, 9, 10, 10),
      );
      expect(
        comparisonCut(
          day: today,
          previous: yesterday,
          now: DateTime(2026, 9, 10, 9),
        ),
        yesterday.openedAt,
      );
    });
  });

  group('HomeSales', () {
    final day = BusinessDay(
      id: 2,
      date: DateTime(2026, 9, 10),
      openedAt: DateTime(2026, 9, 10, 6),
    );

    test('compares every figure with the cut day', () {
      final home = HomeSales(
        day: day,
        sales: _day(net: 54000, orders: 3),
        previous: _day(net: 45000, orders: 2),
      );
      expect(home.netDeltaBp, 2000);
      expect(home.ordersDeltaBp, 5000);
      // 18,000 against 22,500.
      expect(home.averageDeltaBp, -2000);
    });

    test('with no earlier day, compares nothing', () {
      final home = HomeSales(day: day, sales: _day(net: 54000, orders: 3));
      expect(home.netDeltaBp, isNull);
      expect(home.ordersDeltaBp, isNull);
      expect(home.averageDeltaBp, isNull);
    });

    test('an earlier day with no orders has no average to compare', () {
      final home = HomeSales(
        day: day,
        sales: _day(net: 54000, orders: 3),
        previous: _day(net: 0, orders: 0),
      );
      expect(home.averageDeltaBp, isNull);
      expect(home.netDeltaBp, isNull);
    });
  });
}
