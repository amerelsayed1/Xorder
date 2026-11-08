@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/security/pin_hash.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_admin_repositories.dart';
import 'package:shared_module/data/postgres/postgres_directory_repositories.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Admin Mode's password, against a real PostgreSQL (ADR-006b slice D).
///
/// Tested twice, as every rule here is: through the repositories — set,
/// verify, clear, the technician's reset, each with its ledger row — and by
/// raw SQL that goes round them, because migration 55's CHECKs are what hold
/// for the writers that are not this code (a psql prompt, a support script).
///
/// **What this does not prove:** the suites run as a superuser, so nothing
/// here shows the till role cannot write `password_hash`. That rests on the
/// offline REVOKE of INSERT/UPDATE on `pos_users`, which
/// `till_grants_enforced_test.dart` already exercises for the table.
void main() {
  if (PgFixture.host == null) {
    test('admin password (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const password = 'a long enough one';

  late PgFixture pg;
  late PosDatabase db;
  late PostgresStaffDirectoryRepository staff;
  late PostgresSessionRepository sessions;
  late Map<String, PosRole> seeded;
  late int businessId;
  late PosStaff owner;

  setUp(() async {
    pg = await PgFixture.open('admin_password');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('ap', 'AP') RETURNING id",
    )).first[0]! as int;
    final branchId = (await db.query(
      pg.config,
      'INSERT INTO pos_branches (business_id, code, name) '
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;

    seeded = {};
    for (final entry in SystemRoles.seeded.entries) {
      final row = await db.query(
        pg.config,
        'INSERT INTO pos_roles (business_id, code, name_en, name_ar, '
        '  capabilities, is_system) '
        'VALUES (@r, @code, @nameEn, @nameAr, @capabilities, true) RETURNING id',
        parameters: {
          'r': businessId,
          'code': entry.key,
          'nameEn': entry.value.nameEn,
          'nameAr': entry.value.nameAr,
          'capabilities': entry.value.capabilities.toList(),
        },
      );
      seeded[entry.key] = PosRole(
        id: row.first[0]! as int,
        code: entry.key,
        nameEn: entry.value.nameEn,
        capabilities: entry.value.capabilities,
        isSystem: true,
      );
    }

    staff = PostgresStaffDirectoryRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
    );
    sessions = PostgresSessionRepository(
      database: db,
      config: pg.config,
      businessId: businessId,
      branchId: branchId,
      terminalId: '00000000-0000-0000-0000-000000000001',
    );

    final created = await staff.create(
      by: PosStaff(id: 0, name: 'installer', role: seeded[SystemRoles.ownerCode]),
      name: 'Amer',
      username: 'amer',
      pin: '4321',
      roleId: seeded[SystemRoles.ownerCode]!.id,
    );
    expect(created.succeeded, isTrue, reason: '${created.refusal}');
    owner = created.value!;
  });

  tearDown(() => pg.close());

  Future<PosStaff> hire(String code, String name) async {
    final result = await staff.create(
      by: owner,
      name: name,
      username: name.toLowerCase(),
      pin: '1111',
      roleId: seeded[code]!.id,
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  Future<String?> storedHash(int staffId) async => (await db.query(
    pg.config,
    'SELECT password_hash FROM pos_users WHERE id = @id',
    parameters: {'id': staffId},
  )).first[0] as String?;

  Future<List<List<Object?>>> ledger(String action) => db.query(
    pg.config,
    'SELECT actor_user_id, actor_name, entity_id, before_value::text, '
    '  after_value::text '
    'FROM pos_audit_events WHERE business_id = @r AND action = @a '
    'ORDER BY id',
    parameters: {'r': businessId, 'a': action},
  );

  group('through the repositories', () {
    test('set, then verified by name and password — and only that', () async {
      expect(await staff.withPassword(), isEmpty, reason: 'nobody, at first');
      expect(
        await sessions.signInWithPassword(username: 'amer', password: password),
        isNull,
      );

      final set = await staff.setOwnPassword(by: owner, password: password);
      expect(set.succeeded, isTrue, reason: '${set.refusal}');
      expect(await staff.withPassword(), {owner.id});

      final signedIn = await sessions.signInWithPassword(
        username: ' AMER ',
        password: password,
      );
      expect(signedIn?.id, owner.id);
      expect(signedIn?.role?.code, SystemRoles.ownerCode);

      for (final (name, typed) in [
        ('amer', 'a long enough onE'),
        ('amer', '4321'),
        ('nobody', password),
        ('', password),
      ]) {
        expect(
          await sessions.signInWithPassword(username: name, password: typed),
          isNull,
          reason: '$name / $typed',
        );
      }
    });

    test('the row holds a versioned hash, and the ledger holds neither',
        () async {
      await staff.setOwnPassword(by: owner, password: password);

      final hash = await storedHash(owner.id);
      expect(hash, startsWith('pbkdf2-sha256\$600000\$'));
      expect(hash, isNot(contains(password)));
      expect(await PasswordHash.verify(password, hash!), isTrue);

      final rows = await ledger(AuditAction.staffPasswordSet);
      expect(rows, hasLength(1));
      expect(rows.single[0], owner.id);
      expect(rows.single[2], '${owner.id}');
      expect(rows.single[3], isNull, reason: 'no before');
      final after = rows.single[4]! as String;
      expect(after, isNot(contains(password)));
      expect(after, isNot(contains('pbkdf2')));
      expect(after, isNot(contains(hash)));
    });

    test('a weak one is refused before anything is written', () async {
      final result = await staff.setOwnPassword(by: owner, password: 'short');
      expect(
        result.refusal,
        isA<PasswordRejected>().having(
          (r) => r.problem,
          'problem',
          PasswordProblem.tooShort,
        ),
      );
      expect(await storedHash(owner.id), isNull);
      expect(await ledger(AuditAction.staffPasswordSet), isEmpty);
    });

    test("a manager clears a cashier's, and the cashier is back on the PIN",
        () async {
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      final rana = await hire(SystemRoles.cashierCode, 'Rana');
      await staff.setOwnPassword(by: rana, password: 'rana password 1');

      final cleared = await staff.clearPassword(by: hala, staffId: rana.id);
      expect(cleared.succeeded, isTrue, reason: '${cleared.refusal}');
      expect(await storedHash(rana.id), isNull);
      expect(
        await sessions.signInWithPassword(
          username: 'rana',
          password: 'rana password 1',
        ),
        isNull,
      );

      final rows = await ledger(AuditAction.staffPasswordCleared);
      expect(rows.single[0], hala.id);
      expect(rows.single[2], '${rana.id}');
      expect(rows.single[4]! as String, isNot(contains('rana password 1')));

      // Again, with nothing to clear: done, and no second row.
      expect(
        (await staff.clearPassword(by: hala, staffId: rana.id)).succeeded,
        isTrue,
      );
      expect(await ledger(AuditAction.staffPasswordCleared), hasLength(1));
    });

    test("never the owner's — not by a manager, not by the owner", () async {
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      await staff.setOwnPassword(by: owner, password: password);
      final before = await storedHash(owner.id);

      for (final by in [hala, owner]) {
        expect(
          (await staff.clearPassword(by: by, staffId: owner.id)).refusal,
          isA<OwnerPasswordIsTheirs>(),
          reason: by.name,
        );
      }
      expect(await storedHash(owner.id), before);
    });

    test('and not by somebody without staff.manage', () async {
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      final rana = await hire(SystemRoles.cashierCode, 'Rana');
      await staff.setOwnPassword(by: hala, password: 'hala password 1');

      expect(
        (await staff.clearPassword(by: rana, staffId: hala.id)).refusal,
        isA<NotPermitted>(),
      );
      expect(await storedHash(hala.id), isNotNull);
    });

    test("the technician clears the owner's, and the row says who", () async {
      await staff.setOwnPassword(by: owner, password: password);

      final result = await staff.clearPasswordAsTechnician(username: 'Amer ');
      expect(result.value, 'Amer');
      expect(await storedHash(owner.id), isNull);

      final rows = await ledger(AuditAction.staffPasswordCleared);
      expect(rows.single[0], isNull, reason: 'no member of staff did it');
      expect(rows.single[1], AuditAction.technicianActor);
      expect(rows.single[2], '${owner.id}');

      expect(
        (await staff.clearPasswordAsTechnician(username: 'nobody')).value,
        isNull,
      );
      expect(
        (await staff.clearPasswordAsTechnician(username: 'amer')).value,
        isNull,
        reason: 'nothing left to clear',
      );
    });

    test('nothing is written without the administrator credential', () async {
      final noAdmin = PostgresStaffDirectoryRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        adminAvailable: false,
      );
      expect(
        (await noAdmin.setOwnPassword(by: owner, password: password)).refusal,
        isA<AdministratorCredentialRequired>(),
      );
      expect(
        (await noAdmin.clearPasswordAsTechnician(username: 'amer')).refusal,
        isA<AdministratorCredentialRequired>(),
      );
    });
  });

  group('round the repositories, in raw SQL', () {
    Future<void> write(String? hash, {bool stamped = true}) => db.query(
      pg.config,
      'UPDATE pos_users SET password_hash = @h, '
      'password_set_at = ${stamped ? 'now()' : 'NULL'} WHERE id = @id',
      parameters: {'h': hash, 'id': owner.id},
    );

    test('a plaintext is refused by the database itself', () async {
      await expectLater(write('hunter2-hunter2'), throwsA(isA<PosDbException>()));
      expect(await storedHash(owner.id), isNull);
    });

    test('so is a real hash made with too little work', () async {
      final weak = await PasswordHash.create(password, rounds: 1000);
      await expectLater(write(weak), throwsA(isA<PosDbException>()));
    });

    test('and a hash without the moment it was set, or the reverse', () async {
      final good = await PasswordHash.create(password);
      await expectLater(
        write(good, stamped: false),
        throwsA(isA<PosDbException>()),
      );
      await expectLater(write(null), throwsA(isA<PosDbException>()));

      await write(good);
      expect(await storedHash(owner.id), good);
      await write(null, stamped: false);
      expect(await storedHash(owner.id), isNull);
    });
  });

  test('a database migration 55 has not reached reads as nobody having one',
      () async {
    // The back-office door is what upgrades an installed till, so the door
    // reads this column before the upgrade that adds it has run. Undone and
    // put back here, on the shared database, so the next suite finds it.
    await db.query(
      pg.config,
      'ALTER TABLE pos_users DROP COLUMN password_hash CASCADE',
    );
    await db.query(
      pg.config,
      'ALTER TABLE pos_users DROP COLUMN password_set_at CASCADE',
    );
    await db.query(pg.config, 'DELETE FROM schema_migrations WHERE version = 55');
    try {
      expect(await staff.withPassword(), isEmpty);
      expect(
        await sessions.signInWithPassword(username: 'amer', password: password),
        isNull,
      );
    } finally {
      // Put 55 back by hand: its statements name `pos_staff`, which migration
      // 62 renamed, so the migrator can no longer replay it on this schema.
      final m55 = posMigrations.singleWhere((m) => m.version == 55);
      for (final statement in m55.statements) {
        await db.query(pg.config, statement.replaceAll('pos_staff', 'pos_users'));
      }
      await db.query(
        pg.config,
        'INSERT INTO schema_migrations (version) VALUES (55)',
      );
    }
    expect(
      (await staff.setOwnPassword(by: owner, password: password)).succeeded,
      isTrue,
    );
  });
}
