import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:shared_module/data/cloud/device_token_vault.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:xorder_pos_cloud/data/cloud/cloud_provisioning_repository.dart';

/// Only the owner sets up a cloud till (pos-cloud-sign-in-setup, D3, AC-7).
///
/// The platform lets any account holding `pos.provision` provision a terminal;
/// the till is stricter, and reads the role the login reply carries
/// (`UserResource.role`: `RESTAURANT_ADMIN` for the owner). A refused account
/// must not reach the branch list, the terminal list, a pairing code or a
/// registration — the token it was issued goes no further than the reply.
void main() {
  late _Platform platform;

  CloudProvisioningRepository repository() => CloudProvisioningRepository(
    api: PosCloudApi(
      baseUrl: 'http://127.0.0.1:9',
      client: Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = platform,
    ),
    vault: DeviceTokenVault(),
    database: PosDatabase(credentials: InMemoryPosDbCredentials('unused')),
    config: const DeploymentConfig(
      mode: DeploymentMode.cloud,
      baseUrl: 'http://127.0.0.1:9',
      tenantSlug: 'cafe-nile',
    ),
    fingerprint: () async => 'fingerprint',
  );

  Map<String, Object?> login(String role) => {
    'token': 'jwt-for-$role',
    'data': {
      'role': role,
      'restaurant': {'name': 'Cafe Nile'},
    },
  };

  const branches = {
    'data': [
      {
        'id': 1,
        'name': 'Maadi',
        'code': 'MAADI',
        'supported_order_types': ['takeaway'],
      },
    ],
  };
  const terminals = {'data': <Object?>[]};

  group('signing in', () {
    test('the owner goes on to the branches and the tills', () async {
      platform = _Platform({
        '/api/auth/login': (200, login('RESTAURANT_ADMIN')),
        '/api/dashboard/branches': (200, branches),
        '/api/dashboard/pos/terminals': (200, terminals),
      });

      final result = await repository().connect(
        tenantSlug: 'cafe-nile',
        username: 'owner',
        password: 'secret',
      );

      expect(result.succeeded, isTrue);
      expect(result.tenantName, 'Cafe Nile');
      expect(result.branches.single.name, 'Maadi');
    });

    test('any other account is refused, and nothing more is asked', () async {
      platform = _Platform({
        '/api/auth/login': (200, login('RESTAURANT_STAFF')),
        '/api/dashboard/branches': (200, branches),
        '/api/dashboard/pos/terminals': (200, terminals),
      });

      final result = await repository().connect(
        tenantSlug: 'cafe-nile',
        username: 'manager',
        password: 'secret',
      );

      expect(result.succeeded, isFalse);
      expect(result.code, 'NOT_OWNER');
      expect(platform.paths, ['/api/auth/login']);
    });

    test('a reply with no role is not taken for the owner', () async {
      platform = _Platform({
        '/api/auth/login': (200, {'token': 'jwt', 'data': <String, Object?>{}}),
      });

      final result = await repository().connect(
        tenantSlug: 'cafe-nile',
        username: 'owner',
        password: 'secret',
      );

      expect(result.code, 'NOT_OWNER');
      expect(platform.paths, ['/api/auth/login']);
    });

    test('a wrong password is still a wrong password', () async {
      platform = _Platform({
        '/api/auth/login': (401, {'message': 'These credentials do not match'}),
      });

      final result = await repository().connect(
        tenantSlug: 'cafe-nile',
        username: 'owner',
        password: 'wrong',
      );

      expect(result.code, 'CREDENTIALS_REJECTED');
    });
  });

  group('adopting and registering sign in again, and check again', () {
    test('a non-owner cannot adopt a waiting till', () async {
      platform = _Platform({
        '/api/auth/login': (200, login('RESTAURANT_STAFF')),
      });

      final result = await repository().adoptTerminal(
        tenantSlug: 'cafe-nile',
        username: 'manager',
        password: 'secret',
        terminalId: 11,
      );

      expect(result.claim, isNull);
      expect(result.code, 'NOT_OWNER');
      expect(platform.paths, ['/api/auth/login']);
    });

    test('a non-owner cannot register a new till', () async {
      platform = _Platform({
        '/api/auth/login': (200, login('RESTAURANT_STAFF')),
      });

      final result = await repository().registerManually(
        tenantSlug: 'cafe-nile',
        username: 'manager',
        password: 'secret',
        terminalName: 'Counter 3',
        branchId: 1,
        installId: null,
      );

      expect(result.claim, isNull);
      expect(result.code, 'NOT_OWNER');
      expect(platform.paths, ['/api/auth/login']);
    });

    test('a full till count is said as the platform said it', () async {
      platform = _Platform({
        '/api/auth/login': (200, login('RESTAURANT_ADMIN')),
        '/api/pos/terminals/register': (
          422,
          {
            'code': 'TERMINAL_SEAT_LIMIT',
            'message': 'All 2 tills are in use.',
            'details': {
              'seats': {'max': 2, 'claimed': 2, 'occupied': 2},
            },
          },
        ),
      });

      final result = await repository().registerManually(
        tenantSlug: 'cafe-nile',
        username: 'owner',
        password: 'secret',
        terminalName: 'Counter 3',
        branchId: 1,
        installId: null,
      );

      expect(result.claim, isNull);
      expect(result.code, 'TERMINAL_SEAT_LIMIT');
    });
  });
}

/// A platform that answers each path with a scripted status and JSON body, and
/// remembers the paths it was asked for, in order. A path it was not given is
/// a 404, so an unexpected call shows up as a recorded path, not a hang.
class _Platform implements HttpClientAdapter {
  _Platform(this.replies);

  final Map<String, (int, Map<String, Object?>)> replies;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    paths.add(path);
    final (status, body) = replies[path] ?? (404, const {'message': 'none'});
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
