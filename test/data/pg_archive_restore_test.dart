@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/backup/pg_archive.dart';
import 'package:xorder_pos/data/backup/pg_tools.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

import 'pg_fixture.dart';

/// A backup is only a backup once something has been restored from it.
///
/// `backup_restore_test.dart` covers what the product decides around a copy —
/// who may take one, what is recorded, when a restore is refused. This covers
/// the engine underneath, and the accounts a real install runs it as, which
/// that suite cannot: it takes and restores as a superuser.
///
/// Everything here runs the real `pg_dump` and `pg_restore` against a real
/// server, the way a branch would: dumped by an account that can read
/// everything and write nothing, restored by `pos_admin` — the database owner,
/// which is not a superuser — onto a machine that has never seen the data.
///
/// "The same database" is checked the strict way: every table's rows, every
/// sequence's position and every grant the till's account holds, compared
/// with the original. A restore that brought the menu back but reset the
/// invoice counter would hand out invoice numbers that already exist.
/// Both tools from one directory, looked for without running them — the test
/// has to decide whether it is skipped before anything can be awaited.
PgToolset? _findTools() {
  final exe = Platform.isWindows ? '.exe' : '';
  for (final directory in PgTools.searchPath()) {
    final dump = File('$directory${Platform.pathSeparator}pg_dump$exe');
    final restore = File('$directory${Platform.pathSeparator}pg_restore$exe');
    if (dump.existsSync() && restore.existsSync()) {
      return PgToolset(pgDump: dump.path, pgRestore: restore.path, version: '');
    }
  }
  return null;
}

