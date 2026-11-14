/// The Reports tab as an Excel file (BO-11): a sheet for each block on the
/// tab, holding exactly its figures.
///
/// **Nothing here adds up sales**, for the reason `reports_view.dart` gives:
/// every figure is a getter on the same `SalesReport` the tab drew, and
/// every change is Home's `deltaBp` over the same two reports. The tab and
/// its file cannot disagree, because neither of them does any arithmetic the
/// other does not.
///
/// **Insights are left out.** Each is a pick of a row the file already holds
/// — the best day is a row of the days sheet, the busiest till a row of the
/// tills sheet, the growth the net row's change — and a sheet of three
/// repeated cells would be a fourth place to reconcile.
library;

import 'dart:typed_data';

import 'package:shared_module/core/export/workbook.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/branch_sales.dart' show businessDayWire;
import 'package:shared_module/domain/models/home_sales.dart' show deltaBp;
import 'package:shared_module/domain/models/profit_report.dart';
import 'package:shared_module/domain/models/sales_report.dart';

/// `report-2026-09-01-2026-09-10.xlsx`, or one date for one day — and
/// `report-items-…` for a breakdown's own file, so a folder of them says which
/// is which without opening any.
String reportFileName(ReportFilter filter, {String? section}) {
  final name = section == null ? 'report' : 'report-$section';
  final last = DateTime(filter.to.year, filter.to.month, filter.to.day - 1);
  return filter.dates.length == 1
      ? '$name-${businessDayWire(filter.from)}.xlsx'
      : '$name-${businessDayWire(filter.from)}-${businessDayWire(last)}.xlsx';
}

/// [report] as the tab shows it: the tiles against [previous], the days the
/// trend plots, the tills and the branch under them, the payment methods, and
/// [products] — the top five in the order on screen.
Uint8List reportWorkbook({
  required SalesReport report,
  required SalesReport? previous,
  required List<ProductSales> products,
  required AppStrings strings,
  required bool rightToLeft,
}) {
  final s = strings;
  final book = WorkbookWriter(rightToLeft: rightToLeft);
  String amount(String label) => '$label (${report.currency})';
  WorkbookCell? money(Money? value) => value == null ? null : MoneyCell(value);

  // The tiles. A change with nothing to compare against is an empty cell,
  // where the tile says a dash.
  WorkbookCell? change(int now, int? before) => switch (before) {
    final before? => switch (deltaBp(now, before)) {
      final bp? => BasisPointsCell(bp),
      null => null,
    },
    null => null,
  };
  final last = DateTime(
    report.filter.to.year,
    report.filter.to.month,
    report.filter.to.day - 1,
  );
  final average = report.averageOrder;
  book.sheet(s.exportSheetSummary)
    ..row([TextCell(s.exportPeriodFrom), DateCell(report.filter.from)])
    ..row([TextCell(s.exportPeriodTo), DateCell(last)])
    ..row([TextCell(s.currency), TextCell(report.currency)])
    ..blank()
    ..header([
      s.exportColumnFigure,
      s.exportColumnValue,
      s.reportVsPrevious,
      s.exportColumnNote,
    ])
    ..row([
      TextCell(s.homeKpiNetSales),
      MoneyCell(report.net),
      change(report.net.minor, previous?.net.minor),
    ])
    ..row([
      TextCell(s.homeKpiAverage),
      money(average),
      average == null
          ? null
          : change(average.minor, previous?.averageOrder?.minor),
    ])
    ..row([
      TextCell(s.homeKpiOrders),
      CountCell(report.orders),
      change(report.orders, previous?.orders),
    ])
    ..row([
      TextCell(s.reportKpiRefunds),
      MoneyCell(report.refunds),
      change(report.refunds.minor, previous?.refunds.minor),
      TextCell(s.reportRefundCount(report.refundCount)),
    ]);

  // The days the trend plots, every one of them, a shut day's average empty
  // as the line leaves a gap for it; and the branch under them.
  final days = book.sheet(s.reportTrend)
    ..header([
      s.exportColumnDate,
      s.homeKpiOrders,
      amount(s.dayGross),
      amount(s.orderDetailDiscounts),
      amount(s.reportKpiRefunds),
      amount(s.homeKpiNetSales),
      amount(s.homeKpiAverage),
    ]);
  for (final day in report.days) {
    days.row([
      DateCell(day.date),
      CountCell(day.orders),
      MoneyCell(day.gross),
      MoneyCell(day.discounts),
      MoneyCell(day.refunds),
      MoneyCell(day.net),
      money(day.averageOrder),
    ]);
  }
  days.row([
    TextCell(s.reportBranchTotal),
    CountCell(report.orders),
    MoneyCell(report.gross),
    MoneyCell(report.discounts),
    MoneyCell(report.refunds),
    MoneyCell(report.net),
    money(average),
  ]);

  _tills(book.sheet(s.reportTerminals), report, s);

  // What was collected, with BO-5's shares; on account on its own row and
  // with no share, because it is owed and not taken (§3a rule 3).
  final payments = book.sheet(s.reportPayments)
    ..header([
      s.orderColumnMethod,
      amount(s.reportColumnAmount),
      s.exportColumnShare,
    ]);
  final shares = report.tenderShares;
  for (final share in shares) {
    payments.row([
      TextCell(share.method.label),
      MoneyCell(share.method.amount),
      BasisPointsCell(share.basisPoints),
    ]);
  }
  if (!report.onAccount.isZero) {
    payments.row([TextCell(s.reportOnAccount), MoneyCell(report.onAccount)]);
  }
  if (shares.isEmpty && report.onAccount.isZero) {
    payments.row([TextCell(s.reportNoPayments)]);
  }

  // The top five, in the ranking on screen, and the tab's caveat under them:
  // a product's amount is before the order's discount, which belongs to no
  // one line.
  final top = book.sheet(s.reportTopProducts)
    ..header([
      s.exportColumnRank,
      s.exportColumnProduct,
      s.reportColumnQuantity,
      amount(s.reportColumnAmount),
    ]);
  for (final (i, product) in products.indexed) {
    top.row([
      CountCell(i + 1),
      TextCell(product.name),
      CountCell(product.quantity),
      MoneyCell(product.amount),
    ]);
  }
  top
    ..blank()
    ..row([TextCell(s.reportTopProductsNote)]);

  return book.encode();
}

