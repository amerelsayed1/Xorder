import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/security/pin_hash.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/reason_code.dart';
import 'migrations.dart';
import 'pos_database.dart';

/// Preparing an empty PostgreSQL for a till, in one place.
///
/// This used to live only in `bin/pos_migrate.dart`, which meant an offline
/// install began at a command line — on a machine in a restaurant, run by
/// whoever unboxed it. The setup wizard now offers the same thing, and both
/// call *this*, because two implementations of "what grants does a till need"
/// is two answers to a question that must only ever have one.
///
/// **The credential used here is not the credential the till keeps.** Creating
/// a database and applying DDL needs an owner or superuser; selling needs
/// `pos_till`, which is granted the least it can work with and no DDL at all.
/// The admin credential passes through this class and is never persisted —
/// `PosDbSecretStore` only ever holds the till's.
class LocalBootstrap {
  const LocalBootstrap(this.database);

  final PosDatabase database;

  /// `CREATE DATABASE` cannot run inside a transaction and has no
  /// `IF NOT EXISTS`, so it needs its own connection to the maintenance
  /// database and a look before it leaps.
  ///
  /// Returns true when it created one, false when it was already there —
  /// which is not a failure, and is the normal case on a re-run.
  static Future<bool> createDatabase(
    DeploymentConfig admin,
    String adminPassword,
    String name,
  ) async {
    if (!_isPlainIdentifier(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'A database name must be letters, digits and underscores — it is an '
            'identifier, so it cannot be a bind parameter and will be quoted '
            'into the statement.',
      );
    }

    final connection = await Connection.open(
      Endpoint(
        host: admin.databaseHost,
        port: admin.databasePort,
        database: 'postgres',
        username: admin.databaseUser,
        password: adminPassword,
      ),
      settings: ConnectionSettings(
        sslMode: admin.allowsInsecureTransport
            ? SslMode.disable
            : SslMode.require,
      ),
    );

    try {
      final existing = await connection.execute(
        Sql.named('SELECT 1 FROM pg_database WHERE datname = @name'),
        parameters: {'name': name},
      );
      if (existing.isNotEmpty) return false;

      await connection.execute('CREATE DATABASE "$name"');
      return true;
    } finally {
      await connection.close();
    }
  }

  /// Apply every pending migration. Returns the versions this call applied.
  Future<List<int>> migrate(DeploymentConfig admin) =>
      PosMigrator(database).migrate(admin);

  /// The restaurant row, matched on slug so a re-run adopts rather than
  /// duplicates.
  Future<int> seedRestaurant(
    DeploymentConfig admin, {
    required String slug,
    required String name,
  }) async {
    final rows = await database.query(
      admin,
      'INSERT INTO pos_restaurants (slug, name) VALUES (@slug, @name) '
      // Touch the conflicting column and nothing else: this is how the row's
      // id comes back without any of its content being overwritten.
      'ON CONFLICT (slug) DO UPDATE SET slug = EXCLUDED.slug RETURNING id',
      parameters: {'slug': slug, 'name': name},
    );

    return rows.first[0]! as int;
  }

  /// One branch. Its code is the invoice prefix — `MAIN-2026-000042`.
  Future<int> seedBranch(
    DeploymentConfig admin, {
    required int restaurantId,
    required String name,
    required String code,
  }) async {
    final rows = await database.query(
      admin,
      'INSERT INTO pos_branches (restaurant_id, code, name, supported_order_types) '
      "VALUES (@restaurant, @code, @name, ARRAY['dine_in','takeaway','delivery']) "
      'ON CONFLICT (restaurant_id, code) DO UPDATE SET code = EXCLUDED.code '
      'RETURNING id',
      parameters: {'restaurant': restaurantId, 'code': code, 'name': name},
    );

    return rows.first[0]! as int;
  }

  /// The four system roles, from [SystemRoles.seeded].
  ///
  /// Re-running never resets a restaurant's edited permissions: the upsert
  /// touches `code` and leaves `capabilities` alone.
  ///
  /// @return role code → id, and how many were newly created.
  Future<({Map<String, int> ids, int created})> seedSystemRoles(
    DeploymentConfig admin,
    int restaurantId,
  ) async {
    final ids = <String, int>{};
    var created = 0;

    for (final entry in SystemRoles.seeded.entries) {
      final rows = await database.query(
        admin,
        'INSERT INTO pos_roles (restaurant_id, code, name_en, name_ar, capabilities, is_system) '
        'VALUES (@restaurant, @code, @nameEn, @nameAr, @capabilities, true) '
        'ON CONFLICT (restaurant_id, code) DO UPDATE SET code = EXCLUDED.code '
        'RETURNING id, (xmax = 0) AS inserted',
        parameters: {
          'restaurant': restaurantId,
          'code': entry.key,
          'nameEn': entry.value.nameEn,
          'nameAr': entry.value.nameAr,
          'capabilities': entry.value.capabilities.toList(),
        },
      );
      ids[entry.key] = rows.first[0]! as int;
      if (rows.first[1] == true) created++;
    }

    return (ids: ids, created: created);
  }

