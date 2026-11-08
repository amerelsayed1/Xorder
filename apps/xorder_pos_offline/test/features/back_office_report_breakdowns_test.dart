import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/excel_export.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/app/reports_providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/branch_sales.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/finance_report.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/profit_report.dart';
import 'package:shared_module/domain/models/sales_report.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/domain/services/authorization.dart';
import 'package:shared_module/features/admin_mode/admin_session.dart';
import 'package:xorder_pos_offline/features/admin/application/reports_view.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos_offline/features/admin/presentation/report_breakdown_panes.dart';
import 'package:xorder_pos_offline/features/admin/presentation/report_charts.dart';

import '../support/back_office.dart';
import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

/// Reports' five breakdowns (the owner's map) draw BO-5 and nothing else, over
/// the one period all six Reports items share.
///
/// **The expectations are read off what the fake handed the screen**, through
/// BO-5's own getters, as `back_office_reports_test.dart` reads the summary's:
/// a row that did its own sum, or a total from anywhere but the report's
/// rollup, disagrees with them.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

// Reads every report, may not export one — the gate the button must honour.
const _manager = PosStaff(
  id: 2,
  name: 'Mona F.',
  username: 'mona',
  role: PosRole(
    id: 2,
    code: SystemRoles.managerCode,
    nameEn: 'Manager',
    capabilities: {...SystemRoles.manager, PosCapability.adminEnter},
  ),
);

// Thursday, with the day open.
final _today = BusinessDay(
  id: 2,
  date: DateTime.utc(2026, 9, 10),
  openedAt: DateTime(2026, 9, 10, 8),
);

final _month = ReportFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 11));

MethodTotal _method(
  int id,
  String label,
  TenderKind kind,
  int amount, {
  bool cash = false,
}) => MethodTotal(
  tenderTypeId: id,
  label: label,
  kind: kind,
  countsAsCash: cash,
  count: 1,
  amount: Money(amount),
);

SalesReport _report(ReportFilter filter) => SalesReport(
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
        _method(1, 'Cash', TenderKind.cash, 200000, cash: true),
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
      payments: [
        _method(1, 'Cash', TenderKind.cash, 50000, cash: true),
        _method(4, 'Vodafone Cash', TenderKind.wallet, 47700),
      ],
    ),
    // Registered, and sold nothing: listed at zero (§3a rule 2).
    const TerminalSales(
      terminalId: 'c3',
      name: 'Delivery desk',
      orders: 0,
      gross: Money(0),
      discounts: Money(0),
      refunds: Money(0),
      refundCount: 0,
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
        // The fourth day shut: a dash for its average, not a zero.
        orders: i == 3 ? 0 : i + 1,
        gross: Money(i == 3 ? 0 : 10000 * (i + 1) + 50),
        discounts: Money(i == 3 ? 0 : 100 * i),
        refunds: Money(i == 5 ? 2500 : 0),
        refundCount: i == 5 ? 1 : 0,
      ),
  ],
);

/// The same sales and refunds as [_report], split by person — so the
/// Employees total is the summary's net tile, as the database's are.
StaffSalesReport _staff(ReportFilter filter) => StaffSalesReport(
  filter: filter,
  people: const [
    StaffSales(
      staffId: 7,
      name: 'Nour Adel',
      orders: 25,
      gross: Money(250000),
      discounts: Money(4000),
      refunds: Money(2500),
      refundCount: 1,
      voids: 2,
    ),
    StaffSales(
      staffId: 8,
      name: 'Hana Mostafa',
      orders: 17,
      gross: Money(161105),
      discounts: Money(1260),
      refunds: Money(340),
      refundCount: 3,
      voids: 0,
    ),
    // Sales that record nobody.
    StaffSales(
      staffId: null,
      name: null,
      orders: 1,
      gross: Money(1500),
      discounts: Money(0),
      refunds: Money(0),
      refundCount: 0,
      voids: 1,
    ),
  ],
);

// Six, so "every product" is more than the summary's five.
const _products = [
  ProductSales(menuItemId: 1, name: 'Koshari', quantity: 48, amount: Money(216000)),
  ProductSales(menuItemId: 2, name: 'Feteer', quantity: 30, amount: Money(255000)),
  ProductSales(menuItemId: 3, name: 'Hawawshi', quantity: 22, amount: Money(143000)),
  ProductSales(menuItemId: 4, name: 'Molokhia', quantity: 9, amount: Money(63000)),
  ProductSales(menuItemId: null, name: 'Om Ali', quantity: 4, amount: Money(26000)),
  ProductSales(menuItemId: 6, name: 'Tea', quantity: 2, amount: Money(1000)),
];

