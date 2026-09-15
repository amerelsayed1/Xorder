import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';

/// Which connections may go unencrypted.
///
/// `PosDatabase` reads exactly one flag for this — `allowsInsecureTransport`
/// picks `SslMode.disable` over `SslMode.require` — so the rules below are the
/// whole of the policy.
void main() {
  group('a database on this machine', () {
    test('connects without TLS, because there is no wire to protect', () {
      const local = DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: 'localhost',
      );

      // A stock PostgreSQL ships `ssl = off`. Requiring TLS here hardened
      // nothing and made one machine + one database — the commonest install
      // there is — unable to connect at all, with no control in the wizard to
      // relax it: the operator is only asked about certificates once they have
      // typed a LAN address.
      expect(local.isLoopback, isTrue);
      expect(local.allowsInsecureTransport, isTrue);
      expect(
        local.copyWith(databaseHost: '127.0.0.1').allowsInsecureTransport,
        isTrue,
      );
    });

    test('and does not need the operator to have said so', () {
      const local = DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: '127.0.0.1',
      );

      // verifyTls is still true — the default — and the concession stands
      // anyway. Loopback is a fact about the route, not a decision.
      expect(local.verifyTls, isTrue);
      expect(local.allowsInsecureTransport, isTrue);
    });
  });

  group('a database on the LAN', () {
    const lan = DeploymentConfig(
      mode: DeploymentMode.offline,
      databaseHost: '192.168.1.20',
    );

    test('keeps its explicit decision — that traffic crosses a switch', () {
      expect(lan.isLoopback, isFalse);
      expect(lan.allowsInsecureTransport, isFalse,
          reason: 'nobody has waived certificate checks for it yet');

      expect(lan.copyWith(verifyTls: false).allowsInsecureTransport, isTrue);
    });
  });

  group('a database on a public host', () {
    test('may never skip TLS, however the flags are set', () {
      const public = DeploymentConfig(
        mode: DeploymentMode.cloud,
        databaseHost: 'db.example.com',
        verifyTls: false,
      );

      // A cashier mistyping a hostname must not silently downgrade the till.
      expect(public.isLoopback, isFalse);
      expect(public.allowsInsecureTransport, isFalse);
    });

    test('and an empty host earns nothing at all', () {
      const nowhere = DeploymentConfig(mode: DeploymentMode.offline, databaseHost: '');

      // `isSingleMachine` counts an empty host as "this machine" for the
      // wizard's copy. That must not become a transport concession.
      expect(nowhere.isSingleMachine, isTrue);
      expect(nowhere.isLoopback, isFalse);
      expect(nowhere.allowsInsecureTransport, isFalse);
    });
  });

  group('platform API transport', () {
    test('requires HTTPS outside loopback or a private LAN', () {
      expect(
        DeploymentConfig.isPermittedPlatformUrl('https://pos.example.com'),
        isTrue,
      );
      expect(
        DeploymentConfig.isPermittedPlatformUrl('http://pos.example.com'),
        isFalse,
      );
      expect(
        DeploymentConfig.isPermittedPlatformUrl('http://192.168.1.20:8080'),
        isTrue,
      );
      expect(
        DeploymentConfig.isPermittedPlatformUrl('http://pos-host.local:8080'),
        isTrue,
      );
    });

    test('rejects malformed platform URLs as an unconfigured cloud terminal', () {
      const invalid = DeploymentConfig(
        mode: DeploymentMode.cloud,
        databaseHost: 'db.example.com',
        baseUrl: 'http://pos.example.com',
      );
      expect(invalid.isConfigured, isFalse);
    });
  });
}
