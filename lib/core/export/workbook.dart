/// A spreadsheet written from figures a screen already holds (BO-11).
///
/// **Typed cells, never numbers spelled as text.** A total written as the
/// string `1,234.50` is a cell Excel will not add up, and adding things up
/// somewhere else is the reason anybody exports. So an amount is a number
/// under a number format, a date is a date, a share is a percentage, and only
/// words are text.
///
/// **One writer for both exports**, so the Reports file and the Sales file
/// cannot come to disagree about how a piastre or a date is written.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import '../money/money.dart';

/// What one cell holds. Closed, so a new kind is a compile error in the
/// writer rather than a cell that reads `Instance of …`.
sealed class WorkbookCell {
  const WorkbookCell();
}

class TextCell extends WorkbookCell {
  const TextCell(this.text);
  final String text;
}

class CountCell extends WorkbookCell {
  const CountCell(this.count);
  final int count;
}

class MoneyCell extends WorkbookCell {
  const MoneyCell(this.money);
  final Money money;
}

/// A share or a change in basis points, shown as a percentage: 1234 is
/// 12.34%, as the screen prints it.
class BasisPointsCell extends WorkbookCell {
  const BasisPointsCell(this.basisPoints);
  final int basisPoints;
}

/// A business date — a day, with no time in it.
class DateCell extends WorkbookCell {
  const DateCell(this.date);
  final DateTime date;
}

/// An instant, to the minute, in the till's own time zone.
class DateTimeCell extends WorkbookCell {
  const DateTimeCell(this.at);
  final DateTime at;
}

/// A workbook of one or more sheets, in the operator's reading direction.
///
/// Rows are held here and handed to the `excel` package only in [encode],
/// for the reason given there.
class WorkbookWriter {
  WorkbookWriter({required this.rightToLeft});

  /// Set on every sheet, so an Arabic file opens with its first column at
  /// the right, as the screen it came from reads.
  final bool rightToLeft;

  final List<WorkbookSheet> _sheets = [];

  /// A new sheet named [name], cut to what Excel accepts.
  WorkbookSheet sheet(String name) {
    final sheet = WorkbookSheet._(_sheetName(name));
    _sheets.add(sheet);
    return sheet;
  }

  /// The .xlsx file's bytes.
  ///
  /// **An Arabic file is saved once empty, then again full.** `excel` 4.0.6
  /// writes the XML for a sheet made in memory during its first save, and
  /// making it reads the new sheet's view back over the sheet — a view with
  /// no `rightToLeft` — so a sheet flagged before that save comes out left
  /// to right, silently; the round-trip test caught it. And every save
  /// appends the cell styles again, so saving a full workbook twice left
  /// `styles.xml` with eleven formats under a count of six, which is the
  /// kind of file Excel offers to "repair". So the first save is of empty
  /// sheets, before any cell has a style: it makes their XML and nothing
  /// else, the flag set after it survives, and the styles are written once.
  ///
  /// Rejected: writing `rightToLeft` into the zip ourselves, which is a
  /// second writer of a format the package owns.
  Uint8List encode() {
    final book = xl.Excel.createExcel();
    // A new workbook comes with one empty sheet; the first sheet takes it
    // over rather than leaving a blank "Sheet1" in front.
    final blank = book.getDefaultSheet();
    for (final (i, sheet) in _sheets.indexed) {
      if (i == 0 && blank != null && blank != sheet.name) {
        book.rename(blank, sheet.name);
      } else {
        book[sheet.name];
      }
    }
    if (rightToLeft) {
      book.encode();
      for (final sheet in _sheets) {
        book[sheet.name].isRTL = true;
      }
    }
    for (final sheet in _sheets) {
      sheet._writeTo(book[sheet.name]);
    }
    if (_sheets.isNotEmpty) book.setDefaultSheet(_sheets.first.name);
    final bytes = book.encode();
    if (bytes == null) throw StateError('The workbook could not be encoded.');
    return Uint8List.fromList(bytes);
  }

  /// Excel refuses a sheet name over 31 characters or holding any of
  /// `[ ] : * ? / \`. The names are the screen's section titles in either
  /// language, which today fit; cut rather than refused, so a longer
  /// translation next year is a shorter tab and not a file that will not open.
  static String _sheetName(String name) {
    final clean = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    return clean.length <= 31 ? clean : clean.substring(0, 31);
  }
}

