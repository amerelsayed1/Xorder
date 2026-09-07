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
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/history/presentation/order_history_screen.dart';

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
  }) async {
    final repository = FakeOrderHistoryRepository(
      orders: orders,
      details: details,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderHistoryRepositoryProvider.overrideWithValue(repository),
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
          home: OrderHistoryScreen(onClose: onClose ?? () {}),
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
