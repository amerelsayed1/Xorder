@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_waiter_devices.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;
import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Paired waiter handhelds, on the real engine (waiter-app, migration 65).
/// Runs on PostgreSQL and, with `POS_TEST_ENGINE=sqlite`, on a cloud till's
/// file: both host handhelds.
void main() {
  if (PgFixture.host == null) {
    test('waiter devices (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const slug = 'waiter-devices-test';
  late PgFixture pg;
  late SqlDatabase db;
  late PostgresWaiterDevices devices;
  late int businessId;
  late int branchId;

  setUpAll(() async {
    pg = await PgFixture.open('waiter_devices');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
  });

  tearDownAll(() => db.close());

  setUp(() async {
    await db.query(
      pg.config,
      "DELETE FROM pos_businesses WHERE slug IN (@slug, 'waiter-devices-other')",
      parameters: {'slug': slug},
    );
    final bootstrap = LocalBootstrap(db);
    businessId = await bootstrap.seedBusiness(pg.config, slug: slug, name: 'Waiter Devices');
    branchId = await bootstrap.seedBranch(pg.config, businessId: businessId, name: 'Main', code: 'MAIN');
    devices = PostgresWaiterDevices(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  test('a paired device is found by its token, and only the hash is stored', () async {
    final (device, token) = await devices.register('  Phone 1 ');
    expect(device.name, 'Phone 1');
    expect(device.isRevoked, isFalse);
    expect(token.length, greaterThanOrEqualTo(40));

    expect((await devices.byToken(token))!.id, device.id);
    expect(await devices.byToken('not-a-token'), isNull);
    expect(await devices.byToken(''), isNull);

    final stored = await db.query(
      pg.config,
      'SELECT token_hash FROM pos_waiter_devices WHERE id = @id',
      parameters: {'id': device.id},
    );
    expect(stored.single[0], PostgresWaiterDevices.hashOf(token));
    expect(stored.single[0], isNot(token));
  });

  test('two devices get two tokens; the list is newest first', () async {
    final (a, tokenA) = await devices.register('Phone A');
    final (b, tokenB) = await devices.register('Phone B');
    expect(tokenA, isNot(tokenB));
    expect([for (final d in await devices.all()) d.id], [b.id, a.id]);
  });

  test('revoking keeps the device on record, revoked, and keeps its first date', () async {
    final (device, token) = await devices.register('Phone');
    await devices.revoke(device.id);
    final revoked = await devices.byToken(token);
    expect(revoked!.isRevoked, isTrue);

    final firstDate = revoked.revokedAt;
    await devices.revoke(device.id);
    expect((await devices.byToken(token))!.revokedAt, firstDate);
    expect(await devices.all(), hasLength(1));
  });

  test('touching a device stamps when it was last seen', () async {
    final (device, token) = await devices.register('Phone');
    expect(device.lastSeenAt, isNull);
    await devices.touch(device.id);
    expect((await devices.byToken(token))!.lastSeenAt, isNotNull);
  });

  test("another business's token opens nothing here", () async {
    final bootstrap = LocalBootstrap(db);
    final other = await bootstrap.seedBusiness(pg.config, slug: 'waiter-devices-other', name: 'Other');
    final otherBranch = await bootstrap.seedBranch(pg.config, businessId: other, name: 'O', code: 'OTH');
    final (_, token) = await PostgresWaiterDevices(
      database: db,
      config: pg.config,
      businessId: other,
      branchId: otherBranch,
    ).register('Their phone');
    expect(await devices.byToken(token), isNull);
  });

  test('a blank name is refused by the database', () async {
    await expectLater(devices.register('   '), throwsA(anything));
  });
}
