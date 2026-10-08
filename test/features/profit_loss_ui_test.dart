import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/finance_providers.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/reports_providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/mono_amount.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/finance_report.dart';
import 'package:xorder_pos/domain/models/profit_and_loss.dart';
import 'package:xorder_pos/domain/models/profit_report.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/features/admin/presentation/management_finance_panes.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// Finance › Profit & loss.
///
/// The arithmetic and the caveat rules are `profit_and_loss_test.dart`'s. What
/// only a widget test can say is that the page shows the statement in its order
/// with its deductions marked, that a result which is not the whole business is
/// not drawn as if it were — the partial-cost label, the share of sales that
/// has a cost, the list of what is left out — and that a loss reads as one.
final _range = ReportFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 15));

ProfitAndLoss _statement({
  int sales = 114000,
  int tax = 14000,
  int cost = 30000,
  int? costed = 10000,
  int expenses = 5000,
  SupplierFigures figures = SupplierFigures.included,
  int? suppliers = 40000,
}) => ProfitAndLoss(
  filter: _range,
  sales: Money(sales),
  tax: Money(tax),
  costOfGoods: Money(cost),
  costedShareBp: costed,
  drawerExpenses: Money(expenses),
  supplierFigures: figures,
  paidToSuppliers: suppliers == null ? null : Money(suppliers),
);

Future<void> _pane(
  WidgetTester tester,
  ProfitAndLoss? statement, {
  String language = 'en',
}) async {
  tester.view
    ..physicalSize = const Size(1280, 2000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fakeRepositoryOverrides(english: language == 'en'),
        profitAndLossProvider.overrideWith((ref, filter) async => statement),
        businessDayProvider.overrideWith(
          (ref) async => BusinessDay(
            id: 1,
            date: DateTime.utc(2026, 9, 14),
            openedAt: DateTime(2026, 9, 14, 8),
          ),
        ),
      ],
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
        home: const Scaffold(body: FinanceProfitLossPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The amount drawn in the row keyed [key].
Money _amount(WidgetTester tester, String key) => tester
    .widget<MonoAmount>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(MonoAmount)),
    )
    .value;

/// Every caption in the row keyed [key].
List<String> _texts(WidgetTester tester, String key) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
  ))
    ?t.data,
];

