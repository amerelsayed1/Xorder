import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/finance_report.dart';
import 'package:xorder_pos/domain/models/profit_and_loss.dart';
import 'package:xorder_pos/domain/models/profit_report.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';

/// The operating statement: one column, in an accountant's order, made of
/// figures the back office already draws — and a list of what it leaves out.
///
/// The arithmetic is simple on purpose; what is pinned here is the *meaning*
/// of each line, because a statement that adds up and means the wrong thing is
/// the failure that matters: tax counted as revenue, a supplier paid for stock
/// counted again as an expense, or a gross profit quoted as complete when a
/// quarter of the sales have no cost.
void main() {
  final range = ReportFilter(
    from: DateTime(2026, 9, 1),
    to: DateTime(2026, 9, 11),
  );

  ProfitAndLoss statement({
    int sales = 114000,
    int tax = 14000,
    int cost = 30000,
    int? costed = 10000,
    int expenses = 5000,
    SupplierFigures figures = SupplierFigures.included,
    int? suppliers = 40000,
  }) => ProfitAndLoss(
    filter: range,
    sales: Money(sales),
    tax: Money(tax),
    costOfGoods: Money(cost),
    costedShareBp: costed,
    drawerExpenses: Money(expenses),
    supplierFigures: figures,
    paidToSuppliers: suppliers == null ? null : Money(suppliers),
  );

  group('the lines', () {
    test(
      'revenue is sales without the tax that was collected for the state',
      () {
        // 1,140.00 taken, 140.00 of it VAT: the business sold 1,000.00.
        expect(statement().revenue.minor, 100000);
      },
    );

    test('gross profit is revenue less the cost of goods', () {
      expect(statement().grossProfit.minor, 70000);
    });

    test(
      'the result is gross profit less what was paid out of the drawers',
      () {
        expect(statement().operatingResult.minor, 65000);
      },
    );

    test('the gross margin is a share of revenue, rounded once', () {
      // 700 of 1,000 is 70%.
      expect(statement().grossMarginBp, 7000);
      // 1 of 3 is 33.33%.
      expect(statement(sales: 3, tax: 0, cost: 2).grossMarginBp, 3333);
    });

    test('a loss is negative, in profit and margin alike', () {
      final s = statement(sales: 114000, tax: 14000, cost: 130000);

      expect(s.grossProfit.minor, -30000);
      expect(s.grossMarginBp, -3000);
      expect(s.operatingResult.minor, -35000);
    });

    test('no sales: no margin, rather than a margin of nothing', () {
      final s = statement(sales: 0, tax: 0, cost: 0, costed: null);

      expect(s.revenue.minor, 0);
      expect(s.grossMarginBp, isNull);
    });
  });

  group('what is not in it', () {
    test('a supplier payment is not subtracted — it bought stock, which is '
        'already in the cost of goods when it is sold', () {
      // The same statement, whatever was paid to suppliers.
      final a = statement(suppliers: 0);
      final b = statement(suppliers: 900000);

      expect(a.operatingResult.minor, b.operatingResult.minor);
    });

    test('but what was paid to them is shown, for reference', () {
      expect(statement().paidToSuppliers!.minor, 40000);
    });

    test('an unread ledger is unknown, not zero paid', () {
      final s = statement(figures: SupplierFigures.onPlatform, suppliers: null);

      expect(s.paidToSuppliers, isNull);
    });
  });

  group('how complete the cost of goods is', () {
    test('every sale costed: complete, and no caveat about missing costs', () {
      final s = statement(costed: 10000);

      expect(s.isFullyCosted, isTrue);
      expect(s.caveats, isNot(contains(StatementCaveat.itemsWithNoCost)));
    });

    test('part of the sales costed: the gross profit is an upper bound', () {
      final s = statement(costed: 6500);

      expect(s.isFullyCosted, isFalse);
      expect(s.caveats.first, StatementCaveat.itemsWithNoCost);
    });

    test('none costed is the extreme of the same thing', () {
      final s = statement(cost: 0, costed: 0);

      expect(s.isFullyCosted, isFalse);
      expect(s.caveats, contains(StatementCaveat.itemsWithNoCost));
    });

    test('no sales to cost is vacuously complete', () {
      expect(
        statement(sales: 0, tax: 0, cost: 0, costed: null).isFullyCosted,
        isTrue,
      );
    });
  });

  group('the caveats', () {
    test('the limits of the data are always said, in a fixed order', () {
      final s = statement(costed: 10000);

      expect(s.caveats, [
        StatementCaveat.supplierSpendOutsideStock,
        StatementCaveat.rentAndSalaries,
        StatementCaveat.serviceChargeIncluded,
      ]);
    });

    test('a missing-cost caveat leads, because it qualifies the most', () {
      expect(statement(costed: 5000).caveats, [
        StatementCaveat.itemsWithNoCost,
        StatementCaveat.supplierSpendOutsideStock,
        StatementCaveat.rentAndSalaries,
        StatementCaveat.serviceChargeIncluded,
      ]);
    });
  });

  group('assembled from the four reports of one period', () {
    SalesReport salesReport() => SalesReport(
      filter: range,
      days: const [],
      terminals: const [
        TerminalSales(
          terminalId: 'a',
          name: 'Counter',
          orders: 10,
          gross: Money(120000),
          discounts: Money(4000),
          refunds: Money(2000),
          refundCount: 1,
        ),
      ],
    );

    TaxReport taxReport() => TaxReport(
      filter: range,
      unattributedRefunds: Money.zero,
      rates: const [
        TaxCollected(
          name: 'VAT 14%',
          rateBp: 1400,
          orders: 10,
          base: Money(100000),
          charged: Money(14000),
          refunded: Money(300),
        ),
      ],
    );

    ProfitReport profitReport() => ProfitReport(
      filter: range,
      pricesIncludeTax: false,
      products: const [
        ProductProfit(
          menuItemId: 1,
          name: 'Cola',
          quantity: 10,
          revenue: Money(60000),
          costedRevenue: Money(60000),
          cost: Money(25000),
        ),
        ProductProfit(
          menuItemId: null,
          name: 'Burger',
          quantity: 5,
          revenue: Money(40000),
          costedRevenue: Money(0),
          cost: null,
        ),
      ],
    );

    ExpenseReport expenseReport({List<CashMovement> payOuts = const []}) =>
        ExpenseReport(
          filter: range,
          payOuts: payOuts,
          supplierFigures: SupplierFigures.onPlatform,
        );

    test('sales are the net the Sales report draws, tax the net the Taxes '
        'report draws', () {
      final s = ProfitAndLoss.of(
        salesReport: salesReport(),
        taxReport: taxReport(),
        profitReport: profitReport(),
        expenses: expenseReport(),
      );

      // 1,200.00 − 40.00 discounts − 20.00 refunds.
      expect(s.sales.minor, 114000);
      // 140.00 charged − 3.00 given back.
      expect(s.tax.minor, 13700);
      expect(s.revenue.minor, 100300);
    });

    test('the cost of goods and its coverage are the Profit report\'s', () {
      final s = ProfitAndLoss.of(
        salesReport: salesReport(),
        taxReport: taxReport(),
        profitReport: profitReport(),
        expenses: expenseReport(),
      );

      expect(s.costOfGoods.minor, 25000);
      // 600.00 of 1,000.00 of the lines has a cost.
      expect(s.costedShareBp, 6000);
      expect(s.isFullyCosted, isFalse);
    });

    test('drawer expenses are the pay-outs, and the unread supplier ledger is '
        'unknown', () {
      final s = ProfitAndLoss.of(
        salesReport: salesReport(),
        taxReport: taxReport(),
        profitReport: profitReport(),
        expenses: expenseReport(
          payOuts: [
            CashMovement(
              id: 1,
              kind: CashMovementKind.payOut,
              amount: const Money(2500),
              occurredAt: DateTime(2026, 9, 3),
            ),
            CashMovement(
              id: 2,
              kind: CashMovementKind.payOut,
              amount: const Money(1000),
              occurredAt: DateTime(2026, 9, 4),
            ),
          ],
        ),
      );

      expect(s.drawerExpenses.minor, 3500);
      expect(s.paidToSuppliers, isNull);
      expect(s.supplierFigures, SupplierFigures.onPlatform);
    });

    test('a supplier paid from a drawer is not an expense, even read '
        'without the ledger', () {
      // A manager without purchasing: the expenses still hold pay-out 2, a
      // supplier paid for stock that is already cost of goods when it sells.
      final expenses = ExpenseReport(
        filter: range,
        payOuts: [
          CashMovement(
            id: 1,
            kind: CashMovementKind.payOut,
            amount: const Money(2500),
            occurredAt: DateTime(2026, 9, 3),
          ),
          CashMovement(
            id: 2,
            kind: CashMovementKind.payOut,
            amount: const Money(500000),
            occurredAt: DateTime(2026, 9, 4),
          ),
        ],
        supplierFigures: SupplierFigures.notPermitted,
      );

      final s = ProfitAndLoss.of(
        salesReport: salesReport(),
        taxReport: taxReport(),
        profitReport: profitReport(),
        expenses: expenses,
        supplierPayOutIds: const {2},
      );

      expect(s.drawerExpenses.minor, 2500);
      expect(s.paidToSuppliers, isNull);
    });

    test(
      'a share that rounds to 100% with revenue uncosted is not complete',
      () {
        // 99,996 of 100,000 costed: 9999.6 bp rounds to 10000.
        final s = ProfitAndLoss.of(
          salesReport: salesReport(),
          taxReport: taxReport(),
          profitReport: ProfitReport(
            filter: range,
            pricesIncludeTax: false,
            products: const [
              ProductProfit(
                menuItemId: 1,
                name: 'Cola',
                quantity: 10,
                revenue: Money(99996),
                costedRevenue: Money(99996),
                cost: Money(25000),
              ),
              ProductProfit(
                menuItemId: null,
                name: 'Gum',
                quantity: 1,
                revenue: Money(4),
                costedRevenue: Money(0),
                cost: null,
              ),
            ],
          ),
          expenses: expenseReport(),
        );

        expect(s.costedShareBp, 9999);
        expect(s.isFullyCosted, isFalse);
        expect(s.caveats, contains(StatementCaveat.itemsWithNoCost));
      },
    );

    test('four reports of different periods are refused', () {
      final other = ProfitReport(
        filter: ReportFilter(
          from: DateTime(2026, 8, 1),
          to: DateTime(2026, 8, 11),
        ),
        pricesIncludeTax: false,
        products: const [],
      );

      expect(
        () => ProfitAndLoss.of(
          salesReport: salesReport(),
          taxReport: taxReport(),
          profitReport: other,
          expenses: expenseReport(),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
