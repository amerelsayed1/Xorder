import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';

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
  static Future<String> issue({
    required String tenantSlug,
    required String tenantName,
    Duration term = const Duration(days: 365),
  }) async {
    final key = signingKey;
    if (key == null) {
      throw StateError('POS_LICENCE_KEY is not set — nothing to sign with.');
    }

    final now = DateTime.now().toUtc();
    final claims = LicenseClaims(
      licenseId: 'e2e',
      tenantSlug: tenantSlug,
      tenantName: tenantName,
      issuedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(term),
      modes: const {DeploymentMode.branchServer},
      plan: 'End To End',
    );

    final payload = base64Url.encode(utf8.encode(jsonEncode(claims.toJson())));
    final signature = await Ed25519().sign(
      base64Url.decode(payload.padRight(payload.length + ((4 - payload.length % 4) % 4), '=')),
      keyPair: await Ed25519().newKeyPairFromSeed(base64.decode(key)),
    );

    return LicenseFile(
      payloadB64: payload,
      signatureB64: base64Url.encode(signature.bytes),
    ).serialize();
  }
}
