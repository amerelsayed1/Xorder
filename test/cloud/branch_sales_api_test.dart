import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/cloud/branch_sales_api.dart';
import 'package:xorder_pos/domain/models/branch_sales_source.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';

/// POS-BE-029's client and the per-till branch view it feeds (§3a, C4).
///
/// The endpoint does not exist yet; the platform here is a scripted HTTP
/// layer answering in the shape the ask files.
void main() {
  final day = DateTime(2026, 9, 10);
  const branch = 3;

  Map<String, Object?> method(
    String kind,
    int amount, {
    bool cash = false,
    int id = 1,
  }) => {
    'tender_type_id': id,
    'label': kind,
    'kind': kind,
    'counts_as_cash': cash,
    'count': 1,
    'amount_minor': amount,
  };

  Map<String, Object?> summaryBody({
    int branchId = branch,
    Object gross01 = 67345,
    Map<String, Object?>? totals,
  }) => {
    'data': {
      'branch_id': branchId,
      'business_day': '2026-09-10',
      'currency': 'EGP',
      'exponent': 2,
      'terminals': [
        {
          'terminal_id': 'pos-01',
          'name': 'POS-01',
          'orders': 2,
          'gross_minor': gross01,
          'discount_minor': 5000,
          'refund_minor': 0,
          'refund_count': 0,
          'payments': [
            method('cash', 30000, cash: true, id: 1),
            method('card', 20000, id: 2),
            method('other', 12345, id: 4),
          ],
          'last_received_at': '2026-09-10T20:00:00Z',
        },
        {
          'terminal_id': 'pos-02',
          'name': 'POS-02',
          'orders': 1,
          'gross_minor': 31000,
          'discount_minor': 1000,
          'refund_minor': 7000,
          'refund_count': 1,
          'payments': [method('external', 30000, id: 3)],
        },
        {
          'terminal_id': 'pos-03',
          'name': 'POS-03',
          'orders': 0,
          'gross_minor': 0,
          'discount_minor': 0,
          'refund_minor': 0,
          'refund_count': 0,
          'payments': <Object?>[],
        },
      ],
      'totals': ?totals,
    },
  };

  late _ScriptedPlatform platform;
  late DateTime now;
  late int unsynced;

  PlatformBranchSalesSource source({Future<int> Function(DateTime)? count}) =>
      PlatformBranchSalesSource(
        api: BranchSalesApi(
          baseUrl: 'https://platform.test/',
          deviceToken: () => 'xdt_till_token',
          client: Dio(BaseOptions(validateStatus: (_) => true))
            ..httpClientAdapter = platform,
        ),
        branchId: branch,
        unsyncedOnThisTill: count ?? (_) async => unsynced,
        actingUserId: () => 9,
        clock: () => now,
      );

  setUp(() {
    platform = _ScriptedPlatform();
    now = DateTime(2026, 9, 10, 21, 0);
    unsynced = 0;
  });

  test('asks for its business day with the device token and the operator', () async {
    platform.answer(200, summaryBody());
    await source().summary(day);

    final request = platform.requests.single;
    expect(request.uri.path, '/api/pos/branch/sales/summary');
    expect(request.uri.queryParameters, {
      'business_day': '2026-09-10',
      'acting_user_id': '9',
    });
    expect(request.headers['Authorization'], 'Bearer xdt_till_token');
  });

  test('a live summary is read into rows, and the branch is their sum', () async {
    platform.answer(200, summaryBody());
    final reading = await source().summary(day);

    expect(reading.freshness, BranchSalesFreshness.live);
    expect(reading.asOf, now);
    final sales = reading.sales!;
    expect(sales.terminals.map((t) => t.terminalId), [
      'pos-01',
      'pos-02',
      'pos-03',
    ]);
    expect(sales.gross, const Money(98345));
    expect(sales.net, const Money(85345));
    // The platform's kinds are cash | card | external | other (POS-BE-013).
    // It has no `account`, so nothing on this screen is owed rather than
    // collected — and `other` is takings, beside vouchers.
    expect(sales.onAccount, Money.zero);
    expect(sales.otherTender, const Money(12345));
    expect(sales.electronic, const Money(50000));
    expect(sales.collected, const Money(92345));
    expect(sales.terminal('pos-02')!.refunds, const Money(7000));
    expect(reading.totalsMismatch, isFalse);
  });

  group("the platform's kinds, read the way the till seeds them", () {
    Map<String, Object?> paidWith(List<Map<String, Object?>> payments) => {
      'data': {
        'branch_id': branch,
        'business_day': '2026-09-10',
        'currency': 'EGP',
        'exponent': 2,
        'terminals': [
          {
            'terminal_id': 'pos-01',
            'orders': 1,
            'gross_minor': 10000,
            'discount_minor': 0,
            'refund_minor': 0,
            'refund_count': 0,
            'payments': payments,
          },
        ],
      },
    };

    test('external is electronic — what the bank terminal slip is held against', () async {
      // The till files a platform `external` tender as card
      // (`PlatformTenderKind.tillKind`). Reading the same payment back as
      // other would leave this screen's electronic figure short of the slip
      // by every one of them.
      platform.answer(200, paidWith([method('external', 10000, id: 7)]));
      final sales = (await source().summary(day)).sales!;

      expect(sales.terminal('pos-01')!.payments.single.kind, TenderKind.card);
      expect(sales.electronic, const Money(10000));
      expect(sales.otherTender, Money.zero);
    });

    test('a wallet is read as a wallet, as the offline till files it', () async {
      platform.answer(200, paidWith([method('wallet', 7000, id: 10)]));
      final sales = (await source().summary(day)).sales!;

      expect(sales.terminal('pos-01')!.payments.single.kind, TenderKind.wallet);
      expect(sales.cash, Money.zero);
    });

    test('a kind this build has never heard of is other, and cash only by its flag', () async {
      platform.answer(
        200,
        paidWith([
          method('crypto', 6000, id: 8),
          method('barter', 4000, cash: true, id: 9),
        ]),
      );
      final sales = (await source().summary(day)).sales!;

      expect(
        sales.terminal('pos-01')!.payments.map((m) => m.kind),
        everyElement(TenderKind.other),
      );
      expect(sales.otherTender, const Money(6000));
      // Rule 3: cash is the payment's flag, whatever the kind says.
      expect(sales.cash, const Money(4000));
      expect(sales.electronic, Money.zero);
    });
  });

  test('when it cannot refresh, it shows the last snapshot WITH its fetch time', () async {
    final branchView = source();
    platform.answer(200, summaryBody());
    final fetchedAt = now;
    await branchView.summary(day);

    now = now.add(const Duration(hours: 2));
    platform.offline();
    final reading = await branchView.summary(day);

    expect(reading.freshness, BranchSalesFreshness.stale);
    expect(reading.failure, BranchSalesRefreshFailure.offline);
    expect(reading.asOf, fetchedAt, reason: 'the time it was READ, not now');
    expect(reading.sales!.gross, const Money(98345));
  });

  test('never fetched and offline is unavailable — not a branch of zeros', () async {
    platform.offline();
    final reading = await source().summary(day);

    expect(reading.freshness, BranchSalesFreshness.unavailable);
    expect(reading.sales, isNull);
    expect(reading.asOf, isNull);
    expect(reading.failure, BranchSalesRefreshFailure.offline);
  });

  test('a refusal keeps its code, and still labels the old snapshot', () async {
    final branchView = source();
    platform.answer(200, summaryBody());
    await branchView.summary(day);

    platform.answer(403, {
      'code': 'POS_CAPABILITY_MISSING',
      'message': 'reports.view',
    });
    final reading = await branchView.summary(day);

    expect(reading.freshness, BranchSalesFreshness.stale);
    expect(reading.failure, BranchSalesRefreshFailure.refused);
    expect(reading.failureCode, 'POS_CAPABILITY_MISSING');
  });

  test("this till's unsynced sales are counted beside the totals, never in them", () async {
    unsynced = 3;
    platform.answer(200, summaryBody());
    final reading = await source().summary(day);

    expect(reading.unsyncedOnThisTill, 3);
    expect(reading.sales!.orders, 3, reason: 'the platform said 3; nothing added');
    expect(reading.sales!.gross, const Money(98345));
  });

  test('an unsynced count that cannot be read is unknown, not zero', () async {
    platform.answer(200, summaryBody());
    final reading = await source(
      count: (_) async => throw StateError('database gone'),
    ).summary(day);

    expect(reading.unsyncedOnThisTill, isNull);
    expect(reading.freshness, BranchSalesFreshness.live);
  });

  test("another branch's figures are refused, not shown", () async {
    platform.answer(200, summaryBody(branchId: 99));
    final reading = await source().summary(day);

    expect(reading.freshness, BranchSalesFreshness.unavailable);
    expect(reading.failure, BranchSalesRefreshFailure.unreadable);
  });

  test('a money figure that is not an integer is unreadable, never rounded', () async {
    platform.answer(200, summaryBody(gross01: 67345.5));
    final reading = await source().summary(day);

    expect(reading.freshness, BranchSalesFreshness.unavailable);
    expect(reading.failure, BranchSalesRefreshFailure.unreadable);
  });

  test('platform totals that disagree with its rows are flagged; the rows win', () async {
    platform.answer(
      200,
      summaryBody(totals: {'orders': 3, 'gross_minor': 98346, 'net_minor': 85345}),
    );
    final reading = await source().summary(day);

    expect(reading.totalsMismatch, isTrue);
    expect(reading.sales!.gross, const Money(98345));
  });

  group('drill-down', () {
    Map<String, Object?> salesBody({String terminal = 'pos-02'}) => {
      'data': [
        {
          'id': 8814,
          'client_transaction_id': '8a4b6c1e-0000-4000-8000-000000000001',
          'invoice_number': 'MANS-2026-000042',
          'settlement_status': 'PARTIALLY_REFUNDED',
          'created_at': '2026-09-10T11:00:00Z',
          'total_minor': 30000,
          'discount_minor': 1000,
          'refunded_minor': 0,
          'acting_user_id': 9,
        },
      ],
      'meta': {
        'terminal_id': terminal,
        'business_day': '2026-09-10',
        'currency': 'EGP',
        'exponent': 2,
      },
    };

    test("reads one terminal's sales for the day", () async {
      platform.answer(200, salesBody());
      final reading = await source().terminalSales('pos-02', day);

      expect(platform.requests.single.uri.path, '/api/pos/branch/sales');
      expect(platform.requests.single.uri.queryParameters['terminal_id'], 'pos-02');
      expect(reading.freshness, BranchSalesFreshness.live);
      expect(reading.sales!.single.total, const Money(30000));
      expect(reading.sales!.single.invoiceNumber, 'MANS-2026-000042');
    });

    test('offline is unavailable — there is no cached list of another till', () async {
      platform.offline();
      final reading = await source().terminalSales('pos-02', day);

      expect(reading.freshness, BranchSalesFreshness.unavailable);
      expect(reading.sales, isNull);
    });

    test("a reply about a different terminal is refused", () async {
      platform.answer(200, salesBody(terminal: 'pos-01'));
      final reading = await source().terminalSales('pos-02', day);

      expect(reading.failure, BranchSalesRefreshFailure.unreadable);
    });
  });
}

/// Answers each request with the next scripted reply, and keeps the request.
class _ScriptedPlatform implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final _replies = <(int, Object?)?>[];

  void answer(int status, Object? body) => _replies.add((status, body));

  /// The next request gets no answer at all.
  void offline() => _replies.add(null);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = _replies.removeAt(0);
    if (reply == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(reply.$2),
      reply.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
