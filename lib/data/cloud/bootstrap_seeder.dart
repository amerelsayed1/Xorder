import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/tender_method.dart';
import '../postgres/pos_database.dart';
import '../../domain/models/customer.dart';
import 'bootstrap_bundle.dart';

/// What a seed attempt did, as data the wizard and the sync loop can act on.
class SeedReport {
  const SeedReport.applied(this.configVersion) : applied = true, reason = null;

  const SeedReport.skipped(this.reason, {this.configVersion = 0})
    : applied = false;

  final bool applied;
  final int configVersion;

  /// Why nothing was written. `stale` is the rollback refusal of POS-BE-025;
  /// `unchanged` is an equal version — both are normal operation, not errors.
  final String? reason;
}

/// Writes a bootstrap bundle into the till's local PostgreSQL.
///
/// This is how a cloud terminal gets its world: the platform authors the
/// catalog, the staff and the floor, and this seeder makes the local database —
/// which every existing repository already reads — agree with it. Nothing in
/// `domain/` or `features/` knows the seed happened; the sale screen just finds
/// the menu there, exactly as it does on a branch server.
///
/// **Platform ids are kept verbatim.** A seeded product row carries the
/// platform's `menu_item_id` as its primary key, which is what lets the drain
/// send lines the server can re-price (POS-BE-006) without an id-mapping table
/// that would have to survive every resync. Serial sequences are bumped past
/// the seeded ids afterwards so locally-authored rows can never collide.
///
/// **The catalog and floor are wiped and rewritten; people are not.** Staff
/// rows are referenced by shifts (`ON DELETE RESTRICT` — the record of who
/// counted a drawer outlives employment), so departed staff are deactivated,
/// never deleted. Catalog rows have no such history: order lines snapshot the
/// name and price at sale time precisely so the catalog can be replaced whole.
class BootstrapSeeder {
  const BootstrapSeeder({required PosDatabase database, required this.config})
    : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;

