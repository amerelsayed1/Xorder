import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/lan_tls.dart';

import 'package:xorder_pos_test_support/lan_tls_fixtures.dart';

/// Which transport a till's database connection gets (ADR-006, slice C).
///
/// The accepted rule is "LAN TLS on by default; off only by an explicit
/// technician action; never downgraded silently". Everything that rule means
/// for a connection is decided by [LanTls.decide], so this is where it is
/// pinned down: host, flags and pin in, transport and pin out.
void main() {
  group('LanTls.decide', () {
    LanTlsDecision decide(
      String host, {
      bool insecure = false,
      String? sha,
      String? pem,
    }) => LanTls.decide(
      host: host,
      allowInsecureLan: insecure,
      pinnedSha256: sha,
      pinnedPem: pem,
    );

    test('loopback is plaintext, whatever else is set', () {
      for (final host in ['localhost', '127.0.0.1', '::1', ' localhost ']) {
        expect(decide(host).transport, LanTransport.loopback, reason: host);
        expect(
          decide(host, sha: fixtureASha256, pem: fixtureACertificate).transport,
          LanTransport.loopback,
          reason: 'a pin does not make loopback encrypt',
        );
      }
    });

    test('a LAN address with nothing set is encrypted and verified', () {
      // The default the whole slice exists for: no tick, no pin, TLS — and a
      // self-signed server fails it, which is what makes the wizard offer the
      // fingerprint.
      final decision = decide('192.168.1.20');
      expect(decision.transport, LanTransport.verifiedChain);
      expect(decision.transport.encrypted, isTrue);
      expect(decision.pin, isNull);
    });

    test('a pin is used, and carries the normalised fingerprint', () {
      final decision = decide(
        '192.168.1.20',
        sha: LanTls.formatFingerprint(fixtureASha256),
        pem: fixtureACertificate,
      );
      expect(decision.transport, LanTransport.pinned);
      expect(decision.pin?.sha256, fixtureASha256);
      expect(decision.pin?.pem, fixtureACertificate.trim());
      expect(decision.pin?.isConsistent, isTrue);
    });

    test('half a pin is no pin', () {
      expect(
        decide('192.168.1.20', sha: fixtureASha256).transport,
        LanTransport.verifiedChain,
      );
      expect(
        decide('192.168.1.20', pem: fixtureACertificate).transport,
        LanTransport.verifiedChain,
      );
      expect(
        decide('192.168.1.20', sha: 'not-hex', pem: fixtureACertificate)
            .transport,
        LanTransport.verifiedChain,
        reason: 'a malformed fingerprint fails closed, never open',
      );
    });

    test('the technician override is plaintext on a private address', () {
      for (final host in [
        '192.168.1.20',
        '10.0.0.5',
        '172.16.4.2',
        'pos-main.local',
      ]) {
        expect(
          decide(host, insecure: true).transport,
          LanTransport.insecureLan,
          reason: host,
        );
      }
    });

    test('and is ignored for anything that is not one', () {
      // A mistyped public hostname must not inherit a LAN concession.
      for (final host in ['db.example.com', '8.8.8.8', '172.32.0.1', 'POS-MAIN']) {
        expect(
          decide(host, insecure: true).transport,
          LanTransport.verifiedChain,
          reason: host,
        );
      }
    });

    test('a pin wins over the override, towards encryption', () {
      // Never both, by this build; a hand-edited file decides for TLS.
      expect(
        decide(
          '192.168.1.20',
          insecure: true,
          sha: fixtureASha256,
          pem: fixtureACertificate,
        ).transport,
        LanTransport.pinned,
      );
    });

    test('an empty host earns nothing', () {
      expect(decide('').transport, LanTransport.verifiedChain);
      expect(decide('', insecure: true).transport, LanTransport.verifiedChain);
    });
  });

  group('fingerprints', () {
    test('are computed over the DER, matching OpenSSL', () {
      expect(LanTls.sha256OfPem(fixtureACertificate), fixtureASha256);
      expect(LanTls.sha256OfPem(fixtureBCertificate), fixtureBSha256);
    });

    test('of a chain file are the first certificate\'s', () {
      expect(
        LanTls.sha256OfPem('$fixtureACertificate$fixtureBCertificate'),
        fixtureASha256,
      );
    });

    test('survive a PEM round trip', () {
      final der = LanTls.derFromPem(fixtureACertificate)!;
      expect(LanTls.sha256OfPem(LanTls.pemFromDer(der)), fixtureASha256);
      expect(PresentedCertificate.fromDer(der).sha256, fixtureASha256);
    });

    test('are shown the way openssl and Windows print them', () {
      final shown = LanTls.formatFingerprint(fixtureASha256);
      expect(shown, startsWith('87:B8:2B:03:'));
      expect(shown.split(':'), hasLength(32));
      expect(LanTls.normaliseFingerprint(shown), fixtureASha256);
      expect(LanTls.normaliseFingerprint('87 b8 2b'), isNull);
    });

    test('nothing that is not a certificate has one', () {
      expect(LanTls.sha256OfPem(''), isNull);
      expect(LanTls.sha256OfPem('-----BEGIN CERTIFICATE-----\n!!\n'
          '-----END CERTIFICATE-----'), isNull);
      expect(PresentedCertificate.fromPem('hello'), isNull);
    });

    test('a pin whose halves disagree is not consistent', () {
      const pin = PinnedCertificate(
        sha256: fixtureBSha256,
        pem: fixtureACertificate,
      );
      expect(pin.isConsistent, isFalse);
    });

    test('the expiry is read from the certificate', () {
      expect(LanTls.notAfterOfPem(fixtureACertificate), fixtureNotAfter);
      expect(LanTls.notAfterOfPem('nothing'), isNull);
    });
  });

  group('LanTls.diagnose', () {
    final a = PresentedCertificate.fromPem(fixtureACertificate)!;
    const pinA = PinnedCertificate(
      sha256: fixtureASha256,
      pem: fixtureACertificate,
    );

    test('names what the technician does next', () {
      expect(
        LanTls.diagnose(pin: null, fetch: const ServerOffersNoTls()),
        LanTlsDiagnosis.notOffered,
      );
      expect(
        LanTls.diagnose(pin: null, fetch: const CertificateFetchFailed('x')),
        LanTlsDiagnosis.unreachable,
      );
      expect(
        LanTls.diagnose(pin: null, fetch: CertificateFetched(a)),
        LanTlsDiagnosis.untrusted,
      );
      expect(
        LanTls.diagnose(pin: pinA, fetch: CertificateFetched(a)),
        LanTlsDiagnosis.nameMismatch,
      );
      expect(
        LanTls.diagnose(
          pin: pinA,
          fetch: CertificateFetched(
            PresentedCertificate.fromPem(fixtureBCertificate)!,
          ),
        ),
        LanTlsDiagnosis.changed,
      );
    });
  });

  group('config.json', () {
    const paired = DeploymentConfig(
      mode: DeploymentMode.offline,
      databaseHost: '192.168.1.20',
      role: TerminalRole.child,
      pinnedCertificateSha256: fixtureASha256,
      pinnedCertificatePem: fixtureACertificate,
    );

    test('keeps the pin and the override across a restart', () {
      final json = paired.toJson();
      expect(json['pinned_certificate_sha256'], fixtureASha256);
      expect(json['pinned_certificate_pem'], fixtureACertificate);
      expect(json['allow_insecure_lan'], isFalse);
      expect(json.containsKey('verify_tls'), isFalse);

      final read = DeploymentConfig.fromJson(json);
      expect(read.lanTls.transport, LanTransport.pinned);
      expect(read.lanTls.pin?.sha256, fixtureASha256);
      expect(read.allowInsecureLan, isFalse);

      final insecure = DeploymentConfig.fromJson(
        paired.copyWith(clearPinnedCertificate: true, allowInsecureLan: true)
            .toJson(),
      );
      expect(insecure.lanTls.transport, LanTransport.insecureLan);
      expect(insecure.pinnedCertificateSha256, isNull);
    });

    test('a config from before slice C is encrypted unless it had opted out',
        () {
      // Written by the old build: `verify_tls`, no pin fields at all.
      final legacy = {
        'mode': 'offline',
        'database_host': '192.168.1.20',
        'database_name': 'xorder_pos',
        'database_user': 'pos_till',
        'database_port': 5432,
        'role': 'client_terminal',
      };

      final untouched = DeploymentConfig.fromJson({
        ...legacy,
        'verify_tls': true,
      });
      expect(untouched.lanTls.transport, LanTransport.verifiedChain);
      expect(untouched.allowInsecureLan, isFalse);

      expect(
        DeploymentConfig.fromJson(legacy).lanTls.transport,
        LanTransport.verifiedChain,
        reason: 'absent was always "verify"',
      );

      // The old wizard's "trust without a certificate": plaintext then, and
      // plaintext now — but as the visible, named override, so it keeps
      // selling the morning after the upgrade and says why.
      final optedOut = DeploymentConfig.fromJson({
        ...legacy,
        'verify_tls': false,
      });
      expect(optedOut.allowInsecureLan, isTrue);
      expect(optedOut.isInsecureLan, isTrue);
    });

    test('the new key outranks the old one', () {
      final read = DeploymentConfig.fromJson({
        'mode': 'offline',
        'database_host': '192.168.1.20',
        'verify_tls': false,
        'allow_insecure_lan': false,
      });
      expect(read.allowInsecureLan, isFalse);
    });

    test('a new address forgets the old server\'s pin', () {
      final moved = paired.copyWith(
        databaseHost: '192.168.1.21',
        clearPinnedCertificate: true,
      );
      expect(moved.lanTls.transport, LanTransport.verifiedChain);
    });
  });
}
