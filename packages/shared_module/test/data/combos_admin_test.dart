@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:shared_module/domain/models/combo_draft.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Authoring combos.
///
/// The till has sold combos since migration 18, and until this suite's subject
/// existed nothing in the app could write one. What matters here is what only
/// a database can answer: that a save writes the whole tree or none of it,
/// that a group keeps its id across an edit, that another business's
/// products cannot be built into a meal, and that every save is on the ledger.
void main() {
  if (PgFixture.host == null) {
    test('combos (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresCatalogAdminRepository admin;
  late int businessId;
  late int categoryId;
  late int burger;
  late int chips;
  late int cola;

  const manager = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.catalogManage},
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

  Future<int> insert(String sql, Map<String, Object?> parameters) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0]! as int;

  Future<int> product(int business, int category, String name) => insert(
    'INSERT INTO pos_products (business_id, category_id, name_en, price_minor) '
    'VALUES (@r, @c, @n, 4500) RETURNING id',
    {'r': business, 'c': category, 'n': name},
  );

  Future<int> category(int business, String name) => insert(
    'INSERT INTO pos_categories (business_id, name_en, slug) '
    'VALUES (@r, @n, @n) RETURNING id',
    {'r': business, 'n': name},
  );

  setUp(() async {
    pg = await PgFixture.open('combos_admin');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    // Combos first: an option RESTRICTs deleting its product (migration 18, on
    // purpose), so a business that still has one cannot be wiped under it.
    await db.query(pg.config, 'DELETE FROM pos_combos');
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = await insert(
      "INSERT INTO pos_businesses (slug, name) VALUES ('cb', 'CB') RETURNING id",
      {},
    );
    final branchId = await insert(
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      {'r': businessId},
    );
    categoryId = await category(businessId, 'Meals');
    burger = await product(businessId, categoryId, 'Burger');
    chips = await product(businessId, categoryId, 'Chips');
    cola = await product(businessId, categoryId, 'Cola');

    admin = PostgresCatalogAdminRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  ComboDraft meal({
    int id = 0,
    String name = 'Burger meal',
    int price = 8500,
    String? sku,
    bool available = true,
    List<ComboGroupDraft>? groups,
  }) => ComboDraft(
    id: id,
    categoryId: categoryId,
    nameEn: name,
    nameAr: 'وجبة برجر',
    price: Money(price),
    sku: sku,
    isAvailable: available,
    groups:
        groups ??
        [
          ComboGroupDraft(
            nameEn: 'Burger',
            options: [ComboOptionDraft(productId: burger)],
          ),
          ComboGroupDraft(
            nameEn: 'Side',
            minSelect: 0,
            maxSelect: 2,
            options: [
              ComboOptionDraft(productId: chips),
              ComboOptionDraft(
                productId: cola,
                priceDelta: const Money(500),
              ),
            ],
          ),
        ],
  );

  Future<ComboDraft> save(ComboDraft combo) async {
    final result = await admin.saveCombo(combo, by: manager);
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  Future<ComboProblem?> refusedWith(ComboDraft combo) async {
    final refusal = (await admin.saveCombo(combo, by: manager)).refusal;
    return refusal is ComboRefused ? refusal.problem : null;
  }

  Future<int> count(String table) async =>
      (await db.query(pg.config, 'SELECT count(*) FROM $table')).first[0]!
          as int;

  group('writing one', () {
    test('the whole tree round-trips, with ids', () async {
      final saved = await save(meal(sku: 'BM1'));

      expect(saved.id, greaterThan(0));
      expect(saved.price.minor, 8500);
      expect(saved.sku, 'BM1');
      expect(saved.nameAr, 'وجبة برجر');
      expect(saved.groups.map((g) => g.nameEn), ['Burger', 'Side']);
      expect(saved.groups.every((g) => g.id > 0), isTrue);

      final side = saved.groups.last;
      expect(side.minSelect, 0);
      expect(side.maxSelect, 2);
      expect(side.options.map((o) => o.productId), [chips, cola]);
      expect(side.options.last.priceDelta.minor, 500);
    });

    test('what is saved is what the list returns', () async {
      final saved = await save(meal());
      final listed = await admin.combos();

      expect(listed.single.id, saved.id);
      expect(listed.single.groups.length, 2);
    });

    test('a blank SKU is stored as none, so two combos can both have none',
        () async {
      await save(meal(sku: '  '));
      await save(meal(name: 'Chicken meal', sku: ''));

      expect(await count('pos_combos'), 2);
    });

    test('every save is on the ledger', () async {
      final saved = await save(meal());
      await save(meal(id: saved.id, price: 9000));

      final rows = await db.query(
        pg.config,
        'SELECT action, entity_id, before_value, after_value '
        // This business's alone: the ledger is append-only, so earlier tests'
        // rows are still there.
        'FROM pos_audit_events WHERE entity_type = @t AND business_id = @r '
        'ORDER BY id',
        parameters: {'t': AuditAction.entityCombo, 'r': businessId},
      );
      expect(rows.length, 2);
      expect(rows.every((r) => r[0] == AuditAction.comboSaved), isTrue);
      expect(rows.every((r) => r[1] == '${saved.id}'), isTrue);
      // The reprice carries what it was, which is what a margin review asks.
      expect((rows.last[2]! as Map)['price_minor'], 8500);
      expect((rows.last[3]! as Map)['price_minor'], 9000);
    });
  });

  group('editing one', () {
    test('a group keeps its id across a save', () async {
      final first = await save(meal());
      final again = await save(meal(id: first.id, groups: first.groups));

      expect(again.groups.map((g) => g.id), first.groups.map((g) => g.id));
    });

    test('removing a group from the list removes it from the database',
        () async {
      final first = await save(meal());
      final burgerOnly = [first.groups.first];

      final again = await save(meal(id: first.id, groups: burgerOnly));

      expect(again.groups.length, 1);
      expect(await count('pos_combo_groups'), 1);
      // Its items go with it — nothing is left pointing at a dead group.
      expect(await count('pos_combo_options'), 1);
    });

    test('items are replaced as a set', () async {
      final first = await save(meal());
      final side = first.groups.last;
      final onlyCola = ComboGroupDraft(
        id: side.id,
        nameEn: side.nameEn,
        minSelect: 0,
        maxSelect: 1,
        options: [ComboOptionDraft(productId: cola)],
      );

      final again = await save(
        meal(id: first.id, groups: [first.groups.first, onlyCola]),
      );

      expect(again.groups.last.options.map((o) => o.productId), [cola]);
    });

    test('it is retired by switching it off, not deleted', () async {
      final first = await save(meal());
      await save(meal(id: first.id, available: false));

      final listed = await admin.combos();
      expect(listed.single.isAvailable, isFalse);
      // The manager can still find it to switch it back on.
      expect(await count('pos_combos'), 1);
    });

    test('a combo that is not there is refused, not recreated', () async {
      final refusal = (await admin.saveCombo(meal(id: 99999), by: manager))
          .refusal;
      expect(refusal, isA<EditedElsewhere>());
      expect(await count('pos_combos'), 0);
    });

    test("another combo's group id cannot be moved into this one", () async {
      final a = await save(meal(name: 'A'));
      final b = await save(meal(name: 'B'));

      final stolen = ComboGroupDraft(
        id: a.groups.first.id,
        nameEn: 'Stolen',
        options: [ComboOptionDraft(productId: burger)],
      );
      final refusal =
          (await admin.saveCombo(
            meal(id: b.id, name: 'B', groups: [stolen]),
            by: manager,
          )).refusal;

      expect(refusal, isA<EditedElsewhere>());
      final listed = await admin.combos();
      final untouched = listed.firstWhere((c) => c.id == a.id);
      expect(untouched.groups.first.nameEn, 'Burger');
    });
  });

  group('refusals leave nothing behind', () {
    test('a rule broken in the tree writes no combo at all', () async {
      final problem = await refusedWith(
        meal(
          groups: [
            ComboGroupDraft(nameEn: 'Burger', options: const []),
          ],
        ),
      );

      expect(problem, ComboProblem.groupEmpty);
      expect(await count('pos_combos'), 0);
    });

    test('a product from another business is refused', () async {
      final otherBusiness = await insert(
        "INSERT INTO pos_businesses (slug, name) VALUES ('ot', 'OT') RETURNING id",
        {},
      );
      final otherCategory = await category(otherBusiness, 'Theirs');
      final theirs = await product(otherBusiness, otherCategory, 'Secret');

      final problem = await refusedWith(
        meal(
          groups: [
            ComboGroupDraft(
              nameEn: 'Mix',
              options: [
                ComboOptionDraft(productId: burger),
                ComboOptionDraft(productId: theirs),
              ],
            ),
          ],
        ),
      );

      expect(problem, ComboProblem.productUnknown);
      expect(await count('pos_combos'), 0);
      expect(await count('pos_combo_options'), 0);
    });

    test("another business's category is refused", () async {
      final otherBusiness = await insert(
        "INSERT INTO pos_businesses (slug, name) VALUES ('ot', 'OT') RETURNING id",
        {},
      );
      final theirs = await category(otherBusiness, 'Theirs');

      final problem = await refusedWith(
        ComboDraft(
          categoryId: theirs,
          nameEn: 'Meal',
          price: const Money(100),
          groups: [
            ComboGroupDraft(
              nameEn: 'Burger',
              options: [ComboOptionDraft(productId: burger)],
            ),
          ],
        ),
      );

      expect(problem, ComboProblem.categoryUnknown);
    });

    test('a SKU another combo holds is refused, in words', () async {
      await save(meal(sku: 'BM1'));

      expect(
        await refusedWith(meal(name: 'Other', sku: 'BM1')),
        ComboProblem.skuTaken,
      );
      expect(await count('pos_combos'), 1);
    });

    test('a combo can keep its own SKU when it is edited', () async {
      final first = await save(meal(sku: 'BM1'));
      final again = await save(meal(id: first.id, sku: 'BM1', price: 9000));

      expect(again.sku, 'BM1');
    });
  });

  group('who may', () {
    test('a cashier may not', () async {
      final refusal = (await admin.saveCombo(meal(), by: cashier)).refusal;

      expect(refusal, isA<NotPermitted>());
      expect(await count('pos_combos'), 0);
    });

    test('a cloud till refuses: the seeder would erase it', () async {
      final cloud = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        offline: false,
      );

      final refusal = (await cloud.saveCombo(meal(), by: manager)).refusal;

      expect(refusal, isA<NotPermitted>());
      expect(await count('pos_combos'), 0);
    });
  });

  test('the till sells what was authored', () async {
    // The point of the whole feature: a combo made here is one the catalogue
    // read — the till's own — can see.
    final saved = await save(meal());
    final rows = await db.query(
      pg.config,
      'SELECT g.min_select, g.max_select, count(o.id) '
      'FROM pos_combo_groups g LEFT JOIN pos_combo_options o '
      '  ON o.combo_group_id = g.id '
      'WHERE g.combo_id = @c GROUP BY g.id ORDER BY g.sort_order',
      parameters: {'c': saved.id},
    );
    expect(rows.map((r) => [r[0], r[1], r[2]]).toList(), [
      [1, 1, 1],
      [0, 2, 2],
    ]);
  });
}
