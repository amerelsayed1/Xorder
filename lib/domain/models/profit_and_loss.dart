/// A period's operating statement, assembled from figures the back office
/// already computes — and honest about what it cannot include.
///
/// **Nothing here is a new query.** Sales, tax, cost of goods and expenses are
/// the figures Reports and Finance already draw ([SalesReport], [TaxReport],
/// [ProfitReport], [ExpenseReport]); this puts them in one column in the order
/// an accountant reads them, so the statement cannot disagree with the screens
/// it was made from.
///
/// ```
///   Sales, after discounts and refunds          (all of it, tax in)
/// − Tax collected, net of refunds               (not the restaurant's)
/// = Revenue
/// − Cost of goods sold                          (items with a cost only)
/// = Gross profit
/// − Expenses paid from the drawers
/// = Operating result
/// ```
///
/// **What it deliberately leaves out, and says it leaves out** — see
/// [StatementCaveat]. The data does not support more, and a bottom line that
/// quietly covers half the business is worse than none:
///
/// * Only an item with a recorded cost has a cost of goods. [coverageBp] says how
///   much of the sales that is, and while it is below 100% the gross profit is
///   an **upper bound** — the items with no cost cost something, and it is not
///   subtracted.
/// * **Purchases are stock, not expense.** Paying a supplier buys goods that
///   become cost of goods when they are sold; counting the payment as an expense
///   as well would count the same food twice. A supplier invoice is a single
///   total with no lines, so packaging and gas — a real expense — cannot be told
///   from stock and are not deducted. What was paid to suppliers is shown for
///   reference, beside the statement and not in it.
/// * Rent and salaries have no entity to hold them (doc 16 §4).
library;

import '../../core/money/money.dart';
import '../../core/money/rounding.dart';
import 'finance_report.dart';
import 'profit_report.dart';
import 'sales_report.dart';

/// Something the statement does not include. Data, not a sentence: the screen
/// words each in its own language, and a caveat added here is a compile error
/// there.
enum StatementCaveat {
  /// Some of the sales are of items with no recorded cost, so their cost of
  /// goods is missing and the gross profit is an upper bound.
  itemsWithNoCost,

  /// Packaging, gas and the like are bought from suppliers and cannot be told
  /// from stock on a total-only invoice, so they are not deducted.
  supplierSpendOutsideStock,

  /// No expense entity: rent, salaries and the rest are not here.
  rentAndSalaries,

  /// Sales are the orders' totals, so any service charge is in them.
  serviceChargeIncluded,
}

class ProfitAndLoss {
  const ProfitAndLoss({
    required this.filter,
    required this.sales,
    required this.tax,
    required this.costOfGoods,
    required this.costedShareBp,
    required this.drawerExpenses,
    required this.supplierFigures,
    this.paidToSuppliers,
    this.currency = 'EGP',
    this.exponent = 2,
  });

  /// Assembled from the four reports of one range.
  ///
  /// Asserts they are of the **same range**: four figures of four periods in one
  /// column is a statement that adds up and means nothing.
  factory ProfitAndLoss.of({
    required SalesReport salesReport,
    required TaxReport taxReport,
    required ProfitReport profitReport,
    required ExpenseReport expenses,
  }) {
    assert(
      salesReport.filter.from == taxReport.filter.from &&
          salesReport.filter.to == taxReport.filter.to &&
          salesReport.filter.from == profitReport.filter.from &&
          salesReport.filter.to == profitReport.filter.to &&
          salesReport.filter.from == expenses.filter.from &&
          salesReport.filter.to == expenses.filter.to,
      'A statement is of one period; these reports are of different ones.',
    );
    return ProfitAndLoss(
      filter: salesReport.filter,
      sales: salesReport.net,
      tax: taxReport.net,
      costOfGoods: profitReport.cost,
      costedShareBp: profitReport.coverageBp,
      drawerExpenses: expenses.payOutTotal,
      supplierFigures: expenses.supplierFigures,
      paidToSuppliers:
          expenses.supplierFigures == SupplierFigures.included
          ? expenses.supplierTotal
          : null,
      currency: salesReport.currency,
      exponent: salesReport.exponent,
    );
  }

  final ReportFilter filter;

  /// What was sold for, after discounts and refunds, **tax in**.
  final Money sales;

  /// Tax collected on those sales, net of what refunds gave back. It was
  /// collected for the authority and is no part of revenue.
  final Money tax;

  /// What the costed items sold cost, from the stock ledger. Items with no
  /// recorded cost contribute nothing here — see
  /// [StatementCaveat.itemsWithNoCost].
  final Money costOfGoods;

  /// The share of sales that has a cost, in basis points. Null with no sales.
  /// Measured on the lines' own revenue, as [ProfitReport] has it, so it is a
  /// share and not an amount to subtract from [revenue].
  final int? costedShareBp;

  /// Cash paid out of the drawers that is not a supplier payment.
  final Money drawerExpenses;

  final SupplierFigures supplierFigures;

  /// What was paid to suppliers in the period — **for reference, not in the
  /// result**. Null when the ledger is not read (a cloud till, or a person who
  /// may not read it), which is not the same as nothing paid.
  final Money? paidToSuppliers;

  final String currency;
  final int exponent;

  /// What the restaurant earned from selling: sales without the tax.
  Money get revenue => sales - tax;

  /// Revenue less the cost of the goods that have a cost. **An upper bound
  /// while [isFullyCosted] is false.**
  Money get grossProfit => revenue - costOfGoods;

  /// Gross profit as a share of revenue, in basis points. Null with no revenue —
  /// a zero margin is a claim about sales, and there were none.
  int? get grossMarginBp => revenue.minor <= 0
      ? null
      : roundHalfUp(grossProfit.minor * 10000, revenue.minor);

  Money get operatingResult => grossProfit - drawerExpenses;

  /// Whether every sale in the period has a cost, so the cost of goods is the
  /// whole of it. Vacuously true with no sales to cost.
  bool get isFullyCosted => costedShareBp == null || costedShareBp! >= 10000;

  /// What this statement does not include, in a fixed order, only for what
  /// applies. The last three always do: they are limits of the data, not of the
  /// period.
  List<StatementCaveat> get caveats => [
    if (!isFullyCosted) StatementCaveat.itemsWithNoCost,
    StatementCaveat.supplierSpendOutsideStock,
    StatementCaveat.rentAndSalaries,
    StatementCaveat.serviceChargeIncluded,
  ];
}
