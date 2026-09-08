import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/import/spreadsheet_reader.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/services/menu_import.dart';

/// Turning a real file's text into rows.
///
/// The cases here are the ones a restaurant's actual export produces — a BOM
/// Excel wrote, Windows line endings, a comma inside a product name — each of
/// which silently breaks a naive split.
void main() {
  List<List<String>> parse(String text, {bool tabs = false}) =>
      SpreadsheetReader.parseDelimited(text, tabs: tabs);

  group('CSV a spreadsheet actually writes', () {
    test('plain rows', () {
      final rows = parse('Category,Name,Price\nMains,Koshari,45.00');
      expect(rows, [
        ['Category', 'Name', 'Price'],
        ['Mains', 'Koshari', '45.00'],
      ]);
    });

    test('Windows line endings', () {
      final rows = parse('Category,Name,Price\r\nMains,Koshari,45.00\r\n');
      expect(rows.first, ['Category', 'Name', 'Price']);
      expect(rows[1], ['Mains', 'Koshari', '45.00']);
    });

    test('the BOM Excel writes on a UTF-8 CSV', () {
      // Left in place it becomes part of the first header, "Category" stops
      // matching, and the whole file is rejected for having no columns.
      final rows = parse('﻿Category,Name,Price\nMains,Koshari,45.00');
      expect(rows.first.first, 'Category');

      final plan = MenuImport.read(
        rows,
        existing: const [],
        categories: const [Category(id: 1, nameEn: 'Mains')],
      );
      expect(plan.problems, isEmpty);
    });

    test('a comma inside a quoted name', () {
      final rows = parse('Name,Price\n"Koshari, large",45.00');
      expect(rows[1], ['Koshari, large', '45.00']);
    });

    test('a quote inside a quoted name', () {
      final rows = parse('Name,Price\n"Chef""s special",45.00');
      expect(rows[1].first, 'Chef"s special');
    });

    test('Arabic survives intact', () {
      final rows = parse('Name,Arabic,Price\nKoshari,كشري,45.00');
      expect(rows[1][1], 'كشري');
    });

    test('a ragged row is not padded', () {
      // The reader reports what is there; `MenuImport` decides what a missing
      // cell means, and it has better words for it than a blank string.
      final rows = parse('A,B,C\n1,2');
      expect(rows[1], hasLength(2));
    });

    test('tabs when the file says tabs', () {
      final rows = parse('Name\tPrice\nKoshari\t45.00', tabs: true);
      expect(rows[1], ['Koshari', '45.00']);
    });

    test('a comma-heavy file is not sniffed as tab-separated', () {
      // Auto-detection is off on purpose: a menu whose names contain commas and
      // whose file contains no tabs would otherwise come back as one column.
      final rows = parse('Name,Price\n"Koshari, large",45.00');
      expect(rows[1], hasLength(2));
    });
  });

  group('prices do not go through a double', () {
    test('a price with trailing zeros keeps them', () {
      // The reason dynamic typing is off. 45.10 parsed as a double and printed
      // back is "45.1", and 0.1 + 0.2 is where money bugs come from.
      final rows = parse('Name,Price\nA,45.10');
      expect(rows[1][1], '45.10');
    });

    test('and reaches the plan as minor units', () {
      final plan = MenuImport.read(
        parse('Category,Name,Price\nMains,A,45.10'),
        existing: const [],
        categories: const [Category(id: 1, nameEn: 'Mains')],
      );
      expect(plan.creates.single.price.minor, 4510);
    });
  });

  group('what it offers a file chooser', () {
    test('the formats a restaurant will actually hand over', () {
      expect(SpreadsheetReader.extensions, contains('csv'));
      expect(SpreadsheetReader.extensions, contains('xlsx'));
    });
  });
}
