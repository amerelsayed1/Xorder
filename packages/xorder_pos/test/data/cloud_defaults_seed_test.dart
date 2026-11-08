@Tags(['integration'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/order_type_config.dart';
import 'package:xorder_pos/domain/models/reason_code.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// What a cloud till seeds for itself after the bundle lands.
///
/// The bundle authors the business and `BootstrapSeeder` writes it; the
/// reasons behind a void or a pay-out and what each kind of order requires
/// are the till's own, and the cloud wizard never seeded them — so every
/// cloud till opened with an empty list behind those dialogs.
void main() {
  if (PgFixture.host == null) {
    test('cloud defaults (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;

  setUp(() async {
    pg = await PgFixture.open('cloud_defaults');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    // As the seeder leaves it: a business row the bundle created, and
    // nothing of the till's own beside it.
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('cloud-defaults', 'Cloud') "
      'RETURNING id',
    )).first[0]! as int;
  });

  tearDown(() => pg.close());

  /// The provider's own function, as the wizard calls it. The fixture's role
  /// stands in for the administrator: the seeder connects as
  /// `adminDatabaseUser`, and the fixture's user owns this database.
  Future<void> seed() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(cloudDefaultsSeederProvider)(
      pg.config.copyWith(adminDatabaseUser: PgFixture.user),
      PgFixture.password,
      businessId,
    );
  }

  Future<int> count(String sql, [Map<String, Object?> extra = const {}]) async =>
      (await db.query(
        pg.config,
        sql,
        parameters: {'r': businessId, ...extra},
      )).first[0]! as int;

  test('a cloud restaurant gets its reasons and its order types', () async {
    await seed();

    for (final scope in SystemReasons.seededScopes) {
      expect(
        await count(
          'SELECT count(*) FROM pos_reason_codes '
          'WHERE business_id = @r AND scope = @s',
          {'s': scope.wire},
        ),
        SystemReasons.seededFor(scope).length,
        reason: scope.wire,
      );
    }
    expect(
      await count('SELECT count(*) FROM pos_order_types WHERE business_id = @r'),
      OrderTypeConfig.seeded.length,
    );
  });

  test("and no tax group: the platform's money config is the rate", () async {
    await seed();

    // `TaxConfig.defaultTaxGroup` prefers a stored `is_default` row over the
    // money config's `vatBp`, so a local 14% here would override whatever the
    // dashboard set for every product the bundle delivers.
    expect(
      await count('SELECT count(*) FROM pos_tax_groups WHERE business_id = @r'),
      0,
    );
  });

  test('seeding again keeps what the restaurant edited', () async {
    await seed();
    await db.query(
      pg.config,
      "UPDATE pos_reason_codes SET name_en = 'Comped by Amer' "
      "WHERE business_id = @r AND scope = 'void' AND sort_order = 1",
      parameters: {'r': businessId},
    );

    // "Try again" on the connecting screen, or "Download menu" on the summary.
    await seed();

    expect(
      await count(
        'SELECT count(*) FROM pos_reason_codes '
        "WHERE business_id = @r AND name_en = 'Comped by Amer'",
      ),
      1,
    );
    expect(
      await count('SELECT count(*) FROM pos_order_types WHERE business_id = @r'),
      OrderTypeConfig.seeded.length,
      reason: 'DO NOTHING on the code: no duplicates on a re-run',
    );
  });
}