/// A test double. Never a default binding. Remembers what it was asked.
class _Fixed implements ReportsRepository {
  final sold = <ReportFilter, SalesReport>{};
  final staffed = <ReportFilter, StaffSalesReport>{};
  final listed = <(ReportFilter, ProductRanking, int?)>[];

  @override
  Future<SalesReport> sales(ReportFilter filter) async =>
      sold[filter] ??= _report(filter);

  @override
  Future<List<ProductSales>> topProducts(
    ReportFilter filter, {
    required ProductRanking by,
    int? limit = 5,
  }) async {
    listed.add((filter, by, limit));
    final ranked = [..._products]
      ..sort(
        (a, b) => switch (by) {
          ProductRanking.quantity => b.quantity.compareTo(a.quantity),
          ProductRanking.amount => b.amount.minor.compareTo(a.amount.minor),
        },
      );
    return limit == null ? ranked : ranked.take(limit).toList();
  }

  @override
  Future<StaffSalesReport> staffSales(ReportFilter filter) async =>
      staffed[filter] ??= _staff(filter);

  @override
  Future<TaxReport> taxes(ReportFilter filter) =>
      throw UnimplementedError('Reports draws no taxes');

  @override
  Future<PaymentLedger> payments(ReportFilter filter, {int limit = 500}) =>
      throw UnimplementedError('Reports draws no payment ledger');

  @override
  Future<ProfitReport> profit(ReportFilter filter) =>
      throw UnimplementedError('Reports draws no profit yet');
}

class _InAdminMode extends AdminSessionController {
  _InAdminMode(this.staff);

  final PosStaff staff;

  @override
  AdminSession? build() =>
      AdminSession(staff: staff, startedAt: DateTime(2026, 9, 10, 9));

  /// The door, once more: somebody else comes through it later.
  void enter(PosStaff next, DateTime at) =>
      state = AdminSession(staff: next, startedAt: at);
}

/// Everything saved, instead of a dialog.
class _Saved {
  final files = <(String, Uint8List)>[];

  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
  }) async {
    files.add((fileName, bytes));
    return '/exports/$fileName';
  }
}

const _localizations = <LocalizationsDelegate<dynamic>>[
  AppLocalizations(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// One breakdown on its own, at the back office's narrowest, tall enough that
/// every row is built. Opened on This month, as the summary would have left
/// it — which is the point of the shared period.
Future<(_Fixed, _Saved)> _pane(
  WidgetTester tester,
  Widget pane, {
  String language = 'en',
  bool database = true,
  PosStaff staff = _owner,
}) async {
  tester.view
    ..physicalSize = const Size(PosSize.wideShellMin, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = _Fixed();
  final saved = _Saved();
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      reportsRepositoryProvider.overrideWithValue(database ? repository : null),
      adminSessionProvider.overrideWith(() => _InAdminMode(staff)),
      businessDayProvider.overrideWith((ref) async => _today),
      workbookSaverProvider.overrideWithValue(saved.save),
    ],
  );
  addTearDown(container.dispose);
  container.read(reportPeriodProvider.notifier).select(ReportPeriod.month);
  container
      .read(terminalProfileProvider.notifier)
      .apply(const TerminalProfile(branchName: 'Maadi'));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: _localizations,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: Scaffold(body: pane),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, saved);
}

/// Every caption at or under [key], in reading order.
List<String> _texts(WidgetTester tester, String key) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(Text),
      matchRoot: true,
    ),
  ))
    ?text.data,
];

String _dashOr(Money? value) => value?.format(withCurrency: true) ?? '—';

const _breakdowns = <Widget>[
  ReportSalesPane(),
  ReportItemsPane(),
  ReportPaymentsPane(),
  ReportBranchesPane(),
  ReportEmployeesPane(),
];

