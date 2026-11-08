@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_directory_repositories.dart';
import 'package:xorder_pos/data/postgres/postgres_floor_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_tenant.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// The reads that replaced the fakes.
///
/// These matter more than most: they are what the till *shows a cashier*, and
/// the implementations they replaced were incapable of being wrong because they
/// returned constants. Every question here is one a business would ask —
/// is this my menu, my floor, my staff, and can somebody else's code claim my
/// till.
void main() {
  if (PgFixture.host == null) {
    test('directory reads (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;
  late int branchId;
  late int otherBranchId;
  late String terminalId;

  const slug = 'directory-test';
  const pin = '2468';

  setUp(() async {
    pg = await PgFixture.open('directory');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);

    // Every test starts from an empty business. Cascades take the rest, which
    // is why the foreign keys were written with ON DELETE CASCADE.
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    final business = await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES (@slug, 'Directory Test') RETURNING id",
      parameters: {'slug': slug},
    );
    businessId = business.first[0] as int;

    final branch = await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name, supported_order_types) "
      "VALUES (@r, 'MAIN', 'Main', ARRAY['dine_in','takeaway']) RETURNING id",
      parameters: {'r': businessId},
    );
    branchId = branch.first[0] as int;

    final other = await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'OTHER', 'Other') RETURNING id",
      parameters: {'r': businessId},
    );
    otherBranchId = other.first[0] as int;

    final salt = PinHash.newSalt();
    await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, branch_id, name, username, pin_salt, pin_hash, capabilities) '
      "VALUES (@r, @b, 'Sara M.', 'sara', @salt, @hash, ARRAY['pos.operate','pos.reprint'])",
      parameters: {
        'r': businessId,
        'b': branchId,
        'salt': salt,
        'hash': await PinHash.hash(pin, salt),
      },
    );

    final terminal = await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name, pairing_code) '
      "VALUES (gen_random_uuid(), @r, @b, 'Counter 1', 'MAIN-AAAA') RETURNING id::text",
      parameters: {'r': businessId, 'b': branchId},
    );
    terminalId = terminal.first[0] as String;
  });

  tearDown(() => pg.close());

  PostgresCatalogRepository catalogue() =>
      PostgresCatalogRepository(database: db, config: pg.config.copyWith(tenantSlug: slug));

  PostgresBranchRepository branches() =>
      PostgresBranchRepository(database: db, config: pg.config.copyWith(tenantSlug: slug));

  PostgresProvisioningRepository provisioning() =>
      PostgresProvisioningRepository(database: db, config: pg.config);

  PostgresSessionRepository session({int? branch}) => PostgresSessionRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        branchId: branch ?? branchId,
        terminalId: terminalId,
      );

  group('the menu', () {
    Future<void> seedMenu() async {
      final category = await db.query(
        pg.config,
        "INSERT INTO pos_categories (business_id, name_en, name_ar, slug, sort_order) "
        "VALUES (@r, 'Grills', 'مشويات', 'grills', 1) RETURNING id",
        parameters: {'r': businessId},
      );
      final group = await db.query(
        pg.config,
        "INSERT INTO pos_modifier_groups (business_id, name_en, is_required, max_select) "
        "VALUES (@r, 'Doneness', true, 1) RETURNING id",
        parameters: {'r': businessId},
      );
      await db.query(
        pg.config,
        'INSERT INTO pos_modifiers (group_id, name_en, price_delta_minor, sort_order) '
        "VALUES (@g, 'Medium', 0, 1), (@g, 'Extra sauce', 1500, 2)",
        parameters: {'g': group.first[0]},
      );
      final product = await db.query(
        pg.config,
        'INSERT INTO pos_products (business_id, category_id, name_en, name_ar, price_minor, sku, barcode) '
        "VALUES (@r, @c, 'Kofta', 'كفتة', 24500, 'GRL-002', '6221031492') RETURNING id",
        parameters: {'r': businessId, 'c': category.first[0]},
      );
      await db.query(
        pg.config,
        'INSERT INTO pos_product_modifier_groups (product_id, group_id) VALUES (@p, @g)',
        parameters: {'p': product.first[0], 'g': group.first[0]},
      );
    }

    test('comes back priced, named in both languages and wired to its options', () async {
      await seedMenu();
      final catalog = await catalogue().load();

      expect(catalog.categories.single.nameEn, 'Grills');
      expect(catalog.categories.single.nameAr, 'مشويات');

      final kofta = catalog.products.single;
      expect(kofta.nameEn, 'Kofta');
      expect(kofta.nameAr, 'كفتة');
      // Minor units all the way from the column, never through a double.
      expect(kofta.price.minor, 24500);
      expect(kofta.sku, 'GRL-002');

      // The join is what makes the modifier sheet open at all. A product whose
      // groups were dropped in transit is one the cashier cannot ring up
      // correctly and has no way to know is wrong.
      expect(catalog.groupsFor(kofta), hasLength(1));
      final group = catalog.groupsFor(kofta).single;
      expect(group.isRequired, isTrue);
      expect(group.isSingleSelect, isTrue);
      expect(group.modifiers.map((m) => m.nameEn), ['Medium', 'Extra sauce']);
      expect(group.modifiers.last.priceDelta.minor, 1500);
    });

    test('an unavailable product still comes back, marked unavailable', () async {
      await seedMenu();
      await db.query(pg.config, 'UPDATE pos_products SET is_available = false');

      // Not filtered out in SQL on purpose: the grid shows an 86'd item greyed
      // with OUT, which tells the cashier the kitchen is out rather than
      // leaving them hunting for a product that has silently vanished.
      final catalog = await catalogue().load();
      expect(catalog.products.single.isAvailable, isFalse);
    });

    test('a barcode finds exactly one product', () async {
      await seedMenu();
      final catalog = await catalogue().load();

      expect(catalog.byBarcode('6221031492')?.nameEn, 'Kofta');
      expect(catalog.byBarcode('0000000000'), isNull);
    });

    test('another business\'s menu is not this one\'s', () async {
      await seedMenu();
      final other = await db.query(
        pg.config,
        "INSERT INTO pos_businesses (slug, name) VALUES ('somebody-else', 'Somebody Else') RETURNING id",
      );
      final otherCategory = await db.query(
        pg.config,
        "INSERT INTO pos_categories (business_id, name_en) VALUES (@r, 'Theirs') RETURNING id",
        parameters: {'r': other.first[0]},
      );
      await db.query(
        pg.config,
        'INSERT INTO pos_products (business_id, category_id, name_en, price_minor) '
        "VALUES (@r, @c, 'Their Burger', 9900)",
        parameters: {'r': other.first[0], 'c': otherCategory.first[0]},
      );

      final catalog = await catalogue().load();
      expect(catalog.products.map((p) => p.nameEn), ['Kofta']);
      expect(catalog.categories.map((c) => c.nameEn), ['Grills']);
    });

    test('a tenant slug that matches nothing is an explained refusal', () async {
      final wrong = PostgresCatalogRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: 'no-such-business'),
      );

      // Not an empty menu: an empty menu looks like a business that sells
      // nothing, and the operator would go looking for the wrong fault.
      await expectLater(
        wrong.load(),
        throwsA(
          isA<PosTenantMissing>().having(
            (e) => e.toString(),
            'message',
            contains('no-such-business'),
          ),
        ),
      );
    });
  });

  group('the floor', () {
    setUp(() async {
      await db.query(
        pg.config,
        'INSERT INTO pos_dining_tables (business_id, branch_id, label, seats, sort_order) '
        'VALUES (@r, @b, @l1, 2, 1), (@r, @b, @l2, 6, 2)',
        parameters: {'r': businessId, 'b': branchId, 'l1': 'T1', 'l2': 'T2'},
      );
      await db.query(
        pg.config,
        "INSERT INTO pos_dining_tables (business_id, branch_id, label, seats) "
        "VALUES (@r, @b, 'X1', 4)",
        parameters: {'r': businessId, 'b': otherBranchId},
      );
    });

    PostgresFloorRepository floor() => PostgresFloorRepository(
          database: db,
          config: pg.config,
          businessId: businessId,
          branchId: branchId,
        );

    test('is this branch\'s tables, in the order they were given', () async {
      final tables = await floor().liveFloor();

      expect(tables.map((t) => t.label), ['T1', 'T2']);
      expect(tables.map((t) => t.seats), [2, 6]);
    });

    test('every table reads free, because open tickets are not stored yet', () async {
      // Deliberate, and worth a test so nobody "fixes" it by deriving a state
      // from settled orders: a row in pos_orders means the table was closed.
      // An invented occupancy would put a number on screen that no query could
      // justify.
      final tables = await floor().liveFloor();

      expect(tables.every((t) => t.isFree), isTrue);
      expect(tables.every((t) => t.openTotal == null), isTrue);
    });

    test('a table taken out of service disappears from the floor', () async {
      await db.query(
        pg.config,
        "UPDATE pos_dining_tables SET is_active = false WHERE label = 'T2'",
      );

      expect((await floor().liveFloor()).map((t) => t.label), ['T1']);
    });
  });

  group('branches', () {
    test('come back with the invoice prefix the sequence will use', () async {
      final list = await branches().forTenant();

      expect(list.map((b) => b.name), ['Main', 'Other']);
      expect(list.first.code, 'MAIN');
      expect(list.first.supportedOrderTypes, ['dine_in', 'takeaway']);
    });

    test('a closed branch is not offered to a terminal being set up', () async {
      await db.query(pg.config, "UPDATE pos_branches SET is_active = false WHERE code = 'OTHER'");

      expect((await branches().forTenant()).map((b) => b.code), ['MAIN']);
    });
  });

  group('claiming a terminal', () {
    test('adopts what the dashboard already decided about this till', () async {
      final result = await provisioning().claimByCode(tenantSlug: slug, code: 'MAIN-AAAA');

      expect(result.succeeded, isTrue);
      expect(result.claim!.terminalName, 'Counter 1');
      expect(result.claim!.branchName, 'Main');
      // The invoice prefix and the tenant arrive here, never from anything the
      // installer can type.
      expect(result.claim!.branchCode, 'MAIN');
      expect(result.claim!.businessId, businessId);
      expect(result.claim!.terminalId, terminalId);
    });

    test('is case- and whitespace-forgiving, because it is typed at a counter', () async {
      final result = await provisioning().claimByCode(tenantSlug: slug, code: '  main-aaaa  ');

      expect(result.succeeded, isTrue);
    });

    test('a spent code and a wrong code are different problems', () async {
      expect(
        (await provisioning().claimByCode(tenantSlug: slug, code: 'MAIN-ZZZZ')).code,
        'PAIRING_CODE_INVALID',
      );

      expect((await provisioning().claimByCode(tenantSlug: slug, code: 'MAIN-AAAA')).succeeded, isTrue);

      // The operator needs a new code, not another attempt at this one, and
      // "not recognised" would send them checking for a typo instead.
      final again = await provisioning().claimByCode(tenantSlug: slug, code: 'MAIN-AAAA');
      expect(again.code, 'PAIRING_CODE_SPENT');
      expect(again.message, contains('already been used'));
    });

    test('a code cannot be redeemed against the wrong business', () async {
      await db.query(
        pg.config,
        "INSERT INTO pos_businesses (slug, name) VALUES ('somebody-else', 'Somebody Else')",
      );

      final result = await provisioning().claimByCode(
        tenantSlug: 'somebody-else',
        code: 'MAIN-AAAA',
      );
      expect(result.succeeded, isFalse);
      expect(result.code, 'PAIRING_CODE_INVALID');

      // And the real owner's code is still unspent.
      expect((await provisioning().claimByCode(tenantSlug: slug, code: 'MAIN-AAAA')).succeeded, isTrue);
    });

    test('an unknown business is named in the refusal', () async {
      final result = await provisioning().claimByCode(tenantSlug: 'nobody', code: 'MAIN-AAAA');

      expect(result.code, 'TENANT_UNKNOWN');
      expect(result.message, contains('nobody'));
    });
  });

  group('registering a terminal by hand', () {
    test('the right PIN creates a terminal that can trade', () async {
      final result = await provisioning().registerManually(
        tenantSlug: slug,
        username: 'sara',
        password: pin,
        terminalName: 'Counter 2',
        branchId: branchId,
        installId: null,
      );

      expect(result.succeeded, isTrue);
      expect(result.claim!.terminalName, 'Counter 2');
      expect(result.claim!.branchCode, 'MAIN');

      final rows = await db.query(
        pg.config,
        "SELECT count(*) FROM pos_terminals WHERE name = 'Counter 2' AND claimed_at IS NOT NULL",
      );
      expect(rows.first[0], 1);
    });

    test('a wrong PIN and an unknown user are refused identically', () async {
      final wrongPin = await provisioning().registerManually(
        tenantSlug: slug,
        username: 'sara',
        password: '0000',
        terminalName: 'Counter 3',
        branchId: branchId,
        installId: null,
      );
      final unknownUser = await provisioning().registerManually(
        tenantSlug: slug,
        username: 'nobody',
        password: pin,
        terminalName: 'Counter 3',
        branchId: branchId,
        installId: null,
      );

      // Identical on purpose: a wizard that distinguished them would enumerate
      // who works at the business for anyone holding the till.
      expect(wrongPin.succeeded, isFalse);
      expect(unknownUser.succeeded, isFalse);
      expect(wrongPin.message, unknownUser.message);

      final rows = await db.query(
        pg.config,
        "SELECT count(*) FROM pos_terminals WHERE name = 'Counter 3'",
      );
      expect(rows.first[0], 0, reason: 'a refused registration must create nothing');
    });
  });

  group('the session', () {
    test('is the business, the branch and the till this terminal really is', () async {
      final current = await session().current();

      expect(current.tenantName, 'Directory Test');
      expect(current.branchName, 'Main');
      expect(current.terminalCode, 'Counter 1');
      expect(current.userName, 'Sara M.');
      expect(current.can('pos.reprint'), isTrue);
      expect(current.can('pos.void'), isFalse);
    });

    test('a branch with nobody assigned still identifies the till', () async {
      // A missing staff row is a setup problem, not a crash. The operator needs
      // to see which terminal is misconfigured in order to fix it.
      final current = await session(branch: otherBranchId).current();

      expect(current.branchName, 'Other');
      expect(current.userName, contains('No staff'));
    });

    test('the PIN is checked against the stored hash, not the stored PIN', () async {
      final stored = await db.query(pg.config, 'SELECT pin_hash FROM pos_users');

      expect(stored.first[0], isNot(pin), reason: 'the PIN itself must never be in the database');
      expect(await session().verifyPin(pin), isTrue);
      expect(await session().verifyPin('0000'), isFalse);
      expect(await session().verifyPin(''), isFalse);
    });

    test('a cashier at another branch cannot unlock this till', () async {
      final salt = PinHash.newSalt();
      await db.query(
        pg.config,
        'INSERT INTO pos_users (business_id, branch_id, name, username, pin_salt, pin_hash) '
        "VALUES (@r, @b, 'Elsewhere', 'elsewhere', @salt, @hash)",
        parameters: {
          'r': businessId,
          'b': otherBranchId,
          'salt': salt,
          'hash': await PinHash.hash('1357', salt),
        },
      );

      expect(await session().verifyPin('1357'), isFalse);
      expect(await session(branch: otherBranchId).verifyPin('1357'), isTrue);
    });

    /// Two people, one PIN — what a business does on its first afternoon.
    ///
    /// Switching user asks for a name as well as a PIN, and the first version
    /// asked "who holds this PIN" and then checked the name against whoever
    /// came back. The lower staff id always won that race, so the second person
    /// with that PIN was refused under their own name, with a message that read
    /// as though they had typed it wrong.
    test('two people sharing a PIN each sign in as themselves', () async {
      final salt = PinHash.newSalt();
      await db.query(
        pg.config,
        'INSERT INTO pos_users (business_id, branch_id, name, username, '
        'pin_salt, pin_hash) '
        "VALUES (@r, @b, 'Sayed A.', 'sayed', @salt, @hash)",
        parameters: {
          'r': businessId,
          'b': branchId,
          'salt': salt,
          // The SAME PIN the fixture's first member of staff already has.
          'hash': await PinHash.hash(pin, salt),
        },
      );

      final first = await session().signInAs(username: 'sara', pin: pin);
      final second = await session().signInAs(username: 'sayed', pin: pin);

      expect(first?.username, 'sara');
      expect(second?.username, 'sayed', reason: 'the lower id must not win');
      // And the PIN-only path still answers with whoever it finds first, which
      // is all an approval needs.
      expect(await session().verifyPin(pin), isTrue);
    });

    test('the right PIN under the wrong name is refused', () async {
      expect(await session().signInAs(username: 'nobody', pin: pin), isNull);
      expect(await session().signInAs(username: '', pin: pin), isNull);
      expect(await session().signInAs(username: 'sara', pin: '0000'), isNull);
    });

    test('a member of staff who left cannot unlock the till', () async {
      await db.query(pg.config, 'UPDATE pos_users SET is_active = false');

      expect(await session().verifyPin(pin), isFalse);
    });
  });
}
