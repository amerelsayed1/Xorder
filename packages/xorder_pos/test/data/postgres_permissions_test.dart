@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/permissions.dart';

import 'pg_fixture.dart';

/// Migration 5, against a database that already had staff on it.
///
/// The interesting case is never the fresh install — it is the branch server
/// that has been taking money for a month and is now being upgraded. Two things
/// there can go wrong silently, which is why they are asserted rather than
/// assumed: capability strings that no longer match anything, and a business
/// left with nobody who may reach the screen that hands out permissions.
void main() {
  if (PgFixture.host == null) {
    test('permissions (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;

  /// The schema as it stood before roles existed. Dropped and rebuilt rather
  /// than truncated: this suite is about a migration, and a migration only runs
  /// once per database.
  Future<void> installOldSchema() async {
    await db.query(pg.config, 'DROP SCHEMA public CASCADE');
    await db.query(pg.config, 'CREATE SCHEMA public');
    await PosMigrator(
      db,
      migrations: posMigrations.where((m) => m.version < 5).toList(),
    ).migrate(pg.config);
  }

  Future<int> seedLegacyBusiness() async {
    final rows = await db.query(
      pg.config,
      // Version 4's names: this runs before migration 64.
      "INSERT INTO pos_restaurants (slug, name) VALUES ('legacy', 'Legacy Kitchen') RETURNING id",
    );
    final businessId = rows.first[0] as int;

    // Two people, in the order they were created. The first is the account
    // `--seed` made; the second is one a manager added by hand later.
    final salt = PinHash.newSalt();
    final hash = await PinHash.hash('1234', salt);
    for (final staff in [
      (name: 'Amer', username: 'manager', capabilities: [
        'pos.operate', 'pos.discount', 'pos.shift_open', 'pos.shift_close',
        'pos.cash_movement', 'pos.reprint',
      ]),
      (name: 'Rana', username: 'rana', capabilities: ['pos.operate', 'pos.reprint']),
    ]) {
      await db.query(
        pg.config,
        'INSERT INTO pos_staff (restaurant_id, name, username, pin_salt, pin_hash, capabilities) '
        'VALUES (@business, @name, @username, @salt, @hash, @capabilities)',
        parameters: {
          'business': businessId,
          'name': staff.name,
          'username': staff.username,
          'salt': salt,
          'hash': hash,
          'capabilities': staff.capabilities,
        },
      );
    }
    return businessId;
  }

  setUp(() async {
    pg = await PgFixture.open('permissions');
    db = pg.database;
    await installOldSchema();
  });

  tearDown(() => pg.close());

  test('rewrites the capability names the first build shipped', () async {
    final businessId = await seedLegacyBusiness();
    await PosMigrator(db).migrate(pg.config);

    final rows = await db.query(
      pg.config,
      'SELECT name, capabilities FROM pos_users WHERE business_id = @r ORDER BY id',
      parameters: {'r': businessId},
    );

    final amer = (rows.first[1] as List).cast<String>().toSet();
    // Every legacy string is gone, and the person kept every permission they
    // had. A rename that dropped one would be a silent demotion.
    expect(amer, containsAll(<String>{
      PosCapability.operate,
      PosCapability.discountApply,
      PosCapability.shiftOpen,
      PosCapability.shiftClose,
      PosCapability.cashMovement,
      PosCapability.receiptReprint,
    }));
    expect(amer.where((c) => c.startsWith('pos.') && c != PosCapability.operate), isEmpty);

    final rana = (rows.last[1] as List).cast<String>().toSet();
    expect(rana, {PosCapability.operate, PosCapability.receiptReprint});
  });

  test('seeds the system roles and leaves somebody able to grant permissions', () async {
    final businessId = await seedLegacyBusiness();
    await PosMigrator(db).migrate(pg.config);

    final roles = await db.query(
      pg.config,
      'SELECT code, is_system, capabilities FROM pos_roles WHERE business_id = @r ORDER BY code',
      parameters: {'r': businessId},
    );
    expect(roles.map((r) => r[0]), [
      SystemRoles.cashierCode,
      SystemRoles.managerCode,
      SystemRoles.ownerCode,
      SystemRoles.supervisorCode,
    ]);
    expect(roles.every((r) => r[1] as bool), isTrue);

    final owner = roles.firstWhere((r) => r[0] == SystemRoles.ownerCode);
    expect((owner[2] as List).cast<String>().toSet(), SystemRoles.owner);

    final cashier = roles.firstWhere((r) => r[0] == SystemRoles.cashierCode);
    expect(
      (cashier[2] as List).cast<String>().toSet().intersection(PosCapability.backOffice),
      isEmpty,
      reason: 'a cashier must never hold a back-office capability',
    );

    // The installer's own account becomes the owner. Without this the upgrade
    // would leave a branch on which nobody holds `staff.manage`, and therefore
    // nobody who could grant it.
    final assigned = await db.query(
      pg.config,
      'SELECT s.name, r.code FROM pos_users s JOIN pos_roles r ON r.id = s.role_id '
      'WHERE s.business_id = @r ORDER BY s.id',
      parameters: {'r': businessId},
    );
    expect(assigned.map((row) => [row[0], row[1]]), [
      ['Amer', SystemRoles.ownerCode],
      ['Rana', SystemRoles.cashierCode],
    ]);
  });

  group('the audit trail', () {
    late int businessId;

    setUp(() async {
      businessId = await seedLegacyBusiness();
      await PosMigrator(db).migrate(pg.config);
      await db.query(
        pg.config,
        'INSERT INTO pos_audit_events (business_id, actor_name, action, entity_type, entity_id, '
        '                              before_value, after_value) '
        "VALUES (@r, 'Amer', 'product.price_changed', 'product', '42', "
        """       '{"price_minor": 4500}'::jsonb, '{"price_minor": 5000}'::jsonb)""",
        parameters: {'r': businessId},
      );
    });

    test('records what changed, before and after', () async {
      final rows = await db.query(
        pg.config,
        "SELECT actor_name, action, after_value->>'price_minor' FROM pos_audit_events "
        'WHERE business_id = @r',
        parameters: {'r': businessId},
      );
      expect(rows.single[0], 'Amer');
      expect(rows.single[1], 'product.price_changed');
      expect(rows.single[2], '5000');
    });

    // The three ways somebody with a psql prompt would try to remove the row
    // that names them. All of them are refused by the database, not by the app:
    // the app is not in the room when this is attempted.
    final refused = throwsA(
      isA<PosDbException>().having(
        (e) => e.toString(),
        'message',
        contains('append-only'),
      ),
    );

    test('refuses an update', () async {
      await expectLater(
        db.query(pg.config, "UPDATE pos_audit_events SET actor_name = 'Somebody else'"),
        refused,
      );
    });

    test('refuses a delete', () async {
      await expectLater(db.query(pg.config, 'DELETE FROM pos_audit_events'), refused);
    });

    test('refuses a truncate', () async {
      await expectLater(db.query(pg.config, 'TRUNCATE pos_audit_events'), refused);
    });
  });
}
