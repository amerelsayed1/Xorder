import 'dart:developer' show log;

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/config/lan_tls.dart';
import '../config/pos_db_secret_store.dart';
import 'pos_tls.dart';

/// Why a connection failed, as data rather than a string.
///
/// A cashier or an installer standing in a restaurant needs to know *which*
/// thing is broken: a hostname that does not resolve, a socket nothing is
/// listening on, a password Postgres rejected and a certificate it rejected all
/// need different actions. One generic "connection failed" drives none of them.
enum PosDbFailure {
  /// The hostname does not resolve. Use the IP, or fix the DHCP reservation.
  dns,

  /// Nothing listening, or a firewall dropped it. `listen_addresses` needs a
  /// restart rather than a reload, and the host needs an inbound rule.
  tcp,

  /// Reached Postgres; it rejected the credential. `pg_hba.conf`, first match wins.
  auth,

  /// The secure connection failed: a certificate this till does not trust,
  /// a server that does not offer TLS, or a handshake that died. **Never
  /// followed by a plaintext attempt** — see `LanTls.decide`. The wizard
  /// asks the server which certificate it presents to say which of these it
  /// was; the start screen just says the till could not confirm whose
  /// database it reached.
  tls,

  /// Reached Postgres, but there is no database by that name yet.
  ///
  /// Its own case because it is the FIRST-INSTALL case, and it used to fall
  /// through to [query] — "connected, but the database did not answer as
  /// expected", which is doubly wrong: nothing answered, because nothing is
  /// there, and the remedy is a button on the same screen that the message
  /// never mentioned. An installer reading it goes checking the name they
  /// typed, which was right all along.
  missingDatabase,

  /// Reached Postgres, and there is no such role to sign in as — or the
  /// statement named one that is not there.
  ///
  /// Its own case because it is NOT a password anybody can correct, and
  /// [auth] used to claim it: `FATAL: role "pos_admin" does not exist` sent
  /// an installer back to a password field to retype a password that was
  /// never the problem. The remedy is a role — name one that exists, or
  /// create it.
  missingRole,

  /// Signed in, and this role is not allowed to do that.
  ///
  /// Its own case because the remedy is a GRANT, not a password. It bites
  /// hardest when the till is pointed at a database somebody ELSE created:
  /// from PostgreSQL 15 the `public` schema no longer grants CREATE to all,
  /// so a role that did not create the database cannot build tables in it.
  permissionDenied,

  /// Reached Postgres and authenticated, but the statement failed.
  query,

  /// Unclassified. Never assume — report the raw error alongside.
  unknown;

