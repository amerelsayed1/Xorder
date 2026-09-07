import 'dart:developer' show log;

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../config/pos_db_secret_store.dart';

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

  /// Reached Postgres; it rejected the certificate.
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
    final text = error.toString().toLowerCase();
    if (text.contains('failed host lookup') || text.contains('nodename')) {
      return dns;
    }
    if (text.contains('refused') ||
        text.contains('timed out') ||
        text.contains('unreachable')) {
      return tcp;
    }
    if (text.contains('certificate') ||
        text.contains('handshake') ||
        text.contains('tls')) {
      return tls;
    }
    if (text.contains('password') ||
        text.contains('authentication') ||
        text.contains('role ') ||
        text.contains('pg_hba')) {
      return auth;
    }
    // AFTER the auth check, deliberately. Postgres phrases both of these the
    // same way — `FATAL: database "x" does not exist` and `FATAL: role "x" does
    // not exist` — and a missing role is an authentication problem, not a
    // first-install one. Letting `auth` claim the role case first is what keeps
    // the two apart.
    if (text.contains('does not exist') && text.contains('database')) {
      return missingDatabase;
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
  PosDatabase({required this.credentials});

  final PosDbCredentials credentials;

  Pool<void>? _pool;
  String? _openedFor;

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

    // Keyed on everything that identifies the connection — including the
    // credential. `Pool.withEndpoints` does not connect eagerly, so a wrong
    // password still produces a pool; without the credential in the key, an
    // operator who corrects a typo in the wizard would keep getting the stale
    // pool back and the fix would appear not to work. Hashed, never the value,
    // so the key stays safe to put in a log line.
    final key =
        '$host:${config.databasePort}/${config.databaseName}'
        '@${config.databaseUser}#${password.hashCode}';
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
        // Relaxed only for a private address the operator explicitly trusted in
        // the wizard. `allowsInsecureTransport` already refuses to do this for a
        // public host, so a mistyped hostname cannot downgrade the till.
        // `require` encrypts but deliberately accepts every certificate in the
        // postgres package. The secure path must verify the certificate and
        // hostname against the platform trust store.
        sslMode: config.allowsInsecureTransport
            ? SslMode.disable
            : SslMode.verifyFull,
      ),
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
      return await session.runTx(action);
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
      return await session.execute(Sql.named(sql), parameters: parameters);
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
