@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Migration 64 — `pos_restaurants` becomes `pos_businesses`.
///
/// As for 62: a rename is only safe as an upgrade of a database that already
/// holds a business, so this builds the schema as 63 left it, puts rows in,
/// runs the real migrator, and asks whether anything was lost, left behind, or
/// broken in a function that still named the old table.
void main() {
  if (PgFixture.host == null) {
    test('business rename (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int oldId;

  Future<Object?> one(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0];

  setUp(() async {
    pg = await PgFixture.open('business_rename');
    db = pg.database;
    // Rebuilt rather than truncated: a migration runs once per database.
    await db.query(pg.config, 'DROP SCHEMA public CASCADE');
    await db.query(pg.config, 'CREATE SCHEMA public');
    await PosMigrator(
      db,
      migrations: posMigrations.where((m) => m.version < 64).toList(),
    ).migrate(pg.config);

    oldId = await one(
          "INSERT INTO pos_restaurants (slug, name) VALUES ('kashri', 'Kashri') "
          'RETURNING id',
        )
        as int;
    await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main')",
      parameters: {'r': oldId},
    );
    await db.query(
      pg.config,
      'INSERT INTO pos_settings (restaurant_id, scope, scope_id, key, value) '
      "VALUES (@r, 'restaurant', '', 'cash.blind_close', 'true')",
      parameters: {'r': oldId},
    );
  });

  tearDown(() async {
    await PosMigrator(db).migrate(pg.config);
    await pg.close();
  });

  test('keeps the business, its branch and its settings, under the new names',
      () async {
    final applied = await PosMigrator(db).migrate(pg.config);
    expect(applied.first, 64);

    expect(
      await one('SELECT slug FROM pos_businesses WHERE id = @id', {'id': oldId}),
      'kashri',
    );
    expect(
      await one(
        'SELECT count(*) FROM pos_branches WHERE business_id = @id',
        {'id': oldId},
      ),
      1,
    );
    expect(
      await one(
        'SELECT scope FROM pos_settings WHERE business_id = @id',
        {'id': oldId},
      ),
      'business',
      reason: 'the stored scope follows the name',
    );
  });

  test('leaves no restaurant name behind in the schema', () async {
    await PosMigrator(db).migrate(pg.config);

    expect(
      await one(
        "SELECT count(*) FROM information_schema.columns "
        "WHERE table_schema = 'public' AND column_name LIKE '%restaurant%'",
      ),
      0,
    );
    expect(
      await one(
        "SELECT count(*) FROM pg_class c JOIN pg_namespace n "
        "ON n.oid = c.relnamespace WHERE n.nspname = 'public' "
        "AND c.relname LIKE '%restaurant%'",
      ),
      0,
      reason: 'tables, sequences and indexes',
    );
    expect(
      await one(
        "SELECT count(*) FROM pg_constraint WHERE conname LIKE '%restaurant%'",
      ),
      0,
    );
    expect(
      await one(
        "SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal "
        "AND tgname LIKE '%restaurant%'",
      ),
      0,
    );
    expect(
      await one(
        "SELECT count(*) FROM pg_proc p JOIN pg_namespace n "
        "ON n.oid = p.pronamespace WHERE n.nspname = 'public' "
        "AND (p.prosrc LIKE '%pos_restaurants%' "
        "     OR p.prosrc LIKE '%restaurant_id%')",
      ),
      0,
      reason: 'a function naming the old table fails on its next call',
    );
  });

  test('the next id carries on, and a new business still gets its units',
      () async {
    await PosMigrator(db).migrate(pg.config);

    final newId = await one(
          "INSERT INTO pos_businesses (slug, name) VALUES ('truck', 'Truck') "
          'RETURNING id',
        )
        as int;
    expect(newId, greaterThan(oldId), reason: 'the sequence was renamed, kept');
    // The seed trigger and its function, re-created by 64, still run.
    expect(
      await one(
        'SELECT count(*) FROM pos_units WHERE business_id = @id',
        {'id': newId},
      ),
      greaterThan(0),
    );
  });

  test('the business-wide scope is the only one with no id', () async {
    await PosMigrator(db).migrate(pg.config);

    await expectLater(
      db.query(
        pg.config,
        'INSERT INTO pos_settings (business_id, scope, scope_id, key, value) '
        "VALUES (@r, 'restaurant', '', 'x', 'y')",
        parameters: {'r': oldId},
      ),
      throwsA(anything),
      reason: 'the old scope value is no longer allowed',
    );
  });
}
