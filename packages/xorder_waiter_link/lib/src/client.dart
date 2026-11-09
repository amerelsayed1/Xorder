import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'server.dart' show sessionHeader;
import 'wire.dart';

/// The handheld's side of the waiter link (waiter-app, WA1).
///
/// One object per till the handheld is paired with. It holds the device token
/// (from [pair]) and the current waiter's session (from [signIn]); every call
/// after those carries both. Failures come back as [WaiterLinkFailure] with
/// the till's code, so the screen words them in the waiter's language.
class WaiterLinkClient {
  WaiterLinkClient({
    required this.baseUri,
    this.deviceToken,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient ?? HttpClient();

  /// `http://192.168.1.20:8787` — the till's address on the restaurant LAN.
  final Uri baseUri;
  String? deviceToken;
  String? sessionToken;
  final Duration timeout;
  final HttpClient _http;

  /// Turn the address a waiter typed into a base URI: a bare host gets the
  /// default port, a missing scheme gets `http`.
  static Uri addressToUri(String address, {int defaultPort = defaultWaiterPort}) {
    var text = address.trim();
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.parse(text);
    return uri.replace(port: uri.hasPort ? uri.port : defaultPort, path: '');
  }

  Future<String> hello() async {
    final body = await _call('GET', ['hello'], auth: false);
    if (body['wire'] != waiterWireVersion) {
      throw const WaiterLinkFailure(WaiterError.versionMismatch, 426);
    }
    return body['name'] is String ? body['name'] as String : '';
  }

  /// Exchange the code the till shows for this device's token.
  Future<String> pair({required String code, required String deviceName}) async {
    final body = await _call('POST', ['pair'], auth: false, body: {
      'code': code.trim(),
      'device_name': deviceName,
    });
    final token = body['device_token'];
    if (token is! String || token.isEmpty) {
      throw const WaiterLinkFailure(WaiterError.badRequest, 200);
    }
    deviceToken = token;
    return token;
  }

  Future<WaiterSession> signIn(String pin) async {
    final session = WaiterSession.fromJson(
      await _call('POST', ['sign-in'], session: false, body: {'pin': pin}),
    );
    sessionToken = session.token;
    return session;
  }

  Future<void> signOut() async {
    try {
      await _call('POST', ['sign-out']);
    } on Object {
      // Signing out locally is what matters; the till expires it anyway.
    }
    sessionToken = null;
  }

  Future<WaiterMenu> menu() async => WaiterMenu.fromJson(await _call('GET', ['menu']));

  Future<WaiterFloor> floor() async => WaiterFloor.fromJson(await _call('GET', ['floor']));

  Future<WaiterCheck> check(int tableId) async =>
      WaiterCheck.fromJson(await _call('GET', ['tables', '$tableId', 'check']));

  /// Apply [ops] against the check the waiter is looking at. A table changed
  /// elsewhere meanwhile throws [WaiterCheckChanged] with the till's current
  /// check, so the screen can show it and let the waiter redo the edit.
  Future<WaiterCheck> apply({
    required int tableId,
    required int? version,
    required List<WaiterOp> ops,
  }) async => WaiterCheck.fromJson(
    await _call('POST', ['tables', '$tableId', 'ops'], body: {
      'version': ?version,
      'ops': [for (final op in ops) op.toJson()],
    }),
  );

  void close() => _http.close(force: true);

  Future<Map<String, Object?>> _call(
    String method,
    List<String> path, {
    bool auth = true,
    bool session = true,
    Map<String, Object?>? body,
  }) async {
    final uri = baseUri.replace(pathSegments: ['v$waiterWireVersion', ...path]);
    try {
      final request = await _http.openUrl(method, uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      if (auth) {
        final token = deviceToken;
        if (token == null) throw const WaiterLinkFailure(WaiterError.unpaired, 401);
        request.headers.set(HttpHeaders.authorizationHeader, 'Device $token');
        if (session && sessionToken != null) request.headers.set(sessionHeader, sessionToken!);
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final text = await utf8.decodeStream(response).timeout(timeout);
      final decoded = text.isEmpty ? const <String, Object?>{} : jsonDecode(text);
      final map = decoded is Map ? decoded.cast<String, Object?>() : const <String, Object?>{};
      if (response.statusCode >= 200 && response.statusCode < 300) return map;

      final code = map['code'] is String ? map['code'] as String : WaiterError.unavailable;
      if (code == WaiterError.checkChanged && map['check'] != null) {
        throw WaiterCheckChanged(WaiterCheck.fromJson(map['check']));
      }
      if (code == WaiterError.signInRequired) sessionToken = null;
      throw WaiterLinkFailure(
        code,
        response.statusCode,
        detail: map['reason'] is String
            ? map['reason'] as String
            : (map['detail'] is String ? map['detail'] as String : null),
      );
    } on WaiterLinkFailure {
      rethrow;
    } on TimeoutException {
      throw const WaiterLinkUnreachable();
    } on SocketException {
      throw const WaiterLinkUnreachable();
    } on HttpException {
      throw const WaiterLinkUnreachable();
    } on FormatException {
      throw const WaiterLinkFailure(WaiterError.badRequest, 0);
    }
  }
}

/// The port the till listens on unless told otherwise.
const defaultWaiterPort = 8787;

/// The till answered no. [code] is one of [WaiterError].
class WaiterLinkFailure implements Exception {
  const WaiterLinkFailure(this.code, this.status, {this.detail});
  final String code;
  final int status;

  /// For [WaiterError.refused], the ticket rule's reason; for
  /// [WaiterError.notPermitted], the capability.
  final String? detail;

  @override
  String toString() => 'WaiterLinkFailure($code, $status, $detail)';
}

/// The table changed on another device; [current] is what it is now.
class WaiterCheckChanged extends WaiterLinkFailure {
  const WaiterCheckChanged(this.current) : super(WaiterError.checkChanged, 409);
  final WaiterCheck current;
}

/// The till could not be reached at all: wrong address, off, or no Wi-Fi.
class WaiterLinkUnreachable extends WaiterLinkFailure {
  const WaiterLinkUnreachable() : super('UNREACHABLE', 0);
}
