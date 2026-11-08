import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/config/pos_db_secret_store.dart';
import 'package:shared_module/data/config/secret_store.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/sql/embedded_datastore.dart';
import 'package:shared_module/data/sql/sql.dart';
import 'package:shared_module/data/sqlite/sqlite_database.dart';

/// A cloud till's data: one encrypted SQLite file in the app's support folder
/// (pos-cloud-single-till-sqlite, owner decisions 2026-11-08).
///
/// No PostgreSQL, no installer step, no database password: the file is made
/// by the setup wizard's connecting step, keyed with 32 random bytes kept in
/// the OS secret store (Keychain on macOS, DPAPI on Windows), and every
/// repository reads and writes it through the same SQL the offline app runs
/// on PostgreSQL.

/// The file's name inside the app's support folder.
const cloudDataFileName = 'xorder_pos_cloud.db';

/// Where the key for this till's data file is kept.
final cloudDataKeyStoreProvider = Provider<PosDbSecretStore>(
  (ref) => KeyedSecretStore(ref.watch(secretStoreProvider), 'pos_cloud_data_key'),
);

/// The data file, as the till's database.
final cloudDatabaseProvider = Provider<SqliteDatabase>((ref) {
  final keys = ref.watch(cloudDataKeyStoreProvider);
  final database = SqliteDatabase(
    locate: () async =>
        '${(await getApplicationSupportDirectory()).path}'
        '${Platform.pathSeparator}$cloudDataFileName',
    key: keys.read,
  );
  ref.onDispose(database.close);
  return database;
});

/// Makes the file ready at setup: a key on first run, then the schema.
class CloudDatastore implements EmbeddedDatastore {
  CloudDatastore({required this.database, required this.keys});

  final SqlDatabase database;
  final PosDbSecretStore keys;

  @override
  Future<EmbeddedDatastoreReport> prepare(DeploymentConfig config) async {
    var created = false;
    if (await keys.read() == null) {
      await keys.write(newSqliteKey());
      created = true;
    }
    final ran = await PosMigrator(database).migrate(config);
    return EmbeddedDatastoreReport(
      created: created || ran.isNotEmpty && ran.first == 1,
      migrations: ran.length,
    );
  }
}

/// A copy for the day-close backup: the whole file, encrypted with the same
/// key, reopened to prove it reads, and its tables listed for verification.
Future<Set<String>> Function(File) cloudSnapshot(
  SqliteDatabase database,
  PosDbSecretStore keys,
) => (target) async {
  await database.copyTo(target.path);
  final copy = SqliteDatabase(path: target.path, key: keys.read);
  try {
    final rows = await copy.query(
      const DeploymentConfig(mode: DeploymentMode.cloud),
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return {for (final row in rows) row[0]! as String};
  } finally {
    await copy.close();
  }
};

/// The till's own defaults (reasons, order types), written into the file the
/// till already has open — not over a second, administrator connection, which
/// is a PostgreSQL idea a file does not have.
Future<void> Function(DeploymentConfig, String, int) cloudDefaultsSeeder(
  SqlDatabase database,
) => (config, _, businessId) async {
  final bootstrap = LocalBootstrap(database);
  await bootstrap.seedReasonCodes(config, businessId);
  await bootstrap.seedOrderTypes(config, businessId);
};
