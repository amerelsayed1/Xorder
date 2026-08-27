import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';

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

  /// Reached Postgres and authenticated, but the statement failed.
  query,

  /// Unclassified. Never assume — report the raw error alongside.
  unknown;

  /// Classify a driver error without depending on its exception hierarchy,
  /// which folds several of these into one type.
  static PosDbFailure classify(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('failed host lookup') || text.contains('nodename')) return dns;
    if (text.contains('refused') || text.contains('timed out') || text.contains('unreachable')) {
      return tcp;
    }
    if (text.contains('certificate') || text.contains('handshake') || text.contains('tls')) {
      return tls;
    }
    if (text.contains('password') ||
        text.contains('authentication') ||
        text.contains('role ') ||
        text.contains('pg_hba')) {
      return auth;
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
/// Behind an interface because the real implementation is Keychain on macOS and
/// DPAPI on Windows via `flutter_secure_storage`, and neither belongs in a test.
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

/// Holds the password the setup wizard collected.
///
/// In-memory for now, which means the operator retypes it after a restart —
/// honest, and better than persisting a database password somewhere it could be
/// read. Replacing this with `flutter_secure_storage` (Keychain / DPAPI) is a
/// one-class change and nothing that calls it needs to know.
class MutablePosDbCredentials implements PosDbCredentials {
  String? _password;

  bool get isSet => _password?.isNotEmpty ?? false;

  void set(String? value) => _password = (value?.isEmpty ?? true) ? null : value;

  @override
  Future<String?> password() async => _password;
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
      throw PosDbException(PosDbFailure.dns, 'No branch server address configured.');
    }

    final password = await credentials.password();
    if (password == null || password.isEmpty) {
      throw PosDbException(PosDbFailure.auth, 'No database credential stored for this terminal.');
    }

    // Keyed on everything that identifies the connection — including the
    // credential. `Pool.withEndpoints` does not connect eagerly, so a wrong
    // password still produces a pool; without the credential in the key, an
    // operator who corrects a typo in the wizard would keep getting the stale
    // pool back and the fix would appear not to work. Hashed, never the value,
    // so the key stays safe to put in a log line.
    final key = '$host:${config.databasePort}/${config.databaseName}'
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
        sslMode: config.allowsInsecureTransport ? SslMode.disable : SslMode.require,
      ),
    );
    _openedFor = key;
    return _pool!;
  }

  /// Where this terminal's database lives.
  ///
  /// Only a branch server has one. Cloud and islanded terminals reach their data
  /// over HTTP, so they resolve to null and their repositories must not be the
  /// Postgres ones.
  static String? hostFor(DeploymentConfig config) {
    if (config.mode != DeploymentMode.branchServer) return null;
    final uri = Uri.tryParse(config.baseUrl ?? '');
    final host = uri?.host ?? '';
    return host.isEmpty ? null : host;
  }

  /// Run [action] in a transaction, translating driver errors on the way out.
  ///
  /// Every write goes through here. A till that half-writes an order is worse
  /// than one that refuses it, so there is no non-transactional write path.
  Future<T> runTx<T>(DeploymentConfig config, Future<T> Function(TxSession) action) async {
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
