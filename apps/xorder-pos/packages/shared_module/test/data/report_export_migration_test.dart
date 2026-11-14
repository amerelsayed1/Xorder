@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/services/authorization.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';
import 'package:shared_module/data/sql/sql.dart' show SqlDatabase;

/// Migration 48: the owner role may export to Excel, and nobody else is given
/// it by a migration.
///
/// `report.export` is new (BO-11). A branch server from before it has an owner
/// role without it, and nothing else would ever add it — the seed only runs
/// for businesses created afterwards. Without this the owner of every
/// existing install could not export, and their own role would stop passing
/// the rule that the owner holds everything.
void main() {
  if (PgFixture.host == null) {
    test('report.export (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late SqlDatabase db;
  late int businessId;

  setUp(() async {
    pg = await PgFixture.open('report_export');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('rx', 'RX') RETURNING id",
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

  /// The roles as a branch server that had not run 48 would hold them.
  Future<List<int>> beforeTheKey() async {
    await role(
      SystemRoles.ownerCode,
      {...SystemRoles.owner}..remove(PosCapability.reportExport),
    );
    await role(SystemRoles.managerCode, SystemRoles.manager);
    await role(SystemRoles.supervisorCode, SystemRoles.supervisor);
    await role('accountant', {PosCapability.reportsView});
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 48',
    );
    return PosMigrator(db).migrate(pg.config);
  }

  test('an owner from before the key may export, and is whole again', () async {
    expect(await beforeTheKey(), [48]);
    final owner = await held(SystemRoles.ownerCode);
    expect(owner, contains(PosCapability.reportExport));
    // The rule `RolesRepository.save` asks: an owner role missing a key is
    // a role the Roles pane cannot save.
    expect(
      Authorization.validateRole(
        PosRole(
          id: 1,
          code: SystemRoles.ownerCode,
          nameEn: 'Owner',
          capabilities: owner.toSet(),
        ),
      ),
      isNull,
    );
  });

  test('and no one else is given it — reading reports is not taking them', () async {
    await beforeTheKey();
    for (final code in [
      SystemRoles.managerCode,
      SystemRoles.supervisorCode,
      'accountant',
    ]) {
      expect(
        await held(code),
        isNot(contains(PosCapability.reportExport)),
        reason: code,
      );
    }
  });

  test('and running it again adds it once', () async {
    await beforeTheKey();
    await db.query(
      pg.config,
      'DELETE FROM schema_migrations WHERE version = 48',
    );
    await PosMigrator(db).migrate(pg.config);
    expect(
      (await held(SystemRoles.ownerCode))
          .where((c) => c == PosCapability.reportExport),
      hasLength(1),
    );
  });
}
