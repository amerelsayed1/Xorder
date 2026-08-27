import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';

/// Signs real licence files with a throwaway keypair, so the crypto path is
/// actually exercised rather than mocked away.
class _Issuer {
  _Issuer(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final List<int> publicKeyBytes;

  static Future<_Issuer> create() async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return _Issuer(keyPair, publicKey.bytes);
  }

  Future<LicenseFile> issue(LicenseClaims claims) async {
    final payload = utf8.encode(jsonEncode(claims.toJson()));
    final signature = await Ed25519().sign(payload, keyPair: keyPair);

    return LicenseFile(
      payloadB64: base64Url.encode(payload),
      signatureB64: base64Url.encode(signature.bytes),
    );
  }
}

final _now = DateTime.utc(2026, 8, 26, 12);

LicenseClaims _claims({
  DateTime? issuedAt,
  DateTime? expiresAt,
  int graceDays = 14,
  int warnDays = 30,
  String tenantSlug = 'mahsoub',
  String tenantName = 'Mahsoub Grill',
  Set<DeploymentMode> modes = const {DeploymentMode.cloud},
  Set<String> fingerprints = const {},
}) =>
    LicenseClaims(
      licenseId: 'lic_001',
      tenantSlug: tenantSlug,
      tenantName: tenantName,
      issuedAt: issuedAt ?? _now.subtract(const Duration(days: 100)),
      expiresAt: expiresAt ?? _now.add(const Duration(days: 200)),
      graceDays: graceDays,
      warnDays: warnDays,
      modes: modes,
      fingerprints: fingerprints,
    );

const _cloud = DeploymentConfig(
  mode: DeploymentMode.cloud,
  baseUrl: 'https://xorder.io',
  tenantSlug: 'mahsoub',
);

