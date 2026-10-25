import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/excel_export.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/reports_providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/profit_report.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/application/reports_view.dart';
import 'package:xorder_pos/features/admin/presentation/report_breakdown_panes.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// The Profit section under Reports › Items.
///
/// The arithmetic is `profit_report_test.dart`'s and the SQL is
/// `test/data/profit_report_test.dart`'s. What only a widget test can say is
/// that the page tells the truth about what it does not know: the margin sits
/// beside its coverage, an item with no cost is a tag and dashes and never a
/// zero, a loss reads as one, a tax-inclusive restaurant is warned — and that
/// the list above is not held hostage by the section beneath it.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

final _today = BusinessDay(
  id: 2,
  date: DateTime.utc(2026, 9, 10),
  openedAt: DateTime(2026, 9, 10, 8),
);

final _month = ReportFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 11));

const _sold = [
  ProductSales(menuItemId: 1, name: 'Cola', quantity: 40, amount: Money(8000)),
  ProductSales(menuItemId: 4, name: 'Chips', quantity: 30, amount: Money(4500)),
  ProductSales(menuItemId: 7, name: 'Steak', quantity: 5, amount: Money(10000)),
  ProductSales(menuItemId: 8, name: 'Salad', quantity: 8, amount: Money(1600)),
  ProductSales(menuItemId: null, name: 'Burger', quantity: 9, amount: Money(8500)),
];

/// Cola earns; Chips was half-costed (sold before its first delivery, then
/// after); Steak and Salad lose, one at −25% and one at −6.25%; the Burger is a
/// dish and has no cost at all.
ProfitReport _profit(ReportFilter filter, {bool inclusive = false}) =>
    ProfitReport(
      filter: filter,
      pricesIncludeTax: inclusive,
      products: ProfitReport.ranked(const [
        ProductProfit(
          menuItemId: 1,
          name: 'Cola',
          quantity: 40,
          revenue: Money(8000),
          costedRevenue: Money(8000),
          cost: Money(4200),
        ),
        ProductProfit(
          menuItemId: 4,
          name: 'Chips',
          quantity: 30,
          revenue: Money(4500),
          costedRevenue: Money(1500),
          cost: Money(1000),
        ),
        ProductProfit(
          menuItemId: 7,
          name: 'Steak',
          quantity: 5,
          revenue: Money(10000),
          costedRevenue: Money(10000),
          cost: Money(12500),
        ),
        ProductProfit(
          menuItemId: 8,
          name: 'Salad',
          quantity: 8,
          revenue: Money(1600),
          costedRevenue: Money(1600),
          cost: Money(1700),
        ),
        ProductProfit(
          menuItemId: null,
          name: 'Burger',
          quantity: 9,
          revenue: Money(8500),
          costedRevenue: Money(0),
          cost: null,
        ),
      ]),
    );

class _Reports implements ReportsRepository {
  _Reports({this.sold = _sold, this.inclusive = false, this.failProfit = false,
      this.profit_});

  final List<ProductSales> sold;
  final bool inclusive;
  final bool failProfit;
  final ProfitReport Function(ReportFilter)? profit_;

  /// Every filter the profit read was made with.
  final asked = <ReportFilter>[];

  @override
  Future<List<ProductSales>> topProducts(
    ReportFilter filter, {
    required ProductRanking by,
    int? limit = 5,
  }) async => sold;

