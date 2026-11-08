@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_units_repository.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/pos_unit.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// The units stock is counted and bought in, as the business names them.
///
/// Migration 39 turned a closed list in code into a table the back office
/// owns. What has to hold: every business starts with the seven, a unit the
/// business adds is kept by its code and read back as itself, and the code —
/// which purchase lines and stock rows store — never changes under them.
void main() {
  if (PgFixture.host == null) {
    test('units (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const buyer = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'owner',
      nameEn: 'Owner',
      capabilities: {PosCapability.purchaseManage},
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

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;
  late PostgresUnitsRepository units;

  Future<Object?> one(String sql, [Map<String, Object?> p = const {}]) async =>
      (await db.query(pg.config, sql, parameters: p)).first[0];

  setUp(() async {
    pg = await PgFixture.open('units');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId =
        await one(
              "INSERT INTO pos_businesses (slug, name) VALUES ('units', "
              "'Units') RETURNING id",
            )
            as int;
    final branchId =
        await one(
              "INSERT INTO pos_branches (business_id, code, name) "
              "VALUES (@r, 'U1', 'Main') RETURNING id",
              {'r': businessId},
            )
            as int;
    units = PostgresUnitsRepository(
      database: db,
      config: pg.config,
      readDatabase: db,
      readConfig: pg.config,
      adminAvailable: true,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  test('a new business starts with the seven', () async {
    // Seeded by the database, not by each of the three places that create a
    // business remembering to.
    final all = await units.all();
    expect([for (final u in all) u.code], [
      'ea',
      'kg',
      'g',
      'l',
      'ml',
      'box',
      'pack',
    ]);
    final kg = all.firstWhere((u) => u.code == 'kg');
    expect(kg.allowsFraction, isTrue);
    expect(kg.etaUnitType, 'KGM');
    expect(kg.nameAr, isNotEmpty);
    expect(all.firstWhere((u) => u.code == 'box').allowsFraction, isFalse);
  });

  test('a business from before the migration has them too', () async {
    // The migration seeds every business already there, and running it
    // again adds nothing twice.
    await db.query(
      pg.config,
      'DELETE FROM pos_units WHERE business_id = @r',
      parameters: {'r': businessId},
    );
    await pg.replay(39);
    await pg.replay(39);

    expect(await units.all(), hasLength(7));
  });

  test('a unit the business adds is kept, and read back as itself', () async {
    final result = await units.save(
      const PosUnit(
        id: 0,
        code: 'tray',
        nameEn: 'Tray of 30',
        nameAr: 'طبق ٣٠',
      ),
      by: buyer,
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');

    expect([for (final u in await units.all()) u.code], contains('tray'));
    // Not "each": the old fallback would have read a purchase line written in
    // trays as one of something.
    expect(QuantityUnit.fromWire('tray').wire, 'tray');
    expect(QuantityUnit.fromWire('tray'), result.value!.unit);
  });

  test('two units cannot share a code', () async {
    final result = await units.save(
      const PosUnit(id: 0, code: 'kg', nameEn: 'Kilo again'),
      by: buyer,
    );
    expect(result.succeeded, isFalse);
    expect(result.refusal, isA<CatalogInvalid>());
  });

  test('renaming keeps the code — purchase lines store it', () async {
    final tray = (await units.save(
      const PosUnit(id: 0, code: 'tray', nameEn: 'Tray of 30'),
      by: buyer,
    )).value!;

    await units.save(
      PosUnit(id: tray.id, code: 'something_else', nameEn: 'Egg tray'),
      by: buyer,
    );

    final after = (await units.all()).firstWhere((u) => u.id == tray.id);
    expect(after.nameEn, 'Egg tray');
    expect(after.code, 'tray');
  });

  test('a retired unit is listed only when asked for', () async {
    final box = (await units.all()).firstWhere((u) => u.code == 'box');
    await units.save(box.copyWith(isActive: false), by: buyer);

    expect([for (final u in await units.all()) u.code], isNot(contains('box')));
    expect(
      [for (final u in await units.all(includeInactive: true)) u.code],
      contains('box'),
    );
  });

  test('a code of the wrong shape is refused, by the repository and the '
      'database both', () async {
    final result = await units.save(
      const PosUnit(id: 0, code: 'Kg!', nameEn: 'Shouting kilo'),
      by: buyer,
    );
    expect(result.refusal, isA<CatalogInvalid>());

    await expectLater(
      db.query(
        pg.config,
        "INSERT INTO pos_units (business_id, code, name_en) "
        "VALUES (@r, 'Kg!', 'x')",
        parameters: {'r': businessId},
      ),
      throwsA(isA<PosDbException>()),
    );
  });

  test('units are the buyer\'s to change', () async {
    final result = await units.save(
      const PosUnit(id: 0, code: 'sack', nameEn: 'Sack'),
      by: cashier,
    );
    expect(result.refusal, isA<NotPermitted>());
  });

  test('every change is on the audit trail', () async {
    await units.save(
      const PosUnit(id: 0, code: 'sack', nameEn: 'Sack of rice'),
      by: buyer,
    );
    final row = (await db.query(
      pg.config,
      "SELECT action, entity_type, after_value->>'code' FROM pos_audit_events "
      "WHERE business_id = @r AND entity_type = 'unit'",
      parameters: {'r': businessId},
    )).single;
    expect(row, [AuditAction.unitSaved, AuditAction.entityUnit, 'sack']);
  });
}
