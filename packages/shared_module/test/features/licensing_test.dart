import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';

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
      expect(entitlement.notice, isA<LicenceExpiresIn>().having((n) => n.days, 'days', 10));
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
      expect(entitlement.notice, isA<LicenceNotYetValid>());
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
      expect(
        entitlement.notice,
        isA<LicenceTenantMismatch>()
            .having((n) => n.licenceTenant, 'licence tenant', contains('Other Grill'))
            .having((n) => n.terminalTenant, 'terminal tenant', 'mahsoub'),
      );
    });

    test('refuses a cloud-only licence on an offline terminal', () {
      final entitlement = LicenseVerifier.evaluateClaims(
        claims: _claims(modes: {DeploymentMode.cloud}),
        deployment: const DeploymentConfig(
          mode: DeploymentMode.offline,
          databaseHost: '192.168.1.20',
          tenantSlug: 'mahsoub',
        ),
        now: _now,
      );

      expect(entitlement.state, LicenseState.modeNotLicensed);
    });

    test('accepts a licence covering the configured mode', () {
      final entitlement = LicenseVerifier.evaluateClaims(
        claims: _claims(modes: {DeploymentMode.cloud, DeploymentMode.offline}),
        deployment: const DeploymentConfig(
          mode: DeploymentMode.offline,
          databaseHost: '192.168.1.20',
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
    test('recognises private database hosts, which alone may skip TLS', () {
      const lan = DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: '192.168.1.20',
        allowInsecureLan: true,
      );
      expect(lan.isPrivateHost, isTrue);
      expect(lan.allowsInsecureTransport, isTrue);
    });

    test('never downgrades transport for a public host', () {
      // A mistyped hostname must not silently put the till on plaintext.
      const public = DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: 'evil.example.com',
        allowInsecureLan: true,
      );
      expect(public.isPrivateHost, isFalse);
      expect(public.allowsInsecureTransport, isFalse);
    });

    test('offline needs no base url to count as configured', () {
      const offline = DeploymentConfig(mode: DeploymentMode.offline);
      expect(offline.isConfigured, isTrue);

      const cloudUnset = DeploymentConfig(mode: DeploymentMode.cloud);
      expect(cloudUnset.isConfigured, isFalse);
    });

    test('a terminal with no database address is not a configuration', () {
      // Every mode reads and writes PostgreSQL now, so this is no longer a
      // question only the branch-server shape had to answer.
      const hostless = DeploymentConfig(mode: DeploymentMode.offline, databaseHost: '  ');
      expect(hostless.isConfigured, isFalse);
    });

    test('only cloud sends money to the platform', () {
      expect(DeploymentMode.cloud.syncsSalesToPlatform, isTrue);
      expect(DeploymentMode.offline.syncsSalesToPlatform, isFalse);
    });

    test('only an offline terminal relies on a periodic check-in', () {
      // A cloud terminal is continuously visible to Super Admin because it
      // writes there; an offline one is visible only when it renews.
      expect(DeploymentMode.offline.requiresPeriodicCheckIn, isTrue);
      expect(DeploymentMode.cloud.requiresPeriodicCheckIn, isFalse);
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

  group('legacy wire values', () {
    // The three-mode model shipped. Licences signed under it carry
    // `branch_server` or `standalone` in `modes[]` and **cannot be re-signed**,
    // and a terminal upgrading in place reads a `config.json` written by that
    // build. Anything here failing is a live till that will not start.
    test('a branch-server licence still covers an offline terminal', () {
      final claims = LicenseClaims.fromJson({
        'license_id': 'legacy',
        'tenant_slug': 'mahsoub',
        'tenant_name': 'Mahsoub Grill',
        'issued_at': _now.subtract(const Duration(days: 1)).toIso8601String(),
        'expires_at': _now.add(const Duration(days: 300)).toIso8601String(),
        'modes': ['branch_server'],
      });

      expect(claims.modes, {DeploymentMode.offline});

      final entitlement = LicenseVerifier.evaluateClaims(
        claims: claims,
        deployment: const DeploymentConfig(
          mode: DeploymentMode.offline,
          databaseHost: '192.168.1.20',
          tenantSlug: 'mahsoub',
        ),
        now: _now,
      );
      expect(entitlement.state, LicenseState.valid);
    });

    test('an islanded licence covers the same offline mode', () {
      expect(DeploymentMode.fromWire('standalone'), DeploymentMode.offline);
      expect(DeploymentMode.fromWire('branch_server'), DeploymentMode.offline);
      expect(DeploymentMode.fromWire('cloud'), DeploymentMode.cloud);
      expect(DeploymentMode.fromWire('offline'), DeploymentMode.offline);
    });

    test('a mode from a newer build parses to nothing rather than throwing', () {
      expect(DeploymentMode.fromWire('quantum'), isNull);
      expect(DeploymentMode.fromWire(null), isNull);
    });

    test('a branch-server config keeps its database host across the upgrade', () {
      // The old build had no `database_host`: the address lived in `base_url`,
      // and losing it would mean an engineer retyping it into every terminal.
      final upgraded = DeploymentConfig.fromJson({
        'mode': 'branch_server',
        'base_url': 'https://192.168.1.20:8100',
        'upstream_url': 'https://xorder.io',
        'tenant_slug': 'mahsoub',
        'verify_tls': false,
        'database_name': 'xorder_pos',
        'database_user': 'pos_till',
        'database_port': 5432,
      });

      expect(upgraded.mode, DeploymentMode.offline);
      expect(upgraded.databaseHost, '192.168.1.20');
      expect(upgraded.baseUrl, isNull, reason: 'offline has no platform address');
      expect(upgraded.isConfigured, isTrue);
      expect(upgraded.allowsInsecureTransport, isTrue);
    });

    test('an islanded config upgrades to a database on this machine', () {
      final upgraded = DeploymentConfig.fromJson({
        'mode': 'standalone',
        'tenant_slug': 'mahsoub',
      });

      expect(upgraded.mode, DeploymentMode.offline);
      expect(upgraded.databaseHost, DeploymentConfig.localhost);
      expect(upgraded.isSingleMachine, isTrue);
      expect(upgraded.isConfigured, isTrue);
    });

    test('a cloud config keeps its platform address and gains a local database', () {
      final upgraded = DeploymentConfig.fromJson({
        'mode': 'cloud',
        'base_url': 'https://xorder.io',
      });

      expect(upgraded.mode, DeploymentMode.cloud);
      expect(upgraded.baseUrl, 'https://xorder.io');
      expect(upgraded.databaseHost, DeploymentConfig.localhost);
    });

    test('the new wire value round-trips unchanged', () {
      const offline = DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: '10.0.0.5',
        tenantSlug: 'mahsoub',
      );
      final back = DeploymentConfig.fromJson(offline.toJson());

      expect(back.mode, DeploymentMode.offline);
      expect(back.databaseHost, '10.0.0.5');
      expect(back.tenantSlug, 'mahsoub');
    });
  });

  // POS-BE-027. The server has emitted `max_offline_days` since POS-BE-015
  // shipped; the client had never read it. Both claims are additive, and the
  // whole point of the group is that adding them changed nothing for a licence
  // that predates them.
  group('offline window and claims version', () {
    Map<String, Object?> payloadOf(LicenseClaims claims) =>
        jsonDecode(jsonEncode(claims.toJson())) as Map<String, Object?>;

    test('a licence signed before these claims existed still parses', () {
      // Exactly the payload the issuer produced before POS-BE-027: the two keys
      // are absent, not null. A till updating in place reads this file.
      final legacy = payloadOf(_claims())
        ..remove('max_offline_days')
        ..remove('license_version');

      final claims = LicenseClaims.fromJson(legacy);

      expect(
        claims.maxOfflineDays,
        isNull,
        reason: 'absent means unlimited — reading it as zero would expire '
            'every licence already in the field',
      );
      expect(claims.licenseVersion, 1);
      expect(claims.isNewerThanApp, isFalse);
    });

    test('an explicit null window is unlimited, which is right for cloud', () {
      final claims = LicenseClaims.fromJson(
        payloadOf(_claims())..['max_offline_days'] = null,
      );

      expect(claims.maxOfflineDays, isNull);
    });

    test('a window the server set is carried through', () {
      final claims = LicenseClaims.fromJson(
        payloadOf(_claims())..['max_offline_days'] = 30,
      );

      expect(claims.maxOfflineDays, 30);
    });

    test('both claims round-trip', () {
      final issued = LicenseClaims(
        licenseId: 'lic_027',
        tenantSlug: 'mahsoub',
        tenantName: 'Mahsoub Grill',
        issuedAt: _now,
        expiresAt: _now.add(const Duration(days: 365)),
        maxOfflineDays: 14,
        licenseVersion: 2,
      );

      final back = LicenseClaims.fromJson(payloadOf(issued));

      expect(back.maxOfflineDays, 14);
      expect(back.licenseVersion, 2);
    });

    test('a licence from a newer build is honoured, not refused', () {
      // The cardinal rule inverted would be to deny here. A till holding a
      // licence issued for a build it has not been updated to yet must keep
      // selling; it simply cannot act on claims it does not know about.
      final claims = LicenseClaims.fromJson(
        payloadOf(_claims())
          ..['license_version'] = LicenseClaims.supportedVersion + 1
          ..['some_claim_from_the_future'] = {'nested': true},
      );

      expect(claims.isNewerThanApp, isTrue);

      final entitlement = LicenseVerifier.evaluateClaims(
        claims: claims,
        deployment: _cloud,
        now: _now,
      );

      expect(entitlement.state, LicenseState.valid);
      expect(entitlement.canSell, isTrue);
      expect(entitlement.canOpenShift, isTrue);
    });

    test('a nonsense version falls back to 1 rather than throwing', () {
      final claims = LicenseClaims.fromJson(
        payloadOf(_claims())..['license_version'] = 'v2',
      );

      expect(claims.licenseVersion, 1);
    });

    test('signatures are unaffected: no licence needs re-signing', () async {
      final issuer = await _Issuer.create();
      final verifier = LicenseVerifier(publicKeyBytes: issuer.publicKeyBytes);

      // Signed *with* the new keys present.
      final withClaims = await issuer.issue(
        LicenseClaims(
          licenseId: 'lic_new',
          tenantSlug: 'mahsoub',
          tenantName: 'Mahsoub Grill',
          issuedAt: _now.subtract(const Duration(days: 1)),
          expiresAt: _now.add(const Duration(days: 365)),
          maxOfflineDays: 7,
          licenseVersion: 1,
        ),
      );

      expect(await verifier.verifySignature(withClaims), isTrue);
      expect(LicenseVerifier.claimsOf(withClaims)?.maxOfflineDays, 7);

      // And a file signed over a payload that never carried them still
      // verifies, because the signature covers bytes and this change only
      // reads more of them.
      final legacyPayload = utf8.encode(
        jsonEncode(
          payloadOf(_claims())
            ..remove('max_offline_days')
            ..remove('license_version'),
        ),
      );
      final signature = await Ed25519().sign(
        legacyPayload,
        keyPair: issuer.keyPair,
      );
      final legacyFile = LicenseFile(
        payloadB64: base64Url.encode(legacyPayload),
        signatureB64: base64Url.encode(signature.bytes),
      );

      expect(await verifier.verifySignature(legacyFile), isTrue);
      expect(LicenseVerifier.claimsOf(legacyFile)?.maxOfflineDays, isNull);
      expect(LicenseVerifier.claimsOf(legacyFile)?.licenseVersion, 1);
    });
  });
}
