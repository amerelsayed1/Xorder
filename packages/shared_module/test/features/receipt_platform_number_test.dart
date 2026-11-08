import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/printer_config.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';
import 'package:shared_module/features/receipt/receipt_dialog.dart';

/// XORD-058 follow-up: the open receipt picks up the platform's number.
///
/// A cloud till's slip opens PROVISIONAL; the drain brings the number back a
/// second later. The dialog used to keep PROVISIONAL until somebody reprinted
/// from history. It now looks again after every pass that delivered something,
/// and swaps the number in. An offline till's own number never changes.
void main() {
  const strings = EnStrings();
  const txn = 'txn-58';

  Ticket settled() {
    final rung = TicketEngine.addLine(
      Ticket(
        id: txn,
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
      ),
      const Product(id: 1, categoryId: 1, nameEn: 'Tea', price: Money(4000)),
    ).ticket!;
    return TicketEngine.addTender(
      rung,
      typeId: 1,
      label: 'Cash',
      countsAsCash: true,
    ).ticket!;
  }

  Future<ProviderContainer> open(
    WidgetTester tester, {
    required DeploymentMode mode,
    required FakeOrdersRepository orders,
    required SubmitOrderResult result,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hardwarePortsProvider.overrideWithValue(FakeHardwarePorts()),
          printQueueRepositoryProvider.overrideWithValue(null),
          printerConfigProvider.overrideWith(
            () => _FixedPrinter(const PrinterConfig(name: '10.20.30.40:9100')),
          ),
          deploymentProvider.overrideWith(
            () => _FixedDeployment(
              DeploymentConfig.unconfigured.copyWith(
                mode: mode,
                baseUrl: 'https://xorder.io',
              ),
            ),
          ),
          ordersRepositoryProvider.overrideWithValue(orders),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReceiptDialog(ticket: settled(), result: result),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ReceiptDialog)));
  }

  const provisional = SubmitOrderResult(clientTransactionId: txn, queued: true);

  testWidgets('a cloud receipt swaps PROVISIONAL for the number after a sync', (
    tester,
  ) async {
    final orders = FakeOrdersRepository();
    final container = await open(
      tester,
      mode: DeploymentMode.cloud,
      orders: orders,
      result: provisional,
    );

    expect(find.text(strings.provisionalInvoice), findsOneWidget);
    expect(find.text(strings.receiptQueuedOffline), findsOneWidget);

    // A pass that delivered nothing else leaves it alone.
    container.read(salesDeliveredProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text(strings.provisionalInvoice), findsOneWidget);

    // The drain brings the number back.
    orders.platformNumbers[txn] = 'BR8-2026-000013';
    container.read(salesDeliveredProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(find.text('BR8-2026-000013'), findsOneWidget);
    expect(find.text(strings.provisionalInvoice), findsNothing);
    expect(find.text(strings.receiptSynced), findsOneWidget);
    expect(find.text(strings.receiptQueuedOffline), findsNothing);
  });

  testWidgets('a number already back when the receipt opens is shown at once', (
    tester,
  ) async {
    final orders = FakeOrdersRepository()
      ..platformNumbers[txn] = 'BR8-2026-000014';
    await open(
      tester,
      mode: DeploymentMode.cloud,
      orders: orders,
      result: provisional,
    );

    expect(find.text('BR8-2026-000014'), findsOneWidget);
    expect(find.text(strings.provisionalInvoice), findsNothing);
  });

  testWidgets("an offline till's own number never changes", (tester) async {
    final orders = FakeOrdersRepository()
      ..platformNumbers[txn] = 'SHOULD-NOT-APPEAR';
    final container = await open(
      tester,
      mode: DeploymentMode.offline,
      orders: orders,
      result: const SubmitOrderResult(
        clientTransactionId: txn,
        queued: false,
        invoiceNumber: 'BR8-000481',
      ),
    );
    container.read(salesDeliveredProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(find.text('BR8-000481'), findsOneWidget);
    expect(find.text('SHOULD-NOT-APPEAR'), findsNothing);
    expect(find.text(strings.receiptSynced), findsNothing);
  });
}

class _FixedPrinter extends PrinterConfigController {
  _FixedPrinter(this.value);

  final PrinterConfig value;

  @override
  PrinterConfig build() => value;
}

class _FixedDeployment extends DeploymentController {
  _FixedDeployment(this.value);

  final DeploymentConfig value;

  @override
  DeploymentConfig build() => value;
}
