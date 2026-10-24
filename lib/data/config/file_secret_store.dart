import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'pos_db_secret_store.dart';

/// Machine-bound secrets in a file beside `config.json` — **not** in the OS
/// keychain, by explicit decision (owner, 2026-09-04).
///
/// The keychain binding this replaces produced the macOS *"XOrder POS wants to
/// use your confidential information"* password prompt on launch — and on an
/// unsigned or ad-hoc-signed build (which is every dev build, and every
/// Developer ID install until notarised), each rebuild looks like a new app to
/// the keychain, so the prompt returns forever. A till that asks the operator
/// for the *machine's* login password at open is a support call every morning.
///
/// The honest threat model, stated rather than implied: on a single-user till,
/// the login keychain is unlocked the moment the operator logs in, so a
/// keychain item and a user-readable file resist the same attacker — someone
/// at the till's own session reads both; someone without it reads neither.
/// The protections that actually matter stay where they were: the `pos_till`
/// database role holds `SELECT`/`INSERT` and nothing else, the device token
/// dies with terminal revocation server-side, and neither secret opens the
/// dashboard. The file is created `0600` where the platform honours it.
///
/// One file, many keys — the database password and the cloud device token are
/// two entries in one JSON object, so a support engineer clearing "the
/// credentials" clears one thing.
class FileSecretStore implements PosDbSecretStore {
  FileSecretStore({required this.key, Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  /// Which entry this instance owns.
  final String key;

  static const fileName = 'secrets.json';

  /// The database password, as `KeychainPosDbSecretStore` used to hold it.
  static const databasePasswordKey = 'pos_till_database_password';

  /// The cloud device token (POS-BE-011 Option C).
  static const deviceTokenKey = 'pos_cloud_device_token';

  /// The read-only backup account's password (`pos_backup`).
  ///
  /// Kept here, beside the till's, because it can do no more than the till's
  /// file already can: it reads every row and writes none.
  static const backupPasswordKey = 'pos_backup_database_password';

  /// The back office's database password (`pos_admin`).
  ///
  /// **Unlike the two above, this one can do more than the till's file.** It
  /// was never kept anywhere until Admin Mode became a username and a PIN
  /// (owner decision, 12 Sep 2026) — see `adminDbSecretStoreProvider` for what
  /// keeping it here costs, and why that was accepted.
  static const adminPasswordKey = 'pos_admin_database_password';

  final Future<Directory> Function() _directory;

  @override
  Object? get lastFailure => _lastFailure;
  Object? _lastFailure;

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, fileName));
  }

  Future<Map<String, Object?>> _readAll() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(await file.readAsString());
      // A damaged file is an empty store, not a crash — same bargain as
      // FileTerminalConfigStore: the wizard can re-ask, a dead till cannot.
      return decoded is Map ? decoded.cast<String, Object?>() : {};
    } on FileSystemException catch (error) {
      _lastFailure = error;
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, Object?> secrets) async {
    final target = await _file();
    final temporary = File('${target.path}.tmp');
    // Empty first, then restricted, then filled. Written-then-chmodded leaves
    // the secret on disk at the umask default — 0644 on a stock macOS — for
    // as long as the write and the rename take, and anything that reads the
    // directory in that window gets the database password. The window is
    // small; it is also unnecessary.
    await temporary.writeAsString('', flush: true);
    await _restrict(temporary);
    await temporary.writeAsString(jsonEncode(secrets), flush: true);
    await temporary.rename(target.path);
    // Rename preserves the mode, so this is belt and braces — and it is what
    // repairs a `secrets.json` that an earlier build left group-readable.
    await _restrict(target);
  }

  /// Owner-only permissions, best effort. Windows scopes Application Support
  /// per user profile already; on POSIX this makes it explicit.
  Future<void> _restrict(File file) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['600', file.path]);
    } on ProcessException {
      // A store that works but is group-readable beats one that refused to
      // work; the failure is visible in the file listing, not hidden.
    }
  }

  @override
  Future<String?> read() async {
    final value = await _readAll();
    final secret = value[key];
    return secret is String && secret.isNotEmpty ? secret : null;
  }

  @override
  Future<void> write(String value) async {
    try {
      final secrets = await _readAll();
      secrets[key] = value;
      await _writeAll(secrets);
      _lastFailure = null;
    } on FileSystemException catch (error) {
      _lastFailure = error;
      throw PosDbSecretStoreException(error);
    }
  }

  /// Delete the whole secrets file — every entry, not only this instance's
  /// [key]. For the hard reset: the file holds the database password, the cloud
  /// device token and the back-office and backup passwords together, and a till
  /// handed to somebody else must keep none of them. A missing file is not an
  /// error.
  Future<void> deleteFile() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
      _lastFailure = null;
    } on FileSystemException catch (error) {
      _lastFailure = error;
      throw PosDbSecretStoreException(error);
    }
  }

  @override
  Future<void> clear() async {
    try {
      final secrets = await _readAll();
      secrets.remove(key);
      await _writeAll(secrets);
      _lastFailure = null;
    } on FileSystemException catch (error) {
      _lastFailure = error;
      throw PosDbSecretStoreException(error);
    }
  }
}