  Future<SeedReport> seed(BootstrapBundle bundle, {bool force = false}) async {
    if (!bundle.seedable) {
      return const SeedReport.skipped('incomplete');
    }
    final restaurant = bundle.restaurant!;

    return _db.runTx(config, (tx) async {
      final held = await tx.execute(
        Sql.named(
          'SELECT config_version FROM pos_cloud_state WHERE restaurant_id = @restaurant',
        ),
        parameters: {'restaurant': restaurant.id},
      );
      final cached = held.isEmpty ? -1 : held.first[0] as int;

      // The version is the sole precedence signal (POS-BE-025): an older bundle
      // is a rollback and is refused, an equal one is already applied. `force`
      // exists for a re-seed after a half-failed apply, never for precedence.
      if (!force && bundle.configVersion < cached) {
        return SeedReport.skipped('stale', configVersion: cached);
      }
      if (!force && bundle.configVersion == cached) {
        return SeedReport.skipped('unchanged', configVersion: cached);
      }

      await _seedIdentity(tx, bundle);
      await _seedReceiptProfiles(tx, bundle);
      await _seedMoney(tx, bundle);
      await _seedFinancialAccounts(tx, bundle);
      await _seedTenderTypes(tx, bundle);
      await _seedTenderAccountDefaults(tx, bundle);
      await _seedStaff(tx, bundle);
      await _seedCustomers(tx, bundle);
      await _seedCatalog(tx, bundle);
      await _seedTables(tx, bundle);
      await _bumpSequences(tx);

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_cloud_state (restaurant_id, config_version, bootstrap_synced_at, updated_at)
          VALUES (@restaurant, @version, @syncedAt, now())
          ON CONFLICT (restaurant_id) DO UPDATE
            SET config_version = @version, bootstrap_synced_at = @syncedAt, updated_at = now()
        '''),
        parameters: {
          'restaurant': restaurant.id,
          'version': bundle.configVersion,
          'syncedAt': (bundle.syncedAt ?? DateTime.now()).toUtc(),
        },
      );

      return SeedReport.applied(bundle.configVersion);
    });
  }

  /// Records what the platform says the logo is (XORD-021). The picture itself
  /// is downloaded afterwards by `LogoSync`: this runs in a transaction that
  /// must not wait on a network.
  ///
  /// No `branding` block at all is an older platform and changes nothing. A
  /// block with no logo means the restaurant has none: the platform's copy on
  /// this till is removed, but a logo chosen on the till itself is not, because
  /// the platform never sent that one and has no say over it.
  Future<void> _seedLogo(
    TxSession tx,
    int restaurantId,
    BootstrapBranding? branding,
  ) async {
    if (branding == null) return;
    final url = branding.logoUrl;
    if (url != null) {
      await tx.execute(
        Sql.named(
          'UPDATE pos_restaurants SET logo_remote_url = @url WHERE id = @id',
        ),
        parameters: {'id': restaurantId, 'url': url},
      );
      return;
    }
    await tx.execute(
      Sql.named(
        'UPDATE pos_restaurants '
        '   SET logo_remote_url = NULL, '
        '       logo_bytes = CASE WHEN logo_source = \'platform\' '
        '                         THEN NULL ELSE logo_bytes END, '
        '       logo_mime = CASE WHEN logo_source = \'platform\' '
        '                        THEN NULL ELSE logo_mime END, '
        '       logo_fetched_url = CASE WHEN logo_source = \'platform\' '
        '                               THEN NULL ELSE logo_fetched_url END, '
        '       logo_updated_at = CASE WHEN logo_source = \'platform\' '
        '                              THEN now() ELSE logo_updated_at END, '
        '       logo_source = CASE WHEN logo_source = \'platform\' '
        '                          THEN NULL ELSE logo_source END '
        ' WHERE id = @id',
      ),
      parameters: {'id': restaurantId},
    );
  }

  Future<void> _seedIdentity(TxSession tx, BootstrapBundle bundle) async {
    final restaurant = bundle.restaurant!;
    final terminal = bundle.terminal!;

    await tx.execute(
      Sql.named('''
        INSERT INTO pos_restaurants (id, slug, name, name_ar, tax_number, is_active)
        VALUES (@id, @slug, @name, @nameAr, @tax, true)
        ON CONFLICT (id) DO UPDATE
          SET slug = @slug, name = @name, name_ar = @nameAr, tax_number = @tax, is_active = true
      '''),
      parameters: {
        'id': restaurant.id,
        'slug': restaurant.slug,
        'name': restaurant.name,
        'nameAr': restaurant.nameAr,
        'tax': restaurant.taxRegistrationNumber,
      },
    );

    // Which languages the menu is written in (XORD-005). Only when the platform
    // said: an older platform sends nothing, and the till keeps what it has.
    if (restaurant.contentLanguages case final languages?) {
      await tx.execute(
        Sql.named(
          'UPDATE pos_restaurants SET content_languages = @languages '
          'WHERE id = @id',
        ),
        parameters: {'id': restaurant.id, 'languages': languages},
      );
    }

    await _seedLogo(tx, restaurant.id, bundle.branding);

    for (final branch in bundle.branches) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_branches (id, restaurant_id, code, name, supported_order_types, is_active)
          VALUES (@id, @restaurant, @code, @name, @orderTypes, true)
          ON CONFLICT (id) DO UPDATE
            SET code = @code, name = @name, supported_order_types = @orderTypes, is_active = true
        '''),
        parameters: {
          'id': branch.id,
          'restaurant': restaurant.id,
          // The code is the invoice prefix and the local column is NOT NULL; a
          // branch the platform never gave one falls back to its id, which is
          // ugly on a receipt and unmistakably a configuration gap.
          'code': branch.code ?? 'BR${branch.id}',
          'name': branch.name,
          'orderTypes': branch.supportedOrderTypes,
        },
      );
    }
    if (bundle.branches.isNotEmpty) {
      await tx.execute(
        Sql.named(
          'UPDATE pos_branches SET is_active = false '
          'WHERE restaurant_id = @restaurant AND NOT (id = ANY(@keep))',
        ),
        parameters: {
          'restaurant': restaurant.id,
          'keep': [for (final b in bundle.branches) b.id],
        },
      );
    }

