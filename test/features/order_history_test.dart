import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/payment_status.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';
import 'package:xorder_pos/features/history/presentation/order_detail_pane.dart';
import 'package:xorder_pos/features/history/presentation/order_history_screen.dart';
import 'package:xorder_pos/features/history/presentation/payment_status_chip.dart';

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
      // slower the longer the restaurant has been open.
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
      // Two em dashes: the staff column and the table column.
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('says so when the cap was hit', (tester) async {
      // A short list and a truncated one look identical, and only one of them
      // means "look further back".
      await pump(
        tester,
        orders: [
          for (var i = 0; i < 200; i++)
            order(id: i, invoice: 'INV-$i', occurredAt: at(10)),
        ],
      );
      expect(
        find.textContaining('Showing the newest 200'),
        findsOneWidget,
      );
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
      expect(find.text('666.40'), findsOneWidget);
      expect(find.text('-66.64'), findsOneWidget);
      expect(find.text('59.98'), findsOneWidget);
      // Twice: the list row's total and the pane's. They agree because both
      // read the same written number.
      expect(find.text('93.30'), findsOneWidget);
      expect(find.text('753.04'), findsNWidgets(2));
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
