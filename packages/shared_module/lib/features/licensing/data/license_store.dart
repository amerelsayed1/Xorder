import '../domain/license_verifier.dart';

/// Where the installed licence lives between launches.
///
/// A licence is not a secret — it is signed, public-verifiable, and reveals
/// nothing an attacker could not read off the screen — so it does not need the
/// OS keychain. It does need to survive an app update, which is why it is a
/// file rather than a preference.
abstract interface class LicenseStore {
  Future<LicenseFile?> read();
  Future<void> write(LicenseFile file);
  Future<void> clear();
}

/// A stable, non-identifying fingerprint for this machine.
///
/// Used only to pin a licence to a terminal. Deliberately derived from hardware
/// identifiers rather than anything about the user, and hashed before it leaves
/// the device — the licence server has no business knowing the operator's
/// machine name.
abstract interface class TerminalFingerprint {
  Future<String> value();
}

/// In-memory implementation used by the wizard's dry-run and by tests.
class InMemoryLicenseStore implements LicenseStore {
  InMemoryLicenseStore([this._file]);

  LicenseFile? _file;

  @override
  Future<LicenseFile?> read() async => _file;

  @override
  Future<void> write(LicenseFile file) async => _file = file;

  @override
  Future<void> clear() async => _file = null;
}

class FakeTerminalFingerprint implements TerminalFingerprint {
  const FakeTerminalFingerprint([this.fingerprint = 'test-terminal']);

  final String fingerprint;

  @override
  Future<String> value() async => fingerprint;
}
