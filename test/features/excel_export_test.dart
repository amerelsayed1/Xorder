import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/excel_export.dart';
import 'package:xorder_pos/app/labels.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/reports_providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/finance_report.dart';
import 'package:xorder_pos/domain/models/profit_report.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_home_pane.dart'
    show formatDeltaBp;
import 'package:xorder_pos/features/admin/presentation/management_reports_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos/features/admin/presentation/report_charts.dart';
import 'package:xorder_pos/features/history/presentation/order_history_screen.dart';
import 'package:xorder_pos/features/history/presentation/order_status_chip.dart';
import 'package:xorder_pos/features/history/presentation/payment_status_chip.dart';
import 'package:xorder_pos/features/history/sales_export.dart';

import '../support/fakes.dart';

/// BO-11: the Excel button on Reports and on the Sales list.
///
/// **The claim is that the file is the screen.** So each workbook here is
/// parsed back with the same `excel` package that wrote it and read cell by
/// cell against what the screen printed — the reports' tiles, rows and
/// totals, and the sales list's rows and strip — through the screen's own
/// formatting of each cell's value. A file that summed anything itself, or
/// wrote an amount as text, disagrees.
///
/// Everybody here holds what they hold through a ROLE and nothing directly:
/// `PosStaff.capabilities` is direct grants only, and a gate that read it
/// would refuse the owner.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

/// Let into Admin Mode and reads every report — and may not take one away.
const _manager = PosStaff(
  id: 2,
  name: 'Mona K.',
  username: 'mona',
  role: PosRole(
    id: 2,
    code: SystemRoles.managerCode,
    nameEn: 'Manager',
    capabilities: {...SystemRoles.manager, PosCapability.adminEnter},
    isSystem: true,
  ),
);

/// What the save dialog was handed. A test double, never a default binding.
class _Dialog {
  final saved = <({String fileName, Uint8List bytes})>[];

  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
    required String dialogTitle,
  }) async {
    saved.add((fileName: fileName, bytes: bytes));
    return '/exports/$fileName';
  }
}

/// A sheet read back, each cell as the plain Dart value it holds.
List<List<Object?>> _sheet(Uint8List bytes, String name) {
  final table = xl.Excel.decodeBytes(bytes).tables[name];
  expect(table, isNotNull, reason: 'no sheet named $name');
  return [
    for (final row in table!.rows) [for (final cell in row) _plain(cell?.value)],
  ];
}

Object? _plain(xl.CellValue? cell) => switch (cell) {
  null => null,
  xl.TextCellValue(:final value) => value.toString(),
  xl.IntCellValue(:final value) => value,
  xl.DoubleCellValue(:final value) => value,
  xl.DateCellValue() => cell.asDateTimeLocal(),
  xl.DateTimeCellValue() => cell.asDateTimeLocal(),
  _ => '$cell',
};

/// An amount cell back in minor units. It must be a number: text fails the
/// cast, which is the failure this is here to catch.
int _minor(Object? cell) => Money.tryParse('${cell! as num}')!.minor;

/// A percentage cell back in basis points.
int _bp(Object? cell) => ((cell! as num) * 10000).round();

String _printed(Object? cell) => Money(_minor(cell)).format();

/// Every caption at or under [key], in reading order.
List<String> _texts(WidgetTester tester, Key key) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byType(Text),
      matchRoot: true,
    ),
  ))
    ?text.data,
];

