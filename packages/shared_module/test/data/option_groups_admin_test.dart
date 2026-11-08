@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:shared_module/data/postgres/postgres_catalog_repository.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/option_group.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// `jsonb` comes back decoded on some driver paths and as text on others.
Map<String, Object?> _payload(Object? raw) => switch (raw) {
  final Map map => map.cast<String, Object?>(),
  final String text => (jsonDecode(text) as Map).cast<String, Object?>(),
  _ => throw StateError('unreadable payload: $raw'),
};

/// Sizes and extras, authored on an offline till the way the platform authors
/// them (migration 45).
///
/// Three claims matter more than the rest, and each has its own group below:
/// an option keeps its id however often its group is saved, because parked
/// tickets and order lines name it by id; an item never has two sets of sizes;
/// and the price on the tile is the default size's, derived at the read, so it
/// cannot drift from the sizes the way the platform's stored copy does.
void main() {
  if (PgFixture.host == null) {
    test('option groups (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresCatalogAdminRepository admin;
  late int businessId;
  late int burgers;
  late int drinks;

  const slug = 'option-groups-test';

  const manager = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.catalogManage},
    ),
  );
  const cashier = PosStaff(
    id: 2,
    name: 'Rana A.',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.operate},
    ),
  );

  const sizes = OptionGroupDraft(
    nameEn: 'Burger sizes',
    displayNameEn: 'Size',
    displayNameAr: 'الحجم',
    isVariant: true,
    options: [
      OptionDraft(nameEn: 'Regular', price: Money(8500)),
      OptionDraft(nameEn: 'Large', price: Money(11000)),
    ],
  );
  const extras = OptionGroupDraft(
    nameEn: 'Extras',
    maxSelect: 3,
    options: [
      OptionDraft(nameEn: 'Cheese', price: Money(1500)),
      OptionDraft(nameEn: 'Bacon', price: Money(2500)),
    ],
  );

  Future<int> category(String name, {int? business}) async =>
      (await db.query(
        pg.config,
        'INSERT INTO pos_categories (business_id, name_en) '
        'VALUES (@r, @name) RETURNING id',
        parameters: {'r': business ?? businessId, 'name': name},
      )).first[0]! as int;

  setUp(() async {
    pg = await PgFixture.open('option_groups_admin');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES (@slug, 'Options') "
      'RETURNING id',
      parameters: {'slug': slug},
    )).first[0]! as int;

    admin = PostgresCatalogAdminRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
    );
    burgers = await category('Burgers');
    drinks = await category('Drinks');
  });

  tearDown(() => pg.close());

  Future<int> product(
    String name, {
    int? categoryId,
    int price = 5000,
    int? discounted,
  }) async => (await db.query(
    pg.config,
    'INSERT INTO pos_products (business_id, category_id, name_en, '
    '  price_minor, discounted_price_minor) '
    'VALUES (@r, @c, @name, @price, @discounted) RETURNING id',
    parameters: {
      'r': businessId,
      'c': categoryId ?? burgers,
      'name': name,
      'price': price,
      'discounted': discounted,
    },
  )).first[0]! as int;

  String why(AdminRefusal? refusal) => switch (refusal) {
    OptionGroupRefused(:final problem, :final names) => '$problem $names',
    CatalogInvalid(:final reason) => reason,
    _ => '$refusal',
  };

  /// Which rule refused it. A code rather than the sentence, since the
  /// sentence is now the screen's to word in the screen's language.
  OptionGroupProblem? problemOf(AdminRefusal? refusal) =>
      refusal is OptionGroupRefused ? refusal.problem : null;

  Future<OptionGroupDraft> library(OptionGroupDraft group) async {
    final result = await admin.saveOptionGroup(group, by: manager);
    expect(result.succeeded, isTrue, reason: why(result.refusal));
    return result.value!;
  }

  Future<List<OptionGroupRef>> offer(
    int productId,
    List<OptionGroupRef> groups,
  ) async {
    final result = await admin.setProductOptionGroups(
      productId,
      groups,
      by: manager,
    );
    expect(result.succeeded, isTrue, reason: why(result.refusal));
    return result.value!;
  }

  OptionGroupDraft own(List<OptionGroupRef> refs, int index) =>
      (refs[index] as InlineGroupRef).group;

  Future<int> count(String sql, [Map<String, Object?>? parameters]) async =>
      (await db.query(pg.config, sql, parameters: parameters)).first[0]! as int;

  Future<Catalog> menu() => PostgresCatalogRepository(
    database: db,
    config: pg.config.copyWith(tenantSlug: slug),
  ).load();

  Future<Product> item(int id) async =>
      (await menu()).products.singleWhere((p) => p.id == id);

  Matcher refusedSaying(String words) => throwsA(
    isA<PosDbException>().having((e) => '${e.raw}', 'message', contains(words)),
  );

  // ── the schema ─────────────────────────────────────────────────────────

  group('what the database refuses on its own', () {
    Future<int> rawGroup({
      bool global = true,
      String scope = 'items',
      String name = 'Raw',
    }) async => (await db.query(
      pg.config,
      'INSERT INTO pos_modifier_groups (business_id, name_en, is_global, '
      '  apply_scope) VALUES (@r, @name, @global, @scope) RETURNING id',
      parameters: {
        'r': businessId,
        'name': name,
        'global': global,
        'scope': scope,
      },
    )).first[0]! as int;

    test('a scope other than items, categories or all', () async {
      await expectLater(
        rawGroup(scope: 'branch'),
        refusedSaying('pos_modifier_groups_scope_known'),
      );
    });

    test('a group typed on one item that reaches items by itself', () async {
      await expectLater(
        rawGroup(global: false, scope: 'all'),
        refusedSaying('pos_modifier_groups_scope_is_global'),
      );
    });

    test('a sale price at or above the regular one, or below nothing',
        () async {
      final group = await rawGroup();
      Future<void> option(int price, int? sale) => db.query(
        pg.config,
        'INSERT INTO pos_modifiers (group_id, name_en, price_delta_minor, '
        '  discounted_price_minor) VALUES (@g, @name, @price, @sale)',
        parameters: {'g': group, 'name': 'x', 'price': price, 'sale': sale},
      );

      await expectLater(
        option(1000, 1000),
        refusedSaying('pos_modifiers_sale_price_sane'),
      );
      await expectLater(
        option(1000, -1),
        refusedSaying('pos_modifiers_sale_price_sane'),
      );
      await option(1000, 999);
      await option(1000, null);
    });

    test('category links go with their group, and with their category',
        () async {
      final group = await rawGroup(scope: 'categories');
      final empty = await category('Seasonal');
      await db.query(
        pg.config,
        'INSERT INTO pos_modifier_group_categories (group_id, category_id) '
        'VALUES (@g, @a), (@g, @b)',
        parameters: {'g': group, 'a': burgers, 'b': empty},
      );

      await db.query(
        pg.config,
        'DELETE FROM pos_categories WHERE id = @id',
        parameters: {'id': empty},
      );
      expect(
        await count('SELECT count(*) FROM pos_modifier_group_categories'),
        1,
      );

      await db.query(
        pg.config,
        'DELETE FROM pos_modifier_groups WHERE id = @id',
        parameters: {'id': group},
      );
      expect(
        await count('SELECT count(*) FROM pos_modifier_group_categories'),
        0,
      );
    });

    test('an item link to a group that reaches every item by itself',
        () async {
      // Going round the repository, which never writes this.
      final everywhere = await rawGroup(scope: 'all', name: 'Sauces');
      final burger = await product('Burger');
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_product_modifier_groups (product_id, group_id) '
          'VALUES (@p, @g)',
          parameters: {'p': burger, 'g': everywhere},
        ),
        refusedSaying('"Sauces" already reaches every item by itself'),
      );
    });

    test('a category link to a group that is not category-wide', () async {
      final linked = await rawGroup(name: 'Sauces');
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_modifier_group_categories (group_id, category_id) '
          'VALUES (@g, @c)',
          parameters: {'g': linked, 'c': burgers},
        ),
        refusedSaying('not to chosen categories'),
      );
    });

    test('a scope change that leaves links of the old kind behind', () async {
      final linked = await rawGroup(name: 'Sauces');
      await db.query(
        pg.config,
        'INSERT INTO pos_product_modifier_groups (product_id, group_id) '
        'VALUES (@p, @g)',
        parameters: {'p': await product('Burger'), 'g': linked},
      );
      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_modifier_groups SET apply_scope = 'all' WHERE id = @g",
          parameters: {'g': linked},
        ),
        refusedSaying('still linked to items one by one'),
      );

      final byCategory = await rawGroup(scope: 'categories', name: 'Dips');
      await db.query(
        pg.config,
        'INSERT INTO pos_modifier_group_categories (group_id, category_id) '
        'VALUES (@g, @c)',
        parameters: {'g': byCategory, 'c': burgers},
      );
      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_modifier_groups SET apply_scope = 'all' WHERE id = @g",
          parameters: {'g': byCategory},
        ),
        refusedSaying('still linked to categories'),
      );
    });
  });

  // ── the library ────────────────────────────────────────────────────────

  group('the library', () {
    test('a group round-trips with its options, headings and scope',
        () async {
      final saved = await library(
        sizes.copyWith(scope: OptionGroupScope.categories, categoryIds: {burgers}),
      );

      expect(saved.id, greaterThan(0));
      expect(saved.revision, 1);
      expect(saved.displayNameEn, 'Size');
      expect(saved.scope, OptionGroupScope.categories);
      expect(saved.categoryIds, {burgers});
      expect(saved.options.map((o) => o.nameEn), ['Regular', 'Large']);
      expect(saved.options.every((o) => o.id > 0), isTrue);

      final listed = (await admin.optionLibrary()).single;
      expect(listed.group.id, saved.id);
      expect(
        await count(
          'SELECT count(*) FROM pos_modifier_groups WHERE is_global AND id = @id',
          {'id': saved.id},
        ),
        1,
      );
    });

    test('is listed by name, and counts every item each group reaches',
        () async {
      final burger = await product('Burger');
      await product('Chicken burger');
      await product('Cola', categoryId: drinks);

      final linked = await library(extras.copyWith(nameEn: 'Charlie'));
      await offer(burger, [OptionGroupRef.shared(linked.id)]);
      await library(
        extras.copyWith(
          nameEn: 'Alpha',
          scope: OptionGroupScope.categories,
          categoryIds: {burgers},
        ),
      );
      await library(extras.copyWith(nameEn: 'Bravo', scope: OptionGroupScope.all));

      final listed = await admin.optionLibrary();
      expect(listed.map((g) => g.group.nameEn), ['Alpha', 'Bravo', 'Charlie']);
      // By reach, not by link: the group on every item is on three, not none.
      expect(listed.map((g) => g.itemCount), [2, 3, 1]);
    });

    test('only somebody who may edit the menu can change it', () async {
      final result = await admin.saveOptionGroup(sizes, by: cashier);
      expect(result.refusal, isA<NotPermitted>());

      final cloud = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        offline: false,
      );
      expect(
        (await cloud.saveOptionGroup(sizes, by: manager)).refusal,
        isA<NotPermitted>(),
        reason: 'the platform authors the menu on a cloud till',
      );

      final noCredential = PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        adminAvailable: false,
      );
      expect(
        (await noCredential.saveOptionGroup(sizes, by: manager)).refusal,
        isA<AdministratorCredentialRequired>(),
      );
      expect(
        (await admin.setProductOptionGroups(
          await product('Burger'),
          const [OptionGroupRef.inline(sizes)],
          by: cashier,
        )).refusal,
        isA<NotPermitted>(),
      );
      expect(await admin.optionLibrary(), isEmpty);
    });

    test("the platform's rules are refused, and nothing is written", () async {
      for (final bad in [
        extras.copyWith(nameEn: '  '),
        extras.copyWith(maxSelect: 51),
        extras.copyWith(
          options: [
            for (var i = 0; i < 51; i++) OptionDraft(nameEn: 'Option $i'),
          ],
        ),
        extras.copyWith(
          options: const [OptionDraft(nameEn: 'Less', price: Money(-1))],
        ),
        sizes.copyWith(
          options: const [
            OptionDraft(
              nameEn: 'Regular',
              price: Money(8500),
              salePrice: Money(8500),
            ),
          ],
        ),
        sizes.copyWith(scope: OptionGroupScope.categories),
      ]) {
        final result = await admin.saveOptionGroup(bad, by: manager);
        expect(result.refusal, isA<OptionGroupRefused>(), reason: bad.nameEn);
      }
      expect(await count('SELECT count(*) FROM pos_modifier_groups'), 0);
    });

    test("an extra's sale price is dropped, and a size's is kept", () async {
      final extra = await library(
        extras.copyWith(
          options: const [
            OptionDraft(
              nameEn: 'Cheese',
              price: Money(1500),
              salePrice: Money(1000),
            ),
          ],
        ),
      );
      expect(extra.options.single.salePrice, isNull);

      final size = await library(
        sizes.copyWith(
          options: const [
            OptionDraft(
              nameEn: 'Regular',
              price: Money(8500),
              salePrice: Money(7000),
            ),
          ],
        ),
      );
      expect(size.options.single.salePrice?.minor, 7000);
      expect(
        await count(
          'SELECT count(*) FROM pos_modifiers '
          'WHERE discounted_price_minor IS NOT NULL',
        ),
        1,
      );
    });

    test('a size group is always required and single-select', () async {
      final saved = await library(
        sizes.copyWith(isRequired: false, maxSelect: 5),
      );
      expect(saved.isRequired, isTrue);
      expect(saved.maxSelect, 1);
    });

    test("a category-wide group reaches only this business's categories",
        () async {
      final other = (await db.query(
        pg.config,
        "INSERT INTO pos_businesses (slug, name) VALUES ('elsewhere', 'Else') "
        'RETURNING id',
      )).first[0]! as int;
      final theirs = await category('Theirs', business: other);

      final result = await admin.saveOptionGroup(
        extras.copyWith(
          scope: OptionGroupScope.categories,
          categoryIds: {burgers, theirs},
        ),
        by: manager,
      );
      expect(
        problemOf(result.refusal),
        OptionGroupProblem.foreignCategory,
        reason: why(result.refusal),
      );
    });

    test('leaving chosen items takes the group off the items it was on',
        () async {
      final burger = await product('Burger');
      final saved = await library(extras);
      await offer(burger, [OptionGroupRef.shared(saved.id)]);

      await library(saved.copyWith(scope: OptionGroupScope.all));
      expect(
        await count(
          'SELECT count(*) FROM pos_product_modifier_groups WHERE group_id = @g',
          {'g': saved.id},
        ),
        0,
      );
      // And it is still on the item, by the new path, once.
      expect((await item(burger)).modifierGroupIds, [saved.id]);
    });

    test('leaving categories takes the group off its categories', () async {
      final saved = await library(
        extras.copyWith(
          scope: OptionGroupScope.categories,
          categoryIds: {burgers, drinks},
        ),
      );
      final narrowed = await library(saved.copyWith(categoryIds: {drinks}));
      expect(narrowed.categoryIds, {drinks});

      await library(narrowed.copyWith(scope: OptionGroupScope.items));
      expect(
        await count('SELECT count(*) FROM pos_modifier_group_categories'),
        0,
      );
    });

    test('a save based on an older read is refused', () async {
      final first = await library(extras);
      await library(first.copyWith(nameEn: 'Toppings'));

      final result = await admin.saveOptionGroup(
        first.copyWith(nameEn: 'Add-ons'),
        by: manager,
      );
      expect(
        result.refusal,
        isA<EditedElsewhere>().having((e) => e.currentRevision, 'current', 2),
      );
    });

    test("another group's option cannot be moved into this one", () async {
      final a = await library(extras);
      final b = await library(sizes);

      final result = await admin.saveOptionGroup(
        b.copyWith(options: [...b.options, a.options.first]),
        by: manager,
      );
      expect(
        problemOf(result.refusal),
        OptionGroupProblem.foreignOption,
        reason: why(result.refusal),
      );
    });

    test('a group typed on one item is not the library\'s to edit or delete',
        () async {
      final refs = await offer(await product('Burger'), [
        const OptionGroupRef.inline(extras),
      ]);
      final typed = own(refs, 0);

      expect(
        (await admin.saveOptionGroup(typed, by: manager)).refusal,
        isA<OptionGroupRefused>(),
      );
      expect(
        (await admin.deleteOptionGroup(typed, by: manager)).refusal,
        isA<OptionGroupRefused>(),
      );
      expect(await admin.optionLibrary(), isEmpty);
    });

    test('deleting a library group takes it off every item', () async {
      final burger = await product('Burger');
      final chicken = await product('Chicken burger');
      final saved = await library(extras);
      await offer(burger, [OptionGroupRef.shared(saved.id)]);
      await offer(chicken, [OptionGroupRef.shared(saved.id)]);

      final result = await admin.deleteOptionGroup(saved, by: manager);
      expect(result.succeeded, isTrue, reason: why(result.refusal));

      expect(await count('SELECT count(*) FROM pos_modifier_groups'), 0);
      expect(await count('SELECT count(*) FROM pos_modifiers'), 0);
      expect(await count('SELECT count(*) FROM pos_product_modifier_groups'), 0);
      expect((await item(burger)).modifierGroupIds, isEmpty);
    });
  });

  // ── option ids ─────────────────────────────────────────────────────────

  group('an option keeps its id', () {
    test('across a rename, a reprice, a reorder and an addition', () async {
      // **The platform reissues every id on every save.** Here a parked
      // ticket and every order line name options by id, so a Large that
      // became a different number when somebody fixed a typo in "Regular" is
      // a Large nothing can find again.
      final first = await library(sizes);
      final regular = first.options[0].id;
      final large = first.options[1].id;

      final edited = await library(
        first.copyWith(
          options: [
            first.options[1].copyWith(price: const Money(11500)),
            const OptionDraft(nameEn: 'Medium', price: Money(9500)),
            first.options[0].copyWith(nameEn: 'Regular size'),
          ],
        ),
      );
      expect(edited.options.map((o) => o.nameEn), [
        'Large',
        'Medium',
        'Regular size',
      ]);
      expect(edited.options[0].id, large);
      expect(edited.options[2].id, regular);
      expect(edited.options[1].id, isNot(anyOf(large, regular)));
      expect(edited.options[0].price.minor, 11500);

      // Taking one away deletes that one, and only that one.
      final trimmed = await library(
        edited.copyWith(options: [edited.options[0], edited.options[1]]),
      );
      expect(trimmed.options.map((o) => o.id), [
        large,
        edited.options[1].id,
      ]);
      expect(
        await count(
          'SELECT count(*) FROM pos_modifiers WHERE id = @id',
          {'id': regular},
        ),
        0,
      );
    });

    test('on a group typed on an item, saved with the item', () async {
      final burger = await product('Burger');
      final first = own(
        await offer(burger, const [OptionGroupRef.inline(sizes)]),
        0,
      );

      // Read back the way the editor would, and edited.
      final read = own(await admin.productOptionGroups(burger), 0);
      final again = own(
        await offer(burger, [
          OptionGroupRef.inline(
            read.copyWith(
              options: [
                read.options[0].copyWith(price: const Money(9000)),
                read.options[1],
              ],
            ),
          ),
        ]),
        0,
      );

      expect(again.id, first.id, reason: 'the group itself stays too');
      expect(
        again.options.map((o) => o.id),
        first.options.map((o) => o.id),
      );
      expect(again.options.first.price.minor, 9000);
    });
  });

  // ── an item's groups ───────────────────────────────────────────────────

  group("an item's groups", () {
    test('are written in the order given, shared and typed together',
        () async {
      final burger = await product('Burger');
      final shared = await library(extras);

      final refs = await offer(burger, [
        const OptionGroupRef.inline(sizes),
        OptionGroupRef.shared(shared.id),
        OptionGroupRef.inline(extras.copyWith(nameEn: 'Sauces')),
      ]);

      expect(refs[0], isA<InlineGroupRef>());
      expect((refs[1] as SharedGroupRef).groupId, shared.id);
      expect(own(refs, 2).nameEn, 'Sauces');

      final order = await db.query(
        pg.config,
        'SELECT group_id, sort_order FROM pos_product_modifier_groups '
        'WHERE product_id = @p ORDER BY sort_order',
        parameters: {'p': burger},
      );
      expect(order.map((r) => r[1]), [0, 1, 2]);
      expect((await item(burger)).modifierGroupIds, [
        own(refs, 0).id,
        shared.id,
        own(refs, 2).id,
      ]);
    });

    test('a typed group belongs to that item alone', () async {
      final burger = await product('Burger');
      final chicken = await product('Chicken burger');
      final typed = own(
        await offer(burger, const [OptionGroupRef.inline(extras)]),
        0,
      );

      expect(
        await count(
          'SELECT count(*) FROM pos_modifier_groups WHERE id = @g AND NOT is_global',
          {'g': typed.id},
        ),
        1,
      );

      final byId = await admin.setProductOptionGroups(
        chicken,
        [OptionGroupRef.shared(typed.id)],
        by: manager,
      );
      expect(
        problemOf(byId.refusal),
        OptionGroupProblem.notInLibrary,
        reason: why(byId.refusal),
      );

      final whole = await admin.setProductOptionGroups(
        chicken,
        [OptionGroupRef.inline(typed)],
        by: manager,
      );
      expect(
        problemOf(whole.refusal),
        OptionGroupProblem.typedOnAnotherItem,
        reason: why(whole.refusal),
      );
    });

    test('a typed group the list no longer names is deleted', () async {
      final burger = await product('Burger');
      final typed = own(
        await offer(burger, const [OptionGroupRef.inline(extras)]),
        0,
      );

      await offer(burger, const []);
      expect(await count('SELECT count(*) FROM pos_modifier_groups'), 0);
      expect(await count('SELECT count(*) FROM pos_modifiers'), 0);

      // Scoped to this test's business: the ledger is append-only, so the
      // rows every earlier test wrote are still there.
      final ledger = await db.query(
        pg.config,
        'SELECT entity_id FROM pos_audit_events '
        'WHERE action = @a AND business_id = @r',
        parameters: {'a': AuditAction.optionGroupDeleted, 'r': businessId},
      );
      expect(ledger.single[0], '${typed.id}');
    });

    test('a library group that reaches items by itself is not added by hand',
        () async {
      final everywhere = await library(
        extras.copyWith(scope: OptionGroupScope.all),
      );
      final result = await admin.setProductOptionGroups(
        await product('Burger'),
        [OptionGroupRef.shared(everywhere.id)],
        by: manager,
      );
      expect(
        problemOf(result.refusal),
        OptionGroupProblem.alreadyReaches,
        reason: why(result.refusal),
      );
    });

    test('the same group twice is refused', () async {
      final shared = await library(extras);
      final result = await admin.setProductOptionGroups(
        await product('Burger'),
        [OptionGroupRef.shared(shared.id), OptionGroupRef.shared(shared.id)],
        by: manager,
      );
      expect(result.refusal, isA<OptionGroupRefused>());
    });

    test('an edit based on an older read of a typed group is refused',
        () async {
      final burger = await product('Burger');
      final stale = own(
        await offer(burger, const [OptionGroupRef.inline(extras)]),
        0,
      );
      await offer(burger, [
        OptionGroupRef.inline(stale.copyWith(nameEn: 'Toppings')),
      ]);

      final result = await admin.setProductOptionGroups(
        burger,
        [OptionGroupRef.inline(stale.copyWith(nameEn: 'Add-ons'))],
        by: manager,
      );
      expect(result.refusal, isA<EditedElsewhere>());
    });

    test('saving an item does not rewrite the groups nobody touched',
        () async {
      final burger = await product('Burger');
      final refs = await offer(burger, [
        const OptionGroupRef.inline(sizes),
        const OptionGroupRef.inline(extras),
      ]);
      final untouched = own(refs, 1);

      final again = await offer(burger, [
        OptionGroupRef.inline(own(refs, 0).copyWith(nameEn: 'Sizes')),
        OptionGroupRef.inline(untouched),
      ]);
      expect(own(again, 1).revision, untouched.revision);
      expect(own(again, 0).revision, own(refs, 0).revision + 1);
    });
  });

  // ── one set of sizes ───────────────────────────────────────────────────

  group('an item has one set of sizes', () {
    test('two typed on it, or one typed and one shared, are refused',
        () async {
      final burger = await product('Burger');
      final shared = await library(sizes.copyWith(nameEn: 'Shared sizes'));

      for (final both in [
        [
          const OptionGroupRef.inline(sizes),
          OptionGroupRef.inline(sizes.copyWith(nameEn: 'Portion')),
        ],
        [const OptionGroupRef.inline(sizes), OptionGroupRef.shared(shared.id)],
      ]) {
        final result = await admin.setProductOptionGroups(
          burger,
          both,
          by: manager,
        );
        expect(
        problemOf(result.refusal),
        OptionGroupProblem.secondSizes,
        reason: why(result.refusal),
      );
      }
      expect(await admin.productOptionGroups(burger), isEmpty);
    });

    test('a size group that reaches the item by itself counts', () async {
      final burger = await product('Burger');
      await library(
        sizes.copyWith(
          nameEn: 'Burger sizes',
          scope: OptionGroupScope.categories,
          categoryIds: {burgers},
        ),
      );

      final result = await admin.setProductOptionGroups(
        burger,
        [OptionGroupRef.inline(sizes.copyWith(nameEn: 'Own sizes'))],
        by: manager,
      );
      expect(
        problemOf(result.refusal),
        OptionGroupProblem.secondSizes,
        reason: why(result.refusal),
      );
    });

    test('and the library cannot hand a second set to an item that has one',
        () async {
      await offer(await product('Burger'), const [
        OptionGroupRef.inline(sizes),
      ]);

      final result = await admin.saveOptionGroup(
        sizes.copyWith(nameEn: 'House sizes', scope: OptionGroupScope.all),
        by: manager,
      );
      final refusal = result.refusal;
      expect(refusal, isA<OptionGroupRefused>(), reason: why(refusal));
      refusal as OptionGroupRefused;
      expect(refusal.problem, OptionGroupProblem.wouldGiveSecondSizes);
      // The item it names is data beside the code, for each language to
      // place — not a quoted word inside an English sentence.
      expect(refusal.names, ['Burger']);
      expect(await admin.optionLibrary(), isEmpty);
    });
  });

  // ── what the till reads ────────────────────────────────────────────────

  group('what the till reads', () {
    test("library groups trail the item's own, by name", () async {
      final burger = await product('Burger');
      final cola = await product('Cola', categoryId: drinks);

      final zeta = own(
        await offer(burger, [
          OptionGroupRef.inline(extras.copyWith(nameEn: 'Zeta')),
        ]),
        0,
      );
      final bravo = await library(
        extras.copyWith(nameEn: 'Bravo', scope: OptionGroupScope.all),
      );
      final alpha = await library(
        extras.copyWith(
          nameEn: 'Alpha',
          scope: OptionGroupScope.categories,
          categoryIds: {burgers},
        ),
      );
      final charlie = await library(
        extras.copyWith(
          nameEn: 'Charlie',
          scope: OptionGroupScope.categories,
          categoryIds: {drinks},
        ),
      );

      expect((await item(burger)).modifierGroupIds, [
        zeta.id,
        alpha.id,
        bravo.id,
      ]);
      expect((await item(cola)).modifierGroupIds, [bravo.id, charlie.id]);
    });

    test('a group that reaches an item two ways is on its sheet once',
        () async {
      // Unreachable through the repository and refused by migration 45 — so
      // the second path is written with the trigger off, as a row from before
      // it, or from a writer that went round it, would be.
      final burger = await product('Burger');
      final linked = await library(extras.copyWith(nameEn: 'Linked'));
      final everywhere = await library(
        extras.copyWith(nameEn: 'Everywhere', scope: OptionGroupScope.all),
      );
      await offer(burger, [OptionGroupRef.shared(linked.id)]);

      await db.query(
        pg.config,
        'ALTER TABLE pos_product_modifier_groups '
        'DISABLE TRIGGER pos_product_modifier_groups_follow_scope',
      );
      try {
        await db.query(
          pg.config,
          'INSERT INTO pos_product_modifier_groups '
          '  (product_id, group_id, sort_order) VALUES (@p, @g, -1)',
          parameters: {'p': burger, 'g': everywhere.id},
        );
      } finally {
        await db.query(
          pg.config,
          'ALTER TABLE pos_product_modifier_groups '
          'ENABLE TRIGGER pos_product_modifier_groups_follow_scope',
        );
      }

      expect((await item(burger)).modifierGroupIds, [
        everywhere.id,
        linked.id,
      ], reason: 'once, at the position its link gives it');
    });

    test('an item with sizes is priced by its first size', () async {
      final burger = await product('Burger', price: 5000, discounted: 4500);
      await offer(burger, const [
        OptionGroupRef.inline(extras),
        OptionGroupRef.inline(sizes),
      ]);

      final priced = await item(burger);
      expect(priced.price.minor, 8500);
      expect(
        priced.discountedPrice,
        isNull,
        reason: "never the size's price beside the item's own discount",
      );

      final catalog = await menu();
      final size = catalog.groupsFor(priced).firstWhere((g) => g.isVariant);
      expect(size.modifiers.map((m) => m.priceDelta.minor), [8500, 11000]);
      expect(size.modifiers.every((m) => m.isVariant), isTrue);
      final extra = catalog.groupsFor(priced).firstWhere((g) => !g.isVariant);
      expect(extra.modifiers.map((m) => m.priceDelta.minor), [1500, 2500]);
    });

    test("the default size's sale price is the item's offer, and is charged",
        () async {
      final burger = await product('Burger');
      await offer(burger, [
        OptionGroupRef.inline(
          sizes.copyWith(
            options: const [
              OptionDraft(
                nameEn: 'Regular',
                price: Money(8500),
                salePrice: Money(7000),
              ),
              OptionDraft(nameEn: 'Large', price: Money(11000)),
            ],
          ),
        ),
      ]);

      final priced = await item(burger);
      expect(priced.price.minor, 8500);
      expect(priced.discountedPrice?.minor, 7000);

      final regular = (await menu()).groupsFor(priced).single.modifiers.first;
      expect(regular.priceDelta.minor, 7000, reason: 'what the size charges');
      expect(
        priceWithOptions(priced, [regular]).minor,
        priced.effectivePrice.minor,
        reason: 'the tile and an untouched add agree',
      );
    });

    test('an unavailable first size is skipped for the next', () async {
      final burger = await product('Burger');
      await offer(burger, [
        OptionGroupRef.inline(
          sizes.copyWith(
            options: const [
              OptionDraft(
                nameEn: 'Regular',
                price: Money(8500),
                isAvailable: false,
              ),
              OptionDraft(nameEn: 'Large', price: Money(11000)),
            ],
          ),
        ),
      ]);
      expect((await item(burger)).price.minor, 11000);
    });

    test('deleting the shared size group puts the item back on its own price',
        () async {
      // **The drift the platform has.** It copies the default size into the
      // item's price columns on each write, and deleting a shared size group
      // is a write that forgets to — the item goes on advertising a size it
      // no longer has. Derived at the read, there is nothing to forget.
      final burger = await product('Burger', price: 5000, discounted: 4500);
      final shared = await library(sizes);
      await offer(burger, [OptionGroupRef.shared(shared.id)]);
      expect((await item(burger)).price.minor, 8500);

      await admin.deleteOptionGroup(shared, by: manager);

      final back = await item(burger);
      expect(back.price.minor, 5000);
      expect(back.discountedPrice?.minor, 4500);
    });

    test('a business-wide size group prices every item', () async {
      final burger = await product('Burger');
      final cola = await product('Cola', categoryId: drinks, price: 1200);
      await library(sizes.copyWith(scope: OptionGroupScope.all));

      expect((await item(burger)).price.minor, 8500);
      expect((await item(cola)).price.minor, 8500);
    });

    test('the sheet is headed by the display name', () async {
      final burger = await product('Burger');
      await offer(burger, const [OptionGroupRef.inline(sizes)]);

      final heading = (await menu()).groupsFor(await item(burger)).single;
      expect(heading.displayName('en'), 'Size');
      expect(heading.displayName('ar'), 'الحجم');
      expect(heading.nameEn, 'Burger sizes', reason: 'the library name stays');
    });
  });

  // ── the ledger ─────────────────────────────────────────────────────────

  group('the ledger', () {
    /// This test's rows only. The ledger is append-only — deleting the
    /// business in `setUp` leaves every earlier test's rows where they are —
    /// and each test's business is a new id.
    Future<List<List<Object?>>> rows(String action) async => [
      for (final row in await db.query(
        pg.config,
        'SELECT entity_type, entity_id, actor_name, before_value, after_value '
        'FROM pos_audit_events WHERE action = @a AND business_id = @r '
        'ORDER BY id',
        parameters: {'a': action, 'r': businessId},
      ))
        row.toList(),
    ];

    test('says who saved, repriced and deleted a group, and what it held',
        () async {
      final saved = await library(sizes);
      final created = (await rows(AuditAction.optionGroupSaved)).single;
      expect(created[0], AuditAction.entityOptionGroup);
      expect(created[1], '${saved.id}');
      expect(created[2], 'Amer M.');

      await library(
        saved.copyWith(
          options: [
            saved.options[0].copyWith(price: const Money(9000)),
            saved.options[1],
          ],
        ),
      );
      final repriced = (await rows(AuditAction.optionGroupRepriced)).single;
      final before = _payload(repriced[3])['options']! as List;
      final after = _payload(repriced[4])['options']! as List;
      expect((before.first as Map)['price_minor'], 8500);
      expect((after.first as Map)['price_minor'], 9000);

      final current = (await admin.optionLibrary()).single.group;
      await admin.deleteOptionGroup(current, by: manager);
      final deleted = (await rows(AuditAction.optionGroupDeleted)).single;
      expect(_payload(deleted[3])['name'], 'Burger sizes');
    });

    test("says which groups an item offered before and after", () async {
      final burger = await product('Burger');
      final shared = await library(extras);
      final first = await offer(burger, [OptionGroupRef.shared(shared.id)]);
      final second = await offer(burger, [
        const OptionGroupRef.inline(sizes),
        ...first,
      ]);

      final changed = (await rows(AuditAction.productOptionsChanged)).last;
      expect(changed[0], AuditAction.entityProduct);
      expect(changed[1], '$burger');
      expect(_payload(changed[3])['option_groups'], [shared.id]);
      expect(_payload(changed[4])['option_groups'], [
        own(second, 0).id,
        shared.id,
      ]);
    });
  });

  // ── the ids form ───────────────────────────────────────────────────────

  group('attachModifierGroups, kept for its callers', () {
    test("links library groups and keeps the item's own as they are",
        () async {
      final burger = await product('Burger');
      final shared = await library(extras);
      final typed = own(
        await offer(burger, const [OptionGroupRef.inline(sizes)]),
        0,
      );

      final result = await admin.attachModifierGroups(
        burger,
        [shared.id, typed.id, shared.id],
        by: manager,
      );
      expect(result.succeeded, isTrue, reason: why(result.refusal));

      final refs = await admin.productOptionGroups(burger);
      expect((refs[0] as SharedGroupRef).groupId, shared.id);
      expect(own(refs, 1).id, typed.id);
      expect(own(refs, 1).revision, typed.revision, reason: 'untouched');
      expect(
        own(refs, 1).options.map((o) => o.id),
        typed.options.map((o) => o.id),
      );
    });

    test("refuses another item's group rather than sharing it", () async {
      final typed = own(
        await offer(await product('Burger'), const [
          OptionGroupRef.inline(extras),
        ]),
        0,
      );
      final result = await admin.attachModifierGroups(
        await product('Chicken burger'),
        [typed.id],
        by: manager,
      );
      expect(result.refusal, isA<OptionGroupRefused>());
    });
  });
}