  @override
  Future<ProfitReport> profit(ReportFilter filter) async {
    asked.add(filter);
    if (failProfit) throw StateError('ledger unavailable');
    return (profit_ ?? (f) => _profit(f, inclusive: inclusive))(filter);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
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

class _InAdminMode extends AdminSessionController {
  @override
  AdminSession? build() =>
      AdminSession(staff: _owner, startedAt: DateTime(2026, 9, 10, 9));
}

Future<_Reports> _pane(
  WidgetTester tester, {
  _Reports? reports,
  String language = 'en',
  bool database = true,
  _Saved? saved,
}) async {
  tester.view
    ..physicalSize = const Size(PosSize.wideShellMin, 2800)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = reports ?? _Reports();
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(english: language == 'en'),
      reportsRepositoryProvider.overrideWithValue(database ? repository : null),
      adminSessionProvider.overrideWith(_InAdminMode.new),
      businessDayProvider.overrideWith((ref) async => _today),
      if (saved != null) workbookSaverProvider.overrideWithValue(saved.save),
    ],
  );
  addTearDown(container.dispose);
  container.read(reportPeriodProvider.notifier).select(ReportPeriod.month);

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
        home: const Scaffold(body: ReportItemsPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
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

void main() {
  const s = EnStrings();

  setUpAll(loadPosFonts);

  group('the margin, signed', () {
    test('a profit reads as a share', () {
      expect(formatMarginBp(4750), '47.50%');
      expect(formatMarginBp(806), '8.06%');
      expect(formatMarginBp(0), '0.00%');
    });

    test('a loss keeps its sign and its decimals', () {
      expect(formatMarginBp(-2500), '-25.00%');
      // The share formatter alone prints −625 as −6.75%: Dart's `%` is never
      // negative. This is the figure that catches it.
      expect(formatMarginBp(-625), '-6.25%');
      expect(formatMarginBp(-5), '-0.05%');
    });
  });

  testWidgets('it is under the list, on the same period', (tester) async {
    final reports = await _pane(tester);

    expect(find.byKey(const Key('reports-items')), findsOneWidget);
    expect(find.byKey(const Key('reports-profit')), findsOneWidget);
    expect(find.text(s.profitTitle), findsOneWidget);
    // The period the bar shows is the period it was asked for.
    expect(reports.asked.single, _month);
  });

  testWidgets('each product: revenue, cost, profit and margin', (tester) async {
    await _pane(tester);

    expect(_texts(tester, 'reports-profit-0'), [
      'Cola',
      '80.00 EGP',
      '42.00 EGP',
      '38.00 EGP',
      '47.50%',
    ]);
    // Half costed: the margin is on the 15.00 that has a cost, not the 45.00.
    expect(_texts(tester, 'reports-profit-1'), [
      'Chips',
      '45.00 EGP',
      '10.00 EGP',
      '5.00 EGP',
      '33.33%',
    ]);
  });

  testWidgets('a loss reads as a loss', (tester) async {
    await _pane(tester);

    expect(_texts(tester, 'reports-profit-2'), [
      'Salad',
      '16.00 EGP',
      '17.00 EGP',
      '-1.00 EGP',
      '-6.25%',
    ]);
    expect(_texts(tester, 'reports-profit-3'), [
      'Steak',
      '100.00 EGP',
      '125.00 EGP',
      '-25.00 EGP',
      '-25.00%',
    ]);
  });

  testWidgets('a loss is drawn in the danger colour', (tester) async {
    await _pane(tester);

    final margin = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reports-profit-3')),
        matching: find.text('-25.00%'),
      ),
    );
    expect(margin.style!.color, PosPalette.light.danger);

    // And a profit is not: only a loss is shouted.
    final healthy = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('reports-profit-0')),
        matching: find.text('47.50%'),
      ),
    );
    expect(healthy.style!.color, isNot(PosPalette.light.danger));
  });

  testWidgets('an item with no cost is a tag and dashes, never a zero', (
    tester,
  ) async {
    await _pane(tester);

    expect(_texts(tester, 'reports-profit-4'), [
      'Burger',
      s.profitNoCostTag,
      '85.00 EGP',
      '—',
      '—',
      '—',
    ]);
    // And only that row says so.
    expect(find.byKey(const Key('reports-profit-0-uncosted')), findsNothing);
    expect(find.byKey(const Key('reports-profit-4-uncosted')), findsOneWidget);
  });

  testWidgets('the total is every row, over revenue it can and cannot cost', (
    tester,
  ) async {
    await _pane(tester);

    expect(_texts(tester, 'reports-profit-total'), [
      s.reportAllItems,
      '326.00 EGP',
      '194.00 EGP',
      '17.00 EGP',
      '8.06%',
    ]);
  });

  testWidgets('the figures above the table say what the margin covers', (
    tester,
  ) async {
    await _pane(tester);

    // Labels are micro-labels, which the house style sets in capitals.
    String caps(String text) => text.toUpperCase();
    expect(_texts(tester, 'profit-tile-profit'), [
      caps(s.profitKpiProfit),
      '17.00 EGP',
    ]);
    expect(_texts(tester, 'profit-tile-margin'), [
      caps(s.profitColumnMargin),
      '8.06%',
    ]);
    // 211.00 of 326.00 is costed, and the page says it in words beside the share.
    expect(_texts(tester, 'profit-tile-coverage'), [
      caps(s.profitKpiCoverage),
      '64.72%',
      s.profitCoverageNote,
    ]);
    // The revenue it cannot speak to has a line of its own.
    expect(_texts(tester, 'profit-tile-uncosted'), [
      caps(s.profitUncostedRevenue),
      '115.00 EGP',
    ]);
    expect(find.text(s.profitNote), findsOneWidget);
  });

  testWidgets('nothing costed: it says how to get a cost, not a column of '
      'dashes', (tester) async {
    await _pane(
      tester,
      reports: _Reports(
        profit_: (filter) => ProfitReport(
          filter: filter,
          pricesIncludeTax: false,
          products: const [
            ProductProfit(
              menuItemId: null,
              name: 'Burger',
              quantity: 9,
              revenue: Money(8500),
              costedRevenue: Money(0),
              cost: null,
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(const Key('profit-nothing-costed')), findsOneWidget);
    expect(find.text(s.profitNothingCosted), findsOneWidget);
    expect(find.byKey(const Key('profit-tile-profit')), findsNothing);
    expect(find.byKey(const Key('reports-profit-0')), findsNothing);
  });

  group('prices that include tax', () {
    testWidgets('an inclusive restaurant is warned, over the table',
        (tester) async {
      await _pane(tester, reports: _Reports(inclusive: true));

      expect(find.byKey(const Key('profit-tax-note')), findsOneWidget);
      expect(find.text(s.profitTaxNote), findsOneWidget);
      // The figures are still shown: the warning qualifies them, it does not
      // withhold them.
      expect(find.byKey(const Key('reports-profit-0')), findsOneWidget);
    });

    testWidgets('an exclusive one is not', (tester) async {
      await _pane(tester);

      expect(find.byKey(const Key('profit-tax-note')), findsNothing);
    });

    testWidgets('the amount column says it is net, so it is not mistaken for '
        'the gross list above', (tester) async {
      await _pane(tester, reports: _Reports(inclusive: true));

      // Micro-labels are set in capitals.
      expect(
        find.descendant(
          of: find.byKey(const Key('reports-profit')),
          matching: find.text(s.profitColumnAmountNet.toUpperCase()),
        ),
        findsOneWidget,
      );
    });

    testWidgets('and is plain "Amount" where prices exclude tax', (tester) async {
      await _pane(tester);

      expect(find.text(s.profitColumnAmountNet.toUpperCase()), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('reports-profit')),
          matching: find.text(s.reportColumnAmount.toUpperCase()),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the note tells the method, and says where it is an estimate', (
      tester,
    ) async {
      await _pane(tester, reports: _Reports(inclusive: true));

      expect(s.profitTaxNote, contains('estimate'));
      expect(find.text(s.profitTaxNote), findsOneWidget);
    });

    testWidgets('and it is said even when nothing is costed', (tester) async {
      await _pane(
        tester,
        reports: _Reports(
          profit_: (filter) => ProfitReport(
            filter: filter,
            pricesIncludeTax: true,
            products: const [],
          ),
        ),
      );

      expect(find.byKey(const Key('profit-tax-note')), findsOneWidget);
    });
  });

  group('when the list or the ledger is not there', () {
    testWidgets('no sales, no profit section at all', (tester) async {
      final reports = await _pane(tester, reports: _Reports(sold: const []));

      expect(find.text(s.reportNoProducts), findsOneWidget);
      expect(find.byKey(const Key('reports-profit')), findsNothing);
      expect(reports.asked, isEmpty, reason: 'nothing to ask a ledger about');
    });

    testWidgets('a failed profit read does not take the list with it', (
      tester,
    ) async {
      await _pane(tester, reports: _Reports(failProfit: true));

      // The section says so, in the reports' own words…
      expect(
        find.descendant(
          of: find.byKey(const Key('reports-profit')),
          matching: find.text(s.reportUnavailable),
        ),
        findsOneWidget,
      );
      // …and the list above it is whole.
      expect(find.byKey(const Key('reports-item-0')), findsOneWidget);
      expect(find.byKey(const Key('reports-items-total')), findsOneWidget);
    });

    testWidgets('no database is said, not drawn as zero profit', (tester) async {
      await _pane(tester, database: false);

      // The list refuses first, on a till with no database.
      expect(find.text(s.reportNoDatabase), findsWidgets);
      expect(find.byKey(const Key('profit-tile-profit')), findsNothing);
    });
  });

  group('the Excel export', () {
    Future<xl.Excel> exported(WidgetTester tester, _Saved saved) async {
      await tester.tap(find.byKey(ExcelExportButton.buttonKey));
      await tester.pumpAndSettle();
      expect(saved.files, hasLength(1));
      return xl.Excel.decodeBytes(saved.files.single.$2);
    }

    List<Object?> sheetRow(xl.Excel book, String sheet, String lead) {
      final found = book.tables[sheet]!.rows.firstWhere(
        (r) => r.isNotEmpty && r.first?.value.toString() == lead,
      );
      return [
        for (final cell in found)
          switch (cell?.value) {
            null => null,
            xl.TextCellValue(:final value) => value.toString(),
            xl.DoubleCellValue(:final value) => value,
            // Excel hands a whole amount back as an integer.
            xl.IntCellValue(:final value) => value.toDouble(),
            final other => '$other',
          },
      ];
    }

    testWidgets('writes the Profit sheet the page is showing', (tester) async {
      final saved = _Saved();
      await _pane(tester, saved: saved);

      final book = await exported(tester, saved);

      expect(book.tables.keys, [s.reportsItems, s.profitTitle]);
      // Cola's row in the file is Cola's row on the page: 80.00 / 42.00 /
      // 38.00 / 47.50%.
      final cola = sheetRow(book, s.profitTitle, 'Cola');
      expect(cola.take(5), ['Cola', 80.0, 42.0, 38.0, 0.475]);
    });

    testWidgets('a loss and an uncosted dish read as they do on the page', (
      tester,
    ) async {
      final saved = _Saved();
      await _pane(tester, saved: saved);

      final book = await exported(tester, saved);

      final salad = sheetRow(book, s.profitTitle, 'Salad');
      expect(salad[3], -1.0);
      expect(salad[4], closeTo(-0.0625, 1e-9));

      final burger = sheetRow(book, s.profitTitle, 'Burger');
      expect(burger[1], 85.0);
      expect(burger.sublist(2, 5), [null, null, null]);
      expect(burger[5], s.profitNoCostTag);
    });

    testWidgets('a ledger that failed to read costs the file its Profit sheet, '
        'not the whole export', (tester) async {
      final saved = _Saved();
      await _pane(tester, reports: _Reports(failProfit: true), saved: saved);

      final book = await exported(tester, saved);

      // The items it could write are written, and the page above the file has
      // already said the profit was unavailable.
      expect(book.tables.keys, [s.reportsItems]);
      expect(find.byKey(ExcelExportButton.noteKey), findsOneWidget);
    });
  });

  testWidgets('in Arabic it is the owner\'s word, and still fits', (
    tester,
  ) async {
    await _pane(tester, language: 'ar');

    const ar = ArStrings();
    // The section's title and its profit column are the same Arabic word.
    expect(find.text(ar.profitTitle), findsWidgets);
    expect(find.text(ar.profitColumnCost), findsOneWidget);
    expect(find.text(ar.profitNote), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
