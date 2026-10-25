/// Where the till's PostgreSQL password is kept between launches.
///
/// The OS store: DPAPI on Windows, the Keychain on macOS (ADR-006), reached
/// through `KeyedSecretStore` over `SecretStore.forPlatform()` in
/// `secret_store.dart`. Both tie the secret to this machine and this user, the
/// property a plain file cannot have — a `config.json` with a password in it
/// is a password that ends up in a support email. Only a development machine
/// (Linux, a test run) gets a plaintext file, and it is named for it.
///
/// **Pure Dart, deliberately.** The implementations resolve their folder
/// through `path_provider`, which needs Flutter; this contract must not,
/// because `pos_database.dart` depends on it and `bin/pos_migrate.dart` runs
/// that from a plain `dart run`, where `dart:ui` does not exist. Keeping the
/// two apart is what stops a keystore import from breaking the install-time
/// migration tool.
abstract interface class PosDbSecretStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();

  /// The last platform error, or null when the store is working.
  ///
  /// On the contract rather than on one implementation because the boot path has
  /// to ask it through the interface. Without it, "this is a fresh install" and
  /// "this machine's keystore is broken" arrive at the wizard as the same empty
  /// password field — and they need opposite responses from the person standing
  /// at the till. `Object?` keeps this file free of any Flutter type, which is
  /// what lets `bin/pos_migrate.dart` still import the chain.
  Object? get lastFailure;
}

/// A store refused a write or a clear.
///
/// Lives beside the contract rather than in one binding because every
/// implementation throws it, and this file is the only one both a Flutter app
/// and a plain `dart run` can import.
class PosDbSecretStoreException implements Exception {
  const PosDbSecretStoreException(this.cause);

  final Object cause;

  @override
  String toString() => 'The credential store refused the operation: $cause';
}
