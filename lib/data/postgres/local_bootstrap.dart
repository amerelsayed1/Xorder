import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/content_languages.dart';
import '../../domain/models/order_type_config.dart';
import '../../domain/models/tender_method.dart';
import '../../core/security/pin_hash.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/reason_code.dart';
import 'migrations.dart';
import 'pos_database.dart';
import 'pos_tls.dart';

/// What [LocalBootstrap.seedOwner] did, or why it did not.
///
/// Data, not an exception — the same reasoning as `AdminRefusal`. Pointing an
/// installer at a business that already has an owner is an ordinary thing to
/// do — a second till, a reinstall — and both callers have to put the answer
/// into words, the wizard in two languages. Left to migration 42's trigger, the
/// CLI died on a driver error and the wizard showed that error, in English.
sealed class OwnerSeed {
  const OwnerSeed();
}

/// The account was created.
class OwnerCreated extends OwnerSeed {
  const OwnerCreated();
}

/// The username was already there and was left alone — PIN included.
class OwnerAlreadyHere extends OwnerSeed {
  const OwnerAlreadyHere();
}

/// Somebody else is this business's active owner, so nobody was created.
///
/// Carries their username as well as their name, because the first way
/// forward is to seed under that username — which is signing in as them. The
/// other is to disable them first, which is the handover migration 42 allows.
class AnotherOwnerActive extends OwnerSeed {
  const AnotherOwnerActive({required this.name, required this.username});

  final String name;
  final String username;
}

/// PostgreSQL has no account for the till, and the administrator credential
/// may not create one.
///
/// Not a [PosDbException], although a driver error is what it came from: by
/// the time it reaches the wizard, `permissionDenied` is indistinguishable
/// from a refused GRANT on a table, and the two need opposite sentences — one
/// is about a role that does not exist, the other about one that does. Carries
/// both names because the remedy names both: use an administrator that may
/// create roles, or create this one by hand.
class TillRoleRefused implements Exception {
  const TillRoleRefused({required this.role, required this.admin});

  final String role;
  final String admin;

  @override
  String toString() => 'TillRoleRefused: "$admin" may not create "$role".';
}

