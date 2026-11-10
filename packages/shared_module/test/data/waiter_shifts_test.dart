@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_waiter_devices.dart';
import 'package:shared_module/data/postgres/postgres_waiter_shifts.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;
import 'package:xorder_pos_test_support/pg_fixture.dart';

/// The waiter shift clock on the real engine (migration 66). Runs on
/// PostgreSQL and, with `POS_TEST_ENGINE=sqlite`, on a cloud till's file.
void main() {
  if (PgFixture.host == null) {
    test('waiter shifts (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const slug = 'waiter-shifts-test';
  late PgFixture pg;
  late SqlDatabase db;
  late PostgresWaiterShifts shifts;
  late int businessId;
  late int branchId;
  late int mona;
  late int sami;
  late int phone;

  setUpAll(() async {
    pg = await PgFixture.open('waiter_shifts');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
  });

  tearDownAll(() => db.close());

  Future<int> user(String name) async {
    final row = await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, branch_id, name, username, pin_salt, pin_hash) '
      "VALUES (@b, @br, @n, @u, 'salt', 'hash') RETURNING id",
      parameters: {'b': businessId, 'br': branchId, 'n': name, 'u': name.toLowerCase()},
    );
    return row.single[0]! as int;
  }

  setUp(() async {
    await db.query(
      pg.config,
      "DELETE FROM pos_waiter_shifts WHERE business_id IN (SELECT id FROM pos_businesses WHERE slug IN (@slug, 'waiter-shifts-other'))",
      parameters: {'slug': slug},
    );
    await db.query(
      pg.config,
      "DELETE FROM pos_businesses WHERE slug IN (@slug, 'waiter-shifts-other')",
      parameters: {'slug': slug},
    );
    final bootstrap = LocalBootstrap(db);
    businessId = await bootstrap.seedBusiness(pg.config, slug: slug, name: 'Waiter Shifts');
    branchId = await bootstrap.seedBranch(pg.config, businessId: businessId, name: 'Main', code: 'MAIN');
    mona = await user('Mona');
    sami = await user('Sami');
    final (device, _) = await PostgresWaiterDevices(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    ).register('Phone 1');
    phone = device.id;
    shifts = PostgresWaiterShifts(database: db, config: pg.config, businessId: businessId, branchId: branchId);
  });

  test('start opens a shift once; finish closes it and stamps the time', () async {
    expect(await shifts.open(mona), isNull);
    final started = await shifts.start(mona, deviceId: phone);
    expect(started.isOpen, isTrue);
    expect((await shifts.start(mona, deviceId: phone)).id, started.id, reason: 'never two open shifts');
    expect((await shifts.open(mona))!.id, started.id);
    expect(await shifts.open(sami), isNull, reason: "one waiter's shift is theirs alone");

    final finished = await shifts.finish(mona, deviceId: phone);
    expect(finished!.id, started.id);
    expect(finished.endedAt, isNotNull);
    expect(finished.endedAt!.isBefore(finished.startedAt), isFalse);
    expect(await shifts.open(mona), isNull);
    expect(await shifts.finish(mona), isNull, reason: 'nothing open to finish');

    final next = await shifts.start(mona);
    expect(next.id, isNot(started.id), reason: 'a finished shift is not reopened');
  });

  test('the database refuses a second open shift for one person', () async {
    await shifts.start(mona);
    await expectLater(
      db.query(
        pg.config,
        'INSERT INTO pos_waiter_shifts (business_id, branch_id, user_id) VALUES (@b, @br, @u)',
        parameters: {'b': businessId, 'br': branchId, 'u': mona},
      ),
      throwsA(anything),
    );
  });

  test('the listing names the waiter and handhelds, newest first, open ones included', () async {
    final a = await shifts.start(mona, deviceId: phone);
    await shifts.finish(mona, deviceId: phone);
    final b = await shifts.start(sami, deviceId: phone);

    final now = DateTime.now().toUtc();
    final listed = await shifts.between(now.subtract(const Duration(days: 1)), now.add(const Duration(days: 1)));
    expect([for (final s in listed) s.id], [b.id, a.id]);
    expect(listed.first.staffName, 'Sami');
    expect(listed.first.isOpen, isTrue);
    expect(listed.last.staffName, 'Mona');
    expect(listed.last.startedDevice, 'Phone 1');
    expect(listed.last.endedDevice, 'Phone 1');

    final before = await shifts.between(now.subtract(const Duration(days: 3)), now.subtract(const Duration(days: 2)));
    expect(before, isEmpty, reason: 'outside the range');
  });

  test("another business's shifts are not this one's", () async {
    await shifts.start(mona);
    final bootstrap = LocalBootstrap(db);
    final other = await bootstrap.seedBusiness(pg.config, slug: 'waiter-shifts-other', name: 'Other');
    final otherBranch = await bootstrap.seedBranch(pg.config, businessId: other, name: 'O', code: 'OTH');
    final theirs = PostgresWaiterShifts(database: db, config: pg.config, businessId: other, branchId: otherBranch);
    expect(await theirs.open(mona), isNull);
    final now = DateTime.now().toUtc();
    expect(await theirs.between(now.subtract(const Duration(days: 1)), now.add(const Duration(days: 1))), isEmpty);
  });
}
