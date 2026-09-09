@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// Authoring the named rates (§17).
///
/// The rule this file exists for is the one a CHECK cannot express and a
/// migration only half-holds: **exactly one group is the fallback, and it cannot
/// be retired.** A partial unique index stops two defaults; nothing stopped
/// zero, and zero is worse — every product that names no group would have no
/// rate at all.
void main() {
  if (PgFixture.host == null) {
    test('tax groups (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
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
      capabilities: {PosCapability.settingsManage},
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

  setUp(() async {
    pg = await PgFixture.open('tax_groups_admin');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('tg', 'TG') RETURNING id",
    )).first[0]! as int;
    branchId = (await db.query(
      pg.config,
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    admin = PostgresCatalogAdminRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  Future<TaxGroup> save(TaxGroup group, {PosStaff by = manager}) async {
    final result = await admin.saveTaxGroup(group, by: by);
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  Future<List<({int id, String name, int rate, bool isDefault, bool active})>>
  stored() async {
    final rows = await db.query(
      pg.config,
      'SELECT id, name_en, rate_bp, is_default, is_active FROM pos_tax_groups '
      'WHERE restaurant_id = @r ORDER BY id',
      parameters: {'r': restaurantId},
    );
    return [
      for (final row in rows)
        (
          id: row[0]! as int,
          name: row[1]! as String,
          rate: row[2]! as int,
          isDefault: row[3]! as bool,
          active: row[4]! as bool,
        ),
    ];
  }

  group('writing one', () {
    test('a rate round-trips', () async {
      final saved = await save(
        const TaxGroup(
          id: 0,
          nameEn: 'VAT',
          nameAr: 'ضريبة القيمة المضافة',
          rateBp: 1400,
          isDefault: true,
        ),
      );

      expect(saved.id, greaterThan(0));
      expect(saved.rateBp, 1400);
      expect(saved.isDefault, isTrue);
      expect((await stored()).single.name, 'VAT');
    });

    test('zero-rated is a rate, not a missing one', () async {
      // 0% and "no group" are different things, and only one of them files
      // correctly.
      final saved = await save(
        const TaxGroup(id: 0, nameEn: 'Zero-rated', rateBp: 0),
      );
      expect(saved.rateBp, 0);
      expect(saved.isZeroRated, isTrue);
      expect(saved.etaSubType, EtaTaxCode.zeroRated);
    });

    test('a nameless rate is refused', () async {
      // Zero-rated and exempt are both 0% and different on a filing; the name is
      // the only place that difference lives.
      final result = await admin.saveTaxGroup(
        const TaxGroup(id: 0, nameEn: '   ', rateBp: 0),
        by: manager,
      );
      expect(result.succeeded, isFalse);
      expect(await stored(), isEmpty);
    });

    test('a rate outside 0–100% is refused', () async {
      for (final bp in [-1, 10001]) {
        final result = await admin.saveTaxGroup(
          TaxGroup(id: 0, nameEn: 'Odd', rateBp: bp),
          by: manager,
        );
        expect(result.succeeded, isFalse, reason: '$bp');
      }
      expect(await stored(), isEmpty);
    });

    test('two groups may not share a name', () async {
      await save(const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400));
      await expectLater(
        admin.saveTaxGroup(
          const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 500),
          by: manager,
        ),
        throwsA(isA<Object>()),
      );
    });

    test('repricing one changes the rate and nothing else', () async {
      final vat = await save(
        const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400, isDefault: true),
      );
      await save(
        TaxGroup(
          id: vat.id,
          nameEn: 'VAT',
          rateBp: 1500,
          isDefault: true,
        ),
      );

      final all = await stored();
      expect(all, hasLength(1));
      expect(all.single.rate, 1500);
      expect(all.single.isDefault, isTrue);
    });
  });

  group('the fallback rate', () {
    test('making a second group the default takes it off the first', () async {
      // The database refuses two defaults with a partial unique index. Clearing
      // the old one here is what turns that constraint into a saved rate rather
      // than an error a manager has to interpret.
      final vat = await save(
        const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400, isDefault: true),
      );
      final reduced = await save(
        const TaxGroup(id: 0, nameEn: 'Reduced', rateBp: 500, isDefault: true),
      );

      final all = await stored();
      expect(all.firstWhere((g) => g.id == vat.id).isDefault, isFalse);
      expect(all.firstWhere((g) => g.id == reduced.id).isDefault, isTrue);
    });

    test('cannot simply stop being the default', () async {
      // Something has to answer "what does an unclassified product cost", and
      // every product that names no group is unclassified.
      final vat = await save(
        const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400, isDefault: true),
      );

      final result = await admin.saveTaxGroup(
        TaxGroup(id: vat.id, nameEn: 'VAT', rateBp: 1400),
        by: manager,
      );
      expect(result.succeeded, isFalse);
      expect((result.refusal! as CatalogInvalid).reason, contains('fallback'));
      expect((await stored()).single.isDefault, isTrue);
    });

    test('cannot be retired either', () async {
      final vat = await save(
        const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400, isDefault: true),
      );

      final result = await admin.saveTaxGroup(
        TaxGroup(
          id: vat.id,
          nameEn: 'VAT',
          rateBp: 1400,
          isDefault: true,
          isActive: false,
        ),
        by: manager,
      );
      expect(result.succeeded, isFalse);
      expect((await stored()).single.active, isTrue);
    });

    test('but a non-default group can be retired and brought back', () async {
      await save(
        const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400, isDefault: true),
      );
      final zero = await save(
        const TaxGroup(id: 0, nameEn: 'Zero-rated', rateBp: 0),
      );

      await save(
        TaxGroup(
          id: zero.id,
          nameEn: 'Zero-rated',
          rateBp: 0,
          isActive: false,
        ),
      );
      expect((await stored()).firstWhere((g) => g.id == zero.id).active, isFalse);

      await save(TaxGroup(id: zero.id, nameEn: 'Zero-rated', rateBp: 0));
      expect((await stored()).firstWhere((g) => g.id == zero.id).active, isTrue);
    });
  });

  group('what is refused', () {
    test('a cashier cannot change what tax is charged', () async {
      final result = await admin.saveTaxGroup(
        const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400),
        by: cashier,
      );
      expect(result.refusal, isA<NotPermitted>());
      expect(await stored(), isEmpty);
    });

    test('a cloud till is refused — the platform authors tax', () async {
      final cloud = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        restaurantId: restaurantId,
        branchId: branchId,
        offline: false,
      );
      final result = await cloud.saveTaxGroup(
        const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400),
        by: manager,
      );
      expect(result.refusal, isA<NotPermitted>());
    });

    test('another restaurant keeps its own rates', () async {
      await save(const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400));

      final other = (await db.query(
        pg.config,
        "INSERT INTO pos_restaurants (slug, name) VALUES ('o', 'O') RETURNING id",
      )).first[0]! as int;
      final otherBranch = (await db.query(
        pg.config,
        'INSERT INTO pos_branches (restaurant_id, code, name) '
        "VALUES (@r, 'M', 'M') RETURNING id",
        parameters: {'r': other},
      )).first[0]! as int;

      final theirs = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        restaurantId: other,
        branchId: otherBranch,
      );
      // The same name, which is allowed: uniqueness is per restaurant.
      final result = await theirs.saveTaxGroup(
        const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 500),
        by: manager,
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect((await stored()).single.rate, 1400, reason: 'ours is untouched');
    });
  });

  test('a rate change is audited — it changes what every item costs', () async {
    final vat = await save(
      const TaxGroup(id: 0, nameEn: 'VAT', rateBp: 1400, isDefault: true),
    );
    await save(
      TaxGroup(id: vat.id, nameEn: 'VAT', rateBp: 1500, isDefault: true),
    );

    final rows = await db.query(
      pg.config,
      'SELECT after_value FROM pos_audit_events WHERE action = @a '
      'ORDER BY id DESC LIMIT 1',
      parameters: {'a': AuditAction.taxGroupSaved},
    );
    expect(rows, hasLength(1));
    expect('${rows.first[0]}', contains('1500'));
  });
}
