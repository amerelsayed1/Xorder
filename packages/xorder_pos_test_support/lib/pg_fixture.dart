import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/sql/sql.dart' as seam;
import 'package:shared_module/data/sqlite/sqlite_database.dart';

/// Shared setup for the suites that need a real PostgreSQL.
///
/// **Every suite uses ONE database per checkout** ([sharedName]). It used to be
/// one database per suite, which left ~65 `xorder_pos_<suite>_<tag>` databases
/// on the server after every run. Each suite already migrates (idempotent) and
/// empties what it needs in its own `setUp`, so a single database is enough —
/// **provided the suites run one at a time.**
///
/// **That proviso is the whole risk, and it has bitten before.** `flutter test`
/// runs suites in parallel, and two of them truncating one database produced a
/// failure you would fear most here — a duplicate invoice number — from a test
/// artefact rather than a real race. A flaky money test is worse than no test,
/// because people learn to ignore it. So the PostgreSQL suites (tagged
/// `integration`) must run with `--concurrency=1`; `scripts/check.sh` does that.
/// **Running them yourself, run `flutter test --tags integration --concurrency=1`.**
/// A plain parallel `flutter test` with `POS_PG_HOST` set brings the flaky
/// failures back.
///
/// A suite that creates and drops databases of its own (a restore needs a
/// source and a target; an install test builds the database it is testing)
/// keeps using [nameFor] for those, so they never share the common one.
///
/// **Each checkout gets its own database**, which is the same lesson one level
/// out: two git worktrees running `test/data` against the same server used to
/// share one database and each suite's `DELETE FROM pos_businesses` wiped the
/// other's rows mid-test, surfacing as a foreign key violation on a business
/// that had existed a millisecond earlier.
///
/// The discriminator is derived from the checkout path rather than passed in, so
/// nothing has to be coordinated between concurrent agents or remembered by a
/// person.
class PgFixture {
  PgFixture._(this.database, this.config);

  final seam.SqlDatabase database;
  final DeploymentConfig config;

  /// `POS_TEST_ENGINE=sqlite` runs the same suites on the cloud till's engine:
  /// an encrypted SQLite file per test file, no server
  /// (pos-cloud-single-till-sqlite, stage 4). Anything else is PostgreSQL.
  static bool get onSqlite =>
      Platform.environment['POS_TEST_ENGINE'] == 'sqlite';

  /// The server, or — on SQLite, where there is none — a stand-in so the
  /// suites that skip without a server run.
  static String? get host =>
      Platform.environment['POS_PG_HOST'] ?? (onSqlite ? 'sqlite' : null);
  static int get port => int.tryParse(Platform.environment['POS_PG_PORT'] ?? '5432') ?? 5432;
  static String get password => Platform.environment['POS_PG_PASSWORD'] ?? 'postgres';
  static String get user => Platform.environment['POS_PG_USER'] ?? 'pos_till';

