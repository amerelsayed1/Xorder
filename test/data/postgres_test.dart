import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';

/// Pure tests for the Postgres layer — no database, no widget tree.
///
/// What can be tested without a server is tested without one. The SQL itself is
/// covered by `postgres_integration_test.dart`, which needs a real box.
void main() {
  group('invoice numbers', () {
    test('formats as prefix-period-padded', () {
      expect(
        PostgresOrdersRepository.formatInvoiceNumber(
          prefix: 'MAADI',
          period: '2026',
          value: 1042,
        ),
        'MAADI-2026-001042',
      );
    });

    test('does not truncate once the padding is exceeded', () {
      // A branch that sells a million tickets in a year must keep numbering,
      // not wrap or lose digits.
      expect(
        PostgresOrdersRepository.formatInvoiceNumber(
          prefix: 'DWTN',
          period: '2026',
          value: 1234567,
        ),
        'DWTN-2026-1234567',
      );
    });
  });

  group('failure classification', () {
    // A cashier needs to know which thing is broken, because the four causes
    // need four different actions from whoever is standing in the restaurant.
    test('separates the four causes a till can hit', () {
      expect(
        PosDbFailure.classify(Exception('Failed host lookup: pos-host.local')),
        PosDbFailure.dns,
      );
      expect(
        PosDbFailure.classify(Exception('SocketException: Connection refused')),
        PosDbFailure.tcp,
      );
      expect(
        PosDbFailure.classify(Exception('password authentication failed for user')),
        PosDbFailure.auth,
      );
      expect(
        PosDbFailure.classify(Exception('CERTIFICATE_VERIFY_FAILED')),
        PosDbFailure.tls,
      );
    });

    test('an unrecognised error is unknown, never mislabelled', () {
      // Guessing wrong sends an installer to fix the firewall when the password
      // is wrong. Unknown plus the raw error is more useful than a bad guess.
      expect(PosDbFailure.classify(Exception('something new')), PosDbFailure.unknown);
    });
  });

  group('host resolution', () {
    test('every mode has a database, and the mode does not decide where', () {
      // The shared-database shape: PostgreSQL on a box on the LAN.
      const shared = DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: '192.168.1.20',
      );
      expect(PosDatabase.hostFor(shared), '192.168.1.20');

      // A cloud terminal keeps its own local PostgreSQL and syncs it upward, so
      // it resolves to a host too — binding it to the unconfigured repositories
      // would have left it with no data path at all.
      const cloud = DeploymentConfig(mode: DeploymentMode.cloud, baseUrl: 'https://xorder.io');
      expect(PosDatabase.hostFor(cloud), 'localhost');

      // Single-terminal offline: same mode as the shared shape, different host.
      expect(
        PosDatabase.hostFor(const DeploymentConfig(mode: DeploymentMode.offline)),
        'localhost',
      );
    });

    test('a terminal that has not been set up resolves to nothing', () {
      const blank = DeploymentConfig(mode: DeploymentMode.offline, databaseHost: '   ');
      expect(PosDatabase.hostFor(blank), isNull);
    });
  });

  group('credentials', () {
    test('a missing credential is an auth failure, not a crash', () async {
      final db = PosDatabase(credentials: InMemoryPosDbCredentials(null));
      const config = DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: '192.168.1.20',
      );

      await expectLater(
        db.pool(config),
        throwsA(
          isA<PosDbException>().having((e) => e.failure, 'failure', PosDbFailure.auth),
        ),
      );
    });

    test('no configured host reports dns rather than opening a pool', () async {
      final db = PosDatabase(credentials: InMemoryPosDbCredentials('secret'));
      await expectLater(
        db.pool(const DeploymentConfig(
          mode: DeploymentMode.cloud,
          baseUrl: 'https://xorder.io',
          databaseHost: '',
        )),
        throwsA(
          isA<PosDbException>().having((e) => e.failure, 'failure', PosDbFailure.dns),
        ),
      );
    });
  });
}
