@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/money_config_codec.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// `jsonb` comes back decoded on some driver paths and as text on others.
Map<String, Object?> _payload(Object? raw) => switch (raw) {
      final Map map => map.cast<String, Object?>(),
      final String text => (jsonDecode(text) as Map).cast<String, Object?>(),
      _ => throw StateError('unreadable payload: $raw'),
    };

/// Authoring the menu on the till.
///
/// This is the feature an offline restaurant cannot trade without, and the one
/// the coordination docs previously ruled out — so what it refuses matters as
/// much as what it writes. Every test here is a question a restaurant would
/// actually ask: can I change a price, can I take something off sale without
/// losing what it sold, and can two managers on two tills overwrite each other.
void main() {
  if (PgFixture.host == null) {
    test('catalogue authoring (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresCatalogAdminRepository repository;
  late int restaurantId;
  late int categoryId;

  const slug = 'catalog-admin-test';

  /// Holds `catalog.manage`, as the owner and manager system roles do.
  const manager = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'amer',
    capabilities: {PosCapability.catalogManage},
  );

  /// Holds it not. A cashier may never reprice the food.
  const cashier = PosStaff(
    id: 2,
    name: 'Rana A.',
    username: 'rana',
    capabilities: {PosCapability.operate},
  );

  setUp(() async {
    pg = await PgFixture.open('catalog_admin');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    final restaurant = await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES (@slug, 'Catalog Test') "
      'RETURNING id',
      parameters: {'slug': slug},
    );
    restaurantId = restaurant.first[0]! as int;

    final branch = await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    );

    repository = PostgresCatalogAdminRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branch.first[0]! as int,
    );

    final saved = await repository.saveCategory(
      const Category(id: 0, nameEn: 'Hot Drinks', slug: 'hot-drinks'),
      by: manager,
    );
    categoryId = saved.value!.id;
  });

  tearDown(() => pg.close());

  Product draft({
    int id = 0,
    String name = 'Espresso',
    int price = 3500,
    Money? discounted,
  }) =>
      Product(
        id: id,
        categoryId: categoryId,
        nameEn: name,
        price: Money(price),
        discountedPrice: discounted,
      );

  group('what it writes', () {
    test('a category and an item reach the till catalogue', () async {
      final saved = await repository.saveProduct(draft(), by: manager);
      expect(saved.value, isNotNull);

      // Read back through the SAME repository the sale screen uses, not by
      // inspecting rows: what matters is that the cashier sees it.
      final catalog = await PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: slug),
      ).load();

      expect(catalog.categories.single.nameEn, 'Hot Drinks');
      expect(catalog.products.single.nameEn, 'Espresso');
      expect(catalog.products.single.price.minor, 3500);
    });

    test('a price change is audited as a reprice, with both amounts', () async {
      final saved = await repository.saveProduct(draft(), by: manager);
      await repository.saveProduct(
        saved.value!.copyWith(price: const Money(4000)),
        by: manager,
      );

      final rows = await db.query(
        pg.config,
        "SELECT action, before_value->>'price_minor', after_value->>'price_minor' "
        'FROM pos_audit_events WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityProduct},
      );

      // Not a generic `product.updated`: "who changed what this costs, and
      // when" is the question a disputed receipt asks, and it must be findable
      // without reading every edit ever made.
      expect(rows.first[0], AuditAction.productRepriced);
      expect(rows.first[1], '3500');
      expect(rows.first[2], '4000');
    });

    test('renaming without touching the price is not a reprice', () async {
      final saved = await repository.saveProduct(draft(), by: manager);
      await repository.saveProduct(
        saved.value!.copyWith(nameEn: 'Doppio'),
        by: manager,
      );

      final rows = await db.query(
        pg.config,
        'SELECT action FROM pos_audit_events WHERE entity_type = @e '
        'ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityProduct},
      );
      expect(rows.first[0], AuditAction.productUpdated);
    });

    test('archiving takes it off sale and keeps the row', () async {
      final saved = await repository.saveProduct(draft(), by: manager);
      final archived =
          await repository.archiveProduct(saved.value!, by: manager);

      expect(archived.value!.isAvailable, isFalse);
      // Still there: every past sale names this row, so it is hidden, never
      // removed.
      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_products WHERE id = @id',
        parameters: {'id': saved.value!.id},
      );
      expect(rows.first[0], 1);
    });
  });

  group('what it refuses', () {
    test('a cashier cannot touch the menu', () async {
      final result = await repository.saveProduct(draft(), by: cashier);

      expect(result.value, isNull);
      expect(result.refusal, isA<NotPermitted>());
      final rows = await db.query(
        pg.config, 'SELECT count(*) FROM pos_products');
      expect(rows.first[0], 0, reason: 'and nothing was written');
    });

    test('a cloud terminal cannot author at all', () async {
      // The provider will not build this outside offline, but the rule lives
      // here too: a rule that exists only in a provider is one the next caller
      // does not know about. On a cloud till the platform is the author and
      // the bootstrap seeder would wipe whatever this wrote.
      final cloud = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        restaurantId: restaurantId,
        offline: false,
      );

      final result = await cloud.saveProduct(draft(), by: manager);
      expect(result.refusal, isA<NotPermitted>());
    });

    test('an offer above the normal price is refused with a sentence', () async {
      // Valid SQL — `price_minor >= 0` holds for both — and wrong arithmetic,
      // so the database cannot catch this one.
      final result = await repository.saveProduct(
        draft(price: 3500, discounted: const Money(4000)),
        by: manager,
      );

      expect(result.refusal, isA<CatalogInvalid>());
      expect(
        (result.refusal! as CatalogInvalid).reason,
        contains('higher than'),
      );
    });

    test('an item edited on another till is refused, not overwritten', () async {
      final saved = await repository.saveProduct(draft(), by: manager);

      // The other till deletes it while this one holds a stale copy.
      await db.query(
        pg.config,
        'DELETE FROM pos_products WHERE id = @id',
        parameters: {'id': saved.value!.id},
      );

      final result = await repository.saveProduct(
        saved.value!.copyWith(price: const Money(9999)),
        by: manager,
      );
      expect(result.refusal, isA<EditedElsewhere>());
    });

    test('a nameless item is refused', () async {
      final result =
          await repository.saveProduct(draft(name: '   '), by: manager);
      expect(result.refusal, isA<CatalogInvalid>());
    });
  });

  group('money rules', () {
    /// Holds `settings.manage` — a different job from pricing a plate.
    const owner = PosStaff(
      id: 3,
      name: 'Owner',
      username: 'owner',
      capabilities: {
        PosCapability.settingsManage,
        PosCapability.catalogManage,
      },
    );

    test('what is saved is what the ticket then prices with', () async {
      // The property that matters. An offline till with nothing written here
      // silently prices from a hardcoded 12%/14% and prints `deviceConfig` on
      // every slip; a LOSSY encode would be worse still, charging an amount
      // nobody chose.
      const wanted = TaxConfig(
        serviceBp: 1000,
        vatBp: 1400,
        serviceDineInOnly: true,
      );

      final saved = await repository.saveMoneyConfig(wanted, by: owner);
      expect(saved.value, isNotNull);

      final rows = await db.query(
        pg.config,
        'SELECT payload FROM pos_money_config WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      final readBack = MoneyConfigCodec.toTaxConfig(_payload(rows.first[0]));

      expect(readBack.serviceBp, 1000);
      expect(readBack.vatBp, 1400);
      expect(readBack.serviceDineInOnly, isTrue);
      // And it is no longer the device default the receipt has to disclose.
      expect(readBack.source, TaxSource.server);
    });

    test('a service charge on every order type round-trips', () async {
      // `serviceDineInOnly` defaults to TRUE, so a takeaway-inclusive charge
      // has to say so explicitly — which is exactly the bit that has to
      // survive the encode.
      const wanted = TaxConfig(
        serviceBp: 500,
        vatBp: 0,
        serviceDineInOnly: false,
      );
      await repository.saveMoneyConfig(wanted, by: owner);

      final rows = await db.query(
        pg.config,
        'SELECT payload FROM pos_money_config WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      final readBack = MoneyConfigCodec.toTaxConfig(_payload(rows.first[0]));

      expect(readBack.serviceDineInOnly, isFalse);
      expect(readBack.vatBp, 0, reason: 'no tax configured means no tax');
    });

    test('a manager without settings.manage cannot change the rates', () async {
      // `catalog.manage` prices a plate. It does not set the tax rate.
      final result = await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 9900, vatBp: 0),
        by: manager,
      );
      expect(result.refusal, isA<NotPermitted>());
    });

    test('the change is audited with both rates', () async {
      await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 1200, vatBp: 1400),
        by: owner,
      );
      await repository.saveMoneyConfig(
        const TaxConfig(serviceBp: 0, vatBp: 1400),
        by: owner,
      );

      final rows = await db.query(
        pg.config,
        "SELECT before_value->>'service_bp', after_value->>'service_bp' "
        'FROM pos_audit_events WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityMoney},
      );
      expect(rows.first[0], '1200');
      expect(rows.first[1], '0');
    });
  });

  group('the floor', () {
    const owner = PosStaff(
      id: 3,
      name: 'Owner',
      username: 'owner',
      capabilities: {PosCapability.settingsManage},
    );

    test('a table reaches the floor the waiter sees', () async {
      final saved = await repository.saveTable(
        const DiningTable(id: 0, label: 'T1', seats: 4, areaName: 'Terrace'),
        by: owner,
      );
      expect(saved.value!.label, 'T1');

      final rows = await db.query(
        pg.config,
        'SELECT label, seats, area_name FROM pos_dining_tables '
        'WHERE restaurant_id = @r',
        parameters: {'r': restaurantId},
      );
      expect(rows.first[0], 'T1');
      expect(rows.first[1], 4);
      expect(rows.first[2], 'Terrace');
    });

    test('two tables cannot share a label in one branch', () async {
      // The label is what a waiter says out loud. Two tables called 6 is an
      // argument at the pass, so the unique key is named rather than thrown.
      await repository.saveTable(
        const DiningTable(id: 0, label: 'T1', seats: 2),
        by: owner,
      );
      final second = await repository.saveTable(
        const DiningTable(id: 0, label: 'T1', seats: 4),
        by: owner,
      );

      expect(second.refusal, isA<CatalogInvalid>());
      expect((second.refusal! as CatalogInvalid).reason, contains('already'));
    });

    test('a table with no seats is refused', () async {
      final result = await repository.saveTable(
        const DiningTable(id: 0, label: 'T9', seats: 0),
        by: owner,
      );
      expect(result.refusal, isA<CatalogInvalid>());
    });

    test('archiving keeps the row, because tickets name it', () async {
      final saved = await repository.saveTable(
        const DiningTable(id: 0, label: 'T2', seats: 2),
        by: owner,
      );
      await repository.archiveTable(saved.value!, by: owner);

      final rows = await db.query(
        pg.config,
        'SELECT is_active FROM pos_dining_tables WHERE id = @id',
        parameters: {'id': saved.value!.id},
      );
      expect(rows.first[0], isFalse, reason: 'hidden');
      expect(rows.length, 1, reason: 'and still there');
    });

    test('a manager without settings.manage cannot move the furniture', () async {
      final result = await repository.saveTable(
        const DiningTable(id: 0, label: 'T3', seats: 2),
        by: manager,
      );
      expect(result.refusal, isA<NotPermitted>());
    });
  });
}
