import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/printer_config.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/tender_method.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';
import 'package:shared_module/features/receipt/receipt_dialog.dart';

/// Change due is the biggest number on the receipt dialog (audit S3-3).
///
/// The cashier was watched handing back 170 on a 500 note by reading it off
/// the slip's own "Change" row, in the same small mono as the VAT. The dialog
/// now puts the figure above the paper at the payment screen's 46px. The
/// figure is the engine's: the test tenders through `TicketEngine` and reads
/// `TicketTotals.change`, and nothing in the widget is allowed to compute it.
void main() {
  const cash = TenderMethod(
    id: 1,
    code: 'cash',
    nameEn: 'Cash',
    kind: TenderKind.cash,
    countsAsCash: true,
    opensDrawer: true,
  );
  const card = TenderMethod(
    id: 2,
    code: 'card',
    nameEn: 'Card',
    kind: TenderKind.card,
  );

  /// A 330.00 takeaway, paid with [method] for [tendered] — or exactly.
  Ticket settled({TenderMethod method = cash, Money? tendered}) {
    final rung = TicketEngine.addLine(
      Ticket(
        id: 'txn-1',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
      ),
      const Product(
        id: 1,
        categoryId: 1,
        nameEn: 'Mixed Grill',
        price: Money(33000),
      ),
    ).ticket!;

    return TicketEngine.addTender(
      rung,
      typeId: method.id,
      label: method.wireLabel,
      amount: tendered,
      countsAsCash: method.countsAsCash,
    ).ticket!;
  }

  Future<Ticket> open(
    WidgetTester tester, {
    TenderMethod method = cash,
    Money? tendered,
    String locale = 'en',
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ticket = settled(method: method, tendered: tendered);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hardwarePortsProvider.overrideWithValue(FakeHardwarePorts()),
          printQueueRepositoryProvider.overrideWithValue(null),
          printerConfigProvider.overrideWith(
            () => _FixedPrinter(const PrinterConfig(name: '10.20.30.40:9100')),
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
          home: Scaffold(
            body: ReceiptDialog(
              ticket: ticket,
              result: const SubmitOrderResult(
                clientTransactionId: 'txn-1',
                queued: false,
                invoiceNumber: 'HST-000481',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ticket;
  }

  final banner = find.byKey(const ValueKey('change-due'));

  testWidgets('a cash tender over the total shows the change, large', (
    tester,
  ) async {
    const strings = EnStrings();
    final ticket = await open(tester, tendered: const Money(50000));

    // The engine's figure, not one the widget worked out.
    expect(ticket.totals.change, const Money(17000));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.text('170.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner, matching: find.text(strings.changeDue)),
      findsOneWidget,
    );

    // Unmistakable means the biggest number on the screen: nothing else on
    // the dialog — the slip's total, its own change row — is set larger.
    final figure = tester.widget<Text>(
      find.descendant(of: banner, matching: find.text('170.00')),
    );
    final largest = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.style?.fontSize ?? 0)
        .reduce((a, b) => a > b ? a : b);
    expect(figure.style?.fontSize, 46);
    expect(figure.style?.fontSize, largest);
    expect(figure.style?.fontFamily, PosFonts.mono);
  });

  testWidgets('an exact cash tender shows none', (tester) async {
    final ticket = await open(tester);
    expect(ticket.totals.change, Money.zero);
    expect(banner, findsNothing);
    expect(find.text(const EnStrings().changeDue), findsNothing);
  });

  testWidgets('a card tender shows none', (tester) async {
    await open(tester, method: card);
    expect(banner, findsNothing);
  });

  testWidgets('the label is in the till\'s language', (tester) async {
    await open(tester, tendered: const Money(50000), locale: 'ar');
    expect(
      find.descendant(
        of: banner,
        matching: find.text(const ArStrings().changeDue),
      ),
      findsOneWidget,
    );
    // And the figure is still Western digits, read the same across the
    // counter in either language.
    expect(
      find.descendant(of: banner, matching: find.text('170.00')),
      findsOneWidget,
    );
  });
}

class _FixedPrinter extends PrinterConfigController {
  _FixedPrinter(this.value);

  final PrinterConfig value;

  @override
  PrinterConfig build() => value;
}
