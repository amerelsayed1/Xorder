@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

import 'pg_fixture.dart';

/// Migration 62 — `pos_staff` becomes `pos_users`.
///
/// A rename is only safe if it is an upgrade of a database that already holds
/// people, not just a fresh install that never knew the old name. So this
/// builds the schema as it stood at version 61, puts rows in every table the
/// rename touches, runs the real migrator, and asks whether anything was lost
/// or left behind.
void main() {
  if (PgFixture.host == null) {
    test('pos_users rename (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int userId;

  setUp(() async {
    pg = await PgFixture.open('pos_users_rename');
    db = pg.database;
    // Rebuilt rather than truncated: a migration runs once per database.
    await db.query(pg.config, 'DROP SCHEMA public CASCADE');
    await db.query(pg.config, 'CREATE SCHEMA public');
    await PosMigrator(
      db,
      migrations: posMigrations.where((m) => m.version < 62).toList(),
    ).migrate(pg.config);

    businessId = (await db.query(
      pg.config,
      // Version 61's names: this runs before migrations 62 and 64.
      "INSERT INTO pos_restaurants (slug, name) VALUES ('ren', 'Rename') RETURNING id",
    )).first[0]! as int;
    userId = (await db.query(
      pg.config,
      'INSERT INTO pos_staff (restaurant_id, name, username, pin_salt, pin_hash) '
      "VALUES (@r, 'Hana', 'hana', 's', 'h') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;
    await db.query(
      pg.config,
      'INSERT INTO pos_staff_permission_overrides (staff_id, capability, effect) '
      "VALUES (@u, 'order.refund', 'ALLOW')",
      parameters: {'u': userId},
    );
    await db.query(
      pg.config,
      'INSERT INTO pos_audit_events (restaurant_id, actor_staff_id, actor_name, '
      "                              action, entity_type) "
      "VALUES (@r, @u, 'Hana', 'x.changed', 'x')",
      parameters: {'r': businessId, 'u': userId},
    );
  });

  tearDown(() async {
    // Leave the shared database at the current schema for the next suite.
    await db.query(pg.config, 'DROP SCHEMA public CASCADE');
    await db.query(pg.config, 'CREATE SCHEMA public');
    await PosMigrator(db).migrate(pg.config);
    await pg.close();
  });

  test('keeps every row, and the ids other rows point at', () async {
    final applied = await PosMigrator(db).migrate(pg.config);
    // 62 first; anything numbered after it follows.
    expect(applied.first, 62);

    final users = await db.query(
      pg.config,
      'SELECT id, name FROM pos_users WHERE business_id = @r',
      parameters: {'r': businessId},
    );
    expect(users.single[0], userId);
    expect(users.single[1], 'Hana');

    final overrides = await db.query(
      pg.config,
      'SELECT user_id, capability FROM pos_user_permission_overrides',
    );
    expect(overrides.single[0], userId);
    expect(overrides.single[1], 'order.refund');

    final audit = await db.query(
      pg.config,
      'SELECT actor_user_id FROM pos_audit_events WHERE business_id = @r',
      parameters: {'r': businessId},
    );
    expect(audit.single[0], userId);

    // The id sequence moved with the table, still pointing past the old rows.
    final next = await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, name, username, pin_salt, pin_hash) '
      "VALUES (@r, 'Rana', 'rana', 's', 'h') RETURNING id",
      parameters: {'r': businessId},
    );
    expect(next.single[0], greaterThan(userId));
  });

  test('leaves nothing named after staff behind', () async {
    await PosMigrator(db).migrate(pg.config);

    // Names, not data: `staff.manage` is a capability string and stays.
    final leftovers = await db.query(pg.config, r'''
      SELECT 'relation', c.relname FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relname ILIKE '%staff%'
      UNION ALL
      SELECT 'constraint', con.conname FROM pg_constraint con
        JOIN pg_namespace n ON n.oid = con.connamespace
       WHERE n.nspname = 'public' AND con.conname ILIKE '%staff%'
      UNION ALL
      SELECT 'trigger', t.tgname FROM pg_trigger t
       WHERE NOT t.tgisinternal AND t.tgname ILIKE '%staff%'
      UNION ALL
      SELECT 'function', p.proname FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname ILIKE '%staff%'
      UNION ALL
      SELECT 'column', c.relname || '.' || a.attname FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'r'
         AND a.attnum > 0 AND NOT a.attisdropped
         AND a.attname ILIKE '%staff%'
    ''');
    expect(leftovers.map((r) => '${r[0]} ${r[1]}').toList(), isEmpty);
  });
}
