import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

/// Turning a file on disk into rows of strings.
///
/// The one place that knows about file formats. Everything downstream —
/// `MenuImport` and its plan — works on `List<List<String>>` and has no idea
/// whether it came from Excel, a CSV, or a test.
abstract final class SpreadsheetReader {
  /// What a file chooser should offer.
  static const extensions = ['csv', 'xlsx', 'xlsm', 'tsv', 'txt'];

  /// Read [path], choosing a parser by its extension.
  ///
  /// Throws [SpreadsheetUnreadable] with a sentence an operator can act on.
  /// Every failure here is somebody's file being wrong, which is a normal thing
  /// for a file to be — none of them are bugs.
  static Future<List<List<String>>> read(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw const SpreadsheetUnreadable('That file is no longer there.');
    }

    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'xlsx' || 'xlsm' => _excel(await file.readAsBytes()),
      // `.xls` is a different, older format the `excel` package does not read.
      // Named explicitly rather than falling through to the CSV parser, which
      // would produce one row of binary rubbish and a baffling error.
      'xls' => throw const SpreadsheetUnreadable(
        'That is an older .xls file. Open it in Excel and save it as .xlsx '
        'or .csv.',
      ),
      _ => parseDelimited(
        await file.readAsString(encoding: utf8),
        tabs: extension == 'tsv',
      ),
    };
  }

  /// Rows from a CSV or tab-separated file. Public so it can be tested without
  /// touching a disk.
  static List<List<String>> parseDelimited(String text, {bool tabs = false}) {
    // The BOM Excel writes when it saves a UTF-8 CSV. Left in place it becomes
    // part of the first header, so "Category" stops matching and the whole file
    // is rejected for having no columns.
    final body = text.startsWith('﻿') ? text.substring(1) : text;

    // `autoDetect: false`, because a menu with a comma in a product name and
    // no tabs anywhere would otherwise be sniffed as tab-separated and come
    // back as one column. The extension already said which it is.
    //
    // `dynamicTyping: false` for the reason the whole money model exists: a
    // price parsed into a `double` here is a price that has already lost.
    final rows = Csv(
      fieldDelimiter: tabs ? '\t' : ',',
      autoDetect: false,
      dynamicTyping: false,
      skipEmptyLines: false,
    ).decode(body.replaceAll('\r\n', '\n'));

    return [
      for (final row in rows) [for (final cell in row) '${cell ?? ''}'],
    ];
  }

  /// Rows from the **first** sheet of a workbook.
  ///
  /// The first, not a named one: a business's menu file has its menu on the
  /// sheet that opens, and asking somebody to rename a tab before they can
  /// import is asking them to do the computer's job.
  static List<List<String>> _excel(List<int> bytes) {
    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } on Object {
      throw const SpreadsheetUnreadable(
        'That file could not be opened as a spreadsheet.',
      );
    }

    final name = book.tables.keys.firstOrNull;
    if (name == null) {
      throw const SpreadsheetUnreadable('That workbook has no sheets in it.');
    }

    return [
      for (final row in book.tables[name]!.rows)
        [
          for (final cell in row)
            // The cell's string form is what a person sees in it, which is what
            // the parser expects. A price stored as a number arrives as "45" or
            // "45.5" and `Money.tryParse` handles both — going through a double
            // to "reformat" it is exactly what the money model exists to stop.
            cell?.value?.toString().trim() ?? '',
        ],
    ];
  }
}

/// A file that cannot be read, in words an operator can act on.
class SpreadsheetUnreadable implements Exception {
  const SpreadsheetUnreadable(this.message);

  final String message;

  @override
  String toString() => message;
}
