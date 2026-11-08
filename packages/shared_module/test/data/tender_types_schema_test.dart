@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:shared_module/data/postgres/postgres_tender_types_repository.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:shared_module/domain/models/tender_method.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// Payment methods, as data (§40).
///
/// The interesting part is not the table. It is that a business editing its
/// payment methods must not change what a shift that closed last week said the
/// drawer should have held — so `counts_as_cash` is snapshotted onto the
/// payment when the money moves, and this is where that is proved.
void main() {
  if (PgFixture.host == null) {
    test('tender types (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late PostgresTenderTypesRepository tenders;
  late int businessId;

  const slug = 'tender-types-test';

  setUp(() async {
    pg = await PgFixture.open('tender_types');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES (@s, 'Tenders') "
      'RETURNING id',
      parameters: {'s': slug},
    )).first[0]! as int;

    // The migration seeds every business that existed when it ran. One
    // created afterwards is seeded by the bootstrap; here it is done directly
    // so the test is about the table rather than about the seeder.
    await db.query(
      pg.config,
      '''
      INSERT INTO pos_tender_types
        (business_id, code, name_en, name_ar, kind, counts_as_cash,
         opens_drawer, requires_reference, sort_order)
      SELECT @r, v.code, v.name_en, v.name_ar, v.kind, v.cash, v.drawer,
             v.reference, v.sort
        FROM (VALUES
          ('cash',    'Cash',             'نقدي',       'cash',    true,  true,  false, 1),
          ('card',    'Card',             'بطاقة',      'card',    false, false, true,  2),
          ('wallet',  'Wallet · InstaPay','محفظة',      'wallet',  false, false, true,  3),
          ('account', 'On account',       'على الحساب', 'account', false, false, false, 4)
        ) AS v(code, name_en, name_ar, kind, cash, drawer, reference, sort)
      ''',
      parameters: {'r': businessId},
    );

    tenders = PostgresTenderTypesRepository(
      database: db,
      config: pg.config.copyWith(tenantSlug: slug),
      businessId: businessId,
    );
  });

  tearDown(() => pg.close());

  group('what a business starts with', () {
    test('is exactly what the code calls seeded', () async {
      // Two definitions of "what a new business starts with" is how a fresh
      // install and a migrated one end up different.
      final stored = await tenders.all();

      expect(
        stored.map((t) => t.code),
        TenderMethod.seeded.map((t) => t.code),
      );
      for (final method in stored) {
        final expected = TenderMethod.seeded.firstWhere(
          (t) => t.code == method.code,
        );
        expect(method.nameEn, expected.nameEn, reason: method.code);
        expect(method.nameAr, expected.nameAr, reason: method.code);
        expect(method.kind, expected.kind, reason: method.code);
        expect(
          method.countsAsCash,
          expected.countsAsCash,
          reason: method.code,
        );
        expect(method.opensDrawer, expected.opensDrawer, reason: method.code);
        expect(
          method.requiresReference,
          expected.requiresReference,
          reason: method.code,
        );
      }
    });

    test('only cash counts as cash', () async {
      final stored = await tenders.all();
      expect(
        stored.where((t) => t.countsAsCash).map((t) => t.code),
        ['cash'],
      );
    });

    test('comes back in the order the business put them in', () async {
      await db.query(
        pg.config,
        "UPDATE pos_tender_types SET sort_order = 0 WHERE code = 'card'",
      );
      expect((await tenders.all()).first.code, 'card');
    });
  });

  group('editing them', () {
    test('a retired method is off the till and still in the editor', () async {
      // Retired, not deleted: a settled payment names it, and a receipt
      // reprinted next year still has to say what the customer paid with.
      await db.query(
        pg.config,
        "UPDATE pos_tender_types SET is_active = false WHERE code = 'account'",
      );

      expect((await tenders.all()).map((t) => t.code), isNot(contains('account')));
      expect(
        (await tenders.all(includeInactive: true)).map((t) => t.code),
        contains('account'),
      );
    });

    test('a renamed method keeps its code', () async {
      await db.query(
        pg.config,
        "UPDATE pos_tender_types SET name_en = 'Visa' WHERE code = 'card'",
      );
      final card = (await tenders.all()).firstWhere((t) => t.code == 'card');
      expect(card.nameEn, 'Visa');
      expect(card.wireLabel, 'Visa', reason: 'and that is what gets stored');
    });

    test('a second method cannot take a code that is taken', () async {
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_tender_types (business_id, code, name_en) '
          "VALUES (@r, 'cash', 'Cash again')",
          parameters: {'r': businessId},
        ),
        throwsA(isA<Object>()),
      );
    });

    test('two businesses may each have a method called cash', () async {
      final other = (await db.query(
        pg.config,
        "INSERT INTO pos_businesses (slug, name) VALUES ('other', 'Other') "
        'RETURNING id',
      )).first[0]! as int;

      await db.query(
        pg.config,
        'INSERT INTO pos_tender_types (business_id, code, name_en) '
        "VALUES (@r, 'cash', 'Cash')",
        parameters: {'r': other},
      );
      // And it does not appear on this business's till.
      expect((await tenders.all()), hasLength(4));
    });

    test('an unknown kind is refused by the database', () async {
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_tender_types (business_id, code, name_en, kind) '
          "VALUES (@r, 'crypto', 'Crypto', 'bitcoin')",
          parameters: {'r': businessId},
        ),
        throwsA(isA<Object>()),
      );
    });

    test('a kind this binary does not know is still takeable', () async {
      // The other direction. A till on an older build must not refuse to sell
      // because somebody added a payment method in the back office.
      expect(TenderKind.fromWire('crypto'), TenderKind.other);
      expect(TenderKind.fromWire(null), TenderKind.other);
      expect(TenderKind.fromWire('wallet'), TenderKind.wallet);
    });
  });

  test('a business created after the migration is seeded by the installer',
      () async {
    // **Found by installing one.** Migration 23 seeds every business present
    // when it runs, and a fresh install runs the migrations first and creates
    // the business second — so without `seedTenderTypes` the new business
    // has none, the till falls back to the compiled-in four, and Management
    // shows an empty list beside a payment screen offering four methods.
    await db.query(pg.config, 'DELETE FROM pos_tender_types');

    final created = await LocalBootstrap(db).seedTenderTypes(
      pg.config,
      businessId,
    );

    expect(created, 4);
    expect(
      (await tenders.all()).map((t) => t.code),
      TenderMethod.seeded.map((t) => t.code),
    );
  });

  test('seeding twice does not undo a rename', () async {
    await db.query(
      pg.config,
      "UPDATE pos_tender_types SET name_en = 'Visa' WHERE code = 'card'",
    );

    final created = await LocalBootstrap(db).seedTenderTypes(
      pg.config,
      businessId,
    );

    expect(created, 0, reason: 'nothing was missing');
    expect(
      (await tenders.all()).firstWhere((t) => t.code == 'card').nameEn,
      'Visa',
    );
  });

  test('a business with no rows still gets a till that can take money',
      () async {
    // The migration has not run, or the seed was wiped. An empty payment
    // screen is a till that cannot trade.
    await db.query(pg.config, 'DELETE FROM pos_tender_types');
    expect((await tenders.all()).map((t) => t.code), ['cash', 'card', 'wallet', 'account']);
  });

  group('authoring them', skip: PgFixture.onSqlite ? "the offline back office's writer; a cloud till never binds it" : false, () {
    late PostgresCatalogAdminRepository admin;

    const owner = PosStaff(
      id: 1,
      name: 'Amer M.',
      capabilities: {
        PosCapability.settingsManage,
        PosCapability.catalogManage,
      },
    );
    const cashier = PosStaff(
      id: 2,
      name: 'Rana A.',
      capabilities: {PosCapability.operate},
    );

    setUp(() async {
      final branchId = (await db.query(
        pg.config,
        "INSERT INTO pos_branches (business_id, code, name) "
        "VALUES (@r, 'MAIN', 'Main') RETURNING id",
        parameters: {'r': businessId},
      )).first[0]! as int;

      admin = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: branchId,
      );
    });

    Future<TenderMethod> byCode(String code) async =>
        (await tenders.all(includeInactive: true))
            .firstWhere((t) => t.code == code);

    test('a new method reaches the till', () async {
      final result = await admin.saveTenderType(
        const TenderMethod(
          id: 0,
          code: 'voucher',
          nameEn: 'Meal voucher',
          nameAr: 'قسيمة',
          kind: TenderKind.voucher,
          opensDrawer: true,
          refundAllowed: false,
          sortOrder: 5,
        ),
        by: owner,
      );

      expect(result.succeeded, isTrue, reason: '\${result.refusal}');
      final saved = await byCode('voucher');
      expect(saved.nameEn, 'Meal voucher');
      expect(saved.kind, TenderKind.voucher);
      expect(saved.refundAllowed, isFalse);
      expect(
        saved.opensDrawer && !saved.countsAsCash,
        isTrue,
        reason: 'vouchers live in the drawer without being cash',
      );
    });

    test('a method is renamed without changing what it is', () async {
      final card = await byCode('card');
      await admin.saveTenderType(
        TenderMethod(
          id: card.id,
          code: card.code,
          nameEn: 'Visa',
          kind: card.kind,
          requiresReference: card.requiresReference,
          sortOrder: card.sortOrder,
        ),
        by: owner,
      );

      final saved = await byCode('card');
      expect(saved.nameEn, 'Visa');
      expect(saved.code, 'card', reason: 'the code is identity');
    });

    test('retiring the last cash method is refused', () async {
      // A business that does this has a till that can put nothing in the
      // drawer and a cash-up that reads zero for the rest of time. The fix
      // afterwards is a database edit, and whoever did it will not know that
      // is what they did.
      final cash = await byCode('cash');
      final result = await admin.saveTenderType(
        TenderMethod(
          id: cash.id,
          code: cash.code,
          nameEn: cash.nameEn,
          countsAsCash: false,
          kind: cash.kind,
        ),
        by: owner,
      );

      expect(result.refusal, isA<CatalogInvalid>());
      expect((await byCode('cash')).countsAsCash, isTrue);
    });

    test('retiring one of two cash methods is allowed', () async {
      await admin.saveTenderType(
        const TenderMethod(
          id: 0,
          code: 'petty',
          nameEn: 'Petty cash',
          kind: TenderKind.cash,
          countsAsCash: true,
        ),
        by: owner,
      );

      final cash = await byCode('cash');
      final result = await admin.saveTenderType(
        TenderMethod(
          id: cash.id,
          code: cash.code,
          nameEn: cash.nameEn,
          kind: cash.kind,
          isActive: false,
          countsAsCash: true,
        ),
        by: owner,
      );
      expect(result.succeeded, isTrue, reason: '\${result.refusal}');
    });

    test('a nameless method is refused', () async {
      final result = await admin.saveTenderType(
        const TenderMethod(id: 0, code: 'x', nameEn: '  '),
        by: owner,
      );
      expect(result.refusal, isA<CatalogInvalid>());
    });

    test('a cashier cannot change how the business takes money', () async {
      final result = await admin.saveTenderType(
        const TenderMethod(id: 0, code: 'x', nameEn: 'Anything'),
        by: cashier,
      );
      expect(result.refusal, isA<NotPermitted>());
    });

    test('the change is audited, naming what counts as cash', () async {
      await admin.saveTenderType(
        const TenderMethod(
          id: 0,
          code: 'voucher',
          nameEn: 'Meal voucher',
          kind: TenderKind.voucher,
        ),
        by: owner,
      );

      final rows = await db.query(
        pg.config,
        "SELECT action, after_value->>'counts_as_cash' FROM pos_audit_events "
        'WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
        parameters: {'e': AuditAction.entityTenderType},
      );
      // Changing this changes what every future cash-up expects to find in the
      // drawer, so it has to be findable.
      expect(rows.first[0], AuditAction.tenderTypeSaved);
      expect(rows.first[1], 'false');
    });
  });
}
