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

    final databaseName = 'xorder_pos_$suite';
    await _ensureDatabase(address, databaseName);

    return PgFixture._(
      PosDatabase(credentials: InMemoryPosDbCredentials(password)),
      DeploymentConfig(
        mode: DeploymentMode.branchServer,
        baseUrl: 'http://$address:8100',
        upstreamUrl: 'https://xorder.io',
        // The throwaway container has no certificate. Only a private host may
        // ever skip verification, and 127.0.0.1 qualifies.
        verifyTls: false,
        databaseName: databaseName,
        databaseUser: user,
        databasePort: port,
      ),
    );
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
