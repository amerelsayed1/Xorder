import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'server.dart' show sessionHeader;
import 'wire.dart';

/// What a handheld asks of whoever holds its tables: the till over the LAN
/// ([WaiterLinkClient]), or the platform over the internet in the cloud
/// flavor, which serves the same wire (POS-BE-033). The screens depend on
/// this and nothing else; tests put a fake behind it.
abstract interface class WaiterClient {
  /// The token the server gave this device on its first sign-in, if any.
  String? get deviceToken;
  set deviceToken(String? value);

  Future<String> hello();

  /// Name and PIN open a session. With no [deviceToken] yet, the server
  /// registers the device as [deviceName] and the returned session carries
  /// the token, which this client keeps.
  Future<WaiterSession> signIn({required String username, required String pin, required String deviceName});

  Future<void> signOut();
  Future<WaiterMenu> menu();
  Future<WaiterFloor> floor();
  Future<WaiterCheck> check(int tableId);
  Future<WaiterCheck> apply({required int tableId, required int? version, required List<WaiterOp> ops});
  void close();
}

/// The handheld's side of the waiter link (waiter-app, WA1; sign-in WA3).
///
/// One object per server the handheld talks to. It holds the device token
/// (from the first [signIn]) and the current waiter's session; every call
/// after those carries both. Failures come back as [WaiterLinkFailure] with
/// the server's code, so the screen words them in the waiter's language.
class WaiterLinkClient implements WaiterClient {
  /// [pinnedSha256] is the till's certificate fingerprint this handheld
  /// confirmed (lower-case hex). With it, the handshake accepts exactly that
  /// certificate; without it, a self-signed certificate is refused with
  /// [WaiterLinkUntrustedCertificate] carrying what was presented, so the
  /// screen can show the fingerprint for the waiter to compare with the till
  /// and confirm. Over `https` to a public host (the cloud flavor) the
  /// platform's trust store decides and no pin is involved.
  WaiterLinkClient({
    required this.baseUri,
    this.deviceToken,
    this.pinnedSha256,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient ?? _httpClientFor(pinnedSha256) {
    _http.badCertificateCallback = _judge;
  }

  static HttpClient _httpClientFor(String? pinned) =>
      // A pin replaces the trust store: nothing else may vouch for the till.
      pinned == null ? HttpClient() : HttpClient(context: SecurityContext(withTrustedRoots: false));

  /// The till's certificate fingerprint, confirmed by the waiter.
  String? pinnedSha256;

  /// What the last refused handshake presented.
  WaiterCertificate? _refused;

  bool _judge(X509Certificate certificate, String host, int port) {
    final presented = WaiterCertificate.fromDer(certificate.der, notAfter: certificate.endValidity);
    if (pinnedSha256 != null && presented.sha256 == pinnedSha256) return true;
    _refused = presented;
    return false;
  }

  /// `http://192.168.1.20:8787` — the till's address on the restaurant LAN —
  /// or `https://demo.xorder.io/api/pos/waiter` in the cloud flavor; the wire
  /// version and the call's path are appended to whatever path it carries.
  final Uri baseUri;
  @override
  String? deviceToken;
  String? sessionToken;
  final Duration timeout;
  final HttpClient _http;

  /// Turn the address a waiter typed into a base URI: a bare host gets the
  /// default port, and the scheme is `https` — the till serves nothing else
  /// (WA4). A typed `http://` is corrected, not honoured.
  static Uri addressToUri(String address, {int defaultPort = defaultWaiterPort}) {
    var text = address.trim();
    if (text.contains('://')) text = text.substring(text.indexOf('://') + 3);
    final uri = Uri.parse('https://$text');
    return uri.replace(port: uri.hasPort ? uri.port : defaultPort, path: '');
  }

  @override
  Future<String> hello() async {
    final body = await _call('GET', ['hello'], auth: false);
    if (body['wire'] != waiterWireVersion) {
      throw const WaiterLinkFailure(WaiterError.versionMismatch, 426);
    }
    return body['name'] is String ? body['name'] as String : '';
  }

  @override
  Future<WaiterSession> signIn({
    required String username,
    required String pin,
    required String deviceName,
  }) async {
    final session = WaiterSession.fromJson(
      await _call('POST', ['sign-in'], auth: deviceToken != null, session: false, body: {
        'username': username.trim(),
        'pin': pin,
        'device_name': deviceName,
      }),
    );
    if (session.deviceToken case final token?) deviceToken = token;
    sessionToken = session.token;
    return session;
  }

  @override
  Future<void> signOut() async {
    try {
      await _call('POST', ['sign-out']);
    } on Object {
      // Signing out locally is what matters; the till expires it anyway.
    }
    sessionToken = null;
  }

  @override
  Future<WaiterMenu> menu() async => WaiterMenu.fromJson(await _call('GET', ['menu']));

  @override
  Future<WaiterFloor> floor() async => WaiterFloor.fromJson(await _call('GET', ['floor']));

  @override
  Future<WaiterCheck> check(int tableId) async =>
      WaiterCheck.fromJson(await _call('GET', ['tables', '$tableId', 'check']));

  /// Apply [ops] against the check the waiter is looking at. A table changed
  /// elsewhere meanwhile throws [WaiterCheckChanged] with the till's current
  /// check, so the screen can show it and let the waiter redo the edit.
  @override
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

  @override
  void close() => _http.close(force: true);

  Future<Map<String, Object?>> _call(
    String method,
    List<String> path, {
    bool auth = true,
    bool session = true,
    Map<String, Object?>? body,
  }) async {
    final uri = baseUri.replace(pathSegments: [
      ...baseUri.pathSegments.where((p) => p.isNotEmpty),
      'v$waiterWireVersion',
      ...path,
    ]);
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
    } on HandshakeException {
      // A certificate the pin did not vouch for — or, with no pin, any
      // self-signed one. Reported with what was presented, never retried in
      // the clear.
      final refused = _refused;
      _refused = null;
      if (refused != null) throw WaiterLinkUntrustedCertificate(refused, pinned: pinnedSha256 != null);
      throw const WaiterLinkUnreachable();
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

/// A certificate a till presented, as the handheld shows it for comparison.
class WaiterCertificate {
  const WaiterCertificate({required this.sha256, this.notAfter});

  factory WaiterCertificate.fromDer(List<int> der, {DateTime? notAfter}) =>
      WaiterCertificate(sha256: crypto.sha256.convert(der).toString(), notAfter: notAfter);

  /// Lower-case hex, 64 characters, no separators — the till's `LanTls` form.
  final String sha256;
  final DateTime? notAfter;

  /// `AB:CD:EF:…`, the shape the till's Settings › Waiter devices prints, so
  /// the two screens a person holds side by side read the same characters.
  String get formatted => [
    for (var i = 0; i + 2 <= sha256.length; i += 2) sha256.substring(i, i + 2),
  ].join(':').toUpperCase();
}

/// The handshake was refused over the till's certificate. With [pinned]
/// false the handheld has never confirmed this till: show [presented] and
/// ask. With [pinned] true the till answered with a certificate other than
/// the confirmed one: either it was set up again, or something is in the
/// middle — say so, and never accept it silently.
class WaiterLinkUntrustedCertificate extends WaiterLinkFailure {
  const WaiterLinkUntrustedCertificate(this.presented, {required this.pinned})
      : super(pinned ? WaiterError.certificateChanged : WaiterError.certificateUntrusted, 0);

  final WaiterCertificate presented;
  final bool pinned;
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