  /// Classify a driver error without depending on its exception hierarchy,
  /// which folds several of these into one type.
  static PosDbFailure classify(Object error) {
    // By type first: the driver's text for this one is only "Bad server
    // certificate.", and a certificate refused is the case that must never be
    // mistaken for a network fault somebody might "fix" by turning TLS off.
    if (error is BadCertificateException) return tls;
    // Then by SQLSTATE, where the server sent one. The text rules below read
    // the MESSAGE, and a message quotes whatever the statement named: a
    // migration that has not run yet fails as `column "password_hash" does
    // not exist` (42703), and the word `password` in it used to report a
    // missing column as a refused login — sending an installer to retype a
    // password that was fine. A code cannot be fooled by a column's name.
    //
    // Only the codes whose answer is unambiguous are mapped. 28000 is NOT:
    // PostgreSQL uses it both for a role that does not exist and for a
    // pg_hba.conf refusal, which the text rules already tell apart (and the
    // second of those is TLS or auth depending on how the till came in).
    // Nor are 08xxx and 57P0x mapped to [tcp]: "unreachable" opens the
    // forced-reset rescue path in Admin Mode, and a server that answered
    // "shutting down" or "starting up" is not one that nothing answered —
    // widening that door belongs in its own change, not in a classifier fix.
    // Every unmapped code falls through to the text rules exactly as before.
    if (error is ServerException) {
      switch (error.code) {
        case '28P01': // invalid_password
          return auth;
        case '3D000': // invalid_catalog_name: no database by that name
          return missingDatabase;
        case '42501': // insufficient_privilege
          return permissionDenied;
        case '42703' || '42P01': // undefined_column, undefined_table
          return query;
      }
    }
    final text = error.toString().toLowerCase();
    if (text.contains('failed host lookup') || text.contains('nodename')) {
      return dns;
    }
    if (text.contains('refused') ||
        text.contains('timed out') ||
        text.contains('unreachable')) {
      return tcp;
    }
    // A pg_hba refusal names how the client came in: `no encryption` is a
    // plaintext till meeting a hostssl-only server (the remedy is encryption),
    // `SSL encryption` is an encrypted till from an address no line admits
    // (the remedy is pg_hba). Decided here, before the `ssl` below claims
    // the second one as a TLS fault it is not.
    if (text.contains('no pg_hba.conf entry')) {
      return text.contains('no encryption') ? tls : auth;
    }
    // `ssl` for the driver's "Server does not support SSL, but it was
    // required".
    if (text.contains('certificate') ||
        text.contains('handshake') ||
        text.contains('tls') ||
        text.contains('ssl')) {
      return tls;
    }
    // BEFORE the auth check, both of them. Postgres phrases the two the same
    // way — `FATAL: database "x" does not exist` and `FATAL: role "x" does not
    // exist` — so they are told apart by the noun, and neither may fall to
    // `auth`, which matches on `role ` and would take the role case first.
    // It used to, and reported a role PostgreSQL has never heard of as a
    // rejected password: an installer on a hand-installed PostgreSQL was sent
    // to retype `pos_admin`'s password over and over, when the role was simply
    // not there and the field to change was the one above it.
    if (text.contains('does not exist')) {
      if (text.contains('role ')) return missingRole;
      if (text.contains('database')) return missingDatabase;
    }
    if (text.contains('password') ||
        text.contains('authentication') ||
        text.contains('role ') ||
        text.contains('pg_hba')) {
      return auth;
    }
    // 42501. Named before the generic ServerException below, which would
    // otherwise report a GRANT problem as "the statement failed".
    if (text.contains('permission denied') || text.contains('42501')) {
      return permissionDenied;
    }
    if (error is ServerException) return query;
    return unknown;
  }
}

/// A database failure the UI can act on.
///
/// Thrown only across the repository boundary. Nothing in `lib/domain/` or
/// `lib/features/` ever catches a `postgres` type, which is what keeps the HTTP
/// swap a one-file change.
class PosDbException implements Exception {
  PosDbException(this.failure, this.raw);

  final PosDbFailure failure;
  final Object raw;

  /// The role a [PosDbFailure.missingRole] was about, when the driver named
  /// one — which Postgres always does, in exactly this shape.
  ///
  /// Read rather than assumed because a build connects as one role and grants
  /// to another: naming the administrator for a missing `pos_till` is the same
  /// class of wrong answer as calling it a bad password. Null when the text is
  /// not the shape this expects, and every caller has a role of its own to
  /// fall back on.
  static String? roleNamedIn(Object raw) =>
      RegExp(r'role "([^"]+)" does not exist')
          .firstMatch(raw.toString())
          ?.group(1);

  @override
  String toString() => 'PosDbException(${failure.name}): $raw';
}

/// Supplies the till's database password.
///
/// Behind an interface because the real implementation reads the till's
/// secrets file in Application Support, and the filesystem belongs in no test.
/// The credential is `pos_till`, not a superuser: see the GRANTs in
/// `docs/pos/08-postgres-lan.md` §7.
abstract interface class PosDbCredentials {
  Future<String?> password();
}

/// Reads the password from memory. Used by tests and by the opt-in integration
/// suite; the production binding is secure storage.
class InMemoryPosDbCredentials implements PosDbCredentials {
  InMemoryPosDbCredentials(this._password);

  final String? _password;

  @override
  Future<String?> password() async => _password;
}

/// Holds the password the setup wizard collected, backed by the OS keystore.
///
/// Memory is still the read path — the pool asks for the password on every
/// reconnect, and a keychain round trip per reconnect would be a keychain
/// prompt per reconnect. The keystore is read once at boot by [restore] and
/// written once by [save], at the end of the wizard.
///
/// [MutablePosDbCredentials.store] is null in tests and in the opt-in
/// integration suite, where the
/// credential is supplied directly and no keystore should be touched. With no
/// store this behaves exactly as it did before there was one: in-memory, lost
/// on exit.
class MutablePosDbCredentials implements PosDbCredentials {
  MutablePosDbCredentials({this.store});

  /// Null in tests, where the credential is supplied directly.
  final PosDbSecretStore? store;

  String? _password;

  bool get isSet => _password?.isNotEmpty ?? false;

