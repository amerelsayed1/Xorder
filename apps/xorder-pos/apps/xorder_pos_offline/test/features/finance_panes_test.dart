import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/app/reports_providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/widgets/mono_amount.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/branch_sales.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/finance_report.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/profit_report.dart';
import 'package:shared_module/domain/models/sales_report.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_finance_panes.dart';
import 'package:xorder_pos_offline/features/admin/presentation/report_breakdown_panes.dart';

import 'package:xorder_pos_test_support/fakes.dart';

// Holds `reports.view` through the role, as a real owner does;
// `PosStaff.capabilities` is direct grants only.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);
const _cashier = PosStaff(
  id: 4,
  name: 'Rana A.',
  role: PosRole(
    id: 2,
    code: 'cashier',
    nameEn: 'Cashier',
    capabilities: {PosCapability.operate},
  ),
);

Money _egp(int minor) => Money(minor, currency: 'EGP', exponent: 2);

MethodTotal _method(int id, String label, TenderKind kind, int count, int amount) =>
    MethodTotal(
      tenderTypeId: id,
      label: label,
      kind: kind,
      countsAsCash: kind == TenderKind.cash,
      count: count,
      amount: _egp(amount),
    );

/// Two terminals over two trading days of the filter, in piastres:
/// 80,000 gross, 5,000 off, 1,000 refunded, 74,000 net over 4 sales;
/// collected 53,000 (cash 38,000 in three, card 15,000), 12,000 on account.
SalesReport _salesFor(ReportFilter filter) => SalesReport(
  filter: filter,
  terminals: [
    TerminalSales(
      terminalId: 't1',
      name: 'POS-01',
      orders: 3,
      gross: _egp(60000),
      discounts: _egp(5000),
      refunds: _egp(1000),
      refundCount: 1,
      payments: [
        _method(1, 'Cash', TenderKind.cash, 2, 30000),
        _method(2, 'Card', TenderKind.card, 1, 15000),
      ],
    ),
    TerminalSales(
      terminalId: 't2',
      name: 'POS-02',
      orders: 1,
      gross: _egp(20000),
      discounts: _egp(0),
      refunds: _egp(0),
      refundCount: 0,
      payments: [
        _method(1, 'Cash', TenderKind.cash, 1, 8000),
        _method(4, 'Account', TenderKind.account, 1, 12000),
      ],
    ),
  ],
  // The same cells, by day: the 13th and the 14th, every other date zero.
  days: [
    for (final date in filter.dates)
      switch (date.day) {
        13 => ReportDay(
          date: date,
          orders: 1,
          gross: _egp(20000),
          discounts: _egp(0),
          refunds: _egp(0),
          refundCount: 0,
        ),
        14 => ReportDay(
          date: date,
          orders: 3,
          gross: _egp(60000),
          discounts: _egp(5000),
          refunds: _egp(1000),
          refundCount: 1,
        ),
        _ => ReportDay(
          date: date,
          orders: 0,
          gross: _egp(0),
          discounts: _egp(0),
          refunds: _egp(0),
          refundCount: 0,
        ),
      },
  ],
);

List<PaymentEntry> _entries() {
  PaymentEntry entry(int id, MethodTotal m, int amount, int hour) =>
      PaymentEntry(
        paymentId: id,
        orderId: 100 + id,
        invoiceNumber: 'INV-$id',
        occurredAt: DateTime(2026, 9, 14, hour),
        terminalId: 't1',
        terminalName: 'POS-01',
        tenderTypeId: m.tenderTypeId,
        label: m.label,
        kind: m.kind,
        countsAsCash: m.countsAsCash,
        amount: _egp(amount),
      );
  final cash = _method(1, 'Cash', TenderKind.cash, 0, 0);
  return [
    entry(5, cash, 8000, 20),
    entry(4, _method(4, 'Account', TenderKind.account, 0, 0), 12000, 18),
    entry(3, _method(2, 'Card', TenderKind.card, 0, 0), 15000, 15),
    entry(2, cash, 20000, 12),
    entry(1, cash, 10000, 10),
  ];
}

/// A test double. Never a default binding.
class _Books implements ReportsRepository {
  _Books({this.truncated = false});

