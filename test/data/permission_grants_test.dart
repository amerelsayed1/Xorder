@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_directory_repositories.dart';
import 'package:xorder_pos/data/postgres/postgres_discounts_repository.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
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
  late int restaurantId;
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
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES (@s, 'Grants') "
      'RETURNING id',
      parameters: {'s': slug},
    )).first[0]! as int;

    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    Future<int> role(String code, Set<String> capabilities) async =>
        (await db.query(
          pg.config,
          'INSERT INTO pos_roles (restaurant_id, code, name_en, capabilities) '
          'VALUES (@r, @c, @c, @caps) RETURNING id',
          parameters: {
            'r': restaurantId,
            'c': code,
            'caps': capabilities.toList(),
          },
        )).first[0]! as int;

    cashierRoleId = await role('cashier', SystemRoles.cashier);
    supervisorRoleId = await role('supervisor', SystemRoles.supervisor);

    final salt = PinHash.newSalt();
    staffId = (await db.query(
      pg.config,
      'INSERT INTO pos_staff (restaurant_id, branch_id, role_id, name, '
      "  username, pin_salt, pin_hash) "
      "VALUES (@r, @b, @role, 'Rana', 'rana', @salt, @hash) RETURNING id",
      parameters: {
        'r': restaurantId,
        'b': branchId,
        'role': cashierRoleId,
        'salt': salt,
        'hash': await PinHash.hash(pin, salt),
      },
    )).first[0]! as int;

    final terminal = (await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name) '
      "VALUES (gen_random_uuid(), @r, @b, 'Counter 1') RETURNING id::text",
      parameters: {'r': restaurantId, 'b': branchId},
    )).first[0]! as String;

    session = PostgresSessionRepository(
      database: db,
      config: pg.config.copyWith(tenantSlug: slug),
      restaurantId: restaurantId,
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
    'INSERT INTO pos_staff_roles (staff_id, role_id) VALUES (@s, @r)',
    parameters: {'s': staffId, 'r': roleId},
  );

  Future<void> override(String capability, String effect) => db.query(
    pg.config,
    'INSERT INTO pos_staff_permission_overrides (staff_id, capability, effect) '
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
    'INSERT INTO pos_permission_limits (restaurant_id, subject_type, '
    '  subject_id, limit_key, limit_bp, limit_minor) '
    'VALUES (@r, @t, @i, @k, @bp, @m)',
    parameters: {
      'r': restaurantId,
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
        'SELECT count(*) FROM pos_staff_roles WHERE staff_id = @s',
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
        'UPDATE pos_staff SET role_id = @r WHERE id = @s',
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

    test('another restaurant\'s ceiling does not reach this one', () async {
      final other = (await db.query(
        pg.config,
        "INSERT INTO pos_restaurants (slug, name) VALUES ('other', 'Other') "
        'RETURNING id',
      )).first[0]! as int;
      await limit('staff', staffId, LimitKey.discount, bp: 100);
      await db.query(
        pg.config,
        'UPDATE pos_permission_limits SET restaurant_id = @o',
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
      'DELETE FROM pos_staff WHERE id = @s',
      parameters: {'s': staffId},
    );

    final rows = await db.query(
      pg.config,
      'SELECT count(*) FROM pos_staff_permission_overrides',
    );
    expect(rows.first[0], 0);
  });

  group('the ceiling the till actually applies', () {
    late PostgresDiscountsRepository discounts;

    setUp(() {
      discounts = PostgresDiscountsRepository(
        database: db,
        config: pg.config.copyWith(tenantSlug: slug),
        restaurantId: restaurantId,
      );
    });

    test('an unlimited person is unlimited', () async {
      final limit = await discounts.limitFor(await signIn());
      expect(limit.isUnlimited, isTrue);
    });

    test("the role's old column still binds", () async {
      // `pos_roles.max_discount_bp` predates Wave C and restaurants have set
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
}
