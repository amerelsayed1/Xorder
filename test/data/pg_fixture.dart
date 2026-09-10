import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

/// Shared setup for the suites that need a real PostgreSQL.
///
/// **Each suite gets its own database.** `flutter test` runs suites in parallel,
/// and two of them truncating one database produced exactly the failure you
/// would fear most here — a duplicate invoice number — from a test artefact
/// rather than a real race. A flaky money test is worse than no test, because
/// people learn to ignore it.
///
/// **And each checkout gets its own set**, which is the same lesson one level
/// out. Naming by suite alone was enough while there was one working copy; the
/// moment two git worktrees ran `test/data` against the same server they shared
/// `xorder_pos_permission_grants`, and each suite's `DELETE FROM pos_restaurants`
/// wiped the other's rows mid-test. It surfaced as a foreign key violation on a
/// restaurant that had existed a millisecond earlier — a failure that reads
/// exactly like a real bug and is not one, which is the worst kind to leave
/// lying around.
///
/// The discriminator is derived from the checkout path rather than passed in, so
/// nothing has to be coordinated between concurrent agents or remembered by a
/// person.
class PgFixture {
  PgFixture._(this.database, this.config);

  final PosDatabase database;
  final DeploymentConfig config;

  static String? get host => Platform.environment['POS_PG_HOST'];
  static int get port => int.tryParse(Platform.environment['POS_PG_PORT'] ?? '5432') ?? 5432;
  static String get password => Platform.environment['POS_PG_PASSWORD'] ?? 'postgres';
  static String get user => Platform.environment['POS_PG_USER'] ?? 'pos_till';

  /// Create (once) and open a database named for the calling suite.
  static Future<PgFixture> open(String suite) async {
    final address = host;
    if (address == null) throw StateError('POS_PG_HOST is not set');

    final databaseName = nameFor(suite);
    await _ensureDatabase(address, databaseName);

    return PgFixture._(
      PosDatabase(credentials: InMemoryPosDbCredentials(password)),
      DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: address,
        // The throwaway container has no certificate. Only a private host may
        // ever skip verification, and 127.0.0.1 qualifies.
        verifyTls: false,
        databaseName: databaseName,
        databaseUser: user,
        databasePort: port,
      ),
    );
  }

  /// The database [open] uses for [suite] in this checkout.
  static String nameFor(String suite) => 'xorder_pos_${suite}_$_checkout';

  /// Run [statements] against the maintenance database, one by one, outside
  /// any transaction — for what `CREATE` and `DROP DATABASE` need.
  static Future<void> maintenance(List<String> statements) async {
    final address = host;
    if (address == null) throw StateError('POS_PG_HOST is not set');
    final admin = await Connection.open(
      Endpoint(
        host: address,
        port: port,
        database: 'postgres',
        username: user,
        password: password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    try {
      for (final statement in statements) {
        await admin.execute(statement);
      }
    } finally {
      await admin.close();
    }
  }

  /// A short, stable tag for this working copy.
  ///
  /// Hashed rather than derived from the folder name: a worktree path can be
  /// long, can contain characters a database name may not, and two worktrees can
  /// share a leaf name. Eight hex digits of the absolute path collide only if
  /// somebody is running more than a few million checkouts at once.
  static final String _checkout = _tag(Directory.current.path);

  static String _tag(String path) {
    // FNV-1a, inline: this needs to be stable across runs and processes, and
    // `Object.hashCode` is neither.
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// `CREATE DATABASE` has no `IF NOT EXISTS`, so check first. It also cannot
  /// run inside a transaction, hence a bare connection rather than `runTx`.
  static Future<void> _ensureDatabase(String address, String name) async {
    final admin = await Connection.open(
      Endpoint(
        host: address,
        port: port,
        database: 'postgres',
        username: user,
        password: password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    try {
      final existing = await admin.execute(
        Sql.named('SELECT 1 FROM pg_database WHERE datname = @name'),
        parameters: {'name': name},
      );
      // Identifier, not a value, so it cannot be a bind parameter. Safe because
      // `name` is built from a compile-time suite constant, never from input.
      if (existing.isEmpty) await admin.execute('CREATE DATABASE "$name"');
    } finally {
      await admin.close();
    }
  }

  /// Empty ledger, same schema. Run between tests.
  Future<void> truncate() => database.runTx(
        config,
        (tx) => tx.execute('TRUNCATE pos_orders, pos_invoice_sequences RESTART IDENTITY CASCADE'),
      );

  Future<void> close() => database.close();
}
