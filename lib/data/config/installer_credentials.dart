import 'dart:convert';
import 'dart:io';

/// The PostgreSQL accounts `installer/provision.ps1` created on this machine.
///
/// The installer generates a password per role from the system's cryptographic
/// generator, writes them to `%ProgramData%\XOrder POS\install-credentials.json`
/// and locks that file to Administrators and SYSTEM — *before* `initdb`, so
/// that a half-finished install still leaves the passwords where a technician
/// will look. Nobody ever types them, and nobody could: they are 24 random
/// characters.
///
/// Which is exactly why the cloud wizard reads them instead of asking. The
/// database screen used to demand a host, a name, a port, a role and a password
/// that the person standing at the till had no way of knowing — the only honest
/// answer was to open this file and copy out of it.
///
/// **Absent is a normal answer, not a failure.** A developer's Mac has no
/// installer and therefore no file; so does a till whose PostgreSQL somebody
/// set up by hand. Both get the fallback screen, with the fields and the
/// defaults, rather than a wizard that refuses to go on.
class InstallerCredentials {
  const InstallerCredentials({
    required this.port,
    required this.database,
    required this.adminUser,
    required this.adminPassword,
    required this.tillUser,
    required this.tillPassword,
  });

  final int port;
  final String database;

  /// `pos_admin` — owns the schema, applies migrations, grants. Used to build
  /// and then kept only for Admin Mode; see `SetupController.complete`.
  final String adminUser;
  final String adminPassword;

  /// `pos_till` — SELECT and INSERT on the POS tables and nothing else. The
  /// credential the till trades on, and the only one in the keystore.
  final String tillUser;
  final String tillPassword;

  /// Tolerant by rule, like every other reader of somebody else's document: a
  /// file this build half-understands is treated as no file at all rather than
  /// as a crash on the first screen of an install. The alternative — throwing —
  /// would turn a stale credentials file into a till that cannot be set up,
  /// with the reason buried in a stack trace.
  static InstallerCredentials? tryParse(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final json = decoded.cast<String, Object?>();

    Map<String, Object?>? role(String key) =>
        json[key] is Map ? (json[key] as Map).cast<String, Object?>() : null;

    final admin = role('admin');
    final till = role('till');
    final adminPassword = admin?['password'];
    final tillPassword = till?['password'];
    // Without both passwords there is nothing here the wizard could use, and
    // half of them is worse than none: it would build a database and then fail
    // to grant the till access to it.
    if (adminPassword is! String ||
        adminPassword.isEmpty ||
        tillPassword is! String ||
        tillPassword.isEmpty) {
      return null;
    }

    return InstallerCredentials(
      port: switch (json['port']) {
        final int value => value,
        final String value => int.tryParse(value) ?? 5432,
        _ => 5432,
      },
      database: json['database'] is String && (json['database'] as String).isNotEmpty
          ? json['database'] as String
          : 'xorder_pos',
      adminUser: admin?['name'] is String ? admin!['name'] as String : 'pos_admin',
      adminPassword: adminPassword,
      tillUser: till?['name'] is String ? till!['name'] as String : 'pos_till',
      tillPassword: tillPassword,
    );
  }
}

/// Where the wizard looks for [InstallerCredentials].
///
/// An interface so a test can say what this machine looks like without a
/// filesystem — reading a real path from a widget test would make the answer
/// depend on the developer's own machine.
abstract interface class InstallerCredentialsSource {
  Future<InstallerCredentials?> read();
}

/// The file the Windows installer wrote.
class FileInstallerCredentials implements InstallerCredentialsSource {
  const FileInstallerCredentials();

  /// Kept in step with `$CredFile` in `installer/provision.ps1` by hand. A
  /// constant in two places is a real cost; the alternative was shipping the
  /// path through a `--dart-define` that every developer would have to know
  /// about, to describe a file only Windows ever has.
  static const fileName = 'install-credentials.json';
  static const directoryName = 'XOrder POS';

  @override
  Future<InstallerCredentials?> read() async {
    // ProgramData, from the environment rather than hard-coded to C:\: a
    // machine whose Windows lives on another drive is rare and completely
    // ordinary, and the installer itself resolves it the same way.
    final root = Platform.environment['ProgramData'];
    if (root == null || root.isEmpty) return null;

    final file = File('$root${Platform.pathSeparator}$directoryName'
        '${Platform.pathSeparator}$fileName');
    try {
      if (!await file.exists()) return null;
      return InstallerCredentials.tryParse(await file.readAsString());
    } on FileSystemException {
      // The file is locked to Administrators and SYSTEM. A till running as
      // somebody else is refused it — which reads here as "this machine cannot
      // tell me", the same outcome as the file not being there, and lands the
      // operator on the fallback screen instead of on an unhandled error.
      return null;
    }
  }
}
