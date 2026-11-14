import 'dart:convert';
import 'dart:typed_data';

/// A repository statement, turned into one SQLite will run
/// (pos-cloud-single-till-sqlite, stage 3).
///
/// The repositories are written once, in the PostgreSQL the offline app has
/// always run. A cloud till runs the same text on SQLite, translated here on
/// the way in. Only the forms the repositories actually use are translated
/// (measured 2026-11-08); a form missing from this list fails loudly on SQLite
/// in the repository suites, which run on both engines, rather than quietly
/// meaning something else:
///
/// | PostgreSQL | SQLite |
/// |---|---|
/// | `@name` parameters | `?N`, bound from the map in order |
/// | `x = ANY(@list)` | `x IN (SELECT value FROM json_each(@list))` |
/// | `expr::date` | `date(expr)` |
/// | `::text`, `::bigint`, `::int`, `::jsonb`, … | dropped (SQLite is not typed) |
/// | `'{}'::text[]` | `'[]'` (an empty JSON array) |
/// | `FOR UPDATE [OF t]` | dropped: a transaction already holds the file's write lock |
/// | `ILIKE` | `LIKE` (SQLite's `LIKE` ignores case for ASCII letters) |
/// | `array_agg(…)` | `json_group_array(…)` |
/// | `bool_or(…)` / `bool_and(…)` | `max(…)` / `min(…)` |
/// | `GREATEST(…)` / `LEAST(…)` | `max(…)` / `min(…)` (SQLite's many-argument forms) |
/// | `string_agg(…)` | `group_concat(…)` |
/// | `IS [NOT] DISTINCT FROM` | `IS NOT` / `IS` |
/// | `ARRAY[a, b]` | `json_array(a, b)` |
/// | `(VALUES …) AS v(a, b)` | `(SELECT column1 AS a, column2 AS b FROM (VALUES …)) AS v` |
/// | `x + interval '1 hour'`, `x - interval '40 days'` | `strftime(…, x, '+1 hour')` |
/// | `x - make_interval(hours => n)` | `strftime(…, x, '-' \|\| n \|\| ' hours')` |
/// | `decode('ff00', 'hex')` | `X'ff00'` |
///
/// `now()` and `gen_random_uuid()` are not translated: the engine registers
/// SQLite functions by those names.
class SqliteStatement {
  SqliteStatement._(this.sql, this.values);

  /// The statement as SQLite runs it.
  final String sql;

  /// The values for its `?N` placeholders, in order, already encoded.
  final List<Object?> values;

  /// Translate [text] and bind [parameters] (a `Map<String, Object?>` keyed by
  /// name, or null).
  factory SqliteStatement.from(String text, Object? parameters) {
    final named = switch (parameters) {
      null => const <String, Object?>{},
      final Map<String, Object?> map => map,
      final Map map => map.cast<String, Object?>(),
      _ => throw ArgumentError.value(
        parameters,
        'parameters',
        'SQLite statements take named parameters only',
      ),
    };
    final order = <String>[];
    final sql = _bindNames(translate(text), order);
    return SqliteStatement._(sql, [
      for (final name in order)
        if (named.containsKey(name))
          encode(named[name])
        else
          throw ArgumentError('No value for @$name in: $text'),
    ]);
  }

