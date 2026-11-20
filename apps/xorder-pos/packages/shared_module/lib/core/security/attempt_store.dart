import '../../data/config/secret_store.dart';

/// Where an [AttemptLimiter] keeps its count between runs of the app, so that
/// closing and reopening the till is not a way to get five fresh guesses
/// (security audit F1, tablet-cloud-onboarding).
///
/// One string in, one string out: the limiter owns the format, the store only
/// keeps it. Kept apart from the limiter so the rule stays pure Dart and its
/// tests need neither a disk nor a keychain.
abstract class AttemptStore {
  /// What [write] last kept, or null when nothing was.
  Future<String?> read();

  Future<void> write(String snapshot);
}

/// Keeps the count in the till's own secret store — the Android Keystore on a
/// tablet, DPAPI on Windows, the Keychain on macOS — under one key, so a file
/// copied or edited from outside the app cannot reset or forge it.
///
/// A hard reset (`SecretStore.deleteAll`) clears it too. That reset is itself
/// behind a verified credential, so it is not a free way round the lockout.
class SecretAttemptStore implements AttemptStore {
  const SecretAttemptStore(this._secrets, {this.key = defaultKey});

  final SecretStore _secrets;
  final String key;

  static const defaultKey = 'sign_in_attempts';

  @override
  Future<String?> read() => _secrets.read(key);

  @override
  Future<void> write(String snapshot) => _secrets.write(key, snapshot);
}

/// Keeps it in memory only — what a limiter had before, and what tests use.
class MemoryAttemptStore implements AttemptStore {
  MemoryAttemptStore([this.snapshot]);

  String? snapshot;

  @override
  Future<String?> read() async => snapshot;

  @override
  Future<void> write(String value) async => snapshot = value;
}