    await tx.execute(
      Sql.named('''
        INSERT INTO pos_terminals (id, restaurant_id, branch_id, name, sync_policy, claimed_at)
        VALUES (@id, @restaurant, @branch, @name, @policy, now())
        ON CONFLICT (id) DO UPDATE
          SET branch_id = @branch, name = @name, sync_policy = @policy,
              claimed_at = COALESCE(pos_terminals.claimed_at, now())
      '''),
      parameters: {
        'id': terminal.id,
        'restaurant': restaurant.id,
        'branch': terminal.branchId,
        'name': terminal.name,
        'policy': switch (terminal.syncPolicy) {
          'manual' => 'manual',
          _ => 'automatic',
        },
      },
    );
  }

  /// Who the receipt says sold the food, per branch (A3, CB-08).
  ///
  /// **The bug this closes.** Nothing in `data/cloud/` wrote this table, so
  /// every cloud till printed and filed with `ReceiptProfile(branchId: 0)` —
  /// the compiled-in blank — no matter what the restaurant had typed anywhere.
  /// The platform is the author now, and the bundle carries one row per active
  /// branch whether anybody authored it or not, so the till has something to
  /// print on day one.
  ///
  /// The same columns and the same `ON CONFLICT (branch_id)` upsert
  /// `PostgresReceiptProfileRepository.save` writes, with two differences, both
  /// deliberate:
  ///
  /// - **`revision` is the platform's**, not `revision + 1`. There the counter
  ///   is the till's own optimistic lock between an office and a counter; here
  ///   the platform owns it and the till is a reader. Bumping it locally would
  ///   put the two counters permanently out of step, and the number is what the
  ///   dashboard refuses a stale save on.
  /// - **No audit row and no `updated_by`.** The ledger answers "which person
  ///   at this till changed this", and the answer here is "nobody — a sync
  ///   did". Writing the seed as an audit event would bury the one entry that
  ///   matters (a manager editing the legal identity) under one per resync, and
  ///   the dashboard already has its own audit of the real edit.
  ///
  /// A profile for a branch the bundle did not carry is skipped rather than
  /// inserted: `branch_id` is a foreign key, and one bad row would roll back
  /// the whole seed — the catalog, the staff and the floor with it.
  Future<void> _seedReceiptProfiles(TxSession tx, BootstrapBundle bundle) async {
    // An empty list leaves every row as it is. A platform that predates A3
    // sends no `receipt_profiles` at all, and wiping the table on that would
    // send the till straight back to printing blanks — which is the bug. The
    // contract's "one row per active branch, authored or not" is what makes
    // "absent" and "empty" the same statement here.
    if (bundle.receiptProfiles.isEmpty) return;

    final restaurantId = bundle.restaurant!.id;
    final knownBranches = {for (final b in bundle.branches) b.id};

    for (final profile in bundle.receiptProfiles) {
      if (!knownBranches.contains(profile.branchId)) continue;

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_receipt_profiles
            (restaurant_id, branch_id, trade_name, registration_number,
             activity_code, branch_code, country, governate, region_city,
             street, building_number, postal_code, floor, room, landmark,
             additional_info, phone, header_note, footer_note, revision,
             updated_at)
          VALUES
            (@restaurant, @branch, @trade, @rin, @activity, @code, @country,
             @governate, @city, @street, @building, @postal, @floor, @room,
             @landmark, @extra, @phone, @header, @footer, @revision, now())
          ON CONFLICT (branch_id) DO UPDATE SET
            trade_name = excluded.trade_name,
            registration_number = excluded.registration_number,
            activity_code = excluded.activity_code,
            branch_code = excluded.branch_code,
            country = excluded.country,
            governate = excluded.governate,
            region_city = excluded.region_city,
            street = excluded.street,
            building_number = excluded.building_number,
            postal_code = excluded.postal_code,
            floor = excluded.floor,
            room = excluded.room,
            landmark = excluded.landmark,
            additional_info = excluded.additional_info,
            phone = excluded.phone,
            header_note = excluded.header_note,
            footer_note = excluded.footer_note,
            revision = excluded.revision,
            updated_at = now(),
            -- Cleared, not kept: the row no longer says what the manager who
            -- last touched it said, and leaving their id on it would name them
            -- as the author of the platform's text.
            updated_by = NULL
        '''),
        parameters: {
          'restaurant': restaurantId,
          'branch': profile.branchId,
          'trade': profile.tradeName.trim(),
          'rin': profile.registrationNumber.trim(),
          'activity': profile.activityCode.trim(),
          'code': profile.branchCode.trim(),
          'country': profile.address.country.trim(),
          'governate': profile.address.governate.trim(),
          'city': profile.address.regionCity.trim(),
          'street': profile.address.street.trim(),
          'building': profile.address.buildingNumber.trim(),
          // Every column is NOT NULL DEFAULT '' but the wire's two notes are
          // nullable, so the nulls are flattened here rather than at the read —
          // the same choice migration 19 made for the same reason.
          'postal': profile.address.postalCode?.trim() ?? '',
          'floor': profile.address.floor?.trim() ?? '',
          'room': profile.address.room?.trim() ?? '',
          'landmark': profile.address.landmark?.trim() ?? '',
          'extra': profile.address.additionalInformation?.trim() ?? '',
          'phone': profile.phone?.trim() ?? '',
          'header': profile.headerNote?.trim() ?? '',
          'footer': profile.footerNote?.trim() ?? '',
          'revision': profile.revision,
        },
      );
    }

    // Nothing is deleted or blanked for a branch the bundle stopped naming.
    // Inactive branches are omitted from both blocks, and `pos_branches` rows
    // are switched off rather than removed — so a profile whose branch went
    // away is unreachable already, and `ON DELETE CASCADE` takes it the day the
    // branch really goes. A DELETE here would need a grant the till has no
    // other use for.
  }

  /// The platform's tax rules, charges and tender types — the answer to "how
  /// much is owed" (POS-BE-013). Stored verbatim: a rule shape this build
  /// predates still round-trips, and the codec decides what the engine can
  /// currently express.
  Future<void> _seedMoney(TxSession tx, BootstrapBundle bundle) async {
    await tx.execute(
      Sql.named('''
        INSERT INTO pos_money_config (restaurant_id, payload, synced_at)
        VALUES (@restaurant, @payload, now())
        ON CONFLICT (restaurant_id) DO UPDATE
          SET payload = @payload, synced_at = now()
      '''),
      parameters: {
        'restaurant': bundle.restaurant!.id,
        'payload': jsonEncode(bundle.money),
      },
    );
  }

  /// The platform's financial accounts (XORD-015, stage 1).
  ///
  /// **Platform ids are the local primary keys**, like branches and products: no
  /// local row predates these, so there is nothing for an id to collide with
  /// (`_bumpSequences` keeps the serial above them).
  ///
  /// **An absent key changes nothing** — an older platform. A present key,
  /// even an empty one, is the platform's whole answer: anything it did not
  /// name is switched off.
  ///
  /// **Retired, never deleted**: stage 2 will name an account on a payment, and
  /// a DELETE would orphan it. There is no DELETE grant to do it with.
  ///
  /// An account tied to a branch this till does not hold is skipped, not
  /// stored as a shared one: widening "Maadi's drawer" into "everyone's" would
  /// be a silent change of what it means.
  Future<void> _seedFinancialAccounts(
    TxSession tx,
    BootstrapBundle bundle,
  ) async {
    if (!bundle.sendsFinancialAccounts) return;

    final restaurantId = bundle.restaurant!.id;
    final kept = <int>[];

    for (final account in bundle.financialAccounts) {
      final branchId = account.branchId;
      if (branchId != null) {
        final branch = await tx.execute(
          Sql.named(
            'SELECT 1 FROM pos_branches WHERE id = @b AND restaurant_id = @r',
          ),
          parameters: {'b': branchId, 'r': restaurantId},
        );
        if (branch.isEmpty) continue;
      }

      // `WHERE … restaurant_id` on the conflict: an id that already belongs to
      // another restaurant on this database is left alone rather than
      // overwritten. A branch server holds one restaurant, so this is a belt.
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_financial_accounts (id, restaurant_id, branch_id,
            name, kind, currency, reference_label, is_active, sort_order)
          VALUES (@id, @restaurant, @branch, @name, @kind, @currency,
            @reference, @active, @sort)
          ON CONFLICT (id) DO UPDATE
            SET branch_id = @branch, name = @name, kind = @kind,
                currency = @currency, reference_label = @reference,
                is_active = @active, sort_order = @sort
            WHERE pos_financial_accounts.restaurant_id = @restaurant
        '''),
        parameters: {
          'id': account.id,
          'restaurant': restaurantId,
          'branch': branchId,
          'name': account.name,
          'kind': account.kind.wire,
          'currency': account.currency,
          'reference': account.referenceLabel,
          'active': account.isActive,
          'sort': account.sortOrder,
        },
      );
      kept.add(account.id);
    }

    await tx.execute(
      Sql.named(
        'UPDATE pos_financial_accounts SET is_active = false '
        'WHERE restaurant_id = @restaurant AND NOT (id = ANY(@keep))',
      ),
      parameters: {'restaurant': restaurantId, 'keep': kept},
    );
  }

  /// The account each payment method pays into, per branch (XORD-015).
  ///
  /// Replaced wholesale: unlike the accounts they point at, a default carries
  /// no history (nothing is booked against it in stage 1), so there is nothing
  /// a DELETE could orphan. The platform names payment methods by ITS id; the
  /// local row is found through `platform_id`, which is why this runs after
  /// `_seedTenderTypes`.
  ///
  /// A row that cannot be placed — a payment method this till has no row for,
  /// a branch it does not hold, an account it did not store — is skipped. An
  /// absent key changes nothing, like the accounts.
  Future<void> _seedTenderAccountDefaults(
    TxSession tx,
    BootstrapBundle bundle,
  ) async {
    if (!bundle.sendsTenderAccountDefaults) return;

    final restaurantId = bundle.restaurant!.id;

    await tx.execute(
      Sql.named(
        'DELETE FROM pos_tender_account_defaults WHERE restaurant_id = @r',
      ),
      parameters: {'r': restaurantId},
    );

    for (final row in bundle.tenderAccountDefaults) {
      final tender = await tx.execute(
        Sql.named(
          'SELECT id FROM pos_tender_types '
          'WHERE restaurant_id = @r AND platform_id = @p',
        ),
        parameters: {'r': restaurantId, 'p': row.tenderTypeId},
      );
      if (tender.isEmpty) continue;

      final branchId = row.branchId;
      if (branchId != null) {
        final branch = await tx.execute(
          Sql.named(
            'SELECT 1 FROM pos_branches WHERE id = @b AND restaurant_id = @r',
          ),
          parameters: {'b': branchId, 'r': restaurantId},
        );
        if (branch.isEmpty) continue;
      }

      final account = await tx.execute(
        Sql.named(
          'SELECT 1 FROM pos_financial_accounts '
          'WHERE id = @a AND restaurant_id = @r',
        ),
        parameters: {'a': row.accountId, 'r': restaurantId},
      );
      if (account.isEmpty) continue;

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_tender_account_defaults (restaurant_id,
            tender_type_id, branch_id, branch_key, financial_account_id)
          VALUES (@r, @t, @b, @k, @a)
          ON CONFLICT (tender_type_id, branch_key) DO UPDATE
            SET financial_account_id = @a
        '''),
        parameters: {
          'r': restaurantId,
          't': tender.first[0]! as int,
          'b': branchId,
          'k': branchId ?? 0,
          'a': row.accountId,
        },
      );
    }
  }

  /// The platform's payment methods, as the rows the payment screen reads.
  ///
  /// `tender_types` also stays inside the verbatim payload above, where
  /// nothing reads it; the payment screen and the drain read these rows.
  ///
  /// **Keyed on `platform_id`, not on the primary key** — the one place this
  /// seeder does not keep a platform id as the local key. Migration 41 says
  /// why: the till's own rows 1–4 were here first, and a queued payment names
  /// its tender by local id, so overwriting them in place would re-mean those
  /// payments as whichever platform tender shared the number. Every column is
  /// rewritten on conflict, so no flag of an earlier row survives into the
  /// platform's.
  ///
  /// Retired, never deleted, like people: `pos_order_payments.tender_type_id`
  /// has no foreign key onto this table, so a DELETE would orphan a payment in
  /// silence where a retired row stays readable.
  Future<void> _seedTenderTypes(TxSession tx, BootstrapBundle bundle) async {
    final restaurantId = bundle.restaurant!.id;
    final tenders = bundle.tenderTypes;

    // An empty list leaves the table as it is. Retiring everything would drop
    // the payment screen onto its compiled-in fallback, and every payment
    // taken on that would be held by the drain anyway — no better than what
    // is here, and a crash would be worse than both. The platform guarantees
    // a POS restaurant is never delivered an empty list; this is the till not
    // relying on that.
    if (tenders.isEmpty) return;

    // Past the compiled-in ids before anything is inserted. Migration 41's
    // CHECK refuses a platform row at 1–4; this is what stops the serial from
    // offering one.
    await tx.execute(
      Sql.named(
        "SELECT setval(pg_get_serial_sequence('pos_tender_types', 'id'), "
        'GREATEST(COALESCE((SELECT MAX(id) FROM pos_tender_types), 0), '
        '@floor), true)',
      ),
      parameters: {'floor': TenderMethod.seededIdCeiling},
    );

    for (final tender in tenders) {
      final kind = tender.kind;
      // Only cash is notes in the drawer. An unknown kind counts as nothing,
      // which is the safe direction for a drawer and the same default
      // `Tender.countsAsCash` has.
      final cash = kind == PlatformTenderKind.cash;

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_tender_types (restaurant_id, platform_id, code,
            name_en, name_ar, kind, counts_as_cash, opens_drawer,
            requires_reference, refund_allowed, is_active, sort_order)
          VALUES (@restaurant, @platformId, @code, @name, NULL, @kind, @cash,
            @cash, false, true, @active, @sort)
          ON CONFLICT (restaurant_id, platform_id) DO UPDATE
            SET code = @code, name_en = @name, name_ar = NULL, kind = @kind,
                counts_as_cash = @cash, opens_drawer = @cash,
                requires_reference = false, refund_allowed = true,
                is_active = @active, sort_order = @sort
        '''),
        parameters: {
          'restaurant': restaurantId,
          'platformId': tender.id,
          // Unique by construction: platform_id is unique per restaurant, and
          // migration 41 keeps the prefix off every row the platform did not
          // send.
          'code': 'platform-${tender.id}',
          // One name comes over the wire. `name_ar` stays null rather than a
          // copy of it, so `displayName` falls back openly instead of
          // claiming a translation nobody wrote.
          'name': tender.name,
          'kind': (kind?.tillKind ?? TenderKind.other).wire,
          'cash': cash,
          // `requires_reference` is false for all of them. The platform has
          // nowhere to say a tender wants one, and nothing at the counter reads
          // the flag today — so setting it here would be a rule the owner can
          // neither see on the dashboard nor switch off there, waiting for the
          // day the payment screen starts enforcing it. `refund_allowed` is
          // true for the matching reason: refusing a refund the owner never
          // refused is the worse error at a counter.
          'active': tender.isActive,
          'sort': tender.sortOrder,
        },
      );
    }

    // Everything the bundle did not name is switched off — the till's own four
    // included. On a cloud till those were never the platform's, and a payment
    // taken on one is exactly what the drain now refuses to send.
    await tx.execute(
      Sql.named(
        'UPDATE pos_tender_types SET is_active = false '
        'WHERE restaurant_id = @restaurant '
        '  AND (platform_id IS NULL OR NOT (platform_id = ANY(@keep)))',
      ),
      parameters: {
        'restaurant': restaurantId,
        'keep': [for (final t in tenders) t.id],
      },
    );
  }

  /// The customer directory (POS-BE-014).
  ///
  /// **Upserted, never cleared.** Every other platform-authored collection is
  /// DELETEd and re-inserted, because the platform is the sole author and the
  /// bundle is the whole truth. Customers are the one collection the till also
  /// WRITES — a cashier creates one at the counter during an outage — so
  /// wiping the table on every bootstrap would delete people this till has not
  /// managed to upload yet. An empty list is therefore left alone entirely.
  ///
  /// Matched on the PHONE, not on the platform id, because a customer created
  /// here and one sent down may be the same person: the till made a local row
  /// with no `platform_id`, and the bundle now brings the id the platform gave
  /// them. Keying on the number is what merges those two into one row instead
  /// of leaving a duplicate the cashier can see.
  Future<void> _seedCustomers(TxSession tx, BootstrapBundle bundle) async {
    if (bundle.customers.isEmpty) return;
    final restaurantId = bundle.restaurant!.id;

    for (final customer in bundle.customers) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_customers (restaurant_id, client_transaction_id,
                                     platform_id, name, phone, email, address)
          VALUES (@restaurant, gen_random_uuid(), @platform, @name, @phone,
                  @email, @address)
          ON CONFLICT (restaurant_id, phone) DO UPDATE
            SET platform_id = @platform,
                name        = @name,
                email       = COALESCE(@email, pos_customers.email),
                address     = COALESCE(@address, pos_customers.address),
                updated_at  = now()
        '''),
        parameters: {
          'restaurant': restaurantId,
          'platform': customer.id,
          'name': customer.name,
          'phone': PosCustomer.normalisePhone(customer.phone),
          'email': customer.email,
          'address': customer.address,
        },
      );
    }
  }

  Future<void> _seedStaff(TxSession tx, BootstrapBundle bundle) async {
    final restaurantId = bundle.restaurant!.id;

    for (final member in bundle.staff) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_staff (id, restaurant_id, name, username, pin_salt, pin_hash, capabilities, is_active)
          VALUES (@id, @restaurant, @name, @username, @salt, @hash, @capabilities, @active)
          ON CONFLICT (id) DO UPDATE
            SET name = @name, username = @username,
                pin_salt = @salt, pin_hash = @hash,
                capabilities = @capabilities, is_active = @active
        '''),
        parameters: {
          'id': member.id,
          'restaurant': restaurantId,
          'name': member.name,
          'username': member.username,
          // Empty strings, not nulls: the columns are NOT NULL, and an empty
          // verifier can never match any PIN — "no PIN set" means "cannot sign
          // in offline", exactly as the contract states.
          'salt': member.pin?.salt ?? '',
          'hash': member.pin?.hash ?? '',
          // The platform speaks `pos.*` tenant-capability strings; the local
          // rows speak the till's canonical names. One translation, on the way
          // in, through the same map every other reader uses.
          'capabilities': PosCapability.canonicalAll(
            member.capabilities.toSet(),
          ).toList()..sort(),
          'active': member.isActive,
        },
      );
    }

    // Departed staff are switched off, never deleted — their shifts reference
    // them. Platform-authored rows are authoritative for who works here.
    if (bundle.staff.isNotEmpty) {
      await tx.execute(
        Sql.named(
          'UPDATE pos_staff SET is_active = false '
          'WHERE restaurant_id = @restaurant AND NOT (id = ANY(@keep))',
        ),
        parameters: {
          'restaurant': restaurantId,
          'keep': [for (final s in bundle.staff) s.id],
        },
      );
    }
  }

  Future<void> _seedCatalog(TxSession tx, BootstrapBundle bundle) async {
    final restaurantId = bundle.restaurant!.id;

    // Children before parents; the platform's catalog replaces the local one
    // whole. Order lines snapshot name and price at sale time, so history
    // survives the wipe by construction.
    await tx.execute(
      Sql.named(
        'DELETE FROM pos_product_modifier_groups WHERE product_id IN '
        '(SELECT id FROM pos_products WHERE restaurant_id = @restaurant)',
      ),
      parameters: {'restaurant': restaurantId},
    );
    await tx.execute(
      Sql.named(
        'DELETE FROM pos_modifiers WHERE group_id IN '
        '(SELECT id FROM pos_modifier_groups WHERE restaurant_id = @restaurant)',
      ),
      parameters: {'restaurant': restaurantId},
    );
    // `pos_modifier_group_categories` goes with the groups and the categories
    // — it cascades from both (migration 45). Deliberately not deleted by
    // name: a cascade needs no grant, and a cloud till whose grants predate
    // the table would be refused a DELETE on it and lose the whole seed.
    for (final table in [
      'pos_products',
      'pos_modifier_groups',
      'pos_categories',
    ]) {
      await tx.execute(
        Sql.named('DELETE FROM $table WHERE restaurant_id = @restaurant'),
        parameters: {'restaurant': restaurantId},
      );
    }

    for (final category in bundle.categories) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_categories (id, restaurant_id, name_en, name_ar, slug, sort_order, is_active)
          VALUES (@id, @restaurant, @nameEn, @nameAr, @slug, @sort, @active)
        '''),
        parameters: {
          'id': category.id,
          'restaurant': restaurantId,
          'nameEn': category.nameEn,
          'nameAr': category.nameAr,
          'slug': category.slug,
          'sort': category.sortOrder,
          'active': category.isActive,
        },
      );
    }

    for (final group in bundle.optionGroups) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_modifier_groups (id, restaurant_id, name_en, name_ar, is_required, max_select, is_variant, sort_order)
          VALUES (@id, @restaurant, @nameEn, @nameAr, @required, @maxSelect, @variant, @sort)
        '''),
        parameters: {
          'id': group.id,
          'restaurant': restaurantId,
          'nameEn': group.nameEn,
          'nameAr': group.nameAr,
          'required': group.isRequired,
          'maxSelect': group.maxSelect < 1 ? 1 : group.maxSelect,
          'variant': group.isVariant,
          'sort': group.sortOrder,
        },
      );
      for (final option in group.options) {
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_modifiers (id, group_id, name_en, name_ar, price_delta_minor, is_available, sort_order)
            VALUES (@id, @group, @nameEn, @nameAr, @delta, @available, @sort)
          '''),
          parameters: {
            'id': option.id,
            'group': group.id,
            'nameEn': option.nameEn,
            'nameAr': option.nameAr,
            'delta': option.priceDeltaMinor,
            'available': option.isAvailable,
            'sort': option.sortOrder,
          },
        );
      }
    }

    final knownCategories = {for (final c in bundle.categories) c.id};
    final knownGroups = {for (final g in bundle.optionGroups) g.id};
    for (final product in bundle.products) {
      // A product naming a category the bundle did not carry would trip the FK
      // and roll back the whole seed. Dropping the one product keeps the other
      // two hundred sellable, which is the trade a till wants.
      if (!knownCategories.contains(product.categoryId)) continue;

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_products (id, restaurant_id, category_id, name_en, name_ar,
                                    price_minor, discounted_price_minor, sku, barcode,
                                    is_available, sort_order)
          VALUES (@id, @restaurant, @category, @nameEn, @nameAr,
                  @price, @discounted, @sku, @barcode, @available, @sort)
        '''),
        parameters: {
          'id': product.id,
          'restaurant': restaurantId,
          'category': product.categoryId,
          'nameEn': product.nameEn,
          'nameAr': product.nameAr,
          'price': product.priceMinor,
          'discounted': product.discountedPriceMinor,
          'sku': product.sku,
          'barcode': product.barcode,
          'available': product.isAvailable,
          'sort': product.sortOrder,
        },
      );

      var position = 0;
      for (final groupId in product.optionGroupIds) {
        if (!knownGroups.contains(groupId)) continue;
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_product_modifier_groups (product_id, group_id, sort_order)
            VALUES (@product, @group, @sort)
            ON CONFLICT (product_id, group_id) DO NOTHING
          '''),
          parameters: {
            'product': product.id,
            'group': groupId,
            'sort': position++,
          },
        );
      }
    }
  }

  Future<void> _seedTables(TxSession tx, BootstrapBundle bundle) async {
    final restaurantId = bundle.restaurant!.id;
    final knownBranches = {for (final b in bundle.branches) b.id};

    await tx.execute(
      Sql.named(
        'DELETE FROM pos_dining_tables WHERE restaurant_id = @restaurant',
      ),
      parameters: {'restaurant': restaurantId},
    );
    for (final table in bundle.tables) {
      if (!knownBranches.contains(table.branchId)) continue;
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_dining_tables (id, restaurant_id, branch_id, label, seats, area_name, is_active)
          VALUES (@id, @restaurant, @branch, @label, @seats, @area, @active)
        '''),
        parameters: {
          'id': table.id,
          'restaurant': restaurantId,
          'branch': table.branchId,
          'label': table.label,
          'seats': table.seats,
          'area': table.areaName,
          'active': table.isActive,
        },
      );
    }
  }

  /// Push every serial past the platform ids just written, so a locally
  /// authored row can never be assigned an id the next resync will also use.
  Future<void> _bumpSequences(TxSession tx) async {
    const tables = [
      'pos_restaurants',
      'pos_branches',
      'pos_staff',
      'pos_categories',
      'pos_modifier_groups',
      'pos_modifiers',
      'pos_products',
      'pos_dining_tables',
      'pos_financial_accounts',
    ];
    for (final table in tables) {
      await tx.execute(
        "SELECT setval(pg_get_serial_sequence('$table', 'id'), "
        'GREATEST(COALESCE((SELECT MAX(id) FROM $table), 0), 1), true)',
      );
    }
  }
}
