import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/reports_providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/finance_report.dart';
import 'package:xorder_pos/domain/models/home_sales.dart' show deltaBp;
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_home_pane.dart'
    show formatDeltaBp;
import 'package:xorder_pos/features/admin/presentation/management_reports_pane.dart';
import 'package:xorder_pos/features/admin/presentation/report_charts.dart';

import '../support/fakes.dart';

/// The Reports tab (BO-6) draws BO-5 and nothing else.
///
/// **The claim is that every number on it is the repository's.** So the
/// expectations here are not typed-in figures: each is read off the very
/// `SalesReport` and `ProductSales` the fake handed the screen, through
/// BO-5's own getters. A tile that did its own sum, or a row that showed a
/// figure from somewhere else, disagrees with them.
///
/// The owner comes through Admin Mode's door holding `reports.view` by ROLE,
/// with nobody signed in at the till — the case the gate used to refuse.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

// Thursday, with the day open.
final _today = BusinessDay(
  id: 2,
  date: DateTime.utc(2026, 9, 10),
  openedAt: DateTime(2026, 9, 10, 8),
);

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

/// The period on screen. Figures chosen so no two cells of a row print
/// alike: an ordered read of a row then says which cell holds which figure.
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
    // Took money here without being registered to the branch (§3a rule 2).
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
        // The fourth day shut: a zero on the net line, a gap on the average.
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

const _koshari = ProductSales(
  menuItemId: 1,
  name: 'Koshari',
  quantity: 48,
  amount: Money(216000),
);
const _feteer = ProductSales(
  menuItemId: 2,
  name: 'Feteer',
  quantity: 30,
  amount: Money(255000),
);

const _byQuantity = [
  _koshari,
  _feteer,
  ProductSales(
    menuItemId: 3,
    name: 'Hawawshi',
    quantity: 22,
    amount: Money(143000),
  ),
  ProductSales(
    menuItemId: 4,
    name: 'Molokhia',
    quantity: 9,
    amount: Money(63000),
  ),
  // An open-price line: no menu item, grouped by its name.
  ProductSales(
    menuItemId: null,
    name: 'Om Ali',
    quantity: 4,
    amount: Money(26000),
  ),
];

const _byAmount = [_feteer, _koshari];

/// A test double. Never a default binding.
///
/// Answers the first period it is asked for as the one on screen and that
/// period's `previous` as the comparison — and remembers every answer, so a
/// test reads its expectations off exactly what the screen was given.
class _Fixed implements ReportsRepository {
  final served = <ReportFilter, SalesReport>{};
  final ranked = <ProductRanking>[];

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
    int limit = 5,
  }) async {
    ranked.add(by);
    return switch (by) {
      ProductRanking.quantity => _byQuantity,
      ProductRanking.amount => _byAmount,
    };
  }

  // Finance's (BO-9); the Reports tab never asks for them.
  @override
  Future<TaxReport> taxes(ReportFilter filter) =>
      throw UnimplementedError('Reports draws no taxes');

  @override
  Future<PaymentLedger> payments(ReportFilter filter, {int limit = 500}) =>
      throw UnimplementedError('Reports draws no payment ledger');
}

class _InAdminMode extends AdminSessionController {
  @override
  AdminSession? build() =>
      AdminSession(staff: _owner, startedAt: DateTime(2026, 9, 10, 9));
}

