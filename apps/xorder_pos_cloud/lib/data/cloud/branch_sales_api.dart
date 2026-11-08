import 'package:dio/dio.dart';

import 'package:xorder_pos/core/network/network_log.dart';

import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/branch_sales_source.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/data/cloud/cloud_api.dart';

/// The client half of **POS-BE-029** — the branch view for a cloud till whose
/// database is its own (`docs/coordination/POS_TO_BACKEND.md`).
///
/// Filed, not built: the endpoints do not exist yet, and this is written
/// against the contract as filed and tested against a fake HTTP layer. It
/// lives beside [PosCloudApi] rather than inside it until the backend marks
/// the ask READY — folding it in then is a move, and folding it in now would
/// put an endpoint nobody serves on the class every sync pass uses.
///
/// Same transport rules as [PosCloudApi], deliberately: the device token read
/// per request, and a 4xx/5xx returned as a [CloudReply] rather than thrown.
/// "The platform said no" and "the platform said nothing" lead to different
/// sentences on the branch view, exactly as they lead to different actions in
/// the drain.
class BranchSalesApi {
  BranchSalesApi({
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
               receiveTimeout: const Duration(seconds: 30),
               // Non-2xx is data, not an exception — see [CloudReply].
               validateStatus: (_) => true,
             ),
           );

  final String _base;
  final Dio _client;
  final String? Function() _deviceToken;

  /// `GET /api/pos/branch/sales/summary?business_day=` — the branch totals'
  /// ingredients: one row per terminal of the requesting terminal's branch.
  ///
  /// [actingUserId] is who is looking. The platform checks `reports.view` on
  /// them; the device token alone says which till, not which person.
  Future<CloudReply> summary({
    required DateTime businessDay,
    int? actingUserId,
  }) => _get('/api/pos/branch/sales/summary', {
    'business_day': businessDayWire(businessDay),
    'acting_user_id': ?actingUserId,
  });

  /// `GET /api/pos/branch/sales?terminal_id=&business_day=` — one terminal's
  /// sales, for drill-down.
  Future<CloudReply> terminalSales({
    required String terminalId,
    required DateTime businessDay,
    int? actingUserId,
  }) => _get('/api/pos/branch/sales', {
    'terminal_id': terminalId,
    'business_day': businessDayWire(businessDay),
    'acting_user_id': ?actingUserId,
  });