void main() {
  final tools = _findTools();
  if (PgFixture.host == null || tools == null) {
    test(
      'backup and restore (skipped — needs POS_PG_HOST and pg_dump)',
      () {},
      skip: true,
    );
    return;
  }

  // Cluster-wide, so named for this suite and never for anything real — and
  // for this checkout, because another worktree's run shares the server's
  // roles even though it never shares these databases.
  final reader = PgFixture.roleFor('backup_reader');
  // The database's owner, and the account that restores it: not a superuser,
  // and not the install's real `pos_admin` — which a clean server has not got,
  // and which another suite makes with a password of its own. A name for this
  // checkout, made here and dropped here.
  final owner = PgFixture.roleFor('backup_owner');
  const readerPassword = 'reader-password';
  const ownerPassword = 'owner-password';
  const terminal = '55555555-5555-4555-8555-555555555555';

  final source = PgFixture.nameFor('pg_archive_restore');
  final target = PgFixture.nameFor('pg_archive_restore_target');

  late PgFixture pg;
  late PosDatabase targetDb;
  late DeploymentConfig targetConfig;
  late Directory folder;
  late File backup;
  var taken = 0;

  PgArchive archive() => PgArchive(tools);

  /// A fresh name each time: a real copy is named for the second it was taken.
  File nextFile() => File('${folder.path}/copy-${taken++}.dump');

  BackupConnection as(String user, String database) => BackupConnection(
    host: PgFixture.host!,
    port: PgFixture.port,
    database: database,
    user: user,
    // Each account signs in with the password it was made with. They all
    // signed in with the superuser's, which a server that trusts every client
    // never noticed and one that checks passwords refuses.
    password: user == reader
        ? readerPassword
        : user == owner
        ? ownerPassword
        : PgFixture.password,
    verifyTls: false,
  );

  Future<Object?> one(
    String sql, [
    Map<String, Object?> parameters = const {},
  ]) async =>
      (await pg.database.query(pg.config, sql, parameters: parameters))
          .first[0];

  /// Everything a restore has to bring back, as one comparable value.
  Future<Map<String, Object?>> fingerprint(
    PosDatabase db,
    DeploymentConfig config,
  ) async {
    final tables = await db.query(
      config,
      "SELECT table_name FROM information_schema.tables "
      "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' "
      'ORDER BY table_name',
    );
    return {
      for (final row in tables)
        'rows:${row[0]}': (await db.query(
          config,
          "SELECT count(*) || ':' || md5(coalesce(string_agg(t::text, '|' "
          "ORDER BY t::text), '')) FROM \"${row[0]}\" t",
        )).first[0],
      // Where each counter will go next: an invoice number, an order id.
      'sequences': (await db.query(
        config,
        "SELECT string_agg(sequencename || '=' || coalesce(last_value, 0), ',' "
        "ORDER BY sequencename) FROM pg_sequences WHERE schemaname = 'public'",
      )).first[0],
      // What the till's account may do — table and column grants both.
      'till grants': (await db.query(
        config,
        "SELECT string_agg(table_name || '.' || privilege_type, ',' "
        'ORDER BY table_name, privilege_type) '
        "FROM information_schema.role_table_grants WHERE grantee = 'pos_till'",
      )).first[0],
      'till column grants': (await db.query(
        config,
        "SELECT string_agg(table_name || '.' || column_name || '.' || "
        "privilege_type, ',' ORDER BY table_name, column_name, privilege_type) "
        "FROM information_schema.column_privileges WHERE grantee = 'pos_till'",
      )).first[0],
    };
  }

  setUpAll(() async {
    await PgFixture.maintenance([
      'DROP DATABASE IF EXISTS "$source" WITH (FORCE)',
      'DROP DATABASE IF EXISTS "$target" WITH (FORCE)',
      // The shape the installer gives the real backup account: a member of
      // pg_read_all_data, and nothing else.
      'DO \$\$ BEGIN '
          "IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$reader') "
          "THEN CREATE ROLE $reader LOGIN PASSWORD '$readerPassword'; END IF; "
          'END \$\$',
      // Set again either way: a leftover from an earlier run has whatever
      // password that run gave it, and these names are this suite's alone.
      "ALTER ROLE $reader LOGIN PASSWORD '$readerPassword'",
      'GRANT pg_read_all_data TO $reader',
      'DO \$\$ BEGIN '
          "IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$owner') "
          "THEN CREATE ROLE $owner LOGIN PASSWORD '$ownerPassword'; END IF; "
          'END \$\$',
      "ALTER ROLE $owner LOGIN PASSWORD '$ownerPassword'",
      // The till's account, which the fingerprint compares grants for. Made
      // only if the server has none: on a machine where the installer ran it is
      // the real one, and this suite has no business changing its password.
      'DO \$\$ BEGIN '
          "IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pos_till') "
          "THEN CREATE ROLE pos_till LOGIN PASSWORD 'till-password'; END IF; "
          'END \$\$',
    ]);

    pg = await PgFixture.open('pg_archive_restore');
    await PosMigrator(pg.database).migrate(pg.config);
    for (final grant in LocalBootstrap.tillGrants(
      database: source,
      role: 'pos_till',
    )) {
      await pg.database.query(pg.config, grant);
    }

    final restaurant =
        await one(
              "INSERT INTO pos_restaurants (slug, name) "
              "VALUES ('kashri', 'Koshary El Tahrir') RETURNING id",
            )
            as int;
    final branch =
        await one(
              "INSERT INTO pos_branches (restaurant_id, code, name) "
              "VALUES (@r, 'MAIN', 'Tahrir') RETURNING id",
              {'r': restaurant},
            )
            as int;
    final staff =
        await one(
              'INSERT INTO pos_staff (restaurant_id, branch_id, name, '
              "  username, pin_salt, pin_hash) VALUES (@r, @b, 'Nour Adel', "
              "  'nour', 'salt', 'hash') RETURNING id",
              {'r': restaurant, 'b': branch},
            )
            as int;
    final category =
        await one(
              'INSERT INTO pos_categories (restaurant_id, name_en) '
              "VALUES (@r, 'Koshary') RETURNING id",
              {'r': restaurant},
            )
            as int;
    await one(
      'INSERT INTO pos_products (restaurant_id, category_id, name_en, '
      "  price_minor) VALUES (@r, @c, 'Large koshary', 6500) RETURNING id",
      {'r': restaurant, 'c': category},
    );
    await one(
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
      "VALUES (@t::uuid, @r, @b, 'POS-01') RETURNING id",
      {'t': terminal, 'r': restaurant, 'b': branch},
    );
    await one(
      'INSERT INTO pos_business_days (restaurant_id, branch_id, '
      "  business_date, opened_by, opened_at) VALUES (@r, @b, '2026-09-11', "
      "  @by, now() - interval '3 hours') RETURNING id",
      {'r': restaurant, 'b': branch, 'by': staff},
    );
    await one(
      'INSERT INTO pos_shifts (restaurant_id, branch_id, terminal_id, '
      "  opened_by, opened_at) VALUES (@r, @b, @t::uuid, @by, "
      "  now() - interval '2 hours') RETURNING id",
      {'r': restaurant, 'b': branch, 't': terminal, 'by': staff},
    );
    for (final total in [6500, 13000]) {
      await one(
        'INSERT INTO pos_orders (client_transaction_id, restaurant_id, '
        '  branch_id, terminal_id, invoice_number, order_type, currency, '
        '  exponent, subtotal_minor, service_minor, vat_minor, total_minor, '
        '  occurred_at, status) '
        'VALUES (gen_random_uuid(), @r, @b, @t::uuid, '
        "  'INV-' || gen_random_uuid()::text, 'takeaway', 'EGP', 2, "
        "  @total, 0, 0, @total, now() - interval '1 hour', 'PAID') "
        'RETURNING id',
        {'r': restaurant, 'b': branch, 't': terminal, 'total': total},
      );
    }

    targetConfig = DeploymentConfig(
      mode: DeploymentMode.offline,
      databaseHost: PgFixture.host!,
      verifyTls: false,
      databaseName: target,
      databaseUser: PgFixture.user,
      databasePort: PgFixture.port,
    );
    targetDb = PosDatabase(
      credentials: InMemoryPosDbCredentials(PgFixture.password),
    );
    folder = await Directory.systemTemp.createTemp('xorder-backups');
  });

  tearDownAll(() async {
    await pg.close();
    await targetDb.close();
    if (folder.existsSync()) await folder.delete(recursive: true);
    // It holds a membership and nothing on either database, so no database
    // has to go first. Dropped rather than kept for the next run: with a name
    // per checkout, a deleted worktree's reader — a login role that can read
    // everything — would otherwise stay on the server for good.
    await PgFixture.maintenance([
      'DROP ROLE IF EXISTS $reader',
      // The owner owns the restore target, so the database goes first. The
      // till's role is not dropped: where the installer ran it is the real one.
      'DROP DATABASE IF EXISTS "$target" WITH (FORCE)',
      'DROP ROLE IF EXISTS $owner',
    ]);
  });

  test('taken by an account that can read everything and write nothing',
      () async {
    backup = nextFile();
    final contents = await archive().dump(from: as(reader, source), to: backup);

    expect(backup.existsSync(), isTrue);
    expect(backup.lengthSync(), greaterThan(0));
    expect(contents, contains('TABLE DATA public pos_orders'));
  });

  test('restored onto a machine that never saw it, it is the same database',
      () async {
    // A blank database owned by pos_admin — what a replacement till's
    // installer leaves behind.
    await PgFixture.maintenance(['CREATE DATABASE "$target" OWNER $owner']);

    await archive().restore(from: backup, into: as(owner, target));

    final original = await fingerprint(pg.database, pg.config);
    final restored = await fingerprint(targetDb, targetConfig);
    expect(original['rows:pos_products'], startsWith('1:'));
    expect(original['rows:pos_shifts'], startsWith('1:'));
    expect(original['till grants'], isNotNull);
    expect(restored, original);
  });

  test('restored over a damaged one, the damage goes and nothing doubles',
      () async {
    await targetDb.query(
      targetConfig,
      'UPDATE pos_products SET price_minor = 1',
    );
    await targetDb.query(
      targetConfig,
      'INSERT INTO pos_categories (restaurant_id, name_en) '
      "SELECT id, 'Stray' FROM pos_restaurants",
    );

    await archive().restore(from: backup, into: as(owner, target));

    expect(
      await fingerprint(targetDb, targetConfig),
      await fingerprint(pg.database, pg.config),
    );
  });

  test('a damaged backup is refused before the database is touched',
      () async {
    // The last few bytes missing — a USB drive pulled out as the copy
    // finished. Where `--list` gives up depends on the dump's layout, so the
    // cut is small and the premise is checked rather than assumed: this file
    // LISTS, and only reading it to the end finds the end missing.
    final bytes = await backup.readAsBytes();
    final cut = File('${backup.path}.cut')
      ..writeAsBytesSync(bytes.sublist(0, bytes.length - 16));
    final listed = await Process.run(tools.pgRestore, ['--list', cut.path]);
    expect(listed.exitCode, 0, reason: 'the premise: a list alone accepts it');

    await expectLater(
      archive().restore(from: cut, into: as(owner, target)),
      throwsA(isA<ArchiveFailure>()
          .having((e) => e.kind, 'kind', ArchiveFailureKind.unreadable)),
    );
  });

  test('a restore that fails part-way leaves the database it found',
      () async {
    // A sound backup that cannot finish here: it grants to a role this server
    // does not have — exactly what restoring onto a machine that was never
    // given `pos_till` looks like. The GRANT comes after every table has been
    // dropped and refilled, so this fails as late as a restore can.
    //
    // Per checkout, and not only for tidiness: this test needs the role to be
    // missing when the restore runs. Under one shared name, another worktree
    // creating its ghost at that moment would let the restore succeed, and
    // that ghost's grant in the other source database would stop this run's
    // DROP ROLE.
    final ghost = PgFixture.roleFor('backup_ghost');
    await PgFixture.maintenance(['CREATE ROLE $ghost']);
    final File doomed;
    try {
      await pg.database.query(
        pg.config,
        'GRANT SELECT ON pos_products TO $ghost',
      );
      doomed = nextFile();
      await archive().dump(from: as(reader, source), to: doomed);
    } finally {
      await pg.database.query(
        pg.config,
        'REVOKE ALL ON pos_products FROM $ghost',
      );
      await PgFixture.maintenance(['DROP ROLE $ghost']);
    }

    await targetDb.query(
      targetConfig,
      'UPDATE pos_products SET price_minor = 7777',
    );
    final before = await fingerprint(targetDb, targetConfig);

    await expectLater(
      archive().restore(from: doomed, into: as(owner, target)),
      throwsA(isA<ArchiveFailure>()
          .having((e) => e.kind, 'kind', ArchiveFailureKind.restoreFailed)),
    );

    expect(
      await fingerprint(targetDb, targetConfig),
      before,
      reason: 'all or nothing: never a half-restored database',
    );
  });
}
