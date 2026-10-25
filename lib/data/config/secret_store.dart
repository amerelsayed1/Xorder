import 'dart:io';

import 'file_secret_store.dart';
import 'mac_keychain_secret_store.dart';
import 'pos_db_secret_store.dart';
import 'windows_dpapi_secret_store.dart';

/// Every secret this till keeps, by name, in the operating system's own store.
///
/// **One store, many keys** — the same shape `secrets.json` had, so that a
/// hard reset is one call and a support engineer clearing "the credentials"
/// clears one thing. [PosDbSecretStore], the single-secret contract every
/// consumer was written against, is unchanged: [KeyedSecretStore] lends one
/// key of this store to it, so nothing that reads a password learned that the
/// storage moved.
///
/// Which store is chosen is [forPlatform]'s decision and nobody else's (ADR-006:
/// DPAPI on Windows, Keychain on macOS, **no plaintext fallback**). A store that
/// cannot answer throws [SecretStoreUnavailable]; it never quietly hands over to
/// another store, because a fallback is exactly how a password ends up back in
/// a JSON file on a machine whose keychain was locked for one morning.
abstract class SecretStore {
  /// The value under [key], or null when there is none. Throws
  /// [SecretStoreUnavailable] when the store could not be asked — which is not
  /// the same answer as null, and the boot path needs to tell them apart.
  Future<String?> read(String key);

  /// Keep [value] under [key], replacing what was there.
  Future<void> write(String key, String value);

  /// Remove [key]. Removing what is not there is not an error.
  Future<void> delete(String key);

  /// Remove every secret this till keeps — the hard reset.
  Future<void> deleteAll();

  /// Whether the operating system protects what this store holds.
  ///
  /// False only for [DevelopmentFileSecretStore]. The legacy migration asks it:
  /// moving `secrets.json` into a store that *is* `secrets.json` would wipe the
  /// only copy.
  bool get protectedByOperatingSystem;

  /// What a technician should be told this store is, in an error message.
  String get description;

  /// The store this machine must use.
  ///
  /// [platform] is a parameter so the choice itself is testable on the Linux
  /// machine the tests run on; production passes nothing and gets
  /// [SecretPlatform.host]. [directory] is where the DPAPI ciphertext and the
  /// development file live (Application Support by default); the Keychain
  /// needs none.
  ///
  /// There is deliberately no `try` here and no second choice. A Windows or
  /// macOS till whose store is broken finds out on its first read, as a
  /// [SecretStoreUnavailable] the setup wizard shows; it never finds out by
  /// discovering, a year later, that its passwords were in a file all along.
  static SecretStore forPlatform({
    SecretPlatform? platform,
    Future<Directory> Function()? directory,
  }) => switch (platform ?? SecretPlatform.host) {
    SecretPlatform.windows => WindowsDpapiSecretStore(directory: directory),
    SecretPlatform.macos => MacKeychainSecretStore(),
    SecretPlatform.development => DevelopmentFileSecretStore(
      directory: directory,
    ),
  };
}

/// Which family of secret store an operating system gets.
///
/// An enum rather than `Platform.isWindows` at the call site, so the factory's
/// one rule — plaintext only where nobody sells — is a switch the compiler
/// checks and a test can drive.
enum SecretPlatform {
  windows,
  macos,

  /// Linux and anything else: a developer's machine or a test run. XOrder POS
  /// ships for Windows and macOS only, so no till lands here.
  development;

  static SecretPlatform get host {
    if (Platform.isWindows) return SecretPlatform.windows;
    if (Platform.isMacOS) return SecretPlatform.macos;
    return SecretPlatform.development;
  }
}

/// The operating system's secret store refused, or could not be reached.
///
/// A [PosDbSecretStoreException], so every caller that already handled a
/// refusing store — the setup wizard's `complete()`, the terminal reset —
/// handles this one with no change, and shows its [toString].
///
/// **Never carries the secret.** [cause] is a platform status or a file error;
/// a message built from the value being stored would put the password in the
/// wizard's error banner and in whatever screenshot is sent to support.
class SecretStoreUnavailable extends PosDbSecretStoreException {
  const SecretStoreUnavailable({
    required this.store,
    required this.operation,
    required Object cause,
  }) : super(cause);

  /// Which store, for the technician: "Windows DPAPI", "macOS Keychain".
  final String store;

  /// What was being attempted: read, write, delete.
  final String operation;

  @override
  String toString() => '$store could not $operation a saved credential: $cause';
}

/// One key of a [SecretStore], seen through the single-secret contract.
///
/// Read failures land in [lastFailure] and read as null rather than throwing:
/// that is the [PosDbSecretStore] contract, and the boot path depends on it —
/// `main()` restores every secret before the first frame, and a throw there is
/// a blank window instead of the wizard's "this machine cannot store the
/// password" warning. Writes and clears throw, because the person who asked to
/// save is standing there and must see that it did not happen.
class KeyedSecretStore implements PosDbSecretStore {
  KeyedSecretStore(this.store, this.key);

  final SecretStore store;
  final String key;

  @override
  Object? get lastFailure => _lastFailure;
  Object? _lastFailure;

  @override
  Future<String?> read() async {
    try {
      final value = await store.read(key);
      _lastFailure = null;
      return (value?.isEmpty ?? true) ? null : value;
    } on SecretStoreUnavailable catch (error) {
      _lastFailure = error;
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    // An empty secret is no secret — `FileSecretStore` read one back as null,
    // and keeping that meaning saves the OS store an entry nobody can use.
    if (value.isEmpty) return clear();
    try {
      await store.write(key, value);
      _lastFailure = null;
    } on SecretStoreUnavailable catch (error) {
      _lastFailure = error;
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await store.delete(key);
      _lastFailure = null;
    } on SecretStoreUnavailable catch (error) {
      _lastFailure = error;
      rethrow;
    }
  }
}

/// `secrets.json`, kept for the machines nobody sells on: Linux, a developer's
/// workstation, a test run.
///
/// **Plaintext, and named for it.** [SecretStore.forPlatform] hands this out
/// only for [SecretPlatform.development]; a Windows or macOS till cannot reach
/// it. It wraps [FileSecretStore] rather than replacing it, so the file format
/// a developer's machine already has keeps working, and so the legacy
/// migration reads exactly the file this writes.
class DevelopmentFileSecretStore implements SecretStore {
  DevelopmentFileSecretStore({Future<Directory> Function()? directory})
    : _directory = directory;

  final Future<Directory> Function()? _directory;

  FileSecretStore _entry(String key) =>
      FileSecretStore(key: key, directory: _directory);

  @override
  bool get protectedByOperatingSystem => false;

  @override
  String get description => 'Development secrets file (plaintext)';

  SecretStoreUnavailable _refused(String operation, Object cause) =>
      SecretStoreUnavailable(
        store: description,
        operation: operation,
        cause: cause,
      );

  @override
  Future<String?> read(String key) async {
    final entry = _entry(key);
    final value = await entry.read();
    // FileSecretStore answers a file it could not open with null and a
    // `lastFailure`; this contract answers it with a throw.
    if (entry.lastFailure case final failure?) throw _refused('read', failure);
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _entry(key).write(value);
    } on PosDbSecretStoreException catch (error) {
      throw _refused('write', error.cause);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _entry(key).clear();
    } on PosDbSecretStoreException catch (error) {
      throw _refused('delete', error.cause);
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      await _entry(FileSecretStore.databasePasswordKey).deleteFile();
    } on PosDbSecretStoreException catch (error) {
      throw _refused('delete', error.cause);
    }
  }
}
