import '../config/pos_db_secret_store.dart';

/// Holds the terminal's device token (POS-BE-011, Option C).
///
/// The token is the till's own credential — `xdt_…`, issued exactly once at
/// claim or register, no TTL, killed only by terminal revocation. It follows
/// the same storage rules as the database password and reuses the same keystore
/// contract: memory is the read path (the API client asks on every request),
/// and the OS store (DPAPI on Windows, the Keychain on macOS; see
/// `SecretStore.forPlatform`) is the persistence. Plaintext in a file is never
/// an option on a till — a bearer token in `config.json` is a bearer token in
/// a support email.
///
/// With no [store] — tests, and the wizard before its first save — this is
/// purely in-memory, lost on exit.
class DeviceTokenVault {
  DeviceTokenVault({this.store});

  final PosDbSecretStore? store;

  String? _token;

  bool get isSet => _token?.isNotEmpty ?? false;

  /// Synchronous read for the request path. [restore] must have run at boot.
  String? get token => _token;

  /// Accept a token just issued by claim/register and persist it immediately —
  /// the server shows it exactly once, so "hold it in memory and save later"
  /// is a crash away from a till that has to be re-paired.
  Future<void> accept(String token) async {
    if (token.isEmpty) return;
    _token = token;
    await store?.write(token);
  }

  /// Load the saved token at boot. Does not overwrite one already set.
  Future<void> restore() async {
    if (isSet) return;
    _token = await store?.read();
  }

  /// Forget the token here and in the keystore — terminal reset, or the server
  /// answering `DEVICE_TOKEN_INVALID` after a rotation this till missed.
  Future<void> forget() async {
    _token = null;
    await store?.clear();
  }
}
