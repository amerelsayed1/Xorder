import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/platform_endpoint.dart';
import 'package:shared_module/features/setup/domain/setup_state.dart';
import 'package:shared_module/features/licensing/data/platform_licence_api.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';

/// Activation is a key exchange, and the key is the whole credential.
///
/// This was the bug behind "Activate online never works": the till sent a
/// `tenant_slug` it does not have yet — the wizard asks for the licence FIRST,
/// because the licence is what supplies the tenant — and the platform required
/// one, so the call 422'd and the null-return dressed it up as an unrecognised
/// key. An offline customer makes it structural: there is no tenant to name.
void main() {
  group('activation by key', () {
    test('sends no tenant slug when the terminal has none yet', () async {
      final adapter = _CapturingAdapter(_file);
      final api = PlatformLicenceApi(
        client: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
        baseUrl: () => 'https://xorder.io',
        // The state of every till at the licence step of the wizard.
        tenantSlug: () => null,
      );

      final fetched = await api.fetchByKey('XO4T-9WQM-2K7H-BR5N', 'fp-1');

      expect(fetched.file, isNotNull);
      expect(fetched.notice, isNull);
      expect(adapter.body, isNot(contains('tenant_slug')));
      expect(adapter.body!['key'], 'XO4T-9WQM-2K7H-BR5N');
      expect(adapter.body!['fingerprint'], 'fp-1');
    });

    test('sends it when the terminal already knows its tenant', () async {
      // Optional is not the same as abandoned: a configured till renewing its
      // licence still offers the slug, and the platform still checks it — an
      // installer activating the wrong customer's key is told so.
      final adapter = _CapturingAdapter(_file);
      final api = PlatformLicenceApi(
        client: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
        baseUrl: () => 'https://xorder.io',
        tenantSlug: () => 'al-asima',
      );

      await api.fetchByKey('XO4T-9WQM-2K7H-BR5N', 'fp-1');

      expect(adapter.body!['tenant_slug'], 'al-asima');
    });

    test('an empty slug is treated as no slug, not as an empty one', () async {
      final adapter = _CapturingAdapter(_file);
      final api = PlatformLicenceApi(
        client: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
        baseUrl: () => 'https://xorder.io',
        tenantSlug: () => '',
      );

      await api.fetchByKey('XO4T-9WQM-2K7H-BR5N', 'fp-1');

      expect(adapter.body, isNot(contains('tenant_slug')));
    });
  });

  group('where activation is sent', () {
    test('a debug build asks the local stack, not production', () {
      // The bug this exists to prevent: a developer issues a licence from their
      // own Super Admin, types the key into a till they just launched, and the
      // till asks xorder.io — which truthfully has never heard of it. The
      // message reads as a bad key; the key is perfect.
      //
      // Tests run in debug, so this asserts the branch a developer gets.
      expect(PlatformEndpoint.base, PlatformEndpoint.devDefault);
      expect(PlatformEndpoint.production, 'https://xorder.io');
    });

    test('the activation URL is built from whatever base resolved to', () {
      // Guards the pair together: a base that moved without the URL following
      // it would send activation to the old platform in complete silence.
      expect(
        PlatformEndpoint.licenceActivation.toString(),
        '${PlatformEndpoint.base}/api/pos/licence/activate',
      );
    });
  });

  group('the platform address is shown and editable', () {
    test('an unset licence server falls back to the build default', () {
      const draft = SetupDraft();

      // Null on almost every till. The pane renders PlatformEndpoint.base in
      // its place, so the address is always VISIBLE even when nobody typed it.
      expect(draft.deployment.licenceServerUrl, isNull);
    });

    test('a typed address survives a config round-trip', () {
      // Persisted because RENEWAL uses it too: a till activated against a
      // staging platform must not silently renew against production nine
      // months later.
      const config = DeploymentConfig(
        mode: DeploymentMode.offline,
        licenceServerUrl: 'http://192.168.1.20:8080',
      );

      expect(
        DeploymentConfig.fromJson(config.toJson()).licenceServerUrl,
        'http://192.168.1.20:8080',
      );
    });

    test('it is kept in offline mode, where base_url is not', () {
      // `base_url` is dropped for a mode that has no platform address. This one
      // must not be: an offline terminal has no other address for anything and
      // still has to renew.
      const config = DeploymentConfig(
        mode: DeploymentMode.offline,
        baseUrl: 'https://xorder.io',
        licenceServerUrl: 'http://localhost:8080',
      );
      final restored = DeploymentConfig.fromJson(config.toJson());

      expect(
        restored.baseUrl,
        isNull,
        reason: 'offline has no platform address',
      );
      expect(restored.licenceServerUrl, 'http://localhost:8080');
    });

    test('blanking it returns the terminal to the default', () {
      const config = DeploymentConfig(
        mode: DeploymentMode.offline,
        licenceServerUrl: 'http://192.168.1.20:8080',
      );

      // copyWith cannot assign null, so clearing needs its own flag — without
      // it a typed address could be changed but never taken back.
      expect(
        config.copyWith(clearLicenceServerUrl: true).licenceServerUrl,
        isNull,
      );
    });
  });

  group('why activation failed', () {
    // Every one of these used to be the same sentence: "that licence key was
    // not recognised". Four of the five are not about the key at all, and the
    // one that is still needs to say WHICH platform refused it — a key minted
    // on a local stack and typed into a till built for production is a correct
    // key meeting the wrong server, and "not recognised" sends the installer
    // hunting for a typo that does not exist.
    Future<LicenceNotice?> noticeFor(_CapturingAdapter adapter) async {
      final api = PlatformLicenceApi(
        client: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
        baseUrl: () => 'https://xorder.io',
      );
      return (await api.fetchByKey('PY0X-BSX7-2R2G-75B6', 'fp-1')).notice;
    }

    test('an unknown key names the platform that refused it', () async {
      final notice = await noticeFor(_CapturingAdapter('{}', status: 404));

      expect(notice, isA<LicenceKeyNotRecognised>());
      expect((notice! as LicenceKeyNotRecognised).address, 'https://xorder.io');
    });

    test('an unreachable platform is not the key\'s fault', () async {
      final notice = await noticeFor(_CapturingAdapter('', throws: true));

      expect(notice, isA<LicenceServerUnreachable>());
      expect(
        (notice! as LicenceServerUnreachable).address,
        'https://xorder.io',
      );
    });

    test('a throttled attempt says to wait, not that the key is wrong', () async {
      // An installer retrying a key they believe in WILL hit the per-key limit,
      // and being told "not recognised" at that moment is the opposite of true.
      expect(
        await noticeFor(_CapturingAdapter('{}', status: 429)),
        isA<TooManyLicenceAttempts>(),
      );
    });

    test('a revoked licence is a commercial fact, not a typo', () async {
      expect(
        await noticeFor(_CapturingAdapter('{}', status: 403)),
        isA<LicenceRevoked>(),
      );
    });

    test('a full licence is its own answer: right key, nothing withdrawn', () async {
      // 409 with the platform's code. Not "revoked" (403) and not "not
      // recognised" (404): an installer told either would hunt for a problem
      // that is not there, when the fix is to release or add a device.
      final notice = await noticeFor(
        _CapturingAdapter('{"code":"licence_seats_full","seats":1}', status: 409),
      );

      expect(notice, isA<LicenceSeatsFull>());
      expect((notice! as LicenceSeatsFull).seats, 1);
    });

    test('any other 409 stays an unexplained refusal, not a guess', () async {
      final notice = await noticeFor(_CapturingAdapter('{"code":"other"}', status: 409));

      expect(notice, isA<LicenceServerRefused>());
      expect((notice! as LicenceServerRefused).status, 409);
    });

    test('a server error carries its status so it can be diagnosed', () async {
      final notice = await noticeFor(
        _CapturingAdapter('oops', status: 502, contentType: 'text/plain'),
      );

      expect(notice, isA<LicenceServerRefused>());
      expect((notice! as LicenceServerRefused).status, 502);
    });

    test(
      'a 200 that is not a licence is the address answering, not the key',
      () async {
        // A captive portal, a proxy, the wrong service entirely.
        final notice = await noticeFor(
          _CapturingAdapter('<html>hello</html>', contentType: 'text/html'),
        );

        expect(notice, isA<LicenceServerRefused>());
        expect((notice! as LicenceServerRefused).status, 200);
      },
    );
  });

  group('a licence issued to a customer who is not a tenant', () {
    test('parses and evaluates exactly like any other', () {
      // The platform signs the customer's own name and identifier into the same
      // two claims a hosted tenant fills. The till cannot tell the difference,
      // and must not need to.
      final claims = LicenseClaims.fromJson({
        'license_id': 'LIC-2026-0007',
        'tenant_slug': 'al-asima',
        'tenant_name': 'Al Asima Grill',
        'issued_at': DateTime(2026, 9, 1).toIso8601String(),
        'expires_at': DateTime(2027, 9, 1).toIso8601String(),
        'max_terminals': 3,
        'modes': ['offline'],
      });

      expect(claims.tenantSlug, 'al-asima');
      expect(claims.tenantName, 'Al Asima Grill');
      expect(claims.modes, {DeploymentMode.offline});
      expect(claims.maxTerminals, 3);
    });

    test('carries a user cap, and a missing one means unlimited', () {
      // The two numbers an offline licence actually sells. `max_users` is the
      // enforceable one — a till cannot see its sibling machines, but every
      // staff row is in the database it is already reading.
      final capped = LicenseClaims.fromJson({
        'license_id': 'LIC-2026-0009',
        'tenant_slug': 'al-asima',
        'tenant_name': 'Al Asima Grill',
        'issued_at': DateTime(2026, 9, 1).toIso8601String(),
        'expires_at': DateTime(2027, 9, 1).toIso8601String(),
        'max_terminals': 3,
        'max_users': 8,
        'modes': ['offline'],
      });
      expect(capped.maxUsers, 8);

      // A licence signed before this claim existed must read as unlimited, not
      // as zero — zero would lock every already-installed till out of adding
      // anybody the moment it was updated.
      final legacy = LicenseClaims.fromJson({
        'license_id': 'LIC-2026-0001',
        'tenant_slug': 'al-asima',
        'tenant_name': 'Al Asima Grill',
        'issued_at': DateTime(2026, 9, 1).toIso8601String(),
        'expires_at': DateTime(2027, 9, 1).toIso8601String(),
        'modes': ['offline'],
      });
      expect(legacy.maxUsers, isNull);
    });

    test('grants every feature rather than a plan slice', () {
      // There is no feature ladder on a machine we do not run.
      final claims = LicenseClaims.fromJson({
        'license_id': 'LIC-2026-0010',
        'tenant_slug': 'al-asima',
        'tenant_name': 'Al Asima Grill',
        'issued_at': DateTime(2026, 9, 1).toIso8601String(),
        'expires_at': DateTime(2027, 9, 1).toIso8601String(),
        'features': ['qr_menu', 'dine_in', 'pos', 'takeaway'],
        'plan': null,
        'modes': ['offline'],
      });

      expect(claims.plan, isNull);
      expect(claims.features, contains('pos'));
    });

    test(
      'a lifetime term is an ordinary date the till simply never reaches',
      () {
        // Stored as a sentinel rather than a null, because `expires_at` is read
        // unconditionally here and a null would not parse — on binaries that
        // verify offline and cannot be updated from the platform.
        final claims = LicenseClaims.fromJson({
          'license_id': 'LIC-2026-0008',
          'tenant_slug': 'al-asima',
          'tenant_name': 'Al Asima Grill',
          'issued_at': DateTime(2026, 9, 1).toIso8601String(),
          'expires_at': DateTime(2099, 12, 31).toIso8601String(),
          'modes': ['offline'],
        });

        expect(claims.expiresAt.year, 2099);

        final entitlement = LicenseVerifier.evaluateClaims(
          claims: claims,
          deployment: const DeploymentConfig(
            mode: DeploymentMode.offline,
            tenantSlug: 'al-asima',
          ),
          now: DateTime(2030, 1, 1),
        );
        expect(entitlement.state, LicenseState.valid);
        expect(entitlement.canOpenShift, isTrue);
        expect(entitlement.canSell, isTrue);
      },
    );
  });
}

/// The three-key document the platform returns, as bytes on the wire.
final _file = jsonEncode({
  'payload': 'cGF5bG9hZA',
  'signature': 'c2ln',
  'key_id': 'v1',
});

/// Captures the request body instead of making one, and answers however the
/// test needs the platform to answer.
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(
    this.response, {
    this.status = 200,
    this.throws = false,
    this.contentType = Headers.jsonContentType,
  });

  final String response;
  final int status;

  /// What a proxy error page or captive portal actually sends back, which is
  /// the case these tests care about.
  final String contentType;

  /// Simulates a platform that cannot be reached at all.
  final bool throws;

  Map<String, Object?>? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    body = (options.data as Map).cast<String, Object?>();
    if (throws) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    return ResponseBody.fromString(
      response,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
