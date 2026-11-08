@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/domain/models/permissions.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Migration 46: the owner role may enter Admin Mode, and nobody else is given
/// it by a migration.
///
/// A branch server from before Admin Mode has an owner role without
/// `admin.enter`, and nothing else would ever add it — the seed only runs for
/// businesses created afterwards. Without this the owner of every existing
/// install would be refused at their own back office.
void main() {
  if (PgFixture.host == null) {
    test('admin.enter (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;

  setUp(() async {
    pg = await PgFixture.open('admin_enter');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('ae', 'AE') RETURNING id",
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

  Future<Set<String>> held(String code) async => {
    ...((await db.query(
      pg.config,
      'SELECT capabilities FROM pos_roles WHERE business_id = @r AND code = @code',
      parameters: {'r': businessId, 'code': code},
    )).first[0]! as List).cast<String>(),
  };

  /// The roles as a branch server that had not run 46 would hold them.
  Future<List<int>> beforeAdminMode() async {
    await role(
      SystemRoles.ownerCode,
      {...SystemRoles.owner}..remove(PosCapability.adminEnter),
    );
    await role(SystemRoles.managerCode, SystemRoles.manager);
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 46',
    );
    return PosMigrator(db).migrate(pg.config);
  }

  test('an owner from before Admin Mode may enter it', () async {
    expect(await beforeAdminMode(), [46]);
    expect(await held(SystemRoles.ownerCode), contains(PosCapability.adminEnter));
  });

  test('and a manager is not given it — that is the owner\'s to decide', () async {
    await beforeAdminMode();
    expect(
      await held(SystemRoles.managerCode),
      isNot(contains(PosCapability.adminEnter)),
    );
  });

  test('and running it again adds it once', () async {
    await beforeAdminMode();
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 46',
    );
    await PosMigrator(db).migrate(pg.config);
    final owner = (await db.query(
      pg.config,
      'SELECT capabilities FROM pos_roles WHERE business_id = @r AND code = @code',
      parameters: {'r': businessId, 'code': SystemRoles.ownerCode},
    )).first[0]! as List;
    expect(owner.where((c) => c == PosCapability.adminEnter), hasLength(1));
  });
}