const _localizations = <LocalizationsDelegate<dynamic>>[
  AppLocalizations(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

// ── Reports ───────────────────────────────────────────────────────────────

final _businessDay = BusinessDay(
  id: 2,
  date: DateTime.utc(2026, 9, 10),
  openedAt: DateTime(2026, 9, 10, 8),
);

MethodTotal _method(int id, String label, TenderKind kind, int amount) =>
    MethodTotal(
      tenderTypeId: id,
      label: label,
      kind: kind,
      countsAsCash: kind == TenderKind.cash,
      count: 1,
      amount: Money(amount),
    );

SalesReport _current(ReportFilter filter) => SalesReport(
  filter: filter,
  terminals: [
    TerminalSales(
      terminalId: 'a1',
      name: 'Counter 1',
      orders: 30,
      gross: const Money(312345),
      discounts: const Money(4500),
      refunds: const Money(2500),
      refundCount: 1,
      payments: [
        _method(1, 'Cash', TenderKind.cash, 200000),
        _method(2, 'Visa', TenderKind.card, 98345),
        _method(3, 'On account', TenderKind.account, 7000),
      ],
    ),
    TerminalSales(
      terminalId: 'b2',
      name: 'Terrace',
      orders: 12,
      gross: const Money(98760),
      discounts: const Money(760),
      refunds: const Money(300),
      refundCount: 2,
      payments: [_method(4, 'Vodafone Cash', TenderKind.wallet, 97700)],
    ),
    // Took money here without being registered to the branch.
    const TerminalSales(
      terminalId: 'f00d-9',
      name: null,
      orders: 1,
      gross: Money(1500),
      discounts: Money(0),
      refunds: Money(40),
      refundCount: 1,
    ),
  ],
  days: [
    for (final (i, date) in filter.dates.indexed)
      ReportDay(
        date: date,
        // The fourth day shut: its average is a gap, not a zero.
        orders: i == 3 ? 0 : i + 1,
        gross: Money(i == 3 ? 0 : 10000 * (i + 1) + 50),
        discounts: Money(i == 3 ? 0 : 100 * i),
        refunds: Money(i == 5 ? 2500 : 0),
        refundCount: i == 5 ? 1 : 0,
      ),
  ],
);

SalesReport _previous(ReportFilter filter) => SalesReport(
  filter: filter,
  terminals: const [
    TerminalSales(
      terminalId: 'a1',
      name: 'Counter 1',
      orders: 40,
      gross: Money(300000),
      discounts: Money(0),
      refunds: Money(5000),
      refundCount: 2,
    ),
  ],
  days: [
    for (final date in filter.dates)
      ReportDay(
        date: date,
        orders: 0,
        gross: Money.zero,
        discounts: Money.zero,
        refunds: Money.zero,
        refundCount: 0,
      ),
  ],
);

const _topFive = [
  ProductSales(menuItemId: 1, name: 'Koshari', quantity: 48, amount: Money(216000)),
  ProductSales(menuItemId: 2, name: 'Feteer', quantity: 30, amount: Money(255000)),
  ProductSales(menuItemId: 3, name: 'Hawawshi', quantity: 22, amount: Money(143000)),
  ProductSales(menuItemId: 4, name: 'Molokhia', quantity: 9, amount: Money(63000)),
  ProductSales(menuItemId: null, name: 'Om Ali', quantity: 4, amount: Money(26000)),
];

/// A test double. Never a default binding. Answers the first period asked
/// as the one on screen, its `previous` as the comparison, and remembers.
class _Fixed implements ReportsRepository {
  final served = <ReportFilter, SalesReport>{};

  @override
  Future<SalesReport> sales(ReportFilter filter) async {
    final isPrevious = served.keys.any((shown) => shown.previous == filter);
    return served[filter] ??=
        isPrevious ? _previous(filter) : _current(filter);
  }

  @override
  Future<List<ProductSales>> topProducts(
    ReportFilter filter, {
    required ProductRanking by,
    int? limit = 5,
  }) async => _topFive;

  @override
  Future<StaffSalesReport> staffSales(ReportFilter filter) =>
      throw UnimplementedError('the summary writes no staff');

  // Finance's (BO-9); neither export asks for them.
  @override
  Future<TaxReport> taxes(ReportFilter filter) =>
      throw UnimplementedError('the exports write no taxes');

  @override
  Future<PaymentLedger> payments(ReportFilter filter, {int limit = 500}) =>
      throw UnimplementedError('the exports write no payment ledger');

  @override
  Future<ProfitReport> profit(ReportFilter filter) =>
      throw UnimplementedError('the exports write no profit');
}

class _InAdminMode extends AdminSessionController {
  _InAdminMode(this.staff);

  final PosStaff staff;

  @override
  AdminSession? build() =>
      AdminSession(staff: staff, startedAt: DateTime(2026, 9, 10, 9));
}

Future<(_Fixed, _Dialog)> _reports(
  WidgetTester tester, {
  required PosStaff staff,
  String language = 'en',
}) async {
  // The back office's narrowest, where the button shares its row with four
  // chips and the range; tall enough that every section is built.
  tester.view
    ..physicalSize = const Size(1100, 2200)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = _Fixed();
  final dialog = _Dialog();
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      reportsRepositoryProvider.overrideWithValue(repository),
      adminSessionProvider.overrideWith(() => _InAdminMode(staff)),
      businessDayProvider.overrideWith((ref) async => _businessDay),
      workbookSaverProvider.overrideWithValue(dialog.save),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: _localizations,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: const Scaffold(body: ManagementReportsPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, dialog);
}

Future<Uint8List> _export(WidgetTester tester, _Dialog dialog) async {
  await tester.tap(find.byKey(ExcelExportButton.buttonKey));
  await tester.pumpAndSettle();
  return dialog.saved.single.bytes;
}

/// A till row as the screen prints it: the name, the unregistered word when
/// there is one, the count, and four amounts.
List<String> _tillAsPrinted(List<Object?> row) => [
  row[0]! as String,
  if (row[6] case final String note) note,
  '${row[1]}',
  for (final cell in row.sublist(2, 6)) _printed(cell),
];

// ── Sales ─────────────────────────────────────────────────────────────────

final _now = DateTime.now();
final _day = DateTime(_now.year, _now.month, _now.day);

/// A hundred and twenty sales today — two full pages and a part one — with
/// every tenth voided and every seventh part paid, so each figure on the
/// strip has something in it and a struck-through row is among them.
final _orders = [
  for (var i = 0; i < 120; i++)
    OrderRecord(
      id: i + 1,
      clientTransactionId: 'txn-$i',
      invoiceNumber: 'INV-${(i + 1).toString().padLeft(4, '0')}',
      status: i % 10 == 3 ? OrderStatus.voided : OrderStatus.paid,
      orderType: i.isOdd ? OrderType.dineIn : OrderType.takeaway,
      occurredAt: _day.add(Duration(hours: 8, minutes: i)),
      subtotal: Money(10000 + i * 105),
      discount: Money.zero,
      service: Money.zero,
      vat: Money.zero,
      total: Money(10000 + i * 105),
      paidTotal: Money(i % 7 == 5 ? 4000 : 10000 + i * 105),
      tableLabel: i.isOdd ? 'T${i % 12}' : null,
      servedByStaffId: 1,
      servedByName: 'Amer M.',
      terminalName: 'Counter',
      tenders: const [OrderRecordTender(tenderTypeId: 1, label: 'Cash')],
      // Every third sale is for somebody, so the file has both a customer and a
      // blank to get right.
      customerName: i % 3 == 0 ? 'Mona Fathy' : null,
      customerPhone: i % 3 == 0 ? '01012345678' : null,
    ),
];

Future<(FakeOrderHistoryRepository, _Dialog)> _sales(
  WidgetTester tester, {
  required String username,
  required String pin,
  String language = 'en',
}) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = FakeOrderHistoryRepository(orders: _orders);
  final dialog = _Dialog();
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      orderHistoryRepositoryProvider.overrideWithValue(repository),
      // No day open: "Today" is the calendar date.
      businessDayProvider.overrideWith((ref) async => null),
      tenderTypesAllProvider.overrideWith((ref) async => const []),
      refundsForOrderProvider.overrideWith((ref, _) async => const <Refund>[]),
      workbookSaverProvider.overrideWithValue(dialog.save),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: _localizations,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: ManagementScreen(
          onClose: () {},
          onReconfigure: () {},
          initialPane: ManagementPane.sales,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await enterAdminMode(tester, username: username, pin: pin);
  return (repository, dialog);
}

void main() {
  const s = EnStrings();
  const ar = ArStrings();

  group('Reports', () {
    testWidgets('without report.export — a manager who reads every report — '
        'there is no button', (tester) async {
      expect(
        Authorization.check(_manager, PosCapability.reportsView).isAllowed,
        isTrue,
      );
      expect(
        Authorization.check(_manager, PosCapability.reportExport).isAllowed,
        isFalse,
      );
      await _reports(tester, staff: _manager);
      expect(find.byKey(const Key('reports-tile-net')), findsOneWidget);
      expect(find.byKey(ExcelExportButton.buttonKey), findsNothing);
    });

    testWidgets('the owner, through the role: the file is the tab, cell for '
        'cell', (tester) async {
      expect(_owner.capabilities, isEmpty, reason: 'held through the role');
      expect(
        Authorization.check(_owner, PosCapability.reportExport).isAllowed,
        isTrue,
      );
      final (repository, dialog) = await _reports(tester, staff: _owner);
      await tester.tap(find.byKey(const Key('reports-period-month')));
      await tester.pumpAndSettle();
      final bytes = await _export(tester, dialog);
      expect(tester.takeException(), isNull);

      expect(
        dialog.saved.single.fileName,
        'report-2026-09-01-2026-09-10.xlsx',
      );
      expect(
        _texts(tester, ExcelExportButton.noteKey),
        [s.exportExcelSaved('/exports/report-2026-09-01-2026-09-10.xlsx')],
      );
      final filter = repository.served.keys.firstWhere(
        (f) => f.from == DateTime(2026, 9, 1),
      );
      final report = repository.served[filter]!;

      final book = xl.Excel.decodeBytes(bytes);
      expect(book.tables.keys, [
        s.exportSheetSummary,
        s.reportTrend,
        s.reportTerminals,
        s.reportPayments,
        s.reportTopProducts,
      ]);
      expect(book.tables.values.map((t) => t.isRTL), everyElement(isFalse));

      // The tiles, and each one's change, as the tile prints them.
      final summary = _sheet(bytes, s.exportSheetSummary);
      expect(summary[0], [s.exportPeriodFrom, DateTime(2026, 9, 1), null, null]);
      expect(summary[1], [s.exportPeriodTo, DateTime(2026, 9, 10), null, null]);
      expect(summary[2], [s.currency, 'EGP', null, null]);
      expect(summary[4], [
        s.exportColumnFigure,
        s.exportColumnValue,
        s.reportVsPrevious,
        s.exportColumnNote,
      ]);
      final net = _texts(tester, const Key('reports-tile-net'));
      expect(summary[5][0], s.homeKpiNetSales);
      expect([_printed(summary[5][1]), formatDeltaBp(_bp(summary[5][2]))], [
        net[1],
        net[2],
      ]);
      final average = _texts(tester, const Key('reports-tile-average'));
      expect(
        [_printed(summary[6][1]), formatDeltaBp(_bp(summary[6][2]))],
        [average[1], average[2]],
      );
      final orders = _texts(tester, const Key('reports-tile-orders'));
      expect(
        ['${summary[7][1]}', formatDeltaBp(_bp(summary[7][2]))],
        [orders[1], orders[2]],
      );
      final refunds = _texts(tester, const Key('reports-tile-refunds'));
      expect(
        [
          _printed(summary[8][1]),
          summary[8][3],
          formatDeltaBp(_bp(summary[8][2])),
        ],
        [refunds[1], refunds[2], refunds[3]],
      );

      // Every till, the stranger included, and the branch under them.
      final tills = _sheet(bytes, s.reportTerminals);
      expect(tills.first, [
        s.orderColumnTerminal,
        s.homeKpiOrders,
        '${s.dayGross} (EGP)',
        '${s.orderDetailDiscounts} (EGP)',
        '${s.reportKpiRefunds} (EGP)',
        '${s.homeKpiNetSales} (EGP)',
        s.exportColumnNote,
      ]);
      expect(tills, hasLength(report.terminals.length + 2));
      for (final (i, till) in report.terminals.indexed) {
        expect(
          _tillAsPrinted(tills[i + 1]),
          _texts(tester, Key('reports-terminal-${till.terminalId}')),
        );
      }
      expect(
        _tillAsPrinted(tills.last),
        _texts(tester, const Key('reports-terminal-total')),
      );

      // The days the trend plots — the line's own values — with a gap for
      // the shut day's average, and the same branch total under them.
      final days = _sheet(bytes, s.reportTrend);
      final dayRows = days.sublist(1, days.length - 1);
      expect(
        [for (final row in dayRows) businessDayWire(row[0]! as DateTime)],
        [for (final day in report.days) businessDayWire(day.date)],
      );
      final plot = find.byKey(const Key('reports-trend-plot'));
      expect(
        [for (final row in dayRows) _minor(row[5])],
        (tester.widget<CustomPaint>(plot).painter! as TrendPainter).values,
      );
      expect(dayRows[3][6], isNull);
      expect(days.last.sublist(1, 6), tills.last.sublist(1, 6));

      // The payment methods: BO-5's shares, and on account on its own.
      final payments = _sheet(bytes, s.reportPayments);
      final shares = report.tenderShares;
      for (final (i, _) in shares.indexed) {
        final row = payments[i + 1];
        final bp = _bp(row[2]);
        expect(
          [
            row[0],
            _printed(row[1]),
            '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%',
          ],
          _texts(tester, Key('reports-tender-$i')),
        );
      }
      final owed = payments[shares.length + 1];
      expect(
        [owed[0], _printed(owed[1])],
        _texts(tester, const Key('reports-on-account')),
      );

      // The top five, in the order on screen.
      final top = _sheet(bytes, s.reportTopProducts);
      for (var i = 0; i < _topFive.length; i++) {
        final row = top[i + 1];
        expect(
          ['${row[0]}', row[1], '${row[2]}', _printed(row[3])],
          _texts(tester, Key('reports-product-$i')),
        );
      }
    });

    testWidgets('in Arabic: Arabic headings, right to left, the same figures', (
      tester,
    ) async {
      final (_, dialog) = await _reports(tester, staff: _owner, language: 'ar');
      final bytes = await _export(tester, dialog);
      expect(tester.takeException(), isNull);

      final book = xl.Excel.decodeBytes(bytes);
      expect(book.tables.keys, [
        ar.exportSheetSummary,
        ar.reportTrend,
        ar.reportTerminals,
        ar.reportPayments,
        ar.reportTopProducts,
      ]);
      expect(book.tables.values.map((t) => t.isRTL), everyElement(isTrue));

      final tills = _sheet(bytes, ar.reportTerminals);
      expect(tills.first, [
        ar.orderColumnTerminal,
        ar.homeKpiOrders,
        '${ar.dayGross} (EGP)',
        '${ar.orderDetailDiscounts} (EGP)',
        '${ar.reportKpiRefunds} (EGP)',
        '${ar.homeKpiNetSales} (EGP)',
        ar.exportColumnNote,
      ]);
      expect(
        _tillAsPrinted(tills.last),
        _texts(tester, const Key('reports-terminal-total')),
      );
      expect(_sheet(bytes, ar.exportSheetSummary)[5].first, ar.homeKpiNetSales);
    });
  });

  group('Sales', () {
    testWidgets('without report.export — the supervisor let into Admin Mode '
        '— there is no button', (tester) async {
      const nour = PosStaff(
        id: 3,
        name: 'Nour S.',
        username: 'nour',
        role: FakeSessionRepository.trustedSupervisor,
      );
      expect(
        Authorization.check(nour, PosCapability.reportExport).isAllowed,
        isFalse,
      );
      await _sales(tester, username: 'nour', pin: '2468');
      // The list is there — her own sales, of which she rang up none.
      expect(find.byKey(OrderHistoryScreen.ownSalesKey), findsOneWidget);
      expect(find.byKey(ExcelExportButton.buttonKey), findsNothing);
    });

    testWidgets('the owner\'s file holds every page of the filter, row for '
        'row, and the strip\'s four figures', (tester) async {
      final (repository, dialog) = await _sales(
        tester,
        username: 'amer',
        pin: '4321',
      );
      // On screen: page one of three.
      expect(_texts(tester, OrderHistoryScreen.pagerTotalKey), ['120']);
      expect(_texts(tester, OrderHistoryScreen.pagerRangeKey), ['1–50']);

      final bytes = await _export(tester, dialog);
      expect(tester.takeException(), isNull);
      expect(
        dialog.saved.single.fileName,
        'sales-${businessDayWire(_day)}.xlsx',
      );
      // Walked through the list's road, a page at a time.
      expect(
        repository.queries.where((q) => q.limit == exportPageSize),
        isNotEmpty,
      );

      final sheet = _sheet(bytes, s.tabSales);
      expect(xl.Excel.decodeBytes(bytes).tables[s.tabSales]!.isRTL, isFalse);
      expect(sheet.first, [
        s.orderColumnInvoice,
        s.exportColumnOccurredAt,
        s.orderColumnType,
        s.orderColumnWhere,
        s.orderColumnStaff,
        s.orderColumnMethod,
        s.orderColumnTerminal,
        '${s.orderColumnTotal} (EGP)',
        s.orderColumnStatus,
        s.orderColumnPayment,
        // After the page's own columns, so Total does not move.
        s.customersColumnCustomer,
        s.customersPhone,
      ]);

      // Every sale, newest first as the list pages them, each cell the
      // row's own value — the amount a number, the time a date.
      final newestFirst = [..._orders]
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      final rows = sheet.sublist(1, 1 + newestFirst.length);
      for (final (i, order) in newestFirst.indexed) {
        final row = rows[i];
        expect(
          [...row.sublist(0, 7), _minor(row[7]), ...row.sublist(8)],
          [
            order.invoiceNumber,
            order.occurredAt,
            order.orderType.label(s),
            order.tableLabel,
            order.servedByName,
            paidWith(order, s),
            order.terminalName,
            order.total.minor,
            order.status.label(s),
            order.paymentStatus.label(s),
            order.customerName,
            order.customerPhone,
          ],
          reason: order.invoiceNumber,
        );
      }
      // And the rows in view are the file's first, as the list draws them.
      for (final row in rows.take(8)) {
        expect(find.text(row[0]! as String), findsOneWidget);
      }
      expect(find.text(rows[50][0]! as String), findsNothing);

      // Under them, the strip's four figures, as the strip prints them.
      final figures = sheet.sublist(rows.length + 2, rows.length + 6);
      expect([for (final f in figures) f[0]], [
        s.orderSummaryTotal,
        s.orderSummaryCount,
        s.orderSummaryPaid,
        s.orderSummaryOutstanding,
      ]);
      expect(
        [
          _printed(figures[0][7]),
          '${figures[1][7]}',
          _printed(figures[2][7]),
          _printed(figures[3][7]),
        ],
        [
          ..._texts(tester, OrderHistoryScreen.summaryTotalKey),
          ..._texts(tester, OrderHistoryScreen.summaryCountKey),
          ..._texts(tester, OrderHistoryScreen.summaryPaidKey),
          ..._texts(tester, OrderHistoryScreen.summaryOutstandingKey),
        ],
      );
      expect(figures[1][8], s.orderSummaryCountDead(12));
      expect(sheet[rows.length + 7].take(2), [s.exportPeriodFrom, _day]);
      expect(sheet[rows.length + 8].take(2), [s.exportPeriodTo, _day]);
    });

    testWidgets('in Arabic: Arabic headings and right to left', (tester) async {
      final (_, dialog) = await _sales(
        tester,
        username: 'amer',
        pin: '4321',
        language: 'ar',
      );
      final bytes = await _export(tester, dialog);
      expect(tester.takeException(), isNull);
      expect(xl.Excel.decodeBytes(bytes).tables[ar.tabSales]!.isRTL, isTrue);
      final sheet = _sheet(bytes, ar.tabSales);
      expect(sheet.first.first, ar.orderColumnInvoice);
      expect(sheet.first[7], '${ar.orderColumnTotal} (EGP)');
      expect(sheet[_orders.length + 2].first, ar.orderSummaryTotal);
    });
  });
}