  /// Create (once) and open the checkout's shared database.
  ///
  /// [suite] is kept so the 60-odd call sites still say who is asking, but it no
  /// longer names a database; see the class comment for why that is safe only
  /// when the suites run one at a time.
  static Future<PgFixture> open(String suite) async {
    if (onSqlite) return _openSqlite();
    final address = host;
    if (address == null) throw StateError('POS_PG_HOST is not set');

    final databaseName = sharedName;
    await _ensureDatabase(address, databaseName);
    if (!_freshForThisFile) {
      await _resetSchema(address, databaseName);
      _freshForThisFile = true;
    }

    return PgFixture._(
      PosDatabase(credentials: InMemoryPosDbCredentials(password)),
      DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: address,
        // The throwaway container has no certificate. Only a private host may
        // ever skip verification, and 127.0.0.1 qualifies.
        allowInsecureLan: true,
        databaseName: databaseName,
        databaseUser: user,
        databasePort: port,
      ),
    );
  }

  /// The one database every suite shares in this checkout.
  static String get sharedName => 'xorder_pos_test_$_checkout';

  /// A database of its own for [suite] in this checkout, for the few suites that
  /// create and drop databases themselves. Not what [open] uses.
  static String nameFor(String suite) => 'xorder_pos_${suite}_$_checkout';

  /// A role named [name] for this checkout alone.
  ///
  /// Roles are cluster-wide, so [nameFor] never reached them: two checkouts
  /// both creating `xorder_test_install_admin` meant one's `DROP ROLE` failed
  /// on the database the other had just given it — one checkout's cleanup
  /// breaking on another's test. The tag keeps the result a plain lowercase
  /// identifier, well inside PostgreSQL's 63 bytes for any suite-sized [name].
  static String roleFor(String name) => 'xorder_test_${name}_$_checkout';

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
  ///
  /// The path hashed is the **workspace root**, not the member the suite runs
  /// from (pos-split-apps, stage 3): the shared package and both apps have
  /// PostgreSQL suites, `check.sh` runs them one member after another, and
  /// one database per checkout is what `tool/drop_test_databases.dart` cleans.
  static final String _checkout = _tag(workspaceRootOf(Directory.current.path));

  /// The nearest ancestor of [path] (itself included) holding a `pubspec.yaml`
  /// with a `workspace:` section, or [path] when there is none.
  static String workspaceRootOf(String path) {
    var dir = Directory(path).absolute;
    while (true) {
      final pubspec = File('${dir.path}/pubspec.yaml');
      if (pubspec.existsSync() &&
          pubspec.readAsLinesSync().any((l) => l.startsWith('workspace:'))) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return Directory(path).absolute.path;
      dir = parent;
    }
  }

  static String _tag(String path) {
    // FNV-1a, inline: this needs to be stable across runs and processes, and
    // `Object.hashCode` is neither.
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Whether this test file has already been given an empty schema.
  ///
  /// Static, so once per isolate — and `flutter test` runs each test file in
  /// its own isolate. See [_resetSchema].
  static bool _freshForThisFile = false;

  /// One file per test file (each runs in its own isolate), shared by every
  /// fixture that file opens — as the PostgreSQL database is.
  static SqliteDatabase? _sqlite;

  static Future<PgFixture> _openSqlite() async {
    final db = _sqlite ??= await () async {
      final dir = await Directory.systemTemp.createTemp('pos_sqlite_suite_');
      final key = newSqliteKey();
      return SqliteDatabase(path: '${dir.path}/till.db', key: () async => key);
    }();
    return PgFixture._(
      db,
      const DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: 'sqlite',
        databaseName: 'xorder_pos',
      ),
    );
  }

  /// Start each test FILE on an empty schema (XORD-029).
  ///
  /// Sharing one database meant one suite's leftovers broke every suite after
  /// it, in two ways. A suite that leaves money history behind (an order, a
  /// shift, a combo) makes the next one's `DELETE FROM pos_businesses` fail:
  /// those references are RESTRICT on purpose, because a sale must never be
  /// deleted with its cashier. And a suite that replays an old migration by
  /// deleting its `schema_migrations` row, and fails, leaves that row deleted —
  /// so every later suite tries to re-run it while migrating. Rebuilding the
  /// schema once per file keeps the one-database rule (and its single cleanup)
  /// while making each file independent of the order it runs in. Tests inside
  /// one file still share it, as they always did.
  ///
  /// Only ever this checkout's own test database ([sharedName]).
  static Future<void> _resetSchema(String address, String name) async {
    final connection = await Connection.open(
      Endpoint(
        host: address,
        port: port,
        database: name,
        username: user,
        password: password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    try {
      await connection.execute('DROP SCHEMA IF EXISTS public CASCADE');
      await connection.execute('CREATE SCHEMA public');
      // As a new database leaves it, so roles the suites create can still
      // reach their tables once granted.
      await connection.execute('ALTER SCHEMA public OWNER TO pg_database_owner');
      await connection.execute('GRANT USAGE ON SCHEMA public TO PUBLIC');
    } finally {
      await connection.close();
    }
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

  /// Re-run migration [version] on today's schema, as it would read today.
  ///
  /// A suite that proves a migration is safe to run twice used to delete its
  /// `schema_migrations` row and let the migrator run it again. Migrations
  /// keep the names of their day, and later ones renamed tables and columns
  /// (62: `pos_staff` → `pos_users`; 64: `pos_restaurants` → `pos_businesses`,
  /// `restaurant_id` → `business_id`), so the old text no longer runs. This
  /// runs the same statements with those renames applied, and records the
  /// version, in one transaction. Returns `[version]`, as the migrator would.
  Future<List<int>> replay(int version) async {
    if (onSqlite) {
      throw UnsupportedError('replay replays PostgreSQL migration text');
    }
    final migration = posMigrations.singleWhere((m) => m.version == version);
    await database.runTx(config, (tx) async {
      for (final statement in migration.statements) {
        await tx.execute(_asToday(statement));
      }
      await tx.execute(
        Sql.named(
          'INSERT INTO schema_migrations (version) VALUES (@v) '
          'ON CONFLICT DO NOTHING',
        ),
        parameters: {'v': version},
      );
    });
    return [version];
  }

  static String _asToday(String sql) => sql
      .replaceAll('pos_staff_permission_overrides', 'pos_user_permission_overrides')
      .replaceAll('pos_staff_roles', 'pos_user_roles')
      .replaceAll('pos_staff', 'pos_users')
      .replaceAll('pos_restaurants', 'pos_businesses')
      .replaceAll('restaurant_id', 'business_id');

  /// Empty ledger, same schema. Run between tests.
  Future<void> truncate() => onSqlite
      ? _truncateSqlite()
      : database.runTx(
          config,
          (tx) => tx.execute('TRUNCATE pos_orders, pos_invoice_sequences RESTART IDENTITY CASCADE'),
        );

  /// PostgreSQL's `TRUNCATE … CASCADE` on SQLite: every table that refers,
  /// however indirectly, to an order or an invoice counter is emptied first,
  /// then those two, and their ids start again from 1.
  Future<void> _truncateSqlite() => database.runTx(config, (tx) async {
    final tables = [
      for (final r in await tx.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name LIKE 'pos_%'",
      ))
        r[0]! as String,
    ];
    final refersTo = <String, Set<String>>{};
    for (final table in tables) {
      for (final r in await tx.execute(
        "SELECT \"table\" FROM pragma_foreign_key_list('$table')",
      )) {
        refersTo.putIfAbsent(r[0]! as String, () => {}).add(table);
      }
    }
    final doomed = <String>[];
    void visit(String table) {
      if (doomed.contains(table)) return;
      for (final child in refersTo[table] ?? const <String>{}) {
        visit(child);
      }
      doomed.add(table);
    }

    visit('pos_orders');
    visit('pos_invoice_sequences');
    for (final table in doomed) {
      await tx.execute('DELETE FROM "$table"');
      await tx.execute("DELETE FROM sqlite_sequence WHERE name = '$table'");
    }
  });

  Future<void> close() => database.close();
}
