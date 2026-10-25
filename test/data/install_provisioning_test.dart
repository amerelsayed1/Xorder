@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

import 'pg_fixture.dart';

/// What the Windows installer does to PostgreSQL, done here against a real one.
///
/// `installer/provision.ps1` cannot run on the machines this suite runs on, so
/// it holds none of the logic worth testing: the accounts, who owns the
/// database, the migrations and the grants are all `pos_migrate` — tested
/// here, both through the API and through the command line exactly as the
/// script calls it.
void main() {
  if (PgFixture.host == null) {
    test('install provisioning (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  // Cluster-wide, so named for this suite and never for anything real — and
  // for this checkout, like the databases. With one fixed set, a worktree's
  // setUpAll tried to drop the admin role while it still owned the other
  // worktree's database, and neither run could clean up after itself.
  final names = {
    InstallRole.admin: PgFixture.roleFor('install_admin'),
    InstallRole.till: PgFixture.roleFor('install_till'),
    InstallRole.backup: PgFixture.roleFor('install_backup'),
  };
  // By name, not by prefix: another checkout's roles match the prefix too,
  // and its run creating one mid-test would change what "nothing changed" saw.
  final ours = names.values.map((name) => "'$name'").join(', ');
  final apiDb = PgFixture.nameFor('install_api');
  final cliDb = PgFixture.nameFor('install_cli');

  // Databases first: the admin role owns [apiDb], and the till's CONNECT is
  // granted on it — the only things these roles hold anywhere — so once it is
  // gone a plain DROP ROLE succeeds. No REASSIGN OWNED: it would hand a
  // leftover to the superuser to linger rather than remove it, and anything
  // it could find beyond [apiDb] would not be this suite's to touch.
  List<String> cleanUp() => [
    'DROP DATABASE IF EXISTS "$apiDb" WITH (FORCE)',
    'DROP DATABASE IF EXISTS "$cliDb" WITH (FORCE)',
    for (final name in names.values) 'DROP ROLE IF EXISTS "$name"',
  ];

  DeploymentConfig configFor(String database, String user) => DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseHost: PgFixture.host!,
    allowInsecureLan: true,
    databaseName: database,
    databaseUser: user,
    databasePort: PgFixture.port,
  );
  final superuser = configFor('postgres', PgFixture.user);

  Future<List<List<Object?>>> sql(String database, String query) async {
    final db = PosDatabase(
      credentials: InMemoryPosDbCredentials(PgFixture.password),
    );
    try {
      return [
        for (final row in await db.query(
          configFor(database, PgFixture.user),
          query,
        ))
          row.toList(),
      ];
    } finally {
      await db.close();
    }
  }

  // The passwords the install's roles are made with, and then signed in with.
  // The administrator's was typed twice below — once to create the role and once
  // to be it — and the second time used the superuser's instead, which a server
  // that trusts every client never noticed.
  const adminPassword = 'first-admin';
  const cliPassword = 'cli-install-password';

  setUpAll(() => PgFixture.maintenance(cleanUp()));

  tearDownAll(() => PgFixture.maintenance(cleanUp()));

  test('three accounts, each with only its own rights', () async {
    final created = await LocalBootstrap.createRoles(
      superuser,
      PgFixture.password,
      names: names,
      passwords: {
        InstallRole.admin: adminPassword,
        InstallRole.till: 'first-till',
        InstallRole.backup: 'first-backup',
      },
    );
    expect(created, unorderedEquals(names.values));

    final rows = await sql(
      'postgres',
      'SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin, '
      '  pg_has_role(rolname, \'pg_read_all_data\', \'MEMBER\') '
      'FROM pg_roles WHERE rolname IN ($ours) '
      'ORDER BY rolname',
    );
    final byName = {for (final r in rows) r[0]: r.sublist(1)};
    //                       super  createrole createdb login  reads-all
    expect(byName[names[InstallRole.admin]], [false, false, true, true, false]);
    expect(byName[names[InstallRole.backup]], [false, false, false, true, true]);
    expect(byName[names[InstallRole.till]], [false, false, false, true, false]);
  });

  test('run again, it changes nothing — not even a password', () async {
    // The till and the backup keep these passwords. An upgrade that reset
    // them would stop both on the morning after it.
    Future<List<List<Object?>>> secrets() => sql(
      'postgres',
      "SELECT rolname, rolpassword FROM pg_authid "
      'WHERE rolname IN ($ours) ORDER BY rolname',
    );
    final before = await secrets();

    final created = await LocalBootstrap.createRoles(
      superuser,
      PgFixture.password,
      names: names,
      passwords: {
        InstallRole.admin: 'different',
        InstallRole.till: 'different',
        InstallRole.backup: 'different',
      },
    );

    expect(created, isEmpty);
    expect(await secrets(), before);
  });

  test('the database is the administrator\'s, and so is every table', () async {
    // A restore drops and recreates every table; only their owner may. A
    // database built by the superuser could never be restored by the account
    // the back office signs in as.
    final admin = names[InstallRole.admin]!;
    expect(
      await LocalBootstrap.createDatabase(
        superuser,
        PgFixture.password,
        apiDb,
        owner: admin,
      ),
      isTrue,
    );

    // As the administrator, with the administrator's own password.
    final asAdmin = PosDatabase(
      credentials: InMemoryPosDbCredentials(adminPassword),
    );
    try {
      await PosMigrator(asAdmin).migrate(configFor(apiDb, admin));
      for (final grant in LocalBootstrap.tillGrants(
        database: apiDb,
        role: names[InstallRole.till]!,
      )) {
        await asAdmin.query(configFor(apiDb, admin), grant);
      }
    } finally {
      await asAdmin.close();
    }

    final owners = await sql(
      apiDb,
      "SELECT (SELECT pg_get_userbyid(datdba) FROM pg_database "
      "         WHERE datname = current_database()), "
      "       count(*) FILTER (WHERE tableowner <> '$admin'), count(*) "
      "FROM pg_tables WHERE schemaname = 'public'",
    );
    expect(owners.single[0], admin);
    expect(owners.single[1], 0, reason: 'every table is the owner\'s');
    expect(owners.single[2] as int, greaterThan(30));

    final till = names[InstallRole.till]!;
    final can = await sql(
      apiDb,
      "SELECT has_table_privilege('$till', 'pos_orders', 'INSERT'), "
      "       has_table_privilege('$till', 'pos_staff', 'UPDATE')",
    );
    expect(can.single, [true, false], reason: 'sells; does not edit staff');
  });

  test('the command line, called the way provision.ps1 calls it', () async {
    // Step one as the superuser, step two as the owner — the script's exact
    // flags. Where the install's own role names already exist on the server,
    // step one leaves them alone; where they do not, it makes them with
    // [cliPassword]. Either way the owner of the database it creates is
    // pos_admin, which is the part that matters.
    Future<ProcessResult> tool(List<String> args, String password) =>
        Process.run(
          'dart',
          ['run', 'bin/pos_migrate.dart', ...args],
          environment: {
            'POS_PG_PASSWORD': password,
            // What step one makes the three roles with when they are not there
            // yet — as they are not on a server this suite has to itself — and
            // what step two signs in as the owner with.
            'POS_ADMIN_PASSWORD': cliPassword,
            'POS_TILL_PASSWORD': cliPassword,
            'POS_BACKUP_PASSWORD': cliPassword,
          },
        );
    final common = [
      '--host', PgFixture.host!, '--port', '${PgFixture.port}', //
      '--database', cliDb, '--no-verify-tls',
    ];

    final prepare = await tool([
      ...common,
      '--user', PgFixture.user, '--create-roles', '--create-database', //
      '--owner', 'pos_admin', '--no-migrate',
    ], PgFixture.password);
    expect(prepare.exitCode, 0, reason: '${prepare.stdout}${prepare.stderr}');
    expect(
      await sql(cliDb, "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'"),
      [
        [0],
      ],
      reason: '--no-migrate stops before any table exists',
    );

    final migrate = await tool([
      ...common,
      '--user', 'pos_admin', '--grant-to', 'pos_till', //
    ], cliPassword);
    expect(migrate.exitCode, 0, reason: '${migrate.stdout}${migrate.stderr}');

    final owner = await sql(
      cliDb,
      "SELECT tableowner FROM pg_tables WHERE tablename = 'pos_orders'",
    );
    expect(owner.single.single, 'pos_admin');

    final status = await tool([
      ...common,
      '--user', 'pos_admin', '--status', //
    ], cliPassword);
    expect('${status.stdout}', isNot(contains('PENDING')));

    await PgFixture.maintenance(['DROP DATABASE IF EXISTS "$cliDb" WITH (FORCE)']);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
