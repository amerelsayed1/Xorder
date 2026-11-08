import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/purchase_order.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/supplier.dart';
import 'package:xorder_pos/domain/models/supplier_invoice.dart';
import 'package:xorder_pos/features/admin/presentation/supplier_invoice_dialog.dart';
import 'package:xorder_pos/features/admin/presentation/supplier_payment_dialog.dart';

/// Invoices and payments, on screen (§37).
///
/// The claim each test defends is one a wrong screen would turn into money: the
/// VAT is taken *out* of a gross total rather than added to it, a payment starts
/// at what the chosen bill still owes, and money that will not fit on a bill is
/// stopped while the amount is still on screen to change.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1800);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  const dairy = Supplier(id: 7, nameEn: 'Nile Dairy', paymentTermDays: 30);
  const meats = Supplier(id: 8, nameEn: 'Cairo Meats');

  /// A shift open on this terminal, which is what makes the drawer switch
  /// possible at all.
  final shift = PosShift(
    id: 42,
    openedAt: DateTime(2026, 3, 1, 9),
    openingFloat: const Money(20000),
    openedByName: 'Sara M.',
  );

  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
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
                onPressed: () => open(context),
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
  }

  SupplierInvoice invoice({
    int id = 1,
    int supplierId = 7,
    String number = 'INV-900',
    int totalMinor = 100000,
    int paidMinor = 0,
    int dueInDays = 10,
  }) => SupplierInvoice(
    id: id,
    supplierId: supplierId,
    number: number,
    total: Money(totalMinor),
    tax: Money(0),
    paid: Money(paidMinor),
    issuedAt: DateTime.now().subtract(const Duration(days: 1)),
    dueAt: DateTime.now().add(Duration(days: dueInDays)),
  );

  group('the invoice dialog', () {
    testWidgets('the VAT is taken out of the total, not added to it', (
      tester,
    ) async {
      // **The arithmetic people get wrong.** 14% of a gross 1,140.00 is 159.60;
      // the VAT inside it is 140.00. Adding instead of extracting overstates
      // every reclaim by about two per cent of turnover, and the first person
      // to notice would be an inspector.
      await host(
        tester,
        (context) async =>
            SupplierInvoiceDialog.show(context, suppliers: const [dairy]),
      );

      await tester.enterText(find.byKey(const Key('invoice-total')), '1140.00');
      await tester.tap(find.byKey(const Key('invoice-rate-1400')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('invoice-tax')))
            .controller
            ?.text,
        '140.00',
      );
      // Grouped, because `Money.format` groups thousands — and `tryParse`
      // strips the commas again, so the box round-trips.
      expect(find.text('1,000.00 EGP'), findsWidgets, reason: 'the net, shown');
    });

    testWidgets('the subtotal is shown, never typed', (tester) async {
      await host(
        tester,
        (context) async =>
            SupplierInvoiceDialog.show(context, suppliers: const [dairy]),
      );

      // Three money boxes would be three numbers to disagree. There are two.
      expect(find.byKey(const Key('invoice-total')), findsOneWidget);
      expect(find.byKey(const Key('invoice-tax')), findsOneWidget);
      expect(find.text('SUBTOTAL'), findsNothing);
      expect(
        find.text('Subtotal'),
        findsOneWidget,
        reason: 'a label, not a box',
      );
    });

    testWidgets('the due date follows the supplier terms', (tester) async {
      // 30-day terms, so the due date is a month out and the label says why —
      // rather than presenting a date somebody has to check against a contract.
      await host(
        tester,
        (context) async =>
            SupplierInvoiceDialog.show(context, suppliers: const [dairy]),
      );
      expect(find.text('DUE · 30 DAY TERMS'), findsOneWidget);
    });

    testWidgets('cash on delivery says so rather than showing 0 days', (
      tester,
    ) async {
      await host(
        tester,
        (context) async =>
            SupplierInvoiceDialog.show(context, suppliers: const [meats]),
      );
      expect(find.text('DUE · ON DELIVERY'), findsOneWidget);
    });

    testWidgets('an invoice with no number is refused beside the field', (
      tester,
    ) async {
      SupplierInvoice? saved;
      await host(
        tester,
        (context) async => saved = await SupplierInvoiceDialog.show(
          context,
          suppliers: const [dairy],
        ),
      );

      await tester.enterText(find.byKey(const Key('invoice-total')), '100.00');
      await tester.tap(find.byKey(const Key('invoice-save')));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(find.textContaining('number printed on it'), findsOneWidget);
    });

    testWidgets('a complete invoice comes back with the net derived', (
      tester,
    ) async {
      SupplierInvoice? saved;
      await host(
        tester,
        (context) async => saved = await SupplierInvoiceDialog.show(
          context,
          suppliers: const [dairy, meats],
        ),
      );

      await tester.tap(find.text('Cairo Meats'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('invoice-number')), '55/A');
      await tester.enterText(find.byKey(const Key('invoice-total')), '1140.00');
      await tester.enterText(find.byKey(const Key('invoice-tax')), '140.00');
      await tester.tap(find.byKey(const Key('invoice-save')));
      await tester.pumpAndSettle();

      expect(saved?.supplierId, 8);
      expect(saved?.number, '55/A');
      expect(saved?.total, const Money(114000));
      expect(saved?.tax, const Money(14000));
      expect(saved?.subtotal, const Money(100000));
    });

    group('against an order', () {
      PurchaseOrder order({
        int receivedUnits = 10,
        PurchaseStatus status = PurchaseStatus.received,
        int supplierId = 7,
      }) => PurchaseOrder(
        id: 3,
        supplierId: supplierId,
        reference: 'PO-2026-0003',
        status: status,
        lines: [
          PurchaseOrderLine(
            id: 11,
            description: 'Milk 1L',
            ordered: Quantity.of(10),
            received: Quantity.of(receivedUnits),
            unitCost: const Money(10000),
            taxRateBp: 1400,
          ),
        ],
      );

      testWidgets('a matching invoice says so', (tester) async {
        await host(
          tester,
          (context) async => SupplierInvoiceDialog.show(
            context,
            suppliers: const [dairy],
            orders: [order()],
          ),
        );

        await tester.tap(find.byKey(const Key('invoice-order-3')));
        await tester.enterText(
          find.byKey(const Key('invoice-total')),
          '1140.00',
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Agrees with what arrived'), findsOneWidget);
      });

      testWidgets('billing for more than arrived is flagged, not refused', (
        tester,
      ) async {
        // The invoice still says what it says. Recording it is how the query
        // gets raised at all — refusing it would leave the paper unrecorded and
        // the supplier still expecting to be paid.
        SupplierInvoice? saved;
        await host(
          tester,
          (context) async => saved = await SupplierInvoiceDialog.show(
            context,
            suppliers: const [dairy],
            orders: [order(receivedUnits: 8)],
          ),
        );

        await tester.tap(find.byKey(const Key('invoice-order-3')));
        await tester.enterText(find.byKey(const Key('invoice-number')), 'X1');
        await tester.enterText(
          find.byKey(const Key('invoice-total')),
          '1140.00',
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('More than what arrived'), findsOneWidget);

        await tester.tap(find.byKey(const Key('invoice-save')));
        await tester.pumpAndSettle();
        expect(saved?.total, const Money(114000), reason: 'saved anyway');
      });

      testWidgets('a draft order is not offered — nothing can have arrived', (
        tester,
      ) async {
        await host(
          tester,
          (context) async => SupplierInvoiceDialog.show(
            context,
            suppliers: const [dairy],
            orders: [order(status: PurchaseStatus.draft)],
          ),
        );
        expect(find.text('PO-2026-0003'), findsNothing);
      });

      testWidgets('another supplier\'s order is not offered', (tester) async {
        await host(
          tester,
          (context) async => SupplierInvoiceDialog.show(
            context,
            suppliers: const [dairy],
            orders: [order(supplierId: 8)],
          ),
        );
        expect(find.text('PO-2026-0003'), findsNothing);
      });
    });
  });

  group('the payment dialog', () {
    testWidgets('the amount starts at what the bill still owes', (
      tester,
    ) async {
      // Nearly every payment settles a bill in full, so the common case is one
      // tap. Typing over it is how a part payment gets recorded.
      await host(
        tester,
        (context) async => SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice(totalMinor: 100000, paidMinor: 40000)],
        ),
      );

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('payment-amount')))
            .controller
            ?.text,
        '600.00',
      );
    });

    testWidgets('picking another bill moves the amount with it', (
      tester,
    ) async {
      // Leaving the previous figure in the box is how somebody pays 1,000
      // against a 90 invoice and finds out from a refusal.
      await host(
        tester,
        (context) async => SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [
            invoice(id: 1, number: 'A', totalMinor: 100000),
            invoice(id: 2, number: 'B', totalMinor: 9000),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('payment-invoice-2')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('payment-amount')))
            .controller
            ?.text,
        '90.00',
      );
    });

    testWidgets('money that will not fit is stopped before it is sent', (
      tester,
    ) async {
      SupplierPaymentRequest? paid;
      await host(
        tester,
        (context) async => paid = await SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice(totalMinor: 100000)],
        ),
      );

      await tester.enterText(
        find.byKey(const Key('payment-amount')),
        '1500.00',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Only 1,000.00 EGP is left'), findsOneWidget);

      await tester.tap(find.byKey(const Key('payment-save')));
      await tester.pumpAndSettle();
      expect(paid, isNull, reason: 'and not sent');
    });

    testWidgets('on account takes any amount, because it fits nothing', (
      tester,
    ) async {
      SupplierPaymentRequest? paid;
      await host(
        tester,
        (context) async => paid = await SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice(totalMinor: 100000)],
        ),
      );

      await tester.tap(find.byKey(const Key('payment-on-account')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('payment-amount')),
        '2000.00',
      );
      await tester.tap(find.byKey(const Key('payment-save')));
      await tester.pumpAndSettle();

      expect(paid?.payment.isOnAccount, isTrue);
      expect(paid?.payment.amount, const Money(200000));
    });

    testWidgets('a reference box appears only where a bank needs one', (
      tester,
    ) async {
      // A reference field on a cash payment is a field somebody has to decide
      // to leave empty.
      await host(
        tester,
        (context) async => SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice()],
        ),
      );

      expect(find.byKey(const Key('payment-reference')), findsNothing);

      await tester.tap(find.byKey(const Key('payment-method-cheque')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment-reference')), findsOneWidget);
    });

    testWidgets('the cheque number travels with the payment', (tester) async {
      SupplierPaymentRequest? paid;
      await host(
        tester,
        (context) async => paid = await SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice()],
        ),
      );

      await tester.tap(find.byKey(const Key('payment-method-cheque')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('payment-reference')),
        '004512',
      );
      await tester.tap(find.byKey(const Key('payment-save')));
      await tester.pumpAndSettle();

      expect(paid?.payment.method, SupplierPaymentMethod.cheque);
      expect(paid?.payment.reference, '004512');
    });

    testWidgets('a late bill is badged in the picker', (tester) async {
      await host(
        tester,
        (context) async => SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice(dueInDays: -7)],
        ),
      );
      expect(find.text('7 days late'), findsOneWidget);
    });

    testWidgets('with no shift open it says why, rather than offering a switch '
        'that would refuse', (tester) async {
      // The office is not always beside an open till. Saying so in one line is
      // the difference between a manager knowing the drawer is untouched and
      // finding out when their Z report is short.
      await host(
        tester,
        (context) async => SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice()],
        ),
      );

      expect(find.byKey(const Key('payment-from-drawer')), findsNothing);
      expect(
        find.textContaining('does not change the till drawer'),
        findsOneWidget,
      );
    });

    testWidgets('the till switch is offered for cash on an open shift', (
      tester,
    ) async {
      await host(
        tester,
        (context) async => SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice()],
          openShift: shift,
        ),
      );

      expect(find.byKey(const Key('payment-from-drawer')), findsOneWidget);
      // And the no-shift line is gone: the screen says one thing about the
      // drawer, not two.
      expect(
        find.textContaining('does not change the till drawer'),
        findsNothing,
      );
    });

    testWidgets('a transfer is never offered the drawer', (tester) async {
      // Money that goes out of a bank account does not pass through a till, so
      // there is nothing to ask about.
      await host(
        tester,
        (context) async => SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice()],
          openShift: shift,
        ),
      );

      await tester.tap(find.byKey(const Key('payment-method-bank_transfer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment-from-drawer')), findsNothing);
    });

    testWidgets('it starts off — recording a payment must not move cash '
        'nobody said to move', (tester) async {
      // A bookkeeper typing up last week's receipt book is the commoner case,
      // and a switch that started on would take *today's* drawer down for money
      // that left days ago.
      SupplierPaymentRequest? paid;
      await host(
        tester,
        (context) async => paid = await SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice()],
          openShift: shift,
        ),
      );

      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('payment-from-drawer')))
            .value,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('payment-save')));
      await tester.pumpAndSettle();
      expect(paid?.fromShiftId, isNull);
      expect(paid?.comesOutOfTheDrawer, isFalse);
    });

    testWidgets('switched on, the payment names the shift the cash comes from', (
      tester,
    ) async {
      SupplierPaymentRequest? paid;
      await host(
        tester,
        (context) async => paid = await SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice()],
          openShift: shift,
        ),
      );

      await tester.tap(find.byKey(const Key('payment-from-drawer')));
      await tester.tap(find.byKey(const Key('payment-save')));
      await tester.pumpAndSettle();

      expect(paid?.fromShiftId, 42, reason: 'the open shift, not a flag');
    });

    testWidgets('switching to a cheque afterwards leaves the drawer alone', (
      tester,
    ) async {
      // The flag stays set behind a control that is no longer on screen, and the
      // money has to follow what the screen was last saying rather than what it
      // said two taps ago.
      SupplierPaymentRequest? paid;
      await host(
        tester,
        (context) async => paid = await SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: [invoice()],
          openShift: shift,
        ),
      );

      await tester.tap(find.byKey(const Key('payment-from-drawer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment-method-cheque')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment-save')));
      await tester.pumpAndSettle();

      expect(paid?.fromShiftId, isNull);
    });

    testWidgets('a supplier with nothing owing can still be paid on account', (
      tester,
    ) async {
      SupplierPaymentRequest? paid;
      await host(
        tester,
        (context) async => paid = await SupplierPaymentDialog.show(
          context,
          supplier: dairy,
          unpaid: const [],
        ),
      );

      await tester.enterText(find.byKey(const Key('payment-amount')), '500.00');
      await tester.tap(find.byKey(const Key('payment-save')));
      await tester.pumpAndSettle();

      expect(paid?.payment.isOnAccount, isTrue);
      expect(paid?.payment.amount, const Money(50000));
    });
  });

  testWidgets('the Arabic invoice dialog keeps its figures in Latin digits', (
    tester,
  ) async {
    await host(
      tester,
      (context) async =>
          SupplierInvoiceDialog.show(context, suppliers: const [dairy]),
      locale: 'ar',
    );

    expect(find.text('إدخال فاتورة'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('invoice-total')), '1140.00');
    await tester.tap(find.byKey(const Key('invoice-rate-1400')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('invoice-tax')))
          .controller
          ?.text,
      '140.00',
    );
  });
}
