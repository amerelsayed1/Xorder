import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/sql/row_reads.dart';
import 'package:shared_module/data/sql/sql.dart';
import 'package:shared_module/data/sqlite/sqlite_database.dart';

/// The cloud till's datastore: an encrypted SQLite file
/// (pos-cloud-single-till-sqlite, stage 3). No server; each test gets a file.
void main() {
  const config = DeploymentConfig(mode: DeploymentMode.cloud);
  late Directory dir;
  late String path;
  final key = newSqliteKey();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pos_sqlite_');
    path = '${dir.path}/till.db';
  });
  tearDown(() => dir.delete(recursive: true));

  SqliteDatabase open({String? withKey}) =>
      SqliteDatabase(path: path, key: () async => withKey ?? key);

  Future<SqliteDatabase> withTable() async {
    final db = open();
    await db.executeScript(
      'CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'name TEXT NOT NULL UNIQUE, at TEXT, flag INTEGER)',
    );
    return db;
  }

  test('a committed write survives closing and reopening the file', () async {
    final db = await withTable();
    await db.runTx(config, (tx) async {
      await tx.execute(
        Sql.named('INSERT INTO t (name, at, flag) VALUES (@n, @at, @f)'),
        parameters: {
          'n': 'Koshary',
          'at': DateTime.utc(2026, 11, 8, 12),
          'f': true,
        },
      );
    });
    await db.close();

    final again = open();
    final rows = await again.query(config, 'SELECT name, at, flag FROM t');
    expect(rows.single[0], 'Koshary');
    expect(rows.single.dateTime(1), DateTime.utc(2026, 11, 8, 12));
    expect(rows.single.boolean(2), isTrue);
    await again.close();
  });

  test('the file is encrypted: another key cannot read it', () async {
    final db = await withTable();
    await db.close();

    final wrong = open(withKey: newSqliteKey());
    await expectLater(
      wrong.query(config, 'SELECT count(*) FROM t'),
      throwsA(
        isA<PosDbException>().having((e) => e.failure, 'failure', PosDbFailure.auth),
      ),
    );
    // And the bytes on disk are not a plain SQLite file.
    final header = (await File(path).openRead(0, 16).first);
    expect(String.fromCharCodes(header.take(15)), isNot('SQLite format 3'));
  });

  test('no key, no file: a till never writes unencrypted data', () async {
    final db = SqliteDatabase(path: path, key: () async => null);
    await expectLater(
      db.query(config, 'SELECT 1'),
      throwsA(isA<PosDbException>()),
    );
    expect(File(path).existsSync(), isFalse);
  });

  test('a failure inside a transaction leaves nothing behind', () async {
    final db = await withTable();
    await expectLater(
      db.runTx(config, (tx) async {
        await tx.execute(
          Sql.named('INSERT INTO t (name) VALUES (@n)'),
          parameters: {'n': 'half a sale'},
        );
        throw StateError('the printer caught fire');
      }),
      throwsA(isA<PosDbException>()),
    );
    expect((await db.query(config, 'SELECT count(*) FROM t')).single[0], 0);
    await db.close();
  });

  test('rollback() undoes the transaction and still returns', () async {
    final db = await withTable();
    final result = await db.runTx(config, (tx) async {
      await tx.execute(
        Sql.named('INSERT INTO t (name) VALUES (@n)'),
        parameters: {'n': 'refused line'},
      );
      await tx.rollback();
      return 'refused';
    });
    expect(result, 'refused');
    expect((await db.query(config, 'SELECT count(*) FROM t')).single[0], 0);
    await db.close();
  });

  test('a duplicate reads as SQLSTATE 23505, as on PostgreSQL', () async {
    final db = await withTable();
    Future<void> insert() => db.runTx(config, (tx) async {
      await tx.execute(
        Sql.named('INSERT INTO t (name) VALUES (@n)'),
        parameters: {'n': 'same'},
      );
    });
    await insert();
    await expectLater(
      insert(),
      throwsA(
        isA<PosDbException>().having((e) => e.sqlState, 'sqlState', '23505'),
      ),
    );
    await db.close();
  });

  test('RETURNING and affected rows behave as on PostgreSQL', () async {
    final db = await withTable();
    final inserted = await db.runTx(
      config,
      (tx) => tx.execute(
        Sql.named('INSERT INTO t (name) VALUES (@n) RETURNING id'),
        parameters: {'n': 'a'},
      ),
    );
    expect(inserted.single[0], isA<int>());
    final updated = await db.runTx(
      config,
      (tx) => tx.execute(Sql.named("UPDATE t SET name = 'b'")),
    );
    expect(updated.affectedRows, 1);
    await db.close();
  });

  test('now() and gen_random_uuid() exist, by those names', () async {
    final db = open();
    final row = (await db.query(
      config,
      'SELECT now(), gen_random_uuid()',
    )).single;
    expect(
      DateTime.parse(row[0]! as String).difference(DateTime.now()).abs(),
      lessThan(const Duration(minutes: 1)),
    );
    expect(
      row[1],
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$')),
    );
    await db.close();
  });

  test('a read from inside a transaction joins it rather than waiting', () async {
    final db = await withTable();
    final seen = await db.runTx(config, (tx) async {
      await tx.execute(
        Sql.named('INSERT INTO t (name) VALUES (@n)'),
        parameters: {'n': 'inside'},
      );
      return (await db.query(config, 'SELECT count(*) FROM t')).single[0];
    });
    expect(seen, 1);
    await db.close();
  });

  test('a list parameter works through ANY', () async {
    final db = await withTable();
    for (final name in ['a', 'b', 'c']) {
      await db.runTx(config, (tx) async {
        await tx.execute(
          Sql.named('INSERT INTO t (name) VALUES (@n)'),
          parameters: {'n': name},
        );
      });
    }
    final rows = await db.query(
      config,
      'SELECT name FROM t WHERE name = ANY(@names) ORDER BY name',
      parameters: {
        'names': ['a', 'c'],
      },
    );
    expect([for (final r in rows) r[0]], ['a', 'c']);
    await db.close();
  });

  test('a copy for backup opens with the same key and holds the data', () async {
    final db = await withTable();
    await db.runTx(config, (tx) async {
      await tx.execute(
        Sql.named('INSERT INTO t (name) VALUES (@n)'),
        parameters: {'n': 'kept'},
      );
    });
    final copy = '${dir.path}/backup.db';
    await db.copyTo(copy);
    await db.close();

    final restored = SqliteDatabase(path: copy, key: () async => key);
    expect((await restored.query(config, 'SELECT name FROM t')).single[0], 'kept');
    await restored.close();
  });
}
