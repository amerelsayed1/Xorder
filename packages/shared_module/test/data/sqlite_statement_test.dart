import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/sqlite/sqlite_statement.dart';

/// The PostgreSQL the repositories are written in, turned into SQLite on the
/// way in (pos-cloud-single-till-sqlite, stage 3). One rule per test, in the
/// shapes the repositories actually use.
void main() {
  String t(String sql) => SqliteStatement.translate(sql);

  group('casts', () {
    test('a typed cast is dropped', () {
      expect(t('SELECT count(*)::bigint FROM x'), 'SELECT count(*) FROM x');
      expect(t('WHERE s.terminal_id::text = @t'), 'WHERE s.terminal_id = @t');
      expect(
        t('SELECT coalesce(sum(p.amount_minor), 0)::bigint AS minor'),
        'SELECT coalesce(sum(p.amount_minor), 0) AS minor',
      );
      expect(t('VALUES (@before::jsonb)'), 'VALUES (@before)');
    });

    test('a date cast becomes date()', () {
      expect(t('WHERE o.occurred_at::date = @d'), 'WHERE date(o.occurred_at) = @d');
      expect(t('WHERE (@at)::date >= x'), 'WHERE date((@at)) >= x');
    });

    test('an empty array literal becomes an empty JSON array', () {
      expect(
        t("coalesce(ro.capabilities, '{}'::text[])"),
        "coalesce(ro.capabilities, '[]')",
      );
    });

    test('a cast inside a string literal is text, not a cast', () {
      expect(t("SELECT 'a::date'"), "SELECT 'a::date'");
    });
  });

  group('ANY', () {
    test('a list parameter becomes json_each', () {
      expect(
        t('WHERE o.status = ANY(@statuses)'),
        'WHERE o.status IN (SELECT value FROM json_each(@statuses))',
      );
      expect(
        t('AND NOT (id = ANY(@keep))'),
        'AND NOT (id IN (SELECT value FROM json_each(@keep)))',
      );
    });

    test('an array column does too', () {
      expect(
        t('WHERE @cap = ANY(capabilities)'),
        'WHERE @cap IN (SELECT value FROM json_each(capabilities))',
      );
    });
  });

  group('the rest', () {
    test('row locks are dropped: the transaction holds the write lock', () {
      expect(t('SELECT 1 FROM x WHERE id = 1 FOR UPDATE'), 'SELECT 1 FROM x WHERE id = 1');
      expect(t('SELECT 1 FROM x s FOR UPDATE OF s'), 'SELECT 1 FROM x s');
      expect(t('SELECT 1 FROM r WHERE id = 1 FOR NO KEY UPDATE'), 'SELECT 1 FROM r WHERE id = 1');
      expect(t('SELECT 1 FROM g FOR SHARE'), 'SELECT 1 FROM g');
    });

    test('functions and operators with a SQLite spelling', () {
      expect(t('name ILIKE @q'), 'name LIKE @q');
      expect(t('array_agg(x ORDER BY y)'), 'json_group_array(x ORDER BY y)');
      expect(t('bool_or(x)'), 'max(x)');
      expect(t('GREATEST(a, b)'), 'max(a, b)');
      expect(t('LEAST(a, b)'), 'min(a, b)');
      expect(t('a IS DISTINCT FROM b'), 'a IS NOT b');
      expect(t('a IS NOT DISTINCT FROM b'), 'a IS b');
    });

    test('array literals become JSON arrays', () {
      expect(
        t("VALUES (ARRAY['dine_in','takeaway'])"),
        "VALUES (json_array('dine_in','takeaway'))",
      );
    });

    test('a VALUES list with named columns is named in a SELECT', () {
      expect(
        t("SELECT v.a FROM (VALUES ('x', 1), ('y', 2)) AS v(a, n)"),
        "SELECT v.a FROM (SELECT column1 AS a, column2 AS n FROM "
        "(VALUES ('x', 1), ('y', 2))) AS v",
      );
      // A function call followed by AS is not a VALUES list.
      expect(t('SELECT count(x) AS n FROM t'), 'SELECT count(x) AS n FROM t');
    });

    test('interval arithmetic becomes date arithmetic', () {
      expect(
        t("WHERE at > now() - interval '1 hour'"),
        "WHERE at > strftime('%Y-%m-%dT%H:%M:%f000Z', now(), '-1 hour')",
      );
      expect(
        t("VALUES (@at + interval '40 days')"),
        "VALUES (strftime('%Y-%m-%dT%H:%M:%f000Z', @at, '+40 days'))",
      );
    });

    test('make_interval and hex bytes', () {
      expect(
        t('VALUES (now() - make_interval(hours => @h))'),
        "VALUES (strftime('%Y-%m-%dT%H:%M:%f000Z', now(), '-' || (@h) || ' hours'))",
      );
      expect(t("VALUES (decode('1b40', 'hex'))"), "VALUES (X'1b40')");
    });

    test('portable SQL passes through untouched', () {
      const sql =
          'INSERT INTO t (a) VALUES (@a) ON CONFLICT (a) DO UPDATE SET '
          'b = EXCLUDED.b RETURNING id';
      expect(t(sql), sql);
    });
  });

  group('parameters', () {
    test('named parameters bind positionally, once per name', () {
      final s = SqliteStatement.from(
        'SELECT * FROM t WHERE a = @a AND b = @b OR a2 = @a',
        {'a': 1, 'b': 'x'},
      );
      expect(s.sql, 'SELECT * FROM t WHERE a = ?1 AND b = ?2 OR a2 = ?1');
      expect(s.values, [1, 'x']);
    });

    test('an @ inside a literal is not a parameter', () {
      final s = SqliteStatement.from("SELECT 'a@b.com', @x", {'x': 2});
      expect(s.sql, "SELECT 'a@b.com', ?1");
    });

    test('a missing value is refused, not bound as null', () {
      expect(() => SqliteStatement.from('SELECT @x', {}), throwsArgumentError);
    });

    test('values are stored the way SQLite keeps them', () {
      final s = SqliteStatement.from('SELECT @a, @b, @c, @d, @e', {
        'a': true,
        'b': DateTime.utc(2026, 11, 8, 14, 3, 5, 123, 456),
        'c': [1, 2],
        'd': {'k': 'v'},
        'e': Uint8List.fromList([1, 2]),
      });
      expect(s.values[0], 1);
      expect(s.values[1], '2026-11-08T14:03:05.123456Z');
      expect(s.values[2], '[1,2]');
      expect(s.values[3], '{"k":"v"}');
      expect(s.values[4], isA<Uint8List>());
    });

    test('instants sort as text in time order', () {
      final earlier = SqliteStatement.isoUtc(DateTime.utc(2026, 1, 9, 23));
      final later = SqliteStatement.isoUtc(DateTime.utc(2026, 1, 10, 1));
      expect(earlier.compareTo(later), lessThan(0));
    });
  });
}
