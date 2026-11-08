@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_customers_repository.dart';

import 'pg_fixture.dart';

/// Migration 51 — who the food is for (POS-BE-014).
///
/// The invariant the database is asked to keep is the one that matters: one
/// person per number per business. A till that writes a duplicate locally
/// uploads a split the platform then has to merge, and a split directory is
/// invisible until somebody asks how often a regular orders.
/// Somebody who may add customers, and somebody who may sell but not add.
const _owner = PosStaff(
  id: 1,
  name: 'Amer',
  username: 'amer',
  role: PosRole(
    id: 1,
    code: SystemRoles.ownerCode,
    nameEn: 'Owner',
    capabilities: SystemRoles.owner,
  ),
);
const _sellsOnly = PosStaff(
  id: 2,
  name: 'Omar',
  username: 'omar',
  role: PosRole(
    id: 2,
    code: 'sells-only',
    nameEn: 'Sells only',
    capabilities: {PosCapability.operate},
  ),
);

void main() {
  if (PgFixture.host == null) {
    test('customers (skipped — set POS_PG_HOST)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late PostgresCustomersRepository customers;
  late int branchId;

  setUp(() async {
    pg = await PgFixture.open('customers');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_sync_outbox');
    await db.query(pg.config, 'DELETE FROM pos_customers');
    await db.query(pg.config, 'DELETE FROM pos_branches');
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('cust', 'Cust') "
      'RETURNING id',
    )).first[0] as int;

    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'C1', 'Main') RETURNING id",
      parameters: {'r': businessId},
    )).first[0] as int;

    customers = PostgresCustomersRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
    );
  });

  tearDown(() => pg.close());

  test('a number is a person, however it is typed', () async {
    final first = await customers.upsert(
      by: _owner,
      name: 'Amer',
      phone: '(010) 1694-3505',
      address: '12 Road 9',
    );

    // The same human, entered again in Arabic digits with a fuller name and
    // no address. One row, name corrected, address NOT blanked.
    final again = await customers.upsert(
      by: _owner,
      name: 'Amer El Sayed',
      phone: '٠١٠١٦٩٤٣٥٠٥',
    );

    expect(again.id, first.id, reason: 'one number is one person');
    expect(again.name, 'Amer El Sayed');
    expect(
      again.address,
      '12 Road 9',
      reason: 'a cashier who did not retype the address did not delete it',
    );

    final all = await customers.search('');
    expect(all.length, 1);
  });

  test('a customer with no usable number is refused, not stored', () async {
    await expectLater(
      customers.upsert(by: _owner, name: 'Nobody', phone: '---'),
      throwsArgumentError,
    );
    expect(await customers.search(''), isEmpty);
  });

  test('searching finds a name fragment or the tail of a number', () async {
    await customers.upsert(by: _owner, name: 'Amer El Sayed', phone: '01016943505');
    await customers.upsert(by: _owner, name: 'Mohamed Ali', phone: '01111111111');

    expect((await customers.search('3505')).single.name, 'Amer El Sayed');
    expect((await customers.search('el say')).single.name, 'Amer El Sayed');
    expect((await customers.search('MOHAMED')).single.name, 'Mohamed Ali');
    expect((await customers.search('٣٥٠٥')).single.name, 'Amer El Sayed');
    expect(await customers.search('nobody'), isEmpty);
  });

  test('an empty box offers the most recently seen first', () async {
    // The person the cashier wants is very often the last one served.
    await customers.upsert(by: _owner, name: 'First', phone: '01000000001');
    await customers.upsert(by: _owner, name: 'Second', phone: '01000000002');

    expect((await customers.search('')).first.name, 'Second');
  });

  group('telling the platform', () {
    test('a cloud till queues a customer it created', () async {
      final cloud = PostgresCustomersRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: branchId,
        syncsToPlatform: true,
      );
      await cloud.upsert(by: _owner, name: 'Amer', phone: '01016943505');

      final queued = await db.query(
        pg.config,
        "SELECT count(*) FROM pos_sync_outbox WHERE event_type = 'customer'",
      );
      expect(int.parse('${queued.first[0]}'), 1);
    });

    test('an offline till queues nothing — there is nobody to tell', () async {
      // And a backlog that is never drained would sit in the sync pill
      // forever, on a product whose whole point is that it does not need one.
      await customers.upsert(by: _owner, name: 'Amer', phone: '01016943505');

      final queued = await db.query(
        pg.config,
        "SELECT count(*) FROM pos_sync_outbox WHERE event_type = 'customer'",
      );
      expect(int.parse('${queued.first[0]}'), 0);
    });

    test('a customer who came DOWN in a bundle is never sent back up', () async {
      // They already have a platform_id. Re-posting them is a write the
      // platform has to resolve for nothing.
      await db.query(
        pg.config,
        'INSERT INTO pos_customers (business_id, client_transaction_id, '
        "  platform_id, name, phone) "
        "VALUES (@r, gen_random_uuid(), 77, 'Seeded', '01099999999')",
        parameters: {'r': businessId},
      );

      final cloud = PostgresCustomersRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: branchId,
        syncsToPlatform: true,
      );
      // The same person, corrected at the counter.
      await cloud.upsert(by: _owner, name: 'Seeded Again', phone: '01099999999');

      final queued = await db.query(
        pg.config,
        "SELECT count(*) FROM pos_sync_outbox WHERE event_type = 'customer'",
      );
      expect(int.parse('${queued.first[0]}'), 0);
    });
  });

  test('another business on the same branch server is invisible', () async {
    final other = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('other', 'Other') "
      'RETURNING id',
    )).first[0] as int;

    await customers.upsert(by: _owner, name: 'Ours', phone: '01016943505');
    await PostgresCustomersRepository(
      database: db,
      config: pg.config,
      businessId: other,
    ).upsert(by: _owner, name: 'Theirs', phone: '01016943505');

    // The same number in two businesses is two people — the unique index is
    // per business, and a branch server can hold more than one.
    expect((await customers.search('')).single.name, 'Ours');
  });

  test('somebody without customers.create writes nothing (XORD-001)', () async {
    await expectLater(
      customers.upsert(by: _sellsOnly, name: 'Nope', phone: '01099999999'),
      throwsA(isA<CustomerNotPermitted>()),
    );
    await expectLater(
      customers.upsert(by: null, name: 'Nobody signed in', phone: '01088888888'),
      throwsA(isA<CustomerNotPermitted>()),
      reason: 'an unattended till is not a till with every permission',
    );
    expect(await customers.search(''), isEmpty);
  });
}
