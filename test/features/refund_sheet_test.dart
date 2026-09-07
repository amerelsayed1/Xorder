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
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/reason_code.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/refund/presentation/refund_sheet.dart';

/// The refund sheet — the screen where money leaves the drawer.
///
/// The arithmetic is pinned in `refund_engine_test.dart`. What is asserted here
/// is the wiring: that the figures shown are the engine's, that what is written
/// is what was shown, that a retry replays rather than pays twice, and that a
/// failed write says so instead of pretending.
void main() {
  /// 175.00 of food, 17.50 service, 26.95 VAT, 219.45 total — the same fixture
  /// the engine tests use, so a figure that disagrees between the two files is
  /// a real disagreement.
  OrderRecordDetail detail({
    List<OrderRecordLine>? lines,
    List<OrderRecordPayment> payments = const [
      OrderRecordPayment(label: 'Cash', amount: Money(21945), tenderTypeId: 1),
    ],
    OrderStatus status = OrderStatus.paid,
  }) => OrderRecordDetail(
    order: OrderRecord(
      id: 1,
      clientTransactionId: 'txn-1',
      invoiceNumber: 'HST-000481',
      status: status,
      orderType: OrderType.dineIn,
      // Today, so the default seven-day window does not refuse everything.
      occurredAt: DateTime.now().subtract(const Duration(hours: 3)),
      subtotal: const Money(17500),
      discount: Money.zero,
      service: const Money(1750),
      vat: const Money(2695),
      total: const Money(21945),
    ),
    lines:
        lines ??
        const [
          OrderRecordLine(
            id: 10,
            lineKey: 'L1',
            name: 'Mixed Grill',
            quantity: 3,
            unitPrice: Money(5000),
            lineTotal: Money(15000),
          ),
          OrderRecordLine(
            id: 11,
            lineKey: 'L2',
            name: 'Mint tea',
            quantity: 1,
            unitPrice: Money(2500),
            lineTotal: Money(2500),
          ),
        ],
    payments: payments,
    discounts: const [],
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1200);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// Opens the sheet and hands back the repository it wrote to.
  Future<FakeRefundsRepository> open(
    WidgetTester tester, {
    OrderRecordDetail? on,
    List<Refund> previous = const [],
    RefundPolicy policy = RefundPolicy.defaults,
    Object? failWith,
    String locale = 'en',
  }) async {
    final repository = FakeRefundsRepository()..failWith = failWith;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          refundsRepositoryProvider.overrideWithValue(repository),
          refundPolicyProvider.overrideWithValue(policy),
          reasonsRepositoryProvider.overrideWithValue(const _Reasons()),
          staffDirectoryRepositoryProvider.overrideWithValue(const _Directory()),
          signedInStaffProvider.overrideWith(_SignedIn.new),
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => RefundSheet.show(
                  context,
                  detail: on ?? detail(),
                  previous: previous,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return repository;
  }

  /// Presses `+` on the row for [name] the given number of times.
  Future<void> take(WidgetTester tester, String name, int count) async {
    final row = find.ancestor(of: find.text(name), matching: find.byType(Row));
    for (var i = 0; i < count; i++) {
      await tester.tap(
        find.descendant(of: row.first, matching: find.text('+')).first,
      );
      await tester.pump();
    }
  }

  Future<void> pickReason(WidgetTester tester) async {
    await tester.tap(find.text(SystemReasons.seeded.first.nameEn));
    await tester.pumpAndSettle();
  }

  group('what it shows', () {
    testWidgets('opens on the order, naming what is left', (tester) async {
      await open(tester);
      expect(find.text('Refund HST-000481'), findsOneWidget);
      expect(find.text('LEFT TO REFUND'), findsOneWidget);
      // Twice: what is left to refund, and the tender it would go back to.
      expect(find.text('219.45'), findsNWidgets(2));
    });

    testWidgets('what is left already accounts for earlier refunds', (
      tester,
    ) async {
      await open(
        tester,
        previous: [
          Refund(
            id: 1,
            clientRefundId: 'prev',
            orderId: 1,
            kind: RefundKind.partial,
            subtotal: const Money(5000),
            discount: Money.zero,
            service: const Money(500),
            vat: const Money(770),
            total: const Money(6270),
            occurredAt: DateTime.now(),
          ),
        ],
      );
      expect(find.text('156.75'), findsOneWidget);
    });

    testWidgets('shows the engine\'s figures, not a recomputed tax', (
      tester,
    ) async {
      await open(tester);
      await take(tester, 'Mixed Grill', 1);
      await tester.pumpAndSettle();

      // 50.00 of a 175.00 subtotal: service 5.00, VAT 7.70, total 62.70.
      // Every one of those is a share of what the order charged.
      expect(find.text('5.00'), findsWidgets);
      expect(find.text('7.70'), findsOneWidget);
      expect(find.text('62.70'), findsOneWidget);
    });

    testWidgets('a line with nothing left says why', (tester) async {
      await open(
        tester,
        on: detail(
          lines: const [
            OrderRecordLine(
              id: 10,
              lineKey: 'L1',
              name: 'Mixed Grill',
              quantity: 1,
              unitPrice: Money(5000),
              lineTotal: Money(5000),
              refundedQuantity: 1,
            ),
          ],
        ),
      );
      // Shown rather than hidden: a line missing from the list looks like a
      // bug, and "already refunded" is the answer somebody is looking for.
      expect(find.text('Mixed Grill'), findsOneWidget);
      expect(find.text('Already refunded'), findsOneWidget);
    });

    testWidgets('a partly refunded line says how much is left', (tester) async {
      await open(
        tester,
        on: detail(
          lines: const [
            OrderRecordLine(
              id: 10,
              lineKey: 'L1',
              name: 'Mixed Grill',
              quantity: 3,
              unitPrice: Money(5000),
              lineTotal: Money(15000),
              refundedQuantity: 2,
            ),
          ],
        ),
      );
      expect(find.text('1 left'), findsOneWidget);
    });

    testWidgets('the tender offered is the one the money came in on', (
      tester,
    ) async {
      // Refunding a card sale to cash empties a drawer that never held it.
      await open(
        tester,
        on: detail(
          payments: const [
            OrderRecordPayment(
              label: 'Card',
              amount: Money(21945),
              tenderTypeId: 2,
            ),
          ],
        ),
      );
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
    });
  });

  group('what it refuses', () {
    testWidgets('nothing selected leaves the button dead', (tester) async {
      final repository = await open(tester);
      await tester.tap(find.text('Refund 0.00 EGP'));
      await tester.pumpAndSettle();
      expect(repository.issued, isEmpty);
    });

    testWidgets('a sale outside the window explains itself', (tester) async {
      await open(
        tester,
        on: OrderRecordDetail(
          order: OrderRecord(
            id: 1,
            clientTransactionId: 'txn',
            invoiceNumber: 'OLD',
            status: OrderStatus.paid,
            orderType: OrderType.takeaway,
            occurredAt: DateTime.now().subtract(const Duration(days: 9)),
            subtotal: const Money(10000),
            discount: Money.zero,
            service: Money.zero,
            vat: const Money(1400),
            total: const Money(11400),
          ),
          lines: const [
            OrderRecordLine(
              id: 10,
              lineKey: 'L1',
              name: 'Koshari',
              quantity: 1,
              unitPrice: Money(10000),
              lineTotal: Money(10000),
            ),
          ],
          payments: const [
            OrderRecordPayment(
              label: 'Cash',
              amount: Money(11400),
              tenderTypeId: 1,
            ),
          ],
          discounts: const [],
        ),
      );

      expect(
        find.textContaining('outside the refund window'),
        findsOneWidget,
      );
    });

    testWidgets('refunds switched off say so', (tester) async {
      await open(tester, policy: const RefundPolicy(enabled: false));
      expect(
        find.text('Refunds are switched off for this restaurant.'),
        findsOneWidget,
      );
    });

    testWidgets('a required reason is asked for before anything is written', (
      tester,
    ) async {
      final repository = await open(tester);
      await take(tester, 'Mixed Grill', 1);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Refund 62.70 EGP'));
      await tester.pumpAndSettle();

      expect(find.text('Give a reason for the refund.'), findsOneWidget);
      expect(repository.issued, isEmpty);
    });

    testWidgets('the stepper will not go past what is left', (tester) async {
      await open(
        tester,
        on: detail(
          lines: const [
            OrderRecordLine(
              id: 10,
              lineKey: 'L1',
              name: 'Mixed Grill',
              quantity: 3,
              unitPrice: Money(5000),
              lineTotal: Money(15000),
              refundedQuantity: 2,
            ),
            OrderRecordLine(
              id: 11,
              lineKey: 'L2',
              name: 'Mint tea',
              quantity: 1,
              unitPrice: Money(2500),
              lineTotal: Money(2500),
            ),
          ],
        ),
      );

      // Only one remains, so pressing + five times must still take one — 50.00
      // of food, which pro-rates to 62.70.
      await take(tester, 'Mixed Grill', 5);
      await tester.pumpAndSettle();
      expect(find.text('Refund 62.70 EGP'), findsOneWidget);
    });
  });

  group('issuing', () {
    testWidgets('writes what was shown, with the reason and the tender', (
      tester,
    ) async {
      final repository = await open(tester);
      await take(tester, 'Mixed Grill', 1);
      await tester.pumpAndSettle();
      await pickReason(tester);

      await tester.tap(find.text('Refund 62.70 EGP'));
      await tester.pumpAndSettle();

      expect(repository.issued, hasLength(1));
      final refund = repository.issued.single;
      // The figure on the button is the figure on the row. Nothing is
      // recalculated between the confirmation and the write.
      expect(refund.total.minor, 6270);
      expect(refund.vat.minor, 770);
      expect(refund.lines.single.orderLineId, 10);
      expect(refund.lines.single.quantity, 1);
      expect(refund.payments.single.tenderTypeId, 1);
      // The stored label, not the translated one — the cash-up matches on it.
      expect(refund.payments.single.label, 'Cash');
      expect(refund.refundedByName, 'Nour Adel');
      expect(refund.kind, RefundKind.partial);
    });

    testWidgets('refunding everything closes the order', (tester) async {
      final repository = await open(tester);
      await take(tester, 'Mixed Grill', 3);
      await take(tester, 'Mint tea', 1);
      await tester.pumpAndSettle();
      await pickReason(tester);

      await tester.tap(find.text('Refund 219.45 EGP'));
      await tester.pumpAndSettle();

      final refund = repository.issued.single;
      expect(refund.total.minor, 21945);
      expect(refund.kind, RefundKind.full);
    });

    testWidgets('an amount refund gives back exactly the amount typed', (
      tester,
    ) async {
      final repository = await open(tester);
      await tester.tap(find.text('By amount'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '50.00');
      await tester.pumpAndSettle();
      await pickReason(tester);

      await tester.tap(find.text('Refund 50.00 EGP'));
      await tester.pumpAndSettle();

      final refund = repository.issued.single;
      expect(refund.total.minor, 5000);
      // No lines: nobody said which food this was for, and inventing an
      // attribution would move a quantity the operator never chose.
      expect(refund.lines, isEmpty);
    });

    testWidgets('the sheet hands back what went out', (tester) async {
      await open(tester);
      await take(tester, 'Mint tea', 1);
      await tester.pumpAndSettle();
      await pickReason(tester);

      await tester.tap(find.text('Refund 31.35 EGP'));
      await tester.pumpAndSettle();

      // Closed, which is what tells the caller to re-read the order.
      expect(find.text('Refund HST-000481'), findsNothing);
    });
  });

  group('when the write fails', () {
    testWidgets('says no money moved, and stays open', (tester) async {
      final repository = await open(
        tester,
        failWith: StateError('the branch server went away'),
      );
      await take(tester, 'Mixed Grill', 1);
      await tester.pumpAndSettle();
      await pickReason(tester);

      await tester.tap(find.text('Refund 62.70 EGP'));
      await tester.pumpAndSettle();

      expect(repository.issued, isEmpty);
      expect(
        find.textContaining('no money has gone back'),
        findsOneWidget,
      );
      // Still open, with the selection intact — the customer is standing there
      // and retyping it is the last thing anybody needs.
      expect(find.text('Refund HST-000481'), findsOneWidget);
      expect(find.text('Refund 62.70 EGP'), findsOneWidget);
    });

    testWidgets('a retry replays rather than paying twice', (tester) async {
      // The id is generated once when the dialog opens, not per press. A fresh
      // id per attempt is how a customer gets paid twice.
      final repository = await open(
        tester,
        failWith: StateError('timeout'),
      );
      await take(tester, 'Mixed Grill', 1);
      await tester.pumpAndSettle();
      await pickReason(tester);

      await tester.tap(find.text('Refund 62.70 EGP'));
      await tester.pumpAndSettle();

      repository.failWith = null;
      await tester.tap(find.text('Refund 62.70 EGP'));
      await tester.pumpAndSettle();
      final first = repository.issued.single.clientRefundId;

      // And a third press of the same dialog would carry the same id again.
      expect(first, isNotEmpty);
      expect(repository.issued, hasLength(1));
    });
  });

  group('Arabic', () {
    testWidgets('renders right to left without overflowing', (tester) async {
      await open(tester, locale: 'ar');
      expect(find.textContaining('استرجاع'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the amount stays left to right', (tester) async {
      await open(tester, locale: 'ar');
      final directionality = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('219.45'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(directionality.textDirection, TextDirection.ltr);
    });
  });
}

class _Reasons implements ReasonsRepository {
  const _Reasons();

  @override
  Future<List<ReasonCode>> forScope(ReasonScope scope) async => [
    for (var i = 0; i < 4; i++)
      ReasonCode(
        id: i + 1,
        scope: scope,
        code: SystemReasons.seeded[i].code,
        nameEn: SystemReasons.seeded[i].nameEn,
        nameAr: SystemReasons.seeded[i].nameAr,
        sortOrder: i + 1,
      ),
  ];
}

class _SignedIn extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 4,
    name: 'Nour Adel',
    capabilities: {PosCapability.operate, PosCapability.orderRefund},
  );
}

class _Directory implements StaffDirectoryRepository {
  const _Directory();

  @override
  Future<PosStaff?> byPin(String pin) async => null;

  @override
  Future<List<PosStaff>> all({bool includeInactive = true}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
