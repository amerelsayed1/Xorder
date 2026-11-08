@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_admin_repositories.dart';
import 'package:xorder_pos/data/postgres/postgres_directory_repositories.dart';
import 'package:xorder_pos/data/postgres/postgres_discounts_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/authorization.dart';

import 'pg_fixture.dart';

/// What a person actually holds, read back through sign-in.
///
/// Sign-in is the only moment the till learns this, so the test goes through
/// it rather than through the tables: a resolution that were correct in SQL and
/// never reached the cashier would be a resolution nobody has.
void main() {
  if (PgFixture.host == null) {
    test('permission grants (skipped — set POS_PG_HOST to run)', () {},
        skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late PostgresSessionRepository session;
  late int businessId;
  late int branchId;
  late int staffId;
  late int cashierRoleId;
  late int supervisorRoleId;

  const slug = 'permission-grants-test';
  const pin = '4242';

  setUp(() async {
    pg = await PgFixture.open('permission_grants');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES (@s, 'Grants') "
      'RETURNING id',
      parameters: {'s': slug},
    )).first[0]! as int;

    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': businessId},
    )).first[0]! as int;

    Future<int> role(String code, Set<String> capabilities) async =>
        (await db.query(
          pg.config,
          'INSERT INTO pos_roles (business_id, code, name_en, capabilities) '
          'VALUES (@r, @c, @c, @caps) RETURNING id',
          parameters: {
            'r': businessId,
            'c': code,
            'caps': capabilities.toList(),
          },
        )).first[0]! as int;

    cashierRoleId = await role('cashier', SystemRoles.cashier);
    supervisorRoleId = await role('supervisor', SystemRoles.supervisor);

    final salt = PinHash.newSalt();
    staffId = (await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, branch_id, role_id, name, '
      "  username, pin_salt, pin_hash) "
      "VALUES (@r, @b, @role, 'Rana', 'rana', @salt, @hash) RETURNING id",
      parameters: {
        'r': businessId,
        'b': branchId,
        'role': cashierRoleId,
        'salt': salt,
        'hash': await PinHash.hash(pin, salt),
      },
    )).first[0]! as int;

    final terminal = (await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      "VALUES (gen_random_uuid(), @r, @b, 'Counter 1') RETURNING id::text",
      parameters: {'r': businessId, 'b': branchId},
    )).first[0]! as String;

    session = PostgresSessionRepository(
      database: db,
      config: pg.config.copyWith(tenantSlug: slug),
      businessId: businessId,
      branchId: branchId,
      terminalId: terminal,
    );
  });

  tearDown(() => pg.close());

  Future<PosStaff> signIn() async {
    final staff = await session.signIn(pin);
    expect(staff, isNotNull, reason: 'the PIN should match');
    return staff!;
  }

  Future<void> addRole(int roleId) => db.query(
    pg.config,
    'INSERT INTO pos_user_roles (user_id, role_id) VALUES (@s, @r)',
    parameters: {'s': staffId, 'r': roleId},
  );

  Future<void> override(String capability, String effect) => db.query(
    pg.config,
    'INSERT INTO pos_user_permission_overrides (user_id, capability, effect) '
    'VALUES (@s, @c, @e)',
    parameters: {'s': staffId, 'c': capability, 'e': effect},
  );

  Future<void> limit(
    String subjectType,
    int subjectId,
    String key, {
    int? bp,
    int? minor,
  }) => db.query(
    pg.config,
    'INSERT INTO pos_permission_limits (business_id, subject_type, '
    '  subject_id, limit_key, limit_bp, limit_minor) '
    'VALUES (@r, @t, @i, @k, @bp, @m)',
    parameters: {
      'r': businessId,
      't': subjectType,
      'i': subjectId,
      'k': key,
      'bp': bp,
      'm': minor,
    },
  );

  group('the primary role', () {
    test('lives in its own column and is not copied into the extras', () async {
      // Copying it would mean writing both places on every role change — and
      // when the primary changed, the copy would stay, silently leaving
      // somebody holding the role they were moved off.
      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_user_roles WHERE user_id = @s',
        parameters: {'s': staffId},
      );
      expect(rows.first[0], 0);
    });

    test('the staff list says "Cashier", not "2 roles"', () async {
      final staff = await signIn();
      expect(staff.role!.code, 'cashier');
      expect(staff.extraRoles, isEmpty);
    });

    test('changing it does not leave the old role behind', () async {
      await addRole(supervisorRoleId);
      await db.query(
        pg.config,
        'UPDATE pos_users SET role_id = @r WHERE id = @s',
        parameters: {'r': supervisorRoleId, 's': staffId},
      );

      // The extra row names the same role as the new primary, and the resolver
      // drops it rather than reporting a role twice.
      final staff = await signIn();
      expect(staff.role!.code, 'supervisor');
      expect(staff.extraRoles, isEmpty);
      expect(staff.can(PosCapability.orderVoid), isTrue);
    });
  });

  group('multiple roles', () {
    test('a second role adds its permissions', () async {
      await addRole(supervisorRoleId);
      final staff = await signIn();

      expect(staff.can(PosCapability.orderVoid), isTrue, reason: 'supervisor');
      expect(staff.can(PosCapability.operate), isTrue, reason: 'cashier');
    });

    test('the second role is named, not folded into a flat set', () async {
      await addRole(supervisorRoleId);
      final staff = await signIn();
      expect(staff.extraRoles.single.code, 'supervisor');
    });
  });

  group('overrides', () {
    test('an ALLOW grants what no role does', () async {
      await override(PosCapability.orderRefund, 'ALLOW');
      final staff = await signIn();
      expect(staff.can(PosCapability.orderRefund), isTrue);
    });

    test('a DENY takes away what a role grants', () async {
      await addRole(supervisorRoleId);
      await override(PosCapability.orderVoid, 'DENY');
      final staff = await signIn();

      expect(staff.can(PosCapability.orderVoid), isFalse);
      expect(staff.deniedByOverride, contains(PosCapability.orderVoid));
    });

    test('an unknown effect is refused by the database', () async {
      await expectLater(
        override(PosCapability.orderVoid, 'MAYBE'),
        throwsA(isA<Object>()),
      );
    });

    test('one person cannot hold two overrides on the same capability',
        () async {
      // The primary key. Otherwise ALLOW and DENY could both be written and
      // the answer would depend on which row was read.
      await override(PosCapability.orderVoid, 'ALLOW');
      await expectLater(
        override(PosCapability.orderVoid, 'DENY'),
        throwsA(isA<Object>()),
      );
    });
  });

  group('limits', () {
    test('a role ceiling reaches the person who holds the role', () async {
      await limit('role', cashierRoleId, LimitKey.discount, bp: 1000);
      final staff = await signIn();
      expect(staff.limitFor(LimitKey.discount).maxBp, 1000);
    });

    test('a personal ceiling tightens the role', () async {
      await limit('role', cashierRoleId, LimitKey.discount, bp: 2000);
      await limit('staff', staffId, LimitKey.discount, bp: 500);
      final staff = await signIn();
      expect(staff.limitFor(LimitKey.discount).maxBp, 500);
    });

    test('a personal ceiling cannot raise a role ceiling', () async {
      await limit('role', cashierRoleId, LimitKey.discount, bp: 1000);
      await limit('staff', staffId, LimitKey.discount, bp: 9000);
      final staff = await signIn();
      expect(staff.limitFor(LimitKey.discount).maxBp, 1000);
    });

    test('two roles tighten each other', () async {
      await addRole(supervisorRoleId);
      await limit('role', cashierRoleId, LimitKey.discount, bp: 1000);
      await limit('role', supervisorRoleId, LimitKey.discount, bp: 3000);
      final staff = await signIn();

      // Otherwise a limit is something you escape by collecting roles.
      expect(staff.limitFor(LimitKey.discount).maxBp, 1000);
    });

    test('another business\'s ceiling does not reach this one', () async {
      final other = (await db.query(
        pg.config,
        "INSERT INTO pos_businesses (slug, name) VALUES ('other', 'Other') "
        'RETURNING id',
      )).first[0]! as int;
      await limit('staff', staffId, LimitKey.discount, bp: 100);
      await db.query(
        pg.config,
        'UPDATE pos_permission_limits SET business_id = @o',
        parameters: {'o': other},
      );

      final staff = await signIn();
      expect(staff.limitFor(LimitKey.discount).isUnlimited, isTrue);
    });

    test('a limit that limits nothing is refused', () async {
      // An unlimited subject has no row at all.
      await expectLater(
        limit('staff', staffId, LimitKey.discount),
        throwsA(isA<Object>()),
      );
    });

    test('a share above 100% is refused', () async {
      await expectLater(
        limit('staff', staffId, LimitKey.discount, bp: 10001),
        throwsA(isA<Object>()),
      );
    });

    test('a negative cash ceiling is refused', () async {
      await expectLater(
        limit('staff', staffId, LimitKey.refund, minor: -1),
        throwsA(isA<Object>()),
      );
    });

    test('one subject cannot hold the same ceiling twice', () async {
      await limit('staff', staffId, LimitKey.discount, bp: 1000);
      await expectLater(
        limit('staff', staffId, LimitKey.discount, bp: 2000),
        throwsA(isA<Object>()),
      );
    });

    test('no ceiling anywhere is unlimited', () async {
      final staff = await signIn();
      expect(staff.limitFor(LimitKey.discount).isUnlimited, isTrue);
    });
  });

  test('a role somebody holds cannot be deleted out from under them', () async {
    // RESTRICT, not CASCADE: deleting a role has to be refused and explained,
    // not performed quietly.
    await addRole(supervisorRoleId);
    await expectLater(
      db.query(
        pg.config,
        'DELETE FROM pos_roles WHERE id = @r',
        parameters: {'r': supervisorRoleId},
      ),
      throwsA(isA<Object>()),
    );
  });

  test('removing somebody removes their grants with them', () async {
    // CASCADE this way round: an override belonging to a deleted person is not
    // a record of anything, it is a dangling exception.
    await addRole(supervisorRoleId);
    await override(PosCapability.orderRefund, 'ALLOW');
    await db.query(
      pg.config,
      'DELETE FROM pos_users WHERE id = @s',
      parameters: {'s': staffId},
    );

    final rows = await db.query(
      pg.config,
      'SELECT count(*) FROM pos_user_permission_overrides',
    );
    expect(rows.first[0], 0);
  });

  group('the ceiling the till actually applies', () {
    late PostgresDiscountsRepository discounts;

    setUp(() {
      discounts = PostgresDiscountsRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: slug),
        businessId: businessId,
      );
    });

    test('an unlimited person is unlimited', () async {
      final limit = await discounts.limitFor(await signIn());
      expect(limit.isUnlimited, isTrue);
    });

    test("the role's old column still binds", () async {
      // `pos_roles.max_discount_bp` predates Wave C and businesses have set
      // it. Reading only the new table would silently lift every ceiling
      // already configured.
      await db.query(
        pg.config,
        'UPDATE pos_roles SET max_discount_bp = 1000 WHERE id = @r',
        parameters: {'r': cashierRoleId},
      );

      final limit = await discounts.limitFor(await signIn());
      expect(limit.maxBp, 1000);
    });

    test('a Wave C ceiling binds on its own', () async {
      // And reading only the old column would make the new table decorative.
      await limit('staff', staffId, LimitKey.discount, bp: 500);
      final applied = await discounts.limitFor(await signIn());
      expect(applied.maxBp, 500);
    });

    test('the tighter of the two wins, whichever it is', () async {
      await db.query(
        pg.config,
        'UPDATE pos_roles SET max_discount_bp = 1000 WHERE id = @r',
        parameters: {'r': cashierRoleId},
      );
      await limit('staff', staffId, LimitKey.discount, bp: 2500);

      // Neither source can loosen the other.
      expect((await discounts.limitFor(await signIn())).maxBp, 1000);
    });

    test('a cash ceiling from one source and a share from the other both apply',
        () async {
      await db.query(
        pg.config,
        'UPDATE pos_roles SET max_discount_bp = 1500 WHERE id = @r',
        parameters: {'r': cashierRoleId},
      );
      await limit('staff', staffId, LimitKey.discount, minor: 5000);

      final applied = await discounts.limitFor(await signIn());
      expect(applied.maxBp, 1500);
      expect(applied.maxAmount!.minor, 5000);
    });

    test('the ceiling refuses what it should, through Authorization', () async {
      // End to end: the row in the table becomes the refusal at the till.
      await limit('staff', staffId, LimitKey.discount, bp: 1000);
      final staff = await signIn();

      expect(
        Authorization.checkWithin(
          staff,
          PosCapability.discountApply,
          baseMinor: 10000,
          amountMinor: 900,
        ),
        isA<NeedsOverride>(),
        reason: 'a cashier cannot discount at all — that comes first',
      );

      final supervisorish = staff.copyWith(
        capabilities: {PosCapability.discountApply},
      );
      expect(
        Authorization.checkWithin(
          supervisorish,
          PosCapability.discountApply,
          baseMinor: 10000,
          amountMinor: 900,
        ),
        isA<Allowed>(),
      );
      expect(
        Authorization.checkWithin(
          supervisorish,
          PosCapability.discountApply,
          baseMinor: 10000,
          amountMinor: 1100,
        ),
        isA<DeniedByLimit>(),
      );
    });
  });

  group('editing somebody\'s grants', () {
    late PostgresStaffDirectoryRepository directory;
    late PosStaff owner;

    setUp(() async {
      directory = PostgresStaffDirectoryRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
      );
      final all = await directory.all();
      owner = all.firstWhere((s) => s.id == staffId).copyWith(
        // Stands in for whoever is in the back office. The staff row on disk is
        // a cashier; what matters to `setGrants` is what the *editor* holds.
        capabilities: {...SystemRoles.owner},
      );
    });

    Future<PosStaff> setGrants({
      Set<int> roles = const {},
      List<PermissionOverride> overrides = const [],
      Map<String, PermissionLimit> limits = const {},
      PosStaff? by,
    }) async {
      final result = await directory.setGrants(
        by: by ?? owner,
        staffId: staffId,
        extraRoleIds: roles,
        overrides: overrides,
        limits: limits,
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      return result.value!;
    }

    test('an extra role is written and read back', () async {
      await setGrants(roles: {supervisorRoleId});
      expect((await signIn()).extraRoles.single.code, 'supervisor');
    });

    test('the primary role is never written into the extras', () async {
      // Passing it is not an error — the editor sends what it is showing — but
      // storing it is what makes a later role change leave the old one behind.
      await setGrants(roles: {cashierRoleId, supervisorRoleId});

      final rows = await db.query(
        pg.config,
        'SELECT role_id FROM pos_user_roles WHERE user_id = @s',
        parameters: {'s': staffId},
      );
      expect(rows.single[0], supervisorRoleId);
    });

    test('an empty set removes what was there', () async {
      // The case that matters: taking a grant away is the write most likely to
      // be attempted and most damaging to half-apply.
      await setGrants(roles: {supervisorRoleId});
      await setGrants();
      expect((await signIn()).extraRoles, isEmpty);
    });

    test('a DENY is written and binds', () async {
      await setGrants(
        roles: {supervisorRoleId},
        overrides: [
          const PermissionOverride(
            capability: PosCapability.orderVoid,
            effect: OverrideEffect.deny,
          ),
        ],
      );

      final staff = await signIn();
      expect(staff.can(PosCapability.orderVoid), isFalse);
      expect(staff.deniedByOverride, contains(PosCapability.orderVoid));
    });

    test('removing a DENY gives the permission back', () async {
      await setGrants(
        roles: {supervisorRoleId},
        overrides: [
          const PermissionOverride(
            capability: PosCapability.orderVoid,
            effect: OverrideEffect.deny,
          ),
        ],
      );
      await setGrants(roles: {supervisorRoleId});

      expect((await signIn()).can(PosCapability.orderVoid), isTrue);
    });

    test('a ceiling is written and reaches the till', () async {
      await setGrants(
        limits: {LimitKey.discount: const PermissionLimit(maxBp: 750)},
      );
      expect((await signIn()).limitFor(LimitKey.discount).maxBp, 750);
    });

    test('an unlimited ceiling is stored as no row at all', () async {
      // The CHECK refuses a row that limits nothing, and "unlimited" has to be
      // expressible.
      await setGrants(limits: {LimitKey.discount: PermissionLimit.unlimited});

      final rows = await db.query(
        pg.config,
        'SELECT count(*) FROM pos_permission_limits',
      );
      expect(rows.first[0], 0);
    });

    test('a manager cannot grant an ALLOW for something they lack', () async {
      // §48 through a different door. Without this, a manager who cannot
      // refund grants somebody *else* the right to.
      final manager = owner.copyWith(capabilities: {...SystemRoles.manager});
      final result = await directory.setGrants(
        by: manager,
        staffId: staffId,
        extraRoleIds: const {},
        overrides: [
          const PermissionOverride(
            capability: PosCapability.backupManage,
            effect: OverrideEffect.allow,
          ),
        ],
        limits: const {},
      );

      final reason = (result.refusal! as RoleNotAllowed).reason;
      expect(
        (reason as CannotGrantWhatYouLack).capabilities,
        {PosCapability.backupManage},
      );
    });

    test('a manager can always DENY, whatever they hold', () async {
      // Taking authority away is safe, and refusing it would mean a manager
      // could not revoke anything an owner had granted.
      final manager = owner.copyWith(capabilities: {...SystemRoles.manager});
      final result = await directory.setGrants(
        by: manager,
        staffId: staffId,
        extraRoleIds: const {},
        overrides: [
          const PermissionOverride(
            capability: PosCapability.backupManage,
            effect: OverrideEffect.deny,
          ),
        ],
        limits: const {},
      );
      expect(result.succeeded, isTrue);
    });

    test('a cashier cannot edit anybody\'s grants', () async {
      final cashier = owner.copyWith(
        capabilities: {PosCapability.operate},
        role: null,
      );
      final result = await directory.setGrants(
        by: cashier,
        staffId: staffId,
        extraRoleIds: {supervisorRoleId},
        overrides: const [],
        limits: const {},
      );
      expect(result.refusal, isA<NotPermitted>());
      expect((await signIn()).extraRoles, isEmpty);
    });

    test('the change is audited under its own action', () async {
      await setGrants(
        limits: {LimitKey.discount: const PermissionLimit(maxBp: 750)},
      );

      final rows = await db.query(
        pg.config,
        "SELECT action, after_value->'limits'->'discount.max'->>'bp' "
        'FROM pos_audit_events ORDER BY id DESC LIMIT 1',
      );
      // "Who gave this person the right to refund" is the question an
      // investigation asks, and a generic staff.updated does not answer it.
      expect(rows.first[0], AuditAction.staffGrantsChanged);
      expect(rows.first[1], '750');
    });
  });
}
