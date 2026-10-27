import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'pos_db_secret_store.dart';

/// `secrets.json`: every secret in **plaintext**, in a file beside
/// `config.json`. Since ADR-006 this is the development store only, plus the
/// format the legacy migration reads.
///
/// **No Windows or macOS till writes this any more.** `SecretStore.forPlatform`
/// gives those DPAPI and the Keychain, and hands this file (wrapped as
/// `DevelopmentFileSecretStore`) only to Linux and test runs.
/// `LegacySecretMigration` moves an older till's copy into the OS store at its
/// first launch, then zeroes and deletes it.
///
/// Why it existed: on 2026-09-04 the owner moved secrets *out* of the
/// keychain, because an ad-hoc-signed or unsigned build looks like a new app
/// to the keychain after every rebuild, and the macOS *"XOrder POS wants to
/// use your confidential information"* prompt came back every morning.
/// ADR-006 reversed that. The file's protection was `chmod 600` on POSIX and
/// nothing at all on Windows, so a copy of the profile folder was a copy of
/// every password. The prompt's cost is recorded in
/// `mac_keychain_secret_store.dart`.
///
/// One file, many keys — the database password and the cloud device token are
/// two entries in one JSON object, so a support engineer clearing "the
/// credentials" clears one thing. The key names are kept as the names in the
/// OS store too, which is what lets the migration move them one for one.
class FileSecretStore implements PosDbSecretStore {
  FileSecretStore({required this.key, Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  /// Which entry this instance owns.
  final String key;

  static const fileName = 'secrets.json';

  /// The till's database password (`pos_till`).
  static const databasePasswordKey = 'pos_till_database_password';

  /// The cloud device token (POS-BE-011 Option C).
  static const deviceTokenKey = 'pos_cloud_device_token';

  /// The read-only backup account's password (`pos_backup`).
  ///
  /// Kept beside the till's because it reads every row and writes none. Every
  /// row includes the `pos_users` PIN hashes, which the till's own role can
  /// also read (SECURITY_AND_RECOVERY §3).
  static const backupPasswordKey = 'pos_backup_database_password';

  /// The back office's database password (`pos_admin`).
  ///
  /// **Unlike the three above, this one can do more than the till's own.** It
  /// was never kept anywhere until Admin Mode became a username and a PIN
  /// (owner decision, 12 Sep 2026) — see `adminDbSecretStoreProvider` for what
  /// keeping it costs. Whether to keep it at all is open (Q17).
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