  Future<CloudReply> _get(String path, Map<String, Object?> query) async {
    final token = _deviceToken();
    try {
      final response = await _client.get<Object?>(
        '$_base$path',
        queryParameters: query,
        options: Options(
          headers: {
            'Accept': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
      );
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

/// The branch view from the platform, for the per-till shape (§3a).
///
/// **Never silently stale.** A refresh that fails returns the last snapshot
/// that succeeded, labelled [BranchSalesFreshness.stale] with the time it was
/// fetched — not an error screen, because the Z still has to be done on a
/// night the internet is down, and not the old figures dressed as new ones,
/// because a manager comparing tills at 11 p.m. must know that POS-02's number
/// is from 9.
///
/// **This till's unsynced sales are a separate count.** Adding them into the
/// platform's figures would double-count every one the moment it synced, and
/// rule 1 — the branch is the sum of its rows — would stop holding. They go
/// in [BranchSalesReading.unsyncedOnThisTill], for the banner.
///
/// The snapshot is held in memory only. A till restarted while offline shows
/// "unavailable" rather than a snapshot from disk; persisting it would be the
/// first thing to add if that proves to matter on a real night.
class PlatformBranchSalesSource implements BranchSalesSource {
  PlatformBranchSalesSource({
    required this.api,
    required this.branchId,
    required this.unsyncedOnThisTill,
    this.actingUserId,
    this.currency = 'EGP',
    this.exponent = 2,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final BranchSalesApi api;

  /// This till's branch. A reply naming any other branch is refused as
  /// unreadable — the backend already 404s it, and this is the till not
  /// taking that on trust (§2: a till never sees another branch's figures).
  final int branchId;

  /// Counts this till's settled, not-yet-delivered sales for a business day
  /// from the local outbox. See `PostgresBranchSalesRepository.unsyncedSalesOn`.
  final Future<int> Function(DateTime businessDay) unsyncedOnThisTill;

  final int? Function()? actingUserId;
  final String currency;
  final int exponent;
  final DateTime Function() clock;

  final _last = <String, _Snapshot>{};

  @override
  Future<BranchSalesReading> summary(DateTime businessDay) async {
    final key = businessDayWire(businessDay);
    final unsynced = await _countUnsynced(businessDay);
    final reply = await api.summary(
      businessDay: businessDay,
      actingUserId: actingUserId?.call(),
    );

    final BranchSalesRefreshFailure failure;
    if (reply.ok) {
      final parsed = _parseSummary(reply.data, businessDay);
      if (parsed != null) {
        final snapshot = _Snapshot(parsed.sales, clock(), parsed.mismatch);
        _last[key] = snapshot;
        return BranchSalesReading(
          freshness: BranchSalesFreshness.live,
          sales: snapshot.sales,
          asOf: snapshot.fetchedAt,
          unsyncedOnThisTill: unsynced,
          totalsMismatch: snapshot.mismatch,
        );
      }
      failure = BranchSalesRefreshFailure.unreadable;
    } else {
      failure = reply.offline
          ? BranchSalesRefreshFailure.offline
          : BranchSalesRefreshFailure.refused;
    }

    final last = _last[key];
    if (last == null) {
      return BranchSalesReading(
        freshness: BranchSalesFreshness.unavailable,
        failure: failure,
        failureCode: reply.code,
        unsyncedOnThisTill: unsynced,
      );
    }
    return BranchSalesReading(
      freshness: BranchSalesFreshness.stale,
      sales: last.sales,
      asOf: last.fetchedAt,
      failure: failure,
      failureCode: reply.code,
      unsyncedOnThisTill: unsynced,
      totalsMismatch: last.mismatch,
    );
  }

  /// One other terminal's sales. No snapshot to fall back on: §3a says
  /// drilling into another terminal needs the connection, and a cached list
  /// of somebody else's sales is a list nobody can act on.
  Future<BranchTerminalSalesReading> terminalSales(
    String terminalId,
    DateTime businessDay,
  ) async {
    final reply = await api.terminalSales(
      terminalId: terminalId,
      businessDay: businessDay,
      actingUserId: actingUserId?.call(),
    );
    if (!reply.ok) {
      return BranchTerminalSalesReading(
        freshness: BranchSalesFreshness.unavailable,
        failure: reply.offline
            ? BranchSalesRefreshFailure.offline
            : BranchSalesRefreshFailure.refused,
        failureCode: reply.code,
      );
    }
    final sales = _parseSales(reply.body, terminalId, businessDay);
    if (sales == null) {
      return const BranchTerminalSalesReading(
        freshness: BranchSalesFreshness.unavailable,
        failure: BranchSalesRefreshFailure.unreadable,
      );
    }
    return BranchTerminalSalesReading(
      freshness: BranchSalesFreshness.live,
      sales: sales,
      asOf: clock(),
    );
  }

  /// A count that cannot be read is reported as unknown, not as zero: "0 sales
  /// waiting" is a claim, and a false one is how a manager closes a day that
  /// has money missing from it.
  Future<int?> _countUnsynced(DateTime businessDay) async {
    try {
      return await unsyncedOnThisTill(businessDay);
    } on Object {
      return null;
    }
  }

  ({BranchSales sales, bool mismatch})? _parseSummary(
    Map<String, Object?> data,
    DateTime businessDay,
  ) {
    try {
      if (_int(data['branch_id']) != branchId) return null;
      if (data['business_day'] != businessDayWire(businessDay)) return null;
      final code = data['currency'] is String
          ? data['currency'] as String
          : currency;
      final exp = data.containsKey('exponent')
          ? _require(data['exponent'])
          : exponent;
      Money money(Object? minor) =>
          Money(_require(minor), currency: code, exponent: exp);

      final rows = data['terminals'];
      if (rows is! List) return null;
      final sales = BranchSales(
        branchId: branchId,
        businessDay: businessDay,
        currency: code,
        exponent: exp,
        terminals: List.unmodifiable([
          for (final row in rows) _terminal(_map(row), money),
        ]),
      );

      // The platform's own totals are read only to be checked. What the till
      // shows is the sum of the rows, whatever the platform thinks it is.
      var mismatch = false;
      if (data['totals'] case final Map totals) {
        bool differs(String key, int ours) =>
            totals.containsKey(key) && _int(totals[key]) != ours;
        mismatch =
            differs('orders', sales.orders) ||
            differs('gross_minor', sales.gross.minor) ||
            differs('discount_minor', sales.discounts.minor) ||
            differs('refund_minor', sales.refunds.minor) ||
            differs('net_minor', sales.net.minor);
      }
      return (sales: sales, mismatch: mismatch);
    } on _Unreadable {
      return null;
    }
  }

  TerminalSales _terminal(
    Map<String, Object?> row,
    Money Function(Object?) money,
  ) {
    final id = row['terminal_id'];
    if (id is! String || id.isEmpty) throw const _Unreadable();
    final methods = row['payments'] ?? const <Object?>[];
    if (methods is! List) throw const _Unreadable();
    return TerminalSales(
      terminalId: id,
      name: row['name'] is String ? row['name'] as String : null,
      orders: _require(row['orders']),
      gross: money(row['gross_minor']),
      discounts: money(row['discount_minor']),
      refunds: money(row['refund_minor']),
      refundCount: _require(row['refund_count']),
      lastReceivedAt: switch (row['last_received_at']) {
        final String at => DateTime.tryParse(at)?.toLocal(),
        _ => null,
      },
      payments: List.unmodifiable([
        for (final raw in methods) _method(_map(raw), money),
      ]),
    );
  }

  MethodTotal _method(Map<String, Object?> row, Money Function(Object?) money) {
    final label = row['label'];
    final cash = row['counts_as_cash'];
    // The cash flag decides rule 3's cash figure, so a row without one is not
    // guessed at. Defaulting it to false would move a drawer's cash into
    // "other" on a screen a manager reconciles the drawer against.
    if (label is! String || cash is! bool) throw const _Unreadable();
    return MethodTotal(
      tenderTypeId: _int(row['tender_type_id']),
      label: label,
      // The platform's vocabulary, not the till's — `cash | card | external |
      // other` (POS-BE-013) — through the same switch the seeder uses. Read
      // with [TenderKind.fromWire], `external` fell to other: a card taken on
      // the bank's own terminal was electronic when this till took it and
      // other when this screen read it back, leaving electronic short of the
      // settlement slip by every one. An unknown kind from a newer platform is
      // `other` — still collected, never on account, cash only by its flag.
      kind:
          PlatformTenderKind.fromWire(row['kind'] as String?)?.tillKind ??
          TenderKind.other,
      countsAsCash: cash,
      count: _require(row['count']),
      amount: money(row['amount_minor']),
    );
  }

  List<BranchTerminalSale>? _parseSales(
    Map<String, Object?> body,
    String terminalId,
    DateTime businessDay,
  ) {
    try {
      final meta = _map(body['meta']);
      if (meta['terminal_id'] != terminalId) return null;
      if (meta['business_day'] != businessDayWire(businessDay)) return null;
      final code = meta['currency'] is String
          ? meta['currency'] as String
          : currency;
      final exp = meta.containsKey('exponent')
          ? _require(meta['exponent'])
          : exponent;
      Money money(Object? minor) =>
          Money(_require(minor), currency: code, exponent: exp);

      final rows = body['data'];
      if (rows is! List) return null;
      return List.unmodifiable([
        for (final raw in rows)
          switch (_map(raw)) {
            final row => BranchTerminalSale(
              serverId: _require(row['id']),
              clientTransactionId: row['client_transaction_id'] as String?,
              invoiceNumber: row['invoice_number'] as String?,
              settlementStatus: row['settlement_status'] as String?,
              occurredAt: switch (row['created_at']) {
                final String at when DateTime.tryParse(at) != null =>
                  DateTime.parse(at).toLocal(),
                _ => throw const _Unreadable(),
              },
              total: money(row['total_minor']),
              discount: money(row['discount_minor']),
              refunded: money(row['refunded_minor']),
              actingUserId: _int(row['acting_user_id']),
            ),
          },
      ]);
    } on _Unreadable {
      return null;
    } on TypeError {
      // A string field that arrived as something else. Same answer as any
      // other unreadable reply: nothing shown, and the reason on the reading.
      return null;
    }
  }

  /// Integers only. A JSON float is refused, never truncated: POS-BE-007 says
  /// money never travels as one, and a platform that starts sending them has a
  /// bug that rounding here would hide. Laravel's bigint-as-string is accepted.
  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final String v => int.tryParse(v),
    _ => null,
  };

  static int _require(Object? value) => _int(value) ?? (throw const _Unreadable());

  static Map<String, Object?> _map(Object? value) => switch (value) {
    final Map<String, Object?> map => map,
    final Map map => map.cast<String, Object?>(),
    _ => throw const _Unreadable(),
  };
}

class _Snapshot {
  const _Snapshot(this.sales, this.fetchedAt, this.mismatch);

  final BranchSales sales;
  final DateTime fetchedAt;
  final bool mismatch;
}

class _Unreadable implements Exception {
  const _Unreadable();
}
