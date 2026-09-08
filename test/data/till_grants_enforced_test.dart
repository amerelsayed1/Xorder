@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

import 'pg_fixture.dart';

/// The offline grant set, applied to a real role on a real server, and then
/// tried.
///
/// `till_grants_test.dart` asserts the statements. This asserts that
/// PostgreSQL agrees — which is the only claim that matters, because the
/// statements could be right and the schema could still hand the role
/// something through a default privilege or an inherited membership.
void main() {
  if (PgFixture.host == null) {
    test('till grants (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const role = 'pos_till_grant_probe';
  const password = 'probe-only';

  late PgFixture pg;
  late PosDatabase db;

  setUpAll(() async {
    pg = await PgFixture.open('till_grants');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);

    // A throwaway role, created and dropped here. It holds nothing but what
    // the offline grant list gives it, which is the point.
    await _dropRole(db, pg, role);
    await db.query(
      pg.config,
      'CREATE ROLE "$role" LOGIN PASSWORD \'$password\'',
    );
    // The upgrade, not the fresh install: the role is first given the CLOUD
    // set — which is what every offline branch server built before the split
    // actually holds — and then the offline list is applied over it. Passing
    // from that starting point is the claim that matters, because a REVOKE
    // that only works on a role which never had the grant proves nothing.
    for (final statement in LocalBootstrap.tillGrants(
      database: pg.config.databaseName,
      role: role,
      cloudSeeding: true,
    )) {
      await db.query(pg.config, statement);
    }
    for (final statement in LocalBootstrap.tillGrants(
      database: pg.config.databaseName,
      role: role,
      cloudSeeding: false,
    )) {
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

  test('the till may read the menu', () async {
    final connection = await connect();
    addTearDown(connection.close);
    // No refusal is the assertion; the row count is irrelevant.
    await connection.execute('SELECT 1 FROM pos_products');
    await connection.execute('SELECT 1 FROM pos_staff');
  });

  test('the till may not reprice the menu', () async {
    expect(
      await refusalFor('UPDATE pos_products SET price_minor = 1'),
      '42501',
      reason: 'insufficient_privilege — the money offline lives in this row',
    );
  });

  test('the till may not add or remove a product', () async {
    expect(
      await refusalFor(
        "INSERT INTO pos_products (restaurant_id, category_id, name_en, "
        "price_minor) VALUES (1, 1, 'x', 1)",
      ),
      '42501',
    );
    expect(await refusalFor('DELETE FROM pos_products'), '42501');
  });

  test('the till may not promote somebody to the owner role', () async {
    // The escalation this whole change exists to close: with UPDATE here, a
    // recovered till password reaches Management without the administrator's.
    expect(await refusalFor('UPDATE pos_staff SET role_id = 1'), '42501');
  });

  test('the till may not overwrite a PIN hash', () async {
    expect(
      await refusalFor("UPDATE pos_staff SET pin_hash = 'x', pin_salt = 'y'"),
      '42501',
    );
  });

  test('the till may not rename the restaurant or its branches', () async {
    expect(await refusalFor("UPDATE pos_restaurants SET name = 'x'"), '42501');
    expect(await refusalFor("UPDATE pos_branches SET name = 'x'"), '42501');
  });

  test('the till may still take money', () async {
    // The other half of the claim: closing the hole must not close the till.
    expect(
      await refusalFor('SELECT 1 FROM pos_orders'),
      isNull,
      reason: 'reads its own sales',
    );
    expect(
      await refusalFor('SELECT 1 FROM pos_shifts'),
      isNull,
    );
    expect(
      await refusalFor('SELECT 1 FROM pos_invoice_sequences'),
      isNull,
    );
  });

  test('a sale is still writable, and still cannot be repriced', () async {
    expect(
      await refusalFor('UPDATE pos_orders SET total_minor = 0'),
      '42501',
      reason: 'the column-scoped grant excludes every money column',
    );
  });

  // ── Everything added since Wave A ────────────────────────────────────────
  //
  // The tests above were written when the schema stopped at orders and staff.
  // Six migrations have added tables since, and a grant list that only ever
  // grows is a grant list nobody re-reads — so each new table gets the same
  // two questions: can the till do its job, and can it do anything else.

  test('the till reads what the restaurant configured, and sets nothing',
      () async {
    // A cashier reads the blind-close switch; they do not flip it.
    expect(await refusalFor('SELECT 1 FROM pos_settings'), isNull);
    expect(
      await refusalFor("UPDATE pos_settings SET value = 'true'"),
      '42501',
    );
    expect(
      await refusalFor(
        'INSERT INTO pos_settings (restaurant_id, scope, key, value) '
        "VALUES (1, 'branch', 'cash.blind_close', 'false')",
      ),
      '42501',
    );
  });

  test('the till records a drawer movement and cannot unrecord one', () async {
    // A pay-out already recorded is money that left. Correcting one is a
    // second movement, not an edit of the first.
    expect(await refusalFor('SELECT 1 FROM pos_cash_movements'), isNull);
    expect(
      await refusalFor('UPDATE pos_cash_movements SET amount_minor = 0'),
      '42501',
    );
    expect(await refusalFor('DELETE FROM pos_cash_movements'), '42501');
  });

  test('the till closes a business day and cannot move when it started',
      () async {
    expect(await refusalFor('SELECT 1 FROM pos_business_days'), isNull);
    expect(
      await refusalFor('UPDATE pos_business_days SET gross_minor = 0'),
      isNull,
      reason: 'in the column-scoped grant — a close writes the totals',
    );
    expect(
      await refusalFor('UPDATE pos_business_days SET opened_at = now()'),
      '42501',
    );
    expect(await refusalFor('DELETE FROM pos_business_days'), '42501');
  });

  test('the till can load the whole menu Wave M gave it', () async {
    // **This is what the probe role found.** None of these five had a grant,
    // so an offline till on its own credential could not read its catalogue at
    // all — `pos_product_prices` is joined by the catalogue query and the
    // three combo tables are read straight after it. Every suite ran as the
    // superuser, which is precisely the class of bug a superuser cannot see.
    expect(await refusalFor('SELECT 1 FROM pos_tax_groups'), isNull);
    expect(await refusalFor('SELECT 1 FROM pos_product_prices'), isNull);
    expect(await refusalFor('SELECT 1 FROM pos_combos'), isNull);
    expect(await refusalFor('SELECT 1 FROM pos_combo_groups'), isNull);
    expect(await refusalFor('SELECT 1 FROM pos_combo_options'), isNull);
  });

  test('the till may not change the tax rates it charges', () async {
    // Offline, this row IS the VAT rate on every receipt.
    expect(await refusalFor('UPDATE pos_tax_groups SET rate_bp = 0'), '42501');
    expect(
      await refusalFor('UPDATE pos_product_prices SET price_minor = 1'),
      '42501',
    );
    expect(await refusalFor('UPDATE pos_combos SET price_minor = 1'), '42501');
  });

  test('the till writes the tax breakdown with the sale, and cannot edit it',
      () async {
    // Also missing: a settlement writes `pos_order_taxes` and, for a combo,
    // `pos_order_line_items`. Without these grants every sale on an offline
    // till would have failed at the moment the money moved.
    expect(await refusalFor('SELECT 1 FROM pos_order_taxes'), isNull);
    expect(await refusalFor('SELECT 1 FROM pos_order_line_items'), isNull);
    expect(
      await refusalFor('UPDATE pos_order_taxes SET amount_minor = 0'),
      '42501',
      reason: 'the rates a customer was charged are part of what they paid',
    );
    expect(await refusalFor('DELETE FROM pos_order_taxes'), '42501');
    expect(await refusalFor('DELETE FROM pos_order_line_items'), '42501');
  });

  test('the till may not change what the receipt says about the seller',
      () async {
    // The trade name and registration number on a legal document.
    expect(await refusalFor('SELECT 1 FROM pos_receipt_profiles'), isNull);
    expect(
      await refusalFor(
        "UPDATE pos_receipt_profiles SET registration_number = '000000000'",
      ),
      '42501',
    );
  });

  test('the till queues an e-receipt and cannot rewrite what it filed',
      () async {
    // The column-scoped grant on `pos_eta_receipts`: the status and the
    // verdict move, the document does not. A row that could be rewritten after
    // a rejection would be a row that proves nothing about what was submitted.
    expect(await refusalFor('SELECT 1 FROM pos_eta_receipts'), isNull);
    expect(
      await refusalFor("UPDATE pos_eta_receipts SET status = 'accepted'"),
      isNull,
      reason: 'the drain records a verdict',
    );
    expect(
      await refusalFor("UPDATE pos_eta_receipts SET document = '{}'::jsonb"),
      '42501',
    );
    expect(
      await refusalFor("UPDATE pos_eta_receipts SET canonical = 'x'"),
      '42501',
    );
    expect(
      await refusalFor("UPDATE pos_eta_receipts SET uuid = 'x'"),
      '42501',
      reason: 'the fingerprint is not the till to change',
    );
    expect(await refusalFor('DELETE FROM pos_eta_receipts'), '42501');
  });

  test('the till may not grant itself a permission', () async {
    // **The one that decides whether Wave C means anything.** A recovered till
    // credential that could write an ALLOW override, add a role, or lift a
    // ceiling would make every permission in the product advisory.
    expect(await refusalFor('SELECT 1 FROM pos_staff_roles'), isNull);
    expect(
      await refusalFor(
        'INSERT INTO pos_staff_roles (staff_id, role_id) VALUES (1, 1)',
      ),
      '42501',
    );
    expect(
      await refusalFor(
        'INSERT INTO pos_staff_permission_overrides '
        "  (staff_id, capability, effect) VALUES (1, 'backup.manage', 'ALLOW')",
      ),
      '42501',
    );
    expect(
      await refusalFor('DELETE FROM pos_staff_permission_overrides'),
      '42501',
      reason: 'nor remove a DENY somebody put there',
    );
    expect(
      await refusalFor(
        'INSERT INTO pos_permission_limits (restaurant_id, subject_type, '
        "  subject_id, limit_key, limit_bp) VALUES (1, 'staff', 1, 'x', 10000)",
      ),
      '42501',
    );
    expect(
      await refusalFor('UPDATE pos_permission_limits SET limit_bp = 10000'),
      '42501',
      reason: 'nor lift a ceiling somebody set',
    );
  });

  test('the till may not edit a role', () async {
    expect(await refusalFor('SELECT 1 FROM pos_roles'), isNull);
    expect(
      await refusalFor(
        "UPDATE pos_roles SET capabilities = ARRAY['backup.manage']",
      ),
      '42501',
    );
  });

  test('the refund counters belong to the trigger, not to the till', () async {
    // The case this file was written to answer and never did. Migration 12
    // maintains `refunded_minor` from a SECURITY DEFINER trigger and grants
    // the till no UPDATE on it. Whether that combination works under the
    // till's own privileges is exactly what a superuser run cannot say — and
    // this probe role can, because it holds nothing but the grant list.
    expect(
      await refusalFor('UPDATE pos_orders SET refunded_minor = 0'),
      '42501',
    );
    expect(
      await refusalFor('UPDATE pos_order_lines SET refunded_quantity = 0'),
      '42501',
    );
    // And the till can still record the refund that moves them.
    expect(await refusalFor('SELECT 1 FROM pos_refunds'), isNull);
  });

}

/// A role with grants on it cannot be dropped until they are revoked, and
/// `DROP OWNED BY` throws when the role does not exist yet — which is the
/// normal case on the first run.
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
