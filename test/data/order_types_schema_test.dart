@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_order_types_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
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
  late PostgresCatalogAdminRepository admin;
  late int restaurantId;
  late int branchId;

  const manager = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {
        PosCapability.settingsManage,
        // Choosing order types is its own key since XORD-002.
        PosCapability.orderTypesManage,
      },
    ),
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.operate},
    ),
  );

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

    branchId = (await db.query(
      pg.config,
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    types = PostgresOrderTypesRepository(
      database: db,
      config: pg.config.copyWith(tenantSlug: slug),
      restaurantId: restaurantId,
    );
    admin = PostgresCatalogAdminRepository(
      database: db,
      config: pg.config.copyWith(tenantSlug: slug),
      restaurantId: restaurantId,
      branchId: branchId,
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

  group('editing one', () {
    OrderTypeConfig of(String wire) =>
        OrderTypeConfig(type: OrderType.fromWire(wire)!, nameEn: 'x');

    Future<OrderTypeConfig> current(String wire) async =>
        (await types.all(includeInactive: true))
            .firstWhere((c) => c.type.wire == wire);

    test('a rename lands on the row the code names', () async {
      final takeaway = await current('takeaway');
      final result = await admin.saveOrderType(
        OrderTypeConfig(
          type: takeaway.type,
          nameEn: 'Collection',
          nameAr: 'استلام',
          sortOrder: takeaway.sortOrder,
        ),
        by: manager,
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');

      final after = await current('takeaway');
      expect(after.nameEn, 'Collection');
      expect(after.nameAr, 'استلام');
      // And nothing else moved: the upsert is on the code, and four rows are
      // seeded, so an insert instead of an update would leave five.
      expect(await types.all(includeInactive: true), hasLength(4));
      expect((await current('dine_in')).nameEn, 'Dine in');
    });

    test('a table can be turned on for a type that had none', () async {
      // The switch that used to be `type == OrderType.dineIn` in three files. A
      // caterer who seats people turns it on for takeaway.
      expect((await current('takeaway')).requiresTable, isFalse);

      await admin.saveOrderType(
        OrderTypeConfig(
          type: OrderType.takeaway,
          nameEn: 'Catering',
          requiresTable: true,
        ),
        by: manager,
      );

      expect((await current('takeaway')).requiresTable, isTrue);
    });

    test('turning one off takes it off the till but keeps the row', () async {
      await admin.saveOrderType(
        OrderTypeConfig(
          type: OrderType.driveThru,
          nameEn: 'Drive-thru',
          isActive: false,
        ),
        by: manager,
      );

      expect(
        (await types.all()).map((c) => c.type.wire),
        isNot(contains('drive_thru')),
        reason: 'the till stops offering it',
      );
      expect(
        (await types.all(includeInactive: true)).map((c) => c.type.wire),
        contains('drive_thru'),
        reason: 'and the editor can turn it back on',
      );
    });

    test('the last one cannot be turned off', () async {
      // A restaurant with no active order type has a till that cannot start a
      // ticket, and the fix afterwards is a database edit by somebody who will
      // not know that is what they are doing.
      for (final wire in ['takeaway', 'delivery', 'drive_thru']) {
        final off = await admin.saveOrderType(
          OrderTypeConfig(
            type: OrderType.fromWire(wire)!,
            nameEn: wire,
            isActive: false,
          ),
          by: manager,
        );
        expect(off.succeeded, isTrue, reason: '$wire: ${off.refusal}');
      }

      final last = await admin.saveOrderType(
        const OrderTypeConfig(
          type: OrderType.dineIn,
          nameEn: 'Dine in',
          isActive: false,
        ),
        by: manager,
      );
      expect(last.succeeded, isFalse);
      expect((last.refusal! as CatalogInvalid).reason, contains('sellable'));
      expect((await types.all()), hasLength(1));
    });

    test('a nameless type is refused', () async {
      final result = await admin.saveOrderType(
        const OrderTypeConfig(type: OrderType.dineIn, nameEn: '  '),
        by: manager,
      );
      expect(result.succeeded, isFalse);
    });

    test('a cashier cannot change what the restaurant sells', () async {
      final result = await admin.saveOrderType(of('dine_in'), by: cashier);
      expect(result.refusal, isA<NotPermitted>());
      expect((await current('dine_in')).nameEn, 'Dine in');
    });

    test('settings.manage alone no longer chooses order types (XORD-002)', () async {
      const settingsOnly = PosStaff(
        id: 0,
        name: 'Omar',
        role: PosRole(
          id: 3,
          code: 'settings-only',
          nameEn: 'Settings only',
          capabilities: {PosCapability.settingsManage},
        ),
      );
      final result = await admin.saveOrderType(of('dine_in'), by: settingsOnly);
      expect((result.refusal! as NotPermitted).capability, PosCapability.orderTypesManage);
    });

    test('a type outside the licence cannot be switched ON', () async {
      // Delivery is off first; the licence covers dine-in and takeaway only.
      await admin.saveOrderType(
        const OrderTypeConfig(type: OrderType.delivery, nameEn: 'Delivery', isActive: false),
        by: manager,
      );
      final on = await admin.saveOrderType(
        const OrderTypeConfig(type: OrderType.delivery, nameEn: 'Delivery'),
        by: manager,
        entitled: {OrderType.dineIn, OrderType.takeaway},
      );
      expect((on.refusal! as CatalogInvalid).reason, contains('licence'));
      expect((await current('delivery')).isActive, isFalse);
    });

    test('a type the licence no longer covers can still be switched OFF', () async {
      final off = await admin.saveOrderType(
        const OrderTypeConfig(type: OrderType.delivery, nameEn: 'Delivery', isActive: false),
        by: manager,
        entitled: {OrderType.dineIn},
      );
      expect(off.succeeded, isTrue, reason: '${off.refusal}');
      expect((await current('delivery')).isActive, isFalse);
    });

    test('and one already on stays savable (a rename) when the licence lapses from it', () async {
      final rename = await admin.saveOrderType(
        const OrderTypeConfig(type: OrderType.delivery, nameEn: 'Home delivery'),
        by: manager,
        entitled: {OrderType.dineIn},
      );
      expect(rename.succeeded, isTrue, reason: '${rename.refusal}');
    });

    test('a cloud till is refused — the platform owns these', () async {
      final cloud = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: slug),
        restaurantId: restaurantId,
        branchId: branchId,
        offline: false,
      );
      final result = await cloud.saveOrderType(of('dine_in'), by: manager);
      expect(result.refusal, isA<NotPermitted>());
    });

    test('the change is audited — it changes what can be sold', () async {
      await admin.saveOrderType(
        const OrderTypeConfig(
          type: OrderType.delivery,
          nameEn: 'Delivery',
          requiresTable: true,
        ),
        by: manager,
      );

      // The newest row, not every row: `pos_audit_events` outlives the
      // restaurant delete this fixture does between tests, so the earlier
      // tests' rows are still here — which is the ledger behaving correctly.
      final rows = await db.query(
        pg.config,
        'SELECT after_value FROM pos_audit_events WHERE action = @a '
        'ORDER BY id DESC LIMIT 1',
        parameters: {'a': AuditAction.orderTypeSaved},
      );
      expect(rows, hasLength(1));
      expect('${rows.first[0]}', contains('requires_table'));
      expect('${rows.first[0]}', contains('delivery'));
    });
  });
}
