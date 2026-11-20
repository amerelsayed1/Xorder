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
const sqliteUpgrades = <int, List<String>>{
  // Waiter handhelds paired with this till (waiter-app, WA1).
  65: [
    '''CREATE TABLE IF NOT EXISTS "pos_waiter_devices" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "business_id" INTEGER NOT NULL,
  "branch_id" INTEGER,
  "name" TEXT NOT NULL,
  "token_hash" TEXT NOT NULL,
  "paired_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%f000Z', 'now')),
  "last_seen_at" TEXT,
  "revoked_at" TEXT,
  CONSTRAINT "pos_waiter_devices_token_unique" UNIQUE (token_hash),
  CONSTRAINT "pos_waiter_devices_name_present" CHECK ((trim(name) <> '')),
  FOREIGN KEY (branch_id) REFERENCES pos_branches(id),
  FOREIGN KEY (business_id) REFERENCES pos_businesses(id) ON DELETE CASCADE
)''',
    '''CREATE INDEX IF NOT EXISTS pos_waiter_devices_business_idx ON pos_waiter_devices (business_id, branch_id)''',
  ],
  // Waiter shifts clocked on the handheld (waiter shift clock).
  66: [
    '''CREATE TABLE IF NOT EXISTS "pos_waiter_shifts" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "business_id" INTEGER NOT NULL,
  "branch_id" INTEGER,
  "user_id" INTEGER NOT NULL,
  "started_device_id" INTEGER,
  "ended_device_id" INTEGER,
  "started_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%f000Z', 'now')),
  "ended_at" TEXT,
  CONSTRAINT "pos_waiter_shifts_ends_after_start" CHECK ((ended_at IS NULL OR ended_at >= started_at)),
  FOREIGN KEY (business_id) REFERENCES pos_businesses(id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id) REFERENCES pos_branches(id),
  FOREIGN KEY (user_id) REFERENCES pos_users(id),
  FOREIGN KEY (started_device_id) REFERENCES pos_waiter_devices(id),
  FOREIGN KEY (ended_device_id) REFERENCES pos_waiter_devices(id)
)''',
    '''CREATE UNIQUE INDEX IF NOT EXISTS pos_waiter_shifts_one_open ON pos_waiter_shifts (user_id) WHERE ended_at IS NULL''',
    '''CREATE INDEX IF NOT EXISTS pos_waiter_shifts_business_idx ON pos_waiter_shifts (business_id, branch_id, started_at)''',
  ],
  // The count of orders in a trading day (PostgreSQL migration 67). A cloud
  // till is one till, so "shared by every till" is only itself, but the history
  // and the receipt read the column on either engine.
  //
  // SQLite cannot change the row in a BEFORE trigger, and the trading day is
  // itself stamped by an AFTER INSERT trigger that UPDATEs the row
  // (`pos_orders_business_day`). So the number is taken in the two places the
  // day can arrive: an INSERT that already names it, and the UPDATE that
  // stamps it. A row with no trading day keeps NULL, never an invented number.
  67: [
    'ALTER TABLE pos_orders ADD COLUMN day_order_number INTEGER',
    '''CREATE TABLE IF NOT EXISTS "pos_order_day_counters" (
  "business_day_id" INTEGER PRIMARY KEY,
  "last_value" INTEGER NOT NULL DEFAULT 0,
  CONSTRAINT "pos_order_day_counters_sane" CHECK (last_value >= 0),
  FOREIGN KEY (business_day_id) REFERENCES pos_business_days(id) ON DELETE CASCADE
)''',
    '''CREATE TRIGGER pos_orders_number_insert AFTER INSERT ON pos_orders
  WHEN NEW.day_order_number IS NULL AND NEW.business_day_id IS NOT NULL
BEGIN
  INSERT INTO pos_order_day_counters (business_day_id, last_value)
  VALUES (NEW.business_day_id, 1)
  ON CONFLICT (business_day_id)
  DO UPDATE SET last_value = last_value + 1;
  UPDATE pos_orders SET day_order_number = (
    SELECT last_value FROM pos_order_day_counters
     WHERE business_day_id = NEW.business_day_id)
   WHERE rowid = NEW.rowid;
END''',
    '''CREATE TRIGGER pos_orders_number_day_stamped
  AFTER UPDATE OF business_day_id ON pos_orders
  WHEN NEW.day_order_number IS NULL AND NEW.business_day_id IS NOT NULL
BEGIN
  INSERT INTO pos_order_day_counters (business_day_id, last_value)
  VALUES (NEW.business_day_id, 1)
  ON CONFLICT (business_day_id)
  DO UPDATE SET last_value = last_value + 1;
  UPDATE pos_orders SET day_order_number = (
    SELECT last_value FROM pos_order_day_counters
     WHERE business_day_id = NEW.business_day_id)
   WHERE rowid = NEW.rowid;
END''',
  ],
};

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