/// One sheet, written a row at a time from the top.
class WorkbookSheet {
  WorkbookSheet._(this.name);

  final String name;
  final _rows = <({List<WorkbookCell?> cells, bool bold})>[];

  /// A row of column headings, in bold.
  void header(List<String> titles) => _rows.add((
    cells: [for (final title in titles) TextCell(title)],
    bold: true,
  ));

  /// A row of cells, left to right in the sheet's own direction. A null is
  /// an empty cell — what the screen draws as a dash, which in a sheet
  /// would be text in a column of numbers.
  void row(List<WorkbookCell?> cells) => _rows.add((cells: cells, bold: false));

  void blank() => _rows.add((cells: const [], bold: false));

  void _writeTo(xl.Sheet sheet) {
    final widths = <int, int>{};
    for (final (index, row) in _rows.indexed) {
      for (final (column, cell) in row.cells.indexed) {
        if (cell == null) continue;
        sheet.updateCell(
          xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: index),
          _value(cell),
          cellStyle: xl.CellStyle(bold: row.bold, numberFormat: _format(cell)),
        );
        widths[column] = math.max(widths[column] ?? 0, _width(cell));
      }
    }
    for (final MapEntry(key: column, value: width) in widths.entries) {
      sheet.setColumnWidth(column, math.min(width + 2, 60).toDouble());
    }
  }

  static xl.CellValue _value(WorkbookCell cell) => switch (cell) {
    TextCell(:final text) => xl.TextCellValue(text),
    CountCell(:final count) => xl.IntCellValue(count),
    MoneyCell(:final money) => xl.DoubleCellValue(_major(money)),
    BasisPointsCell(:final basisPoints) => xl.DoubleCellValue(
      basisPoints / 10000,
    ),
    DateCell(:final date) => xl.DateCellValue(
      year: date.year,
      month: date.month,
      day: date.day,
    ),
    DateTimeCell(:final at) => xl.DateTimeCellValue(
      year: at.year,
      month: at.month,
      day: at.day,
      hour: at.hour,
      minute: at.minute,
    ),
  };

  /// **The one place an amount becomes a double**, and it is the file's
  /// doing, not ours: an .xlsx number is an IEEE double written out as text.
  /// Every figure was summed in minor units before it got here. A whole
  /// number of piastres over 100 is the double nearest the exact amount, and
  /// the shortest spelling of that double — what the package writes — is the
  /// amount's own digits: 123456 is written `1234.56`, never `1234.5599…`.
  /// The same holds for a share in basis points over 10,000.
  ///
  /// Rejected: the amount as text, which Excel will not add up; the minor
  /// units as an integer, which every reader would have to divide by hand.
  static double _major(Money money) {
    var scale = 1;
    for (var i = 0; i < money.exponent; i++) {
      scale *= 10;
    }
    return money.minor / scale;
  }

  static xl.NumFormat _format(WorkbookCell cell) => switch (cell) {
    TextCell() => xl.NumFormat.standard_0,
    CountCell() => xl.NumFormat.standard_3,
    // As many decimals as the currency has — two for the pound, three for a
    // Kuwaiti tenant — so a file never shows a fils the till did not charge.
    MoneyCell(:final money) => switch (money.exponent) {
      0 => xl.NumFormat.standard_3,
      2 => xl.NumFormat.standard_4,
      final places => xl.CustomNumericNumFormat(
        formatCode: '#,##0.${'0' * places}',
      ),
    },
    BasisPointsCell() => xl.NumFormat.standard_10,
    // The screens' own spelling of a date (`businessDayWire`), rather than
    // Excel's built-in short date, which is month-first on an English
    // Windows and reads 09-10 as the tenth of September's opposite.
    DateCell() => const xl.CustomDateTimeNumFormat(formatCode: 'yyyy-mm-dd'),
    DateTimeCell() => const xl.CustomDateTimeNumFormat(
      formatCode: 'yyyy-mm-dd hh:mm',
    ),
  };

  static int _width(WorkbookCell cell) => switch (cell) {
    TextCell(:final text) => text.length,
    CountCell() => 8,
    MoneyCell() => 14,
    BasisPointsCell() => 9,
    DateCell() => 11,
    DateTimeCell() => 17,
  };
}
