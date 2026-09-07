@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

import 'pg_fixture.dart';

/// The offline grant set, applied to a real role on a real server, and then
/// tried.
///
/// `till_grants_test.dart` asserts the statements. This asserts that
/// PostgreSQL agrees — which is the only claim that matters, because the
/// statements could be right and the schema could still hand the role
/// something through a default privilege or an inherited membership.
void main() {
  if (PgFixture.host == null) {
    test('till grants (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const role = 'pos_till_grant_probe';
  const password = 'probe-only';

  late PgFixture pg;
  late PosDatabase db;

  setUpAll(() async {
    pg = await PgFixture.open('till_grants');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);

    // A throwaway role, created and dropped here. It holds nothing but what
    // the offline grant list gives it, which is the point.
    await _dropRole(db, pg, role);
    await db.query(
      pg.config,
      'CREATE ROLE "$role" LOGIN PASSWORD \'$password\'',
    );
    // The upgrade, not the fresh install: the role is first given the CLOUD
    // set — which is what every offline branch server built before the split
    // actually holds — and then the offline list is applied over it. Passing
    // from that starting point is the claim that matters, because a REVOKE
    // that only works on a role which never had the grant proves nothing.
    for (final statement in LocalBootstrap.tillGrants(
      database: pg.config.databaseName,
      role: role,
      cloudSeeding: true,
    )) {
      await db.query(pg.config, statement);
    }
    for (final statement in LocalBootstrap.tillGrants(
      database: pg.config.databaseName,
      role: role,
      cloudSeeding: false,
    )) {
      await db.query(pg.config, statement);
    }
  });

  tearDownAll(() async {
    await _dropRole(db, pg, role);
    await db.close();
  });

  Future<Connection> connect() => Connection.open(
    Endpoint(
      host: pg.config.databaseHost,
      port: pg.config.databasePort,
      database: pg.config.databaseName,
      username: role,
      password: password,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  Future<Object?> refusalFor(String sql) async {
    final connection = await connect();
    try {
      await connection.execute(sql);
      return null;
    } on ServerException catch (error) {
      return error.code;
    } finally {
      await connection.close();
    }
  }

  test('the till may read the menu', () async {
    final connection = await connect();
    addTearDown(connection.close);
    // No refusal is the assertion; the row count is irrelevant.
    await connection.execute('SELECT 1 FROM pos_products');
    await connection.execute('SELECT 1 FROM pos_staff');
  });

  test('the till may not reprice the menu', () async {
    expect(
      await refusalFor('UPDATE pos_products SET price_minor = 1'),
      '42501',
      reason: 'insufficient_privilege — the money offline lives in this row',
    );
  });

  test('the till may not add or remove a product', () async {
    expect(
      await refusalFor(
        "INSERT INTO pos_products (restaurant_id, category_id, name_en, "
        "price_minor) VALUES (1, 1, 'x', 1)",
      ),
      '42501',
    );
    expect(await refusalFor('DELETE FROM pos_products'), '42501');
  });

  test('the till may not promote somebody to the owner role', () async {
    // The escalation this whole change exists to close: with UPDATE here, a
    // recovered till password reaches Management without the administrator's.
    expect(await refusalFor('UPDATE pos_staff SET role_id = 1'), '42501');
  });

  test('the till may not overwrite a PIN hash', () async {
    expect(
      await refusalFor("UPDATE pos_staff SET pin_hash = 'x', pin_salt = 'y'"),
      '42501',
    );
  });

  test('the till may not rename the restaurant or its branches', () async {
    expect(await refusalFor("UPDATE pos_restaurants SET name = 'x'"), '42501');
    expect(await refusalFor("UPDATE pos_branches SET name = 'x'"), '42501');
  });

  test('the till may still take money', () async {
    // The other half of the claim: closing the hole must not close the till.
    expect(
      await refusalFor('SELECT 1 FROM pos_orders'),
      isNull,
      reason: 'reads its own sales',
    );
    expect(
      await refusalFor('SELECT 1 FROM pos_shifts'),
      isNull,
    );
    expect(
      await refusalFor('SELECT 1 FROM pos_invoice_sequences'),
      isNull,
    );
  });

  test('a sale is still writable, and still cannot be repriced', () async {
    expect(
      await refusalFor('UPDATE pos_orders SET total_minor = 0'),
      '42501',
      reason: 'the column-scoped grant excludes every money column',
    );
  });
}

/// A role with grants on it cannot be dropped until they are revoked, and
/// `DROP OWNED BY` throws when the role does not exist yet — which is the
/// normal case on the first run.
Future<void> _dropRole(PosDatabase db, PgFixture pg, String role) async {
  for (final statement in [
    'DROP OWNED BY "$role"',
    'DROP ROLE IF EXISTS "$role"',
  ]) {
    try {
      await db.query(pg.config, statement);
    } on Object {
      // Nothing to revoke, or nothing to drop.
    }
  }
}
