@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/domain/models/permissions.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// Migration 47: the roles that took payments off bills before the act had a
/// key keep taking them off.
///
/// `payment.remove` is new, and a key added after a role exists reaches it
/// only by a migration saying so. Without this, every supervisor and manager on
/// an existing install would suddenly need somebody else's PIN to correct a
/// payment they have always corrected themselves — and the owner would need
/// one too, which the owner-holds-everything rule does not allow.
void main() {
  if (PgFixture.host == null) {
    test('payment.remove (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;

  setUp(() async {
    pg = await PgFixture.open('payment_remove');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('pr', 'PR') RETURNING id",
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
      {...capabilities}..remove(PosCapability.paymentRemove);

  /// The roles as a branch server that had not run 47 would hold them.
  Future<List<int>> beforeTheKey() async {
    await role(SystemRoles.ownerCode, without(SystemRoles.owner));
    await role(SystemRoles.managerCode, without(SystemRoles.manager));
    await role(SystemRoles.supervisorCode, without(SystemRoles.supervisor));
    await role(SystemRoles.cashierCode, SystemRoles.cashier);
    await role('head_waiter', {PosCapability.operate});
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 47',
    );
    return PosMigrator(db).migrate(pg.config);
  }

  test('the owner, the manager and the supervisor keep it', () async {
    expect(await beforeTheKey(), [47]);
    for (final code in [
      SystemRoles.ownerCode,
      SystemRoles.managerCode,
      SystemRoles.supervisorCode,
    ]) {
      expect(await held(code), contains(PosCapability.paymentRemove), reason: code);
    }
  });

  test('a cashier and a business\'s own roles now ask a supervisor', () async {
    await beforeTheKey();
    expect(
      await held(SystemRoles.cashierCode),
      isNot(contains(PosCapability.paymentRemove)),
    );
    expect(
      await held('head_waiter'),
      isNot(contains(PosCapability.paymentRemove)),
    );
  });

  test('running it again adds it once', () async {
    await beforeTheKey();
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 47',
    );
    await PosMigrator(db).migrate(pg.config);
    expect(
      (await held(SystemRoles.managerCode))
          .where((c) => c == PosCapability.paymentRemove),
      hasLength(1),
    );
  });
}
