import 'dart:io';

import 'package:postgres/postgres.dart';

import 'test_db_cleanup.dart';

/// Drops the databases and roles the PostgreSQL test suites leave on the
/// server, for ONE checkout.
///
///     dart run tool/drop_test_databases.dart --dry-run        # what would go
///     dart run tool/drop_test_databases.dart                  # this checkout
///     dart run tool/drop_test_databases.dart --tag 9309f7c3   # another one
///
/// `scripts/check.sh` runs it when the run ends. `KEEP_TEST_DBS=1` makes
/// check.sh skip it, to look at what a failing suite left.
///
/// **What it will drop**, and nothing else: databases `xorder_pos_<suite>_<tag>`
/// and roles `xorder_test_<name>_<tag>` for the one [tag] (this checkout's by
/// default). It never matches `xorder_pos`, the real till database, or any
/// database without a tag, or another checkout's tag unless named with `--tag`.
/// It refuses a server that is not this machine unless `--allow-remote`.
///
/// Connects like `test/data/pg_fixture.dart`: `POS_PG_HOST` (required),
/// `POS_PG_PORT`, `POS_PG_USER`, `POS_PG_PASSWORD`.
Future<void> main(List<String> args) async {
  var dryRun = false;
  var allowRemote = false;
  String? tag;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dry-run':
        dryRun = true;
      case '--allow-remote':
        allowRemote = true;
      case '--tag':
        if (i + 1 >= args.length) _fail('--tag needs a value (8 hex digits).');
        tag = args[++i];
      default:
        _fail('Unknown argument "${args[i]}".');
    }
  }

  // The same path `PgFixture` hashes: the workspace root, so a run from any
  // member — the shared package or an app — names the one database per
  // checkout (pos-split-apps, stage 3).
  tag ??= checkoutTag(_workspaceRootOf(Directory.current.path));
  if (!isCheckoutTag(tag)) {
    _fail('"$tag" is not a checkout tag (8 lowercase hex digits).');
  }

  final host = Platform.environment['POS_PG_HOST'];
  if (host == null || host.isEmpty) {
    stdout.writeln(
      'POS_PG_HOST is not set: no test database was created, '
      'nothing to drop.',
    );
    return;
  }
  if (!isLocalHost(host) && !allowRemote) {
    _fail(
      'POS_PG_HOST is "$host", not this machine. Dropping databases on '
      'another server needs --allow-remote.',
    );
  }

  final admin = await Connection.open(
    Endpoint(
      host: host,
      port: int.tryParse(Platform.environment['POS_PG_PORT'] ?? '5432') ?? 5432,
      database: 'postgres',
      username: Platform.environment['POS_PG_USER'] ?? 'pos_till',
      password: Platform.environment['POS_PG_PASSWORD'] ?? 'postgres',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  try {
    final databases = [
      for (final row in await admin.execute(
        'SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1',
      ))
        row[0]! as String,
    ].where((n) => isTestDatabase(n, tag!) && isPlainIdentifier(n)).toList();

    final roles = [
      for (final row in await admin.execute(
        'SELECT rolname FROM pg_roles ORDER BY 1',
      ))
        row[0]! as String,
    ].where((n) => isTestRole(n, tag!) && isPlainIdentifier(n)).toList();

    stdout.writeln(
      'Checkout tag $tag: ${databases.length} test '
      'database(s), ${roles.length} test role(s).',
    );
    for (final name in databases) {
      stdout.writeln('  database $name');
    }
    for (final name in roles) {
      stdout.writeln('  role     $name');
    }
    if (dryRun) {
      stdout.writeln('--dry-run: nothing dropped.');
      return;
    }

    var dropped = 0;
    for (final name in databases) {
      try {
        // Anything still connected (a crashed run) would make the drop fail.
        await admin.execute(
          "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
          "WHERE datname = '$name' AND pid <> pg_backend_pid()",
        );
        await admin.execute('DROP DATABASE IF EXISTS "$name"');
        dropped++;
      } on Object catch (error) {
        stderr.writeln('Could not drop database $name: $error');
      }
    }
    // Roles after databases: a role that owns objects cannot be dropped while
    // its databases exist.
    for (final name in roles) {
      try {
        await admin.execute('DROP ROLE IF EXISTS "$name"');
        dropped++;
      } on Object catch (error) {
        stderr.writeln('Could not drop role $name: $error');
      }
    }
    stdout.writeln('Dropped $dropped of ${databases.length + roles.length}.');
  } finally {
    await admin.close();
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}

/// The nearest ancestor of [path] holding a `pubspec.yaml` with a
/// `workspace:` section, or [path] itself. Mirrors `PgFixture.workspaceRootOf`.
String _workspaceRootOf(String path) {
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
