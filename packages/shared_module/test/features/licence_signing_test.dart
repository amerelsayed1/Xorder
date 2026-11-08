import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/labels.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/features/licensing/data/licence_service.dart';
import 'package:shared_module/features/licensing/data/license_keys.dart';
import 'package:shared_module/features/licensing/data/license_store.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';

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

  test('a development build reads a licence from a platform whose key it '
      'was not built with', () async {
    final ours = await Ed25519().newKeyPair();
    final theirs = await Ed25519().newKeyPair();
    final theirPublic = (await theirs.extractPublicKey()).bytes;
    final signed = await sign(claimsFor(), theirs);

    // What activation hands a till: the file, and the issuer's public key
    // beside it. Through tryParse, as the platform API delivers it.
    final file = LicenseFile.tryParse(
      jsonEncode({
        'payload': signed.payloadB64,
        'signature': signed.signatureB64,
        'key_id': 'v1',
        'enforcement': 'online',
        'issuer_public_key': base64.encode(theirPublic),
      }),
    )!;
    expect(file.issuerPublicKeyB64, base64.encode(theirPublic));
    // And it survives the round trip to disk, so the next launch still has it.
    expect(
      LicenseFile.tryParse(file.serialize())!.issuerPublicKeyB64,
      base64.encode(theirPublic),
    );

    // Tests run without dart.vm.product, so the default is a developer's.
    final development = LicenseVerifier(
      publicKeyBytes: (await ours.extractPublicKey()).bytes,
      keyId: 'development-v1',
    );
    expect(development.trustIssuerKey, isTrue);
    expect(await development.verifySignature(file), isTrue);
    final verdict = await development.evaluate(
      file: file,
      deployment: deployment,
      now: now,
    );
    expect(verdict.state, LicenseState.valid);

    // A release build holds its compiled-in key and nothing else.
    final release = LicenseVerifier(
      publicKeyBytes: (await ours.extractPublicKey()).bytes,
      keyId: 'v1',
      trustIssuerKey: false,
    );
    expect(await release.verifySignature(file), isFalse);

    // The issuer's word is not a skeleton key: a file that fails against the
    // key it names fails. Edited payload, honest-looking issuer field.
    final edited = LicenseFile(
      payloadB64: base64Url.encode(
        utf8.encode(
          jsonEncode(claimsFor(term: const Duration(days: 3650)).toJson()),
        ),
      ),
      signatureB64: signed.signatureB64,
      issuerPublicKeyB64: base64.encode(theirPublic),
    );
    expect(await development.verifySignature(edited), isFalse);
  });

  test('a licence signed under another key id says which, and which this '
      'build holds', () async {
    final ours = await Ed25519().newKeyPair();
    final theirs = await Ed25519().newKeyPair();
    final verifier = LicenseVerifier(
      publicKeyBytes: (await ours.extractPublicKey()).bytes,
      keyId: 'development-v1',
    );

    // A production platform's file read by a debug build: the key id on the
    // file names a key this build does not hold. The licence is good; the
    // build is the wrong one, and "ask your supplier to reissue it" would
    // get the same file minted again.
    final signed = await sign(claimsFor(), theirs);
    final verdict = await verifier.evaluate(
      file: LicenseFile(
        payloadB64: signed.payloadB64,
        signatureB64: signed.signatureB64,
        keyId: 'v1',
      ),
      deployment: deployment,
      now: now,
    );
    final notice = verdict.notice;
    expect(notice, isA<LicenceUnverifiable>());
    notice as LicenceUnverifiable;
    expect(notice.otherKey, isTrue);
    expect(notice.signedWith, 'v1');
    expect(notice.holds, 'development-v1');
    final said = notice.text(const EnStrings());
    expect(said, contains('“v1”'));
    expect(said, contains('“development-v1”'));
    expect(said, isNot(contains('reissue')));

    // The same key id, and still not verifying: the file has been edited, and
    // reissuing it is exactly the advice.
    final edited = await verifier.evaluate(
      file: LicenseFile(
        payloadB64: signed.payloadB64,
        signatureB64: signed.signatureB64,
        keyId: 'development-v1',
      ),
      deployment: deployment,
      now: now,
    );
    final same = edited.notice! as LicenceUnverifiable;
    expect(same.otherKey, isFalse);
    expect(same.text(const EnStrings()), contains('reissue'));
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

  test('a licence for another business is refused, and says whose it is', () async {
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
