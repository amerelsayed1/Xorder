import 'dart:collection';

import '../../core/config/deployment.dart';
import '../postgres/pos_database.dart' show PosDbFailure;

/// The SQL the till's repositories speak, owned here rather than borrowed from
/// a driver (pos-cloud-single-till-sqlite).
///
/// The repositories were written against `package:postgres` and used a small
/// part of it: a named statement, a transaction session that executes one, and
/// the rows that come back. Those four shapes are named here, with the same
/// spellings, so a repository moves onto this seam by changing its import —
/// and the engine behind it can be PostgreSQL (the offline app, and every till
/// until now) or SQLite (the cloud app), with one set of repositories for both.
///
/// What is NOT here is anything only one engine has: connection pools, TLS,
/// roles, `pg_dump`. Those stay with their engine.

/// A statement with `@name` parameters.
///
/// `Sql.named('… @id …')` is the call every repository already makes; both
/// engines bind `@name` parameters from a map.
class Sql {
  const Sql.named(this.text);

  final String text;

  @override
  String toString() => text;
}

/// One row: its columns by position, as the repositories already read them
/// (`row[0] as int`).
class ResultRow extends UnmodifiableListView<Object?> {
  ResultRow(super.values);
}

/// The rows a statement returned, and how many rows it changed.
class Result extends UnmodifiableListView<ResultRow> {
  Result(super.rows, {required this.affectedRows});

  /// Rows inserted, updated or deleted. Zero for a read.
  final int affectedRows;
}

/// A transaction in progress. Everything executed through it commits together
/// or not at all.
abstract interface class TxSession {
  /// Run [query] — a [Sql], or plain text with no parameters — inside this
  /// transaction.
  Future<Result> execute(Object query, {Object? parameters});

  /// End this transaction undone, whatever the callback then returns — for a
  /// refusal found halfway through a write that already wrote something.
  Future<void> rollback();
}

/// Where a till keeps its data.
///
/// Every write goes through [runTx]: a till that half-writes an order is worse
/// than one that refuses it, so there is no non-transactional write path.
/// Failures leave as `PosDbException`, whichever engine raised them.
abstract interface class SqlDatabase {
  /// Run [action] in a transaction for [config]'s database.
  Future<T> runTx<T>(
    DeploymentConfig config,
    Future<T> Function(TxSession) action,
  );

  /// One read, outside any transaction.
  Future<Result> query(
    DeploymentConfig config,
    String sql, {
    Object? parameters,
  });

  /// Null when the database answers; otherwise which way it failed.
  Future<PosDbFailure?> probe(DeploymentConfig config);

  /// Let go of whatever the engine holds open.
  Future<void> close();
}
