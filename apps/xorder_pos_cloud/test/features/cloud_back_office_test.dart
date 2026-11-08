import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:xorder_pos_cloud/features/cloud_back_office_screen.dart';

/// CB-07 — a cloud till has no back office of its own.
///
/// The address is built from what the till already knows rather than from a
/// new field on the bundle, so the rule worth pinning is when it declines to
/// answer: a wrong address is worse than none, because a manager who types it
/// in reaches a certificate warning or somebody else's business.
void main() {
  DeploymentConfig cloud({String? baseUrl, String? slug}) => DeploymentConfig(
    mode: DeploymentMode.cloud,
    baseUrl: baseUrl,
    tenantSlug: slug,
  );

  group('naming the dashboard', () {
    test('the business gets its own subdomain, on /admin', () {
      expect(
        dashboardAddress(cloud(baseUrl: 'https://xorder.io', slug: 'maadi')),
        'https://maadi.xorder.io/admin',
      );
    });

    test('a host that already names the tenant is left alone', () {
      // The operator typed the business's own address into setup, and it is
      // the one that works — prefixing the slug again would invent
      // maadi.maadi.xorder.io.
      expect(
        dashboardAddress(
          cloud(baseUrl: 'https://maadi.xorder.io', slug: 'maadi'),
        ),
        'https://maadi.xorder.io/admin',
      );
    });

    test('a development platform keeps its scheme and port', () {
      expect(
        dashboardAddress(cloud(baseUrl: 'http://localhost:8080', slug: 'demo')),
        'http://demo.localhost:8080/admin',
      );
    });
  });

  group('declining to guess', () {
    test('no platform address, no answer', () {
      expect(dashboardAddress(cloud(slug: 'maadi')), isNull);
      expect(dashboardAddress(cloud(baseUrl: '  ', slug: 'maadi')), isNull);
    });

    test('no tenant, no answer', () {
      expect(dashboardAddress(cloud(baseUrl: 'https://xorder.io')), isNull);
    });

    test('an address that is not a URL at all', () {
      expect(dashboardAddress(cloud(baseUrl: 'not a url', slug: 'x')), isNull);
    });
  });
}
