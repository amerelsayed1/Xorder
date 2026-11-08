@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_admin_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// One owner per business, and the owner's own access is not editable.
///
/// Tested twice, as every cross-row rule in this codebase is: through
/// [PostgresStaffDirectoryRepository], which refuses with a sentence, and by
/// raw SQL that goes round it — because the repository is one writer of
/// `pos_users` and the installer, `pos_migrate --seed` and the cloud seeder are
/// three more. Migration 42's triggers are what hold for all four.
///
/// Counted among ACTIVE staff throughout. That is what keeps ownership
/// transferable — disable the old owner, then appoint the new one — and it is
/// the part most worth pinning, because the tempting "one owner row, ever"
/// would make selling the business a job for a psql prompt.
void main() {
  if (PgFixture.host == null) {
    test('one owner (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresStaffDirectoryRepository staff;
  late Map<String, PosRole> seeded;
  late int businessId;
  late int branchId;
  late PosStaff owner;

  setUp(() async {
    pg = await PgFixture.open('one_owner');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('oo', 'OO') RETURNING id",
    )).first[0]! as int;
    branchId = (await db.query(
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

    // The installer's account, created through the repository so that the
    // first owner is known to be allowed — the rule is about the second.
    final created = await staff.create(
      by: PosStaff(
        id: 0,
        name: 'installer',
        role: seeded[SystemRoles.ownerCode],
      ),
      name: 'Amer',
      username: 'amer',
      pin: '4321',
      roleId: seeded[SystemRoles.ownerCode]!.id,
    );
    expect(created.succeeded, isTrue, reason: '${created.refusal}');
    owner = created.value!;
  });

  tearDown(() => pg.close());

  int roleId(String code) => seeded[code]!.id;

  Future<PosStaff> hire(String code, String name) async {
    final result = await staff.create(
      by: owner,
      name: name,
      username: name.toLowerCase(),
      pin: '1111',
      roleId: roleId(code),
    );
    expect(result.succeeded, isTrue, reason: '${result.refusal}');
    return result.value!;
  }

  /// Who is on the owner role, and whether they are active, as stored.
  Future<Map<String, bool>> owners() async {
    final rows = await db.query(
      pg.config,
      'SELECT s.name, s.is_active FROM pos_users s '
      'JOIN pos_roles r ON r.id = s.role_id '
      "WHERE s.business_id = @r AND r.code = 'owner' ORDER BY s.id",
      parameters: {'r': businessId},
    );
    return {for (final row in rows) row[0]! as String: row[1]! as bool};
  }

  Future<String?> storedRole(int staffId) async => (await db.query(
    pg.config,
    'SELECT r.code FROM pos_users s LEFT JOIN pos_roles r ON r.id = s.role_id '
    'WHERE s.id = @id',
    parameters: {'id': staffId},
  )).first[0] as String?;

  Future<int> count(String table, int staffId) async => (await db.query(
    pg.config,
    table == 'pos_permission_limits'
        ? "SELECT count(*) FROM pos_permission_limits WHERE subject_type = 'staff' "
              'AND subject_id = @s'
        : 'SELECT count(*) FROM $table WHERE user_id = @s',
    parameters: {'s': staffId},
  )).first[0]! as int;

  Future<void> sql(String statement, [Map<String, Object?>? parameters]) =>
      db.query(pg.config, statement, parameters: parameters);

  /// A staff row written straight into the table, past every Dart check.
  Future<int> insertStaff(
    String name, {
    required String role,
    bool active = true,
  }) async => (await db.query(
    pg.config,
    'INSERT INTO pos_users (business_id, branch_id, name, username, '
    '  pin_salt, pin_hash, role_id, is_active) '
    "VALUES (@r, @b, @n, @u, 's', 'h', @role, @active) RETURNING id",
    parameters: {
      'r': businessId,
      'b': branchId,
      'n': name,
      'u': name.toLowerCase(),
      'role': roleId(role),
      'active': active,
    },
  )).first[0]! as int;

  /// The database refused, and said something a person can act on. Matched on
  /// the text rather than on an exception type, because what reaches a psql
  /// prompt is the text.
  Matcher refusedSaying(String fragment) => throwsA(
    predicate<Object>(
      (error) => '$error'.contains(fragment),
      'an error saying "$fragment"',
    ),
  );

  group('one owner, through the repository', () {
    test('a second owner is refused, and the refusal names the first', () async {
      final result = await staff.create(
        by: owner,
        name: 'Nour',
        username: 'nour',
        pin: '2222',
        roleId: roleId(SystemRoles.ownerCode),
      );

      expect(result.refusal, isA<OwnerAlreadyExists>());
      expect((result.refusal! as OwnerAlreadyExists).ownerName, 'Amer');
      expect(await owners(), {'Amer': true});
      expect(await staff.all(), hasLength(1), reason: 'nobody was written');
    });

    test('nobody can be moved onto Owner while there is one', () async {
      final rana = await hire(SystemRoles.cashierCode, 'Rana');

      final result = await staff.update(
        by: owner,
        staffId: rana.id,
        roleId: roleId(SystemRoles.ownerCode),
      );

      expect((result.refusal! as OwnerAlreadyExists).ownerName, 'Amer');
      expect(await storedRole(rana.id), SystemRoles.cashierCode);
    });

    test('Owner cannot be handed out as an extra role while there is one', () async {
      final rana = await hire(SystemRoles.cashierCode, 'Rana');

      final result = await staff.setGrants(
        by: owner,
        staffId: rana.id,
        extraRoleIds: {roleId(SystemRoles.ownerCode)},
        overrides: const [],
        limits: const {},
      );

      expect((result.refusal! as OwnerAlreadyExists).ownerName, 'Amer');
      expect(await count('pos_user_roles', rana.id), 0);
    });

    test('a disabled owner cannot come back while another is active', () async {
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      final nour = await hire(SystemRoles.cashierCode, 'Nour');

      // The handover, done properly: out, then in.
      expect(
        (await staff.setActive(by: owner, staffId: owner.id, isActive: false))
            .succeeded,
        isTrue,
      );
      final appointed = await staff.update(
        by: hala,
        staffId: nour.id,
        roleId: roleId(SystemRoles.ownerCode),
      );
      expect(appointed.succeeded, isTrue, reason: '${appointed.refusal}');

      final back = await staff.setActive(
        by: hala,
        staffId: owner.id,
        isActive: true,
      );
      expect((back.refusal! as OwnerAlreadyExists).ownerName, 'Nour');
      expect(await owners(), {'Amer': false, 'Nour': true});
    });

    test('ownership is handed over by disabling, then appointing', () async {
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      final nour = await hire(SystemRoles.cashierCode, 'Nour');

      // Nour has exceptions of her own before she is appointed. They mean
      // nothing on an owner and a DENY among them would be a lock-out, so the
      // appointment takes them away rather than being refused over them.
      final granted = await staff.setGrants(
        by: owner,
        staffId: nour.id,
        extraRoleIds: {roleId(SystemRoles.supervisorCode)},
        overrides: const [
          PermissionOverride(
            capability: PosCapability.receiptReprint,
            effect: OverrideEffect.deny,
          ),
        ],
        limits: const {LimitKey.discount: PermissionLimit(maxBp: 1000)},
      );
      expect(granted.succeeded, isTrue, reason: '${granted.refusal}');

      await staff.setActive(by: owner, staffId: owner.id, isActive: false);
      final appointed = await staff.update(
        by: hala,
        staffId: nour.id,
        roleId: roleId(SystemRoles.ownerCode),
      );

      expect(appointed.succeeded, isTrue, reason: '${appointed.refusal}');
      expect(appointed.value!.role!.code, SystemRoles.ownerCode);
      expect(await owners(), {'Amer': false, 'Nour': true});
      expect(await count('pos_user_roles', nour.id), 0);
      expect(await count('pos_user_permission_overrides', nour.id), 0);
      expect(await count('pos_permission_limits', nour.id), 0);
    });

    test('Owner is never an extra role, even with no owner at all', () async {
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      final rana = await hire(SystemRoles.cashierCode, 'Rana');
      await staff.setActive(by: owner, staffId: owner.id, isActive: false);

      final result = await staff.setGrants(
        by: hala,
        staffId: rana.id,
        extraRoleIds: {roleId(SystemRoles.ownerCode)},
        overrides: const [],
        limits: const {},
      );

      expect(result.refusal, isA<OwnerIsNotAnExtraRole>());
      expect(await count('pos_user_roles', rana.id), 0);
    });
  });

  group('the owner is fixed', () {
    test('their role cannot be changed', () async {
      // A second manager is there, so the lock-out rule has no objection. What
      // refuses this is the owner rule and nothing else.
      await hire(SystemRoles.managerCode, 'Hala');

      final result = await staff.update(
        by: owner,
        staffId: owner.id,
        roleId: roleId(SystemRoles.managerCode),
      );

      expect(result.refusal, isA<OwnerIsFixed>());
      expect(await storedRole(owner.id), SystemRoles.ownerCode);
    });

    test('nor their direct grants', () async {
      final result = await staff.update(
        by: owner,
        staffId: owner.id,
        directGrants: {PosCapability.orderRefund},
      );
      expect(result.refusal, isA<OwnerIsFixed>());
    });

    test('nor their extra roles, exceptions or ceilings', () async {
      final result = await staff.setGrants(
        by: owner,
        staffId: owner.id,
        extraRoleIds: {roleId(SystemRoles.cashierCode)},
        overrides: const [
          PermissionOverride(
            capability: PosCapability.staffManage,
            effect: OverrideEffect.deny,
          ),
        ],
        limits: const {LimitKey.discount: PermissionLimit(maxBp: 500)},
      );

      expect(result.refusal, isA<OwnerIsFixed>());
      expect(await count('pos_user_roles', owner.id), 0);
      expect(await count('pos_user_permission_overrides', owner.id), 0);
      expect(await count('pos_permission_limits', owner.id), 0);
    });

    Future<String> storedPin(int staffId) async => (await db.query(
      pg.config,
      'SELECT pin_hash FROM pos_users WHERE id = @id',
      parameters: {'id': staffId},
    )).first[0]! as String;

    test('nor their PIN, by anybody else', () async {
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      final before = await storedPin(owner.id);

      final result = await staff.resetPin(
        by: hala,
        staffId: owner.id,
        pin: '9999',
      );

      expect(result.refusal, isA<OwnerPinIsTheirs>());
      expect(await storedPin(owner.id), before);
    });

    test('not even with the owner disabled — that would be the way round', () async {
      // Disable, reset, re-enable: the owner back on a PIN the manager chose.
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      final disabled = await staff.setActive(
        by: hala,
        staffId: owner.id,
        isActive: false,
      );
      expect(disabled.succeeded, isTrue, reason: '${disabled.refusal}');

      final result = await staff.resetPin(
        by: hala,
        staffId: owner.id,
        pin: '9999',
      );
      expect(result.refusal, isA<OwnerPinIsTheirs>());
    });

    test("but the owner may reset their own, and a manager everybody else's",
        () async {
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      final rana = await hire(SystemRoles.cashierCode, 'Rana');
      final before = await storedPin(owner.id);

      final own = await staff.resetPin(
        by: owner,
        staffId: owner.id,
        pin: '9999',
      );
      expect(own.succeeded, isTrue, reason: '${own.refusal}');
      expect(await storedPin(owner.id), isNot(before));

      final theirs = await staff.resetPin(
        by: hala,
        staffId: rana.id,
        pin: '8642',
      );
      expect(theirs.succeeded, isTrue, reason: '${theirs.refusal}');
    });

    test("and in SQL it is not refused: the installer and the seeder set it",
        () async {
      // Pinned, so nobody completes the rule with a trigger. The database sees
      // a role, not a person; a trigger would refuse the cloud seeder's upsert
      // of the owner's PIN and the installer's re-run, and stop nobody who
      // holds the administrator password anyway.
      await sql(
        'UPDATE pos_users SET pin_salt = @s, pin_hash = @h WHERE id = @id',
        {'s': 'salt', 'h': 'seeded', 'id': owner.id},
      );
      expect(await storedPin(owner.id), 'seeded');
    });

    test('but renaming them works', () async {
      final result = await staff.update(
        by: owner,
        staffId: owner.id,
        name: 'Amer M.',
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect(await owners(), {'Amer M.': true});
    });

    test('and disabling them is still the lock-out rule\'s business', () async {
      // Unchanged by this rule: the owner may be disabled, as long as somebody
      // else can still manage staff.
      final alone = await staff.setActive(
        by: owner,
        staffId: owner.id,
        isActive: false,
      );
      expect(alone.refusal, isA<WouldLockEveryoneOut>());

      await hire(SystemRoles.managerCode, 'Hala');
      final covered = await staff.setActive(
        by: owner,
        staffId: owner.id,
        isActive: false,
      );
      expect(covered.succeeded, isTrue, reason: '${covered.refusal}');
    });

    test('a disabled former owner can be given another role', () async {
      // Otherwise the person who sold the business could never come back as
      // its manager: re-enabling them is refused while the new owner is
      // active, and so — if the fixed-role rule covered them — would be
      // moving them off Owner first. A dead end nobody could get out of.
      final hala = await hire(SystemRoles.managerCode, 'Hala');
      await staff.setActive(by: owner, staffId: owner.id, isActive: false);

      final moved = await staff.update(
        by: hala,
        staffId: owner.id,
        roleId: roleId(SystemRoles.managerCode),
      );
      expect(moved.succeeded, isTrue, reason: '${moved.refusal}');
      expect(await storedRole(owner.id), SystemRoles.managerCode);
    });
  });

  group('the database, gone round', () {
    test('a second active owner is refused, naming the first', () async {
      await expectLater(
        insertStaff('Nour', role: SystemRoles.ownerCode),
        refusedSaying('Amer is already the owner'),
      );
      expect(await owners(), {'Amer': true});
    });

    test('moving somebody onto Owner in SQL is refused', () async {
      final rana = await insertStaff('Rana', role: SystemRoles.cashierCode);
      await expectLater(
        sql('UPDATE pos_users SET role_id = @role WHERE id = @id', {
          'role': roleId(SystemRoles.ownerCode),
          'id': rana,
        }),
        refusedSaying('is already the owner'),
      );
    });

    test('re-enabling a second owner in SQL is refused', () async {
      final former = await insertStaff(
        'Nour',
        role: SystemRoles.ownerCode,
        active: false,
      );
      await expectLater(
        sql('UPDATE pos_users SET is_active = true WHERE id = @id', {
          'id': former,
        }),
        refusedSaying('is already the owner'),
      );
    });

    test('an inactive owner is not counted, so a handover can be staged', () async {
      await insertStaff('Nour', role: SystemRoles.ownerCode, active: false);
      expect(await owners(), {'Amer': true, 'Nour': false});
    });

    test('the owner role is never an extra role', () async {
      final rana = await insertStaff('Rana', role: SystemRoles.cashierCode);
      await expectLater(
        sql('INSERT INTO pos_user_roles (user_id, role_id) VALUES (@s, @r)', {
          's': rana,
          'r': roleId(SystemRoles.ownerCode),
        }),
        refusedSaying('cannot be an extra role'),
      );
    });

    test('the owner is given no extra roles', () async {
      await expectLater(
        sql('INSERT INTO pos_user_roles (user_id, role_id) VALUES (@s, @r)', {
          's': owner.id,
          'r': roleId(SystemRoles.cashierCode),
        }),
        refusedSaying('given no extra roles'),
      );
    });

    test('the owner is given no permission exceptions', () async {
      // The DENY is the one that matters: it is how a business would lock
      // itself out of the screen that could take it off again.
      await expectLater(
        sql(
          'INSERT INTO pos_user_permission_overrides (user_id, capability, effect) '
          "VALUES (@s, 'staff.manage', 'DENY')",
          {'s': owner.id},
        ),
        refusedSaying('exception on the owner'),
      );
    });

    test('somebody still carrying exceptions cannot be made the owner', () async {
      await sql('UPDATE pos_users SET is_active = false WHERE id = @id', {
        'id': owner.id,
      });
      final rana = await insertStaff('Rana', role: SystemRoles.cashierCode);
      await sql(
        'INSERT INTO pos_user_permission_overrides (user_id, capability, effect) '
        "VALUES (@s, 'receipt.reprint', 'DENY')",
        {'s': rana},
      );

      await expectLater(
        sql('UPDATE pos_users SET role_id = @role WHERE id = @id', {
          'role': roleId(SystemRoles.ownerCode),
          'id': rana,
        }),
        refusedSaying('clear them'),
      );
    });

    test('two owners appointed at the same moment: exactly one wins', () async {
      // Without the lock on the owner role's row, each transaction counts the
      // other's uncommitted appointment as nobody, and both commit.
      await sql('UPDATE pos_users SET is_active = false WHERE id = @id', {
        'id': owner.id,
      });

      Future<bool> appoint(String name, {required Duration after, bool hold = false}) async {
        await Future<void>.delayed(after);
        try {
          await db.runTx(pg.config, (tx) async {
            await tx.execute(
              Sql.named(
                'INSERT INTO pos_users (business_id, branch_id, name, username, '
                '  pin_salt, pin_hash, role_id) '
                "VALUES (@r, @b, @n, @n, 's', 'h', @role)",
              ),
              parameters: {
                'r': businessId,
                'b': branchId,
                'n': name,
                'role': roleId(SystemRoles.ownerCode),
              },
            );
            if (hold) await tx.execute('SELECT pg_sleep(0.6)');
          });
          return true;
        } catch (_) {
          return false;
        }
      }

      final results = await Future.wait([
        appoint('first', after: Duration.zero, hold: true),
        appoint('second', after: const Duration(milliseconds: 150)),
      ]);

      expect(results.where((won) => won), hasLength(1));
      expect(
        (await owners()).values.where((active) => active),
        hasLength(1),
      );
    });
  });

  group('what was already there', () {
    test('a business with two owners already can still rename and disable them',
        () async {
      // A branch server that ran an earlier build may have two. Migration 42
      // does not rewrite them — which one is the real owner is the
      // business's question, not a migration's — so edits that do not touch
      // the role or the active flag must keep working on both rows.
      await sql('ALTER TABLE pos_users DISABLE TRIGGER pos_users_one_owner_insert');
      final second = await insertStaff('Nour', role: SystemRoles.ownerCode);
      await sql('ALTER TABLE pos_users ENABLE TRIGGER pos_users_one_owner_insert');
      expect(await owners(), {'Amer': true, 'Nour': true});

      await sql("UPDATE pos_users SET name = 'Nour S.' WHERE id = @id", {
        'id': second,
      });
      // The repository's UPDATE always writes `role_id = coalesce(@role,
      // role_id)`, so this is the case the trigger's WHEN clause is for.
      final renamed = await staff.update(by: owner, staffId: owner.id, name: 'Amer M.');
      expect(renamed.succeeded, isTrue, reason: '${renamed.refusal}');

      final disabled = await staff.setActive(
        by: owner,
        staffId: second,
        isActive: false,
      );
      expect(disabled.succeeded, isTrue, reason: '${disabled.refusal}');
      expect(await owners(), {'Amer M.': true, 'Nour S.': false});
    });

    test('re-running the installer with the same owner does nothing', () async {
      // `seedOwner` is `ON CONFLICT DO NOTHING`, and a BEFORE INSERT trigger
      // fires before the conflict is found. Had the trigger counted Amer
      // against his own re-insert, every re-run of the wizard would fail.
      final created = await LocalBootstrap(db).seedOwner(
        pg.config,
        businessId: businessId,
        branchId: branchId,
        roleId: roleId(SystemRoles.ownerCode),
        name: 'Someone Else',
        username: 'amer',
        pin: '9999',
      );
      expect(created, isA<OwnerAlreadyHere>());
      expect(await owners(), {'Amer': true});
    });

    test('but seeding a second owner under another username is refused', () async {
      // The one path the installer and `pos_migrate --seed` had to a second
      // owner: pointed at a business that already has one, with a different
      // username. It used to succeed silently. `seedOwner` now asks first and
      // answers with data both callers put into words — see
      // `installer_owner_test.dart`; the trigger is still what refuses the
      // same INSERT from anybody else, as the group above shows.
      final seeded = await LocalBootstrap(db).seedOwner(
        pg.config,
        businessId: businessId,
        branchId: branchId,
        roleId: roleId(SystemRoles.ownerCode),
        name: 'Nour',
        username: 'nour',
        pin: '9999',
      );
      expect(
        seeded,
        isA<AnotherOwnerActive>().having((r) => r.name, 'name', 'Amer'),
      );
      expect(await owners(), {'Amer': true});
    });
  });
}