  /// The reason lists, from [SystemReasons.seeded].
  ///
  /// Migration 9 seeds every restaurant that existed when it ran. This is for
  /// the ones created afterwards — by `--seed`, or by the wizard building a
  /// database on a machine in a restaurant — because a `CROSS JOIN` over
  /// `pos_restaurants` inside a migration can only ever see the past.
  ///
  /// Re-running never resets an edited list: the upsert touches `code` and
  /// leaves the names, the sort order and `is_active` alone. A restaurant that
  /// renamed "Manager comp" or retired "Training" keeps its decision.
  ///
  /// @return how many rows were newly created.
  Future<int> seedReasonCodes(DeploymentConfig admin, int restaurantId) async {
    var created = 0;

    for (final scope in SystemReasons.seededScopes) {
      // Per scope, not one list for all of them: "Staff meal" is not a reason
      // anybody puts money into a till.
      final reasons = SystemReasons.seededFor(scope);
      for (var i = 0; i < reasons.length; i++) {
        final reason = reasons[i];
        final rows = await database.query(
          admin,
          'INSERT INTO pos_reason_codes (restaurant_id, scope, code, name_en, '
          '  name_ar, requires_note, sort_order) '
          'VALUES (@restaurant, @scope, @code, @nameEn, @nameAr, @note, @sort) '
          'ON CONFLICT (restaurant_id, scope, code) DO UPDATE SET code = EXCLUDED.code '
          'RETURNING (xmax = 0) AS inserted',
          parameters: {
            'restaurant': restaurantId,
            'scope': scope.wire,
            'code': reason.code,
            'nameEn': reason.nameEn,
            'nameAr': reason.nameAr,
            'note': reason.requiresNote,
            'sort': i + 1,
          },
        );
        if (rows.first[0] == true) created++;
      }
    }

    return created;
  }

  /// The rate this restaurant charges, named.
  ///
  /// Migration 16 backfills every restaurant that existed when it ran; this is
  /// the other half — a restaurant created afterwards needs one too, or its
  /// products can never be classified and an ETA filing has an unnamed rate on
  /// it.
  ///
  /// Returns true when it created one. Idempotent: a restaurant that already
  /// has a default keeps whatever it configured, because a re-run of setup must
  /// not reset an accountant's decision.
  Future<bool> seedTaxGroup(
    DeploymentConfig admin,
    int restaurantId, {
    int rateBp = 1400,
  }) async {
    final rows = await database.query(
      admin,
      'INSERT INTO pos_tax_groups (restaurant_id, name_en, name_ar, rate_bp, '
      "  is_default) VALUES (@restaurant, 'VAT', @nameAr, @rate, true) "
      'ON CONFLICT DO NOTHING RETURNING id',
      parameters: {
        'restaurant': restaurantId,
        'nameAr': 'ضريبة القيمة المضافة',
        // Whatever this branch is actually charging. Defaulting to Egypt's
        // headline rate for a branch configured otherwise would change what
        // customers pay.
        'rate': rateBp,
      },
    );
    return rows.isNotEmpty;
  }

  /// The first person, on the owner role.
  ///
  /// The PIN is hashed here with the same PBKDF2 work factor the till verifies
  /// with, which is why [PinHash] is pure Dart. `DO NOTHING` on conflict, so a
  /// re-run never silently resets somebody's PIN.
  ///
  /// @return true when this call created the account.
  Future<bool> seedOwner(
    DeploymentConfig admin, {
    required int restaurantId,
    required int branchId,
    required int roleId,
    required String name,
    required String username,
    required String pin,
  }) async {
    final salt = PinHash.newSalt();
    final hash = await PinHash.hash(pin, salt);

    final rows = await database.query(
      admin,
      'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, '
      'pin_salt, pin_hash, role_id, capabilities) '
      // No direct grants: the ROLE carries the permissions, so changing what
      // an owner may do is one edit in one place.
      "VALUES (@restaurant, @branch, @name, @username, @salt, @hash, @role, '{}') "
      'ON CONFLICT (restaurant_id, username) DO NOTHING RETURNING id',
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'name': name,
        'username': username,
        'salt': salt,
        'hash': hash,
        'role': roleId,
      },
    );

