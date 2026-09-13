@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

import 'pg_fixture.dart';

/// The administrator grant set, applied to a real role and then tried.
///
/// **The sibling of `till_grants_enforced_test.dart`, written after that one
/// found six missing grants on the till.** The same question asked of the back
/// office found a worse answer: an administrator role is given the till list
/// *and* the administrative one, and on an offline install the till list
/// **REVOKEs** the catalogue writes — deliberately, so a recovered till
/// password cannot reprice the menu. The administrative list never put them
/// back. Management could open the Menu pane on the one deployment where menu
/// authoring exists at all, and fail on the first save.
///
/// Nothing caught it because `postgres_admin_test.dart` runs as the superuser,
/// who needs no grant. A probe role needs no password anybody has to be asked
/// for, which is the whole reason this file can exist.
void main() {
  if (PgFixture.host == null) {
    test('admin grants (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  // Per checkout, for the till probe's reason: a role is cluster-wide, and one
  // name shared by two worktrees meant each one's cleanup broke the other's
  // run.
  final role = PgFixture.roleFor('admin_grant_probe');
  const password = 'probe-only';

  late PgFixture pg;
  late PosDatabase db;

  setUpAll(() async {
    pg = await PgFixture.open('admin_grants');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);

    await _dropRole(db, pg, role);
    await db.query(
      pg.config,
      'CREATE ROLE "$role" LOGIN PASSWORD \'$password\'',
    );

    // Exactly what `pos_migrate --grant-admin-to` applies, in the same order:
    // the OFFLINE till list — which is the case that revokes — and then the
    // administrative one over it.
    for (final statement in [
      ...LocalBootstrap.tillGrants(
        database: pg.config.databaseName,
        role: role,
        cloudSeeding: false,
      ),
      ...LocalBootstrap.administrativeGrants(role: role),
    ]) {
      await db.query(pg.config, statement);
    }
  });

  tearDownAll(() async {
    await _dropRole(db, pg, role);
    await db.close();
  });

  Future<Connection> connect() => Connection.open(
    Endpoint(
      host: pg.config.databaseHost,
      port: pg.config.databasePort,
      database: pg.config.databaseName,
      username: role,
      password: password,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  Future<Object?> refusalFor(String sql) async {
    final connection = await connect();
    try {
      await connection.execute(sql);
      return null;
    } on ServerException catch (error) {
      return error.code;
    } finally {
      await connection.close();
    }
  }

  test('Management can author the menu', () async {
    // The bug this file was written for. Every one of these is a statement the
    // Menu pane makes, and every one of them was refused.
    expect(
      await refusalFor(
        "INSERT INTO pos_categories (restaurant_id, name_en) "
        "VALUES (1, 'Grills')",
      ),
      isNot('42501'),
      reason: 'a foreign key failure is fine here; a privilege one is not',
    );
    expect(
      await refusalFor('UPDATE pos_products SET price_minor = 1'),
      isNull,
    );
    expect(await refusalFor('UPDATE pos_categories SET sort_order = 1'), isNull);
    expect(
      await refusalFor('UPDATE pos_dining_tables SET seats = 4'),
      isNull,
    );
    expect(
      await refusalFor('DELETE FROM pos_product_modifier_groups'),
      isNull,
      reason: 'which options a product offers is current shape, not history',
    );
  });

  test('Management can author what the restaurant charges', () async {
    expect(await refusalFor('SELECT 1 FROM pos_money_config'), isNull);
    expect(await refusalFor('SELECT 1 FROM pos_tax_groups'), isNull);
  });

  test('Management can read and write the people', () async {
    expect(await refusalFor("UPDATE pos_staff SET name = 'x'"), isNull);
    expect(
      await refusalFor("UPDATE pos_roles SET name_en = 'x'"),
      isNull,
    );
    expect(
      await refusalFor(
        "INSERT INTO pos_staff_permission_overrides "
        "  (staff_id, capability, effect) VALUES (1, 'order.refund', 'ALLOW')",
      ),
      isNot('42501'),
    );
    expect(
      await refusalFor('DELETE FROM pos_permission_limits'),
      isNull,
      reason: 'removing a ceiling has to be expressible',
    );
  });

  test('Management can set who the receipt says sold the food', () async {
    expect(
      await refusalFor("UPDATE pos_receipt_profiles SET trade_name = 'x'"),
      isNull,
    );
  });

  test('Management still cannot delete a person or a sale', () async {
    // The rule the administrative list opens with: no DELETE anywhere. Staff
    // are disabled, roles are edited and the catalogue is archived, because a
    // deleted row takes its audit trail's subject with it.
    expect(await refusalFor('DELETE FROM pos_staff'), '42501');
    expect(await refusalFor('DELETE FROM pos_orders'), '42501');
    expect(await refusalFor('DELETE FROM pos_products'), '42501');
    expect(await refusalFor('DELETE FROM pos_categories'), '42501');
    expect(await refusalFor('DELETE FROM pos_audit_events'), '42501');
  });

  test('Management cannot rewrite a settled sale', () async {
    // The back office is not a way around the column-scoped grant on orders.
    // Somebody who can change what a customer was charged, after they paid, is
    // somebody the audit ledger cannot describe.
    expect(await refusalFor('UPDATE pos_orders SET total_minor = 0'), '42501');
    expect(
      await refusalFor('UPDATE pos_orders SET refunded_minor = 0'),
      '42501',
    );
    expect(
      await refusalFor("UPDATE pos_eta_receipts SET canonical = 'x'"),
      '42501',
    );
  });

  test('Management may look at the drawer without moving it', () async {
    expect(await refusalFor('SELECT 1 FROM pos_cash_movements'), isNull);
    expect(
      await refusalFor('UPDATE pos_cash_movements SET amount_minor = 0'),
      '42501',
    );
    expect(await refusalFor('SELECT 1 FROM pos_refunds'), isNull);
    expect(
      await refusalFor('UPDATE pos_refunds SET total_minor = 0'),
      '42501',
    );
  });
}

/// A role with grants on it cannot be dropped until they are revoked, and
/// `DROP OWNED BY` throws when the role does not exist yet.
Future<void> _dropRole(PosDatabase db, PgFixture pg, String role) async {
  for (final statement in [
    'DROP OWNED BY "$role"',
    'DROP ROLE IF EXISTS "$role"',
  ]) {
    try {
      await db.query(pg.config, statement);
    } on Object {
      // Nothing to revoke, or nothing to drop.
    }
  }
}