  /// True when the keystore refused the last operation.
  ///
  /// Distinct from `!isSet`, and the distinction is the whole point: a fresh
  /// install has no password *and* a working keystore, so it can simply be
  /// asked for one. A machine whose keystore is unreachable will accept a
  /// password, appear to finish setup, and ask again tomorrow — so the operator
  /// has to be told now, while they are still standing at the till.
  bool get storeUnavailable => store?.lastFailure != null;

  void set(String? value) =>
      _password = (value?.isEmpty ?? true) ? null : value;

  @override
  Future<String?> password() async => _password;

  /// Load the saved password at boot. Does not overwrite one already set.
  Future<void> restore() async {
    if (isSet) return;
    _password = await store?.read();
  }

  /// Commit the current password to the keystore.
  ///
  /// Clearing is as important as writing: a terminal reconfigured onto a
  /// different database must not keep the old server's credential where the
  /// next boot would find it.
  Future<void> save() async {
    final target = store;
    if (target == null) return;

    final password = _password;
    if (password == null) {
      await target.clear();
    } else {
      await target.write(password);
    }
  }

  /// Forget the password here and in the keystore. Used by terminal reset.
  Future<void> forget() async {
    _password = null;
    await store?.clear();
  }
}

/// Owns the connection pool to the branch server's PostgreSQL.
///
/// **A pool, not a connection.** The selling screen, the sync worker and the
/// print job each want their own session, and the pool handles reconnect after
/// the branch switch reboots — which it will, mid-service, eventually.
///
/// This class is the only place in the app that knows Postgres exists. Every
/// caller goes through a repository contract, so replacing these with HTTP
/// implementations later changes `providers.dart` and nothing else.
class PosDatabase {
  PosDatabase({
    required this.credentials,
    LanTlsDecision Function(DeploymentConfig config)? transportFor,
  }) : _transportFor = transportFor ?? _configuredTransport;

  final PosDbCredentials credentials;

  /// How a connection to [DeploymentConfig.databaseHost] is protected —
  /// always [DeploymentConfig.lanTls] in the app.
  ///
  /// A parameter only so `test/data/lan_tls_handshake_test.dart` can point
  /// the TLS path at a fake server on 127.0.0.1, which the real rule
  /// (rightly) never encrypts. Nothing in `lib/` passes it.
  final LanTlsDecision Function(DeploymentConfig config) _transportFor;

  static LanTlsDecision _configuredTransport(DeploymentConfig config) =>
      config.lanTls;

  Pool<void>? _pool;
  String? _openedFor;

  /// The transport settings the open pool was built with, handed again to
  /// every checkout. In `postgres` 3.5.12 a pool's own `PoolSettings` reach
  /// only the connections the pool opens through `withConnection(settings:)`;
  /// `pool.execute` and `pool.runTx` resolve their settings without them, so a
  /// pinned certificate's `SecurityContext` was silently dropped and a
  /// self-signed LAN server was refused. Found by running
  /// `lan_tls_handshake_test` against the real driver.
  ConnectionSettings? _connectionSettings;