  final bool truncated;
  final filters = <ReportFilter>[];
  var calls = 0;

  @override
  Future<SalesReport> sales(ReportFilter filter) async {
    calls++;
    filters.add(filter);
    return _salesFor(filter);
  }

  @override
  Future<List<ProductSales>> topProducts(
    ReportFilter filter, {
    required ProductRanking by,
    int? limit = 5,
  }) async => const [];

  @override
  Future<StaffSalesReport> staffSales(ReportFilter filter) =>
      throw UnimplementedError('Finance draws no staff');

  @override
  Future<TaxReport> taxes(ReportFilter filter) async {
    calls++;
    filters.add(filter);
    return TaxReport(
      filter: filter,
      rates: [
        TaxCollected(
          name: 'VAT',
          rateBp: 1400,
          orders: 4,
          base: _egp(70000),
          charged: _egp(9800),
          refunded: _egp(140),
        ),
        TaxCollected(
          name: 'Zero-rated',
          rateBp: 0,
          orders: 1,
          base: _egp(3000),
          charged: _egp(0),
          refunded: _egp(0),
        ),
      ],
      unattributedRefunds: _egp(25),
    );
  }

  @override
  Future<PaymentLedger> payments(ReportFilter filter, {int limit = 500}) async {
    calls++;
    filters.add(filter);
    final all = _entries();
    return PaymentLedger(
      filter: filter,
      entries: truncated ? all.take(3).toList() : all,
      truncated: truncated,
    );
  }

  @override
  Future<ProfitReport> profit(ReportFilter filter) =>
      throw UnimplementedError('Finance draws no profit');
}

class _Viewer extends SignedInStaffController {
  _Viewer(this.staff);

  final PosStaff? staff;

  @override
  PosStaff? build() => staff;
}

Future<(_Books, ProviderContainer)> _pump(
  WidgetTester tester,
  Widget pane, {
  PosStaff viewer = _owner,
  String language = 'en',
  _Books? books,
}) async {
  // Tall, so every row of every table is laid out: a ListView builds only
  // what it shows, and a sum over rows that were never built is no sum.
  tester.view
    ..physicalSize = const Size(1400, 3200)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = books ?? _Books();
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      reportsRepositoryProvider.overrideWithValue(repository),
      signedInStaffProvider.overrideWith(() => _Viewer(viewer)),
      // Trading in the 14th, so "this month" is 1–14 September.
      businessDayProvider.overrideWith(
        (ref) async => BusinessDay(
          id: 1,
          date: DateTime.utc(2026, 9, 14),
          openedAt: DateTime(2026, 9, 14, 8),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: Scaffold(body: pane),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, container);
}

Finder _in(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f);

/// The amounts drawn in the row keyed [key], in column order.
List<Money> _amounts(WidgetTester tester, Key key) => [
  for (final w in tester.widgetList<MonoAmount>(
    find.descendant(of: find.byKey(key), matching: find.byType(MonoAmount)),
  ))
    w.value,
];

/// Column by column, the sum of the amounts in every row whose key starts
/// with [prefix].
List<Money> _columnSums(WidgetTester tester, String prefix) {
  final rows = find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(prefix),
      )
      .evaluate()
      .map((e) => e.widget.key!)
      .toList();
  expect(rows, isNotEmpty, reason: prefix);
  List<Money>? sums;
  for (final key in rows) {
    final amounts = _amounts(tester, key);
    sums = sums == null
        ? amounts
        : [for (var i = 0; i < amounts.length; i++) sums[i] + amounts[i]];
  }
  return sums!;
}

