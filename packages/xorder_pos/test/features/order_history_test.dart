import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/excel_export.dart';
import 'package:xorder_pos/app/labels.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/domain/services/payment_status.dart';
import 'package:xorder_pos/features/admin_mode/admin_messages.dart';
import 'package:xorder_pos/features/history/presentation/history_widgets.dart';
import 'package:xorder_pos/features/history/presentation/order_detail_pane.dart';
import 'package:xorder_pos/features/history/presentation/order_history_screen.dart';
import 'package:xorder_pos/features/history/presentation/payment_status_chip.dart';

import 'package:xorder_pos_test_support/fonts.dart';

/// The order history screen.
///
/// What is asserted here is what a person standing at the till would notice: a
/// list that shows what it says it shows, filters that reach the data layer
/// rather than being applied on top of a list already fetched, a voided order
/// that reads as voided, and totals that are the ones on the receipt.
void main() {
  final today = DateTime.now();
  DateTime at(int hour, {int daysAgo = 0}) => DateTime(
    today.year,
    today.month,
    today.day,
    hour,
  ).subtract(Duration(days: daysAgo));

  OrderRecord order({
    required int id,
    required String invoice,
    required DateTime occurredAt,
    OrderStatus status = OrderStatus.paid,
    OrderType type = OrderType.dineIn,
    String? table,
    String? servedBy,
    int? servedById,
    int total = 26800,
    String? voidedBy,
    String? reason,
    int? paid,
    int refunded = 0,
    DateTime? businessDate,
    String? terminal,
    String? till,
    List<OrderRecordTender> tenders = const [],
    String? customer,
    String? customerPhone,
    String? customerEmail,
    bool platformNumbered = true,
  }) => OrderRecord(
    id: id,
    clientTransactionId: 'txn-$id',
    invoiceNumber: invoice,
    status: status,
    orderType: type,
    occurredAt: occurredAt,
    subtotal: Money(total),
    discount: Money.zero,
    service: Money.zero,
    vat: Money.zero,
    total: Money(total),
    tableLabel: table,
    servedByName: servedBy,
    servedByStaffId: servedById,
    voidedByName: voidedBy,
    voidReason: reason,
    voidedAt: voidedBy == null ? null : occurredAt,
    // A settled sale by default: what the till writes today.
    paidTotal: Money(paid ?? (status == OrderStatus.voided ? 0 : total)),
    refundedTotal: Money(refunded),
    businessDate: businessDate,
    terminalId: terminal,
    terminalName: till,
    tenders: tenders,
    customerId: customer == null ? null : 500 + id,
    customerName: customer,
    customerPhone: customerPhone,
    customerEmail: customerEmail,
    platformNumbered: platformNumbered,
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    // Larger than the default 800×600, which is smaller than any machine this
    // desktop product runs on. The screen is a list beside a 420 pane.
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<FakeOrderHistoryRepository> pump(
    WidgetTester tester, {
    List<OrderRecord> orders = const [],
    Map<int, OrderRecordDetail> details = const {},
    String locale = 'en',
    VoidCallback? onClose,
    PosStaff? viewer = _supervisor,
    List<PosStaff> staff = const [],
    List<TenderMethod> tenders = const [],
    List<HistoryTerminal> terminals = const [],
    BusinessDay? businessDay,
    List<Refund> refunds = const [],
    DateTime? openedAt,
    HistoryPreset preset = HistoryPreset.all,
    DeploymentMode? mode,
  }) async {
    final repository = FakeOrderHistoryRepository(
      orders: orders,
      details: details,
      terminals: terminals,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderHistoryRepositoryProvider.overrideWithValue(repository),
          // Somebody is signed in, through a ROLE. The list reads nothing for
          // an unattended till, and a fixture with bare capabilities would
          // pass against a rule that read `PosStaff.capabilities`.
          signedInStaffProvider.overrideWith(() => _Viewer(viewer)),
          staffDirectoryProvider.overrideWith((ref) async => staff),
          tenderTypesAllProvider.overrideWith((ref) async => tenders),
          businessDayProvider.overrideWith((ref) async => businessDay),
          refundsForOrderProvider.overrideWith((ref, _) async => refunds),
          if (mode != null)
            deploymentProvider.overrideWith(
              () => _FixedDeployment(
                DeploymentConfig.unconfigured.copyWith(
                  mode: mode,
                  baseUrl: 'https://xorder.io',
                ),
              ),
            ),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: OrderHistoryScreen(
            onClose: onClose ?? () {},
            openedAt: openedAt,
            preset: preset,
          ),
        ),
      ),
    );
    // Localisations resolve asynchronously — one frame renders an empty app.
    await tester.pumpAndSettle();
    return repository;
  }

  group('the list', () {
    testWidgets('shows an order per row, newest first', (tester) async {
      await pump(
        tester,
        orders: [
          order(id: 1, invoice: 'HST-000481', occurredAt: at(10)),
          order(id: 2, invoice: 'HST-000482', occurredAt: at(12)),
        ],
      );

      expect(find.text('HST-000481'), findsOneWidget);
      expect(find.text('HST-000482'), findsOneWidget);

      final first = tester.getTopLeft(find.text('HST-000482')).dy;
      final second = tester.getTopLeft(find.text('HST-000481')).dy;
      expect(first, lessThan(second));
    });

    testWidgets('at the narrowest window the table scrolls sideways rather '
        'than overflowing', (tester) async {
      // 1024 is the window's minimum (`main.dart`). Beside the 420 detail
      // pane that leaves the list 604 wide, and its fixed columns alone need
      // more — a Row that ran out of room and reported it on every frame.
      // Found re-hosting this list as the back office's Sales tab (BO-2).
      tester.view.physicalSize = const Size(1024, 700);
      await pump(
        tester,
        orders: [
          order(
            id: 1,
            invoice: 'HST-000481',
            occurredAt: at(10),
            table: 'T12',
            servedBy: 'Nour Adel',
            terminal: 't1',
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('HST-000481'), findsOneWidget);
    });

    testWidgets('says which slice is on screen, and how many', (tester) async {
      // A list showing today without saying so looks like a list of everything,
      // and somebody hunting last week's receipt concludes it is gone.
      await pump(
        tester,
        orders: [
          order(id: 1, invoice: 'A', occurredAt: at(10)),
          order(id: 2, invoice: 'B', occurredAt: at(11)),
        ],
      );
      expect(find.text('Today · 2 orders'), findsOneWidget);
    });

    testWidgets('opens on today, not on everything', (tester) async {
      final repository = await pump(
        tester,
        orders: [
          order(id: 1, invoice: 'TODAY', occurredAt: at(10)),
          order(id: 2, invoice: 'LASTWEEK', occurredAt: at(10, daysAgo: 4)),
        ],
      );

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('LASTWEEK'), findsNothing);
      expect(repository.queries.first.from, isNotNull);
    });

    testWidgets('widening the range reaches the data layer', (tester) async {
      final repository = await pump(
        tester,
        orders: [
          order(id: 1, invoice: 'TODAY', occurredAt: at(10)),
          order(id: 2, invoice: 'LASTWEEK', occurredAt: at(10, daysAgo: 4)),
        ],
      );

      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();

      expect(find.text('LASTWEEK'), findsOneWidget);
      // Re-queried, rather than filtered in the widget over a list it already
      // had — which would silently cap history at whatever the first read
      // returned.
      expect(repository.queries.length, greaterThan(1));
    });

    testWidgets('the empty state distinguishes "none" from "none matching"', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('No orders yet in this period.'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets('a filtered empty state offers a way out', (tester) async {
      await pump(
        tester,
        orders: [order(id: 1, invoice: 'A', occurredAt: at(10))],
      );

      await tester.tap(find.text('Voided'));
      await tester.pumpAndSettle();

      expect(find.text('No orders match these filters.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('a status filter narrows the list', (tester) async {
      await pump(
        tester,
        orders: [
          order(id: 1, invoice: 'PAID-1', occurredAt: at(10)),
          order(
            id: 2,
            invoice: 'VOID-1',
            occurredAt: at(11),
            status: OrderStatus.voided,
            voidedBy: 'Sami Farid',
          ),
        ],
      );

      await tester.tap(find.text('Voided'));
      await tester.pumpAndSettle();

      expect(find.text('VOID-1'), findsOneWidget);
      expect(find.text('PAID-1'), findsNothing);
    });

    testWidgets('a second tap on a status chip releases it', (tester) async {
      await pump(
        tester,
        orders: [order(id: 1, invoice: 'PAID-1', occurredAt: at(10))],
      );

      await tester.tap(find.text('Voided'));
      await tester.pumpAndSettle();
      expect(find.text('PAID-1'), findsNothing);

      await tester.tap(find.text('Voided'));
      await tester.pumpAndSettle();
      expect(find.text('PAID-1'), findsOneWidget);
    });

    testWidgets('searching matches the tail of an invoice number', (
      tester,
    ) async {
      await pump(
        tester,
        orders: [
          order(id: 1, invoice: 'HST-000481', occurredAt: at(10)),
          order(id: 2, invoice: 'HST-000482', occurredAt: at(11)),
        ],
      );

      await tester.enterText(find.byType(TextField), '481');
      // Past the 250ms debounce.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('HST-000481'), findsOneWidget);
      expect(find.text('HST-000482'), findsNothing);
    });

    testWidgets('typing does not query on every keystroke', (tester) async {
      final repository = await pump(
        tester,
        orders: [order(id: 1, invoice: 'HST-000481', occurredAt: at(10))],
      );
      final before = repository.queries.length;

      await tester.enterText(find.byType(TextField), '4');
      await tester.enterText(find.byType(TextField), '48');
      await tester.enterText(find.byType(TextField), '481');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // One read for three keystrokes. A query per keystroke against a table
      // holding every sale the branch ever made is a search box that gets
      // slower the longer the business has been open.
      expect(repository.queries.length - before, 1);
    });

    testWidgets('an order with no recorded seller shows a blank, not a guess', (
      tester,
    ) async {
      await pump(
        tester,
        orders: [order(id: 1, invoice: 'OLD', occurredAt: at(10))],
      );
      expect(find.text('OLD'), findsOneWidget);
      // Five em dashes: the staff and table columns, since BO-2 the payment
      // method and till columns, and the customer — each saying "not recorded"
      // rather than guessing.
      expect(find.text('—'), findsNWidgets(5));
    });

    // "Says so when the cap was hit" lived here. There is no cap since BO-3:
    // the list pages, and the pager says how many there are in all — see
    // the group below, which keeps its point (a short list and a cut one
    // must not look alike).
  });

  group('the summary strip and the pager (BO-3)', () {
    /// What a figure reads — the keyed widget's own text, or its text's.
    String figure(WidgetTester tester, Key key) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(key),
                matching: find.byType(Text),
                matchRoot: true,
              )
              .first,
        )
        .data!;

    /// The invoices on screen, top to bottom.
    List<String> listed(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data?.startsWith('INV-') ?? false),
        ),
      ))
        text.data!,
    ];

    String name(int id) => 'INV-${id.toString().padLeft(3, '0')}';

    testWidgets('the four figures are the listed rows\' own sums', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        orders: [
          order(id: 1, invoice: 'PAID', occurredAt: at(9)),
          order(
            id: 2,
            invoice: 'VOID',
            occurredAt: at(10),
            status: OrderStatus.voided,
            total: 10000,
            voidedBy: 'Sami Farid',
          ),
          order(
            id: 3,
            invoice: 'PART',
            occurredAt: at(11),
            total: 50000,
            paid: 20000,
          ),
          order(
            id: 4,
            invoice: 'BACK',
            occurredAt: at(12),
            status: OrderStatus.partiallyRefunded,
            total: 30000,
            refunded: 10000,
          ),
          order(
            id: 5,
            invoice: 'GONE',
            occurredAt: at(13),
            status: OrderStatus.refunded,
            total: 15000,
            refunded: 15000,
          ),
        ],
      );

      // 268.00 + 500.00 + 300.00. The void and the full refund are struck
      // through on the list, and a total that added them back would disagree
      // with the rows under it.
      expect(figure(tester, OrderHistoryScreen.summaryTotalKey), '1,068.00 EGP');
      expect(figure(tester, OrderHistoryScreen.summaryCountKey), '5');
      expect(find.text('Of which 2 voided or refunded'), findsOneWidget);
      // Taken, before refunds: 268.00 + 200.00 + 300.00.
      expect(figure(tester, OrderHistoryScreen.summaryPaidKey), '768.00 EGP');
      // Only the part-paid sale owes. The void reads UNPAID too, and owes
      // nothing to anybody.
      expect(
        figure(tester, OrderHistoryScreen.summaryOutstandingKey),
        '300.00 EGP',
      );
      // Asked of the data layer with the list's own filter.
      expect(repository.summaries.last, repository.queries.last.unpaged);
    });

    testWidgets('a cashier\'s figures are their own sales\', not the '
        'branch\'s', (tester) async {
      // Through the role (`_cashier`), as every fixture here.
      final repository = await pump(
        tester,
        viewer: _cashier,
        orders: [
          order(
            id: 1,
            invoice: 'MINE',
            occurredAt: at(9),
            servedById: 4,
            total: 10000,
          ),
          order(
            id: 2,
            invoice: 'THEIRS',
            occurredAt: at(10),
            servedById: 9,
            total: 99900,
          ),
        ],
      );

      expect(figure(tester, OrderHistoryScreen.summaryTotalKey), '100.00 EGP');
      expect(figure(tester, OrderHistoryScreen.summaryCountKey), '1');
      expect(repository.summaries, isNotEmpty);
      expect(
        repository.summaries.map((q) => q.servedByStaffId),
        everyElement(4),
      );
      // /orders is still the cashier's screen: its title and its way out.
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('pages through every row exactly once, across a tie', (
      tester,
    ) async {
      // Tall enough that a whole page is built, so what is on screen is the
      // page and not the part of it the viewport reached.
      tester.view.physicalSize = const Size(1440, 2600);
      // Newest first: 45 sales after one o'clock, then fifteen on one
      // instant at noon — the fiftieth row is in the middle of them — then
      // sixty in the morning.
      final repository = await pump(
        tester,
        orders: [
          for (var i = 1; i <= 120; i++)
            order(
              id: i,
              invoice: name(i),
              occurredAt: i <= 45
                  ? at(13).add(Duration(minutes: i))
                  : i <= 60
                  ? at(12)
                  : at(8).add(Duration(minutes: i)),
            ),
        ],
      );
      final expected = [
        for (var i = 45; i >= 1; i--) name(i),
        // One instant, told apart by id — the ORDER BY's tie-break.
        for (var i = 60; i >= 46; i--) name(i),
        for (var i = 120; i >= 61; i--) name(i),
      ];

      final seen = [...listed(tester)];
      expect(figure(tester, OrderHistoryScreen.pagerRangeKey), '1–50');
      expect(figure(tester, OrderHistoryScreen.pagerTotalKey), '120');
      expect(figure(tester, OrderHistoryScreen.pagerPageKey), '1 / 3');
      expect(find.text('Today · 120 orders'), findsOneWidget);
      final summaries = repository.summaries.length;

      await tester.tap(find.byKey(OrderHistoryScreen.nextPageKey));
      await tester.pumpAndSettle();
      seen.addAll(listed(tester));
      expect(figure(tester, OrderHistoryScreen.pagerRangeKey), '51–100');
      expect(figure(tester, OrderHistoryScreen.pagerPageKey), '2 / 3');

      await tester.tap(find.byKey(OrderHistoryScreen.nextPageKey));
      await tester.pumpAndSettle();
      seen.addAll(listed(tester));
      expect(figure(tester, OrderHistoryScreen.pagerRangeKey), '101–120');
      expect(
        tester
            .widget<PosButton>(find.byKey(OrderHistoryScreen.nextPageKey))
            .onPressed,
        isNull,
      );

      // Every row once, in list order: nothing repeated at a page boundary,
      // nothing skipped in the tie across the first.
      expect(seen, expected);
      expect(
        repository.summaries.length,
        summaries,
        reason: 'turning a page re-reads the rows, not the totals',
      );

      await tester.tap(find.byKey(OrderHistoryScreen.previousPageKey));
      await tester.pumpAndSettle();
      expect(listed(tester), expected.sublist(50, 100));
    });

    testWidgets('a new filter starts again at page one', (tester) async {
      await pump(
        tester,
        orders: [
          for (var i = 1; i <= 60; i++)
            order(
              id: i,
              invoice: name(i),
              occurredAt: at(8).add(Duration(minutes: i)),
            ),
        ],
      );
      await tester.tap(find.byKey(OrderHistoryScreen.nextPageKey));
      await tester.pumpAndSettle();
      expect(figure(tester, OrderHistoryScreen.pagerRangeKey), '51–60');

      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      expect(figure(tester, OrderHistoryScreen.pagerRangeKey), '1–50');
      expect(figure(tester, OrderHistoryScreen.pagerPageKey), '1 / 2');
    });

    testWidgets('one page says how many, and offers nowhere to go', (
      tester,
    ) async {
      await pump(
        tester,
        orders: [
          order(id: 1, invoice: name(1), occurredAt: at(9)),
          order(id: 2, invoice: name(2), occurredAt: at(10)),
        ],
      );
      expect(figure(tester, OrderHistoryScreen.pagerRangeKey), '1–2');
      expect(figure(tester, OrderHistoryScreen.pagerTotalKey), '2');
      expect(find.byKey(OrderHistoryScreen.nextPageKey), findsNothing);
      expect(find.byKey(OrderHistoryScreen.previousPageKey), findsNothing);
    });

    testWidgets('in Arabic the words are Arabic and every figure reads left '
        'to right', (tester) async {
      await pump(
        tester,
        locale: 'ar',
        orders: [
          for (var i = 1; i <= 60; i++)
            order(
              id: i,
              invoice: name(i),
              occurredAt: at(8).add(Duration(minutes: i)),
            ),
        ],
      );

      expect(find.text('إجمالي المبيعات'), findsOneWidget);
      expect(find.text('الفواتير'), findsOneWidget);
      expect(find.text('المدفوع'), findsOneWidget);
      expect(find.text('المتبقي'), findsOneWidget);
      expect(find.text('عرض'), findsOneWidget);
      expect(find.text('التالي'), findsOneWidget);
      expect(find.text('السابق'), findsOneWidget);
      expect(figure(tester, OrderHistoryScreen.pagerRangeKey), '1–50');
      for (final key in [
        OrderHistoryScreen.pagerRangeKey,
        OrderHistoryScreen.pagerTotalKey,
        OrderHistoryScreen.pagerPageKey,
        OrderHistoryScreen.summaryCountKey,
      ]) {
        expect(tester.widget<Text>(find.byKey(key)).textDirection,
            TextDirection.ltr);
      }
      // Read from the right: "عرض" before the range, the range before "من".
      final words = tester.getCenter(find.text('عرض')).dx;
      final range = tester.getCenter(
        find.byKey(OrderHistoryScreen.pagerRangeKey),
      ).dx;
      final of = tester.getCenter(find.text('من')).dx;
      expect(words, greaterThan(range));
      expect(range, greaterThan(of));
      expect(tester.takeException(), isNull);
    });
  });

  group('the detail pane', () {
    OrderRecordDetail detail(OrderRecord record) => OrderRecordDetail(
      order: record,
      lines: [
        OrderRecordLine(
          id: 1,
          lineKey: 'L1',
          name: 'Koshari',
          quantity: 2,
          unitPrice: const Money(5000),
          lineTotal: const Money(10000),
        ),
        OrderRecordLine(
          id: 2,
          lineKey: 'L2',
          name: 'Mint tea',
          quantity: 1,
          unitPrice: const Money(2500),
          lineTotal: const Money(2500),
          voidedAt: DateTime(2026, 9, 7),
          voidedByName: 'Sami Farid',
        ),
      ],
      payments: const [
        OrderRecordPayment(label: 'Cash', amount: Money(26800)),
      ],
      discounts: const [
        OrderRecordDiscount(
          name: 'Staff meal',
          amount: Money(1000),
          lineKey: 'L1',
          appliedByName: 'Nour Adel',
          approvedByName: 'Hana Mostafa',
        ),
      ],
    );

    testWidgets('asks for an order before it shows one', (tester) async {
      await pump(
        tester,
        orders: [order(id: 1, invoice: 'A', occurredAt: at(10))],
      );
      expect(find.text('Pick an order to see it.'), findsOneWidget);
    });

    testWidgets('opens the order that was tapped', (tester) async {
      final record = order(
        id: 1,
        invoice: 'HST-000481',
        occurredAt: at(10),
        table: 'T12',
        servedBy: 'Nour Adel',
      );
      await pump(
        tester,
        orders: [record],
        details: {1: detail(record)},
      );

      await tester.tap(find.text('HST-000481'));
      await tester.pumpAndSettle();

      expect(find.text('Koshari'), findsOneWidget);
      expect(find.text('Served by: Nour Adel'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
    });

    testWidgets("a cloud till lists a sale the platform has not numbered as "
        'provisional (XORD-058)', (tester) async {
      final waiting = order(
        id: 1,
        invoice: 'BR8-000007',
        occurredAt: at(10),
        platformNumbered: false,
      );
      final sent = order(
        id: 2,
        invoice: 'BR8-2026-000013',
        occurredAt: at(12),
        platformNumbered: true,
      );
      await pump(
        tester,
        orders: [waiting, sent],
        details: {1: detail(waiting)},
        mode: DeploymentMode.cloud,
      );

      // The till's own number is not what the dashboard calls this sale.
      expect(find.text('BR8-000007'), findsNothing);
      expect(find.text('PROVISIONAL'), findsOneWidget);
      expect(find.text('BR8-2026-000013'), findsOneWidget);

      await tester.tap(find.text('PROVISIONAL'));
      await tester.pumpAndSettle();
      // The list row and the detail header.
      expect(find.text('PROVISIONAL'), findsNWidgets(2));
      expect(find.text('Koshari'), findsOneWidget);
    });

    testWidgets("an offline till lists its own number, as before", (
      tester,
    ) async {
      await pump(
        tester,
        orders: [
          order(
            id: 1,
            invoice: 'BR8-000007',
            occurredAt: at(10),
            platformNumbered: false,
          ),
        ],
        mode: DeploymentMode.offline,
      );

      expect(find.text('BR8-000007'), findsOneWidget);
      expect(find.text('PROVISIONAL'), findsNothing);
    });

    testWidgets('a voided line stays on the record and names who', (
      tester,
    ) async {
      final record = order(id: 1, invoice: 'A', occurredAt: at(10));
      await pump(tester, orders: [record], details: {1: detail(record)});

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      // It does not vanish — a voided line that disappeared would leave a
      // kitchen docket referring to food nobody can account for.
      expect(find.text('Mint tea'), findsOneWidget);
      expect(find.text('Voided · Sami Farid'), findsOneWidget);
    });

    testWidgets('a discount names its approver, not only its applier', (
      tester,
    ) async {
      final record = order(id: 1, invoice: 'A', occurredAt: at(10));
      await pump(tester, orders: [record], details: {1: detail(record)});

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      expect(find.text('Staff meal'), findsOneWidget);
      // The approver is who a manager asks about later.
      expect(find.text('Approved by Hana Mostafa'), findsOneWidget);
    });

    testWidgets('a void band names who, and why', (tester) async {
      final record = order(
        id: 1,
        invoice: 'A',
        occurredAt: at(10),
        status: OrderStatus.voided,
        voidedBy: 'Sami Farid',
        reason: 'Wrong order',
      );
      await pump(tester, orders: [record], details: {1: detail(record)});

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      expect(find.text('Voided by Sami Farid'), findsOneWidget);
      expect(find.text('Wrong order'), findsOneWidget);
    });

    testWidgets('an order that took no money says so', (tester) async {
      final record = order(
        id: 1,
        invoice: 'A',
        occurredAt: at(10),
        status: OrderStatus.voided,
        voidedBy: 'Sami Farid',
      );
      await pump(
        tester,
        orders: [record],
        details: {
          1: OrderRecordDetail(
            order: record,
            lines: const [],
            payments: const [],
            discounts: const [],
          ),
        },
      );

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(find.text('No payment was taken.'), findsOneWidget);
    });

    testWidgets('the totals are the ones written, not recomputed', (
      tester,
    ) async {
      final record = OrderRecord(
        id: 1,
        clientTransactionId: 'txn',
        invoiceNumber: 'A',
        status: OrderStatus.paid,
        orderType: OrderType.dineIn,
        occurredAt: at(10),
        subtotal: const Money(66640),
        discount: const Money(6664),
        service: const Money(5998),
        vat: const Money(9330),
        total: const Money(75304),
      );
      await pump(
        tester,
        orders: [record],
        details: {
          1: OrderRecordDetail(
            order: record,
            lines: const [],
            payments: const [],
            discounts: const [],
          ),
        },
      );

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      // 666.40 − 66.64 + 59.98 + 93.30 = 753.04. Read, never derived: today's
      // tax configuration must not be able to change what a customer paid.
      expect(find.text('666.40 EGP'), findsOneWidget);
      expect(find.text('-66.64 EGP'), findsOneWidget);
      expect(find.text('59.98 EGP'), findsOneWidget);
      // The list row's total and the pane's, which agree because both read
      // the same written number — and the strip's twice more (BO-3), as the
      // total and, this sale having taken nothing, as what is outstanding.
      expect(find.text('93.30 EGP'), findsOneWidget);
      expect(find.text('753.04 EGP'), findsNWidgets(4));
      expect(
        find.descendant(
          of: find.byType(OrderDetailPane),
          matching: find.text('753.04 EGP'),
        ),
        findsOneWidget,
      );
    });
  });

  group('own sales only', () {
    final mine = order(
      id: 1,
      invoice: 'MINE',
      occurredAt: at(10),
      servedBy: 'Nour Adel',
      servedById: _cashier.id,
    );
    final theirs = order(
      id: 2,
      invoice: 'THEIRS',
      occurredAt: at(11),
      servedBy: 'Hana Mostafa',
      servedById: _supervisor.id,
    );

    testWidgets('a cashier without order.view_all sees no one else\'s', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        viewer: _cashier,
        staff: const [_cashier, _supervisor],
        orders: [mine, theirs],
      );

      expect(find.text('MINE'), findsOneWidget);
      expect(find.text('THEIRS'), findsNothing);
      // Narrowed before it reached the data, on every read — not filtered in
      // the widget over a list that already held everybody's.
      expect(repository.queries, isNotEmpty);
      expect(
        repository.queries.map((q) => q.servedByStaffId),
        everyElement(_cashier.id),
      );
      // Said, and the picker that would pretend otherwise is not drawn.
      expect(find.byKey(OrderHistoryScreen.ownSalesKey), findsOneWidget);
      expect(find.byKey(OrderHistoryScreen.staffFilterKey), findsNothing);
    });

    testWidgets('a role carrying order.view_all sees the branch', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        staff: const [_cashier, _supervisor],
        orders: [mine, theirs],
      );

      expect(find.text('MINE'), findsOneWidget);
      expect(find.text('THEIRS'), findsOneWidget);
      expect(repository.queries.last.servedByStaffId, isNull);
      expect(find.byKey(OrderHistoryScreen.ownSalesKey), findsNothing);
      expect(find.byKey(OrderHistoryScreen.staffFilterKey), findsOneWidget);
    });
  });

  group('filters', () {
    const tenders = [
      TenderMethod(id: 1, code: 'cash', nameEn: 'Cash'),
      TenderMethod(id: 2, code: 'card', nameEn: 'Card'),
    ];
    const tills = [
      HistoryTerminal(id: 't1', name: 'Counter'),
      HistoryTerminal(id: 't2', name: 'Upstairs'),
    ];

    OrderRecordDetail paidWith(OrderRecord record, List<int> tenderIds) =>
        OrderRecordDetail(
          order: record,
          lines: const [],
          payments: [
            for (final id in tenderIds)
              OrderRecordPayment(
                label: id == 1 ? 'Cash' : 'Card',
                amount: const Money(100),
                tenderTypeId: id,
              ),
          ],
          discounts: const [],
        );

    final cashCounter = order(
      id: 1,
      invoice: 'CASH-T1',
      occurredAt: at(9),
      terminal: 't1',
    );
    final cardCounter = order(
      id: 2,
      invoice: 'CARD-T1',
      occurredAt: at(10),
      terminal: 't1',
    );
    final cardUpstairs = order(
      id: 3,
      invoice: 'CARD-T2',
      occurredAt: at(11),
      terminal: 't2',
    );
    final details = {
      1: paidWith(cashCounter, [1]),
      2: paidWith(cardCounter, [1, 2]),
      3: paidWith(cardUpstairs, [2]),
    };

    Future<void> pick(WidgetTester tester, Key filter, String option) async {
      await tester.tap(find.byKey(filter));
      await tester.pumpAndSettle();
      // The open menu's copy, not the one the closed button sizes itself by.
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a payment method narrows the list, split bills included', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        tenders: tenders,
        orders: [cashCounter, cardCounter, cardUpstairs],
        details: details,
      );

      await pick(tester, OrderHistoryScreen.tenderFilterKey, 'Card');

      expect(repository.queries.last.tenderTypeId, 2);
      expect(find.text('CASH-T1'), findsNothing);
      expect(find.text('CARD-T1'), findsOneWidget);
      expect(find.text('CARD-T2'), findsOneWidget);
    });

    testWidgets('one till offers no terminal filter', (tester) async {
      await pump(
        tester,
        terminals: const [HistoryTerminal(id: 't1', name: 'Counter')],
        orders: [cashCounter],
      );
      expect(find.byKey(OrderHistoryScreen.terminalFilterKey), findsNothing);
    });

    testWidgets('a second till does, and it narrows', (tester) async {
      final repository = await pump(
        tester,
        terminals: tills,
        orders: [cashCounter, cardCounter, cardUpstairs],
        details: details,
      );

      await pick(tester, OrderHistoryScreen.terminalFilterKey, 'Upstairs');

      expect(repository.queries.last.terminalId, 't2');
      expect(find.text('CARD-T2'), findsOneWidget);
      expect(find.text('CARD-T1'), findsNothing);
      expect(find.text('CASH-T1'), findsNothing);
    });

    testWidgets('they combine', (tester) async {
      final repository = await pump(
        tester,
        tenders: tenders,
        terminals: tills,
        orders: [cashCounter, cardCounter, cardUpstairs],
        details: details,
      );

      await pick(tester, OrderHistoryScreen.tenderFilterKey, 'Card');
      await pick(tester, OrderHistoryScreen.terminalFilterKey, 'Counter');

      final last = repository.queries.last;
      expect((last.tenderTypeId, last.terminalId), (2, 't1'));
      expect(find.text('CARD-T1'), findsOneWidget);
      expect(find.text('CARD-T2'), findsNothing);
      expect(find.text('CASH-T1'), findsNothing);

      // And "Clear filters" clears the new two as well as the old ones.
      await pick(tester, OrderHistoryScreen.terminalFilterKey, 'Upstairs');
      await pick(tester, OrderHistoryScreen.tenderFilterKey, 'Cash');
      expect(find.text('No orders match these filters.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      // All three back: either filter left set would still hide one of them.
      // Asserted on screen rather than on the last query — the unfiltered read
      // is still cached from when the screen opened, so clearing rightly asks
      // the repository nothing new.
      for (final invoice in ['CASH-T1', 'CARD-T1', 'CARD-T2']) {
        expect(find.text(invoice), findsOneWidget, reason: invoice);
      }
    });
  });

  group('the business day', () {
    // 01:45 on the 11th, with the 10th's business day still open.
    final night = DateTime(2026, 9, 11, 1, 45);
    final tenth = DateTime(2026, 9, 10);
    final orders = [
      order(
        id: 1,
        invoice: 'EVENING',
        occurredAt: DateTime(2026, 9, 10, 20),
        businessDate: tenth,
      ),
      order(
        id: 2,
        invoice: 'PAST-MIDNIGHT',
        occurredAt: DateTime(2026, 9, 11, 1, 30),
        businessDate: tenth,
      ),
      order(
        id: 3,
        invoice: 'NIGHT-BEFORE',
        occurredAt: DateTime(2026, 9, 9, 20),
        businessDate: DateTime(2026, 9, 9),
      ),
    ];

    testWidgets('"Today" is the trading day that is still open', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        openedAt: night,
        businessDay: BusinessDay(
          id: 1,
          date: tenth,
          openedAt: DateTime(2026, 9, 10, 10),
        ),
        orders: orders,
      );

      // One night, one list: the sale at 20:00 and the one at 01:30 together.
      expect(find.text('EVENING'), findsOneWidget);
      expect(find.text('PAST-MIDNIGHT'), findsOneWidget);
      expect(find.text('NIGHT-BEFORE'), findsNothing);
      expect(repository.queries.single.from, tenth);
    });

    testWidgets('with no day open, "Today" is the calendar date', (
      tester,
    ) async {
      final repository = await pump(tester, openedAt: night, orders: orders);
      expect(repository.queries.single.from, DateTime(2026, 9, 11));
    });
  });

  group('payment status', () {
    testWidgets('each row carries its own chip beside the order status', (
      tester,
    ) async {
      await pump(
        tester,
        orders: [
          order(id: 1, invoice: 'A', occurredAt: at(12)),
          order(
            id: 2,
            invoice: 'B',
            occurredAt: at(11),
            status: OrderStatus.partiallyRefunded,
            refunded: 5000,
          ),
          order(
            id: 3,
            invoice: 'C',
            occurredAt: at(10),
            status: OrderStatus.voided,
            voidedBy: 'Sami Farid',
          ),
          order(id: 4, invoice: 'D', occurredAt: at(9), paid: 10000),
        ],
      );

      final chips = tester.widgetList<PaymentStatusChip>(
        find.byType(PaymentStatusChip),
      );
      expect(chips.map((c) => c.status), [
        PaymentStatus.paid,
        PaymentStatus.partiallyRefunded,
        PaymentStatus.unpaid,
        PaymentStatus.partiallyPaid,
      ]);
    });
  });

  group('the attribution caveat', () {
    testWidgets('is not shown for a window the fix already covers', (
      tester,
    ) async {
      await pump(tester, openedAt: DateTime(2026, 9, 10, 12));
      expect(find.byKey(OrderHistoryScreen.attributionCaveatKey), findsNothing);
    });

    testWidgets('is shown once the window reaches back before it', (
      tester,
    ) async {
      await pump(tester, openedAt: DateTime(2026, 9, 10, 12));
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(OrderHistoryScreen.attributionCaveatKey),
        findsOneWidget,
      );
    });

    testWidgets('retires itself once no window reaches that far', (
      tester,
    ) async {
      await pump(tester, openedAt: DateTime(2026, 10, 20, 12));
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();
      expect(find.byKey(OrderHistoryScreen.attributionCaveatKey), findsNothing);
    });
  });

  group('sale details', () {
    final record = order(
      id: 1,
      invoice: 'HST-000481',
      occurredAt: at(10),
      status: OrderStatus.partiallyRefunded,
      refunded: 5000,
    );
    final detail = OrderRecordDetail(
      order: record,
      lines: const [
        OrderRecordLine(
          id: 11,
          lineKey: 'L1',
          name: 'Koshari',
          quantity: 2,
          unitPrice: Money(5000),
          lineTotal: Money(10000),
        ),
      ],
      payments: const [OrderRecordPayment(label: 'Cash', amount: Money(26800))],
      discounts: const [],
      events: [
        SaleEvent(kind: SaleEventKind.printed, at: at(10)),
        SaleEvent(
          kind: SaleEventKind.audit,
          at: at(11),
          actorName: 'Nour Adel',
          approvedByName: 'Sami Farid',
          auditAction: AuditAction.permissionOverridden,
        ),
        SaleEvent(
          kind: SaleEventKind.reprintRequested,
          at: at(12),
          actorName: 'Nour Adel',
        ),
        SaleEvent(kind: SaleEventKind.reprintPending, at: at(12)),
        SaleEvent(
          kind: SaleEventKind.refunded,
          at: at(13),
          actorName: 'Nour Adel',
          amount: const Money(5000),
        ),
      ],
    );
    final given = Refund(
      id: 7,
      clientRefundId: 'refund-7',
      orderId: 1,
      kind: RefundKind.partial,
      subtotal: const Money(5000),
      discount: Money.zero,
      service: Money.zero,
      vat: Money.zero,
      total: const Money(5000),
      occurredAt: at(13),
      refundedByName: 'Nour Adel',
      lines: const [
        RefundLineSelection(
          orderLineId: 11,
          name: 'Koshari',
          quantity: 1,
          unitPrice: Money(5000),
        ),
      ],
      payments: const [
        RefundTender(tenderTypeId: 1, label: 'Cash', amount: Money(5000)),
      ],
    );

    testWidgets('shows both chips in the head', (tester) async {
      await pump(tester, orders: [record], details: {1: detail});
      await tester.tap(find.text('HST-000481'));
      await tester.pumpAndSettle();

      // The row's chip and the pane's — both saying the same derived status.
      final chips = tester.widgetList<PaymentStatusChip>(
        find.byType(PaymentStatusChip),
      );
      expect(chips.map((c) => c.status), [
        PaymentStatus.partiallyRefunded,
        PaymentStatus.partiallyRefunded,
      ]);
    });

    testWidgets('a refund shows the lines it took back and where to', (
      tester,
    ) async {
      await pump(
        tester,
        orders: [record],
        details: {1: detail},
        refunds: [given],
      );
      await tester.tap(find.text('HST-000481'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('refund-line-7-11')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('refund-line-7-11')),
          matching: find.text('Koshari'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('refund-tender-7-0')), findsOneWidget);
    });

    testWidgets('the activity lists what happened, in order', (tester) async {
      await pump(tester, orders: [record], details: {1: detail});
      await tester.tap(find.text('HST-000481'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byType(SaleEventRow).last,
        find.byType(ListView).last,
        const Offset(0, -200),
      );

      final rows = tester.widgetList<SaleEventRow>(find.byType(SaleEventRow));
      expect(rows.map((r) => r.event.kind), [
        SaleEventKind.printed,
        SaleEventKind.audit,
        SaleEventKind.reprintRequested,
        SaleEventKind.reprintPending,
        SaleEventKind.refunded,
      ]);
      // An audit row reads as the Activity pane's sentence for it, never the
      // raw action key.
      expect(
        find.descendant(
          of: find.byType(SaleEventRow).at(1),
          matching: find.text(
            AdminText.auditAction(
              const EnStrings(),
              AuditAction.permissionOverridden,
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(AuditAction.permissionOverridden), findsNothing);
    });
  });

  group('the payment and till columns (BO-2)', () {
    const split = [
      OrderRecordTender(tenderTypeId: 1, label: 'Cash'),
      OrderRecordTender(tenderTypeId: 2, label: 'Card'),
    ];

    testWidgets('a split bill names every method it was paid in, and the '
        'till is named', (tester) async {
      await pump(
        tester,
        orders: [
          order(
            id: 1,
            invoice: 'SPLIT',
            occurredAt: at(10),
            till: 'Upstairs',
            tenders: split,
          ),
        ],
      );

      const s = EnStrings();
      expect(find.text('${s.tenderCash} + ${s.tenderCard}'), findsOneWidget);
      expect(find.text('Upstairs'), findsOneWidget);
    });

    testWidgets('a method the business renamed reads as they named it', (
      tester,
    ) async {
      await pump(
        tester,
        orders: [
          order(
            id: 1,
            invoice: 'A',
            occurredAt: at(10),
            tenders: const [OrderRecordTender(tenderTypeId: 2, label: 'Visa')],
          ),
        ],
      );
      expect(find.text('Visa'), findsOneWidget);
    });

    testWidgets('in Arabic the methods are Arabic and the row reads from the '
        'right', (tester) async {
      await pump(
        tester,
        locale: 'ar',
        orders: [
          order(
            id: 1,
            invoice: 'HST-000481',
            occurredAt: at(10),
            till: 'Upstairs',
            tenders: split,
          ),
        ],
      );

      const s = ArStrings();
      final methods = find.text('${s.tenderCash} + ${s.tenderCard}');
      expect(methods, findsOneWidget);
      expect(
        tester.getCenter(find.text('HST-000481')).dx,
        greaterThan(tester.getCenter(methods).dx),
        reason: 'the invoice at the start edge, which in Arabic is the right',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrower than its columns, it scrolls sideways from its '
        'start in Arabic too', (tester) async {
      tester.view.physicalSize = const Size(1024, 700);
      await pump(
        tester,
        locale: 'ar',
        orders: [
          order(
            id: 1,
            invoice: 'HST-000481',
            occurredAt: at(10),
            till: 'Upstairs',
            tenders: split,
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(OrderHistoryScreen.sidewaysKey), findsOneWidget);
      // Opened at its start — the right, in Arabic, where the list is: the
      // invoice is on screen, not scrolled off past the detail pane.
      final invoice = tester.getRect(find.text('HST-000481'));
      expect(invoice.left, greaterThanOrEqualTo(PosSize.historyDetail));
      expect(invoice.right, lessThanOrEqualTo(1024));
    });
  });

  group('who the sale was for', () {
    final mona = order(
      id: 1,
      invoice: 'INV-1',
      occurredAt: at(10),
      customer: 'Mona Fathy',
      customerPhone: '01012345678',
      customerEmail: 'mona@example.com',
    );
    final nobody = order(id: 2, invoice: 'INV-2', occurredAt: at(11));

    Future<void> openMona(WidgetTester tester) async {
      await pump(
        tester,
        orders: [mona, nobody],
        details: {
          1: OrderRecordDetail(
            order: mona,
            lines: const [],
            payments: const [],
            discounts: const [],
          ),
          2: OrderRecordDetail(
            order: nobody,
            lines: const [],
            payments: const [],
            discounts: const [],
          ),
        },
      );
    }

    testWidgets('the list names the customer, and a dash where there is none', (
      tester,
    ) async {
      await openMona(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('history-customer-1'))).data,
        'Mona Fathy',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('history-customer-2'))).data,
        '—',
      );
    });

    testWidgets('the column is headed Customer', (tester) async {
      await openMona(tester);

      expect(
        find.text(const EnStrings().customersColumnCustomer.toUpperCase()),
        findsOneWidget,
      );
    });

    testWidgets('and absent from Cancelled orders, whose columns are the void', (
      tester,
    ) async {
      final voided = order(
        id: 3,
        invoice: 'INV-3',
        occurredAt: at(12),
        status: OrderStatus.voided,
        voidedBy: 'Hana',
        reason: 'Mistake',
        customer: 'Mona Fathy',
      );
      await pump(tester, orders: [voided], preset: HistoryPreset.voided);

      expect(find.byKey(const Key('history-customer-3')), findsNothing);
      expect(
        find.text(const EnStrings().customersColumnCustomer.toUpperCase()),
        findsNothing,
      );
    });

    testWidgets('the detail gives name, phone and email', (tester) async {
      await openMona(tester);

      await tester.tap(find.text('INV-1'));
      await tester.pumpAndSettle();

      final customer = find.byKey(const Key('order-detail-customer'));
      expect(customer, findsOneWidget);
      expect(
        find.descendant(
          of: customer,
          matching: find.text('Customer: Mona Fathy'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: customer, matching: find.text('01012345678')),
        findsOneWidget,
      );
      expect(find.text('mona@example.com'), findsOneWidget);
    });

    testWidgets('a sale for nobody has no customer line at all', (tester) async {
      await openMona(tester);

      await tester.tap(find.text('INV-2'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('order-detail-customer')), findsNothing);
    });

    testWidgets('a customer with no email has no empty line for it', (tester) async {
      final plain = order(
        id: 4,
        invoice: 'INV-4',
        occurredAt: at(13),
        customer: 'Karim Said',
        customerPhone: '01198765432',
      );
      await pump(
        tester,
        orders: [plain],
        details: {
          4: OrderRecordDetail(
            order: plain,
            lines: const [],
            payments: const [],
            discounts: const [],
          ),
        },
      );

      await tester.tap(find.text('INV-4'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('order-detail-customer')), findsOneWidget);
      expect(
        find.byKey(const Key('order-detail-customer-email')),
        findsNothing,
      );
    });

    testWidgets('the search box says it takes a customer', (tester) async {
      await openMona(tester);

      expect(
        find.text(const EnStrings().orderHistorySearchHint),
        findsOneWidget,
      );
      expect(const EnStrings().orderHistorySearchHint, contains('customer'));
    });

    testWidgets('in Arabic the column and the detail line are in Arabic', (
      tester,
    ) async {
      await pump(
        tester,
        orders: [mona],
        locale: 'ar',
        details: {
          1: OrderRecordDetail(
            order: mona,
            lines: const [],
            payments: const [],
            discounts: const [],
          ),
        },
      );

      expect(
        find.text(const ArStrings().customersColumnCustomer),
        findsOneWidget,
      );
      await tester.tap(find.text('INV-1'));
      await tester.pumpAndSettle();
      expect(
        find.text('${const ArStrings().customersColumnCustomer}: Mona Fathy'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('/orders for a cashier, as it was before the back office held it', () {
    final mine = order(
      id: 1,
      invoice: 'MINE',
      occurredAt: at(10),
      servedBy: 'Nour Adel',
      servedById: _cashier.id,
    );
    final theirs = order(
      id: 2,
      invoice: 'THEIRS',
      occurredAt: at(11),
      servedBy: 'Hana Mostafa',
      servedById: _supervisor.id,
    );

    testWidgets('own sales, its own title, Close and Esc, and the pane asking '
        'the cashier', (tester) async {
      // BO-2 moved whose sales these are from the till's operator to the
      // person ACTING. Nobody is in Admin Mode here, so that is still the
      // cashier — and everything a cashier met on /orders is where it was.
      var closed = 0;
      final repository = await pump(
        tester,
        viewer: _cashier,
        staff: const [_cashier, _supervisor],
        orders: [mine, theirs],
        details: {
          1: OrderRecordDetail(
            order: mine,
            lines: const [],
            payments: const [],
            discounts: const [],
          ),
        },
        onClose: () => closed++,
      );

      const s = EnStrings();
      expect(find.text('MINE'), findsOneWidget);
      expect(find.text('THEIRS'), findsNothing);
      expect(
        repository.queries.map((q) => q.servedByStaffId),
        everyElement(_cashier.id),
      );
      expect(find.byKey(OrderHistoryScreen.ownSalesKey), findsOneWidget);
      expect(find.text(s.orderHistoryTitle), findsOneWidget);

      await tester.tap(find.text('MINE'));
      await tester.pumpAndSettle();
      for (final (capability, label) in [
        (PosCapability.orderRefund, s.refundAction),
        (PosCapability.receiptReprint, s.receiptReprintAction),
      ]) {
        expect(
          find.text(label),
          Authorization.check(_cashier, capability) is Denied
              ? findsNothing
              : findsOneWidget,
          reason: capability,
        );
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closed, 1, reason: 'Esc leaves /orders');
      await tester.tap(find.text(s.close));
      await tester.pumpAndSettle();
      expect(closed, 2);
    });
  });

  group('leaving', () {
    testWidgets('the close button calls back', (tester) async {
      var closed = false;
      await pump(tester, onClose: () => closed = true);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });
  });

  group('Arabic', () {
    testWidgets('renders right to left without overflowing', (tester) async {
      final record = order(
        id: 1,
        invoice: 'HST-000481',
        occurredAt: at(10),
        table: 'T12',
        servedBy: 'نور عادل',
      );
      await pump(
        tester,
        locale: 'ar',
        orders: [record],
        details: {
          1: OrderRecordDetail(
            order: record,
            lines: const [
              OrderRecordLine(
                id: 1,
                lineKey: 'L1',
                name: 'كشري',
                quantity: 2,
                unitPrice: Money(5000),
                lineTotal: Money(10000),
              ),
            ],
            payments: const [
              OrderRecordPayment(label: 'نقدًا', amount: Money(26800)),
            ],
            discounts: const [],
          ),
        },
      );

      expect(find.text('الطلبات'), findsOneWidget);
      await tester.tap(find.text('HST-000481'));
      await tester.pumpAndSettle();
      expect(find.text('كشري'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the invoice number stays left to right', (tester) async {
      // Arabic is RTL; an invoice number is not. Rendered without an explicit
      // direction it would reorder around its separators.
      await pump(
        tester,
        locale: 'ar',
        orders: [order(id: 1, invoice: 'HST-000481', occurredAt: at(10))],
      );

      final directionality = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('HST-000481'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(directionality.textDirection, TextDirection.ltr);
    });
  });

  group('alignment in Arabic', () {
    // The bundled faces, not the test font (every glyph a full em): widths and
    // truncation only mean something drawn in the real ones.
    setUpAll(loadPosFonts);

    /// Where the letters are DRAWN, not the box that holds them. A Text in a
    /// fixed-width cell fills the cell whether its glyphs sit at one edge or the
    /// other, so measuring the widget says nothing about alignment.
    Rect ink(WidgetTester tester, Finder finder) {
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final length = paragraph.text.toPlainText().length;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: length),
      );
      final local = boxes.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b));
      return local.shift(paragraph.localToGlobal(Offset.zero));
    }

    Finder searchBox() => find.descendant(
      of: find.byType(HistorySearchField),
      matching: find.byType(TextField),
    );

    // Left-to-right text (a time, an invoice number, a quantity) must READ left
    // to right and still sit on the language's own start edge. It used to sit
    // on the cell's left: in Arabic the time pressed against the next column's
    // word ("07:15صالة"), away from its own heading.

    OrderRecord oneOrder() => order(
      id: 1,
      invoice: 'HST-000481',
      occurredAt: at(10),
      table: 'A1',
    );

    testWidgets('a time sits under its heading, on the right edge', (tester) async {
      await pump(tester, locale: 'ar', orders: [oneOrder()]);

      final heading = ink(tester, find.text(const ArStrings().orderColumnTime));
      final value = ink(tester, find.text('10:00'));

      // Right edges, where Arabic starts. It was 38 px to the left of this.
      expect(value.right, closeTo(heading.right, 4));
    });

    testWidgets('and in English on the left edge, as before', (tester) async {
      await pump(tester, orders: [oneOrder()]);

      final heading = ink(tester, find.text(const EnStrings().orderColumnTime.toUpperCase()));
      final value = ink(tester, find.text('10:00'));

      expect(value.left, closeTo(heading.left, 4));
    });

    testWidgets('the time does not touch the order type beside it', (tester) async {
      await pump(tester, locale: 'ar', orders: [oneOrder()]);

      final time = ink(tester, find.text('10:00'));
      // `.last`: the same word is also a filter chip above the list.
      final type = ink(tester, find.text(OrderType.dineIn.label(const ArStrings())).last);

      // The type is to the left of the time in Arabic; a clear gap between.
      expect(type.right, lessThan(time.left - 8));
    });

    testWidgets('the invoice number lines up with its heading', (tester) async {
      await pump(tester, locale: 'ar', orders: [oneOrder()]);

      final heading = ink(tester, find.text(const ArStrings().orderColumnInvoice));
      final value = ink(tester, find.text('HST-000481'));

      expect(value.right, closeTo(heading.right, 4));
    });

    testWidgets('the Excel button is at the end of the header, not the middle', (tester) async {
      await pump(tester, locale: 'ar', orders: [oneOrder()], onClose: () {});

      final button = tester.getCenter(find.byType(ExcelExportButton));
      // Arabic ends on the LEFT: well inside the left third of 1440.
      expect(button.dx, lessThan(1440 / 3));
    });

    testWidgets('and at the right end in English', (tester) async {
      await pump(tester, orders: [oneOrder()], onClose: () {});

      final button = tester.getCenter(find.byType(ExcelExportButton));
      expect(button.dx, greaterThan(1440 * 2 / 3));
    });

    testWidgets('a line quantity has room before the item name', (tester) async {
      final record = oneOrder();
      await pump(
        tester,
        locale: 'ar',
        orders: [record],
        details: {
          1: OrderRecordDetail(
            order: record,
            lines: const [
              OrderRecordLine(
                id: 1,
                lineKey: 'L1',
                name: 'Koshari',
                quantity: 2,
                unitPrice: Money(5000),
                lineTotal: Money(10000),
              ),
            ],
            payments: const [],
            discounts: const [],
          ),
        },
      );
      await tester.tap(find.text('HST-000481'));
      await tester.pumpAndSettle();

      final quantity = ink(tester, find.text('2').last);
      final name = ink(tester, find.text('Koshari'));

      // In Arabic the quantity is on the right and the name to its left, with a
      // real gap between them.
      expect(quantity.left - name.right, greaterThan(8));
    });

    testWidgets('the search box is as tall as the filter chips beside it', (tester) async {
      await pump(tester, locale: 'ar', orders: [oneOrder()]);

      final chip = tester.getRect(find.byType(HistoryFilterChip).first);
      final box = tester.getRect(searchBox());
      final typing = tester.getRect(
        find.descendant(of: searchBox(), matching: find.byType(EditableText)),
      );

      expect(box.height, closeTo(chip.height, 1));
      // A TextField is only as tall as its text unless it expands: the box was
      // the chips' height, but its border was drawn round a ~25 px strip pinned
      // to the top. So it must expand, and what is typed must sit in the MIDDLE
      // of the chips' height, not near its top.
      expect(tester.widget<TextField>(searchBox()).expands, isTrue);
      expect((typing.center.dy - box.center.dy).abs(), lessThan(3));
    });

    testWidgets('and wide enough to read its whole hint', (tester) async {
      await pump(tester, locale: 'ar', orders: [oneOrder()]);

      final hint = find.text(const ArStrings().orderHistorySearchHint);
      expect(hint, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(hint).didExceedMaxLines, isFalse);
      expect(tester.getSize(searchBox()).width, greaterThanOrEqualTo(260));
    });

    testWidgets('the three footer buttons keep their words whole', (tester) async {
      final record = oneOrder();
      await pump(
        tester,
        locale: 'ar',
        orders: [record],
        details: {
          1: OrderRecordDetail(
            order: record,
            lines: const [],
            payments: const [OrderRecordPayment(label: 'Cash', amount: Money(26800))],
            discounts: const [],
          ),
        },
      );
      await tester.tap(find.text('HST-000481'));
      await tester.pumpAndSettle();

      // The label is drawn whole: the paragraph did not run out of room.
      final label = find.text(const ArStrings().receiptReprintAction);
      expect(label, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
    });
  });
}

const _supervisor = PosStaff(
  id: 9,
  name: 'Hana Mostafa',
  role: PosRole(
    id: 3,
    code: 'supervisor',
    nameEn: 'Supervisor',
    capabilities: {PosCapability.operate, PosCapability.orderViewAll},
  ),
);

const _cashier = PosStaff(
  id: 4,
  name: 'Nour Adel',
  role: PosRole(
    id: 2,
    code: 'cashier',
    nameEn: 'Cashier',
    capabilities: {PosCapability.operate},
  ),
);

class _Viewer extends SignedInStaffController {
  _Viewer(this.staff);

  final PosStaff? staff;

  @override
  PosStaff? build() => staff;
}

class _FixedDeployment extends DeploymentController {
  _FixedDeployment(this.value);

  final DeploymentConfig value;

  @override
  DeploymentConfig build() => value;
}
