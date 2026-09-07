import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/config/deployment.dart';
import 'license.dart';

/// A licence file as distributed: claims plus a detached signature over them.
///
/// Shaped like a JWS but deliberately not a JWT — there is no `alg` field to
/// confuse, and therefore no "alg: none" class of bug. The algorithm is fixed at
/// Ed25519 by this code and cannot be selected by the file.
class LicenseFile {
  const LicenseFile({
    required this.payloadB64,
    required this.signatureB64,
    this.keyId = 'v1',
  });

  final String payloadB64;
  final String signatureB64;
  final String keyId;

  static LicenseFile? tryParse(String raw) {
    try {
      final json = jsonDecode(raw.trim()) as Map<String, Object?>;
      final payload = json['payload'] as String?;
      final signature = json['signature'] as String?;
      if (payload == null || signature == null) return null;

      return LicenseFile(
        payloadB64: payload,
        signatureB64: signature,
        keyId: json['key_id'] as String? ?? 'v1',
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  String serialize() => jsonEncode({
    'payload': payloadB64,
    'signature': signatureB64,
    'key_id': keyId,
  });
}

/// Verifies licence files and turns them into an entitlement.
///
/// ## What this is, and what it is not
///
/// This is **commercial hygiene, not security**. The verification key ships
/// inside the binary, so anyone willing to patch the binary can defeat every
/// check in this file. That is true of every offline licence system ever built
/// and is not a reason to skip it — it is a reason not to rely on it for
/// anything that actually matters.
///
/// Where real enforcement lives:
///   * cloud mode — the server's existing `feature:pos` entitlement and plan
///     limits remain authoritative on every write;
///   * terminal counting — only a server can see sibling terminals, so the
///     offline `maxTerminals` check is advisory (POS-BE-016).
class LicenseVerifier {
  LicenseVerifier({required this.publicKeyBytes, Ed25519? algorithm})
    : _algorithm = algorithm ?? Ed25519();

  /// The licence-server public key. The private half never leaves the issuer.
  ///
  /// Replaced at build time per release channel; tests inject their own so they
  /// can sign real fixtures rather than mock the crypto away.
  final List<int> publicKeyBytes;
  final Ed25519 _algorithm;

  /// Verify the detached signature over the payload bytes.
  Future<bool> verifySignature(LicenseFile file) async {
    try {
      final message = base64Url.decode(_pad(file.payloadB64));
      final signature = base64Url.decode(_pad(file.signatureB64));

      return await _algorithm.verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// Parse claims from a file whose signature has already been verified.
  static LicenseClaims? claimsOf(LicenseFile file) {
    try {
      final json = jsonDecode(
        utf8.decode(base64Url.decode(_pad(file.payloadB64))),
      );
      return LicenseClaims.fromJson(json as Map<String, Object?>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Full check: signature, then claims, then policy.
  Future<LicenseEntitlement> evaluate({
    required LicenseFile? file,
    required DeploymentConfig deployment,
    required DateTime now,
    String? terminalFingerprint,
  }) async {
    if (file == null) {
      return _deny(LicenseState.missing, const LicenceMissing());
    }

    if (!await verifySignature(file)) {
      return _deny(LicenseState.invalid, const LicenceUnverifiable());
    }

    final claims = claimsOf(file);
    if (claims == null) {
      return _deny(LicenseState.invalid, const LicenceFileDamaged());
    }

    return evaluateClaims(
      claims: claims,
      deployment: deployment,
      now: now,
      terminalFingerprint: terminalFingerprint,
    );
  }

  /// Policy only, separated from the crypto so it is exhaustively testable
  /// without generating keys for every case.
  static LicenseEntitlement evaluateClaims({
    required LicenseClaims claims,
    required DeploymentConfig deployment,
    required DateTime now,
    String? terminalFingerprint,
  }) {
    final tenant = deployment.tenantSlug;
    if (tenant != null && tenant.isNotEmpty && tenant != claims.tenantSlug) {
      return _deny(
        LicenseState.tenantMismatch,
        LicenceTenantMismatch(
          licenceTenant: claims.tenantName.isEmpty
              ? claims.tenantSlug
              : claims.tenantName,
          terminalTenant: tenant,
        ),
      );
    }

    if (claims.modes.isNotEmpty && !claims.modes.contains(deployment.mode)) {
      return _deny(
        LicenseState.modeNotLicensed,
        LicenceModeNotCovered(deployment.mode),
      );
    }

    if (claims.fingerprints.isNotEmpty &&
        (terminalFingerprint == null ||
            !claims.fingerprints.contains(terminalFingerprint))) {
      return _deny(
        LicenseState.terminalNotLicensed,
        const LicenceOtherTerminal(),
      );
    }

    if (now.isBefore(claims.issuedAt)) {
      // Almost always a wrong system clock, so say so — telling a cashier the
      // licence "is not yet valid" sends them to the wrong person.
      return _deny(
        LicenseState.notYetValid,
        LicenceNotYetValid(claims.issuedAt),
      );
    }

    final daysRemaining = claims.expiresAt.difference(now).inDays;

    if (now.isBefore(claims.expiresAt)) {
      if (daysRemaining <= claims.warnDays) {
        return LicenseEntitlement(
          state: LicenseState.expiringSoon,
          canOpenShift: true,
          canSell: true,
          canChangeConfiguration: true,
          daysRemaining: daysRemaining,
          notice: LicenceExpiresIn(daysRemaining),
        );
      }
      return LicenseEntitlement(
        state: LicenseState.valid,
        canOpenShift: true,
        canSell: true,
        canChangeConfiguration: true,
        daysRemaining: daysRemaining,
      );
    }

    if (now.isBefore(claims.graceEndsAt)) {
      final graceLeft = claims.graceEndsAt.difference(now).inDays;
      return LicenseEntitlement(
        state: LicenseState.inGrace,
        canOpenShift: true,
        canSell: true,
        // Configuration is frozen in grace: renew before rewiring the till.
        canChangeConfiguration: false,
        daysRemaining: daysRemaining,
        notice: LicenceInGrace(graceLeft),
      );
    }

    // Past grace. The next shift cannot open, but an open one is never cut off
    // and cash-up is never gated.
    return const LicenseEntitlement(
      state: LicenseState.expired,
      canOpenShift: false,
      canSell: true,
      canChangeConfiguration: false,
      notice: LicenceExpired(),
    );
  }

  static LicenseEntitlement _deny(LicenseState state, LicenceNotice notice) =>
      LicenseEntitlement(
        state: state,
        canOpenShift: false,
        // A licence that is missing, damaged or for the wrong tenant stops
        // trade — but cash-up, reprint and export stay open (see
        // LicenseEntitlement), so nobody is locked away from their own takings.
        canSell: false,
        canChangeConfiguration: false,
        notice: notice,
      );

  /// base64url without padding is common in signed tokens; Dart requires it.
  static String _pad(String value) =>
      value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
}
