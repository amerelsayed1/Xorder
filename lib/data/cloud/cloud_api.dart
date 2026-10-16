import 'package:dio/dio.dart';

import '../../core/network/network_log.dart';

/// One answer from the platform — status, decoded body, and the POS-BE-019
/// error envelope if there was one. **Never an exception for a 4xx/5xx**: a
/// refused write is data the drain reacts to, and the reaction differs
/// completely by `code` (hold, quarantine, tell the manager). Only the absence
/// of any answer at all — no route, timeout, connection refused — is modelled,
/// as [offline], because "the platform said no" and "the platform said nothing"
/// demand opposite behaviour from a queue.
class CloudReply {
  const CloudReply({required this.status, this.body = const {}});

  const CloudReply.offline() : status = null, body = const {};

  /// Null when the platform could not be reached at all.
  final int? status;
  final Map<String, Object?> body;

  bool get ok => status != null && status! >= 200 && status! < 300;
  bool get offline => status == null;

  /// The machine-readable error code (POS-BE-019). Null on success or when the
  /// server replied without an envelope — the caller's fallback for an
  /// unrecognised or missing code is *retry later, never discard*.
  String? get code => body['code'] as String?;
  String? get message => body['message'] as String?;

  /// The `data` object Laravel resources wrap, or the body itself when the
  /// response is not wrapped. Both shapes exist across the agreed contracts.
  Map<String, Object?> get data => switch (body['data']) {
    final Map<String, Object?> wrapped => wrapped,
    final Map wrapped => wrapped.cast<String, Object?>(),
    _ => body,
  };
}

