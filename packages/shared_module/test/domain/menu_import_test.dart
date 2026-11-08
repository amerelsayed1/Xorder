import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/services/menu_import.dart';

/// Reading a menu out of a spreadsheet.
///
/// A business arrives with four hundred items in Excel. What matters is not
/// the happy path — it is what happens on row 47 when the price says
/// "forty-five", because that is the row that decides whether the operator
/// trusts the feature or types the menu in by hand anyway.
void main() {
  Product product(
    int id,
    String name,
    int price, {
    String? sku,
    String? nameAr,
    String? barcode,
    bool isAvailable = true,
  }) => Product(
    id: id,
    categoryId: 1,
    nameEn: name,
    nameAr: nameAr,
    price: Money(price),
    sku: sku,
    barcode: barcode,
    isAvailable: isAvailable,
  );

  const mains = Category(id: 1, nameEn: 'Mains');

  MenuImportPlan read(
    List<List<String>> rows, {
    List<Product> existing = const [],
    List<Category> categories = const [mains],
  }) => MenuImport.read(rows, existing: existing, categories: categories);

  final header = MenuImport.templateHeader;

  group('reading a clean file', () {
    test('creates what is not there', () {
      final plan = read([
        header,
        ['Mains', 'Koshari', 'كشري', '45.00', 'K-1', '', 'yes'],
      ]);

      expect(plan.problems, isEmpty);
      expect(plan.creates, hasLength(1));

      final row = plan.creates.single;
      expect(row.nameEn, 'Koshari');
      expect(row.nameAr, 'كشري');
      expect(row.price.minor, 4500);
      expect(row.sku, 'K-1');
      expect(row.isAvailable, isTrue);
      expect(plan.canApply, isTrue);
    });

    test('a price never goes through a double', () {
      // The whole money model exists so that 45.10 is 4510 and not 4509.
      final plan = read([
        header,
        ['Mains', 'A', '', '45.10', '', '', ''],
        ['Mains', 'B', '', '0.05', '', '', ''],
        ['Mains', 'C', '', '1234.99', '', '', ''],
      ]);
      expect(plan.creates.map((r) => r.price.minor), [4510, 5, 123499]);
    });

    test('a blank line in the middle means nothing', () {
      // Normal in any spreadsheet that has been edited by a person.
      final plan = read([
        header,
        ['Mains', 'A', '', '10.00', '', '', ''],
        ['', '', '', '', '', '', ''],
        ['Mains', 'B', '', '20.00', '', '', ''],
      ]);
      expect(plan.problems, isEmpty);
      expect(plan.creates, hasLength(2));
    });

    test('line numbers match what Excel shows', () {
      // Off by one here means somebody hunting the wrong line of a
      // four-hundred-row sheet.
      final plan = read([
        header,
        ['Mains', 'A', '', 'nonsense', '', '', ''],
      ]);
      expect(plan.problems.single.lineNumber, 2);
    });
  });

  group('matching what already exists', () {
    test('an SKU updates rather than duplicating', () {
      final plan = read(
        [
          header,
          ['Mains', 'Koshari', '', '50.00', 'K-1', '', ''],
        ],
        existing: [product(7, 'Koshari', 4500, sku: 'K-1')],
      );

      expect(plan.creates, isEmpty);
      expect(plan.updates, hasLength(1));
      expect(plan.updates.single.existingProductId, 7);
      expect(plan.updates.single.changes, contains('price'));
    });

    test('a row with no SKU falls back to an exact name', () {
      final plan = read(
        [
          header,
          ['Mains', 'Koshari', '', '50.00', '', '', ''],
        ],
        existing: [product(7, 'Koshari', 4500)],
      );
      expect(plan.updates.single.existingProductId, 7);
    });

    test('a row that says the same thing changes nothing', () {
      final plan = read(
        [
          header,
          ['Mains', 'Koshari', '', '45.00', 'K-1', '', 'yes'],
        ],
        existing: [product(7, 'Koshari', 4500, sku: 'K-1')],
      );

      expect(plan.unchanged, hasLength(1));
      expect(plan.updates, isEmpty);
      // A file of rows that all match is a successful import of nothing.
      expect(plan.isEmpty, isTrue);
      expect(plan.canApply, isFalse);
    });

    test('it names which fields differ', () {
      // "Updates 40 products" is not a sentence anybody can approve;
      // "changes the price of 40 products" is.
      final plan = read(
        [
          header,
          ['Mains', 'Koshari', 'كشري', '50.00', 'K-1', '', 'no'],
        ],
        existing: [product(7, 'Koshari', 4500, sku: 'K-1')],
      );

      expect(plan.updates.single.changes, containsAll(<String>[
        'price',
        'Arabic name',
        'availability',
      ]));
    });

    test('moving an item to another category counts as a change', () {
      // Without this the row parses as identical, is filed as "unchanged" and
      // is then skipped — so the move silently never happens.
      const desserts = Category(id: 2, nameEn: 'Desserts');
      final plan = read(
        [
          header,
          ['Desserts', 'Koshari', '', '45.00', 'K-1', '', ''],
        ],
        existing: [product(7, 'Koshari', 4500, sku: 'K-1')],
        categories: const [mains, desserts],
      );

      expect(plan.updates.single.changes, contains('category'));
      expect(plan.newCategories, isEmpty);
    });

    test('a SKU the menu was missing is filled in', () {
      // Matched by name, because the product has no SKU to match on. The file
      // is the first thing that knows one, and that is worth writing.
      final plan = read(
        [
          header,
          ['Mains', 'Koshari', '', '45.00', 'K-1', '', ''],
        ],
        existing: [product(7, 'Koshari', 4500)],
      );

      expect(plan.updates.single.changes, contains('SKU'));
    });

    test('a name already held under a different SKU is refused, not guessed', () {
      final plan = read(
        [
          header,
          ['Mains', 'Koshari', '', '45.00', 'K-1', '', ''],
        ],
        existing: [product(7, 'Koshari', 4500, sku: 'X-9')],
      );

      // Either guess is wrong: one duplicates the item, the other rewrites the
      // code the kitchen and the stock count use.
      expect(plan.problems.single.column, 'sku');
      expect(plan.problems.single.message, contains('X-9'));
      expect(plan.canApply, isFalse);
    });

    test('a file with no SKU column says nothing about SKUs', () {
      // Silence is not an instruction to forget one.
      final plan = read(
        [
          ['Category', 'Name (EN)', 'Price'],
          ['Mains', 'Koshari', '45.00'],
        ],
        existing: [product(7, 'Koshari', 4500, sku: 'K-1')],
      );

      expect(plan.unchanged, hasLength(1));
    });

    test('nothing is ever deleted', () {
      // A product missing from the file is one the business did not mention,
      // not one it wants gone. An import that could empty a menu is one nobody
      // should run on a Friday.
      final plan = read(
        [
          header,
          ['Mains', 'Koshari', '', '45.00', 'K-1', '', ''],
        ],
        existing: [
          product(7, 'Koshari', 4500, sku: 'K-1'),
          product(8, 'Molokhia', 6000, sku: 'M-1'),
        ],
      );

      // The plan simply has nothing to say about Molokhia.
      expect(plan.rows.map((r) => r.existingProductId), [7]);
    });
  });

  group('categories', () {
    test('one that does not exist yet is reported, not invented silently', () {
      final plan = read([
        header,
        ['Desserts', 'Om Ali', '', '35.00', '', '', ''],
      ]);
      expect(plan.newCategories, ['Desserts']);
    });

    test('an existing one is not listed as new', () {
      final plan = read([
        header,
        ['Mains', 'Koshari', '', '45.00', '', '', ''],
      ]);
      expect(plan.newCategories, isEmpty);
    });

    test('it is matched case-insensitively', () {
      final plan = read([
        header,
        ['MAINS', 'Koshari', '', '45.00', '', '', ''],
      ]);
      expect(plan.newCategories, isEmpty);
    });

    test('a new one is listed once however many rows use it', () {
      final plan = read([
        header,
        ['Desserts', 'A', '', '10.00', '', '', ''],
        ['Desserts', 'B', '', '20.00', '', '', ''],
      ]);
      expect(plan.newCategories, ['Desserts']);
    });
  });

  group('headers a real spreadsheet has', () {
    test('spacing, case and punctuation do not matter', () {
      // A sheet that has been through three people has "Name (EN)", "name_en"
      // and "NAME EN" in it, and all three mean the same thing.
      for (final variant in [
        ['Category', 'Name (EN)', 'Name (AR)', 'Price', 'SKU', 'Barcode', 'Available'],
        ['category', 'name_en', 'name_ar', 'price', 'sku', 'barcode', 'available'],
        ['SECTION', 'ITEM', 'ARABIC NAME', 'UNIT PRICE', 'CODE', 'EAN', 'ACTIVE'],
      ]) {
        final plan = read([
          variant,
          ['Mains', 'Koshari', 'كشري', '45.00', 'K-1', '123', 'yes'],
        ]);
        expect(plan.problems, isEmpty, reason: variant.join(','));
        expect(plan.creates.single.price.minor, 4500);
      }
    });

    test('columns may be in any order', () {
      final plan = read([
        ['Price', 'Item', 'Category'],
        ['45.00', 'Koshari', 'Mains'],
      ]);
      expect(plan.creates.single.nameEn, 'Koshari');
      expect(plan.creates.single.price.minor, 4500);
    });

    test('optional columns may be absent entirely', () {
      final plan = read([
        ['Category', 'Name', 'Price'],
        ['Mains', 'Koshari', '45.00'],
      ]);
      expect(plan.problems, isEmpty);
      expect(plan.creates.single.sku, isNull);
      expect(plan.creates.single.isAvailable, isTrue);
    });

    test('a file with no name or price column is refused outright', () {
      final plan = read([
        ['Notes', 'Colour'],
        ['something', 'red'],
      ]);
      expect(plan.problems.single.column, 'header');
      expect(plan.canApply, isFalse);
    });

    test('an empty file says so', () {
      expect(read(const []).problems, hasLength(1));
    });
  });

  group('rows that cannot be used', () {
    test('a price that is not a number', () {
      final plan = read([
        header,
        ['Mains', 'Koshari', '', 'forty-five', '', '', ''],
      ]);
      expect(plan.problems.single.column, 'price');
      expect(plan.problems.single.message, contains('forty-five'));
    });

    test('a missing price, a missing name, a missing category', () {
      final plan = read([
        header,
        ['Mains', 'Koshari', '', '', '', '', ''],
        ['Mains', '', '', '45.00', '', '', ''],
        ['', 'Koshari', '', '45.00', '', '', ''],
      ]);
      expect(plan.problems.map((p) => p.column), ['price', 'name', 'category']);
    });

    test('a negative price', () {
      final plan = read([
        header,
        ['Mains', 'Koshari', '', '-45.00', '', '', ''],
      ]);
      expect(plan.problems.single.column, 'price');
    });

    test('the same SKU twice, naming the first line', () {
      final plan = read([
        header,
        ['Mains', 'A', '', '10.00', 'K-1', '', ''],
        ['Mains', 'B', '', '20.00', 'K-1', '', ''],
      ]);
      expect(plan.problems.single.column, 'sku');
      // Names where the collision started, so the file can be fixed once.
      expect(plan.problems.single.message, contains('line 2'));
      expect(plan.problems.single.lineNumber, 3);
    });

    test('one bad row blocks the whole file', () {
      // Half a menu is worse than none: the operator cannot tell which half
      // landed, and re-running the file would double what did.
      final plan = read([
        header,
        ['Mains', 'A', '', '10.00', '', '', ''],
        ['Mains', 'B', '', 'oops', '', '', ''],
      ]);

      expect(plan.creates, hasLength(1));
      expect(plan.hasProblems, isTrue);
      expect(plan.canApply, isFalse);
    });
  });

  group('the available column', () {
    test('accepts what a person types', () {
      for (final yes in ['yes', 'Y', 'TRUE', '1', 'available']) {
        final plan = read([
          header,
          ['Mains', 'A', '', '10.00', '', '', yes],
        ]);
        expect(plan.creates.single.isAvailable, isTrue, reason: yes);
      }
      for (final no in ['no', 'N', 'false', '0', 'unavailable']) {
        final plan = read([
          header,
          ['Mains', 'A', '', '10.00', '', '', no],
        ]);
        expect(plan.creates.single.isAvailable, isFalse, reason: no);
      }
    });

    test('anything unrecognised means available', () {
      // A product silently marked unavailable because somebody typed "maybe"
      // is a product that vanishes from the grid with no explanation.
      final plan = read([
        header,
        ['Mains', 'A', '', '10.00', '', '', 'maybe'],
      ]);
      expect(plan.creates.single.isAvailable, isTrue);
    });
  });
}