/// Every till, zeros included, and the report's own rollup under them — the
/// tab's bottom line, not a sum this file did. The summary's till sheet and
/// Branches & devices' file are this one sheet, so the two cannot differ.
void _tills(WorkbookSheet tills, SalesReport report, AppStrings s) {
  String amount(String label) => '$label (${report.currency})';
  tills.header([
    s.orderColumnTerminal,
    s.homeKpiOrders,
    amount(s.dayGross),
    amount(s.orderDetailDiscounts),
    amount(s.reportKpiRefunds),
    amount(s.homeKpiNetSales),
    s.exportColumnNote,
  ]);
  for (final till in report.terminals) {
    tills.row([
      TextCell(till.name ?? till.terminalId),
      CountCell(till.orders),
      MoneyCell(till.gross),
      MoneyCell(till.discounts),
      MoneyCell(till.refunds),
      MoneyCell(till.net),
      till.name == null ? TextCell(s.reportUnregistered) : null,
    ]);
  }
  tills.row([
    TextCell(s.reportBranchTotal),
    CountCell(report.orders),
    MoneyCell(report.gross),
    MoneyCell(report.discounts),
    MoneyCell(report.refunds),
    MoneyCell(report.net),
  ]);
}

// ── The breakdowns (the owner's map) ────────────────────────────────────────
//
// One sheet each, the page's own table and nothing more, with the period it
// covers above it — a breakdown's file is opened on its own, away from the
// page that said which week it was. The summary's file is unchanged: it is
// still the whole tab, and a breakdown's file is that page, not a second copy
// of the summary.

/// The period a breakdown's sheet covers, above its table.
WorkbookSheet _breakdownSheet(
  WorkbookWriter book,
  String name,
  ReportFilter filter,
  String currency,
  AppStrings s,
) {
  final last = DateTime(filter.to.year, filter.to.month, filter.to.day - 1);
  return book.sheet(name)
    ..row([TextCell(s.exportPeriodFrom), DateCell(filter.from)])
    ..row([TextCell(s.exportPeriodTo), DateCell(last)])
    ..row([TextCell(s.currency), TextCell(currency)])
    ..blank();
}

