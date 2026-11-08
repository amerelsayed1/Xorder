import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart' as sq;

import '../../core/config/deployment.dart';
import '../postgres/pos_database.dart' show PosDbException, PosDbFailure;
import '../sql/sql.dart';
import 'sqlite_statement.dart';

/// A cloud till's data: one encrypted SQLite file (pos-cloud-single-till-sqlite).
///
/// **One connection, one writer.** A till is one machine with one app on it, so
/// every statement goes through one connection, one at a time: a transaction is
/// `BEGIN IMMEDIATE` (it takes the file's write lock up front, which is what
/// PostgreSQL's `FOR UPDATE` gave each row) and nothing else runs until it
/// commits or rolls back. A read issued from inside a transaction's callback
/// runs inside that transaction instead of waiting for it.
///
/// **Encrypted.** SQLite3MultipleCiphers in SQLCipher-compatible mode, keyed
/// with 32 random bytes the till keeps in its secret store ([key]). A file
/// copied off the machine is unreadable without that store.
///
/// **Durable.** Write-ahead log, `synchronous = FULL`: a sale the cashier was
/// told is saved has reached the disk (BR-7).
class SqliteDatabase implements SqlDatabase {
  SqliteDatabase({required this.path, required this.key});

  /// The file. Created on first open.
  final String path;

  /// The file's key: 32 bytes, as 64 hex characters. Null refuses to open,
  /// so a till never writes an unencrypted file.
  final Future<String?> Function() key;

  sq.Database? _db;

  /// The tail of the queue every statement waits in.
  Future<void> _tail = Future.value();

  static final _inTransaction = Object();

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  /// The open file, opening (and keying) it the first time.
  Future<sq.Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final hex = await key();
    if (hex == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw PosDbException(
        PosDbFailure.auth,
        'No key for this till\'s data file.',
      );
    }
    try {
      await File(path).parent.create(recursive: true);
      final db = sq.sqlite3.open(path);
      try {
        db.execute("PRAGMA cipher = 'sqlcipher'");
        db.execute('PRAGMA legacy = 4');
        db.execute("PRAGMA key = \"x'$hex'\"");
        // The first read is what proves the key: a wrong one fails here, as
        // "file is not a database", not on the first sale.
        db.select('SELECT count(*) FROM sqlite_master');
        db.execute('PRAGMA journal_mode = WAL');
        db.execute('PRAGMA synchronous = FULL');
        db.execute('PRAGMA foreign_keys = ON');
        db.execute('PRAGMA busy_timeout = 5000');
        _registerFunctions(db);
      } on Object {
        db.close();
        rethrow;
      }
      return _db = db;
    } on PosDbException {
      rethrow;
    } on Object catch (error) {
      throw _translate(error);
    }
  }

  /// `now()` and `gen_random_uuid()`, by the names the repositories call.
  static void _registerFunctions(sq.Database db) {
    db.createFunction(
      functionName: 'now',
      argumentCount: const sq.AllowedArgumentCount(0),
      deterministic: false,
      directOnly: false,
      function: (_) => SqliteStatement.isoUtc(DateTime.now()),
    );
    db.createFunction(
      functionName: 'gen_random_uuid',
      argumentCount: const sq.AllowedArgumentCount(0),
      deterministic: false,
      directOnly: false,
      function: (_) => uuidV4(),
    );
  }

  /// Run [work] alone: after everything queued before it, before anything
  /// queued after.
  Future<T> _serialised<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<T> runTx<T>(
    DeploymentConfig config,
    Future<T> Function(TxSession) action,
  ) async {
    // Already inside a transaction (a repository calling another from its
    // callback): join it rather than queue behind it for ever.
    if (Zone.current[_inTransaction] case final _SqliteTx tx) {
      return action(tx);
    }
    return _serialised(() async {
      final db = await _open();
      final tx = _SqliteTx(db);
      try {
        db.execute('BEGIN IMMEDIATE');
      } on Object catch (error) {
        throw _translate(error);
      }
      try {
        final result = await runZoned(
          () => action(tx),
          zoneValues: {_inTransaction: tx},
        );
        db.execute(tx.rolledBack ? 'ROLLBACK' : 'COMMIT');
        return result;
      } on Object catch (error) {
        if (db.autocommit == false) db.execute('ROLLBACK');
        if (error is PosDbException) rethrow;
        throw _translate(error);
      }
    });
  }

  @override
  Future<Result> query(
    DeploymentConfig config,
    String sql, {
    Object? parameters,
  }) async {
    if (Zone.current[_inTransaction] case final _SqliteTx tx) {
      return tx.execute(Sql.named(sql), parameters: parameters);
    }
    return _serialised(() async {
      final db = await _open();
      try {
        return _run(db, sql, parameters);
      } on Object catch (error) {
        throw _translate(error);
      }
    });
  }

  @override
  Future<PosDbFailure?> probe(DeploymentConfig config) async {
    try {
      await query(config, 'SELECT 1');
      return null;
    } on PosDbException catch (error) {
      return error.failure;
    }
  }

  @override
  Future<void> close() async {
    await _serialised(() async {
      _db?.close();
      _db = null;
    });
  }

  /// A consistent copy of the whole file at [target], encrypted with the same
  /// key — the day-close backup (`VACUUM INTO`).
  Future<void> copyTo(String target) => _serialised(() async {
    final db = await _open();
    try {
      final escaped = target.replaceAll("'", "''");
      db.execute("VACUUM INTO '$escaped'");
    } on Object catch (error) {
      throw _translate(error);
    }
  });

  /// Run one statement — schema text with several statements, which takes no
  /// parameters, runs as it is.
  Future<void> executeScript(String script) => _serialised(() async {
    final db = await _open();
    try {
      db.execute(script);
    } on Object catch (error) {
      throw _translate(error);
    }
  });
}

