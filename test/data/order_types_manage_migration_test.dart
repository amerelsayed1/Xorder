@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/permissions.dart';

import 'pg_fixture.dart';

/// Migration 56: whoever managed settings may choose the order types (XORD-002).
///
/// The pane used to answer to `settings.manage`. The key it answers to now is
/// new, and a key added after a role exists reaches it only by a migration
/// saying so — otherwise every manager on an existing install loses the
/// order-types switch on the day of the update. Keyed on the OLD capability, not
/// on the role code, so a restaurant's own roles keep it too.
void main() {
  if (PgFixture.host == null) {
    test('order types key (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;

  setUp(() async {
    pg = await PgFixture.open('order_types_manage');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');
    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('ot', 'OT') RETURNING id",
    )).first[0]! as int;
  });

  tearDown(() => pg.close());

  Future<void> role(String code, Set<String> capabilities) => db.query(
    pg.config,
    'INSERT INTO pos_roles (restaurant_id, code, name_en, name_ar, '
    '  capabilities, is_system) '
    'VALUES (@r, @code, @code, @code, @capabilities, false)',
    parameters: {
      'r': restaurantId,
      'code': code,
      'capabilities': capabilities.toList(),
    },
  );

  Future<List<String>> held(String code) async => ((await db.query(
    pg.config,
    'SELECT capabilities FROM pos_roles WHERE restaurant_id = @r AND code = @code',
    parameters: {'r': restaurantId, 'code': code},
  )).first[0]! as List).cast<String>();

  Future<List<int>> before() async {
    await role('manager', {PosCapability.operate, PosCapability.settingsManage});
    await role('floor_lead', {PosCapability.operate, PosCapability.settingsManage});
    await role('cashier', {PosCapability.operate});
    await db.query(pg.config, 'DELETE FROM schema_migrations WHERE version = 56');
    return PosMigrator(db).migrate(pg.config);
  }

  test('every role that managed settings keeps the order types', () async {
    expect(await before(), [56]);
    expect(await held('manager'), contains(PosCapability.orderTypesManage));
    expect(await held('floor_lead'), contains(PosCapability.orderTypesManage),
        reason: "a restaurant's own role, not just the seeded ones");
  });

  test('a role that could not manage settings is not given it', () async {
    await before();
    expect(await held('cashier'), isNot(contains(PosCapability.orderTypesManage)));
  });

  test('nothing is taken away, and running it again adds it once', () async {
    await before();
    await db.query(pg.config, 'DELETE FROM schema_migrations WHERE version = 56');
    await PosMigrator(db).migrate(pg.config);

    final manager = await held('manager');
    expect(manager.where((c) => c == PosCapability.orderTypesManage), hasLength(1));
    expect(manager, containsAll([PosCapability.operate, PosCapability.settingsManage]));
  });
}
