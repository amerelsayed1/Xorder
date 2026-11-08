@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_receipt_profile_repository.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/receipt_profile.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Who the receipt says sold the food, stored.
///
/// The thing worth testing against a real server is the half-finished state: a
/// business types its trade name on Monday and rings its accountant about
/// the activity code on Thursday, and a store that would not hold Monday's
/// version is a store nobody finishes filling in.
void main() {
  if (PgFixture.host == null) {
    test('receipt profile (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresReceiptProfileRepository repository;
  late int branchId;

  const slug = 'receipt-profile-test';

  late PosStaff manager;
  late PosStaff cashier;

  setUp(() async {
    pg = await PgFixture.open('receipt_profile');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    final business = await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES (@slug, 'Profile Test') "
      'RETURNING id',
      parameters: {'slug': slug},
    );
    final businessId = business.first[0]! as int;

    final branch = await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': businessId},
    );
    branchId = branch.first[0]! as int;

    // Real rows: `updated_by` is a foreign key, and a staff id invented in
    // Dart would pass every test here and fail the first time somebody saved.
    Future<PosStaff> staff(String name, String username, Set<String> caps) async {
      final rows = await db.query(
        pg.config,
        'INSERT INTO pos_users (business_id, branch_id, name, username, '
        "pin_salt, pin_hash, capabilities) VALUES (@r, @b, @n, @u, 'x', 'y', @c) "
        'RETURNING id',
        parameters: {
          'r': businessId,
          'b': branchId,
          'n': name,
          'u': username,
          'c': caps.toList(),
        },
      );
      // Through a role, not as direct grants: that is how a real manager
      // holds `settings.manage`, and it is the shape a permission check that
      // reads only `capabilities` gets wrong.
      return PosStaff(
        id: rows.first[0]! as int,
        name: name,
        username: username,
        role: PosRole(id: 1, code: name, nameEn: name, capabilities: caps),
      );
    }

    manager = await staff('Amer M.', 'amer', {PosCapability.settingsManage});
    cashier = await staff('Rana A.', 'rana', {PosCapability.operate});

    repository = PostgresReceiptProfileRepository(
      database: db,
      config: pg.config,
      readDatabase: db,
      readConfig: pg.config.copyWith(tenantSlug: slug),
      adminAvailable: true,
      businessId: businessId,
      branchId: branchId,
    );
  });

  tearDown(() => pg.close());

  ReceiptProfile complete({int revision = 0}) => ReceiptProfile(
    branchId: branchId,
    tradeName: 'Koshari Abou Tarek',
    registrationNumber: '123456789',
    activityCode: '5610',
    branchCode: 'B1',
    address: const BranchAddress(
      governate: 'Cairo',
      regionCity: 'Downtown',
      street: 'Champollion',
      buildingNumber: '16',
    ),
    phone: '+20 2 2577 5935',
    footerNote: 'Open until 2am',
    revision: revision,
  );

  test('a branch nobody has set up reads as blank, not as an error', () async {
    final profile = await repository.load();
    expect(profile.isBlank, isTrue);
    expect(profile.branchId, branchId);
  });

  test('what is saved is what the receipt then reads', () async {
    await repository.save(complete(), by: manager);

    final read = await repository.load();
    expect(read.tradeName, 'Koshari Abou Tarek');
    expect(read.registrationNumber, '123456789');
    expect(read.address.street, 'Champollion');
    expect(read.phone, '+20 2 2577 5935');
    expect(read.footerNote, 'Open until 2am');
    expect(read.canFile, isTrue);
  });

  test('a half-finished profile saves', () async {
    // Monday. The name and nothing else.
    final result = await repository.save(
      ReceiptProfile(branchId: branchId, tradeName: 'Koshari'),
      by: manager,
    );

    expect(result.succeeded, isTrue);
    final read = await repository.load();
    expect(read.canPrint, isTrue);
    expect(read.canFile, isFalse, reason: 'and it knows it is not done');
  });

  test('an unset optional field comes back null, not as an empty string',
      () async {
    await repository.save(
      ReceiptProfile(branchId: branchId, tradeName: 'Koshari'),
      by: manager,
    );

    // The column is NOT NULL DEFAULT '', so this is the read layer's job. A
    // '' that reached the ETA document would be a field the authority sees as
    // present and empty rather than absent.
    final read = await repository.load();
    expect(read.phone, isNull);
    expect(read.address.postalCode, isNull);
  });

  test('a nameless profile is refused', () async {
    final result = await repository.save(
      ReceiptProfile(branchId: branchId),
      by: manager,
    );
    expect(result.refusal, isA<CatalogInvalid>());
  });

  test('a cashier cannot change what the receipt claims', () async {
    final result = await repository.save(complete(), by: cashier);
    expect(result.refusal, isA<NotPermitted>());
    expect((await repository.load()).isBlank, isTrue);
  });

  test('the office and the counter cannot overwrite each other', () async {
    final first = await repository.save(complete(), by: manager);
    expect(first.value!.revision, 1);

    // The counter still holds revision 0 — it loaded before the office saved.
    final stale = await repository.save(complete(), by: manager);
    expect(stale.refusal, isA<EditedElsewhere>());
    expect((stale.refusal! as EditedElsewhere).currentRevision, 1);

    // And the office's version is the one that stands.
    expect((await repository.load()).tradeName, 'Koshari Abou Tarek');
  });

  test('a second save with the current revision goes through', () async {
    final first = await repository.save(complete(), by: manager);
    final second = await repository.save(
      first.value!.copyWith(tradeName: 'Koshari Downtown'),
      by: manager,
    );

    expect(second.succeeded, isTrue);
    expect((await repository.load()).tradeName, 'Koshari Downtown');
    expect(second.value!.revision, 2);
  });

  test('the change is audited, naming the registration number', () async {
    await repository.save(complete(), by: manager);

    final rows = await db.query(
      pg.config,
      "SELECT action, after_value->>'rin', actor_name FROM pos_audit_events "
      'WHERE entity_type = @e ORDER BY id DESC LIMIT 1',
      parameters: {'e': AuditAction.entityReceiptProfile},
    );

    // Its own action, not a generic settings change: the registration number
    // is the field a receipt is judged on, and "who put that number there"
    // is the question an inspection asks.
    expect(rows.first[0], AuditAction.receiptProfileChanged);
    expect(rows.first[1], '123456789');
    expect(rows.first[2], 'Amer M.');
  });

  test('without the administrator credential nothing is written', () async {
    final locked = PostgresReceiptProfileRepository(
      database: db,
      config: pg.config,
      readDatabase: db,
      readConfig: pg.config.copyWith(tenantSlug: slug),
      adminAvailable: false,
      businessId: 1,
      branchId: branchId,
    );

    final result = await locked.save(complete(), by: manager);
    expect(result.refusal, isA<AdministratorCredentialRequired>());
  });
}