class _SqliteTx implements TxSession {
  _SqliteTx(this._db);

  final sq.Database _db;
  bool rolledBack = false;

  @override
  Future<Result> execute(Object query, {Object? parameters}) async {
    final text = query is Sql ? query.text : query.toString();
    try {
      return _run(_db, text, parameters);
    } on Object catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> rollback() async => rolledBack = true;
}

final _changes = RegExp(
  r'^\s*(WITH\b.*?\)\s*)?(INSERT|UPDATE|DELETE|REPLACE)\b',
  caseSensitive: false,
  dotAll: true,
);

final _truncate = RegExp(
  r'^\s*TRUNCATE\s+(?:TABLE\s+)?(.+?)(\s+RESTART\s+IDENTITY)?(\s+CASCADE)?\s*;?\s*$',
  caseSensitive: false,
  dotAll: true,
);

/// PostgreSQL's `TRUNCATE a, b [RESTART IDENTITY] [CASCADE]`, which SQLite
/// does not have: the tables are emptied — with CASCADE, every table that
/// refers to them however indirectly first — and with RESTART IDENTITY their
/// ids start again from 1. Row triggers fire, so an append-only table still
/// refuses, as PostgreSQL's TRUNCATE triggers make it refuse.
Result _runTruncate(sq.Database db, RegExpMatch m) {
  final named = [
    for (final t in m[1]!.split(',')) t.trim().replaceAll('"', ''),
  ];
  final order = <String>[];
  if (m[3] != null) {
    final refersTo = <String, Set<String>>{};
    for (final row in db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )) {
      final table = row.values.first! as String;
      for (final fk in db.select(
        'SELECT "table" FROM pragma_foreign_key_list(?)',
        [table],
      )) {
        refersTo.putIfAbsent(fk.values.first! as String, () => {}).add(table);
      }
    }
    void visit(String table) {
      if (order.contains(table)) return;
      for (final child in refersTo[table] ?? const <String>{}) {
        if (child != table) visit(child);
      }
      order.add(table);
    }

    named.forEach(visit);
  } else {
    order.addAll(named);
  }
  for (final table in order) {
    db.execute('DELETE FROM "$table"');
    if (m[2] != null) {
      db.execute('DELETE FROM sqlite_sequence WHERE name = ?', [table]);
    }
  }
  return Result(const [], affectedRows: 0);
}

Result _run(sq.Database db, String text, Object? parameters) {
  if (_truncate.firstMatch(text) case final m?) return _runTruncate(db, m);
  final statement = SqliteStatement.from(text, parameters);
  final prepared = db.prepare(statement.sql);
  try {
    final rows = prepared.select(statement.values);
    return Result([
      for (final row in rows) ResultRow(List<Object?>.of(row.values)),
    ], affectedRows: _changes.hasMatch(text) ? db.updatedRows : 0);
  } finally {
    prepared.close();
  }
}

/// A SQLite failure as the till's own: the same [PosDbFailure] kinds, and the
/// SQLSTATE PostgreSQL would have sent for the constraint kinds a repository
/// asks about (`23505` duplicate, `23503` reference, `23514` check, `23502`
/// missing value, `42703` no such column, `42P01` no such table).
PosDbException _translate(Object error) {
  if (error is PosDbException) return error;
  if (error is sq.SqliteException) {
    final message = error.message.toLowerCase();
    final sqlState = switch (error.extendedResultCode) {
      2067 || 1555 => '23505', // UNIQUE, PRIMARY KEY
      787 => '23503', // FOREIGN KEY
      275 => '23514', // CHECK
      1299 => '23502', // NOT NULL
      _ when message.contains('no such column') => '42703',
      _ when message.contains('no such table') => '42P01',
      // A trigger's RAISE(ABORT, …): the repositories' own refusals, which
      // PostgreSQL raised as P0001 with the same message.
      _ when error.resultCode == 19 => 'P0001',
      _ => null,
    };
    final failure = switch (error.resultCode) {
      26 => PosDbFailure.auth, // NOTADB: wrong key, or not our file
      14 => PosDbFailure.missingDatabase, // CANTOPEN
      _ => PosDbFailure.query,
    };
    return PosDbException(failure, error, sqlState: sqlState);
  }
  return PosDbException(PosDbFailure.classify(error), error);
}

/// A random (version 4) UUID, as PostgreSQL's `gen_random_uuid()` writes one.
String uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

/// A new key for a new till's file: 32 random bytes as 64 hex characters.
String newSqliteKey() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 32; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
