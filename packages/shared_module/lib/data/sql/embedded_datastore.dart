import '../../core/config/deployment.dart';

/// A till whose data lives in a file on the till itself — the cloud app's
/// encrypted SQLite (pos-cloud-single-till-sqlite) — rather than in a
/// PostgreSQL server the installer set up.
///
/// The setup wizard's connecting step asks this to get the file ready instead
/// of reading the installer's credentials and building a database: there is
/// nothing to install, no account to create and no password to type.
abstract interface class EmbeddedDatastore {
  /// Create the file and its key if this till has none yet, and bring its
  /// schema up to date. Safe to call again.
  Future<EmbeddedDatastoreReport> prepare(DeploymentConfig config);
}

/// What [EmbeddedDatastore.prepare] did, for the connecting step's report.
class EmbeddedDatastoreReport {
  const EmbeddedDatastoreReport({
    required this.created,
    required this.migrations,
  });

  /// A new file (and key) was made on this call.
  final bool created;

  /// Schema steps applied on this call.
  final int migrations;
}
