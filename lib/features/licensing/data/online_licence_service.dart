import '../../../core/config/deployment.dart';
import '../../../data/cloud/cloud_api.dart';
import '../domain/license.dart';
import '../domain/license_verifier.dart';
import '../domain/online_verdict.dart';
import 'licence_check_store.dart';
import 'licence_service.dart';
import 'license_store.dart';

/// The online licence check for a connected till (POS-BE-031).
///
/// **A decorator, not a replacement.** Activation, import, storage and the
/// signed-file evaluation all stay with [inner] — an islanded till, a till the
/// platform says is `offline`, and a till that has never been told either way
/// keep exactly the path they had. Only [current], the verdict the start
/// screen gates a new shift on, changes, and only once the platform has said
/// this till is `online`.
///
/// **Never asks an endpoint it has not been told exists.** `enforcement` is
/// learned from the claim bundle and from each check reply; until then the
/// till asks once, and only a real 200 moves it onto this path. A 404 that is
/// not the agreed `licence_not_found` is an older platform with no such route,
/// and leaves the till on its file.
///
/// **Never blocks on the network.** The start screen treats a verdict still
/// loading as permitted, so a slow check costs nothing; a failed one falls
/// back to the last definite verdict for as long as that verdict says it may
/// be trusted (72h by default, never more than 7 days), and past that stops
/// the *next* shift only — see [OnlineVerdict].
class OnlineLicenceService implements LicenceService {
  OnlineLicenceService({
    required this.inner,
    required this.checks,
    required this.check,
    required this.fingerprint,
    required this.clock,
    this.appVersion,
  });

  final LicenceService inner;
  final LicenceCheckStore checks;

  /// `POST /api/pos/license/check` on the device credential.
  final Future<CloudReply> Function(Map<String, Object?> body) check;
  final TerminalFingerprint fingerprint;
  final DateTime Function() clock;
  final String? appVersion;

  @override
  bool get canActivateOnline => inner.canActivateOnline;

  @override
  Future<LicenceFetch> fetchByKey(String key, DeploymentConfig deployment) =>
      inner.fetchByKey(key, deployment);

  @override
  Future<LicenseEntitlement> evaluate(
    LicenseFile file,
    DeploymentConfig deployment,
  ) => inner.evaluate(file, deployment);

  @override
  Future<void> store(LicenseFile file) => inner.store(file);

  @override
  Future<LicenseFile?> installed() => inner.installed();

  @override
  Future<LicenseEntitlement> current(DeploymentConfig deployment) async {
    final record = await checks.read() ?? const LicenceCheckRecord();
    // Told it is islanded: the file is the whole truth, and asking would only
    // be noise in the platform's logs.
    if (record.enforcement == 'offline') return inner.current(deployment);

    final reply = await _ask(deployment);
    final now = clock();

    if (reply != null && reply.ok) {
      final verdict = OnlineVerdict.tryParse(reply.body);
      final enforcement = reply.body['enforcement'];
      if (enforcement == 'offline') {
        await _save(record.copyWith(enforcement: 'offline'));
        return inner.current(deployment);
      }
      if (verdict != null && verdict.isDefinite) {
        await _save(
          record.copyWith(
            enforcement: 'online',
            verdict: verdict,
            checkedAt: now,
          ),
        );
        return verdict.entitlement(now);
      }
      // A 200 this build cannot read, or `unknown`: not an answer. Fall
      // through to what was last known.
    } else if (reply?.status == 404 && reply?.code == OnlineVerdict.notIssued) {
      const verdict = OnlineVerdict(status: OnlineVerdict.notIssued);
      await _save(
        record.copyWith(
          enforcement: 'online',
          verdict: verdict,
          checkedAt: now,
        ),
      );
      return verdict.entitlement(now);
    }

    // No answer: offline, throttled, a server error, a credential problem
    // (re-pairing is the heartbeat's to report), or an older platform. A till
    // already on the online path trusts its cache; one that never got there
    // keeps its file.
    if (record.isOnline) {
      final cached = record.fromCache(now);
      if (cached != null) return cached;
    }
    return inner.current(deployment);
  }

  Future<CloudReply?> _ask(DeploymentConfig deployment) async {
    try {
      final file = await inner.installed();
      final expires = file == null
          ? null
          : LicenseVerifier.claimsOf(file)?.expiresAt;
      return await check({
        'fingerprint': await fingerprint.value(),
        'deployment_mode': deployment.mode.wire,
        'app_version': ?appVersion,
        'licence_expires_at': ?expires?.toUtc().toIso8601String(),
      });
    } on Object {
      return null;
    }
  }

  /// A cache that cannot be written costs the next offline launch its
  /// fallback, never this answer.
  Future<void> _save(LicenceCheckRecord record) async {
    try {
      await checks.write(record);
    } on Object {
      // See above.
    }
  }
}
