/// Reading a menu out of a spreadsheet.
///
/// A business arrives with its menu in Excel. Typing four hundred items into
/// a form is how an install takes three days and ends with typos in the prices,
/// so this reads the file they already have.
///
/// **The whole of this file is pure.** It takes rows of strings and produces a
/// plan; it opens no files, touches no database and knows nothing about either.
/// That is what lets the interesting part — what happens when row 47 has a
/// price of "forty-five" — be tested without a spreadsheet or a server.
library;

import '../../core/money/money.dart';
import '../models/catalog.dart';

/// What one row asks for.
enum MenuImportAction {
  /// No product with this SKU exists. It will be created.
  create,

  /// A product with this SKU exists and the row differs from it.
  update,

  /// A product with this SKU exists and the row says the same thing.
  unchanged,
}

/// One row, understood.
class MenuImportRow {
  const MenuImportRow({
    required this.lineNumber,
    required this.action,
    required this.categoryName,
    required this.nameEn,
    required this.price,
    this.nameAr,
    this.sku,
    this.barcode,
    this.isAvailable = true,
    this.existingProductId,
    this.changes = const [],
  });

  /// The row in the file, counting the header as 1 — so it matches what the
  /// person is looking at in Excel. Off-by-one here means somebody hunting the
  /// wrong line of a four-hundred-row sheet.
  final int lineNumber;

  final MenuImportAction action;
  final String categoryName;
  final String nameEn;
  final String? nameAr;
  final Money price;
  final String? sku;
  final String? barcode;
  final bool isAvailable;

  /// Set when this row updates something that already exists.
  final int? existingProductId;

  /// Which fields differ, for the preview. "Updates 40 products" is not a
  /// sentence anybody can approve; "changes the price of 40 products" is.
  final List<String> changes;
}

/// Why a row could not be used.
class MenuImportProblem {
  const MenuImportProblem({
    required this.lineNumber,
    required this.column,
    required this.message,
  });

  final int lineNumber;
  final String column;
  final String message;
}

/// What an import would do, before it does any of it.
class MenuImportPlan {
  const MenuImportPlan({
    required this.rows,
    required this.problems,
    required this.newCategories,
  });

  final List<MenuImportRow> rows;
  final List<MenuImportProblem> problems;

  /// Categories named in the file that do not exist yet, in first-seen order.
  final List<String> newCategories;

  Iterable<MenuImportRow> get creates =>
      rows.where((r) => r.action == MenuImportAction.create);
  Iterable<MenuImportRow> get updates =>
      rows.where((r) => r.action == MenuImportAction.update);
  Iterable<MenuImportRow> get unchanged =>
      rows.where((r) => r.action == MenuImportAction.unchanged);

  bool get hasProblems => problems.isNotEmpty;

  /// Nothing to do. A file of rows that all match what is already there is a
  /// successful import of nothing, not a failure.
  bool get isEmpty => creates.isEmpty && updates.isEmpty;

  /// **A plan with any problem in it is not applied at all.**
  ///
  /// Half a menu is worse than none: the operator cannot tell which half
  /// landed, and re-running the file would double what did. All or nothing,
  /// and the problems are listed so the file can be fixed once.
  bool get canApply => !hasProblems && !isEmpty;
}

/// Turning rows of strings into a plan.
abstract final class MenuImport {
  /// The columns this reads, in the order a template writes them.
  ///
  /// Matched case-insensitively and ignoring spaces, because a spreadsheet that
  /// has been through three people has "Name (EN)", "name_en" and "NAME EN" in
  /// it and all three mean the same thing.
  static const columns = <String>[
    'category',
    'name_en',
    'name_ar',
    'price',
    'sku',
    'barcode',
    'available',
  ];

  /// A header row for the template a business is handed.
  static const templateHeader = <String>[
    'Category',
    'Name (EN)',
    'Name (AR)',
    'Price',
    'SKU',
    'Barcode',
    'Available',
  ];

  static String _key(String header) =>
      header.toLowerCase().replaceAll(RegExp(r'[\s_()-]'), '');