void main() {
  const s = EnStrings();

  // The bundled faces: "fits at 1100" is a claim about IBM Plex, not about
  // the test font, which draws every glyph a full em wide.
  setUpAll(loadPosFonts);

  testWidgets('Sales: each day of the period, and the summary\'s tiles as its '
      'total', (tester) async {
    final (repository, _) = await _pane(tester, const ReportSalesPane());
    final report = repository.sold[_month]!;
    expect(report.days, hasLength(10));
    expect(_texts(tester, 'reports-range'), ['2026-09-01 → 2026-09-10']);

    for (final day in report.days) {
      expect(_texts(tester, 'reports-day-${businessDayWire(day.date)}'), [
        businessDayWire(day.date),
        '${day.orders}',
        day.gross.format(withCurrency: true),
        day.discounts.format(withCurrency: true),
        day.net.format(withCurrency: true),
        day.refunds.format(withCurrency: true),
        _dashOr(day.averageOrder),
      ]);
    }
    expect(
      _texts(tester, 'reports-day-2026-09-04').last,
      '—',
      reason: 'a shut day has no average, not an average of zero',
    );
    expect(_texts(tester, 'reports-days-total'), [
      s.reportBranchTotal,
      '${report.orders}',
      report.gross.format(withCurrency: true),
      report.discounts.format(withCurrency: true),
      report.net.format(withCurrency: true),
      report.refunds.format(withCurrency: true),
      report.averageOrder!.format(withCurrency: true),
    ]);

    final plot = find.byKey(const Key('reports-trend-plot'));
    TrendPainter painter() =>
        tester.widget<CustomPaint>(plot).painter! as TrendPainter;
    expect(painter().values, [for (final day in report.days) day.net.minor]);
    await tester.tap(find.byKey(const Key('reports-metric-orders')));
    await tester.pumpAndSettle();
    expect(painter().values, [for (final day in report.days) day.orders]);
  });

  testWidgets('Items: every product, not the top five, sortable, with the '
      'rows\' total said for what it is', (tester) async {
    final (repository, _) = await _pane(tester, const ReportItemsPane());
    expect(repository.listed.single, (_month, ProductRanking.quantity, null));

    for (final (i, product) in _products.indexed) {
      expect(_texts(tester, 'reports-item-$i'), [
        '${i + 1}',
        product.name,
        '${product.quantity}',
        product.amount.format(withCurrency: true),
      ]);
    }
    final totals = productTotals(_products);
    expect(_texts(tester, 'reports-items-total'), [
      s.reportAllItems,
      '${totals.quantity}',
      totals.amount.format(withCurrency: true),
    ]);
    expect(find.text(s.reportItemsNote), findsOneWidget);

    await tester.tap(find.byKey(const Key('reports-rank-amount')));
    await tester.pumpAndSettle();
    expect(repository.listed.last, (_month, ProductRanking.amount, null));
    expect(_texts(tester, 'reports-item-0')[1], 'Feteer');
    expect(_texts(tester, 'reports-item-5')[1], 'Tea');
    expect(
      _texts(tester, 'reports-items-total').last,
      totals.amount.format(withCurrency: true),
      reason: 'the order changes, the total does not',
    );
  });

  testWidgets('Payment methods: BO-5\'s shares with their counts, collected '
      'as the total, on account apart', (tester) async {
    final (repository, _) = await _pane(tester, const ReportPaymentsPane());
    final report = repository.sold[_month]!;
    final shares = report.tenderShares;
    expect(shares, hasLength(3));

    final bar = tester.widget<CustomPaint>(
      find.byKey(const Key('reports-share-bar')),
    );
    expect((bar.painter! as ShareBarPainter).basisPoints, [
      for (final share in shares) share.basisPoints,
    ]);
    String percent(int bp) =>
        '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%';
    for (final (i, share) in shares.indexed) {
      expect(_texts(tester, 'reports-method-$i'), [
        share.method.label,
        '${share.method.count}',
        share.method.amount.format(withCurrency: true),
        percent(share.basisPoints),
      ]);
    }
    expect(_texts(tester, 'reports-methods-total'), [
      s.financeKpiCollected,
      '${report.collectedPayments}',
      report.collected.format(withCurrency: true),
      '100.00%',
    ]);
    expect(report.collectedPayments, 4, reason: 'Cash twice, Visa, Vodafone');
    expect(_texts(tester, 'reports-methods-on-account'), [
      s.reportOnAccount,
      '1',
      report.onAccount.format(withCurrency: true),
    ]);
  });

  testWidgets('Branches & devices: every till, the idle one at zero, the '
      'branch their rollup, and one branch said as one', (tester) async {
    final (repository, _) = await _pane(tester, const ReportBranchesPane());
    final report = repository.sold[_month]!;

    for (final till in report.terminals) {
      expect(_texts(tester, 'reports-terminal-${till.terminalId}'), [
        if (till.name case final name?) name else ...[
          till.terminalId,
          s.reportUnregistered,
        ],
        '${till.orders}',
        till.gross.format(withCurrency: true),
        till.discounts.format(withCurrency: true),
        till.refunds.format(withCurrency: true),
        till.net.format(withCurrency: true),
      ]);
    }
    expect(_texts(tester, 'reports-terminal-c3')[1], '0');
    expect(_texts(tester, 'reports-terminal-total'), [
      s.reportBranchTotal,
      '${report.orders}',
      report.gross.format(withCurrency: true),
      report.discounts.format(withCurrency: true),
      report.refunds.format(withCurrency: true),
      report.net.format(withCurrency: true),
    ]);
    // The rows are the branch, to the piastre.
    expect(
      report.terminals.fold(Money.zero, (sum, t) => sum + t.net),
      report.net,
    );
    expect(find.text('Maadi'), findsOneWidget, reason: 'the branch, by name');
    expect(find.text(s.reportBranchesNote('Maadi')), findsOneWidget);
  });

  testWidgets('Employees: per person, the nobody-recorded row included, and '
      'a total equal to the summary\'s net', (tester) async {
    final (repository, _) = await _pane(tester, const ReportEmployeesPane());
    final staff = repository.staffed[_month]!;

    for (final person in staff.people) {
      expect(_texts(tester, 'reports-staff-${person.staffId ?? 'none'}'), [
        person.name ?? s.reportSellerNotRecorded,
        '${person.orders}',
        person.net.format(withCurrency: true),
        _dashOr(person.averageOrder),
        person.refunds.format(withCurrency: true),
        '${person.voids}',
      ]);
    }
    expect(_texts(tester, 'reports-staff-total'), [
      s.reportBranchTotal,
      '${staff.orders}',
      staff.net.format(withCurrency: true),
      staff.averageOrder!.format(withCurrency: true),
      staff.refunds.format(withCurrency: true),
      '${staff.voids}',
    ]);
    // The same period's summary, as the fake would give it.
    expect(staff.net, _report(_month).net);
    expect(find.text(s.reportStaffNote), findsOneWidget);
  });

  // A test per page rather than a loop over them: pumping a second scope over
  // the first leaves the first one's disposal to a timer the test outlives.
  group('with no database each page says so, not zeros', () {
    for (final pane in _breakdowns) {
      testWidgets('${pane.runtimeType}', (tester) async {
        await _pane(tester, pane, database: false);
        expect(find.text(s.reportNoDatabase), findsOneWidget);
        expect(find.text(s.reportNoProducts), findsNothing);
        expect(find.text(s.reportBranchTotal), findsNothing);
        expect(find.byKey(ExcelExportButton.buttonKey), findsNothing);
      });
    }
  });

  group('export (BO-11)', () {
    testWidgets('the owner\'s file is the page\'s rows — every item, and the '
        'total', (tester) async {
      final (_, saved) = await _pane(tester, const ReportItemsPane());
      await tester.tap(find.byKey(ExcelExportButton.buttonKey));
      await tester.pumpAndSettle();

      final (name, bytes) = saved.files.single;
      expect(name, 'report-items-2026-09-01-2026-09-10.xlsx');
      final book = xl.Excel.decodeBytes(bytes);
      expect(book.tables.keys, [s.reportsItems]);
      final rows = book.tables[s.reportsItems]!.rows;
      String? text(int row, int column) =>
          rows[row].length > column ? rows[row][column]?.value?.toString() : null;
      // From, to, currency, a blank line — then the table.
      expect(text(4, 1), s.exportColumnProduct);
      expect(
        [for (var i = 0; i < _products.length; i++) text(5 + i, 1)],
        [for (final p in _products) p.name],
      );
      expect(text(5 + _products.length, 1), s.reportAllItems);
    });

    for (final (pane, section, sheet) in [
      (const ReportSalesPane(), 'sales', s.reportsSales),
      (const ReportPaymentsPane(), 'payments', s.reportsPaymentMethods),
      (const ReportBranchesPane(), 'tills', s.reportsBranches),
      (const ReportEmployeesPane(), 'staff', s.reportsEmployees),
    ]) {
      testWidgets('$section: its own file, its own sheet', (tester) async {
        final (_, saved) = await _pane(tester, pane);
        await tester.tap(find.byKey(ExcelExportButton.buttonKey));
        await tester.pumpAndSettle();
        final (name, bytes) = saved.files.single;
        expect(name, 'report-$section-2026-09-01-2026-09-10.xlsx');
        expect(xl.Excel.decodeBytes(bytes).tables.keys, [sheet]);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('without report.export there is no button', (tester) async {
      expect(
        Authorization.check(_manager, PosCapability.reportsView).isAllowed,
        isTrue,
      );
      expect(
        Authorization.check(_manager, PosCapability.reportExport).isAllowed,
        isFalse,
      );
      await _pane(tester, const ReportEmployeesPane(), staff: _manager);
      expect(find.byKey(const Key('reports-staff-total')), findsOneWidget);
      expect(find.byKey(ExcelExportButton.buttonKey), findsNothing);
    });
  });

  testWidgets('the period survives switching items, and every item asks for '
      'it', (tester) async {
    // Items switched as the bar's التقارير menu switches them, the only way
    // between them since the owner took the sub-nav away (15 Sep 2026).
    final bar = BarRoute(ManagementPane.reports);
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository = _Fixed();
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        reportsRepositoryProvider.overrideWithValue(repository),
        businessDayProvider.overrideWith((ref) async => _today),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: _localizations,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildPosTheme(),
          home: bar.screen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterAdminMode(tester);

    await tester.tap(find.byKey(const Key('reports-period-month')));
    await tester.pumpAndSettle();
    expect(_texts(tester, 'reports-range'), ['2026-09-01 → 2026-09-10']);

    for (final (pane, key) in [
      (ManagementPane.reportsSales, 'reports-days-total'),
      (ManagementPane.reportsItems, 'reports-items-total'),
      (ManagementPane.reportsPayments, 'reports-methods-total'),
      (ManagementPane.reportsBranches, 'reports-terminal-total'),
      (ManagementPane.reportsEmployees, 'reports-staff-total'),
      (ManagementPane.reports, 'reports-tile-net'),
    ]) {
      await bar.open(tester, pane);
      expect(find.byKey(Key(key)), findsOneWidget, reason: pane.name);
      expect(
        _texts(tester, 'reports-range'),
        ['2026-09-01 → 2026-09-10'],
        reason: '${pane.name} opens on the month, not on Today',
      );
    }
    // Asked for the month by every road, and never for Today.
    final today = ReportFilter.day(DateTime(2026, 9, 10));
    expect(repository.sold.keys, contains(_month));
    expect(repository.staffed.keys, [_month]);
    expect(
      repository.listed.where((l) => l.$3 == null).map((l) => l.$1),
      everyElement(_month),
    );
    expect(
      repository.sold.keys.where((f) => f == today),
      hasLength(1),
      reason: 'only the summary\'s first read, before the month was chosen',
    );

    // A custom range too: chosen on one item, kept on the next.
    await bar.open(tester, ManagementPane.reportsItems);
    container
        .read(reportPeriodProvider.notifier)
        .pickCustom(first: DateTime(2026, 8, 3), last: DateTime(2026, 8, 9));
    await tester.pumpAndSettle();
    await bar.open(tester, ManagementPane.reportsEmployees);
    expect(_texts(tester, 'reports-range'), ['2026-08-03 → 2026-08-09']);
    expect(tester.takeException(), isNull);
  });

  test('a new Admin Mode session starts on Today', () {
    final container = ProviderContainer(
      overrides: [adminSessionProvider.overrideWith(() => _InAdminMode(_owner))],
    );
    addTearDown(container.dispose);
    final period = container.read(reportPeriodProvider.notifier);
    period.select(ReportPeriod.month);
    expect(container.read(reportPeriodProvider).period, ReportPeriod.month);
    // The manager comes through the door after the owner left.
    (container.read(adminSessionProvider.notifier) as _InAdminMode).enter(
      _manager,
      DateTime(2026, 9, 10, 14),
    );
    expect(container.read(reportPeriodProvider).period, ReportPeriod.today);
  });

  group('in Arabic, at 1100', () {
    for (final pane in _breakdowns) {
      testWidgets('${pane.runtimeType} fits, mirrored, with Western figures', (
        tester,
      ) async {
        await _pane(tester, pane, language: 'ar');
        expect(tester.takeException(), isNull);
        // The first date at the start edge — the right, in Arabic.
        final range = tester.widget<Text>(find.byKey(const Key('reports-range')));
        expect(range.textDirection, TextDirection.ltr);
        expect(range.data, '2026-09-01 → 2026-09-10');
        for (final chart in [
          ...tester.widgetList<CustomPaint>(
            find.byKey(const Key('reports-trend-plot')),
          ),
          ...tester.widgetList<CustomPaint>(
            find.byKey(const Key('reports-share-bar')),
          ),
        ]) {
          final direction = switch (chart.painter) {
            final TrendPainter p => p.direction,
            final ShareBarPainter p => p.direction,
            _ => null,
          };
          expect(direction, TextDirection.rtl);
        }
        expect(find.text(const ArStrings().reportBranchTotal).evaluate().length +
            find.text(const ArStrings().reportAllItems).evaluate().length +
            find.text(const ArStrings().financeKpiCollected).evaluate().length,
            greaterThan(0));
      });
    }
  });
}
