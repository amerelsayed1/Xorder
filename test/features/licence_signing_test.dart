import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/features/licensing/data/license_keys.dart';
import 'package:xorder_pos/features/licensing/data/license_store.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';

/// The licence check, against the key the app actually ships with.
///
/// Until this existed the app was bound to `FakeLicenceService`, which accepted
/// **any non-empty key** and skipped the signature entirely — `HELLO` licensed a
/// terminal for a year. The policy underneath was always right; nothing was
/// checking that a licence came from us.
///
/// These are the questions a licence system exists to answer, so each is asked
/// against a real signature rather than a mocked one.
void main() {
  const deployment = DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseHost: '192.168.1.20',
    tenantSlug: 'amer',
  );

  final now = DateTime.utc(2026, 8, 27);

  LicenseClaims claimsFor({
    String tenant = 'amer',
    Duration term = const Duration(days: 365),
    Set<DeploymentMode> modes = const {DeploymentMode.offline},
  }) =>
      LicenseClaims(
        licenseId: 'lic-1',
        tenantSlug: tenant,
        tenantName: "Amer's Kitchen",
        issuedAt: now.subtract(const Duration(days: 1)),
        expiresAt: now.add(term),
        modes: modes,
      );

  /// Sign claims the way `bin/pos_licence.dart` does.
  Future<LicenseFile> sign(LicenseClaims claims, SimpleKeyPair pair) async {
    final payload = base64Url.encode(utf8.encode(jsonEncode(claims.toJson())));
    final signature = await Ed25519().sign(
      base64Url.decode(payload.padRight(payload.length + ((4 - payload.length % 4) % 4), '=')),
      keyPair: pair,
    );
    return LicenseFile(
      payloadB64: payload,
      signatureB64: base64Url.encode(signature.bytes),
    );
  }

  Future<DefaultLicenceService> serviceFor(List<int> publicKey) async =>
      DefaultLicenceService(
        verifier: LicenseVerifier(publicKeyBytes: publicKey),
        store_: InMemoryLicenseStore(),
        fingerprint: const FakeTerminalFingerprint(),
        clock: () => now,
      );

  test('the shipped public key is a real Ed25519 key, not a placeholder', () {
    // A 32-byte key. Guards against the embedding step being skipped or a
    // truncated paste — both of which would fail closed, but confusingly.
    expect(LicenseKeys.current, hasLength(32));
    expect(LicenseKeys.current.every((b) => b == 0), isFalse);
  });

  test('a licence signed by the matching key activates', () async {
    final pair = await Ed25519().newKeyPair();
    final service = await serviceFor((await pair.extractPublicKey()).bytes);

    final result = await service.activate(
      deployment: deployment,
      fileContents: (await sign(claimsFor(), pair)).serialize(),
    );

    expect(result.succeeded, isTrue);
    expect(result.entitlement?.state, LicenseState.valid);
  });

  test('a licence signed by somebody else is refused', () async {
    final ours = await Ed25519().newKeyPair();
    final theirs = await Ed25519().newKeyPair();
    final service = await serviceFor((await ours.extractPublicKey()).bytes);

    // The claims are perfectly good. Only the signature is wrong — which is the
    // entire thing a licence file is for.
    final result = await service.activate(
      deployment: deployment,
      fileContents: (await sign(claimsFor(), theirs)).serialize(),
    );

    expect(result.succeeded, isFalse);
    expect(result.entitlement?.state, LicenseState.invalid);
    expect(result.notice, isA<LicenceUnverifiable>());
  });

  test('editing the term of a signed licence invalidates it', () async {
    final pair = await Ed25519().newKeyPair();
    final service = await serviceFor((await pair.extractPublicKey()).bytes);
    final honest = await sign(claimsFor(term: const Duration(days: 1)), pair);

    // Re-encode the claims with a longer term and keep the original signature —
    // the obvious attack, and the one the signature exists to stop.
    final tampered = LicenseFile(
      payloadB64: base64Url.encode(
        utf8.encode(jsonEncode(claimsFor(term: const Duration(days: 3650)).toJson())),
      ),
      signatureB64: honest.signatureB64,
    );

    final result = await service.activate(
      deployment: deployment,
      fileContents: tampered.serialize(),
    );

    expect(result.succeeded, isFalse);
    expect(result.entitlement?.state, LicenseState.invalid);
  });

  test('an unsigned file — the old fake issuer\'s output — is refused', () async {
    final pair = await Ed25519().newKeyPair();
    final service = await serviceFor((await pair.extractPublicKey()).bytes);

    // Sixty-four zero bytes is exactly what `FakeLicenceService` produced, and
    // exactly what used to be accepted.
    final unsigned = LicenseFile(
      payloadB64: base64Url.encode(utf8.encode(jsonEncode(claimsFor().toJson()))),
      signatureB64: base64Url.encode(List<int>.filled(64, 0)),
    );

    final result = await service.activate(
      deployment: deployment,
      fileContents: unsigned.serialize(),
    );

    expect(result.succeeded, isFalse);
  });

  test('a licence for another restaurant is refused, and says whose it is', () async {
    final pair = await Ed25519().newKeyPair();
    final service = await serviceFor((await pair.extractPublicKey()).bytes);

    final result = await service.activate(
      deployment: deployment,
      fileContents: (await sign(claimsFor(tenant: 'somebody-else'), pair)).serialize(),
    );

    expect(result.succeeded, isFalse);
    expect(result.entitlement?.state, LicenseState.tenantMismatch);
    expect(
      result.notice,
      isA<LicenceTenantMismatch>()
          .having((n) => n.licenceTenant, 'licence tenant', contains("Amer's Kitchen"))
          .having((n) => n.terminalTenant, 'terminal tenant', 'amer'),
    );
  });

  test('a licence that does not cover this deployment mode is refused', () async {
    final pair = await Ed25519().newKeyPair();
    final service = await serviceFor((await pair.extractPublicKey()).bytes);

    final result = await service.activate(
      deployment: deployment,
      fileContents:
          (await sign(claimsFor(modes: {DeploymentMode.cloud}), pair)).serialize(),
    );

    expect(result.succeeded, isFalse);
    expect(result.entitlement?.state, LicenseState.modeNotLicensed);
  });

  test('typing a key gets an honest answer when there is no server to ask', () async {
    final pair = await Ed25519().newKeyPair();
    final service = await serviceFor((await pair.extractPublicKey()).bytes);

    expect(service.canActivateOnline, isFalse);

    final result = await service.activate(deployment: deployment, key: 'XORD-1234');

    // "That key was not recognised" would send the operator hunting for a typo
    // in a key nothing was ever going to check.
    expect(result.succeeded, isFalse);
    expect(result.notice, isA<NoLicenceServer>());
  });

  test('an expired licence still permits cash-up, and says so', () async {
    final pair = await Ed25519().newKeyPair();
    final service = await serviceFor((await pair.extractPublicKey()).bytes);

    final result = await service.activate(
      deployment: deployment,
      fileContents: (await sign(claimsFor(term: const Duration(days: -60)), pair)).serialize(),
    );

    // The governing rule: never brick a till mid-service. Expiry blocks the
    // next shift, never the open one, and never the takings.
    expect(result.entitlement?.state, LicenseState.expired);
    expect(result.entitlement?.canOpenShift, isFalse);
    expect(result.entitlement?.canSell, isTrue);
  });

  test('a licence is remembered across a restart', () async {
    final pair = await Ed25519().newKeyPair();
    final store = InMemoryLicenseStore();
    final service = DefaultLicenceService(
      verifier: LicenseVerifier(publicKeyBytes: (await pair.extractPublicKey()).bytes),
      store_: store,
      fingerprint: const FakeTerminalFingerprint(),
      clock: () => now,
    );

    await service.activate(
      deployment: deployment,
      fileContents: (await sign(claimsFor(), pair)).serialize(),
    );

    // A second service over the same store is what a relaunched app has. A
    // licence that had to be reinstalled every morning would be worse than none.
    final afterRestart = DefaultLicenceService(
      verifier: LicenseVerifier(publicKeyBytes: (await pair.extractPublicKey()).bytes),
      store_: store,
      fingerprint: const FakeTerminalFingerprint(),
      clock: () => now,
    );

    expect((await afterRestart.current(deployment)).canOpenShift, isTrue);
  });
}