  /// The PostgreSQL forms in [text] rewritten for SQLite, parameters left as
  /// `@name`. Public so each rule is testable on its own.
  static String translate(String text) {
    var sql = _outsideLiterals(text, (code) {
      var out = code;
      out = out.replaceAll(
        RegExp(
          r'\s+FOR\s+(NO\s+KEY\s+UPDATE|UPDATE|KEY\s+SHARE|SHARE)(\s+OF\s+\w+)?',
          caseSensitive: false,
        ),
        '',
      );
      out = out.replaceAll(RegExp(r'\bILIKE\b', caseSensitive: false), 'LIKE');
      out = out.replaceAll(RegExp(r'\bbtrim\s*\(', caseSensitive: false), 'trim(');
      out = out.replaceAllMapped(
        RegExp(r'\b(array_agg|bool_or|bool_and|GREATEST|LEAST|string_agg)\s*\(',
            caseSensitive: false),
        (m) => '${switch (m[1]!.toLowerCase()) {
          'array_agg' => 'json_group_array',
          'bool_or' || 'greatest' => 'max',
          'bool_and' || 'least' => 'min',
          _ => 'group_concat',
        }}(',
      );
      out = out.replaceAll(
        RegExp(r'\bIS\s+NOT\s+DISTINCT\s+FROM\b', caseSensitive: false),
        'IS',
      );
      out = out.replaceAll(
        RegExp(r'\bIS\s+DISTINCT\s+FROM\b', caseSensitive: false),
        'IS NOT',
      );
      return out;
    });
    sql = _rewriteArrays(sql);
    sql = _rewriteValuesAliases(sql);
    sql = _rewriteAny(sql);
    sql = _rewriteCasts(sql);
    sql = _rewriteIntervals(sql);
    sql = _rewriteMakeIntervals(sql);
    sql = sql.replaceAllMapped(
      RegExp(r"decode\(\s*'([0-9a-fA-F]*)'\s*,\s*'hex'\s*\)", caseSensitive: false),
      (m) => "X'${m[1]}'",
    );
    return sql;
  }

  /// `(VALUES …) AS v(a, b)`: SQLite cannot name a VALUES list's columns, so
  /// they are named in a SELECT around it (`column1`, `column2`, … are
  /// SQLite's own names for them).
  static String _rewriteValuesAliases(String sql) {
    final alias = RegExp(r'\)\s*AS\s+(\w+)\s*\(([\w\s,]+)\)', caseSensitive: false);
    var out = sql;
    var from = 0;
    while (true) {
      RegExpMatch? m;
      for (final candidate in alias.allMatches(out, from)) {
        if (!_insideLiteral(out, candidate.start)) {
          m = candidate;
          break;
        }
      }
      if (m == null) return out;
      final close = m.start;
      final open = _openingParen(out, close);
      final inner = out.substring(open + 1, close);
      if (!RegExp(r'^\s*VALUES\b', caseSensitive: false).hasMatch(inner)) {
        from = m.end;
        continue;
      }
      final columns = [for (final c in m[2]!.split(',')) c.trim()];
      final select = [
        for (var i = 0; i < columns.length; i++)
          'column${i + 1} AS ${columns[i]}',
      ].join(', ');
      final replacement = '(SELECT $select FROM ($inner)) AS ${m[1]}';
      out = out.substring(0, open) + replacement + out.substring(m.end);
      from = open + replacement.length;
    }
  }

  static int _openingParen(String sql, int close) {
    var depth = 0;
    var quoted = false;
    for (var i = close; i >= 0; i--) {
      final c = sql[i];
      if (c == "'") quoted = !quoted;
      if (quoted) continue;
      if (c == ')') depth++;
      if (c == '(') {
        depth--;
        if (depth == 0) return i;
      }
    }
    throw FormatException('Unbalanced parenthesis in: $sql');
  }

  /// `ARRAY[a, b]` → `json_array(a, b)`, brackets balanced.
  static String _rewriteArrays(String sql) {
    final pattern = RegExp(r'\bARRAY\s*\[', caseSensitive: false);
    var out = sql;
    while (true) {
      final m = _firstOutsideLiterals(out, pattern);
      if (m == null) return out;
      var depth = 0;
      var close = m.end - 1;
      var quoted = false;
      for (var i = m.end - 1; i < out.length; i++) {
        final c = out[i];
        if (c == "'") quoted = !quoted;
        if (quoted) continue;
        if (c == '[') depth++;
        if (c == ']') {
          depth--;
          if (depth == 0) {
            close = i;
            break;
          }
        }
      }
      out = '${out.substring(0, m.start)}json_array('
          '${out.substring(m.end, close)})${out.substring(close + 1)}';
    }
  }

  /// `operand ± make_interval(unit => n)` → SQLite date arithmetic, the
  /// amount bound at run time.
  static String _rewriteMakeIntervals(String sql) {
    final pattern = RegExp(
      r'\s*([+-])\s*make_interval\s*\(\s*(\w+)\s*=>\s*([^)]+?)\s*\)',
      caseSensitive: false,
    );
    var out = sql;
    while (true) {
      final m = _firstOutsideLiterals(out, pattern);
      if (m == null) return out;
      final start = _operandStart(out, m.start);
      final operand = out.substring(start, m.start).trim();
      out = "${out.substring(0, start)}strftime('%Y-%m-%dT%H:%M:%f000Z', "
          "$operand, '${m[1]}' || (${m[3]}) || ' ${m[2]}')"
          '${out.substring(m.end)}';
    }
  }

  /// `operand ± interval 'N unit'` → SQLite date arithmetic on the same
  /// ISO-8601 text every instant is stored as.
  static String _rewriteIntervals(String sql) {
    final pattern = RegExp(
      r"\s*([+-])\s*interval\s*'([^']+)'",
      caseSensitive: false,
    );
    var out = sql;
    while (true) {
      final m = _firstOutsideLiterals(out, pattern);
      if (m == null) return out;
      final start = _operandStart(out, m.start);
      final operand = out.substring(start, m.start).trim();
      final amount = m[2]!.trim();
      final modifier = '${m[1]}${amount.startsWith(RegExp(r'[+-]')) ? amount.substring(1) : amount}';
      out = "${out.substring(0, start)}strftime('%Y-%m-%dT%H:%M:%f000Z', "
          "$operand, '$modifier')${out.substring(m.end)}";
    }
  }

  /// A value as SQLite stores it: booleans as 0/1, instants as ISO-8601 UTC
  /// text (sorts in time order, reads back to the same instant), lists and
  /// maps as JSON text, bytes as a blob.
  static Object? encode(Object? value) => switch (value) {
    null => null,
    final bool flag => flag ? 1 : 0,
    final DateTime at => isoUtc(at),
    final Uint8List bytes => bytes,
    final int n => n,
    final double d => d,
    final String text => text,
    final BigInt big => big.toInt(),
    final Enum e => e.name,
    final List list => jsonEncode([for (final item in list) _jsonable(item)]),
    final Map map => jsonEncode(map.map((k, v) => MapEntry('$k', _jsonable(v)))),
    final Object other => other.toString(),
  };

  /// `2026-11-08T14:03:05.123456Z`: fixed width, so text order is time order.
  static String isoUtc(DateTime at) {
    final u = at.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final micros = (u.millisecond * 1000 + u.microsecond).toString().padLeft(
      6,
      '0',
    );
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
        'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${micros}Z';
  }

  static Object? _jsonable(Object? value) => switch (value) {
    final DateTime at => isoUtc(at),
    final Enum e => e.name,
    _ => value,
  };

  /// `@name` → `?N`, outside string literals. A name used twice binds once.
  static String _bindNames(String sql, List<String> order) =>
      _outsideLiterals(sql, (code) => code.replaceAllMapped(
            RegExp(r'(?<![@\w])@([A-Za-z_]\w*)'),
            (m) {
              final name = m[1]!;
              var index = order.indexOf(name);
              if (index < 0) {
                order.add(name);
                index = order.length - 1;
              }
              return '?${index + 1}';
            },
          ));

  /// `= ANY(x)` → `IN (SELECT value FROM json_each(x))`, with x balanced.
  static String _rewriteAny(String sql) {
    final pattern = RegExp(r'=\s*ANY\s*\(', caseSensitive: false);
    var out = sql;
    while (true) {
      final m = _firstOutsideLiterals(out, pattern);
      if (m == null) return out;
      final open = m.end - 1;
      final close = _matchingParen(out, open);
      final inner = out.substring(open + 1, close);
      out =
          '${out.substring(0, m.start)}IN (SELECT value FROM json_each($inner))'
          '${out.substring(close + 1)}';
    }
  }

  /// `operand::type`. `::date` becomes `date(operand)`; an empty array
  /// literal becomes an empty JSON array; every other cast is dropped.
  static String _rewriteCasts(String sql) {
    final cast = RegExp(r'::\s*([A-Za-z_]+(\s*\[\s*\])?)');
    var out = sql;
    while (true) {
      final m = _firstOutsideLiterals(out, cast);
      if (m == null) return out;
      final type = m[1]!.replaceAll(RegExp(r'\s'), '').toLowerCase();
      final start = _operandStart(out, m.start);
      final operand = out.substring(start, m.start);
      final String replacement;
      if (type == 'date') {
        replacement = 'date($operand)';
      } else if (type.endsWith('[]') && operand.trim() == "'{}'") {
        replacement = "'[]'";
      } else {
        replacement = operand;
      }
      out = out.substring(0, start) + replacement + out.substring(m.end);
    }
  }

  /// Where the operand ending at [end] begins: a parenthesised group, a quoted
  /// literal, or a run of identifier characters (`o.created_at`, `@at`, `1`).
  static int _operandStart(String sql, int end) {
    var i = end - 1;
    while (i >= 0 && sql[i] == ' ') {
      i--;
    }
    if (i < 0) return end;
    if (sql[i] == ')') {
      var depth = 0;
      for (; i >= 0; i--) {
        if (sql[i] == ')') depth++;
        if (sql[i] == '(') {
          depth--;
          if (depth == 0) break;
        }
      }
      // A function call's name belongs to the operand: `sum(x)::bigint`.
      var j = i - 1;
      while (j >= 0 && RegExp(r'[\w.]').hasMatch(sql[j])) {
        j--;
      }
      return j + 1;
    }
    if (sql[i] == "'") {
      i--;
      while (i >= 0 && sql[i] != "'") {
        i--;
      }
      return i;
    }
    while (i >= 0 && RegExp(r'[\w.@]').hasMatch(sql[i])) {
      i--;
    }
    return i + 1;
  }

  static int _matchingParen(String sql, int open) {
    var depth = 0;
    var quoted = false;
    for (var i = open; i < sql.length; i++) {
      final c = sql[i];
      if (c == "'") quoted = !quoted;
      if (quoted) continue;
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    throw FormatException('Unbalanced parenthesis in: $sql');
  }

  /// [rewrite] applied to the parts of [sql] outside single-quoted literals.
  static String _outsideLiterals(String sql, String Function(String) rewrite) {
    final out = StringBuffer();
    var i = 0;
    while (i < sql.length) {
      final quote = sql.indexOf("'", i);
      if (quote < 0) {
        out.write(rewrite(sql.substring(i)));
        break;
      }
      out.write(rewrite(sql.substring(i, quote)));
      var end = quote + 1;
      while (end < sql.length) {
        if (sql[end] == "'") {
          if (end + 1 < sql.length && sql[end + 1] == "'") {
            end += 2;
            continue;
          }
          break;
        }
        end++;
      }
      out.write(sql.substring(quote, end < sql.length ? end + 1 : end));
      i = end + 1;
    }
    return out.toString();
  }

  /// The first match of [pattern] not inside a single-quoted literal.
  static RegExpMatch? _firstOutsideLiterals(String sql, RegExp pattern) {
    for (final m in pattern.allMatches(sql)) {
      if (!_insideLiteral(sql, m.start)) return m;
    }
    return null;
  }

  static bool _insideLiteral(String sql, int at) {
    var quoted = false;
    for (var i = 0; i < at; i++) {
      if (sql[i] == "'") quoted = !quoted;
    }
    return quoted;
  }
}
