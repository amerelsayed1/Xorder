import 'dart:convert';

import '../../../core/config/deployment.dart';
import '../domain/license.dart';
import '../domain/license_verifier.dart';
import 'license_store.dart';

/// Fetches, verifies and persists licences.
abstract interface class LicenceService {
  /// Whether typing a key can fetch a licence at all.
  ///
  /// False when there is no licence server to ask — which is the situation
  /// today. The wizard reads this rather than offering a button that always
  /// fails: an installer who taps *Activate online* three times before reading
  /// the error has been misled by the interface, not helped by it.
  bool get canActivateOnline;

  /// Online activation: exchange a human-typed key for a signed licence.
  Future<LicenseFile?> fetchByKey(String key, DeploymentConfig deployment);

  Future<LicenseEntitlement> evaluate(LicenseFile file, DeploymentConfig deployment);

  Future<void> store(LicenseFile file);

  /// The entitlement for whatever is currently installed. Called at boot and
  /// again before each shift opens.
  Future<LicenseEntitlement> current(DeploymentConfig deployment);
}

/// Outcome of an activation attempt, so both callers report failures the same way.
class LicenceActivationResult {
  const LicenceActivationResult({this.entitlement, this.notice});

  final LicenseEntitlement? entitlement;

  /// What went wrong, as data. Rendered by `app/labels.dart` in whichever
  /// language the till was set up in — see [LicenceNotice].
  final LicenceNotice? notice;

  /// Whether a licence was parsed and stored at all, healthy or not.
  bool get installed => entitlement != null;

  /// Whether the installed licence actually restores normal operation.
  ///
  /// Keyed on `canOpenShift`, not `canSell`: an expired licence still permits
  /// selling inside an open shift, so `canSell` would report a failed renewal
  /// as a success — which is exactly the case the operator is trying to fix.
  bool get succeeded => entitlement?.canOpenShift ?? false;
}

/// One activation path, shared by first-run setup and by later renewal.
///
/// Both surfaces resolve a key or a file, evaluate it and persist it. Keeping
/// that in one place means a renewal cannot drift from an activation — the two
/// are the same operation performed at different times.
extension LicenceActivation on LicenceService {
  Future<LicenceActivationResult> activate({
    required DeploymentConfig deployment,
    String? key,
    String? fileContents,
  }) async {
    if (fileContents == null && !canActivateOnline) {
      // Saying "that key was not recognised" here would send the operator
      // hunting for a typo in a key that nothing was ever going to check.
      return const LicenceActivationResult(notice: NoLicenceServer());
    }

    final file = fileContents != null
        ? LicenseFile.tryParse(fileContents)
        : await fetchByKey(key ?? '', deployment);

    if (file == null) {
      return LicenceActivationResult(
        notice: fileContents != null
            ? const NotALicenceFile()
            : const LicenceKeyNotRecognised(),
      );
    }

    final entitlement = await evaluate(file, deployment);

    // Persist even a licence that does not permit trade: the operator needs the
    // status screen to show what they actually installed, and an expired
    // licence is still the record of what this terminal is entitled to.
    await store(file);

    return LicenceActivationResult(
      entitlement: entitlement,
      notice: entitlement.canOpenShift ? null : entitlement.notice,
    );
  }
}

class DefaultLicenceService implements LicenceService {
  DefaultLicenceService({
    required this.verifier,
    required this.store_,
    required this.fingerprint,
    required this.clock,
    this.remote,
  });

  final LicenseVerifier verifier;
  final LicenseStore store_;
  final TerminalFingerprint fingerprint;

  /// Injected so licence expiry is testable without waiting a year, and so the
  /// app never silently trusts a wrong system clock.
  final DateTime Function() clock;

  /// Null in standalone mode — there is nothing to ask.
  final Future<LicenseFile?> Function(String key)? remote;

  @override
  bool get canActivateOnline => remote != null;

  @override
  Future<LicenseFile?> fetchByKey(String key, DeploymentConfig deployment) async {
    if (remote == null || key.trim().isEmpty) return null;
    return remote!(key.trim());
  }

  @override
  Future<LicenseEntitlement> evaluate(
    LicenseFile file,
    DeploymentConfig deployment,
  ) async =>
      verifier.evaluate(
        file: file,
        deployment: deployment,
        now: clock(),
        terminalFingerprint: await fingerprint.value(),
      );

  @override
  Future<void> store(LicenseFile file) => store_.write(file);

  @override
  Future<LicenseEntitlement> current(DeploymentConfig deployment) async =>
      verifier.evaluate(
        file: await store_.read(),
        deployment: deployment,
        now: clock(),
        terminalFingerprint: await fingerprint.value(),
      );
}

/// Development licence issuer.
///
/// Mints a **self-signed** licence with a keypair generated at runtime, so the
/// wizard is walkable end to end before a real licence server exists. It is
/// wired only in debug builds — see `licenceServiceProvider`.
class FakeLicenceService implements LicenceService {
  FakeLicenceService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  LicenseFile? _stored;

  @override
  bool get canActivateOnline => true;

  /// Any non-empty key activates, with the term implied by the key so the
  /// wizard's warning and grace states can be demonstrated:
  ///   * a key containing `EXPIRED` → past grace
  ///   * a key containing `GRACE`   → inside grace
  ///   * a key containing `SOON`    → inside the warning window
  ///   * anything else              → a healthy one-year term
  @override
  Future<LicenseFile?> fetchByKey(String key, DeploymentConfig deployment) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (key.trim().isEmpty) return null;

    final now = _clock();
    final expiresAt = switch (key.toUpperCase()) {
      final k when k.contains('EXPIRED') => now.subtract(const Duration(days: 60)),
      final k when k.contains('GRACE') => now.subtract(const Duration(days: 3)),
      final k when k.contains('SOON') => now.add(const Duration(days: 9)),
      _ => now.add(const Duration(days: 365)),
    };

    final claims = LicenseClaims(
      licenseId: 'dev-${key.hashCode.abs()}',
      tenantSlug: deployment.tenantSlug ?? 'mahsoub',
      tenantName: 'Mahsoub Grill',
      issuedAt: now.subtract(const Duration(days: 1)),
      expiresAt: expiresAt,
      maxTerminals: 4,
      features: const {'pos', 'dine_in', 'delivery'},
      modes: DeploymentMode.values.toSet(),
      plan: 'Restaurant Pro',
    );

    return LicenseFile(
      payloadB64: base64Url.encode(utf8.encode(jsonEncode(claims.toJson()))),
      signatureB64: base64Url.encode(List<int>.filled(64, 0)),
      keyId: 'dev',
    );
  }

  /// Skips the signature check — this is the development issuer, and its
  /// signature is a placeholder. Policy is still evaluated in full so the
  /// wizard exercises the real expiry, grace and scope logic.
  @override
  Future<LicenseEntitlement> evaluate(
    LicenseFile file,
    DeploymentConfig deployment,
  ) async {
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
      now: _clock(),
    );
  }

  @override
  Future<void> store(LicenseFile file) async => _stored = file;

  @override
  Future<LicenseEntitlement> current(DeploymentConfig deployment) async {
    final file = _stored;
    if (file == null) {
      return const LicenseEntitlement(
        state: LicenseState.missing,
        canOpenShift: false,
        canSell: false,
        canChangeConfiguration: false,
        notice: LicenceMissing(),
      );
    }
    return evaluate(file, deployment);
  }
}
