import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/password_sign_in.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:xorder_pos_cloud/data/cloud/cloud_password_check.dart';

/// tablet-cloud-onboarding, Stage 4: the platform's verdict on a typed
/// password, over the sign-in call setup already uses.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, [this.body = const {}, this.fail = false]);

  final int status;
  final Map<String, Object?> body;
  final bool fail;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
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

void main() {
  Future<(PasswordVerdict, _Adapter)> ask(_Adapter adapter) async {
    final check = CloudPasswordCheck(
      api: PosCloudApi(
        baseUrl: 'http://127.0.0.1:9',
        client: Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter,
      ),
      tenantSlug: 'cafe-nile',
    );
    final verdict = await check.verify(username: 'rana', password: 'pw');
    return (verdict, adapter);
  }

  test(
    'an accepted login is verified, and asks only the sign-in call',
    () async {
      final (verdict, adapter) = await ask(_Adapter(200, {'token': 'jwt'}));

      expect(verdict, PasswordVerdict.verified);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.path, '/api/auth/login');
      // The business is the saved one, never typed again.
      expect((adapter.requests.single.data as Map)['restaurant'], 'cafe-nile');
    },
  );

  test('401, 403 and 422 are the platform refusing the credentials', () async {
    for (final status in [401, 403, 422]) {
      expect((await ask(_Adapter(status))).$1, PasswordVerdict.rejected);
    }
  });

  test('429 is a throttle, not a wrong password', () async {
    expect((await ask(_Adapter(429))).$1, PasswordVerdict.throttled);
  });

  test('no network, a server error and a 200 with no token are not a verdict '
      'on the password', () async {
    expect(
      (await ask(_Adapter(0, const {}, true))).$1,
      PasswordVerdict.unreachable,
    );
    expect((await ask(_Adapter(500))).$1, PasswordVerdict.unreachable);
    expect((await ask(_Adapter(404))).$1, PasswordVerdict.unreachable);
    expect(
      (await ask(_Adapter(200, const {}))).$1,
      PasswordVerdict.unreachable,
    );
  });
}
