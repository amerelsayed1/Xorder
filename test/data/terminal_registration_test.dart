@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_directory_repositories.dart';
import 'package:xorder_pos/data/postgres/postgres_site_licence.dart';

import 'pg_fixture.dart';

/// Registering a till by hand is an upsert on the machine, not an insert per
/// attempt (P0-4).
///
/// **The defect behind this file.** `registerManually` minted a fresh terminal
/// id on every call, so a wizard that was retried, killed and re-run, or run
/// again after a reset left one `pos_terminals` row per attempt. A child's seat
/// check counts those rows against `max_terminals`, so a restaurant with three
/// tablets could be told every seat was taken. The registration now carries
/// the machine's installation id, and a unique index scoped to the restaurant
/// makes the second attempt land on the first attempt's row.
void main() {
  if (PgFixture.host == null) {
    test(
      'terminal registration (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  const slug = 'registration-test';
  const pin = '2468';

  // Per checkout, because roles are cluster-wide — see `PgFixture.roleFor`.
  final role = PgFixture.roleFor('registration_till');
  const rolePassword = 'probe-only';

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int otherBranchId;

  Future<void> dropRole() async {
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

  setUpAll(() async {
    pg = await PgFixture.open('terminal_registration');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);

    // A role holding the till's grants and nothing else: registration runs on
    // the till credential, and ON CONFLICT DO UPDATE needs UPDATE as well as
    // INSERT. A superuser fixture would pass whatever the grants said.
    await dropRole();
    await db.query(
      pg.config,
      'CREATE ROLE "$role" LOGIN PASSWORD \'$rolePassword\'',
    );
    for (final statement in LocalBootstrap.tillGrants(
      database: pg.config.databaseName,
      role: role,
      cloudSeeding: false,
    )) {
      await db.query(pg.config, statement);
    }
  });

  tearDownAll(() async {
    await dropRole();
    await db.close();
  });

  setUp(() async {
    // Cascades to the branches, the staff, the terminals and the licence.
    await db.query(
      pg.config,
      "DELETE FROM pos_restaurants WHERE slug IN (@slug, 'registration-other')",
      parameters: {'slug': slug},
    );
    final bootstrap = LocalBootstrap(db);
    restaurantId = await bootstrap.seedRestaurant(
      pg.config,
      slug: slug,
      name: 'Registration Test',
    );
    branchId = await bootstrap.seedBranch(
      pg.config,
      restaurantId: restaurantId,
      name: 'Main',
      code: 'MAIN',
    );
    otherBranchId = await bootstrap.seedBranch(
      pg.config,
      restaurantId: restaurantId,
      name: 'Other',
      code: 'OTHER',
    );

    final salt = PinHash.newSalt();
    await db.query(
      pg.config,
      'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, '
      'pin_salt, pin_hash, capabilities) '
      "VALUES (@r, @b, 'Sara M.', 'sara', @salt, @hash, ARRAY['pos.operate'])",
      parameters: {
        'r': restaurantId,
        'b': branchId,
        'salt': salt,
        'hash': await PinHash.hash(pin, salt),
      },
    );
  });

  PostgresProvisioningRepository provisioning() =>
      PostgresProvisioningRepository(database: db, config: pg.config);

  Future<String> register(
    String? installId, {
    String name = 'Counter 1',
    int? branch,
    PostgresProvisioningRepository? through,
  }) async {
    final result = await (through ?? provisioning()).registerManually(
      tenantSlug: slug,
      username: 'sara',
      password: pin,
      terminalName: name,
      branchId: branch ?? branchId,
      installId: installId,
    );
    expect(result.succeeded, isTrue, reason: result.message);
    return result.claim!.terminalId;
  }

  Future<int> terminals() async {
    final rows = await db.query(
      pg.config,
      'SELECT count(*) FROM pos_terminals WHERE restaurant_id = @r',
      parameters: {'r': restaurantId},
    );
    return rows.first[0]! as int;
  }

  test('the same machine registering twice is one terminal, with one id', () async {
    final first = await register('install-a');
    // Renamed and moved on the second run: the installer went back and
    // changed both. The row follows; the id does not change, because it is
    // what every order and shift from this till already carries.
    final second = await register(
      'install-a',
      name: 'Counter 1 (bar)',
      branch: otherBranchId,
    );

    expect(second, first);
    expect(await terminals(), 1);

    final row = await db.query(
      pg.config,
      'SELECT name, branch_id, install_id, claimed_at IS NOT NULL '
      'FROM pos_terminals WHERE id = @id',
      parameters: {'id': first},
    );
    expect(row.first[0], 'Counter 1 (bar)');
    expect(row.first[1], otherBranchId);
    expect(row.first[2], 'install-a');
    expect(row.first[3], isTrue);
  });

  test('two machines are two terminals', () async {
    final a = await register('install-a');
    final b = await register('install-b', name: 'Counter 2');

    expect(a, isNot(b));
    expect(await terminals(), 2);
  });

  test('a re-run does not move the count max_terminals is checked against', () async {
    // The number a child's seat check reads (`PostgresSiteLicence`), so the
    // assertion is on the figure the refusal is made from rather than on a
    // count this file wrote for itself.
    final licence = PostgresSiteLicence(database: db, config: pg.config);
    await licence.publish(
      SiteLicenceRow(
        restaurantId: restaurantId,
        payload: 'payload',
        signature: 'signature',
        keyId: 'v1',
        mode: 'offline',
      ),
    );

    await register('install-a');
    final before = (await licence.read(restaurantId: restaurantId))!;
    await register('install-a');
    await register('install-a');
    final after = (await licence.read(restaurantId: restaurantId))!;

    expect(before.terminalCount, 1);
    expect(after.terminalCount, before.terminalCount);
  });

  test('the till credential can re-register, not only the owner', () async {
    final till = PosDatabase(credentials: InMemoryPosDbCredentials(rolePassword));
    addTearDown(till.close);
    final asTill = PostgresProvisioningRepository(
      database: till,
      config: pg.config.copyWith(databaseUser: role),
    );

    final first = await register('install-a', through: asTill);
    final second = await register('install-a', name: 'Renamed', through: asTill);

    expect(second, first);
    expect(await terminals(), 1);
  });

  test('without an install id it is the old behaviour, a row per call', () async {
    // Kept on purpose for a caller that genuinely has no installation behind
    // it; the wizard always sends one.
    await register(null);
    await register(null);
    await register('');

    expect(await terminals(), 3);
  });

  test('the same install id in another restaurant is another terminal', () async {
    // A machine moved to a different restaurant's database is a new seat
    // there, not the old restaurant's till.
    final other = await LocalBootstrap(db).seedRestaurant(
      pg.config,
      slug: 'registration-other',
      name: 'Registration Other',
    );
    final otherBranch = await LocalBootstrap(db).seedBranch(
      pg.config,
      restaurantId: other,
      name: 'Main',
      code: 'MAIN',
    );
    await register('install-a');
    await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name, install_id) '
      "VALUES (@id, @r, @b, 'Elsewhere', 'install-a')",
      parameters: {'id': const Uuid().v4(), 'r': other, 'b': otherBranch},
    );

    expect(await terminals(), 1);
  });

  test('going round the repository cannot make a second row either', () async {
    // The rule is the index, not the Dart: a second writer that INSERTs
    // without ON CONFLICT is refused rather than quietly spending a seat.
    await register('install-a');

    await expectLater(
      db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name, install_id) '
        "VALUES (@id, @r, @b, 'Duplicate', 'install-a')",
        parameters: {
          'id': const Uuid().v4(),
          'r': restaurantId,
          'b': branchId,
        },
      ),
      throwsA(
        isA<PosDbException>().having(
          (e) => '${e.raw}',
          'raw',
          contains('pos_terminals_install_id_unique'),
        ),
      ),
    );
    expect(await terminals(), 1);

    // Legacy rows are untouched by the index: any number may lack an id.
    for (var i = 0; i < 2; i++) {
      await db.query(
        pg.config,
        'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
        "VALUES (@id, @r, @b, 'Legacy')",
        parameters: {
          'id': const Uuid().v4(),
          'r': restaurantId,
          'b': branchId,
        },
      );
    }
    expect(await terminals(), 3);
  });
}
