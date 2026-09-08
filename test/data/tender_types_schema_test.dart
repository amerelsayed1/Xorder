@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_tender_types_repository.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';

import 'pg_fixture.dart';

/// Payment methods, as data (§40).
///
/// The interesting part is not the table. It is that a restaurant editing its
/// payment methods must not change what a shift that closed last week said the
/// drawer should have held — so `counts_as_cash` is snapshotted onto the
/// payment when the money moves, and this is where that is proved.
void main() {
  if (PgFixture.host == null) {
    test('tender types (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresTenderTypesRepository tenders;
  late int restaurantId;

  const slug = 'tender-types-test';

  setUp(() async {
    pg = await PgFixture.open('tender_types');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES (@s, 'Tenders') "
      'RETURNING id',
      parameters: {'s': slug},
    )).first[0]! as int;

    // The migration seeds every restaurant that existed when it ran. One
    // created afterwards is seeded by the bootstrap; here it is done directly
    // so the test is about the table rather than about the seeder.
    await db.query(
      pg.config,
      '''
      INSERT INTO pos_tender_types
        (restaurant_id, code, name_en, name_ar, kind, counts_as_cash,
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
      parameters: {'r': restaurantId},
    );

    tenders = PostgresTenderTypesRepository(
      database: db,
      config: pg.config.copyWith(tenantSlug: slug),
      restaurantId: restaurantId,
    );
  });

  tearDown(() => pg.close());

  group('what a restaurant starts with', () {
    test('is exactly what the code calls seeded', () async {
      // Two definitions of "what a new restaurant starts with" is how a fresh
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

    test('comes back in the order the restaurant put them in', () async {
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
          'INSERT INTO pos_tender_types (restaurant_id, code, name_en) '
          "VALUES (@r, 'cash', 'Cash again')",
          parameters: {'r': restaurantId},
        ),
        throwsA(isA<Object>()),
      );
    });

    test('two restaurants may each have a method called cash', () async {
      final other = (await db.query(
        pg.config,
        "INSERT INTO pos_restaurants (slug, name) VALUES ('other', 'Other') "
        'RETURNING id',
      )).first[0]! as int;

      await db.query(
        pg.config,
        'INSERT INTO pos_tender_types (restaurant_id, code, name_en) '
        "VALUES (@r, 'cash', 'Cash')",
        parameters: {'r': other},
      );
      // And it does not appear on this restaurant's till.
      expect((await tenders.all()), hasLength(4));
    });

    test('an unknown kind is refused by the database', () async {
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_tender_types (restaurant_id, code, name_en, kind) '
          "VALUES (@r, 'crypto', 'Crypto', 'bitcoin')",
          parameters: {'r': restaurantId},
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

  test('a restaurant with no rows still gets a till that can take money',
      () async {
    // The migration has not run, or the seed was wiped. An empty payment
    // screen is a till that cannot trade.
    await db.query(pg.config, 'DELETE FROM pos_tender_types');
    expect((await tenders.all()).map((t) => t.code), ['cash', 'card', 'wallet', 'account']);
  });
}