/// Preparing an empty PostgreSQL for a till, in one place.
///
/// This used to live only in `bin/pos_migrate.dart`, which meant an offline
/// install began at a command line — on a machine in a business, run by
/// whoever unboxed it. The setup wizard now offers the same thing, and both
/// call *this*, because two implementations of "what grants does a till need"
/// is two answers to a question that must only ever have one.
///
/// **The credential used here is not the credential the till keeps.** Creating
/// a database and applying DDL needs an owner or superuser; selling needs
/// `pos_till`, which is granted the least it can work with and no DDL at all.
/// The admin credential passes through this class and is not persisted by it.
/// The setup wizard does keep it, in the OS store, for Admin Mode; see
/// `adminDbSecretStoreProvider`.
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
    String name, {
    String? owner,
  }) async {
    if (!_isPlainIdentifier(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'A database name must be letters, digits and underscores — it is an '
            'identifier, so it cannot be a bind parameter and will be quoted '
            'into the statement.',
      );
    }

    final connection = await _openMaintenance(admin, adminPassword);

    try {
      final existing = await connection.execute(
        Sql.named('SELECT 1 FROM pg_database WHERE datname = @name'),
        parameters: {'name': name},
      );
      if (existing.isNotEmpty) return false;

      // Owned by the administrator role rather than whoever ran this, when
      // asked: a restore drops and recreates every table, and only an owner
      // may — so a database built by `postgres` could never be restored by
      // the account the back office signs in as.
      await connection.execute(
        owner == null
            ? 'CREATE DATABASE "$name"'
            : 'CREATE DATABASE "$name" OWNER "${_identifier(owner)}"',
      );
      return true;
    } on PosDbException {
      rethrow;
    } on Object catch (error) {
      throw PosDbException(PosDbFailure.classify(error), error);
    } finally {
      await connection.close();
    }
  }

  /// The maintenance connection every account-level step here opens, with the
  /// driver's errors translated on the way out.
  ///
  /// **The translation is the point.** These steps do not go through
  /// [PosDatabase], which is the only other place a `postgres` exception is
  /// turned into a [PosDbException] — so a failure here used to leave this
  /// file as a raw `ServerException` and land in the setup wizard's error bar
  /// as `Severity.fatal 28000: role "pos_admin" does not exist`: a driver's
  /// words, in English, in front of an installer reading Arabic. It is the
  /// FIRST step of the build, so it was also the likeliest thing to fail.
  static Future<Connection> _openMaintenance(
    DeploymentConfig admin,
    String adminPassword,
  ) async {
    try {
      return await Connection.open(
        Endpoint(
          host: admin.databaseHost,
          port: admin.databasePort,
          database: 'postgres',
          username: admin.databaseUser,
          password: adminPassword,
        ),
        // The till's own transport rule, not one of this file's. This used
        // to be `require` off loopback — which in the postgres package
        // accepts any certificate at all, so the administrator's password
        // for building the database was the one credential sent to whoever
        // answered. A pinned or verified certificate, or nothing.
        settings: ConnectionSettings(
          sslMode: PosTlsSettings.sslModeFor(admin.lanTls),
          securityContext: PosTlsSettings.securityContextFor(admin.lanTls),
        ),
      );
    } on Object catch (error) {
      throw PosDbException(PosDbFailure.classify(error), error);
    }
  }

  /// The three accounts an install needs, created where missing.
  ///
  /// **Created, never changed.** A role that already exists keeps its
  /// password: the till and the backup have it stored, and an upgrade that
  /// quietly reset it would stop both on the day after the upgrade.
  ///
  /// Needs a superuser, or a role with CREATEROLE — `pos_admin` deliberately
  /// has neither, which is why this is the installer's step and not the
  /// wizard's.
  ///
  /// @return the roles this call created.
  static Future<List<String>> createRoles(
    DeploymentConfig superuser,
    String superuserPassword, {
    required Map<InstallRole, String> passwords,
    Map<InstallRole, String> names = InstallRole.defaultNames,
  }) async {
    final connection = await _openMaintenance(superuser, superuserPassword);

    final created = <String>[];
    try {
      for (final role in InstallRole.values) {
        final name = names[role]!;
        final password = passwords[role];
        if (await _createRole(connection, role, name, password)) {
          created.add(name);
        }
      }
    } on PosDbException {
      rethrow;
    } on ArgumentError {
      rethrow;
    } on Object catch (error) {
      throw PosDbException(PosDbFailure.classify(error), error);
    } finally {
      await connection.close();
    }
    return created;
  }

  /// The till's own login, created only where PostgreSQL does not have it.
  ///
  /// **Not part of [createRoles], on purpose.** That one is the installer's
  /// step and makes all three accounts as a superuser. This is the wizard's,
  /// and it exists because the wizard's own help text invites the other kind
  /// of machine: a PostgreSQL somebody installed by hand, where `pos_admin`
  /// was never created and the operator is told to type `postgres` instead.
  /// On that machine `pos_till` is missing too — so the build created the
  /// database, applied every migration, and then died on
  /// `GRANT … TO "pos_till"` with a role nobody had made. The till's
  /// password is on the same screen; this uses it.
  ///
  /// **Created, never changed**, for the same reason [createRoles] says so:
  /// a role that is already there keeps the password the till and the backup
  /// already have stored.
  ///
  /// Returns true when it created one. Throws [PosDbException] with
  /// [PosDbFailure.permissionDenied] when the administrator credential may
  /// not create roles — which is the ordinary state of a real `pos_admin`,
  /// and on that machine the role is already there and this never runs.
  static Future<bool> ensureTillRole(
    DeploymentConfig admin,
    String adminPassword, {
    required String name,
    required String password,
  }) async {
    final connection = await _openMaintenance(admin, adminPassword);
    try {
      return await _createRole(connection, InstallRole.till, name, password);
    } on PosDbException catch (error) {
      // `permission denied to create role`, 42501 — the ordinary answer from
      // a real `pos_admin`, which is deliberately given neither SUPERUSER nor
      // CREATEROLE. On that machine the installer made this role already and
      // this line is never reached; anywhere else it is a different remedy
      // from every other refused privilege, so it leaves here as its own type.
      if (error.failure == PosDbFailure.permissionDenied) {
        throw TillRoleRefused(role: name, admin: admin.databaseUser);
      }
      rethrow;
    } on ArgumentError {
      rethrow;
    } on Object catch (error) {
      throw PosDbException(PosDbFailure.classify(error), error);
    } finally {
      await connection.close();
    }
  }

  /// One role, on an open connection: look first, and leave an existing one
  /// exactly as it is. Returns true when it created one.
  static Future<bool> _createRole(
    Connection connection,
    InstallRole role,
    String name,
    String? password,
  ) async {
    final existing = await connection.execute(
      Sql.named('SELECT 1 FROM pg_roles WHERE rolname = @name'),
      parameters: {'name': name},
    );
    if (existing.isNotEmpty) return false;

    if (password == null || password.isEmpty) {
      throw ArgumentError.value(
        role.name,
        'passwords',
        'No password for the $name role, and it does not exist yet.',
      );
    }
    for (final statement in roleStatements(role, name, password)) {
      await connection.execute(statement);
    }
    return true;
  }

  /// What creating one install role runs. Pure, so a test can read it.
  ///
  /// The password is a literal, not a bind parameter — `CREATE ROLE` takes
  /// none — so it is quoted by doubling, the one escape a string literal
  /// needs with `standard_conforming_strings` on, which it is from 9.1.
  static List<String> roleStatements(
    InstallRole role,
    String name,
    String password,
  ) {
    final quoted = "'${password.replaceAll("'", "''")}'";
    final ident = _identifier(name);
    return switch (role) {
      // Creates databases — the wizard's "Build the database" connects as it —
      // and owns this one. Nothing else: no superuser, no CREATEROLE.
      InstallRole.admin => [
        'CREATE ROLE "$ident" LOGIN CREATEDB PASSWORD $quoted',
      ],
      // Granted table by table by [tillGrants], after the migrations.
      InstallRole.till => ['CREATE ROLE "$ident" LOGIN PASSWORD $quoted'],
      // Reads every row and writes none: see `BackupService.reader`.
      InstallRole.backup => [
        'CREATE ROLE "$ident" LOGIN PASSWORD $quoted',
        'GRANT pg_read_all_data TO "$ident"',
      ],
    };
  }

  static String _identifier(String name) {
    if (!_isPlainIdentifier(name)) {
      throw ArgumentError.value(name, 'name', 'Not a plain identifier.');
    }
    return name;
  }

  /// Apply every pending migration. Returns the versions this call applied.
  Future<List<int>> migrate(DeploymentConfig admin) =>
      PosMigrator(database).migrate(admin);

  /// Bring an installed database up to this build: [migrate], then the same
  /// grants the wizard gave, because a table a new migration created has none.
  ///
  /// The grants are re-applied only when something was migrated. They are all
  /// GRANTs, so repeating them is harmless, but there is no reason to write to
  /// the catalogue on every visit to the back office.
  Future<List<int>> upgrade(
    DeploymentConfig admin, {
    required DeploymentConfig till,
  }) async {
    final applied = await migrate(admin);
    if (applied.isNotEmpty) {
      await applyGrants(admin, [
        ...tillGrants(
          database: till.databaseName,
          role: till.databaseUser,
          cloudSeeding: till.mode == DeploymentMode.cloud,
        ),
        ...administrativeGrants(role: till.adminDatabaseUser),
      ]);
    }
    return applied;
  }

  /// The business row, matched on slug so a re-run adopts rather than
  /// duplicates.
  ///
  /// [contentLanguages] is the language the menu is written in (XORD-035): the
  /// wizard's language for a new row, so names are asked for in one language
  /// from the first form. Null leaves the column's own default. It is written
  /// only when the row is created - a re-run that adopts a row never overwrites
  /// what a manager chose since.
  Future<int> seedBusiness(
    DeploymentConfig admin, {
    required String slug,
    required String name,
    ContentLanguages? contentLanguages,
  }) async {
    final rows = await database.query(
      admin,
      'INSERT INTO pos_businesses (slug, name, content_languages) '
      "VALUES (@slug, @name, COALESCE(@languages::text, 'both')) "
      // Touch the conflicting column and nothing else: this is how the row's
      // id comes back without any of its content being overwritten.
      'ON CONFLICT (slug) DO UPDATE SET slug = EXCLUDED.slug RETURNING id',
      parameters: {
        'slug': slug,
        'name': name,
        'languages': contentLanguages?.wire,
      },
    );

    return rows.first[0]! as int;
  }

  /// One branch. Its code is the invoice prefix — `MAIN-2026-000042`.
  Future<int> seedBranch(
    DeploymentConfig admin, {
    required int businessId,
    required String name,
    required String code,
  }) async {
    final rows = await database.query(
      admin,
      'INSERT INTO pos_branches (business_id, code, name, supported_order_types) '
      "VALUES (@business, @code, @name, ARRAY['dine_in','takeaway','delivery']) "
      'ON CONFLICT (business_id, code) DO UPDATE SET code = EXCLUDED.code '
      'RETURNING id',
      parameters: {'business': businessId, 'code': code, 'name': name},
    );

    return rows.first[0]! as int;
  }

  /// The four system roles, from [SystemRoles.seeded].
  ///
  /// Re-running never resets a business's edited permissions: the upsert
  /// touches `code` and leaves `capabilities` alone.
  ///
  /// @return role code → id, and how many were newly created.
  Future<({Map<String, int> ids, int created})> seedSystemRoles(
    DeploymentConfig admin,
    int businessId,
  ) async {
    final ids = <String, int>{};
    var created = 0;

    for (final entry in SystemRoles.seeded.entries) {
      final rows = await database.query(
        admin,
        'INSERT INTO pos_roles (business_id, code, name_en, name_ar, capabilities, is_system) '
        'VALUES (@business, @code, @nameEn, @nameAr, @capabilities, true) '
        'ON CONFLICT (business_id, code) DO UPDATE SET code = EXCLUDED.code '
        'RETURNING id, (xmax = 0) AS inserted',
        parameters: {
          'business': businessId,
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
  /// Migration 9 seeds every business that existed when it ran. This is for
  /// the ones created afterwards — by `--seed`, or by the wizard building a
  /// database on a machine in a business — because a `CROSS JOIN` over
  /// `pos_businesses` inside a migration can only ever see the past.
  ///
  /// Re-running never resets an edited list: the upsert touches `code` and
  /// leaves the names, the sort order and `is_active` alone. A business that
  /// renamed "Manager comp" or retired "Training" keeps its decision.
  ///
  /// @return how many rows were newly created.
  Future<int> seedReasonCodes(DeploymentConfig admin, int businessId) async {
    var created = 0;

    for (final scope in SystemReasons.seededScopes) {
      // Per scope, not one list for all of them: "Staff meal" is not a reason
      // anybody puts money into a till.
      final reasons = SystemReasons.seededFor(scope);
      for (var i = 0; i < reasons.length; i++) {
        final reason = reasons[i];
        final rows = await database.query(
          admin,
          'INSERT INTO pos_reason_codes (business_id, scope, code, name_en, '
          '  name_ar, requires_note, sort_order) '
          'VALUES (@business, @scope, @code, @nameEn, @nameAr, @note, @sort) '
          'ON CONFLICT (business_id, scope, code) DO UPDATE SET code = EXCLUDED.code '
          'RETURNING (xmax = 0) AS inserted',
          parameters: {
            'business': businessId,
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

  /// The rate this business charges, named.
  ///
  /// Migration 16 backfills every business that existed when it ran; this is
  /// the other half — a business created afterwards needs one too, or its
  /// products can never be classified and an ETA filing has an unnamed rate on
  /// it.
  ///
  /// Returns true when it created one. Idempotent: a business that already
  /// has a default keeps whatever it configured, because a re-run of setup must
  /// not reset an accountant's decision.
  /// The four payment methods a new business starts with (§40).
  ///
  /// **Migration 23 cannot do this for a business that does not exist yet.**
  /// It seeds every business present when it runs, and a fresh install runs
  /// the migrations first and creates the business second — so without this
  /// the new business has none, the till falls back to the compiled-in four,
  /// and Management shows an empty list beside a payment screen offering four
  /// methods. Found by installing one.
  ///
  /// Idempotent on the code, so re-running setup does not undo a rename.
  Future<int> seedTenderTypes(
    DeploymentConfig admin,
    int businessId,
  ) async {
    var created = 0;
    for (final method in TenderMethod.seeded) {
      final rows = await database.query(
        admin,
        'INSERT INTO pos_tender_types (business_id, code, name_en, name_ar, '
        '  kind, counts_as_cash, opens_drawer, requires_reference, sort_order) '
        'VALUES (@r, @code, @nameEn, @nameAr, @kind, @cash, @drawer, '
        '        @reference, @sort) '
        'ON CONFLICT (business_id, code) DO NOTHING RETURNING id',
        parameters: {
          'r': businessId,
          'code': method.code,
          'nameEn': method.nameEn,
          'nameAr': method.nameAr,
          'kind': method.kind.wire,
          'cash': method.countsAsCash,
          'drawer': method.opensDrawer,
          'reference': method.requiresReference,
          'sort': method.sortOrder,
        },
      );
      if (rows.isNotEmpty) created++;
    }
    return created;
  }

  /// What each kind of order requires (§31), for a business created after
  /// migration 25 ran. Same split, same reason, as [seedTenderTypes].
  Future<int> seedOrderTypes(DeploymentConfig admin, int businessId) async {
    var created = 0;
    for (final config in OrderTypeConfig.seeded) {
      final rows = await database.query(
        admin,
        'INSERT INTO pos_order_types (business_id, code, name_en, name_ar, '
        '  requires_table, requires_customer, requires_address, sort_order) '
        'VALUES (@r, @code, @nameEn, @nameAr, @tbl, @cust, @addr, @sort) '
        'ON CONFLICT (business_id, code) DO NOTHING RETURNING id',
        parameters: {
          'r': businessId,
          'code': config.type.wire,
          'nameEn': config.nameEn,
          'nameAr': config.nameAr,
          'tbl': config.requiresTable,
          'cust': config.requiresCustomer,
          'addr': config.requiresAddress,
          'sort': config.sortOrder,
        },
      );
      if (rows.isNotEmpty) created++;
    }
    return created;
  }

  Future<bool> seedTaxGroup(
    DeploymentConfig admin,
    int businessId, {
    int rateBp = 1400,
  }) async {
    final rows = await database.query(
      admin,
      'INSERT INTO pos_tax_groups (business_id, name_en, name_ar, rate_bp, '
      "  is_default) VALUES (@business, 'VAT', @nameAr, @rate, true) "
      'ON CONFLICT DO NOTHING RETURNING id',
      parameters: {
        'business': businessId,
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
  /// **It asks before it inserts** whether somebody else is the active owner,
  /// and answers [AnotherOwnerActive] rather than letting migration 42's
  /// trigger throw. Catching the trigger's exception instead would have meant
  /// reading the owner's name back out of an English sentence under SQLSTATE
  /// P0001, which every RAISE in the schema shares. The question is asked the
  /// way the trigger asks it — the owner role's row locked `FOR NO KEY UPDATE`,
  /// in the same transaction as the INSERT — so two installers pointed at one
  /// business queue rather than each counting nobody. The trigger still
  /// holds the rule; this is what lets an installer say it.
  ///
  /// A row with the *same* username is not another owner: that is the re-run,
  /// excluded here for the reason the trigger excludes it.
  Future<OwnerSeed> seedOwner(
    DeploymentConfig admin, {
    required int businessId,
    required int branchId,
    required int roleId,
    required String name,
    required String username,
    required String pin,
  }) async {
    // Hashed before the transaction, not inside it: PBKDF2 is slow on purpose,
    // and the lock below should be held for two statements, not for that.
    final salt = PinHash.newSalt();
    final hash = await PinHash.hash(pin, salt);

    return database.runTx<OwnerSeed>(admin, (tx) async {
      await tx.execute(
        Sql.named('SELECT 1 FROM pos_roles WHERE id = @role FOR NO KEY UPDATE'),
        parameters: {'role': roleId},
      );
      final incumbent = await tx.execute(
        Sql.named(
          'SELECT s.name, s.username FROM pos_users s '
          'JOIN pos_roles r ON r.id = s.role_id '
          'WHERE s.business_id = @business AND r.code = @owner '
          '  AND s.is_active AND s.username <> @username '
          'ORDER BY s.id LIMIT 1',
        ),
        parameters: {
          'business': businessId,
          'owner': SystemRoles.ownerCode,
          'username': username,
        },
      );
      if (incumbent.isNotEmpty) {
        return AnotherOwnerActive(
          name: incumbent.first[0]! as String,
          username: incumbent.first[1]! as String,
        );
      }

      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_users (business_id, branch_id, name, username, '
          'pin_salt, pin_hash, role_id, capabilities) '
          // No direct grants: the ROLE carries the permissions, so changing
          // what an owner may do is one edit in one place.
          "VALUES (@business, @branch, @name, @username, @salt, @hash, @role, '{}') "
          'ON CONFLICT (business_id, username) DO NOTHING RETURNING id',
        ),
        parameters: {
          'business': businessId,
          'branch': branchId,
          'name': name,
          'username': username,
          'salt': salt,
          'hash': hash,
          'role': roleId,
        },
      );
      return rows.isEmpty ? const OwnerAlreadyHere() : const OwnerCreated();
    });
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
        'void_reason_id, void_note, business_day_id, server_invoice_number) '
        'ON pos_orders TO "$role"',
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
    // What the sale took off the shelf. The orders repository writes the
    // ledger row and the position beside it in the sale's own transaction, so
    // a stocked product sold on the till credential needs both — and had
    // neither, which `grants_cover_usage_test` caught after the stock work
    // landed. INSERT on the ledger only: a movement is a record, and an edit
    // to one is another movement. UPDATE on the position, because it is the
    // cache the same transaction maintains. Receipts, waste and counts are
    // back-office acts and stay with [administrativeGrants].
    'GRANT SELECT, INSERT ON pos_stock_movements TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_stock_movements_id_seq TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_stock_levels TO "$role"',
    // The discounts the business offers. Read-only for the till, for the
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
    // What the business has configured. Read-only for the till: a cashier
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
    // What a purchase line and a stock row are labelled in.
    'GRANT SELECT ON pos_units TO "$role"',
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
    // Paper the printer would not take. The till writes a job when a print
    // fails and updates it as it retries, so this needs UPDATE — column-scoped
    // like an order's, and pointedly **not** on `payload`: the bytes are what
    // the customer was promised, and a job whose contents could be rewritten
    // between the sale and the paper is a receipt for a different sale.
    'GRANT SELECT, INSERT ON pos_print_jobs TO "$role"',
    'GRANT UPDATE (status, attempts, last_attempt_at, last_error, printed_at) '
        'ON pos_print_jobs TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_print_jobs_id_seq TO "$role"',
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
    // The payment methods this business takes (§40), and what it adds on top
    // of the food (§38). Read-only, like the menu and for the same reason: a
    // cashier takes a method and charges what the business set, they do not
    // invent either.
    'GRANT SELECT ON pos_tender_types, pos_service_charges, '
        'pos_order_types TO "$role"',
    // Where money goes (XORD-015, stage 1): the accounts and which one each
    // payment method pays into. Read-only here, for the same reason as the
    // payment methods themselves. Nothing is posted to an account yet.
    'GRANT SELECT ON pos_financial_accounts, pos_tender_account_defaults '
        'TO "$role"',
    // The tax breakdown a filing needs, written with the sale (§17, ETA).
    // INSERT and SELECT, never UPDATE: the rates a customer was charged are
    // part of the record of what they paid.
    'GRANT SELECT, INSERT ON pos_order_taxes TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_order_taxes_id_seq TO "$role"',
    // Who the food is for (POS-BE-014). The till WRITES this one, unlike the
    // rest of the business's data: a cashier taking a phone order creates a
    // customer at the counter, with no connection and no back office to do it
    // in. UPDATE as well, because the platform's id lands on the row when the
    // drain delivers it, and because a regular who corrects their address
    // should not become a second person.
    'GRANT SELECT, INSERT, UPDATE ON pos_customers TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_customers_id_seq TO "$role"',
    // What a combo line was actually made of. Same discipline: the kitchen
    // made these, so they are a record rather than a working figure.
    'GRANT SELECT, INSERT ON pos_order_line_items TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_order_line_items_id_seq TO "$role"',
    // The business's own data. Read-only for the till: a till displays
    // the menu, it does not edit it. Changing what the business sells is
    // a back-office act — see [administrativeGrants].
    'GRANT SELECT ON pos_businesses, pos_branches, pos_users, pos_categories, '
        'pos_products, pos_modifier_groups, pos_modifiers, '
        'pos_product_modifier_groups, pos_modifier_group_categories, '
        'pos_dining_tables TO "$role"',
    // Read by every till on every sign-in: the permission gate needs to
    // know what the person who just entered a PIN may do.
    'GRANT SELECT ON pos_roles TO "$role"',
    // The rest of that answer — the extra roles, the per-person exceptions and
    // the ceilings. SELECT only: a till reads what somebody may do and never
    // writes it, which is the whole reason the back office needs a separate
    // credential.
    'GRANT SELECT ON pos_user_roles, pos_user_permission_overrides, '
        'pos_permission_limits TO "$role"',
    // Claiming a pairing code stamps `claimed_at`, and an installer with
    // no dashboard registers the terminal from the wizard.
    'GRANT SELECT, INSERT, UPDATE ON pos_terminals TO "$role"',
    // The licence the main device shares with its children (migration 43). The
    // main device writes it on the till credential — it renews at the till,
    // with nobody in the back office — and a child reads it. UPDATE hands a
    // stolen credential nothing: every licence is Ed25519-signed, so the most
    // it can write is a licence that already existed.
    'GRANT SELECT, INSERT, UPDATE ON pos_site_licence TO "$role"',
    // Shifts are opened and closed at the till by definition. No DELETE: a
    // cash-up somebody wants to disappear is exactly the row that must not.
    'GRANT SELECT, INSERT, UPDATE ON pos_shifts TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_shifts_id_seq TO "$role"',
    // The outbound queue. No DELETE: a delivered row is the record that
    // this sale was already sent, and a till that can forget that is a
    // till that sends it twice.
    'GRANT SELECT, INSERT, UPDATE ON pos_outbox TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_outbox_id_seq TO "$role"',
    // Shifts, cash movements and refunds have their own durable delivery
    // claims; a sale's order outbox row cannot safely stand in for them.
    'GRANT SELECT, INSERT, UPDATE ON pos_sync_outbox TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_sync_outbox_id_seq TO "$role"',
    // The audit ledger. INSERT and SELECT, never UPDATE or DELETE. The
    // table's triggers refuse the rest anyway; this makes it true at the
    // grant as well, so the trigger is the second line of defence rather
    // than the only one.
    'GRANT SELECT, INSERT ON pos_audit_events TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_audit_events_id_seq TO "$role"',
    // The record of every copy taken of this database. On the TILL's list, not
    // only the administrator's, because the automatic copy is taken when the
    // trading day is closed — at the till, by a machine on which nobody has
    // signed into the back office. Granted the same INSERT and SELECT as the
    // ledger and for the same reason: a row saying last night's backup failed
    // verification must not be editable by anybody who would rather it did not
    // say that. Migration 37's trigger refuses the rest even from an admin
    // connection.
    'GRANT SELECT, INSERT ON pos_backups TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_backups_id_seq TO "$role"',
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
    // second opinion: this database IS the business. Granted there, the same
    // statements let a credential recovered from the till reprice the menu for
    // real, and — through `pos_users` — point somebody's row at the owner role
    // or overwrite a PIN hash, reaching Management without ever knowing the
    // administrator's password. So an offline install does not get them, and
    // loses nothing: `BootstrapSeeder` never runs without a platform, and
    // Management authors the menu and the staff over the ADMIN credential.
    if (cloudSeeding) ...[
      'GRANT INSERT, UPDATE ON pos_businesses, pos_branches, pos_users TO "$role"',
      'GRANT INSERT, UPDATE, DELETE ON pos_categories, pos_products, '
          'pos_modifier_groups, pos_modifiers, pos_product_modifier_groups, '
          'pos_modifier_group_categories, pos_dining_tables TO "$role"',
      'GRANT USAGE, SELECT, UPDATE ON SEQUENCE pos_businesses_id_seq, '
          'pos_branches_id_seq, pos_users_id_seq, pos_categories_id_seq, '
          'pos_products_id_seq, pos_modifier_groups_id_seq, '
          'pos_modifiers_id_seq, pos_dining_tables_id_seq TO "$role"',
      // Payment methods, since POS-BE-013 delivers them in the bundle. No
      // DELETE: a tender the platform stopped sending is retired, because a
      // queued payment names it by id and nothing else would. UPDATE on the
      // sequence is for the `setval` that keeps platform rows above the
      // compiled-in ids — see migration 41.
      'GRANT INSERT, UPDATE ON pos_tender_types TO "$role"',
      'GRANT USAGE, SELECT, UPDATE ON SEQUENCE pos_tender_types_id_seq '
          'TO "$role"',
      // Financial accounts, since XORD-015 delivers them in the bundle's
      // `money` block. No DELETE on the accounts: one the platform stopped
      // sending is retired, because a payment will name it. The defaults hold
      // no history (nothing is posted against them), so the seeder may replace
      // them wholesale and gets DELETE there. UPDATE on the sequences is for
      // the `setval` that keeps new rows above the platform's ids.
      'GRANT INSERT, UPDATE ON pos_financial_accounts TO "$role"',
      'GRANT INSERT, UPDATE, DELETE ON pos_tender_account_defaults TO "$role"',
      // UPDATE only where `setval` needs it: the accounts keep platform ids,
      // so `_bumpSequences` moves that serial; the defaults take `nextval`.
      'GRANT USAGE, SELECT, UPDATE ON SEQUENCE '
          'pos_financial_accounts_id_seq TO "$role"',
      'GRANT USAGE, SELECT ON SEQUENCE '
          'pos_tender_account_defaults_id_seq TO "$role"',
      // Who the receipt says sold the food, since A3 delivers it in the bundle
      // (`receipt_profiles[]`). The SELECT above is unconditional — every till
      // prints a slip — and this adds the seeder's upsert on top.
      //
      // The bargain is the same one and reads as well here as anywhere: on a
      // cloud till the trade name and registration number in this table are a
      // *cache* of what the dashboard authors, and a resync overwrites whatever
      // a stolen credential wrote into it. What that credential cannot do is
      // change the document at the source, and the e-receipt it would forge is
      // signed and filed against the taxpayer the PLATFORM names. Offline there
      // is no source and no second opinion — this row IS what the receipt says
      // — so the REVOKE below takes it back, and Management authors it over the
      // administrator's credential exactly as before.
      //
      // No DELETE: a branch the platform stopped naming keeps its row, because
      // `pos_branches` keeps the branch (switched off, not removed) and the
      // cascade is what eventually takes both. INSERT means `nextval`, so the
      // sequence comes with it — the `id` here is the till's own, not the
      // platform's, which is why this one wants no UPDATE on the sequence.
      'GRANT INSERT, UPDATE ON pos_receipt_profiles TO "$role"',
      'GRANT USAGE, SELECT ON SEQUENCE pos_receipt_profiles_id_seq TO "$role"',
      // The **only** UPDATE a refund ever gets, and column-scoped: the drain
      // writes back the platform's credit note number when POS-BE-010 accepts
      // a refund, exactly as it writes back an invoice number on a sale
      // (migration 50). Every money column, the order it names, who gave it
      // back and who authorised it stay unwritable — so the most a recovered
      // till credential can rewrite here is a reference number the platform
      // issued and will issue again on replay.
      //
      // Cloud only, and not because offline is safer: an offline till has no
      // platform to get a credit note number from, so granting it there would
      // be a write nothing performs, sitting in an audit trail as though
      // something did.
      'GRANT UPDATE (server_credit_note_number) ON pos_refunds TO "$role"',
    ] else ...[
      // Taken away, not merely withheld. Every offline branch server built
      // before this distinction existed was granted the block above, and a
      // grant list that only ever adds would leave those installs — the ones
      // already taking money — permissive forever. REVOKE of something never
      // held is a no-op, so a fresh install pays nothing for this.
      'REVOKE INSERT, UPDATE, DELETE ON pos_businesses, pos_branches, '
          'pos_users, pos_categories, pos_products, pos_modifier_groups, '
          'pos_modifiers, pos_product_modifier_groups, '
          'pos_modifier_group_categories, pos_dining_tables '
          'FROM "$role"',
      'REVOKE UPDATE ON SEQUENCE pos_businesses_id_seq, '
          'pos_branches_id_seq, pos_users_id_seq, pos_categories_id_seq, '
          'pos_products_id_seq, pos_modifier_groups_id_seq, '
          'pos_modifiers_id_seq, pos_dining_tables_id_seq FROM "$role"',
      // Offline, `counts_as_cash` on this table is what every cash-up expects
      // in the drawer. Authoring it is Management's, over the admin
      // credential — which the migration tool and the setup wizard both grant
      // AFTER this list, so the REVOKE cannot take it from an administrator.
      'REVOKE INSERT, UPDATE ON pos_tender_types FROM "$role"',
      'REVOKE UPDATE ON SEQUENCE pos_tender_types_id_seq FROM "$role"',
      // The same for the accounts: offline they are Management's to author
      // over the admin credential, and a till that was once cloud must not
      // keep the seeder's writes.
      'REVOKE INSERT, UPDATE ON pos_financial_accounts FROM "$role"',
      'REVOKE INSERT, UPDATE, DELETE ON pos_tender_account_defaults '
          'FROM "$role"',
      'REVOKE UPDATE ON SEQUENCE pos_financial_accounts_id_seq, '
          'pos_tender_account_defaults_id_seq FROM "$role"',
      // Offline, this row is not a cache of anything: it is the trade name and
      // the tax registration number on a legal document, and the till keeps
      // SELECT and nothing else. `till_grants_enforced_test` applies the cloud
      // list and then this one, so this REVOKE is what keeps "the till may not
      // change what the receipt says about the seller" true.
      //
      // The sequence goes too, though a sequence without INSERT is inert. Left
      // granted it would read, to whoever audits this next, as a till that
      // writes here.
      'REVOKE INSERT, UPDATE ON pos_receipt_profiles FROM "$role"',
      'REVOKE USAGE, SELECT ON SEQUENCE pos_receipt_profiles_id_seq '
          'FROM "$role"',
      // And a refund goes back to no UPDATE at all. Nothing offline ever
      // writes this column, and a till that was once cloud must not keep the
      // one grant that lets it edit a refund row.
      'REVOKE UPDATE ON pos_refunds FROM "$role"',
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
    'GRANT SELECT, INSERT, UPDATE ON pos_users TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_users_id_seq TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_roles TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_roles_id_seq TO "$role"',
    // Granting a second role, an exception or a ceiling. DELETE here, unlike
    // almost everywhere else: these three are the *current* shape of somebody's
    // access rather than a record of anything that happened, and the record is
    // the audit ledger's job. A revoked override that could only be flipped to
    // ALLOW and never removed would leave a table nobody can read.
    'GRANT SELECT, INSERT, UPDATE, DELETE ON pos_user_roles, '
        'pos_user_permission_overrides, pos_permission_limits TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_permission_limits_id_seq TO "$role"',
    // A business's own vocabulary for why things happen. Editable in
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
    // which options a product offers. The categories a library group reaches
    // (migration 45) are the same kind of row.
    'GRANT SELECT, INSERT, DELETE ON pos_product_modifier_groups, '
        'pos_modifier_group_categories TO "$role"',
    // **The one DELETE on the catalogue itself**, and only on sizes and
    // extras. Removing an option from a group, or a group from the library,
    // is how the platform edits them and what a manager means by it — and
    // unlike a product, neither is the subject of anything a sale recorded: an
    // order line keeps its own `modifier_summary` and names the options by id
    // only. The rule that matters for those ids is that an option which STAYS
    // keeps its id, which is the repository's to hold, not a grant's.
    'GRANT DELETE ON pos_modifier_groups, pos_modifiers TO "$role"',
    // The named rates. **The write that Wave M deferred** — "granting them
    // before there is a screen would be granting them to nobody" — now that the
    // Tax pane edits them. No DELETE: a group a product points at cannot be
    // removed without silently reclassifying that product, so it is retired.
    'GRANT SELECT, INSERT, UPDATE ON pos_tax_groups TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_units TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_units_id_seq TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_tax_groups_id_seq TO "$role"',
    // Per-branch prices and combos are still read-only here: nothing in
    // Management edits them yet, and granting a write to nobody is how a role
    // ends up holding more than anything needs.
    'GRANT SELECT ON pos_product_prices, pos_combos, '
        'pos_combo_groups, pos_combo_options TO "$role"',
    // The trade name, registration number and address a receipt is judged on.
    // No DELETE: a branch stops having a profile by being archived, not by
    // having its identity removed from under the receipts already issued.
    'GRANT SELECT, INSERT, UPDATE ON pos_receipt_profiles TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_receipt_profiles_id_seq TO "$role"',
    // Authoring what the business offers, and what a role may take off by
    // hand. A DELETE on the targets, unlike almost everywhere else: they are
    // not a record of anything that happened, only the current shape of a
    // discount, and un-targeting a category has to be possible.
    'GRANT SELECT, INSERT, UPDATE ON pos_discounts TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_discounts_id_seq TO "$role"',
    'GRANT SELECT, INSERT, DELETE ON pos_discount_targets TO "$role"',
    // Authoring what the business has configured. The till reads these; the
    // back office writes them — blind close, the business-day start time and
    // the refund policy are all decisions somebody makes once.
    'GRANT SELECT, INSERT, UPDATE, DELETE ON pos_settings TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_settings_id_seq TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_cash_drawers TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_cash_drawers_id_seq TO "$role"',
    // Reading the drawer's history and the day's, and — since a supplier can be
    // paid out of a till from the purchasing pane — writing one movement into
    // it. **INSERT, and still no UPDATE or DELETE:** a pay-out already recorded
    // is money that left, and the back office corrects one by recording a
    // pay-in beside it, which is what voiding such a payment does.
    //
    // It was SELECT-only here. An administrator role is given the till list as
    // well, which already grants INSERT, so a real install happened to work —
    // and a deployment given only this list would have failed on the first
    // supplier paid out of the drawer. Spelling it out is what makes the intent
    // reviewable rather than an accident of two lists overlapping.
    'GRANT SELECT, INSERT ON pos_cash_movements TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_cash_movements_id_seq TO "$role"',
    // The shift the pay-out lands on. SELECT only: the office reads which
    // terminal and which trading day a drawer belongs to, and opens and closes
    // nothing.
    'GRANT SELECT ON pos_shifts TO "$role"',
    'GRANT SELECT ON pos_business_days TO "$role"',
    // Reading refunds back — the void and refund reports, and the Activity
    // pane. SELECT only, even here: a refund is a record of money that left
    // the drawer, and the back office corrects one by issuing another, not by
    // editing the first.
    'GRANT SELECT ON pos_refunds, pos_refund_lines, pos_refund_payments '
        'TO "$role"',

    // ── What Wave D authored, and had no write grant for ─────────────────
    //
    // **Every table below was reachable from a Management pane and writable by
    // nobody.** The till list grants SELECT on the first three, so an
    // administrator — who is given both lists — could read a payment method and
    // could not save one; the purchasing tables had no grant in either list at
    // all. Every database suite runs as the superuser, so every test passed.
    //
    // The coverage test that should have caught it was reading a hand-written
    // list of repository filenames that these were never added to. It now
    // enumerates the directory instead and refuses to pass while a repository
    // is classified as neither till nor back office.
    'GRANT SELECT, INSERT, UPDATE ON pos_tender_types, pos_service_charges, '
        'pos_order_types TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_tender_types_id_seq, '
        'pos_service_charges_id_seq, pos_order_types_id_seq TO "$role"',
    // Financial accounts (XORD-015). Offline only, in practice: on a cloud till
    // the platform authors them and the administrator pane is read-only. No
    // DELETE on the accounts — they are retired. The defaults carry no history
    // and are replaced or cleared by the owner, so they may be deleted.
    'GRANT SELECT, INSERT, UPDATE ON pos_financial_accounts TO "$role"',
    'GRANT SELECT, INSERT, UPDATE, DELETE ON pos_tender_account_defaults '
        'TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_financial_accounts_id_seq, '
        'pos_tender_account_defaults_id_seq TO "$role"',
    // Who the business buys from. No DELETE: a supplier is retired, because
    // their invoices name them.
    'GRANT SELECT, INSERT, UPDATE ON pos_suppliers TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_suppliers_id_seq TO "$role"',
    // Purchase orders and their lines. DELETE on the lines alone, and only
    // there: a draft's lines are the current shape of a document nobody has
    // sent, so the editor replaces them wholesale — whereas the order itself is
    // cancelled rather than removed, because an order somebody sent and then
    // called off is a conversation with a supplier.
    'GRANT SELECT, INSERT, UPDATE ON pos_purchase_orders TO "$role"',
    'GRANT SELECT, INSERT, UPDATE, DELETE ON pos_purchase_order_lines TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_purchase_orders_id_seq, '
        'pos_purchase_order_lines_id_seq TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_purchase_sequences TO "$role"',
    // The stock ledger. INSERT and SELECT, never UPDATE or DELETE — a movement
    // is a claim about what physically happened, and a row somebody can edit
    // afterwards is a stock figure nobody can defend. The cached position is
    // the one thing here that is genuinely a working figure, so it takes
    // UPDATE.
    'GRANT SELECT, INSERT ON pos_stock_movements TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_stock_movements_id_seq TO "$role"',
    // No sequence: the position is keyed by (business, branch, product), so
    // there is nothing to nextval.
    'GRANT SELECT, INSERT, UPDATE ON pos_stock_levels TO "$role"',
    // What is owed and what has been paid. UPDATE is column-scoped on both: an
    // invoice's numbers and a payment's amount are what the supplier's paper
    // says, and the only things the back office may change afterwards are the
    // note and the void. Correcting a figure means voiding the row and entering
    // it again, which is what leaves a trail.
    'GRANT SELECT, INSERT ON pos_supplier_invoices TO "$role"',
    'GRANT UPDATE (number, total_minor, tax_minor, issued_at, due_at, note, '
        'purchase_order_id, purchase_order_reference, voided_at, voided_by, '
        'void_reason_id, void_note, updated_at, updated_by) '
        'ON pos_supplier_invoices TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_supplier_invoices_id_seq TO "$role"',
    'GRANT SELECT, INSERT ON pos_supplier_payments TO "$role"',
    'GRANT UPDATE (note, voided_at, voided_by, void_reason_id, void_note) '
        'ON pos_supplier_payments TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_supplier_payments_id_seq TO "$role"',
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

/// The accounts an install creates. See [LocalBootstrap.createRoles].
enum InstallRole {
  admin,
  till,
  backup;

  static const defaultNames = {
    InstallRole.admin: 'pos_admin',
    InstallRole.till: 'pos_till',
    InstallRole.backup: 'pos_backup',
  };
}
