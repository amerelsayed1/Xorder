import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/postgres_site_licence.dart';

import 'pg_fixture.dart';

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
  late int restaurantId;
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
      "DELETE FROM pos_restaurants WHERE slug = 'site-licence-test'",
    );
    final bootstrap = LocalBootstrap(pg.database);
    restaurantId = await bootstrap.seedRestaurant(
      pg.config,
      slug: 'site-licence-test',
      name: 'Site Licence Test',
    );
    branchId = await bootstrap.seedBranch(
      pg.config,
      restaurantId: restaurantId,
      name: 'Main',
      code: 'MAIN',
    );
  });

  tearDownAll(() => pg.close());

  SiteLicenceRow licence(String payload, {String mode = 'offline'}) =>
      SiteLicenceRow(
        restaurantId: restaurantId,
        payload: payload,
        signature: 'sig-$payload',
        keyId: 'v1',
        mode: mode,
      );

  Future<void> addTerminal(String name) => pg.database.query(
    pg.config,
    'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
    'VALUES (@id, @restaurant, @branch, @name)',
    parameters: {
      'id': const Uuid().v4(),
      'restaurant': restaurantId,
      'branch': branchId,
      'name': name,
    },
  );

  test('nothing published reads as nothing, not as an error', () async {
    expect(await table.read(restaurantId: restaurantId), isNull);
  });

  test('a published licence reads back whole, found with or without the '
      'restaurant', () async {
    await table.publish(licence('first'));

    final narrowed = await table.read(restaurantId: restaurantId);
    expect(narrowed?.payload, 'first');
    expect(narrowed?.signature, 'sig-first');
    expect(narrowed?.keyId, 'v1');
    expect(narrowed?.mode, 'offline');
    // A tablet being set up does not know its restaurant yet.
    expect((await table.read())?.restaurantId, restaurantId);
  });

  test('a renewal replaces the row rather than adding a second', () async {
    await table.publish(licence('first'));
    await table.publish(licence('renewed', mode: 'cloud'));

    final rows = await pg.database.query(
      pg.config,
      'SELECT count(*) FROM pos_site_licence WHERE restaurant_id = @r',
      parameters: {'r': restaurantId},
    );
    expect(rows.first[0], 1);
    final read = await table.read(restaurantId: restaurantId);
    expect(read?.payload, 'renewed');
    expect(read?.mode, 'cloud');
  });

  test('the terminals already registered are counted with it', () async {
    await table.publish(licence('first'));
    await addTerminal('Counter 1');
    await addTerminal('Tablet 1');

    expect((await table.read(restaurantId: restaurantId))?.terminalCount, 2);
  });
}
