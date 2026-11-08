import '../../../core/config/deployment.dart';
import '../domain/license.dart';
import '../domain/license_verifier.dart';
import 'licence_service.dart';

/// The licence a main device shares with its children, as a child reads it.
///
/// A child tablet activates nothing of its own (see `TerminalRole`). The main
/// device writes its signed licence into the database they share, and this is
/// that row: the file itself, which business it belongs to, and the mode the
/// main device runs in — a child runs in whatever its main device does.
class SiteLicence {
  const SiteLicence({
    required this.file,
    required this.businessId,
    required this.mode,
    this.terminalCount = 0,
  });

  final LicenseFile file;
  final int businessId;
  final DeploymentMode mode;

  /// Terminals already registered to the business, the main device among
  /// them. What makes `max_terminals` a count the child can actually check
  /// rather than the advisory number it is on a lone till.
  final int terminalCount;
}

/// Where the shared licence lives. The PostgreSQL implementation is
/// `PostgresSiteLicence`; nothing here touches the driver.
abstract interface class SiteLicenceSource {
  /// The licence the main device published, or null when it has published
  /// none yet. [businessId] narrows it once the child knows which business
  /// it belongs to; before that — while it is still being set up — the most
  /// recent one is the only one there is.
  Future<SiteLicence?> read({int? businessId});

  /// Called on the main device only, whenever its licence is (re)installed.
  Future<void> publish({
    required int businessId,
    required LicenseFile file,
    required DeploymentMode mode,
  });
}

/// For tests and for a child whose database is not configured yet.
class InMemorySiteLicenceSource implements SiteLicenceSource {
  InMemorySiteLicenceSource([this.licence]);

  SiteLicence? licence;

  @override
  Future<SiteLicence?> read({int? businessId}) async => licence;

  @override
  Future<void> publish({
    required int businessId,
    required LicenseFile file,
    required DeploymentMode mode,
  }) async => licence = SiteLicence(
    file: file,
    businessId: businessId,
    mode: mode,
    terminalCount: licence?.terminalCount ?? 0,
  );
}

/// The licence service on a child terminal.
///
/// Reads the main device's licence instead of a file on this machine, and
/// judges it with [LicenseVerifier.evaluateClaims]'s `viaMainDevice` — so the
/// signature, tenant, mode and dates are all checked, and the main device's
/// fingerprint pin is not held against a tablet that was never going to match
/// it.
///
/// Activation is closed on purpose. A licence typed into a child would be a
/// second licence for the same business, pinned to the device most likely to
/// leave the building; a child is renewed by renewing the main device.
class SiteLicenceService implements LicenceService {
  SiteLicenceService({
    required this.source,
    required this.verifySignature,
    required this.clock,
    this.businessId,
    this.keyId,
  });

  final SiteLicenceSource source;
  final Future<bool> Function(LicenseFile file) verifySignature;

  /// The key id this build verifies with — see [LicenseVerifier.keyId].
  final String? keyId;
  final DateTime Function() clock;
  final int? businessId;

  @override
  bool get canActivateOnline => false;

  @override
  Future<LicenceFetch> fetchByKey(
    String key,
    DeploymentConfig deployment,
  ) async => const LicenceFetch.failed(NoLicenceServer());

  @override
  Future<LicenseEntitlement> evaluate(
    LicenseFile file,
    DeploymentConfig deployment,
  ) async {
    if (!await verifySignature(file)) {
      return LicenseEntitlement(
        state: LicenseState.invalid,
        canOpenShift: false,
        canSell: false,
        canChangeConfiguration: false,
        notice: LicenceUnverifiable(signedWith: file.keyId, holds: keyId),
      );
    }
    final claims = LicenseVerifier.claimsOf(file);
    if (claims == null) {
      return const LicenseEntitlement(
        state: LicenseState.invalid,
        canOpenShift: false,
        canSell: false,
        canChangeConfiguration: false,
        notice: LicenceFileDamaged(),
      );
    }
    return LicenseVerifier.evaluateClaims(
      claims: claims,
      deployment: deployment,
      now: clock(),
      viaMainDevice: true,
    );
  }

  /// Nothing is stored on a child. See the class comment.
  @override
  Future<void> store(LicenseFile file) async {}

  /// A database that cannot be reached is let through as an error rather than
  /// reported as "not licensed": the till cannot sell without that database
  /// anyway, and the connection failure is the thing worth reading.
  @override
  Future<LicenseEntitlement> current(DeploymentConfig deployment) async {
    final site = await source.read(businessId: businessId);
    if (site == null) {
      return const LicenseEntitlement(
        state: LicenseState.missing,
        canOpenShift: false,
        canSell: false,
        canChangeConfiguration: false,
        notice: LicenceMissing(),
      );
    }
    return evaluate(site.file, deployment);
  }

  @override
  Future<LicenseFile?> installed() async =>
      (await source.read(businessId: businessId))?.file;
}
