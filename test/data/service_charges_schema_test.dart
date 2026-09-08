@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_service_charges_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/service_charge.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// Service charges, stored (§38).
///
/// The constraint worth having a real server for is the one that says a charge
/// is a percentage **or** a fixed amount: "12% or 20 EGP, whichever" is a
/// question the model would be asking and nobody has answered.
void main() {
  if (PgFixture.host == null) {
    test('service charges (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresServiceChargesRepository charges;
  late int restaurantId;

  const slug = 'service-charges-test';

  const owner = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.settingsManage},
    ),
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    capabilities: {PosCapability.operate},
  );

  setUp(() async {
    pg = await PgFixture.open('service_charges');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES (@s, 'Charges') "
      'RETURNING id',
      parameters: {'s': slug},
    )).first[0]! as int;

    final branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    charges = PostgresServiceChargesRepository(
      database: db,
      config: pg.config,
      readDatabase: db,
      readConfig: pg.config.copyWith(tenantSlug: slug),
      adminAvailable: true,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  test('a restaurant starts with none, which means it keeps its old rate',
      () async {
    // Deliberately not seeded from `pos_money_config`. Seeding a row would look
    // harmless and would not be: the two would drift, and somebody editing the
    // old screen would wonder why the bill did not change.
    expect(await charges.all(), isEmpty);
  });

  test('a percentage charge round-trips', () async {
    final result = await charges.save(
      const ServiceCharge(
        id: 0,
        nameEn: 'Service',
        nameAr: 'خدمة',
        rateBp: 1200,
        orderTypes: {OrderType.dineIn},
      ),
      by: owner,
    );

    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    final stored = (await charges.all()).single;
    expect(stored.rateBp, 1200);
    expect(stored.fixedMinor, isNull);
    expect(stored.orderTypes, {OrderType.dineIn});
    expect(stored.displayName('ar'), 'خدمة');
  });

  test('a fixed charge round-trips', () async {
    await charges.save(
      const ServiceCharge(
        id: 0,
        nameEn: 'Delivery',
        fixedMinor: 2000,
        orderTypes: {OrderType.delivery},
        isTaxable: false,
      ),
      by: owner,
    );

    final stored = (await charges.all()).single;
    expect(stored.isFixed, isTrue);
    expect(stored.fixedMinor, 2000);
    expect(stored.isTaxable, isFalse);
  });

  test('no order types stored means every one', () async {
    await charges.save(
      const ServiceCharge(id: 0, nameEn: 'Service', rateBp: 1000),
      by: owner,
    );
    final stored = (await charges.all()).single;

    expect(stored.orderTypes, isEmpty);
    for (final type in OrderType.values) {
      expect(stored.appliesTo(type), isTrue, reason: type.wire);
    }
  });

  test('an order type this build does not know is dropped, not fatal',
      () async {
    // A restaurant that adds one on a newer binary must not stop an older till
    // from selling.
    await charges.save(
      const ServiceCharge(id: 0, nameEn: 'Service', rateBp: 1000),
      by: owner,
    );
    await db.query(
      pg.config,
      "UPDATE pos_service_charges SET order_types = ARRAY['dine_in', 'catering']",
    );

    expect((await charges.all()).single.orderTypes, {OrderType.dineIn});
  });

  group('what the database refuses', () {
    Future<void> raw(String rateBp, String fixed) => db.query(
      pg.config,
      'INSERT INTO pos_service_charges (restaurant_id, name_en, rate_bp, '
      '  fixed_minor) VALUES (@r, @n, $rateBp, $fixed)',
      parameters: {'r': restaurantId, 'n': 'X'},
    );

    test('a charge that is both a rate and an amount', () async {
      await expectLater(raw('1200', '2000'), throwsA(isA<Object>()));
    });

    test('a charge that is neither', () async {
      await expectLater(raw('NULL', 'NULL'), throwsA(isA<Object>()));
    });

    test('a rate above 100%', () async {
      await expectLater(raw('10001', 'NULL'), throwsA(isA<Object>()));
    });

    test('a negative amount', () async {
      await expectLater(raw('NULL', '-1'), throwsA(isA<Object>()));
    });
  });

  group('what the repository refuses', () {
    test('a nameless charge — it goes on the bill', () async {
      final result = await charges.save(
        const ServiceCharge(id: 0, nameEn: '  ', rateBp: 1200),
        by: owner,
      );
      expect(result.refusal, isA<CatalogInvalid>());
    });

    test('one that is both a rate and an amount, with a sentence', () async {
      // The CHECK would refuse it too. The message a person can act on is
      // worth more than the one PostgreSQL writes.
      final result = await charges.save(
        const ServiceCharge(
          id: 0,
          nameEn: 'Service',
          rateBp: 1200,
          fixedMinor: 2000,
        ),
        by: owner,
      );
      expect(result.refusal, isA<CatalogInvalid>());
    });

    test('a cashier changing what every customer pays', () async {
      final result = await charges.save(
        const ServiceCharge(id: 0, nameEn: 'Service', rateBp: 5000),
        by: cashier,
      );
      expect(result.refusal, isA<NotPermitted>());
      expect(await charges.all(), isEmpty);
    });
  });

  test('a retired charge is off the bill and still in the editor', () async {
    // Retired, not deleted: an order priced with it has its total snapshotted,
    // and somebody will ask what the twelve percent on last month's bill was.
    final saved = await charges.save(
      const ServiceCharge(id: 0, nameEn: 'Service', rateBp: 1200),
      by: owner,
    );
    await charges.save(
      saved.value!.copyWith(isActive: false),
      by: owner,
    );

    expect(await charges.all(), isEmpty);
    expect(await charges.all(includeInactive: true), hasLength(1));
  });

  test('the change is audited, naming the rate', () async {
    await charges.save(
      const ServiceCharge(id: 0, nameEn: 'Service', rateBp: 1200),
      by: owner,
    );

    final rows = await db.query(
      pg.config,
      "SELECT action, after_value->>'rate_bp' FROM pos_audit_events "
      'WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
      parameters: {'e': AuditAction.entityServiceCharge},
    );
    // "Who added 12% and when" is what a complaint asks.
    expect(rows.first[0], AuditAction.serviceChargeSaved);
    expect(rows.first[1], '1200');
  });
}