void main() {
  group('signature verification', () {
    late _Issuer issuer;
    late LicenseVerifier verifier;

    setUp(() async {
      issuer = await _Issuer.create();
      verifier = LicenseVerifier(publicKeyBytes: issuer.publicKeyBytes);
    });

    test('accepts a licence signed by the matching key', () async {
      final file = await issuer.issue(_claims());
      expect(await verifier.verifySignature(file), isTrue);
    });

    test('rejects a licence signed by a different key', () async {
      final other = await _Issuer.create();
      final file = await other.issue(_claims());

      expect(await verifier.verifySignature(file), isFalse);
    });

    test('rejects a licence whose claims were edited after signing', () async {
      final file = await issuer.issue(_claims());

      // Extend the expiry by hand — the classic attack, and the whole reason
      // the payload is signed rather than merely checksummed.
      final claims = LicenseVerifier.claimsOf(file)!;
      final forged = LicenseClaims(
        licenseId: claims.licenseId,
        tenantSlug: claims.tenantSlug,
        tenantName: claims.tenantName,
        issuedAt: claims.issuedAt,
        expiresAt: claims.expiresAt.add(const Duration(days: 3650)),
      );
      final tampered = LicenseFile(
        payloadB64: base64Url.encode(utf8.encode(jsonEncode(forged.toJson()))),
        signatureB64: file.signatureB64,
      );

      expect(await verifier.verifySignature(tampered), isFalse);
    });

    test('rejects garbage instead of throwing', () async {
      const junk = LicenseFile(payloadB64: 'not base64!!', signatureB64: '???');
      expect(await verifier.verifySignature(junk), isFalse);
    });

    test('round-trips through serialize/parse', () async {
      final file = await issuer.issue(_claims());
      final parsed = LicenseFile.tryParse(file.serialize());

      expect(parsed, isNotNull);
      expect(await verifier.verifySignature(parsed!), isTrue);
    });

    test('tryParse returns null on non-JSON rather than throwing', () {
      expect(LicenseFile.tryParse('this is not a licence'), isNull);
      expect(LicenseFile.tryParse('{"payload":"a"}'), isNull);
    });

    test('a missing licence is reported, not crashed on', () async {
      final entitlement = await verifier.evaluate(
        file: null,
        deployment: _cloud,
        now: _now,
      );

      expect(entitlement.state, LicenseState.missing);
      expect(entitlement.canSell, isFalse);
    });

    test('end-to-end: a valid signed licence permits trade', () async {
      final entitlement = await verifier.evaluate(
        file: await issuer.issue(_claims()),
        deployment: _cloud,
        now: _now,
      );

      expect(entitlement.state, LicenseState.valid);
      expect(entitlement.canSell, isTrue);
      expect(entitlement.canOpenShift, isTrue);
    });
  });

  group('expiry policy', () {
    LicenseEntitlement evaluate(LicenseClaims claims, {DateTime? now}) =>
        LicenseVerifier.evaluateClaims(
          claims: claims,
          deployment: _cloud,
          now: now ?? _now,
        );

    test('a licence well inside its term is simply valid', () {
      expect(evaluate(_claims()).state, LicenseState.valid);
    });

    test('warns inside the renewal window without restricting anything', () {
      final entitlement = evaluate(
        _claims(expiresAt: _now.add(const Duration(days: 10))),
      );

      expect(entitlement.state, LicenseState.expiringSoon);
      expect(entitlement.canSell, isTrue);
      expect(entitlement.canChangeConfiguration, isTrue);
      expect(entitlement.message, contains('10 days'));
    });

    test('keeps trading through the grace window but freezes configuration', () {
      final entitlement = evaluate(
        _claims(expiresAt: _now.subtract(const Duration(days: 3))),
      );

      expect(entitlement.state, LicenseState.inGrace);
      expect(entitlement.canSell, isTrue);
      expect(entitlement.canOpenShift, isTrue);
      expect(entitlement.canChangeConfiguration, isFalse);
    });

    test('past grace, a new shift is blocked but the open one is not cut off', () {
      final entitlement = evaluate(
        _claims(expiresAt: _now.subtract(const Duration(days: 30))),
      );

      expect(entitlement.state, LicenseState.expired);
      expect(entitlement.canOpenShift, isFalse);
      // The cardinal rule: never brick a till mid-service.
      expect(entitlement.canSell, isTrue);
    });

    test('cash-up, reprint and export are never gated, in any state', () {
      for (final claims in [
        _claims(),
        _claims(expiresAt: _now.subtract(const Duration(days: 3))),
        _claims(expiresAt: _now.subtract(const Duration(days: 300))),
      ]) {
        final entitlement = evaluate(claims);
        expect(entitlement.canCashUp, isTrue);
        expect(entitlement.canReprint, isTrue);
        expect(entitlement.canExportData, isTrue);
      }
    });

    test('a clock set before the start date blames the clock, not the licence', () {
      final entitlement = evaluate(
        _claims(issuedAt: _now.add(const Duration(days: 5))),
      );

      expect(entitlement.state, LicenseState.notYetValid);
      expect(entitlement.message, contains('date and time'));
    });
  });

  group('scope checks', () {
    test('refuses a licence issued to another tenant', () {
      final entitlement = LicenseVerifier.evaluateClaims(
        claims: _claims(tenantSlug: 'other-grill', tenantName: 'Other Grill'),
        deployment: _cloud,
        now: _now,
      );

      expect(entitlement.state, LicenseState.tenantMismatch);
      expect(entitlement.canSell, isFalse);
      // The message must name both sides — an installer holding the wrong file
      // needs to know which licence they have as well as which they need.
      expect(entitlement.message, contains('Other Grill'));
      expect(entitlement.message, contains('mahsoub'));
    });

    test('refuses a cloud-only licence on a branch server', () {
      final entitlement = LicenseVerifier.evaluateClaims(
        claims: _claims(modes: {DeploymentMode.cloud}),
        deployment: const DeploymentConfig(
          mode: DeploymentMode.branchServer,
          baseUrl: 'https://192.168.1.20',
          tenantSlug: 'mahsoub',
        ),
        now: _now,
      );

      expect(entitlement.state, LicenseState.modeNotLicensed);
    });

    test('accepts a licence covering the configured mode', () {
      final entitlement = LicenseVerifier.evaluateClaims(
        claims: _claims(modes: {DeploymentMode.cloud, DeploymentMode.branchServer}),
        deployment: const DeploymentConfig(
          mode: DeploymentMode.branchServer,
          baseUrl: 'https://192.168.1.20',
          tenantSlug: 'mahsoub',
        ),
        now: _now,
      );

      expect(entitlement.state, LicenseState.valid);
    });

    test('honours a fingerprint pin', () {
      LicenseEntitlement forFingerprint(String? fingerprint) =>
          LicenseVerifier.evaluateClaims(
            claims: _claims(fingerprints: {'machine-a'}),
            deployment: _cloud,
            now: _now,
            terminalFingerprint: fingerprint,
          );

      expect(forFingerprint('machine-a').state, LicenseState.valid);
      expect(forFingerprint('machine-b').state, LicenseState.terminalNotLicensed);
      expect(forFingerprint(null).state, LicenseState.terminalNotLicensed);
    });

    test('an unpinned licence runs on any machine', () {
      final entitlement = LicenseVerifier.evaluateClaims(
        claims: _claims(),
        deployment: _cloud,
        now: _now,
        terminalFingerprint: 'anything-at-all',
      );

      expect(entitlement.state, LicenseState.valid);
    });
  });

  group('deployment config', () {
    test('recognises private hosts, which alone may skip TLS verification', () {
      const lan = DeploymentConfig(
        mode: DeploymentMode.branchServer,
        baseUrl: 'http://192.168.1.20:8100',
        verifyTls: false,
      );
      expect(lan.isPrivateHost, isTrue);
      expect(lan.allowsInsecureTransport, isTrue);
    });

    test('never downgrades transport for a public host', () {
      // A mistyped hostname must not silently put the till on plaintext.
      const public = DeploymentConfig(
        mode: DeploymentMode.branchServer,
        baseUrl: 'http://evil.example.com',
        verifyTls: false,
      );
      expect(public.isPrivateHost, isFalse);
      expect(public.allowsInsecureTransport, isFalse);
    });

    test('standalone needs no base url to count as configured', () {
      const standalone = DeploymentConfig(mode: DeploymentMode.standalone);
      expect(standalone.isConfigured, isTrue);

      const cloudUnset = DeploymentConfig(mode: DeploymentMode.cloud);
      expect(cloudUnset.isConfigured, isFalse);
    });

    test('only cloud can reach the platform for licence refresh', () {
      expect(DeploymentMode.cloud.canReachPlatform, isTrue);
      expect(DeploymentMode.branchServer.canReachPlatform, isFalse);
      expect(DeploymentMode.standalone.canReachPlatform, isFalse);
    });

    test('only an islanded terminal relies on a periodic check-in', () {
      // The other two are continuously visible to Super Admin: one writes to
      // the platform, the other forwards through a mandatory upstream.
      expect(DeploymentMode.standalone.requiresPeriodicCheckIn, isTrue);
      expect(DeploymentMode.cloud.requiresPeriodicCheckIn, isFalse);
      expect(DeploymentMode.branchServer.requiresPeriodicCheckIn, isFalse);
    });

    test('a branch server without an upstream is not a configuration', () {
      const noUpstream = DeploymentConfig(
        mode: DeploymentMode.branchServer,
        baseUrl: 'https://192.168.1.20:8100',
      );
      expect(noUpstream.isConfigured, isFalse);

      expect(
        noUpstream.copyWith(upstreamUrl: 'https://xorder.io').isConfigured,
        isTrue,
      );
    });

    test('sync policy round-trips, and an unknown one falls back rather than throwing', () {
      const manual = DeploymentConfig(
        mode: DeploymentMode.cloud,
        baseUrl: 'https://xorder.io',
        syncPolicy: SyncPolicy.manual,
      );
      expect(DeploymentConfig.fromJson(manual.toJson()).syncPolicy, SyncPolicy.manual);

      // A config written by a newer build must still boot this one.
      final unknown = Map<String, Object?>.from(manual.toJson())..['sync_policy'] = 'telepathy';
      expect(DeploymentConfig.fromJson(unknown).syncPolicy, SyncPolicy.automatic);
    });
  });
}
