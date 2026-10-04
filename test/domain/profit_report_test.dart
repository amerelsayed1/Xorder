import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/profit_report.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';

/// The arithmetic of a profit report — what it claims, and what it refuses to.
///
/// The SQL that feeds it is `test/data/profit_report_test.dart`'s. Here is the
/// part that has to be right whatever the rows are: a margin is a share of the
/// COSTED revenue, an uncosted item is never presented as pure profit, and a
/// loss is reported as one.
void main() {
  ProductProfit item(
    String name, {
    int? id,
    int revenue = 0,
    int? costed,
    int? cost,
    int quantity = 1,
  }) => ProductProfit(
    menuItemId: id,
    name: name,
    quantity: quantity,
    revenue: Money(revenue),
    costedRevenue: Money(costed ?? (cost == null ? 0 : revenue)),
    cost: cost == null ? null : Money(cost),
  );

  ProfitReport report(List<ProductProfit> products, {bool inclusive = false}) =>
      ProfitReport(
        filter: ReportFilter.day(DateTime(2026, 9, 10)),
        products: products,
        pricesIncludeTax: inclusive,
      );

  group('one product', () {
    test('profit is costed revenue less cost, margin is its share', () {
      final cola = item('Cola', id: 1, revenue: 8000, cost: 4200);

      expect(cola.isCosted, isTrue);
      expect(cola.profit!.minor, 3800);
      // 3,800 of 8,000 is 47.5%.
      expect(cola.marginBp, 4750);
    });

    test('with no cost there is no profit — not zero, not all of it', () {
      final burger = item('Burger', revenue: 8500);

      expect(burger.isCosted, isFalse);
      expect(burger.profit, isNull);
      expect(burger.marginBp, isNull);
    });

    test('a loss is a negative profit and a negative margin', () {
      final loss = item('Steak', id: 2, revenue: 10000, cost: 12500);

      expect(loss.profit!.minor, -2500);
      expect(loss.marginBp, -2500);
    });

    test('the margin is rounded once, half-up', () {
      // 1 of 3 is 33.333…% -> 3333; 2 of 3 is 66.666…% -> 6667.
      expect(item('a', revenue: 3, cost: 2).marginBp, 3333);
      expect(item('b', revenue: 3, cost: 1).marginBp, 6667);
    });

    test('a loss keeps its sign through the rounding', () {
      // −1 of 16 is exactly −6.25%: the sign survives `roundHalfUp`.
      expect(item('c', revenue: 16, cost: 17).marginBp, -625);
    });

    test('no revenue is no margin, whatever the cost', () {
      // Every unit came back but the food was spent: a loss with no share.
      final refunded = item('Plate', id: 3, revenue: 0, cost: 900);

      expect(refunded.profit!.minor, -900);
      expect(refunded.marginBp, isNull);
    });

    test('part of the revenue can be costed: the margin is on that part', () {
      // Sold before its first delivery (uncosted), then after (costed).
      final chips = item(
        'Chips',
        id: 4,
        revenue: 4500,
        costed: 1500,
        cost: 1000,
      );

      expect(chips.profit!.minor, 500);
      // 500 of the 1,500 that has a cost — never of the 4,500 that was sold.
      expect(chips.marginBp, 3333);
    });
  });

  group('the whole report', () {
    final products = [
      item('Cola', id: 1, revenue: 8000, cost: 4200),
      item('Chips', id: 4, revenue: 4500, costed: 1500, cost: 1000),
      item('Burger', revenue: 8500),
    ];

    test('totals add up what the rows say', () {
      final r = report(products);

      expect(r.revenue.minor, 21000);
      expect(r.costedRevenue.minor, 9500);
      expect(r.cost.minor, 5200);
      expect(r.profit.minor, 4300);
      expect(r.uncostedRevenue.minor, 11500);
    });

    test('the margin is on the costed revenue, and coverage says how much', () {
      final r = report(products);

      // 4,300 of 9,500 = 45.26% — not of the 21,000 that was sold.
      expect(r.marginBp, 4526);
      // And the report knows only 9,500 of 21,000 = 45.24% of the revenue.
      expect(r.coverageBp, 4524);
    });

    test('profit is never claimed over revenue it cannot speak to', () {
      final r = report(products);

      // The honest bottom line is a share of 45% of the menu. A figure of
      // 4,300 / 21,000 would have called a quarter of the sales pure cost.
      expect(r.marginBp, isNot(r.profit.minor * 10000 ~/ r.revenue.minor));
    });

    test('nothing costed: no profit to show, and it is said', () {
      final r = report([item('Burger', revenue: 8500), item('Fries', revenue: 900)]);

      expect(r.hasAnyCost, isFalse);
      expect(r.profit.minor, 0);
      expect(r.marginBp, isNull);
      expect(r.coverageBp, 0);
    });

    test('an empty range has no coverage and no margin', () {
      final r = report([]);

      expect(r.revenue.minor, 0);
      expect(r.coverageBp, isNull);
      expect(r.marginBp, isNull);
      expect(r.hasAnyCost, isFalse);
    });

    test('a tax-inclusive restaurant is flagged, for the page to say', () {
      expect(report(products, inclusive: true).pricesIncludeTax, isTrue);
      expect(report(products).pricesIncludeTax, isFalse);
    });

    test('the rows cannot be changed from outside', () {
      final r = report(products);

      expect(() => r.products.add(item('x')), throwsUnsupportedError);
    });
  });

  group('ranking', () {
    test('costed by profit, losses last of them, then uncosted by revenue', () {
      final ranked = ProfitReport.ranked([
        item('Burger', revenue: 8500),
        item('Steak', id: 2, revenue: 10000, cost: 12500),
        item('Chips', id: 4, revenue: 4500, cost: 1000),
        item('Cola', id: 1, revenue: 8000, cost: 4200),
        item('Fries', revenue: 900),
      ]);

      expect(ranked.map((p) => p.name), [
        'Cola', // +3,800
        'Chips', // +3,500
        'Steak', // −2,500
        'Burger', // uncosted, 8,500
        'Fries', // uncosted, 900
      ]);
    });

    test('ties fall to revenue, then name, so the page never reshuffles', () {
      final ranked = ProfitReport.ranked([
        item('Rice', id: 6, revenue: 1000, cost: 500),
        item('Chips', id: 4, revenue: 4500, cost: 4000),
        item('Beans', id: 5, revenue: 1000, cost: 500),
      ]);

      expect(ranked.map((p) => p.name), ['Chips', 'Beans', 'Rice']);
    });
  });
}
