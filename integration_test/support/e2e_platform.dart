import 'dart:convert';
import 'dart:io';

/// The platform half of the end-to-end suite.
///
/// Phase 1 builds the cloud path, so the till under test needs a real server
/// to claim against: this provisions a terminal through the dashboard API and
/// hands back its single-use pairing code — exactly what a manager does before
/// an installer arrives.
///
/// Skips the whole suite when `POS_PLATFORM_URL` is unset, the same bargain
/// `POS_PG_HOST` already makes: a machine with no local API running should say
/// so rather than fail.
abstract final class E2ePlatform {
  static String? get baseUrl => Platform.environment['POS_PLATFORM_URL'];
  static String get slug => Platform.environment['POS_TENANT_SLUG'] ?? 'demo';
  static String get username => Platform.environment['POS_TENANT_USER'] ?? 'admin';
  static String get password =>
      Platform.environment['POS_TENANT_PASSWORD'] ?? 'Demo1234!';

  /// The till PIN of the platform user this suite signs shifts in with.
  ///
  /// On the cloud path the bootstrap bundle REPLACES the till's staff table
  /// with the platform's — so a PIN seeded locally by the test is gone the
  /// moment registration succeeds, and the shift must be opened with the
  /// credential the platform actually sent down. That replacement is the
  /// feature working, not a bug: head office owns who may open a drawer.
  static String get staffPin => Platform.environment['POS_STAFF_PIN'] ?? '4829';

  static Future<Map<String, Object?>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('$baseUrl$path'),
      );
      request.headers.set('accept', 'application/json');
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? const {} : jsonDecode(text);
      return decoded is Map
          ? decoded.cast<String, Object?>()
          : <String, Object?>{'data': decoded};
    } finally {
      client.close(force: true);
    }
  }

  /// Provision a fresh terminal and return its pairing code.
  ///
  /// A new terminal per run, deliberately: codes are single-use, and a suite
  /// that reused one would pass once and fail forever after.
  static Future<String> provisionTerminal({required String name}) async {
    final login = await _call('POST', '/api/auth/login', body: {
      'restaurant': slug,
      'username': username,
      'password': password,
    });
    final token = login['token'] as String?;
    if (token == null) {
      throw StateError('Platform refused $username@$slug — cannot provision.');
    }

    final branches = await _call('GET', '/api/dashboard/branches', token: token);
    final list = (branches['data'] as List?) ?? const [];
    if (list.isEmpty) throw StateError('Tenant $slug has no branches.');
    final branchId = (list.first as Map)['id'];

    final terminal = await _call('POST', '/api/dashboard/pos/terminals',
        // MANUAL on purpose. A dynamic terminal starts the background sync
        // timers, which outlive the test body and trip the harness's
        // "_pendingFrame == null" assertion during teardown. The drain itself
        // is still exercised — the sale screen kicks a pass on settlement —
        // so this costs the suite no coverage.
        body: {'name': name, 'branch_id': branchId, 'sync_policy': 'manual'},
        token: token);
    final id = ((terminal['data'] as Map?) ?? terminal)['id'];
    if (id == null) throw StateError('Provisioning failed: $terminal');

    final code = await _call(
      'POST',
      '/api/dashboard/pos/terminals/$id/pairing-code',
      body: const {},
      token: token,
    );
    final pairing = code['pairing_code'] as String?;
    if (pairing == null) throw StateError('No pairing code: $code');
    return pairing;
  }
}