/// The hosted platform, spoken to directly.
///
/// This is the client half of the agreed `/api/pos/*` contracts in
/// `docs/coordination/BACKEND_TO_POS.md`. It is deliberately dumb: it moves
/// JSON and returns [CloudReply]s, and every decision about what a reply
/// *means* lives with the caller — the drain, the provisioning repository, the
/// sync loop — where it can be tested without a socket.
class PosCloudApi {
  PosCloudApi({
    required String baseUrl,
    String? Function()? deviceToken,
    Dio? client,
  }) : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _deviceToken = deviceToken ?? (() => null),
       _client =
           client ??
           posHttpClient(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               // Non-2xx is data, not an exception — see [CloudReply].
               validateStatus: (_) => true,
             ),
           );

  final String _base;
  final Dio _client;

  /// Where this client points — surfaced in wizard errors, because "route not
  /// found" means nothing until you know which server said it.
  String get baseUrl => _base;

  /// Read per request rather than captured, so a token rotation applies to the
  /// next call without rebuilding the client.
  final String? Function() _deviceToken;

  /// Claim a provisioned terminal with a pairing code — Path A (POS-BE-023).
  /// Unauthenticated by design: the code is the credential.
  Future<CloudReply> claimTerminal({
    required String tenantSlug,
    required String pairingCode,
    required String platform,
    required String appVersion,
    required String fingerprint,
  }) => _post('/api/pos/terminals/claim', {
    'tenant_slug': tenantSlug,
    'pairing_code': pairingCode,
    'platform': platform,
    'app_version': appVersion,
    'fingerprint': fingerprint,
  });

  /// Staff sign-in for Path B. The JWT this returns is used for exactly one
  /// call — [registerTerminal] — and is never stored by the till.
  Future<CloudReply> login({
    required String tenantSlug,
    required String username,
    required String password,
  }) => _post('/api/auth/login', {
    // The server resolves the tenant from this slug; usernames are only
    // unique within one.
    'restaurant': tenantSlug,
    'username': username,
    'password': password,
  });

  /// The tenant's branches, read with the staff JWT during setup — before a
  /// device token exists. `BranchResource` carries `code` and
  /// `supported_order_types` (POS-BE-005, READY).
  Future<CloudReply> listBranches({required String jwt}) => _send(
    () => _client.get<Object?>(
      '$_base/api/dashboard/branches',
      options: _options(bearer: jwt),
    ),
  );

  /// The tenant's terminals, read with the staff JWT during setup.
  ///
  /// Path B used to have no reason to ask: it CREATED a terminal, so what
  /// already existed was irrelevant. It stopped being irrelevant when tenant
  /// creation started leaving terminals provisioned and waiting (owner
  /// decision, 2026-09-05) — registering a new one alongside them is how a
  /// two-seat restaurant ends up with four rows and a seat limit nobody
  /// understands. The wizard reads this to offer the tills that already exist.
  ///
  /// Same `pos.provision` capability the register call already requires, so it
  /// asks for nothing an installer does not already hold.
  Future<CloudReply> listTerminals({required String jwt}) => _send(
    () => _client.get<Object?>(
      '$_base/api/dashboard/pos/terminals',
      options: _options(bearer: jwt),
    ),
  );

  /// Mint a pairing code for a terminal this staff account can provision.
  ///
  /// The till issues a code and immediately redeems it. That looks circular
  /// and is deliberate: it reuses the ONE audited path that turns a
  /// provisioned row into a claimed one, device token and bootstrap bundle
  /// included, so adopting a till from the wizard and adopting it from a code
  /// read off the dashboard are the same operation on the server. No new
  /// endpoint, no second way to mint a device credential.
  Future<CloudReply> issuePairingCode({
    required String jwt,
    required int terminalId,
  }) => _post(
    '/api/dashboard/pos/terminals/$terminalId/pairing-code',
    const {},
    bearer: jwt,
  );

  /// Self-register this terminal — Path B (POS-BE-023).
  Future<CloudReply> registerTerminal({
    required String jwt,
    required String clientTransactionId,
    required String terminalName,
    required int branchId,
    required String platform,
    required String appVersion,
    required String fingerprint,
  }) => _post('/api/pos/terminals/register', {
    'client_transaction_id': clientTransactionId,
    'name': terminalName,
    'branch_id': branchId,
    'platform': platform,
    'app_version': appVersion,
    'fingerprint': fingerprint,
  }, bearer: jwt);

  /// The whole world, one document (POS-BE-023). Device token required.
  Future<CloudReply> bootstrap() => _get('/api/pos/bootstrap');

  /// Server-priced order creation (POS-BE-006). The request is built by
  /// `OutboxDrain.buildOrderRequest`, which is where the shape is tested.
  Future<CloudReply> submitOrder(Map<String, Object?> request) => _post(
    '/api/pos/orders',
    request,
    idempotencyKey: request['client_transaction_id'] as String?,
  );

  /// The four independently idempotent money records from POS-BE-009/010.
  /// They intentionally retain their own endpoints as well as the optional
  /// bulk API: serial drain is easier to recover after one bad record and is
  /// the compatibility path the contract explicitly keeps supported.
  /// POS-BE-014 — a customer created at the counter.
  Future<CloudReply> createCustomer(Map<String, Object?> request) => _post(
    '/api/pos/customers',
    request,
    idempotencyKey: request['client_transaction_id'] as String?,
  );

  Future<CloudReply> openShift(Map<String, Object?> request) => _post(
    '/api/pos/shifts',
    request,
    idempotencyKey: request['client_transaction_id'] as String?,
  );

  Future<CloudReply> closeShift(
    String shiftClientId,
    Map<String, Object?> request,
  ) => _post(
    '/api/pos/shifts/$shiftClientId/close',
    request,
    idempotencyKey: request['client_transaction_id'] as String?,
  );

  Future<CloudReply> recordCashMovement(Map<String, Object?> request) => _post(
    '/api/pos/cash-movements',
    request,
    idempotencyKey: request['client_transaction_id'] as String?,
  );

  Future<CloudReply> submitRefund(Map<String, Object?> request) => _post(
    '/api/pos/refunds',
    request,
    idempotencyKey: request['client_transaction_id'] as String?,
  );

  /// Tiny, frequent, automatic; carries no money (POS-BE-022).
  Future<CloudReply> heartbeat(Map<String, Object?> payload) =>
      _post('/api/pos/terminals/heartbeat', payload);

  /// The online licence verdict (POS-BE-031) — asked on the start screen and
  /// before each shift. Spelled `license` as the contract fixed it.
  Future<CloudReply> checkLicence(Map<String, Object?> payload) =>
      _post('/api/pos/license/check', payload);

  Future<CloudReply> _get(String path) =>
      _send(() => _client.get<Object?>('$_base$path', options: _options()));

  Future<CloudReply> _post(
    String path,
    Map<String, Object?> body, {
    String? bearer,
    String? idempotencyKey,
  }) => _send(
    () => _client.post<Object?>(
      '$_base$path',
      data: body,
      options: _options(bearer: bearer, idempotencyKey: idempotencyKey),
    ),
  );

  Options _options({String? bearer, String? idempotencyKey}) {
    final token = bearer ?? _deviceToken();
    return Options(
      headers: {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        // Belt and braces per POS-BE-007: the body field is authoritative, the
        // header survives layers that only look at headers.
        'Idempotency-Key': ?idempotencyKey,
      },
    );
  }

  Future<CloudReply> _send(Future<Response<Object?>> Function() call) async {
    try {
      final response = await call();
      return CloudReply(
        status: response.statusCode,
        body: switch (response.data) {
          final Map<String, Object?> map => map,
          final Map map => map.cast<String, Object?>(),
          _ => const {},
        },
      );
    } on DioException {
      return const CloudReply.offline();
    }
  }
}
