@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/permissions.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Migration 53: the roles that added customers at the counter before the act
/// had a key keep adding them (XORD-001).
///
/// `customers.create` is new, and a key added after a role exists reaches it
/// only by a migration saying so. Without this, every cashier on an existing
/// install would lose, on the day of the update, the customer box they use to
/// take a phone number at the till.
void main() {
  if (PgFixture.host == null) {
    test('customers.create (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;

  setUp(() async {
    pg = await PgFixture.open('customers_create');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('cc', 'CC') RETURNING id",
    )).first[0]! as int;
  });

  tearDown(() => pg.close());

  Future<void> role(String code, Set<String> capabilities) => db.query(
    pg.config,
    'INSERT INTO pos_roles (business_id, code, name_en, name_ar, '
    '  capabilities, is_system) '
    'VALUES (@r, @code, @code, @code, @capabilities, true)',
    parameters: {
      'r': businessId,
      'code': code,
      'capabilities': capabilities.toList(),
    },
  );

  Future<List<String>> held(String code) async => ((await db.query(
    pg.config,
    'SELECT capabilities FROM pos_roles WHERE business_id = @r AND code = @code',
    parameters: {'r': businessId, 'code': code},
  )).first[0]! as List).cast<String>();

  Set<String> without(Set<String> capabilities) =>
      {...capabilities}..remove(PosCapability.customersCreate);

  /// The roles as a branch server that had not run 53 would hold them.
  Future<List<int>> beforeTheKey() async {
    for (final code in [
      SystemRoles.ownerCode,
      SystemRoles.managerCode,
      SystemRoles.supervisorCode,
      SystemRoles.cashierCode,
    ]) {
      await role(code, without(SystemRoles.seeded[code]!.capabilities));
    }
    await role('head_waiter', {PosCapability.operate});
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 53',
    );
    return PosMigrator(db).migrate(pg.config);
  }

  test('every seeded role keeps adding customers at the counter', () async {
    expect(await beforeTheKey(), [53]);
    for (final code in [
      SystemRoles.ownerCode,
      SystemRoles.managerCode,
      SystemRoles.supervisorCode,
      SystemRoles.cashierCode,
    ]) {
      expect(
        await held(code),
        contains(PosCapability.customersCreate),
        reason: code,
      );
    }
  });

  test("a business's own roles are left for the owner to decide", () async {
    await beforeTheKey();
    expect(
      await held('head_waiter'),
      isNot(contains(PosCapability.customersCreate)),
    );
  });

  test('running it again adds it once', () async {
    await beforeTheKey();
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 53',
    );
    await PosMigrator(db).migrate(pg.config);
    expect(
      (await held(SystemRoles.managerCode))
          .where((c) => c == PosCapability.customersCreate),
      hasLength(1),
    );
  });
}