  /// The pool for [config], opening one if the endpoint changed.
  ///
  /// Keyed on the resolved host so that reconfiguring the terminal in the setup
  /// wizard does not leave it talking to the previous branch server.
  Future<Pool<void>> pool(DeploymentConfig config) async {
    final host = hostFor(config);
    if (host == null) {
      throw PosDbException(
        PosDbFailure.dns,
        'No database address configured for this terminal.',
      );
    }

    final password = await credentials.password();
    if (password == null || password.isEmpty) {
      throw PosDbException(
        PosDbFailure.auth,
        'No database credential stored for this terminal.',
      );
    }

    final tls = _transportFor(config);
    // Checked before every pool, not once at pairing: `config.json` is a
    // plain file an engineer is invited to read, and one who edited the PEM
    // or the fingerprint by hand must get a refusal that names the file, not
    // a connection that trusts whichever half they changed.
    if (tls.pin case final pin? when !pin.isConsistent) {
      throw PosDbException(
        PosDbFailure.tls,
        'The certificate this till is paired with does not match the '
        'fingerprint saved beside it in config.json. Pair this till with its '
        'database server again.',
      );
    }

    // Keyed on everything that identifies the connection — including the
    // credential. `Pool.withEndpoints` does not connect eagerly, so a wrong
    // password still produces a pool; without the credential in the key, an
    // operator who corrects a typo in the wizard would keep getting the stale
    // pool back and the fix would appear not to work. Hashed, never the value,
    // so the key stays safe to put in a log line. The transport is in it for
    // the same reason: a till just paired must not keep the pool that was
    // refused a moment ago.
    final key =
        '$host:${config.databasePort}/${config.databaseName}'
        '@${config.databaseUser}#${password.hashCode}'
        '|${tls.transport.name}:${tls.pin?.sha256 ?? ''}';
    if (_pool != null && _openedFor == key) return _pool!;
    await close();

    _pool = Pool.withEndpoints(
      [
        Endpoint(
          host: host,
          port: config.databasePort,
          database: config.databaseName,
          username: config.databaseUser,
          password: password,
        ),
      ],
      settings: PoolSettings(
        maxConnectionCount: 4,
        connectTimeout: const Duration(seconds: 5),
        queryTimeout: const Duration(seconds: 10),
        // One transport per pool, decided before it opens and never revised
        // by a failure: a refused handshake surfaces as PosDbFailure.tls and
        // the pool is not rebuilt in the clear. `require` is never used — in
        // the postgres package it accepts every certificate. See pos_tls.dart.
        sslMode: PosTlsSettings.sslModeFor(tls),
        securityContext: PosTlsSettings.securityContextFor(tls),
      ),
    );
    _connectionSettings = ConnectionSettings(
      sslMode: PosTlsSettings.sslModeFor(tls),
      securityContext: PosTlsSettings.securityContextFor(tls),
    );
    _openedFor = key;
    return _pool!;
  }

  /// Where this terminal's database lives.
  ///
  /// **Every mode has one.** A cloud terminal keeps its own PostgreSQL and syncs
  /// it upward; an offline terminal's PostgreSQL is the source of truth. What
  /// varies is only whether the host is this machine or a box on the LAN, so
  /// this reads [DeploymentConfig.databaseHost] and never the mode.
  ///
  /// Null means *not configured yet* — a terminal that has not finished setup —
  /// and the providers fall back to the unconfigured repositories on it.
  static String? hostFor(DeploymentConfig config) {
    final host = config.databaseHost.trim();
    return host.isEmpty ? null : host;
  }

  /// Run [action] in a transaction, translating driver errors on the way out.
  ///
  /// Every write goes through here. A till that half-writes an order is worse
  /// than one that refuses it, so there is no non-transactional write path.
  Future<T> runTx<T>(
    DeploymentConfig config,
    Future<T> Function(TxSession) action,
  ) async {
    try {
      final session = await pool(config);
      return await session.withConnection(
        (c) => c.runTx(action),
        settings: _connectionSettings,
      );
    } on PosDbException {
      rethrow;
    } on Object catch (error) {
      throw PosDbException(PosDbFailure.classify(error), error);
    }
  }

  /// Read-only convenience with the same error translation.
  Future<Result> query(
    DeploymentConfig config,
    String sql, {
    Object? parameters,
  }) async {
    try {
      final session = await pool(config);
      return await session.withConnection(
        (c) => c.execute(Sql.named(sql), parameters: parameters),
        settings: _connectionSettings,
      );
    } on PosDbException {
      rethrow;
    } on Object catch (error) {
      throw PosDbException(PosDbFailure.classify(error), error);
    }
  }

  /// Probe the endpoint and report which of the failure modes it hit.
  /// Returns null when the connection is healthy.
  Future<PosDbFailure?> probe(DeploymentConfig config) async {
    try {
      await query(config, 'SELECT 1');
      return null;
    } on PosDbException catch (error) {
      // The RAW driver message, on the console. The screen gets one sentence
      // naming which of the four things went wrong, which is what an installer
      // needs; it is not what somebody debugging needs, and this used to be the
      // only place the difference was thrown away.
      // `dart:developer`, not `debugPrint`: this file is also compiled into
      // `bin/pos_migrate.dart`, a pure-Dart CLI with no Flutter engine, and
      // importing `package:flutter/foundation.dart` here drags in `dart:ui` and
      // stops that tool building. There is a test that says so.
      log(
        'probe ${config.databaseUser}@${config.databaseHost}:'
        '${config.databasePort}/${config.databaseName} → '
        '${error.failure.name}: ${error.raw}',
        name: 'pos.db',
      );
      return error.failure;
    }
  }

  Future<void> close() async {
    final existing = _pool;
    _pool = null;
    _openedFor = null;
    if (existing != null) await existing.close();
  }
}
