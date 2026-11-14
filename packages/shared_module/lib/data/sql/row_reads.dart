import 'dart:convert';
import 'dart:typed_data';

/// Reading a column the same way on either engine (pos-cloud-single-till-sqlite).
///
/// PostgreSQL's driver hands back typed values — a `timestamptz` is a
/// `DateTime`, a `boolean` a `bool`, a `jsonb` a `Map`, an array a `List`.
/// SQLite has five storage classes and returns text, integers and blobs. The
/// repositories used to cast (`row[3] as DateTime`), which only one engine can
/// satisfy; these accept what either engine sends and give back the one Dart
/// type the repository wants.
///
/// Timestamps are stored on SQLite as ISO-8601 text in UTC, so they sort in
/// time order and read back to the same instant PostgreSQL would return.
extension RowReads on List<Object?> {
  DateTime dateTime(int i) => readDateTime(this[i])!;

  DateTime? dateTimeOrNull(int i) => readDateTime(this[i]);

  bool boolean(int i) => readBool(this[i])!;

  bool? booleanOrNull(int i) => readBool(this[i]);

  /// A `jsonb` object, or the JSON text SQLite keeps it as.
  Map<String, Object?>? jsonMap(int i) => switch (readJson(this[i])) {
    final Map map => map.cast<String, Object?>(),
    _ => null,
  };

  /// An array (PostgreSQL) or a JSON array (SQLite, `json_group_array`).
  List<Object?>? list(int i) => switch (readJson(this[i])) {
    final List list => list,
    _ => null,
  };

  Uint8List? bytes(int i) => switch (this[i]) {
    null => null,
    final Uint8List bytes => bytes,
    final List<int> ints => Uint8List.fromList(ints),
    final Object other => throw FormatException('not bytes: $other'),
  };
}

/// See [RowReads]. Public so a value read outside a row (a single scalar)
/// is decoded by the same rule.
DateTime? readDateTime(Object? value) => switch (value) {
  null => null,
  final DateTime at => at,
  final String text => DateTime.parse(text),
  final int micros => DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
  final Object other => throw FormatException('not a timestamp: $other'),
};

bool? readBool(Object? value) => switch (value) {
  null => null,
  final bool flag => flag,
  final int n => n != 0,
  final Object other => throw FormatException('not a boolean: $other'),
};

Object? readJson(Object? value) => switch (value) {
  final String text => jsonDecode(text),
  _ => value,
};
