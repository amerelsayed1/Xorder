@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/domain/models/permissions.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// Migration 56: whoever managed settings may choose the order types (XORD-002).
///
/// The pane used to answer to `settings.manage`. The key it answers to now is
/// new, and a key added after a role exists reaches it only by a migration
/// saying so — otherwise every manager on an existing install loses the
/// order-types switch on the day of the update. Keyed on the OLD capability, not
/// on the role code, so a business's own roles keep it too.
void main() {
  if (PgFixture.host == null) {
    test('order types key (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;

  setUp(() async {
    pg = await PgFixture.open('order_types_manage');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('ot', 'OT') RETURNING id",
    )).first[0]! as int;
  });

  tearDown(() => pg.close());

  Future<void> role(String code, Set<String> capabilities) => db.query(
    pg.config,
    // Version 55's names: these run before migration 64.
    'INSERT INTO pos_roles (restaurant_id, code, name_en, name_ar, '
    '  capabilities, is_system) '
    'VALUES (@r, @code, @code, @code, @capabilities, false)',
    parameters: {
      'r': businessId,
      'code': code,
      'capabilities': capabilities.toList(),
    },
  );

  Future<List<String>> held(String code) async => ((await db.query(
    pg.config,
    'SELECT capabilities FROM pos_roles WHERE restaurant_id = @r AND code = @code',
    parameters: {'r': businessId, 'code': code},
  )).first[0]! as List).cast<String>();

  /// A database as 55 left it, with roles on it, brought up to 56.
  ///
  /// Rebuilt rather than rewound: 56 names `pos_staff`, which 62 renamed, so it
  /// can only run on a schema from before 62 — which is the only kind of
  /// database it will ever meet.
  Future<List<int>> upTo56() =>
      PosMigrator(db, migrations: posMigrations.where((m) => m.version <= 56).toList())
          .migrate(pg.config);

  Future<List<int>> before() async {
    await db.query(pg.config, 'DROP SCHEMA public CASCADE');
    await db.query(pg.config, 'CREATE SCHEMA public');
    await PosMigrator(
      db,
      migrations: posMigrations.where((m) => m.version < 56).toList(),
    ).migrate(pg.config);
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('ot', 'OT') RETURNING id",
    )).first[0]! as int;
    await role('manager', {PosCapability.operate, PosCapability.settingsManage});
    await role('floor_lead', {PosCapability.operate, PosCapability.settingsManage});
    await role('cashier', {PosCapability.operate});
    return upTo56();
  }

  test('every role that managed settings keeps the order types', () async {
    expect(await before(), [56]);
    expect(await held('manager'), contains(PosCapability.orderTypesManage));
    expect(await held('floor_lead'), contains(PosCapability.orderTypesManage),
        reason: "a business's own role, not just the seeded ones");
  });

  test('a role that could not manage settings is not given it', () async {
    await before();
    expect(await held('cashier'), isNot(contains(PosCapability.orderTypesManage)));
  });

  test('nothing is taken away, and running it again adds it once', () async {
    await before();
    await db.query(pg.config, 'DELETE FROM schema_migrations WHERE version = 56');
    await upTo56();

    final manager = await held('manager');
    expect(manager.where((c) => c == PosCapability.orderTypesManage), hasLength(1));
    expect(manager, containsAll([PosCapability.operate, PosCapability.settingsManage]));
  });
}
