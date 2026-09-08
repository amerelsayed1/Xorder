@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_admin_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/authorization.dart';

import 'pg_fixture.dart';

/// The Management section's writes, against a real database.
///
/// The questions here are the ones a restaurant actually runs into: a cashier
/// who found the screen, a manager deleting a role somebody is on, and the
/// Sunday-afternoon one — disabling the last account that can hand out
/// permissions. Each is checked at the data layer, because that is the layer
/// that has to hold when the UI is wrong.
void main() {
  if (PgFixture.host == null) {
    test('administration (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late PostgresRolesRepository roles;
  late PostgresStaffDirectoryRepository staff;
  late PostgresAuditRepository audit;
  late PosStaff owner;
  late Map<String, PosRole> seeded;

  var tenant = 0;

  setUpAll(() async {
    pg = await PgFixture.open('admin');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);

    // The database outlives the run — `PgFixture` creates it once and never
    // drops it — so last run's restaurants are still here, and the per-test
    // slugs below start counting from zero again. Staff and roles cascade;
    // the audit rows deliberately do not, and are ignored because every test
    // reads its own restaurant.
    await db.query(pg.config, "DELETE FROM pos_restaurants WHERE slug LIKE 'admin-%'");
  });

  tearDownAll(() => pg.close());

  /// A restaurant of its own per test. Every table under migration 2 is scoped
  /// to one, so this isolates without truncating — which the audit ledger
  /// refuses anyway, by design.
  setUp(() async {
    final slug = 'admin-${tenant++}';
    final rows = await db.query(
      pg.config,
      'INSERT INTO pos_restaurants (slug, name) VALUES (@slug, @slug) RETURNING id',
      parameters: {'slug': slug},
    );
    restaurantId = rows.first[0] as int;

    seeded = {};
    for (final entry in SystemRoles.seeded.entries) {
      final row = await db.query(
        pg.config,
        'INSERT INTO pos_roles (restaurant_id, code, name_en, name_ar, capabilities, is_system) '
        'VALUES (@r, @code, @nameEn, @nameAr, @capabilities, true) RETURNING id',
        parameters: {
          'r': restaurantId,
          'code': entry.key,
          'nameEn': entry.value.nameEn,
          'nameAr': entry.value.nameAr,
          'capabilities': entry.value.capabilities.toList(),
        },
      );
      seeded[entry.key] = PosRole(
        id: row.first[0] as int,
        code: entry.key,
        nameEn: entry.value.nameEn,
        capabilities: entry.value.capabilities,
        isSystem: true,
      );
    }

    roles = PostgresRolesRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
    );
    staff = PostgresStaffDirectoryRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
    );
    audit = PostgresAuditRepository(
      database: db,
      config: pg.config,
      restaurantId: restaurantId,
    );

    // The installer's account, created directly so the first write in each test
    // is the one under examination.
    owner = (await staff.create(
      by: PosStaff(id: 0, name: 'installer', role: seeded[SystemRoles.ownerCode]),
      name: 'Amer',
      username: 'amer',
      pin: '4321',
      roleId: seeded[SystemRoles.ownerCode]!.id,
    ))
        .value!;
  });

  Future<PosStaff> hire(String code, {String name = 'Rana', String pin = '1111'}) async =>
      (await staff.create(
        by: owner,
        name: name,
        username: name.toLowerCase(),
        pin: pin,
        roleId: seeded[code]!.id,
      ))
          .value!;

  group('who may administer', () {
    test('a cashier cannot edit a role', () async {
      final rana = await hire(SystemRoles.cashierCode);

      final refused = await roles.save(
        seeded[SystemRoles.cashierCode]!.copyWith(nameEn: 'Anything'),
        by: rana,
      );

      expect(refused.succeeded, isFalse);
      expect(
        (refused.refusal as NotPermitted).capability,
        PosCapability.staffManage,
      );
    });

    test('a cashier cannot create staff', () async {
      final rana = await hire(SystemRoles.cashierCode);
      final refused = await staff.create(
        by: rana,
        name: 'Smuggled',
        username: 'smuggled',
        pin: '9999',
        roleId: seeded[SystemRoles.ownerCode]!.id,
      );
      expect(refused.refusal, isA<NotPermitted>());
      expect(await staff.all(), hasLength(2));
    });

    test('an owner may', () async {
      final result = await roles.save(
        seeded[SystemRoles.supervisorCode]!.copyWith(nameEn: 'Shift Lead'),
        by: owner,
      );
      expect(result.succeeded, isTrue);
      expect(result.value!.nameEn, 'Shift Lead');
    });
  });

  group('roles', () {
    test('the owner role cannot be stripped of a capability', () async {
      final refused = await roles.save(
        seeded[SystemRoles.ownerCode]!.copyWith(
          capabilities: {...SystemRoles.owner}..remove(PosCapability.backupManage),
        ),
        by: owner,
      );
      expect((refused.refusal as RoleNotAllowed).reason, isA<OwnerMustKeepEverything>());
    });

    test('a cashier role cannot be given back-office capabilities', () async {
      final refused = await roles.save(
        seeded[SystemRoles.cashierCode]!.copyWith(
          capabilities: {...SystemRoles.cashier, PosCapability.catalogManage},
        ),
        by: owner,
      );
      final reason = (refused.refusal as RoleNotAllowed).reason;
      expect(
        (reason as CashiersAreNotAdministrators).capabilities,
        {PosCapability.catalogManage},
      );
    });

    test('a manager cannot write themselves a role holding the database',
        () async {
      // §48, at the write rather than in the editor. Without this rule anybody
      // with staff.manage escalates to everything in one save, and the whole
      // permission catalogue is a checkbox deep.
      final manager = await hire(SystemRoles.managerCode, name: 'Mona', pin: '2222');

      final refused = await roles.save(
        const PosRole(
          id: 0,
          code: 'invented',
          nameEn: 'Invented',
          capabilities: {
            PosCapability.operate,
            PosCapability.backupManage,
          },
        ),
        by: manager,
      );

      final reason = (refused.refusal as RoleNotAllowed).reason;
      expect(
        (reason as CannotGrantWhatYouLack).capabilities,
        {PosCapability.backupManage},
      );

      // And nothing was written.
      final saved = await roles.all();
      expect(saved.map((r) => r.code), isNot(contains('invented')));
    });

    test('a manager can grant everything they hold themselves', () async {
      final manager = await hire(SystemRoles.managerCode, name: 'Nour', pin: '3333');

      final result = await roles.save(
        PosRole(
          id: 0,
          code: 'floor-lead',
          nameEn: 'Floor lead',
          capabilities: SystemRoles.supervisor,
        ),
        by: manager,
      );
      expect(result.succeeded, isTrue);
    });

    test('a system role cannot be deleted', () async {
      final refused = await roles.delete(seeded[SystemRoles.managerCode]!, by: owner);
      expect(refused.refusal, isA<RoleIsSystemDefined>());
    });

    test('a role somebody holds is refused, and says who', () async {
      final custom = (await roles.save(
        const PosRole(
          id: 0,
          code: 'barista',
          nameEn: 'Barista',
          capabilities: {PosCapability.operate},
        ),
        by: owner,
      ))
          .value!;

      await staff.create(
        by: owner,
        name: 'Nour',
        username: 'nour',
        pin: '2222',
        roleId: custom.id,
      );

      final refused = await roles.delete(custom, by: owner);
      expect((refused.refusal as RoleStillHeld).staffNames, ['Nour']);
    });

    test('an unheld custom role deletes, and the ledger keeps what it was', () async {
      final custom = (await roles.save(
        const PosRole(
          id: 0,
          code: 'runner',
          nameEn: 'Runner',
          capabilities: {PosCapability.operate},
        ),
        by: owner,
      ))
          .value!;

      expect((await roles.delete(custom, by: owner)).succeeded, isTrue);
      expect(await roles.all(), hasLength(SystemRoles.seeded.length));

      final trail = await audit.recent(entityType: AuditAction.entityRole);
      expect(trail.first.action, AuditAction.roleDeleted);
      expect(trail.first.before!['code'], 'runner');
    });
  });

  group('staff', () {
    test('a duplicate username is refused rather than shadowing the first', () async {
      final refused = await staff.create(
        by: owner,
        name: 'Another Amer',
        username: 'amer',
        pin: '5555',
        roleId: seeded[SystemRoles.cashierCode]!.id,
      );
      expect((refused.refusal as UsernameTaken).username, 'amer');
    });

    test('a PIN resolves to the person and the capabilities their role carries', () async {
      await hire(SystemRoles.supervisorCode, name: 'Sara', pin: '7788');

      final found = await staff.byPin('7788');
      expect(found!.name, 'Sara');
      expect(found.role!.code, SystemRoles.supervisorCode);
      expect(found.can(PosCapability.discountApply), isTrue);
      expect(found.can(PosCapability.staffManage), isFalse);

      expect(await staff.byPin('0000'), isNull);
    });

    test('a direct grant sits on top of the role', () async {
      final rana = await hire(SystemRoles.cashierCode);
      expect(rana.can(PosCapability.discountApply), isFalse);

      final updated = await staff.update(
        by: owner,
        staffId: rana.id,
        directGrants: {PosCapability.discountApply},
      );

      expect(updated.value!.can(PosCapability.discountApply), isTrue);
      expect(updated.value!.role!.code, SystemRoles.cashierCode,
          reason: 'a single extra grant must not promote somebody to a new role');
    });

    test('disabling the last person who can manage staff is refused', () async {
      await hire(SystemRoles.cashierCode);

      final refused = await staff.setActive(by: owner, staffId: owner.id, isActive: false);
      expect(
        (refused.refusal as WouldLockEveryoneOut).capability,
        PosCapability.staffManage,
      );

      // With a second manager in place the same act is allowed.
      await hire(SystemRoles.managerCode, name: 'Hala', pin: '3333');
      expect(
        (await staff.setActive(by: owner, staffId: owner.id, isActive: false)).succeeded,
        isTrue,
      );
    });

    test('moving the last manager to a cashier role is refused too', () async {
      final refused = await staff.update(
        by: owner,
        staffId: owner.id,
        roleId: seeded[SystemRoles.cashierCode]!.id,
      );
      expect(refused.refusal, isA<WouldLockEveryoneOut>());
    });
  });

  group('the ledger', () {
    test('records a role change with what it was and what it became', () async {
      await roles.save(
        seeded[SystemRoles.supervisorCode]!.copyWith(
          capabilities: {...SystemRoles.supervisor}..remove(PosCapability.orderRefund),
        ),
        by: owner,
      );

      final entry = (await audit.recent(entityType: AuditAction.entityRole)).first;
      expect(entry.action, AuditAction.roleUpdated);
      expect(entry.actorName, 'Amer');
      expect(entry.before!['capabilities'], contains(PosCapability.orderRefund));
      expect(entry.after!['capabilities'], isNot(contains(PosCapability.orderRefund)));
    });

    test('records a PIN reset without recording the PIN', () async {
      final rana = await hire(SystemRoles.cashierCode);
      await staff.resetPin(by: owner, staffId: rana.id, pin: '8642');

      final entry = (await audit.recent(entityType: AuditAction.entityStaff)).first;
      expect(entry.action, AuditAction.staffPinReset);
      expect(entry.before, isNull);
      expect(entry.after, {'name': 'Rana'});
      expect(await staff.byPin('8642'), isNotNull);
    });

    test('names both people when a supervisor lent the permission', () async {
      final rana = await hire(SystemRoles.cashierCode);
      final sara = await hire(SystemRoles.supervisorCode, name: 'Sara', pin: '7788');

      await audit.record(
        by: rana,
        approvedBy: sara,
        action: AuditAction.permissionOverridden,
        entityType: AuditAction.entityOrder,
        entityId: '1042',
        reason: 'Discount on a wrong order',
      );

      final entry = (await audit.recent(entityType: AuditAction.entityOrder)).first;
      expect(entry.actorName, 'Rana');
      expect(entry.approvedByName, 'Sara');
      expect(entry.wasOverridden, isTrue);
      expect(entry.reason, 'Discount on a wrong order');
    });

    test('a refused write leaves no trace', () async {
      final before = (await audit.recent()).length;
      await roles.delete(seeded[SystemRoles.managerCode]!, by: owner);
      expect((await audit.recent()).length, before);
    });
  });
  group('a cloud till, where the platform owns who works here', () {
    // `BootstrapSeeder` upserts `pos_staff` from the bundle and deactivates
    // anybody the bundle does not name. Before this, the back office let a
    // manager add a cashier on a cloud till and the next sync switched them
    // off — silently, with nothing to read. Found by auditing the panes
    // against the seeder rather than by any test.
    late PostgresStaffDirectoryRepository cloud;

    setUp(() {
      cloud = PostgresStaffDirectoryRepository(
        database: db,
        config: pg.config,
        restaurantId: restaurantId,
        offline: false,
      );
    });

    test('adding somebody is refused, and says where to go', () async {
      final result = await cloud.create(
        by: owner,
        name: 'Nour',
        username: 'nour',
        pin: '9876',
        roleId: seeded[SystemRoles.cashierCode]!.id,
      );

      expect(result.refusal, isA<ManagedByPlatform>());
      expect(
        (result.refusal! as ManagedByPlatform).what,
        ManagedByPlatform.staffRecords,
      );
    });

    test('renaming somebody is refused', () async {
      final rana = await hire(SystemRoles.cashierCode);
      final result = await cloud.update(
        by: owner,
        staffId: rana.id,
        name: 'Renamed',
      );
      expect(result.refusal, isA<ManagedByPlatform>());
    });

    test('a PIN reset is refused', () async {
      final rana = await hire(SystemRoles.cashierCode, name: 'Dina', pin: '2468');
      final result = await cloud.resetPin(by: owner, staffId: rana.id, pin: '1357');
      expect(result.refusal, isA<ManagedByPlatform>());
    });

    test('disabling somebody is refused', () async {
      final rana = await hire(SystemRoles.cashierCode, name: 'Hala', pin: '3579');
      final result = await cloud.setActive(
        by: owner,
        staffId: rana.id,
        isActive: false,
      );
      expect(result.refusal, isA<ManagedByPlatform>());
    });

    test('changing direct grants is refused — the bundle carries them',
        () async {
      final rana = await hire(SystemRoles.cashierCode, name: 'Sara', pin: '1122');
      final result = await cloud.update(
        by: owner,
        staffId: rana.id,
        directGrants: {PosCapability.orderRefund},
      );
      expect(result.refusal, isA<ManagedByPlatform>());
    });

    test('but assigning a role is allowed — it is not in the bundle', () async {
      // The half that works, and the reason this refuses per act rather than
      // closing the pane. `pos_staff.role_id` is never written by the seeder.
      final rana = await hire(SystemRoles.cashierCode, name: 'Mai', pin: '3344');
      final result = await cloud.update(
        by: owner,
        staffId: rana.id,
        roleId: seeded[SystemRoles.supervisorCode]!.id,
      );

      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect(result.value!.role!.code, SystemRoles.supervisorCode);
    });

    test('and so are the per-person grants Wave C added', () async {
      // `pos_staff_roles`, the overrides and the ceilings are local tables the
      // bundle does not touch.
      final rana = await hire(SystemRoles.cashierCode, name: 'Yara', pin: '5566');
      final result = await cloud.setGrants(
        by: owner,
        staffId: rana.id,
        extraRoleIds: {seeded[SystemRoles.supervisorCode]!.id},
        overrides: const [],
        limits: const {},
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
    });

    test('an offline till is unaffected', () async {
      final result = await staff.create(
        by: owner,
        name: 'Offline',
        username: 'offline',
        pin: '7788',
        roleId: seeded[SystemRoles.cashierCode]!.id,
      );
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
    });
  });
}