  /// Which column each of [columns] sits in, or null when it is absent.
  ///
  /// Returns null overall when the two columns that cannot be guessed —
  /// a name and a price — are missing.
  static Map<String, int>? _map(List<String> header) {
    const aliases = <String, List<String>>{
      'category': ['category', 'categoryen', 'section', 'group'],
      'name_en': ['nameen', 'name', 'item', 'itemen', 'product'],
      'name_ar': ['namear', 'arabicname', 'arabic'],
      'price': ['price', 'priceegp', 'amount', 'unitprice'],
      'sku': ['sku', 'code', 'itemcode'],
      'barcode': ['barcode', 'ean'],
      'available': ['available', 'isavailable', 'active', 'instock'],
    };

    final found = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final key = _key(header[i]);
      for (final entry in aliases.entries) {
        if (found.containsKey(entry.key)) continue;
        if (entry.value.contains(key)) found[entry.key] = i;
      }
    }

    if (!found.containsKey('name_en') || !found.containsKey('price')) {
      return null;
    }
    return found;
  }

  /// Read [rows] — the first of which is the header — against [existing].
  ///
  /// [existing] is the menu as it stands. Rows are matched to it by **SKU**,
  /// falling back to an exact name match when a row carries none, so that
  /// re-importing a corrected file updates rather than duplicating.
  ///
  /// Nothing is ever deleted. A product missing from the file is a product the
  /// business did not mention, not one it wants gone — and an import that
  /// could empty a menu is one nobody should run on a Friday.
  static MenuImportPlan read(
    List<List<String>> rows, {
    required List<Product> existing,
    required List<Category> categories,
    String currency = 'EGP',
    int exponent = 2,
  }) {
    final problems = <MenuImportProblem>[];
    if (rows.isEmpty) {
      return const MenuImportPlan(
        rows: [],
        problems: [
          MenuImportProblem(
            lineNumber: 0,
            column: '',
            message: 'The file is empty.',
          ),
        ],
        newCategories: [],
      );
    }

    final map = _map(rows.first);
    if (map == null) {
      return const MenuImportPlan(
        rows: [],
        problems: [
          MenuImportProblem(
            lineNumber: 1,
            column: 'header',
            message:
                'The header row needs at least a name column and a price '
                'column.',
          ),
        ],
        newCategories: [],
      );
    }

    final bySku = <String, Product>{
      for (final p in existing)
        if (p.sku != null && p.sku!.isNotEmpty) p.sku!.toLowerCase(): p,
    };
    final byName = <String, Product>{
      for (final p in existing) p.nameEn.trim().toLowerCase(): p,
    };
    final knownCategories = <String>{
      for (final c in categories) c.nameEn.trim().toLowerCase(),
    };
    // Which category a product is in today, by name — so a row that moves an
    // item between categories counts as a change rather than passing as
    // "unchanged" and then being skipped.
    final categoryOf = <int, String>{
      for (final c in categories) c.id: c.nameEn.trim().toLowerCase(),
    };

    final parsed = <MenuImportRow>[];
    final newCategories = <String>[];
    // A file that names the same SKU twice is a file with a mistake in it, and
    // applying both rows would leave whichever came last silently winning.
    final seenSkus = <String, int>{};

    String? cell(List<String> row, String column) {
      final index = map[column];
      if (index == null || index >= row.length) return null;
      final value = row[index].trim();
      return value.isEmpty ? null : value;
    }

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final lineNumber = i + 1;

      // A blank line in the middle of a spreadsheet is normal and means
      // nothing. Skipped rather than reported.
      if (row.every((c) => c.trim().isEmpty)) continue;

      final nameEn = cell(row, 'name_en');
      if (nameEn == null) {
        problems.add(
          MenuImportProblem(
            lineNumber: lineNumber,
            column: 'name',
            message: 'A product needs a name.',
          ),
        );
        continue;
      }

      final rawPrice = cell(row, 'price');
      final price = rawPrice == null
          ? null
          : Money.tryParse(rawPrice, currency: currency, exponent: exponent);
      if (price == null || price.isNegative) {
        problems.add(
          MenuImportProblem(
            lineNumber: lineNumber,
            column: 'price',
            message: rawPrice == null
                ? 'A product needs a price.'
                : '"$rawPrice" is not a price.',
          ),
        );
        continue;
      }

      final sku = cell(row, 'sku');
      if (sku != null) {
        final key = sku.toLowerCase();
        final first = seenSkus[key];
        if (first != null) {
          problems.add(
            MenuImportProblem(
              lineNumber: lineNumber,
              column: 'sku',
              message: 'SKU "$sku" is already used on line $first.',
            ),
          );
          continue;
        }
        seenSkus[key] = lineNumber;
      }

      final categoryName = cell(row, 'category') ?? '';
      if (categoryName.isEmpty) {
        problems.add(
          MenuImportProblem(
            lineNumber: lineNumber,
            column: 'category',
            message: 'A product needs a category.',
          ),
        );
        continue;
      }
      if (!knownCategories.contains(categoryName.toLowerCase()) &&
          !newCategories.any(
            (c) => c.toLowerCase() == categoryName.toLowerCase(),
          )) {
        newCategories.add(categoryName);
      }

      // SKU first, then name. The fallback matters more than it looks: the
      // first file a business sends is usually its existing menu with SKUs
      // newly added, and matching on SKU alone would file all four hundred
      // rows as new and duplicate the entire menu.
      var match = sku == null ? null : bySku[sku.toLowerCase()];
      if (match == null) {
        final named = byName[nameEn.toLowerCase()];
        final heldSku = named?.sku ?? '';
        if (named != null && sku != null && heldSku.isNotEmpty) {
          // Two identities disagree: this name is on the menu already, under a
          // different SKU. Guessing either way would be wrong — one way
          // duplicates the item, the other rewrites the code the kitchen and
          // the stock count use.
          problems.add(
            MenuImportProblem(
              lineNumber: lineNumber,
              column: 'sku',
              message:
                  '"$nameEn" is already on the menu under SKU "$heldSku", '
                  'not "$sku".',
            ),
          );
          continue;
        }
        match = named;
      }

      final available = _boolean(cell(row, 'available')) ?? true;
      final nameAr = cell(row, 'name_ar');
      final barcode = cell(row, 'barcode');

      final changes = <String>[];
      if (match != null) {
        if (match.price.minor != price.minor) changes.add('price');
        if (match.nameEn != nameEn) changes.add('name');
        if ((match.nameAr ?? '') != (nameAr ?? '')) changes.add('Arabic name');
        if ((match.barcode ?? '') != (barcode ?? '')) changes.add('barcode');
        if (match.isAvailable != available) changes.add('availability');
        if (categoryOf[match.categoryId] != categoryName.toLowerCase()) {
          changes.add('category');
        }
        // A file that gives a SKU to an item matched by name is filling in
        // something the menu was missing, and that is worth writing.
        if (sku != null && (match.sku ?? '') != sku) changes.add('SKU');
      }

      parsed.add(
        MenuImportRow(
          lineNumber: lineNumber,
          action: match == null
              ? MenuImportAction.create
              : (changes.isEmpty
                    ? MenuImportAction.unchanged
                    : MenuImportAction.update),
          categoryName: categoryName,
          nameEn: nameEn,
          nameAr: nameAr,
          price: price,
          sku: sku,
          barcode: barcode,
          isAvailable: available,
          existingProductId: match?.id,
          changes: changes,
        ),
      );
    }

    return MenuImportPlan(
      rows: parsed,
      problems: problems,
      newCategories: newCategories,
    );
  }

  /// What a spreadsheet puts in an "Available" column.
  ///
  /// Anything unrecognised is **null**, and the caller defaults it to true — a
  /// product silently marked unavailable because somebody typed "Y" is a
  /// product that vanishes from the grid with no explanation.
  static bool? _boolean(String? value) => switch (value?.toLowerCase()) {
    'true' || 'yes' || 'y' || '1' || 'available' => true,
    'false' || 'no' || 'n' || '0' || 'unavailable' => false,
    _ => null,
  };
}
