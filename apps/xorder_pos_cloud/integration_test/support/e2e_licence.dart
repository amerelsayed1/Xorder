import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';

/// Signs a licence the running app will actually accept.
///
/// The suite boots the real app with **no provider overrides**, which is the
/// whole point of it — so it cannot swap in a lenient verifier. The app checks
/// signatures against the key embedded in the binary, so the only way to get
/// past the licence step is to hold the matching private half and sign a real
/// licence, exactly as `bin/pos_licence.dart` does for a customer.
///
/// The key comes from `POS_LICENCE_KEY`, the same way the database password
/// comes from `POS_PG_PASSWORD`: a signing key checked into a repository is a
/// signing key that has to be rotated.
abstract final class E2eLicence {
  static String? get signingKey {
    final key = Platform.environment['POS_LICENCE_KEY'];
    return key == null || key.trim().isEmpty ? null : key.trim();
  }

  /// A one-year licence for [tenantSlug], covering branch-server tills.
  /// Sign with `POS_LICENCE_KEY` when it is set — the issuer's own seed, so
  /// the file verifies against the key compiled into the build, as a
  /// customer's would. Without it, a key minted for this run: the file then
  /// carries its public half as `issuer_public_key`, exactly as an activation
  /// reply does, and a development build trusts that (see
  /// `LicenseVerifier.trustIssuerKey`). A release build would refuse it,
  /// which is the point of the compiled-in key — and is why the documented
  /// release run still sets `POS_LICENCE_KEY`.
  static Future<String> issue({
    required String tenantSlug,
    required String tenantName,
    Duration term = const Duration(days: 365),
  }) async {
    final key = signingKey;
    final pair = key == null
        ? await Ed25519().newKeyPair()
        : await Ed25519().newKeyPairFromSeed(base64.decode(key));

    final now = DateTime.now().toUtc();
    final claims = LicenseClaims(
      licenseId: 'e2e',
      tenantSlug: tenantSlug,
      tenantName: tenantName,
      issuedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(term),
      modes: const {DeploymentMode.offline},
      plan: 'End To End',
    );

    final payload = base64Url.encode(utf8.encode(jsonEncode(claims.toJson())));
    final signature = await Ed25519().sign(
      base64Url.decode(payload.padRight(payload.length + ((4 - payload.length % 4) % 4), '=')),
      keyPair: pair,
    );

    return LicenseFile(
      payloadB64: payload,
      signatureB64: base64Url.encode(signature.bytes),
      issuerPublicKeyB64: key == null
          ? base64.encode((await pair.extractPublicKey()).bytes)
          : null,
    ).serialize();
  }
}
