import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/profit_report.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/features/admin/application/report_export.dart';

/// The Profit sheet of the Items workbook.
///
/// The file is the page's figures, so what is pinned here is the same promise
/// the page makes: an item with no cost is a **blank**, not a zero (a zero
/// would feed a formula and be quoted as "free"), a loss keeps its sign, the
/// margin travels with its coverage, and a restaurant that prices tax in is
/// told so inside the file as well as on the screen.
void main() {
  const s = EnStrings();
  final filter = ReportFilter(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 11));

  const sold = [
    ProductSales(menuItemId: 1, name: 'Cola', quantity: 40, amount: Money(8000)),
    ProductSales(menuItemId: null, name: 'Burger', quantity: 9, amount: Money(8500)),
  ];

  ProductProfit item(
    String name, {
    required int revenue,
    int? cost,
    int? costed,
  }) => ProductProfit(
    menuItemId: cost == null ? null : 1,
    name: name,
    quantity: 1,
    revenue: Money(revenue),
    costedRevenue: Money(costed ?? (cost == null ? 0 : revenue)),
    cost: cost == null ? null : Money(cost),
  );

  ProfitReport report({
    List<ProductProfit>? products,
    bool inclusive = false,
  }) => ProfitReport(
    filter: filter,
    pricesIncludeTax: inclusive,
    products: ProfitReport.ranked(
      products ??
          [
            item('Cola', revenue: 8000, cost: 4200),
            item('Salad', revenue: 1600, cost: 1700),
            item('Burger', revenue: 8500),
          ],
    ),
  );

  Map<String, List<List<Object?>>> read(
    ProfitReport? profit, {
    bool rightToLeft = false,
  }) {
    final bytes = itemsWorkbook(
      filter: filter,
      products: sold,
      strings: s,
      rightToLeft: rightToLeft,
      profit: profit,
    );
    final book = xl.Excel.decodeBytes(bytes);
    return {
      for (final entry in book.tables.entries)
        entry.key: [
          for (final row in entry.value.rows)
            [for (final cell in row) _plain(cell?.value)],
        ],
    };
  }

  /// The row whose first cell is [lead], cells padded to [width].
  List<Object?> row(List<List<Object?>> sheet, String lead, {int width = 6}) {
    final found = sheet.firstWhere(
      (r) => r.isNotEmpty && r.first == lead,
      orElse: () => throw StateError('no row starting "$lead"'),
    );
    return [for (var i = 0; i < width; i++) i < found.length ? found[i] : null];
  }

  int minor(Object? cell) => Money.tryParse('${cell! as num}')!.minor;
  int bp(Object? cell) => ((cell! as num) * 10000).round();

  test('without a profit report the workbook is the Items sheet alone', () {
    expect(read(null).keys, [s.reportsItems]);
  });

  test('with one, the Profit sheet follows the Items sheet', () {
    expect(read(report()).keys, [s.reportsItems, s.profitTitle]);
  });

  test('a profit report with no sales adds nothing', () {
    expect(read(report(products: const [])).keys, [s.reportsItems]);
  });

  group('the sheet', () {
    late List<List<Object?>> sheet;
    setUp(() => sheet = read(report())[s.profitTitle]!);

    test('says the period and the currency above the table, as Items does', () {
      expect(sheet[0].first, s.exportPeriodFrom);
      expect(sheet[1].first, s.exportPeriodTo);
      // The decoder pads every row to the table's width, so look at two.
      expect(sheet[2].take(2), [s.currency, 'EGP']);
    });

    test('headed in the page\'s columns, with the currency on each amount', () {
      final header = sheet.firstWhere((r) => r.first == s.exportColumnProduct);

      expect(header.take(5), [
        s.exportColumnProduct,
        '${s.reportColumnAmount} (EGP)',
        '${s.profitColumnCost} (EGP)',
        '${s.profitColumnProfit} (EGP)',
        s.profitColumnMargin,
      ]);
    });

    test('a costed item: amounts as numbers, margin as a percentage', () {
      final cola = row(sheet, 'Cola');

      expect(minor(cola[1]), 8000);
      expect(minor(cola[2]), 4200);
      expect(minor(cola[3]), 3800);
      expect(bp(cola[4]), 4750);
      expect(cola[5], isNull, reason: 'a costed row carries no tag');
    });

    test('a loss keeps its sign in both the profit and the margin', () {
      final salad = row(sheet, 'Salad');

      expect(minor(salad[3]), -100);
      expect(bp(salad[4]), -625);
    });

    test('an item with no cost is blank where the cost would be — never zero',
        () {
      final burger = row(sheet, 'Burger');

      expect(minor(burger[1]), 8500, reason: 'it still sold');
      expect(burger[2], isNull);
      expect(burger[3], isNull);
      expect(burger[4], isNull);
      expect(burger[5], s.profitNoCostTag, reason: 'said in words too');
    });

    test('the total is the whole report, margin on the costed part', () {
      final total = row(sheet, s.reportAllItems);

      expect(minor(total[1]), 18100);
      expect(minor(total[2]), 5900);
      expect(minor(total[3]), 3700);
      // 3,700 of the 9,600 that has a cost.
      expect(bp(total[4]), 3854);
    });

    test('and it carries its coverage, so the margin is never read alone', () {
      expect(minor(row(sheet, s.profitKpiCoverage)[1]), 9600);
      expect(minor(row(sheet, s.profitUncostedRevenue)[1]), 8500);
      // 9,600 of 18,100 is 53.04%.
      final share = row(
        sheet,
        '${s.profitKpiCoverage} · ${s.profitCoverageNote}',
      );
      expect(bp(share[1]), 5304);
    });

    test('ends with the page\'s sentence on what profit means here', () {
      expect(sheet.last.first, s.profitNote);
    });

    test('no tax warning when prices exclude tax', () {
      expect(
        sheet.any((r) => r.isNotEmpty && r.first == s.profitTaxNote),
        isFalse,
      );
    });
  });

  test('where prices hold tax the amount column is headed net', () {
    final inclusive = read(report(inclusive: true))[s.profitTitle]!;
    final header = inclusive.firstWhere((r) => r.first == s.exportColumnProduct);
    expect(header[1], '${s.profitColumnAmountNet} (EGP)');

    // And plain "Amount" where they do not — the Items sheet's own word.
    final exclusive = read(report())[s.profitTitle]!;
    final plain = exclusive.firstWhere((r) => r.first == s.exportColumnProduct);
    expect(plain[1], '${s.reportColumnAmount} (EGP)');
  });

  test('a restaurant that prices tax in is told how, inside the file', () {
    final sheet = read(report(inclusive: true))[s.profitTitle]!;

    expect(sheet.any((r) => r.isNotEmpty && r.first == s.profitTaxNote), isTrue);
    // Qualified, not withheld: the figures are still there.
    expect(row(sheet, 'Cola')[1], isNotNull);
  });

  group('when nothing has a cost', () {
    final uncosted = report(
      products: [item('Burger', revenue: 8500), item('Fries', revenue: 900)],
    );

    test('the sheet says how to get one, not a column of blanks', () {
      final sheet = read(uncosted)[s.profitTitle]!;

      expect(sheet.any((r) => r.isNotEmpty && r.first == s.profitNothingCosted), isTrue);
      expect(
        sheet.any((r) => r.isNotEmpty && r.first == s.exportColumnProduct),
        isFalse,
        reason: 'no table to read a margin off',
      );
      expect(sheet.any((r) => r.isNotEmpty && r.first == 'Burger'), isFalse);
    });

    test('the tax warning still applies', () {
      final inclusive = report(
        products: [item('Burger', revenue: 8500)],
        inclusive: true,
      );
      final sheet = read(inclusive)[s.profitTitle]!;

      expect(sheet.any((r) => r.isNotEmpty && r.first == s.profitTaxNote), isTrue);
    });
  });

  test('an Arabic workbook is still read from the right', () {
    final bytes = itemsWorkbook(
      filter: filter,
      products: sold,
      strings: const ArStrings(),
      rightToLeft: true,
      profit: report(),
    );
    final book = xl.Excel.decodeBytes(bytes);

    expect(book.tables.keys, ['الأصناف', 'الربح']);
    expect(book.tables['الربح']!.isRTL, isTrue);
  });
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
