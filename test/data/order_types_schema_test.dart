@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_order_types_repository.dart';
import 'package:xorder_pos/domain/models/order_type_config.dart';
import 'package:xorder_pos/domain/models/ticket.dart';

import 'pg_fixture.dart';

/// Order types, stored (§31).
void main() {
  if (PgFixture.host == null) {
    test('order types (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresOrderTypesRepository types;
  late int restaurantId;

  const slug = 'order-types-test';

  setUp(() async {
    pg = await PgFixture.open('order_types');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES (@s, 'Types') "
      'RETURNING id',
      parameters: {'s': slug},
    )).first[0]! as int;

    // Created after the migration ran, exactly as a real install does.
    await LocalBootstrap(db).seedOrderTypes(pg.config, restaurantId);

    types = PostgresOrderTypesRepository(
      database: db,
      config: pg.config.copyWith(tenantSlug: slug),
      restaurantId: restaurantId,
    );
  });

  tearDown(() => pg.close());

  test('a restaurant created after the migration is still seeded', () async {
    // The bug migration 23 had, not repeated.
    final all = await types.all();
    expect(all.map((c) => c.type.wire), [
      'dine_in',
      'takeaway',
      'delivery',
      'drive_thru',
    ]);
  });

  test('what is seeded is exactly what the code calls seeded', () async {
    for (final stored in await types.all()) {
      final expected = OrderTypeConfig.seeded.firstWhere(
        (c) => c.type == stored.type,
      );
      expect(stored.nameEn, expected.nameEn, reason: stored.type.wire);
      expect(stored.nameAr, expected.nameAr, reason: stored.type.wire);
      expect(
        stored.requiresTable,
        expected.requiresTable,
        reason: stored.type.wire,
      );
      expect(
        stored.requiresAddress,
        expected.requiresAddress,
        reason: stored.type.wire,
      );
    }
  });

  test('seeding twice does not undo a rename', () async {
    await db.query(
      pg.config,
      "UPDATE pos_order_types SET name_en = 'Hall' WHERE code = 'dine_in'",
    );
    final created = await LocalBootstrap(db).seedOrderTypes(
      pg.config,
      restaurantId,
    );

    expect(created, 0);
    expect(
      (await types.all()).firstWhere((c) => c.type == OrderType.dineIn).nameEn,
      'Hall',
    );
  });

  test('a restaurant can move seating off dine-in', () async {
    // The whole point of §31: the rule stops being the type's name.
    await db.query(
      pg.config,
      "UPDATE pos_order_types SET requires_table = false WHERE code = 'dine_in'",
    );
    await db.query(
      pg.config,
      "UPDATE pos_order_types SET requires_table = true, name_en = 'Catering' "
      "WHERE code = 'drive_thru'",
    );

    final rules = OrderTypeRules(await types.all());
    expect(rules.requiresTable(OrderType.dineIn), isFalse);
    expect(rules.requiresTable(OrderType.driveThru), isTrue);
    expect(rules.hasSeating, isTrue);
  });

  test('a retired type is off the till and still in the editor', () async {
    await db.query(
      pg.config,
      "UPDATE pos_order_types SET is_active = false WHERE code = 'drive_thru'",
    );

    expect((await types.all()).map((c) => c.type.wire),
        isNot(contains('drive_thru')));
    expect(
      (await types.all(includeInactive: true)).map((c) => c.type.wire),
      contains('drive_thru'),
    );
  });

  test('a code this build does not know is dropped, not fatal', () async {
    // It has nowhere to be rendered, and a till must not refuse to sell
    // because a newer binary added one.
    await db.query(
      pg.config,
      'INSERT INTO pos_order_types (restaurant_id, code, name_en) '
      "VALUES (@r, 'catering', 'Catering')",
      parameters: {'r': restaurantId},
    );
    expect(await types.all(), hasLength(4));
  });

  test('one restaurant cannot hold the same code twice', () async {
    await expectLater(
      db.query(
        pg.config,
        'INSERT INTO pos_order_types (restaurant_id, code, name_en) '
        "VALUES (@r, 'dine_in', 'Again')",
        parameters: {'r': restaurantId},
      ),
      throwsA(isA<Object>()),
    );
  });

  test('two restaurants may each have dine-in', () async {
    final other = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('other', 'Other') "
      'RETURNING id',
    )).first[0]! as int;

    expect(
      await LocalBootstrap(db).seedOrderTypes(pg.config, other),
      4,
    );
    expect(await types.all(), hasLength(4), reason: 'and this one is unchanged');
  });
}