/// Finance (BO-9): each pane's figures are the rows under them, and the
/// revenue is the Reports figure.
void main() {
  const s = EnStrings();
  final thisMonth = ReportFilter(
    from: DateTime(2026, 9, 1),
    to: DateTime(2026, 9, 15),
  );

  group('Overview', () {
    testWidgets('the tiles are the report and the tax, and the tender rows '
        'add up to what was collected', (tester) async {
      final (books, container) = await _pump(
        tester,
        const FinanceOverviewPane(),
      );
      final report = _salesFor(thisMonth);

      // Revenue is Reports' figure: the same provider, the same filter.
      final reports = container.read(salesReportProvider(thisMonth)).value!;
      expect(
        _in('finance-tile-revenue', find.text(reports.net.format(withCurrency: true))),
        findsOneWidget,
      );
      expect(reports.net, _egp(74000));
      expect(
        _in('finance-tile-collected', find.text(_egp(53000).format(withCurrency: true))),
        findsOneWidget,
      );
      expect(
        _in('finance-tile-on-account', find.text(_egp(12000).format(withCurrency: true))),
        findsOneWidget,
      );
      // 9,800 charged less 140 + 25 given back.
      expect(
        _in('finance-tile-tax', find.text(_egp(9635).format(withCurrency: true))),
        findsOneWidget,
      );
      expect(books.filters.toSet(), {thisMonth});

      // The bar's rows sum to the total line, which is the collected tile;
      // on account is not among them.
      final rows = _columnSums(tester, 'finance-tender-row-');
      expect(rows, _amounts(tester, const Key('finance-tender-total')));
      expect(rows.single, report.collected);
      for (final (i, share) in report.tenderShares.indexed) {
        expect(
          _in(
            'finance-tender-row-$i',
            find.text(formatShareBp(share.basisPoints)),
          ),
          findsOneWidget,
        );
      }
      expect(_in('finance-tender-total', find.text('100.00%')), findsOneWidget);
      expect(find.text('Account'), findsNothing, reason: 'owed, not taken');
      expect(
        _amounts(tester, const Key('finance-on-account')),
        [_egp(12000)],
      );
      expect(find.byType(TenderShareBar), findsOneWidget);
    });

    testWidgets('the period is the tab\'s, and choosing one asks for it', (
      tester,
    ) async {
      final (books, _) = await _pump(tester, const FinanceOverviewPane());
      expect(
        _in('finance-range', find.text('2026-09-01 → 2026-09-14')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('finance-period-lastMonth')));
      await tester.pumpAndSettle();
      expect(
        books.filters.last,
        ReportFilter(from: DateTime(2026, 8, 1), to: DateTime(2026, 9, 1)),
      );
      expect(
        _in('finance-range', find.text('2026-08-01 → 2026-08-31')),
        findsOneWidget,
      );

      // English weeks start on Sunday.
      await tester.tap(find.byKey(const Key('finance-period-thisWeek')));
      await tester.pumpAndSettle();
      expect(books.filters.last.from, DateTime(2026, 9, 13));
    });

    testWidgets('without reports.view there are no figures, and the database '
        'is not asked', (tester) async {
      final (books, _) = await _pump(
        tester,
        const FinanceOverviewPane(),
        viewer: _cashier,
      );
      expect(find.text(s.financeNoFigures), findsOneWidget);
      expect(find.byKey(const Key('finance-tile-revenue')), findsNothing);
      expect(books.calls, 0);
    });
  });

  testWidgets('Revenue: the days add up to the total line, which is the '
      'report\'s', (tester) async {
    await _pump(tester, const FinanceRevenuePane());
    final report = _salesFor(thisMonth);

    final days = _columnSums(tester, 'finance-revenue-day-');
    final total = _amounts(tester, const Key('finance-revenue-total'));
    expect(days, total);
    expect(total, [report.gross, report.discounts, report.refunds, report.net]);
    // Every date of the period is a row, the quiet ones at zero.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'finance-revenue-day-',
            ),
      ),
      findsNWidgets(14),
    );
    expect(_in('finance-tile-orders', find.text('4')), findsOneWidget);
    expect(
      _in('finance-tile-average', find.text(_egp(18500).format(withCurrency: true))),
      findsOneWidget,
    );
  });

  // Finance's own Payment methods page was merged into Reports › Payment
  // methods (XORD-022-A, owner's decision 2026-10-25): the by-method table is
  // the report's, and the ledger of every payment is a section under it. These
  // keep the claim the old page's tests made: the two ways of adding the same
  // money agree.
  group('Payments ledger, under Reports › Payment methods', () {
    testWidgets('the payments listed add up to their total, and to what the '
        'report collected plus what is on account — the same money both '
        'ways', (tester) async {
      await _pump(tester, ReportPaymentsPane(openedAt: DateTime(2026, 9, 14)));

      final ledger = _columnSums(tester, 'finance-ledger-row-');
      final ledgerTotal = _amounts(tester, const Key('finance-ledger-total'));
      expect(ledger, ledgerTotal);

      final collected = _amounts(tester, const Key('reports-methods-total'));
      final onAccount = _amounts(
        tester,
        const Key('reports-methods-on-account'),
      );
      expect(collected.single + onAccount.single, ledgerTotal.single);
      expect(ledgerTotal, [_egp(65000)]);
      expect(find.text(s.financeLedgerTruncated(3)), findsNothing);
    });

    testWidgets('a cut list says so, and its total is only what it lists', (
      tester,
    ) async {
      await _pump(
        tester,
        ReportPaymentsPane(openedAt: DateTime(2026, 9, 14)),
        books: _Books(truncated: true),
      );
      expect(find.text(s.financeLedgerTruncated(3)), findsOneWidget);
      expect(
        _columnSums(tester, 'finance-ledger-row-'),
        _amounts(tester, const Key('finance-ledger-total')),
      );
      // The report's own table still covers the period.
      expect(
        _amounts(tester, const Key('reports-methods-total')).single +
            _amounts(tester, const Key('reports-methods-on-account')).single,
        _egp(65000),
      );
    });
  });

  testWidgets('Taxes: the rates, and what has no rate, add up to the total '
      'line', (tester) async {
    await _pump(tester, const FinanceTaxesPane());

    // Base, charged, refunded, net per rate row.
    final rates = _columnSums(tester, 'finance-tax-row-');
    final unattributed = _amounts(
      tester,
      const Key('finance-tax-unattributed'),
    );
    final total = _amounts(tester, const Key('finance-tax-total'));
    expect(unattributed, [_egp(25), _egp(-25)]);
    expect(total, [
      rates[0],
      rates[1],
      rates[2] + unattributed[0],
      rates[3] + unattributed[1],
    ]);
    expect(total, [_egp(73000), _egp(9800), _egp(165), _egp(9635)]);
    expect(_in('finance-tax-row-0', find.text('14%')), findsOneWidget);
    expect(_in('finance-tax-row-1', find.text('0%')), findsOneWidget);
  });

  testWidgets('in Arabic: Arabic words, Latin digits left to right, the '
      'period from the right and the week from Saturday', (tester) async {
    final (books, _) = await _pump(
      tester,
      const FinanceOverviewPane(),
      language: 'ar',
    );
    const ar = ArStrings();

    expect(find.text(ar.financeKpiRevenue), findsOneWidget);
    expect(find.text(ar.financeTendersTitle), findsOneWidget);
    expect(find.text(s.financeKpiRevenue), findsNothing);

    final amount = tester.widget<Directionality>(
      find
          .descendant(
            of: find.byKey(const Key('finance-tile-revenue')),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(amount.textDirection, TextDirection.ltr);

    final today = tester.getRect(find.byKey(const Key('finance-period-today')));
    final last = tester.getRect(
      find.byKey(const Key('finance-period-lastMonth')),
    );
    expect(today.left, greaterThan(last.left), reason: 'start is right');

    await tester.tap(find.byKey(const Key('finance-period-thisWeek')));
    await tester.pumpAndSettle();
    expect(books.filters.last.from, DateTime(2026, 9, 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Taxes in Arabic lay out without overflow', (tester) async {
    await _pump(tester, const FinanceTaxesPane(), language: 'ar');
    expect(find.text(const ArStrings().financeTaxNote), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('every period is named in both languages', () {
    for (final lang in const <AppStrings>[EnStrings(), ArStrings()]) {
      final names = {
        for (final p in FinancePeriod.values) financePeriodLabel(lang, p),
      };
      expect(names, hasLength(FinancePeriod.values.length));
    }
    expect(formatShareBp(7170), '71.70%');
    expect(formatShareBp(5), '0.05%');
    expect(formatShareBp(10000), '100.00%');
  });
}
