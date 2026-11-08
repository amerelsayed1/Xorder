import '../../core/config/deployment.dart';
import '../postgres/migrations.dart' show PosMigration;
import '../sql/sql.dart';
import 'sqlite_schema.dart';
import 'sqlite_triggers.dart';

/// PostgreSQL migrations after [sqliteSchemaMatchesMigration], as SQLite
/// statements, keyed by the PostgreSQL version they mirror.
///
/// **Every PostgreSQL migration after the baseline needs an entry here**, even
/// an empty one for a migration that touches nothing a cloud till keeps
/// (`sqlite_schema_test.dart` fails until it has one). That is how the two
/// schemas are kept in step (pos-cloud-single-till-sqlite, FEATURE §10).
const sqliteUpgrades = <int, List<String>>{};

/// Brings a cloud till's SQLite file up to the current schema.
///
/// A new file gets [sqliteSchema] and [sqliteTriggers] in one transaction, and
/// is recorded as having every PostgreSQL migration up to the one that schema
/// matches — so code that asks "has migration N run?" gets the same answer on
/// either engine. After that, each [sqliteUpgrades] entry runs once.
class SqliteMigrator {
  const SqliteMigrator(this._db, {required this.migrations});

  final SqlDatabase _db;
  final List<PosMigration> migrations;

  /// Returns the PostgreSQL versions recorded by *this* call.
  Future<List<int>> migrate(DeploymentConfig config) =>
      _db.runTx(config, (tx) async {
        await tx.execute(
          'CREATE TABLE IF NOT EXISTS schema_migrations ('
          ' version INTEGER PRIMARY KEY,'
          " applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%f000Z', 'now')))",
        );
        final existing = await tx.execute('SELECT version FROM schema_migrations');
        final applied = {for (final row in existing) row[0]! as int};

        final ran = <int>[];
        Future<void> record(int version) async {
          await tx.execute(
            Sql.named('INSERT INTO schema_migrations (version) VALUES (@v)'),
            parameters: {'v': version},
          );
          ran.add(version);
        }

        if (applied.isEmpty) {
          for (final statement in [...sqliteSchema, ...sqliteTriggers]) {
            await tx.execute(statement);
          }
          for (final m in migrations) {
            if (m.version <= sqliteSchemaMatchesMigration) await record(m.version);
          }
        }
        for (final m in migrations) {
          if (m.version <= sqliteSchemaMatchesMigration) continue;
          if (applied.contains(m.version) || ran.contains(m.version)) continue;
          final upgrade = sqliteUpgrades[m.version];
          if (upgrade == null) {
            throw StateError(
              'PostgreSQL migration ${m.version} has no SQLite counterpart in '
              'sqliteUpgrades — a cloud till cannot be brought up to it.',
            );
          }
          for (final statement in upgrade) {
            await tx.execute(statement);
          }
          await record(m.version);
        }
        return ran;
      });
}