/// Reports › Sales: every day of the period, in the page's column order, and
/// the report's rollup under them.
Uint8List salesDaysWorkbook({
  required SalesReport report,
  required AppStrings strings,
  required bool rightToLeft,
}) {
  final s = strings;
  final book = WorkbookWriter(rightToLeft: rightToLeft);
  String amount(String label) => '$label (${report.currency})';
  WorkbookCell? money(Money? value) => value == null ? null : MoneyCell(value);
  final days =
      _breakdownSheet(book, s.reportsSales, report.filter, report.currency, s)
        ..header([
          s.exportColumnDate,
          s.homeKpiOrders,
          amount(s.dayGross),
          amount(s.orderDetailDiscounts),
          amount(s.homeKpiNetSales),
          amount(s.reportKpiRefunds),
          amount(s.homeKpiAverage),
        ]);
  for (final day in report.days) {
    days.row([
      DateCell(day.date),
      CountCell(day.orders),
      MoneyCell(day.gross),
      MoneyCell(day.discounts),
      MoneyCell(day.net),
      MoneyCell(day.refunds),
      money(day.averageOrder),
    ]);
  }
  days.row([
    TextCell(s.reportBranchTotal),
    CountCell(report.orders),
    MoneyCell(report.gross),
    MoneyCell(report.discounts),
    MoneyCell(report.net),
    MoneyCell(report.refunds),
    money(report.averageOrder),
  ]);
  return book.encode();
}

/// Reports › Items: every product, in the ranking on screen, the rows' total,
/// and the page's sentence on what that total is not — and, when [profit] is
/// given, the page's Profit section as a second sheet.
///
/// The second sheet is the screen's, not a recomputation: [ProfitReport] is
/// what the page drew, so the file and the page cannot disagree. An item with
/// no cost leaves its cost, profit and margin cells **empty** — a blank is
/// "unknown" and a zero would read as "free", and a formula over a column of
/// zeros is exactly how a margin gets quoted that nobody costed.
Uint8List itemsWorkbook({
  required ReportFilter filter,
  required List<ProductSales> products,
  required AppStrings strings,
  required bool rightToLeft,
  ProfitReport? profit,
}) {
  final s = strings;
  final book = WorkbookWriter(rightToLeft: rightToLeft);
  final totals = productTotals(products);
  final currency = totals.amount.currency;
  final items = _breakdownSheet(book, s.reportsItems, filter, currency, s)
    ..header([
      s.exportColumnRank,
      s.exportColumnProduct,
      s.reportColumnQuantity,
      '${s.reportColumnAmount} ($currency)',
    ]);
  for (final (i, product) in products.indexed) {
    items.row([
      CountCell(i + 1),
      TextCell(product.name),
      CountCell(product.quantity),
      MoneyCell(product.amount),
    ]);
  }
  items
    ..row([
      null,
      TextCell(s.reportAllItems),
      CountCell(totals.quantity),
      MoneyCell(totals.amount),
    ])
    ..blank()
    ..row([TextCell(s.reportItemsNote)]);
  if (profit != null && profit.products.isNotEmpty) {
    _profitSheet(book, profit, s);
  }
  return book.encode();
}

/// The Profit sheet: a row per product, the rows' total, and what the figures
/// do and do not cover — the page's notes, in the page's words.
void _profitSheet(WorkbookWriter book, ProfitReport report, AppStrings s) {
  final currency = report.currency;
  String amount(String label) => '$label ($currency)';
  final sheet = _breakdownSheet(book, s.profitTitle, report.filter, currency, s);

  if (!report.hasAnyCost) {
    // As the page: no column of blanks, and the way to get a cost.
    sheet.row([TextCell(s.profitNothingCosted)]);
    if (report.pricesIncludeTax) {
      sheet
        ..blank()
        ..row([TextCell(s.profitTaxNote)]);
    }
    return;
  }

  sheet.header([
    s.exportColumnProduct,
    amount(
      report.pricesIncludeTax ? s.profitColumnAmountNet : s.reportColumnAmount,
    ),
    amount(s.profitColumnCost),
    amount(s.profitColumnProfit),
    s.profitColumnMargin,
    // Which rows have no cost, said in words as well as by the blanks.
    '',
  ]);
  for (final product in report.products) {
    sheet.row([
      TextCell(product.name),
      MoneyCell(product.revenue),
      product.cost == null ? null : MoneyCell(product.cost!),
      product.profit == null ? null : MoneyCell(product.profit!),
      product.marginBp == null ? null : BasisPointsCell(product.marginBp!),
      product.isCosted ? null : TextCell(s.profitNoCostTag),
    ]);
  }
  sheet
    ..row([
      TextCell(s.reportAllItems),
      MoneyCell(report.revenue),
      MoneyCell(report.cost),
      MoneyCell(report.profit),
      report.marginBp == null ? null : BasisPointsCell(report.marginBp!),
    ])
    ..blank()
    // The denominator of that margin, beside it: a margin without its coverage
    // is read as the business's, and it is not.
    ..row([TextCell(s.profitKpiCoverage), MoneyCell(report.costedRevenue)])
    ..row([
      TextCell(s.profitUncostedRevenue),
      MoneyCell(report.uncostedRevenue),
    ]);
  final coverage = report.coverageBp;
  if (coverage != null) {
    sheet.row([
      TextCell('${s.profitKpiCoverage} · ${s.profitCoverageNote}'),
      BasisPointsCell(coverage),
    ]);
  }
  if (report.pricesIncludeTax) {
    sheet
      ..blank()
      ..row([TextCell(s.profitTaxNote)]);
  }
  sheet
    ..blank()
    ..row([TextCell(s.profitNote)]);
}

