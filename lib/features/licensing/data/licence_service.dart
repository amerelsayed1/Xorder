import 'dart:convert';

import '../../../core/config/deployment.dart';
import '../domain/license.dart';
import '../domain/license_verifier.dart';
import 'license_store.dart';

/// Fetches, verifies and persists licences.
abstract interface class LicenceService {
  /// Whether typing a key can fetch a licence at all.
  ///
  /// A property of the **build**, not of the deployment mode: an offline
  /// terminal still activates and renews against the hosted platform, and it is
  /// only the *sales* that stay in the building. The wizard reads this rather
  /// than offering a button that always fails: an installer who taps *Activate
  /// online* three times before reading the error has been misled by the
  /// interface, not helped by it.
  bool get canActivateOnline;

  /// Online activation: exchange a human-typed key for a signed licence — or
  /// for the reason there isn't one. See [LicenceFetch].
  Future<LicenceFetch> fetchByKey(String key, DeploymentConfig deployment);

  Future<LicenseEntitlement> evaluate(
    LicenseFile file,
    DeploymentConfig deployment,
  );

  Future<void> store(LicenseFile file);

  /// The entitlement for whatever is currently installed. Called at boot and
  /// again before each shift opens.
  Future<LicenseEntitlement> current(DeploymentConfig deployment);

  /// The licence file currently installed, or null if there is none.
  ///
  /// Separate from [current] because the *claims* are needed, not just the
  /// verdict: the wizard runs on `tenant_slug`, `modes` and `max_terminals`,
  /// and an entitlement carries none of them.
  Future<LicenseFile?> installed();
}

/// What an activation attempt actually learned.
///
/// The HTTP layer used to return `LicenseFile?` and collapse every failure into
/// null, which the wizard then reported as an unrecognised key. Unreachable
/// platform, wrong platform, throttled, server error and genuinely-unknown key
/// are five different problems with five different fixes, and an installer
/// standing in a restaurant cannot guess which one they have from one sentence
/// that names only the least likely of them.
class LicenceFetch {
  const LicenceFetch.found(this.file) : notice = null;
  const LicenceFetch.failed(this.notice) : file = null;

  final LicenseFile? file;
  final LicenceNotice? notice;
}

/// Outcome of an activation attempt, so both callers report failures the same way.
class LicenceActivationResult {
  const LicenceActivationResult({this.entitlement, this.claims, this.notice});

  final LicenseEntitlement? entitlement;

  /// The claims inside the file that was just installed.
  ///
  /// Carried out of activation because the **setup wizard now runs on them**:
  /// `tenant_slug` supplies the tenant the account step signs into, and `modes`
  /// and `max_terminals` decide which deployments the connection step may
  /// offer. Null when nothing parsed.
  final LicenseClaims? claims;

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
  /// Adopt the licence already on this machine, without reinstalling it.
  ///
  /// A licence survives a restart — it is a file — but the wizard's draft does
  /// not. Without this, an installer who activated and then restarted mid-setup
  /// was asked to paste the same licence again, while the valid one sat on disk
  /// three directories away.
  ///
  /// Deliberately does not call `store`: nothing changed, and rewriting the
  /// file on every wizard launch would put a working licence at the mercy of a
  /// disk error.
  Future<LicenceActivationResult> restore(DeploymentConfig deployment) async {
    final file = await installed();
    if (file == null) return const LicenceActivationResult();

    final entitlement = await evaluate(file, deployment);

    return LicenceActivationResult(
      entitlement: entitlement,
      claims: LicenseVerifier.claimsOf(file),
      notice: entitlement.canOpenShift ? null : entitlement.notice,
    );
  }

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

    // A file is parsed here; a key goes to the platform, which now answers
    // with a REASON rather than a bare null — see LicenceFetch.
    final LicenceFetch fetched;
    if (fileContents != null) {
      final parsed = LicenseFile.tryParse(fileContents);
      fetched = parsed == null
          ? const LicenceFetch.failed(NotALicenceFile())
          : LicenceFetch.found(parsed);
    } else {
      fetched = await fetchByKey(key ?? '', deployment);
    }

    final file = fetched.file;

    if (file == null) {
      return LicenceActivationResult(notice: fetched.notice);
    }

    final entitlement = await evaluate(file, deployment);

    // Persist even a licence that does not permit trade: the operator needs the
    // status screen to show what they actually installed, and an expired
    // licence is still the record of what this terminal is entitled to.
    await store(file);

    return LicenceActivationResult(
      entitlement: entitlement,
      claims: LicenseVerifier.claimsOf(file),
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

  /// Bound to the hosted platform in every mode — see `PlatformEndpoint`. Null
  /// only in tests that must never touch the network.
  final Future<LicenceFetch> Function(String key, String terminalFingerprint)?
  remote;

  @override
  bool get canActivateOnline => remote != null;

  @override
  Future<LicenceFetch> fetchByKey(
    String key,
    DeploymentConfig deployment,
  ) async {
    if (remote == null) {
      return const LicenceFetch.failed(NoLicenceServer());
    }
    if (key.trim().isEmpty) {
      return const LicenceFetch.failed(LicenceKeyNotRecognised());
    }
    return remote!(key.trim(), await fingerprint.value());
  }

  @override
  Future<LicenseEntitlement> evaluate(
    LicenseFile file,
    DeploymentConfig deployment,
  ) async => verifier.evaluate(
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

  @override
  Future<LicenseFile?> installed() => store_.read();
}

/// Development licence issuer.
///
/// Mints a **self-signed** licence with a keypair generated at runtime, so the
/// wizard is walkable end to end before a real licence server exists. It is
/// wired only in debug builds — see `licenceServiceProvider`.
class FakeLicenceService implements LicenceService {
  FakeLicenceService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

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
  Future<LicenceFetch> fetchByKey(
    String key,
    DeploymentConfig deployment,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (key.trim().isEmpty) {
      return const LicenceFetch.failed(LicenceKeyNotRecognised());
    }

    final now = _clock();
    final expiresAt = switch (key.toUpperCase()) {
      final k when k.contains('EXPIRED') => now.subtract(
        const Duration(days: 60),
      ),
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

    return LicenceFetch.found(
      LicenseFile(
        payloadB64: base64Url.encode(utf8.encode(jsonEncode(claims.toJson()))),
        signatureB64: base64Url.encode(List<int>.filled(64, 0)),
        keyId: 'dev',
      ),
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
  Future<LicenseFile?> installed() async => _stored;

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