    return rows.isNotEmpty;
  }

  /// Grant a database role exactly what its job needs.
  ///
  /// Pure — it returns statements rather than running them — so the CLI and
  /// the wizard apply an identical list and a test can read it without a
  /// database.
  ///
  /// **Two sets, not one.** [till] is what a machine standing in a public room
  /// gets. [administrative] is what the Management section additionally needs,
  /// and is the set that authoring the menu belongs to.
  ///
  /// [cloudSeeding] adds the writes `BootstrapSeeder` needs to replace the
  /// local cache with the platform's copy. It defaults to **off**, because the
  /// safe answer is the one an offline install gets by forgetting to ask.
  static List<String> tillGrants({
    required String database,
    required String role,
    bool cloudSeeding = false,
  }) => <String>[
    'GRANT CONNECT ON DATABASE "$database" TO "$role"',
    'GRANT USAGE ON SCHEMA public TO "$role"',
    // The sale itself.
    'GRANT SELECT, INSERT ON pos_orders, pos_order_lines, pos_order_payments TO "$role"',
    // Voiding is an UPDATE, and an order row that can be updated at all is a
    // total that can be rewritten — which is the property the no-UPDATE grant
    // above was protecting. So the grant is **column-scoped**: the till may set
    // what an order's status is and who changed it, and may not touch a single
    // money column. PostgreSQL enforces that per column, so a recovered till
    // credential can void a sale in the open and still cannot reprice one.
    'GRANT UPDATE (status, status_changed_at, voided_at, voided_by, '
        'void_reason_id, void_note, business_day_id) ON pos_orders TO "$role"',
    // `refunded_quantity` is deliberately NOT in this list, though it was
    // when migration 9 introduced the column. Migration 12 maintains it from a
    // SECURITY DEFINER trigger instead, which means the counter can only move
    // by inserting a refund row — the number and the record it summarises
    // cannot disagree, because there is no way to write one without the other.
    // Granting UPDATE here would put that back under the till's own hand.
    'GRANT UPDATE (voided_at, voided_by, void_reason_id) '
        'ON pos_order_lines TO "$role"',
    // Why somebody voided, refunded, discounted or overrode a price. The till
    // reads the list; editing it is a settings act and belongs to the
    // administrative role.
    'GRANT SELECT ON pos_reason_codes TO "$role"',
    // What happened to a line, in order. INSERT and SELECT only — the same
    // discipline as the audit ledger, because "this line was voided after it
    // was cooked" is a claim that must not be editable by the person it names.
    'GRANT SELECT, INSERT ON pos_order_line_events TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_order_line_events_id_seq TO "$role"',
    // The discounts the restaurant offers. Read-only for the till, for the
    // same reason the menu is: a cashier applies a discount, they do not
    // invent one. Authoring belongs to [administrativeGrants].
    'GRANT SELECT ON pos_discounts, pos_discount_targets TO "$role"',
    // What was actually taken off a sale. INSERT and SELECT, never UPDATE —
    // a discount already applied to a settled order is a record of what the
    // customer was charged, not a working figure.
    'GRANT SELECT, INSERT ON pos_order_discounts TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_order_discounts_id_seq TO "$role"',
    // Money going back. INSERT and SELECT, never UPDATE or DELETE: a refund
    // already given is a record of money that left the drawer, and an
    // adjustment to it is a second refund, not an edit of the first.
    //
    // Note what is missing — UPDATE on `pos_orders.refunded_minor`. The
    // counter is maintained by migration 12's trigger, so a till can record a
    // refund and cannot quietly change how much has already gone back.
    'GRANT SELECT, INSERT ON pos_refunds, pos_refund_lines, '
        'pos_refund_payments TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_refunds_id_seq, '
        'pos_refund_lines_id_seq, pos_refund_payments_id_seq TO "$role"',
    // What the restaurant has configured. Read-only for the till: a cashier
    // reads the blind-close switch, they do not flip it. Authoring belongs to
    // [administrativeGrants].
    'GRANT SELECT ON pos_settings TO "$role"',
    // Who the receipt says sold the food. Read-only for the till: the slip is
    // printed at the counter, and the address on it is set in Management.
    'GRANT SELECT ON pos_receipt_profiles TO "$role"',
    // The e-receipt queue. The till writes into it at settlement and the drain
    // updates a row as it gets a verdict, so this needs UPDATE — but not
    // DELETE, and never on `document` or `canonical`: those are the evidence
    // of what was actually filed, and a row that could be rewritten after a
    // rejection would be a row that proves nothing.
    'GRANT SELECT, INSERT ON pos_eta_receipts TO "$role"',
    'GRANT UPDATE (status, signature, attempts, last_attempt_at, '
        'submitted_at, submission_uuid, long_id, error_message, qr_payload) '
        'ON pos_eta_receipts TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_eta_receipts_id_seq TO "$role"',
    // The chain head, one row per device. UPDATE by definition: every receipt
    // moves it.
    'GRANT SELECT, INSERT, UPDATE ON pos_eta_chains TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_eta_chains_id_seq TO "$role"',
    // Money into and out of the drawer that is not a sale. INSERT and SELECT,
    // never UPDATE or DELETE — a pay-out already recorded is a record of money
    // that left, and correcting one is a second movement, not an edit.
    'GRANT SELECT, INSERT ON pos_cash_movements TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_cash_movements_id_seq TO "$role"',
    'GRANT SELECT ON pos_cash_drawers TO "$role"',
    // The trading day. A till opens one when it starts selling and closes one
    // at the end of the night, so this needs UPDATE — but column-scoped, like
    // an order's: the till may close a day and may not rewrite its takings.
    'GRANT SELECT, INSERT ON pos_business_days TO "$role"',
    'GRANT UPDATE (closed_at, closed_by, forced, force_reason, gross_minor, '
        'net_minor) ON pos_business_days TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_business_days_id_seq TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_invoice_sequences TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_orders_id_seq, pos_order_lines_id_seq, '
        'pos_order_payments_id_seq TO "$role"',
    // Everything Wave M added to the menu, read-only on the same terms as the
    // menu itself.
    //
    // **These were missing entirely**, which meant an offline till on its own
    // credential could not load its catalogue at all: `pos_product_prices` is
    // joined by the catalogue query and `pos_combos` and its two children are
    // read straight after it. Every database suite ran as the superuser, so
    // nothing caught it — the probe role in `till_grants_enforced_test.dart`
    // did, once it was asked about the tables added since Wave A.
    'GRANT SELECT ON pos_tax_groups, pos_product_prices, pos_combos, '
        'pos_combo_groups, pos_combo_options TO "$role"',
    // The tax breakdown a filing needs, written with the sale (§17, ETA).
    // INSERT and SELECT, never UPDATE: the rates a customer was charged are
    // part of the record of what they paid.
    'GRANT SELECT, INSERT ON pos_order_taxes TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_order_taxes_id_seq TO "$role"',
    // What a combo line was actually made of. Same discipline: the kitchen
    // made these, so they are a record rather than a working figure.
    'GRANT SELECT, INSERT ON pos_order_line_items TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_order_line_items_id_seq TO "$role"',
    // The restaurant's own data. Read-only for the till: a till displays
    // the menu, it does not edit it. Changing what the restaurant sells is
    // a back-office act — see [administrativeGrants].
    'GRANT SELECT ON pos_restaurants, pos_branches, pos_staff, pos_categories, '
        'pos_products, pos_modifier_groups, pos_modifiers, '
        'pos_product_modifier_groups, pos_dining_tables TO "$role"',
    // Read by every till on every sign-in: the permission gate needs to
    // know what the person who just entered a PIN may do.
    'GRANT SELECT ON pos_roles TO "$role"',
    // The rest of that answer — the extra roles, the per-person exceptions and
    // the ceilings. SELECT only: a till reads what somebody may do and never
    // writes it, which is the whole reason the back office needs a separate
    // credential.
    'GRANT SELECT ON pos_staff_roles, pos_staff_permission_overrides, '
        'pos_permission_limits TO "$role"',
    // Claiming a pairing code stamps `claimed_at`, and an installer with
    // no dashboard registers the terminal from the wizard.
    'GRANT SELECT, INSERT, UPDATE ON pos_terminals TO "$role"',
    // Shifts are opened and closed at the till by definition. No DELETE: a
    // cash-up somebody wants to disappear is exactly the row that must not.
    'GRANT SELECT, INSERT, UPDATE ON pos_shifts TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_shifts_id_seq TO "$role"',
    // The outbound queue. No DELETE: a delivered row is the record that
    // this sale was already sent, and a till that can forget that is a
    // till that sends it twice.
    'GRANT SELECT, INSERT, UPDATE ON pos_outbox TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_outbox_id_seq TO "$role"',
    // The audit ledger. INSERT and SELECT, never UPDATE or DELETE. The
    // table's triggers refuse the rest anyway; this makes it true at the
    // grant as well, so the trigger is the second line of defence rather
    // than the only one.
    'GRANT SELECT, INSERT ON pos_audit_events TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_audit_events_id_seq TO "$role"',
    // Cloud seeding, and ONLY on a cloud till — see [cloudSeeding]. The
    // platform authors the menu, the staff and the floor, and the bootstrap
    // seeder replicates them here as a local cache: wipe-and-rewrite for the
    // catalog, `setval` to push the serials past the platform's ids (which is
    // why the sequences need UPDATE).
    //
    // This softens the read-only-catalog rule above knowingly, and the bargain
    // is only sound in one direction. On a CLOUD till a stolen till credential
    // rewrites the local *cache*, and the cache is not authoritative — every
    // order is re-priced server-side (POS-BE-006), so repricing the display
    // buys an attacker nothing at settlement. On an OFFLINE till there is no
    // second opinion: this database IS the restaurant. Granted there, the same
    // statements let a credential recovered from the till reprice the menu for
    // real, and — through `pos_staff` — point somebody's row at the owner role
    // or overwrite a PIN hash, reaching Management without ever knowing the
    // administrator's password. So an offline install does not get them, and
    // loses nothing: `BootstrapSeeder` never runs without a platform, and
    // Management authors the menu and the staff over the ADMIN credential.
    if (cloudSeeding) ...[
      'GRANT INSERT, UPDATE ON pos_restaurants, pos_branches, pos_staff TO "$role"',
      'GRANT INSERT, UPDATE, DELETE ON pos_categories, pos_products, '
          'pos_modifier_groups, pos_modifiers, pos_product_modifier_groups, '
          'pos_dining_tables TO "$role"',
      'GRANT USAGE, SELECT, UPDATE ON SEQUENCE pos_restaurants_id_seq, '
          'pos_branches_id_seq, pos_staff_id_seq, pos_categories_id_seq, '
          'pos_products_id_seq, pos_modifier_groups_id_seq, '
          'pos_modifiers_id_seq, pos_dining_tables_id_seq TO "$role"',
    ] else ...[
      // Taken away, not merely withheld. Every offline branch server built
      // before this distinction existed was granted the block above, and a
      // grant list that only ever adds would leave those installs — the ones
      // already taking money — permissive forever. REVOKE of something never
      // held is a no-op, so a fresh install pays nothing for this.
      'REVOKE INSERT, UPDATE, DELETE ON pos_restaurants, pos_branches, '
          'pos_staff, pos_categories, pos_products, pos_modifier_groups, '
          'pos_modifiers, pos_product_modifier_groups, pos_dining_tables '
          'FROM "$role"',
      'REVOKE UPDATE ON SEQUENCE pos_restaurants_id_seq, '
          'pos_branches_id_seq, pos_staff_id_seq, pos_categories_id_seq, '
          'pos_products_id_seq, pos_modifier_groups_id_seq, '
          'pos_modifiers_id_seq, pos_dining_tables_id_seq FROM "$role"',
    ],
    'GRANT SELECT, INSERT, UPDATE ON pos_cloud_state TO "$role"',
    // The open floor. The ONE table the till may DELETE from: settlement
    // removes the parked row because the durable record of the money now
    // lives in pos_orders.
    'GRANT SELECT, INSERT, UPDATE, DELETE ON pos_parked_tickets TO "$role"',
    // Tax rules and charges, cached where pricing can reach them.
    'GRANT SELECT, INSERT, UPDATE ON pos_money_config TO "$role"',
    // So the in-app migrator can see the schema is current and do nothing,
    // rather than failing on the read.
    'GRANT SELECT ON schema_migrations TO "$role"',
  ];

  /// What only the administrator role gets — acts the Management section
  /// performs on behalf of somebody who signed in holding the capability.
  ///
  /// Still no DELETE, anywhere. Staff are disabled, roles are edited and the
  /// catalogue is archived, because a deleted row takes its audit trail's
  /// subject with it and "who removed this and when" is the question that gets
  /// asked.
  static List<String> administrativeGrants({required String role}) => <String>[
    'GRANT SELECT, INSERT, UPDATE ON pos_staff TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_staff_id_seq TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_roles TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_roles_id_seq TO "$role"',
    // Granting a second role, an exception or a ceiling. DELETE here, unlike
    // almost everywhere else: these three are the *current* shape of somebody's
    // access rather than a record of anything that happened, and the record is
    // the audit ledger's job. A revoked override that could only be flipped to
    // ALLOW and never removed would leave a table nobody can read.
    'GRANT SELECT, INSERT, UPDATE, DELETE ON pos_staff_roles, '
        'pos_staff_permission_overrides, pos_permission_limits TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_permission_limits_id_seq TO "$role"',
    // A restaurant's own vocabulary for why things happen. Editable in
    // Settings, which is why this is here and not in the till's set — a
    // cashier who could add a void reason could add one that reads well.
    'GRANT SELECT, INSERT, UPDATE ON pos_reason_codes TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_reason_codes_id_seq TO "$role"',
    // Authoring the menu and the floor.
    //
    // **These were missing**, and the till list actively REVOKEs them on an
    // offline install — deliberately, because the till must not reprice its own
    // menu. An administrator role is given both lists, so without these it was
    // handed the revoke and nothing to put back: Management could open the Menu
    // pane on an offline till and fail on the first save. That is the one
    // deployment where menu authoring exists at all.
    //
    // No DELETE on the catalogue: items are archived, not removed, because a
    // deleted product takes its sales history's subject with it.
    'GRANT SELECT, INSERT, UPDATE ON pos_categories, pos_products, '
        'pos_modifier_groups, pos_modifiers, pos_dining_tables TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_categories_id_seq, '
        'pos_products_id_seq, pos_modifier_groups_id_seq, '
        'pos_modifiers_id_seq, pos_dining_tables_id_seq TO "$role"',
    // The join between the two. DELETE here, unlike the tables it joins: a row
    // is not a record of anything that happened, only the current shape of
    // which options a product offers.
    'GRANT SELECT, INSERT, DELETE ON pos_product_modifier_groups TO "$role"',
    // Tax groups, per-branch prices and combos — everything Wave M made
    // authorable. Read for now, because nothing in Management edits them yet;
    // the writes land with Wave D's settings surface, and granting them before
    // there is a screen would be granting them to nobody.
    'GRANT SELECT ON pos_tax_groups, pos_product_prices, pos_combos, '
        'pos_combo_groups, pos_combo_options TO "$role"',
    // The trade name, registration number and address a receipt is judged on.
    // No DELETE: a branch stops having a profile by being archived, not by
    // having its identity removed from under the receipts already issued.
    'GRANT SELECT, INSERT, UPDATE ON pos_receipt_profiles TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_receipt_profiles_id_seq TO "$role"',
    // Authoring what the restaurant offers, and what a role may take off by
    // hand. A DELETE on the targets, unlike almost everywhere else: they are
    // not a record of anything that happened, only the current shape of a
    // discount, and un-targeting a category has to be possible.
    'GRANT SELECT, INSERT, UPDATE ON pos_discounts TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_discounts_id_seq TO "$role"',
    'GRANT SELECT, INSERT, DELETE ON pos_discount_targets TO "$role"',
    // Authoring what the restaurant has configured. The till reads these; the
    // back office writes them — blind close, the business-day start time and
    // the refund policy are all decisions somebody makes once.
    'GRANT SELECT, INSERT, UPDATE, DELETE ON pos_settings TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_settings_id_seq TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_cash_drawers TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_cash_drawers_id_seq TO "$role"',
    // Reading the drawer's history and the day's. SELECT only, even here: a
    // pay-out is a record of money that left, and the back office corrects one
    // by recording another.
    'GRANT SELECT ON pos_cash_movements, pos_business_days TO "$role"',
    // Reading refunds back — the void and refund reports, and the Activity
    // pane. SELECT only, even here: a refund is a record of money that left
    // the drawer, and the back office corrects one by issuing another, not by
    // editing the first.
    'GRANT SELECT ON pos_refunds, pos_refund_lines, pos_refund_payments '
        'TO "$role"',
  ];

  Future<void> applyGrants(
    DeploymentConfig admin,
    List<String> statements,
  ) async {
    for (final statement in statements) {
      await database.query(admin, statement);
    }
  }

  /// A plain identifier, because a database name is quoted into DDL rather
  /// than bound.
  /// The rule lives on [DeploymentConfig] so the wizard can apply it at the
  /// point of typing. This is the last line of defence, not the first.
  static bool _isPlainIdentifier(String value) =>
      DeploymentConfig.isPlainIdentifier(value);
}