/// Reports › Payment methods: BO-5's shares with their counts, the collected
/// total, and on account on its own row with no share (§3a rule 3).
Uint8List paymentsWorkbook({
  required SalesReport report,
  required AppStrings strings,
  required bool rightToLeft,
}) {
  final s = strings;
  final book = WorkbookWriter(rightToLeft: rightToLeft);
  final shares = report.tenderShares;
  final methods =
      _breakdownSheet(
          book,
          s.reportsPaymentMethods,
          report.filter,
          report.currency,
          s,
        )
        ..header([
          s.orderColumnMethod,
          s.reportColumnPayments,
          '${s.reportColumnAmount} (${report.currency})',
          s.exportColumnShare,
        ]);
  for (final share in shares) {
    methods.row([
      TextCell(share.method.label),
      CountCell(share.method.count),
      MoneyCell(share.method.amount),
      BasisPointsCell(share.basisPoints),
    ]);
  }
  methods.row([
    TextCell(s.financeKpiCollected),
    CountCell(report.collectedPayments),
    MoneyCell(report.collected),
    BasisPointsCell(shares.fold(0, (sum, share) => sum + share.basisPoints)),
  ]);
  if (!report.onAccount.isZero) {
    methods.row([
      TextCell(s.reportOnAccount),
      CountCell(report.onAccountPayments),
      MoneyCell(report.onAccount),
    ]);
  }
  return book.encode();
}

/// Reports › Branches & devices: the summary's till sheet, on its own.
Uint8List terminalsWorkbook({
  required SalesReport report,
  required AppStrings strings,
  required bool rightToLeft,
}) {
  final book = WorkbookWriter(rightToLeft: rightToLeft);
  _tills(
    _breakdownSheet(
      book,
      strings.reportsBranches,
      report.filter,
      report.currency,
      strings,
    ),
    report,
    strings,
  );
  return book.encode();
}

/// Reports › Employees: each person, the rows' rollup, and the rule for whose
/// figure is whose.
Uint8List staffWorkbook({
  required StaffSalesReport report,
  required AppStrings strings,
  required bool rightToLeft,
}) {
  final s = strings;
  final book = WorkbookWriter(rightToLeft: rightToLeft);
  String amount(String label) => '$label (${report.currency})';
  WorkbookCell? money(Money? value) => value == null ? null : MoneyCell(value);
  final people =
      _breakdownSheet(
          book,
          s.reportsEmployees,
          report.filter,
          report.currency,
          s,
        )
        ..header([
          s.reportColumnSeller,
          s.homeKpiOrders,
          amount(s.homeKpiNetSales),
          amount(s.homeKpiAverage),
          amount(s.reportKpiRefunds),
          s.reportColumnVoids,
        ]);
  for (final person in report.people) {
    people.row([
      TextCell(person.name ?? s.reportSellerNotRecorded),
      CountCell(person.orders),
      MoneyCell(person.net),
      money(person.averageOrder),
      MoneyCell(person.refunds),
      CountCell(person.voids),
    ]);
  }
  people
    ..row([
      TextCell(s.reportBranchTotal),
      CountCell(report.orders),
      MoneyCell(report.net),
      money(report.averageOrder),
      MoneyCell(report.refunds),
      CountCell(report.voids),
    ])
    ..blank()
    ..row([TextCell(s.reportStaffNote)]);
  return book.encode();
}
