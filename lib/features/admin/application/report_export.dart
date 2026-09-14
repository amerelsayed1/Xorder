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

import '../../../core/export/workbook.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../domain/models/branch_sales.dart' show businessDayWire;
import '../../../domain/models/home_sales.dart' show deltaBp;
import '../../../domain/models/sales_report.dart';

/// `report-2026-09-01-2026-09-10.xlsx`, or one date for one day.
String reportFileName(ReportFilter filter) {
  final last = DateTime(filter.to.year, filter.to.month, filter.to.day - 1);
  return filter.dates.length == 1
      ? 'report-${businessDayWire(filter.from)}.xlsx'
      : 'report-${businessDayWire(filter.from)}-${businessDayWire(last)}.xlsx';
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

  // Every till, zeros included, and the report's own rollup under them —
  // the tab's bottom line, not a sum this file did.
  final tills = book.sheet(s.reportTerminals)
    ..header([
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
