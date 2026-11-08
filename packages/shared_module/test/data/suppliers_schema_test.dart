@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_suppliers_repository.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/supplier.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Who the business buys from — the first row of the purchasing chain.
void main() {
  if (PgFixture.host == null) {
    test('suppliers (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresSuppliersRepository suppliers;
  late int businessId;

  // Held through a role, as every real installation holds it. A check that
  // read only the direct grants would refuse this person.
  const buyer = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'buyer',
      nameEn: 'Buyer',
      capabilities: {PosCapability.purchaseManage},
    ),
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    capabilities: {PosCapability.operate},
  );

  setUp(() async {
    pg = await PgFixture.open('suppliers');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('buy', 'Buying') "
      'RETURNING id',
    )).first[0]! as int;

    final branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;

    suppliers = PostgresSuppliersRepository(
      database: db,
      config: pg.config,
      adminAvailable: true,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  Future<Supplier> add({
    String name = 'Cairo Poultry',
    String code = '',
    String? tax,
    int terms = 0,
  }) async {
    final result = await suppliers.save(
      Supplier(
        id: 0,
        nameEn: name,
        code: code,
        taxNumber: tax,
        paymentTermDays: terms,
      ),
      by: buyer,
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  group('recording one', () {
    test('a name is all it takes', () async {
      // A business recording a delivery at seven in the morning needs to
      // write down who it came from, not fill in a form.
      final saved = await add();
      expect(saved.nameEn, 'Cairo Poultry');
      expect(saved.isCashOnDelivery, isTrue);
      expect(saved.isActive, isTrue);
    });

    test('everything else round-trips when it is filled in', () async {
      final result = await suppliers.save(
        const Supplier(
          id: 0,
          nameEn: 'Nile Dairy',
          nameAr: 'ألبان النيل',
          code: 'ND-100',
          contactName: 'Hany',
          phone: '+20 100 000 0000',
          email: 'hany@example.invalid',
          address: '12 Corniche',
          taxNumber: '123456789',
          paymentTermDays: 30,
          notes: 'Delivers Tuesdays',
        ),
        by: buyer,
      );

      final saved = result.value!;
      expect(saved.nameAr, 'ألبان النيل');
      expect(saved.code, 'ND-100');
      expect(saved.taxNumber, '123456789');
      expect(saved.paymentTermDays, 30);
      expect(saved.isCashOnDelivery, isFalse);
      expect(saved.displayName('ar'), 'ألبان النيل');
    });

    test('a blank optional field comes back null, not empty', () async {
      // An empty string that reached a purchase invoice would be a contact
      // name the screen shows as present and blank.
      final saved = await add();
      expect(saved.phone, isNull);
      expect(saved.taxNumber, isNull);
      expect(saved.code, isEmpty, reason: 'except the code, which is not null');
    });
  });

  group('what is refused', () {
    test('a nameless supplier', () async {
      final result = await suppliers.save(
        const Supplier(id: 0, nameEn: '   '),
        by: buyer,
      );
      expect(result.refusal, isA<CatalogInvalid>());
    });

    test('a tax number that is not nine digits', () async {
      final result = await suppliers.save(
        const Supplier(id: 0, nameEn: 'X', taxNumber: '1234'),
        by: buyer,
      );
      expect(result.refusal, isA<CatalogInvalid>());
    });

    test('negative payment terms', () async {
      final result = await suppliers.save(
        const Supplier(id: 0, nameEn: 'X', paymentTermDays: -1),
        by: buyer,
      );
      expect(result.refusal, isA<CatalogInvalid>());
    });

    test('somebody who has left, whose role still would allow it', () async {
      // Two separate questions, and `capabilities.contains` answered neither:
      // it cannot see a role, and a set has no opinion about employment.
      // `Authorization.check` asks both.
      final result = await suppliers.save(
        const Supplier(id: 0, nameEn: 'X'),
        by: PosStaff(
          id: 0,
          name: 'Amer M.',
          isActive: false,
          role: buyer.role,
        ),
      );
      expect(result.refusal, isA<NotPermitted>());
      expect(await suppliers.all(), isEmpty);
    });

    test('a cashier — buying is not a shift-floor act', () async {
      final result = await suppliers.save(
        const Supplier(id: 0, nameEn: 'X'),
        by: cashier,
      );
      expect(result.refusal, isA<NotPermitted>());
      expect(await suppliers.all(), isEmpty);
    });

    test('a till with no administrator credential sees nothing', () async {
      await add();
      final locked = PostgresSuppliersRepository(
        database: db,
        config: pg.config,
        adminAvailable: false,
        businessId: businessId,
        branchId: 1,
      );

      // Not an error — a till simply has no business here.
      expect(await locked.all(), isEmpty);
      expect(
        (await locked.save(const Supplier(id: 0, nameEn: 'X'), by: buyer))
            .refusal,
        isA<AdministratorCredentialRequired>(),
      );
    });
  });

  group('codes', () {
    test('two suppliers with no code is normal, not a collision', () async {
      // Blank is the common case. A plain UNIQUE would have made the second
      // one fail, which is why the index is partial.
      await add(name: 'One');
      await add(name: 'Two');
      expect(await suppliers.all(), hasLength(2));
    });

    test('but the same code twice is refused', () async {
      await add(name: 'One', code: 'ACME');
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_suppliers (business_id, name_en, code) '
          "VALUES (@r, 'Two', 'ACME')",
          parameters: {'r': businessId},
        ),
        throwsA(isA<Object>()),
      );
    });

    test('two businesses may share a code', () async {
      await add(name: 'One', code: 'ACME');
      final other = (await db.query(
        pg.config,
        "INSERT INTO pos_businesses (slug, name) VALUES ('o', 'O') RETURNING id",
      )).first[0]! as int;

      await db.query(
        pg.config,
        'INSERT INTO pos_suppliers (business_id, name_en, code) '
        "VALUES (@r, 'Theirs', 'ACME')",
        parameters: {'r': other},
      );
      expect(await suppliers.all(), hasLength(1));
    });
  });

  test('a retired supplier is off the list and still in the editor', () async {
    // Retired, not deleted: their invoices name them, and a purchase history
    // that cannot say who supplied something is not a purchase history.
    final saved = await add();
    await suppliers.save(saved.copyWith(isActive: false), by: buyer);

    expect(await suppliers.all(), isEmpty);
    expect(await suppliers.all(includeInactive: true), hasLength(1));
  });

  test('there is no balance column — it is derived', () async {
    // A stored total drifts the first time somebody voids an invoice inside a
    // transaction that fails halfway.
    final columns = await db.query(
      pg.config,
      "SELECT column_name FROM information_schema.columns "
      "WHERE table_name = 'pos_suppliers'",
    );
    final names = [for (final row in columns) row[0]! as String];
    expect(names, isNot(contains('balance_minor')));
    expect(names, isNot(contains('outstanding_minor')));
  });

  test('the change is audited — money leaves the business here', () async {
    await add(name: 'Cairo Poultry');

    final rows = await db.query(
      pg.config,
      "SELECT action, after_value->>'name' FROM pos_audit_events "
      'WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
      parameters: {'e': AuditAction.entitySupplier},
    );
    // "Who added this account" is the first question a fraud review asks.
    expect(rows.first[0], AuditAction.supplierSaved);
    expect(rows.first[1], 'Cairo Poultry');
  });

  test('the owner and manager roles gain the new capability', () async {
    // Adding a key to `PosCapability.all` does not add it to a role that
    // already exists — the trap migrations 13 and 15 were written for.
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_roles (business_id, code, name_en, capabilities) '
      "VALUES (@r, 'owner', 'Owner', ARRAY['pos.operate']::text[]) RETURNING id",
      parameters: {'r': businessId},
    );
    expect(rows, isNotEmpty);

    // Re-running the migration is how an existing install gets it.
    await pg.replay(27);

    final owner = await db.query(
      pg.config,
      "SELECT capabilities FROM pos_roles WHERE code = 'owner' "
      'AND business_id = @r',
      parameters: {'r': businessId},
    );
    expect(
      (owner.first[0]! as List).cast<String>(),
      contains(PosCapability.purchaseManage),
    );
  });
}
