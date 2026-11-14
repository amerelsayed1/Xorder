@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/postgres_site_licence.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// The licence a main device shares with its tablets, against a real server.
///
/// The child-terminal suite proves the wizard's side with an in-memory source;
/// this proves the SQL that source stands in for — the upsert a renewal relies
/// on, and the terminal count the seat check relies on.
void main() {
  if (PgFixture.host == null) {
    test(
      'site licence (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  late PgFixture pg;
  late PostgresSiteLicence table;
  late int businessId;
  late int branchId;

  setUpAll(() async {
    pg = await PgFixture.open('site_licence');
    await LocalBootstrap(pg.database).migrate(pg.config);
    table = PostgresSiteLicence(database: pg.database, config: pg.config);
  });

  setUp(() async {
    // Cascades to the licence row and the terminals.
    await pg.database.query(
      pg.config,
      "DELETE FROM pos_businesses WHERE slug = 'site-licence-test'",
    );
    final bootstrap = LocalBootstrap(pg.database);
    businessId = await bootstrap.seedBusiness(
      pg.config,
      slug: 'site-licence-test',
      name: 'Site Licence Test',
    );
    branchId = await bootstrap.seedBranch(
      pg.config,
      businessId: businessId,
      name: 'Main',
      code: 'MAIN',
    );
  });

  tearDownAll(() => pg.close());

  SiteLicenceRow licence(String payload, {String mode = 'offline'}) =>
      SiteLicenceRow(
        businessId: businessId,
        payload: payload,
        signature: 'sig-$payload',
        keyId: 'v1',
        mode: mode,
      );

  Future<void> addTerminal(String name) => pg.database.query(
    pg.config,
    'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
    'VALUES (@id, @business, @branch, @name)',
    parameters: {
      'id': const Uuid().v4(),
      'business': businessId,
      'branch': branchId,
      'name': name,
    },
  );

  test('nothing published reads as nothing, not as an error', () async {
    expect(await table.read(businessId: businessId), isNull);
  });

  test('a published licence reads back whole, found with or without the '
      'business', () async {
    await table.publish(licence('first'));

    final narrowed = await table.read(businessId: businessId);
    expect(narrowed?.payload, 'first');
    expect(narrowed?.signature, 'sig-first');
    expect(narrowed?.keyId, 'v1');
    expect(narrowed?.mode, 'offline');
    // A tablet being set up does not know its business yet.
    expect((await table.read())?.businessId, businessId);
  });

  test('a renewal replaces the row rather than adding a second', () async {
    await table.publish(licence('first'));
    await table.publish(licence('renewed', mode: 'cloud'));

    final rows = await pg.database.query(
      pg.config,
      'SELECT count(*) FROM pos_site_licence WHERE business_id = @r',
      parameters: {'r': businessId},
    );
    expect(rows.first[0], 1);
    final read = await table.read(businessId: businessId);
    expect(read?.payload, 'renewed');
    expect(read?.mode, 'cloud');
  });

  test('the terminals already registered are counted with it', () async {
    await table.publish(licence('first'));
    await addTerminal('Counter 1');
    await addTerminal('Tablet 1');

    expect((await table.read(businessId: businessId))?.terminalCount, 2);
  });
}