void main() {
  const s = EnStrings();

  setUpAll(loadPosFonts);

  group('the statement', () {
    testWidgets('each line, in an accountant\'s order, with its figure', (
      tester,
    ) async {
      await _pane(tester, _statement());

      expect(_amount(tester, 'pl-sales').minor, 114000);
      expect(_amount(tester, 'pl-tax').minor, 14000);
      expect(_amount(tester, 'pl-revenue').minor, 100000);
      expect(_amount(tester, 'pl-cogs').minor, 30000);
      expect(_amount(tester, 'pl-gross').minor, 70000);
      expect(_amount(tester, 'pl-expenses').minor, 5000);
      expect(_amount(tester, 'pl-result').minor, 65000);

      // Top to bottom, as the statement reads.
      double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      final order = [
        'pl-sales',
        'pl-tax',
        'pl-revenue',
        'pl-cogs',
        'pl-gross',
        'pl-expenses',
        'pl-result',
      ];
      expect([for (final k in order) top(k)], [for (final k in order) top(k)]..sort());
    });

    testWidgets('a deduction is marked as one, and is drawn as its figure', (
      tester,
    ) async {
      await _pane(tester, _statement());

      expect(_texts(tester, 'pl-tax').first, '− ${s.plTax}');
      expect(_texts(tester, 'pl-cogs').first, '− ${s.plCostOfGoods}');
      expect(_texts(tester, 'pl-expenses').first, '− ${s.plExpenses}');
      // The totals are not marked.
      expect(_texts(tester, 'pl-revenue').first, s.plRevenue);
      expect(_texts(tester, 'pl-result').first, s.plOperatingResult);
    });

    testWidgets('the gross margin is said beside gross profit', (tester) async {
      await _pane(tester, _statement());

      expect(_texts(tester, 'pl-gross'), contains(s.plMargin('70.00%')));
    });
  });

  group('when every sale has a cost', () {
    testWidgets('gross profit is plain gross profit', (tester) async {
      await _pane(tester, _statement(costed: 10000));

      expect(_texts(tester, 'pl-gross').first, s.plGrossProfit);
      expect(find.byKey(const Key('pl-caveat-itemsWithNoCost')), findsNothing);
    });
  });

  group('when only some of the sales have a cost', () {
    testWidgets('gross profit says it is before the items with no cost', (
      tester,
    ) async {
      await _pane(tester, _statement(costed: 6500));

      expect(_texts(tester, 'pl-gross').first, s.plGrossProfitPartial);
    });

    testWidgets('and so does the operating result, which is the figure people '
        'quote', (tester) async {
      await _pane(tester, _statement(costed: 6500));

      expect(_texts(tester, 'pl-result').first, s.plOperatingResultPartial);
    });

    testWidgets('a fully costed result is plain', (tester) async {
      await _pane(tester, _statement(costed: 10000));

      expect(_texts(tester, 'pl-result').first, s.plOperatingResult);
    });

    testWidgets('the share of sales with a cost is said, and the gap named', (
      tester,
    ) async {
      await _pane(tester, _statement(costed: 6500));

      expect(
        tester.widget<Text>(find.byKey(const Key('pl-costed-share'))).data,
        s.plCostedShare('65.00%'),
      );
      expect(find.byKey(const Key('pl-caveat-itemsWithNoCost')), findsOneWidget);
      expect(find.text(s.plCaveatNoCost), findsOneWidget);
    });

    testWidgets('and it is drawn as a warning, not as a fact', (tester) async {
      await _pane(tester, _statement(costed: 6500));

      final text = tester.widget<Text>(find.byKey(const Key('pl-costed-share')));
      expect(text.style!.color, PosPalette.light.warn);
    });
  });

  group('a loss', () {
    testWidgets('is drawn as one: danger colour, signed margin', (tester) async {
      await _pane(tester, _statement(cost: 130000, expenses: 5000));

      final gross = tester.widget<MonoAmount>(
        find.descendant(
          of: find.byKey(const Key('pl-gross')),
          matching: find.byType(MonoAmount),
        ),
      );
      expect(gross.value.minor, -30000);
      expect(gross.color, PosPalette.light.danger);
      expect(_texts(tester, 'pl-gross'), contains(s.plMargin('-30.00%')));

      final result = tester.widget<MonoAmount>(
        find.descendant(
          of: find.byKey(const Key('pl-result')),
          matching: find.byType(MonoAmount),
        ),
      );
      expect(result.value.minor, -35000);
      expect(result.color, PosPalette.light.danger);
    });

    testWidgets('a profit is not drawn in the danger colour', (tester) async {
      await _pane(tester, _statement());

      final result = tester.widget<MonoAmount>(
        find.descendant(
          of: find.byKey(const Key('pl-result')),
          matching: find.byType(MonoAmount),
        ),
      );
      expect(result.color, isNot(PosPalette.light.danger));
    });
  });

  group('what the statement leaves out', () {
    testWidgets('is said, under it, every time', (tester) async {
      await _pane(tester, _statement());

      expect(find.text(s.plLeavesOut.toUpperCase()), findsOneWidget);
      for (final (key, text) in [
        ('supplierSpendOutsideStock', s.plCaveatSupplier),
        ('rentAndSalaries', s.plCaveatRent),
        ('serviceChargeIncluded', s.plCaveatService),
      ]) {
        expect(find.byKey(Key('pl-caveat-$key')), findsOneWidget, reason: key);
        expect(find.text(text), findsOneWidget, reason: key);
      }
    });

    testWidgets('in a fixed order', (tester) async {
      await _pane(tester, _statement(costed: 6500));

      double top(String key) =>
          tester.getTopLeft(find.byKey(Key('pl-caveat-$key'))).dy;
      expect(
        [
          top('itemsWithNoCost'),
          top('supplierSpendOutsideStock'),
          top('rentAndSalaries'),
          top('serviceChargeIncluded'),
        ],
        [
          top('itemsWithNoCost'),
          top('supplierSpendOutsideStock'),
          top('rentAndSalaries'),
          top('serviceChargeIncluded'),
        ]..sort(),
      );
    });

    testWidgets('what was paid to suppliers is shown, beside the statement', (
      tester,
    ) async {
      await _pane(tester, _statement());

      expect(_amount(tester, 'pl-suppliers').minor, 40000);
      expect(find.text(s.plPaidToSuppliers), findsOneWidget);
    });

    testWidgets('and changing it changes nothing in the result', (tester) async {
      await _pane(tester, _statement(suppliers: 900000));

      expect(_amount(tester, 'pl-result').minor, 65000);
    });

    testWidgets('an unread supplier ledger is said, not shown as nothing paid', (
      tester,
    ) async {
      await _pane(
        tester,
        _statement(figures: SupplierFigures.onPlatform, suppliers: null),
      );

      expect(find.byKey(const Key('pl-suppliers')), findsNothing);
      expect(find.byKey(const Key('pl-suppliers-unread')), findsOneWidget);
      expect(find.text(s.plSuppliersUnread), findsOneWidget);
    });
  });

  group('a period with nothing sold', () {
    testWidgets('is a statement of zeros, with no margin to quote', (
      tester,
    ) async {
      await _pane(
        tester,
        _statement(sales: 0, tax: 0, cost: 0, costed: null, expenses: 0),
      );

      expect(_amount(tester, 'pl-result').minor, 0);
      expect(_texts(tester, 'pl-gross').any((t) => t.startsWith('Margin')), isFalse);
      expect(find.byKey(const Key('pl-costed-share')), findsNothing);
    });
  });

  group('when it cannot be shown', () {
    testWidgets('no statement is said, not drawn as a business that earned '
        'nothing', (tester) async {
      await _pane(tester, null);

      expect(find.text(s.financeNoFigures), findsOneWidget);
      expect(find.byKey(const Key('pl-result')), findsNothing);
    });
  });

  testWidgets('in Arabic the statement and its limits are in Arabic', (
    tester,
  ) async {
    await _pane(tester, _statement(costed: 6500), language: 'ar');

    const ar = ArStrings();
    expect(find.text(ar.plRevenue), findsOneWidget);
    expect(find.text(ar.plCaveatSupplier), findsOneWidget);
    expect(find.text(ar.plGrossProfitPartial), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('the provider that composes it', () {
    final sales = SalesReport(
      filter: _range,
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
    final tax = TaxReport(
      filter: _range,
      unattributedRefunds: Money.zero,
      rates: const [
        TaxCollected(
          name: 'VAT 14%',
          rateBp: 1400,
          orders: 10,
          base: Money(100000),
          charged: Money(14000),
          refunded: Money(0),
        ),
      ],
    );
    final profit = ProfitReport(
      filter: _range,
      pricesIncludeTax: false,
      products: const [
        ProductProfit(
          menuItemId: 1,
          name: 'Cola',
          quantity: 1,
          revenue: Money(1000),
          costedRevenue: Money(1000),
          cost: Money(400),
        ),
      ],
    );
    final expenses = ExpenseReport(
      filter: _range,
      payOuts: const [],
      supplierFigures: SupplierFigures.onPlatform,
    );

    ProviderContainer container({
      bool allowed = true,
      SalesReport? salesReport,
      TaxReport? taxReport,
      ProfitReport? profitReport,
      ExpenseReport? expenseReport,
    }) {
      final c = ProviderContainer(
        overrides: [
          reportsAllowedProvider.overrideWithValue(allowed),
          salesReportProvider.overrideWith((ref, f) async => salesReport),
          taxReportProvider.overrideWith((ref, f) async => taxReport),
          profitReportProvider.overrideWith((ref, f) async => profitReport),
          expenseReportProvider.overrideWith((ref, f) async => expenseReport),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('is made of the four reports of the range', () async {
      final c = container(
        salesReport: sales,
        taxReport: tax,
        profitReport: profit,
        expenseReport: expenses,
      );

      final statement = await c.read(profitAndLossProvider(_range).future);

      expect(statement!.sales.minor, 114000);
      expect(statement.tax.minor, 14000);
      expect(statement.costOfGoods.minor, 400);
    });

    test('is null without reports.view, and reads nothing', () async {
      final c = container(
        allowed: false,
        salesReport: sales,
        taxReport: tax,
        profitReport: profit,
        expenseReport: expenses,
      );

      expect(await c.read(profitAndLossProvider(_range).future), isNull);
    });

    test('is null if any one report is missing — a statement with a line '
        'gone would add up and mean nothing', () async {
      for (final missing in ['sales', 'tax', 'profit', 'expenses']) {
        final c = container(
          salesReport: missing == 'sales' ? null : sales,
          taxReport: missing == 'tax' ? null : tax,
          profitReport: missing == 'profit' ? null : profit,
          expenseReport: missing == 'expenses' ? null : expenses,
        );

        expect(
          await c.read(profitAndLossProvider(_range).future),
          isNull,
          reason: 'without $missing',
        );
      }
    });
  });
}
