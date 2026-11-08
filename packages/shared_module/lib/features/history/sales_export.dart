/// The Sales list as an Excel file (BO-11).
///
/// **Every row of the filter on screen, across every page** — not the fifty
/// rows of the page being looked at. The pager is how a person reads a long
/// list; it is not a boundary of what they asked for, and a file of one page
/// under a strip that totals all of them would be a file whose total its own
/// rows do not reach. Under the rows are the strip's four figures.
library;

import 'dart:typed_data';

import '../../app/labels.dart';
import '../../core/export/workbook.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/models/branch_sales.dart' show businessDayWire;
import '../../domain/models/order_record.dart';
import '../../domain/repositories/repositories.dart';
import 'history_scope.dart';
import 'presentation/order_status_chip.dart';
import 'presentation/payment_status_chip.dart';

/// Rows per read while walking a filter for a file.
///
/// The same keyset walk as Next, ten of the list's pages at a stride: a
/// month at a busy counter read fifty rows at a time is over a hundred round
/// trips somebody waits through, and one read of everything is the unbounded
/// read `OrderHistoryQuery.limit` exists to refuse.
const exportPageSize = 500;

/// Every row [query]'s filter admits, newest first, narrowed for [viewer]
/// exactly as the list is — their own sales without `order.view_all`.
///
/// Through [HistoryScope.scope] and the repository's `search`, the list's own
/// road, so the file cannot hold a row the list would not show.
Future<List<OrderRecord>> ordersToExport(
  OrderHistoryRepository repository,
  OrderHistoryQuery query, {
  required PosStaff? viewer,
}) async {
  final scoped = HistoryScope.scope(query.unpaged, viewer);
  if (scoped == null) return const [];
  final rows = <OrderRecord>[];
  var page = scoped.copyWith(clearAfter: true, limit: exportPageSize);
  while (true) {
    final read = await repository.search(page);
    rows.addAll(read);
    // A short page is the last. A full one may be too, and the empty read
    // after it is the honest way to find out.
    if (read.length < exportPageSize) return rows;
    page = page.copyWith(afterOrderId: read.last.id);
  }
}

/// Every method a sale was paid in, in the reader's language and the order
/// they were taken — "Cash + Card" for a split bill. Through `tenderName`, so
/// a method the business renamed reads as they named it, as its receipt
/// does. The list's column and the file's are this one function.
String paidWith(OrderRecord order, AppStrings strings) => order.tenders.isEmpty
    ? '—'
    : order.tenders
          .map((t) => tenderName(t.tenderTypeId, t.label, strings))
          .join(' + ');

/// `sales-2026-09-01-2026-09-10.xlsx` — the business dates it covers, so two
/// exports of two weeks do not ask to overwrite each other.
String salesFileName(OrderHistoryQuery query) {
  final from = query.from;
  final to = query.to;
  if (from == null || to == null) return 'sales.xlsx';
  final last = DateTime(to.year, to.month, to.day - 1);
  return from == last
      ? 'sales-${businessDayWire(from)}.xlsx'
      : 'sales-${businessDayWire(from)}-${businessDayWire(last)}.xlsx';
}

/// Where the Total column is, so the figures under the rows sit under it.
const _totalColumn = 7;

/// [rows] as one sheet: the list's columns, then the strip's figures.
///
/// **The totals are [OrderHistorySummary.of] over the rows written**, the
/// rule the strip's SQL is held to (`order_history_paging_test.dart`). Read
/// again from the rows rather than copied from the strip: a sale rung up
/// between the strip's read and this one would otherwise put a total under
/// the rows that they do not add up to.
///
/// A struck-through sale keeps its total, as its row does, and the Status
/// column says why; the Total figure under them leaves it out and says so,
/// in the strip's own note.
Uint8List salesWorkbook({
  required List<OrderRecord> rows,
  required OrderHistoryQuery query,
  required AppStrings strings,
  required bool rightToLeft,
}) {
  final s = strings;
  final summary = OrderHistorySummary.of(rows);
  final book = WorkbookWriter(rightToLeft: rightToLeft);
  final sheet = book.sheet(s.tabSales)
    ..header([
      s.orderColumnInvoice,
      s.exportColumnOccurredAt,
      s.orderColumnType,
      s.orderColumnWhere,
      s.orderColumnStaff,
      s.orderColumnMethod,
      s.orderColumnTerminal,
      '${s.orderColumnTotal} (${summary.total.currency})',
      s.orderColumnStatus,
      s.orderColumnPayment,
      // After the page's own columns rather than where the screen has them, so
      // the Total column the figures sit under does not move: a file somebody
      // has built a formula over should not change under them.
      s.customersColumnCustomer,
      s.customersPhone,
    ]);
  for (final order in rows) {
    sheet.row([
      TextCell(order.invoiceNumber),
      DateTimeCell(order.occurredAt),
      TextCell(order.orderType.label(s)),
      _text(order.tableLabel),
      _text(order.servedByName),
      order.tenders.isEmpty ? null : TextCell(paidWith(order, s)),
      _text(order.terminalName),
      MoneyCell(order.total),
      TextCell(order.status.label(s)),
      TextCell(order.paymentStatus.label(s)),
      _text(order.customerName),
      _text(order.customerPhone),
    ]);
  }

  List<WorkbookCell?> figure(String label, WorkbookCell value, String? note) =>
      [
        TextCell(label),
        for (var i = 1; i < _totalColumn; i++) null,
        value,
        _text(note),
      ];
  sheet
    ..blank()
    ..row(
      figure(
        s.orderSummaryTotal,
        MoneyCell(summary.total),
        s.orderSummaryTotalNote,
      ),
    )
    ..row(
      figure(
        s.orderSummaryCount,
        CountCell(summary.count),
        summary.dead > 0 ? s.orderSummaryCountDead(summary.dead) : null,
      ),
    )
    ..row(
      figure(
        s.orderSummaryPaid,
        MoneyCell(summary.paid),
        s.orderSummaryPaidNote,
      ),
    )
    ..row(
      figure(
        s.orderSummaryOutstanding,
        MoneyCell(summary.outstanding),
        s.orderSummaryOutstandingNote,
      ),
    );
  final from = query.from;
  final to = query.to;
  if (from != null && to != null) {
    sheet
      ..blank()
      ..row([TextCell(s.exportPeriodFrom), DateCell(from)])
      ..row([
        TextCell(s.exportPeriodTo),
        DateCell(DateTime(to.year, to.month, to.day - 1)),
      ]);
  }
  return book.encode();
}

WorkbookCell? _text(String? value) =>
    value == null || value.isEmpty ? null : TextCell(value);
