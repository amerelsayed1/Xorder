import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/network/network_log.dart';

/// Every call the till makes, on the console, as the wire saw it.
///
/// The log exists for one moment: a wizard that says "that code was already
/// used" about a code somebody is holding in their hand. The sentence is the
/// till's; the reply that chose it is the platform's, and until this nothing
/// printed it.
void main() {
  late List<String> lines;
  late Dio client;
  late _Adapter adapter;

  Dio clientWith(_Adapter adapter) =>
      Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter
        ..interceptors.add(NetworkLog(sink: lines.add));

  setUp(() {
    lines = [];
    adapter = _Adapter('{"code":"PAIRING_CODE_USED","message":"used"}', 422);
    client = clientWith(adapter);
  });

  test('a request prints its method, address and body as sent', () async {
    await client.post<Object?>(
      'https://xorder.io/api/pos/terminals/claim',
      data: {'tenant_slug': 'good-cafe', 'pairing_code': 'Q3BQ-WHZ5'},
    );

    expect(lines[0], 'net → POST https://xorder.io/api/pos/terminals/claim');
    expect(
      jsonDecode(lines[1].trim()),
      {'tenant_slug': 'good-cafe', 'pairing_code': 'Q3BQ-WHZ5'},
      reason: 'the pairing code is what is being debugged, so it prints whole',
    );
  });

  test('a reply prints its status, timing and body — 4xx included', () async {
    // validateStatus lets a 422 through as a response, which is how every
    // client in the till is built; the log has to see it as one too.
    await client.post<Object?>(
      'https://xorder.io/api/pos/terminals/claim',
      data: const {},
    );

    expect(
      lines[2],
      matches(
        r'^net ← 422 POST https://xorder\.io/api/pos/terminals/claim \(\d+ ms\)$',
      ),
    );
    expect(lines[3].trim(), '{"code":"PAIRING_CODE_USED","message":"used"}');
  });

  test('credentials are masked, never printed', () async {
    await client.post<Object?>(
      'https://xorder.io/api/pos/auth/login',
      data: {'username': 'amer', 'password': 'hunter2', 'pin': '4321'},
      options: Options(headers: {'Authorization': 'Bearer abcdefgh1234'}),
    );

    expect(lines[0], endsWith('[Bearer …1234]'));
    expect(lines[0], isNot(contains('abcdefgh')));
    final body = jsonDecode(lines[1].trim()) as Map;
    expect(body['username'], 'amer');
    expect(body['password'], '•••');
    expect(body['pin'], '•••');
    expect(lines.join('\n'), isNot(contains('hunter2')));
  });

  test('a transport failure prints its kind and the address', () async {
    final failing = clientWith(_Adapter('', 0, throws: true));

    await expectLater(
      failing.get<Object?>('https://xorder.io/api/pos/bootstrap'),
      throwsA(isA<DioException>()),
    );

    expect(lines.last, startsWith('net ✗ GET https://xorder.io/api/pos/bootstrap'));
    expect(lines.last, contains('connectionError'));
  });

  test('a long body is cut, with its length said', () async {
    final big = clientWith(_Adapter(jsonEncode({'items': List.filled(400, 'x' * 10)}), 200));

    await big.get<Object?>('https://xorder.io/api/pos/bootstrap');

    expect(lines.last, contains('… ('));
    expect(lines.last.length, lessThan(2100));
  });

  test('a release build gets a bare client; a development build gets the log', () {
    // Tests run as a development build.
    final built = posHttpClient(BaseOptions());
    expect(built.interceptors.whereType<NetworkLog>(), hasLength(1));
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, this.status, {this.throws = false});

  final String body;
  final int status;
  final bool throws;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throws) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