Future<_Fixed> _pump(
  WidgetTester tester, {
  String language = 'en',
  bool database = true,
}) async {
  // The back office's narrowest, and tall enough that the list builds every
  // section — a lazily built row is one no finder can see.
  tester.view
    ..physicalSize = const Size(1100, 2200)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = _Fixed();
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      reportsRepositoryProvider.overrideWithValue(
        database ? repository : null,
      ),
      adminSessionProvider.overrideWith(_InAdminMode.new),
      businessDayProvider.overrideWith((ref) async => _today),
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
        home: const Scaffold(body: ManagementReportsPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

/// The period on screen and the one it is compared with, as the fake served
/// them.
(SalesReport, SalesReport) _shown(_Fixed repository, DateTime from) {
  final filter = repository.served.keys.firstWhere((f) => f.from == from);
  return (repository.served[filter]!, repository.served[filter.previous]!);
}

/// Every caption at or under [key], in reading order — at, because some keys
/// sit on the caption itself.
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

T _painter<T>(WidgetTester tester, Finder paint) =>
    tester.widget<CustomPaint>(paint).painter! as T;

void main() {
  const s = EnStrings();

  testWidgets('today, and the dates it means', (tester) async {
    final repository = await _pump(tester);
    expect(
      repository.served.keys.first,
      ReportFilter.day(DateTime(2026, 9, 10)),
    );
    expect(_texts(tester, 'reports-range'), ['2026-09-10']);
  });

  testWidgets('every tile, bar and row is the repository\'s number', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await tester.tap(find.byKey(const Key('reports-period-month')));
    await tester.pumpAndSettle();

    final (report, previous) = _shown(repository, DateTime(2026, 9, 1));
    expect(report.days, hasLength(10));
    expect(_texts(tester, 'reports-range'), ['2026-09-01 → 2026-09-10']);

    // The four tiles, and each one's change against the period before.
    String delta(int now, int before) => formatDeltaBp(deltaBp(now, before)!);
    expect(_texts(tester, 'reports-tile-net'), [
      s.homeKpiNetSales.toUpperCase(),
      report.net.format(),
      delta(report.net.minor, previous.net.minor),
      s.reportVsPrevious,
    ]);
    expect(_texts(tester, 'reports-tile-average'), [
      s.homeKpiAverage.toUpperCase(),
      report.averageOrder!.format(),
      delta(report.averageOrder!.minor, previous.averageOrder!.minor),
      s.reportVsPrevious,
    ]);
    expect(_texts(tester, 'reports-tile-orders'), [
      s.homeKpiOrders.toUpperCase(),
      '${report.orders}',
      delta(report.orders, previous.orders),
      s.reportVsPrevious,
    ]);
    expect(_texts(tester, 'reports-tile-refunds'), [
      s.reportKpiRefunds.toUpperCase(),
      report.refunds.format(),
      s.reportRefundCount(report.refundCount),
      delta(report.refunds.minor, previous.refunds.minor),
      s.reportVsPrevious,
    ]);

    // The trend: each metric is the days' own figure, a shut day's average a
    // gap rather than a zero.
    final plot = find.byKey(const Key('reports-trend-plot'));
    expect(_painter<TrendPainter>(tester, plot).values, [
      for (final day in report.days) day.net.minor,
    ]);
    await tester.tap(find.byKey(const Key('reports-metric-orders')));
    await tester.pumpAndSettle();
    expect(_painter<TrendPainter>(tester, plot).values, [
      for (final day in report.days) day.orders,
    ]);
    await tester.tap(find.byKey(const Key('reports-metric-average')));
    await tester.pumpAndSettle();
    final averages = _painter<TrendPainter>(tester, plot).values;
    expect(averages, [
      for (final day in report.days) day.averageOrder?.minor,
    ]);
    expect(averages[3], isNull);

    // The top five, in the repository's order, each bar against the first.
    for (final (i, product) in _byQuantity.indexed) {
      expect(_texts(tester, 'reports-product-$i'), [
        '${i + 1}',
        product.name,
        '${product.quantity}',
        product.amount.format(),
      ]);
      final bar = _painter<RankBarPainter>(
        tester,
        find.descendant(
          of: find.byKey(Key('reports-product-$i')),
          matching: find.byType(CustomPaint),
        ),
      );
      expect((bar.value, bar.longest), (product.quantity, 48));
    }
    await tester.tap(find.byKey(const Key('reports-rank-amount')));
    await tester.pumpAndSettle();
    expect(repository.ranked.last, ProductRanking.amount);
    expect(_texts(tester, 'reports-product-0').sublist(1, 2), ['Feteer']);
    expect(find.byKey(const Key('reports-product-2')), findsNothing);

    // The tender bar and its legend: BO-5's shares, on account apart.
    final shares = report.tenderShares;
    expect(shares, hasLength(3));
    expect(
      _painter<ShareBarPainter>(
        tester,
        find.byKey(const Key('reports-share-bar')),
      ).basisPoints,
      [for (final share in shares) share.basisPoints],
    );
    for (final (i, share) in shares.indexed) {
      final bp = share.basisPoints;
      expect(_texts(tester, 'reports-tender-$i'), [
        share.method.label,
        share.method.amount.format(),
        '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%',
      ]);
    }
    expect(_texts(tester, 'reports-on-account'), [
      s.reportOnAccount,
      report.onAccount.format(),
    ]);

    // Every till, the stranger included, and the branch under them.
    for (final till in report.terminals) {
      expect(_texts(tester, 'reports-terminal-${till.terminalId}'), [
        if (till.name case final name?) name else ...[
          till.terminalId,
          s.reportUnregistered,
        ],
        '${till.orders}',
        till.gross.format(),
        till.discounts.format(),
        till.refunds.format(),
        till.net.format(),
      ]);
    }
    expect(_texts(tester, 'reports-terminal-total'), [
      s.reportBranchTotal,
      '${report.orders}',
      report.gross.format(),
      report.discounts.format(),
      report.refunds.format(),
      report.net.format(),
    ]);

    // What stood out: picks from the same lists, and the net tile's change.
    final best = report.days.reduce(
      (a, b) => b.net.minor > a.net.minor ? b : a,
    );
    expect(_texts(tester, 'reports-insight-bestDay'), [
      s.reportInsightBestDay.toUpperCase(),
      businessDayWire(best.date),
      best.net.format(),
    ]);
    expect(_texts(tester, 'reports-insight-topTerminal'), [
      s.reportInsightTopTerminal.toUpperCase(),
      'Counter 1',
      report.terminal('a1')!.net.format(),
    ]);
    expect(_texts(tester, 'reports-insight-growth'), [
      s.reportInsightGrowth.toUpperCase(),
      delta(report.net.minor, previous.net.minor),
    ]);
  });

  testWidgets('with no database behind the till it says so, not zeros', (
    tester,
  ) async {
    await _pump(tester, database: false);
    expect(find.text(s.reportNoDatabase), findsOneWidget);
    // No tile at all: a tile of 0.00 would read as a period with no sales.
    expect(find.byKey(const Key('reports-tile-net')), findsNothing);
    expect(find.byKey(const Key('reports-trend-plot')), findsNothing);
  });

  group('in Arabic', () {
    testWidgets('the charts run right to left, and nothing overflows', (
      tester,
    ) async {
      final repository = await _pump(tester, language: 'ar');
      await tester.tap(find.byKey(const Key('reports-period-month')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The first date at the right edge, as an Arabic page reads time.
      final plot = find.byKey(const Key('reports-trend-plot'));
      final trend = _painter<TrendPainter>(tester, plot);
      expect(trend.direction, TextDirection.rtl);
      final points = trend.pointsIn(tester.getSize(plot)).nonNulls.toList();
      expect(points.first.dx, greaterThan(points.last.dx));

      final bar = find.byKey(const Key('reports-share-bar'));
      final shares = _painter<ShareBarPainter>(tester, bar);
      expect(shares.direction, TextDirection.rtl);
      final width = tester.getSize(bar).width;
      expect(
        shareSpans(shares.basisPoints, width, shares.direction).first.$2,
        width,
        reason: 'the largest share starts at the right edge',
      );
      expect(
        _painter<RankBarPainter>(
          tester,
          find.descendant(
            of: find.byKey(const Key('reports-product-0')),
            matching: find.byType(CustomPaint),
          ),
        ).direction,
        TextDirection.rtl,
      );

      // And the words are Arabic; the figures stay Western and left to right.
      const ar = ArStrings();
      for (final word in [
        ar.homeKpiNetSales,
        ar.reportKpiRefunds,
        ar.reportTopProducts,
        ar.reportPayments,
        ar.reportBranchTotal,
        ar.reportPeriodMonth,
      ]) {
        expect(find.text(word), findsWidgets, reason: word);
      }
      for (final english in [
        s.homeKpiNetSales,
        s.reportKpiRefunds,
        s.reportTopProducts,
        s.reportBranchTotal,
      ]) {
        expect(find.text(english), findsNothing, reason: english);
      }
      final (report, _) = _shown(repository, DateTime(2026, 9, 1));
      expect(
        _texts(tester, 'reports-tile-net'),
        contains(report.net.format()),
      );
    });

    testWidgets('this week starts on Saturday', (tester) async {
      final repository = await _pump(tester, language: 'ar');
      await tester.tap(find.byKey(const Key('reports-period-week')));
      await tester.pumpAndSettle();
      expect(
        repository.served.keys,
        contains(
          ReportFilter(from: DateTime(2026, 9, 5), to: DateTime(2026, 9, 11)),
        ),
      );
    });
  });
}
