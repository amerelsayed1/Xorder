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
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/receipt/receipt_data.dart';
import 'package:xorder_pos/features/receipt/receipt_printing.dart';
import 'package:xorder_pos/features/receipt/reprint_dialog.dart';

/// Reprinting a receipt.
///
/// Two claims carry the weight. The slip must be **marked**, because two
/// identical receipts for one sale is how a refund gets claimed twice. And the
/// reprint must be **recorded** — `AuditAction.receiptReprinted` has been a
/// constant nothing wrote since the ledger was built.
void main() {
  final soldAt = DateTime(2026, 9, 7, 13, 5);

  OrderRecordDetail detail({
    OrderStatus status = OrderStatus.paid,
    String? servedBy = 'Nour Adel',
    List<OrderRecordLine>? lines,
    List<TaxLine> taxLines = const [],
  }) => OrderRecordDetail(
    order: OrderRecord(
      id: 7,
      clientTransactionId: 'txn-7',
      invoiceNumber: 'HST-000481',
      status: status,
      orderType: OrderType.dineIn,
      occurredAt: soldAt,
      subtotal: const Money(17500),
      discount: Money.zero,
      service: const Money(1750),
      vat: const Money(2695),
      total: const Money(21945),
      tableLabel: 'T12',
      servedByName: servedBy,
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
        ],
    payments: const [
      OrderRecordPayment(label: 'Cash', amount: Money(21945), tenderTypeId: 1),
    ],
    discounts: const [],
    taxLines: taxLines,
  );

  Refund refund({int total = 6270}) => Refund(
    id: 1,
    clientRefundId: 'r1',
    orderId: 7,
    kind: RefundKind.partial,
    subtotal: const Money(5000),
    discount: Money.zero,
    service: const Money(500),
    vat: const Money(770),
    total: Money(total),
    occurredAt: soldAt,
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<(FakeAuditRepository, PrintOutcome? Function())> open(
    WidgetTester tester, {
    OrderRecordDetail? on,
    List<Refund> refunds = const [],
    Object? auditFailsWith,
    String locale = 'en',
  }) async {
    final audit = FakeAuditRepository()..failWith = auditFailsWith;
    PrintOutcome? printed;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          auditRepositoryProvider.overrideWithValue(audit),
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
                onPressed: () async {
                  printed = await ReprintDialog.show(
                    context,
                    detail: on ?? detail(),
                    refunds: refunds,
                  );
                },
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
    return (audit, () => printed);
  }

  group('the slip', () {
    testWidgets('is stamped as a reprint', (tester) async {
      // Two identical receipts for one sale is how a refund gets claimed twice.
      await open(tester);
      expect(find.text('REPRINT — NOT AN ORIGINAL'), findsOneWidget);
    });

    testWidgets('says what has already gone back', (tester) async {
      await open(tester, refunds: [refund()]);
      expect(find.text('REFUNDED 62.70 EGP'), findsOneWidget);
    });

    testWidgets('says nothing about refunds when there were none', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('REFUNDED'), findsNothing);
    });

    testWidgets('carries the sale time, not the reprint time', (tester) async {
      // A receipt reprinted a week later that claimed today's date would be a
      // forgery the till produced on request.
      await open(tester);
      // Two rows since the 2026-09-13 layout, and the year is printed now.
      expect(find.text('07/09/2026'), findsOneWidget);
      expect(find.text('13:05'), findsOneWidget);
    });

    testWidgets('names who sold it, not who is reprinting', (tester) async {
      // The slip is a copy of what was issued; rewriting the cashier's name
      // would make it a different document.
      await open(tester);
      expect(find.textContaining('NOUR ADEL'), findsOneWidget);
      expect(find.textContaining('HANA MOSTAFA'), findsNothing);
    });

    testWidgets('says nobody rather than naming the person reprinting', (
      tester,
    ) async {
      // Orders written before migration 11 have no seller. Falling back to
      // whoever is standing at the till would put their name against a sale
      // they did not make — a small lie on a document somebody may keep.
      await open(tester, on: detail(servedBy: null));
      expect(find.textContaining('HANA MOSTAFA'), findsNothing);
      // The cashier row reads a dash. It used to share a line with the till
      // code as `T1 / —`; the till has its own row now.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('prints the totals that were charged', (tester) async {
      await open(tester);
      expect(find.text('175.00 EGP'), findsOneWidget);
      expect(find.text('17.50 EGP'), findsOneWidget);
      expect(find.text('26.95 EGP'), findsOneWidget);
      expect(find.text('219.45'), findsWidgets);
    });

    testWidgets('a voided line stays on the slip, struck through', (
      tester,
    ) async {
      await open(
        tester,
        on: detail(
          lines: [
            const OrderRecordLine(
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
              unitPrice: const Money(2500),
              lineTotal: const Money(2500),
              voidedAt: soldAt,
            ),
          ],
        ),
      );

      // It stays because the kitchen made it and the customer watched.
      // The name is its own cell of the items table now, the quantity another.
      final line = tester.widget<Text>(find.text('Mint tea'));
      expect(line.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('renders in Arabic without overflowing', (tester) async {
      await open(tester, locale: 'ar');
      expect(find.text('إعادة طباعة — ليست الأصل'), findsOneWidget);
      // The payment row was stored as "Cash"; an Arabic slip names the method
      // in Arabic while the method still carries that name.
      expect(find.text('نقدي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('printing', () {
    testWidgets('writes the audit row nothing had ever written', (
      tester,
    ) async {
      final (audit, printed) = await open(tester);
      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();

      // No printer is configured in this harness, so the honest outcome is
      // "nothing was printed" — which is the point of the change: the dialog
      // used to answer `true` here and the caller said "Reprint sent".
      expect(printed(), PrintOutcome.noPrinter);
      expect(audit.entries, hasLength(1));

      final row = audit.entries.single;
      expect(row.action, AuditAction.receiptReprinted);
      expect(row.entityType, 'order');
      expect(row.entityId, '7');
      expect(row.actorName, 'Hana Mostafa');
      expect(row.after?['invoice_number'], 'HST-000481');
    });

    testWidgets('cancelling prints nothing and records nothing', (
      tester,
    ) async {
      final (audit, printed) = await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(printed(), isNull);
      expect(audit.entries, isEmpty);
      expect(find.text('Print'), findsNothing, reason: 'the dialog closed');
    });

    testWidgets('an unwritable ledger means nothing prints', (tester) async {
      // An unrecorded reprint is precisely the one somebody wanted. A missing
      // printer is a smaller problem than a missing record.
      final (audit, printed) = await open(
        tester,
        auditFailsWith: StateError('the branch server went away'),
      );
      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();

      expect(audit.entries, isEmpty);
      expect(printed(), isNull);
      expect(find.text('Print'), findsOneWidget, reason: 'the dialog is still open');
      expect(
        find.textContaining('nothing was printed'),
        findsOneWidget,
      );
    });
  });

  group('ReceiptData.fromOrder', () {
    test('omits the tax rate rather than deriving one', () {
      // With no stored breakdown there is no rate to print. Dividing the tax
      // by the net would print a figure that is right most of the time and
      // wrong wherever rounding went the other way — and a reprint that
      // invents a rate is a document somebody will argue with.
      final data = ReceiptData.fromOrder(detail());
      expect(data.serviceBp, isNull);
      expect(data.taxLines, isEmpty);
      expect(data.vat.minor, 2695);
    });

    test('takes the VAT rate from the stored breakdown', () {
      // `pos_order_taxes` has held the rate since migration 16. It is a
      // snapshot of what was charged, not a quotient.
      final data = ReceiptData.fromOrder(
        detail(
          taxLines: const [
            TaxLine(
              name: 'VAT',
              rateBp: 1400,
              base: Money(19250),
              amount: Money(2695),
            ),
          ],
        ),
      );
      expect(data.taxLines.single.rateBp, 1400);
      expect(data.taxLines.single.amount.minor, 2695);
    });

    test('ignores a breakdown that does not account for the VAT', () {
      // Two VAT figures that do not agree on one slip is worse than one
      // figure with no rate beside it.
      final data = ReceiptData.fromOrder(
        detail(
          taxLines: const [
            TaxLine(
              name: 'VAT',
              rateBp: 1400,
              base: Money(14000),
              amount: Money(1960),
            ),
          ],
        ),
      );
      expect(data.taxLines, isEmpty);
    });

    test('carries every payment, so a split bill prints each tender', () {
      final data = ReceiptData.fromOrder(detail());
      expect(data.payments.single.label, 'Cash');
      expect(data.payments.single.tenderTypeId, 1);
    });

    test('totals the payments rather than recomputing them', () {
      final data = ReceiptData.fromOrder(detail());
      expect(data.paid.minor, 21945);
      // A settled order has no change to give back.
      expect(data.change.minor, 0);
    });

    test('sums the refunds already given', () {
      final data = ReceiptData.fromOrder(
        detail(),
        refunds: [refund(total: 1000), refund(total: 2000)],
      );
      expect(data.refunded.minor, 3000);
      expect(data.wasRefunded, isTrue);
    });

    test('keeps the order currency', () {
      final data = ReceiptData.fromOrder(detail());
      expect(data.total.currency, 'EGP');
    });

    test('an offline sale says nothing about sync', () {
      // It used to print SYNCED TO XORDER, because `queued` is false on a till
      // that queues nothing — so the one deployment that has never contacted a
      // platform was the one claiming it had. On a document a customer keeps.
      final offline = ReceiptData.fromTicket(
        Ticket(id: 'txn', orderType: OrderType.takeaway),
        invoiceNumber: 'INV-1',
        cloudBacked: false,
      );
      expect(offline.syncNote, ReceiptSyncNote.none);
    });

    test('a cloud sale that landed says so', () {
      final synced = ReceiptData.fromTicket(
        Ticket(id: 'txn', orderType: OrderType.takeaway),
        invoiceNumber: 'INV-1',
        queued: false,
        cloudBacked: true,
      );
      expect(synced.syncNote, ReceiptSyncNote.synced);
    });

    test('a cloud sale still owed to the platform says that instead', () {
      final queued = ReceiptData.fromTicket(
        Ticket(id: 'txn', orderType: OrderType.takeaway),
        invoiceNumber: 'INV-1',
        queued: true,
        cloudBacked: true,
      );
      expect(queued.syncNote, ReceiptSyncNote.queued);

      // And a sale with no invoice number yet is owed whatever `queued` says:
      // the platform assigns the number, so its absence means it has not been.
      final unnumbered = ReceiptData.fromTicket(
        Ticket(id: 'txn', orderType: OrderType.takeaway),
        cloudBacked: true,
      );
      expect(unnumbered.syncNote, ReceiptSyncNote.queued);
    });

    test('a reprint from the ledger claims nothing either way', () {
      // The order is in the branch database in front of us. Whether the
      // platform has it is not a question this slip answers.
      expect(ReceiptData.fromOrder(detail()).syncNote, ReceiptSyncNote.none);
    });

    test('is a reprint by default, and a ticket receipt is not', () {
      expect(ReceiptData.fromOrder(detail()).isReprint, isTrue);

      final live = ReceiptData.fromTicket(
        Ticket(id: 'txn', orderType: OrderType.takeaway),
      );
      expect(live.isReprint, isFalse);
      expect(live.wasRefunded, isFalse);
    });
  });
}

class _SignedIn extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 9,
    name: 'Hana Mostafa',
    capabilities: {PosCapability.operate, PosCapability.receiptReprint},
  );
}
