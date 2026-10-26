import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/printer_config.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/data/hardware/network_printer_ports.dart';
import 'package:xorder_pos/domain/models/business_logo.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/receipt/receipt_dialog.dart';
import 'package:xorder_pos/features/receipt/receipt_preview_dialog.dart';
import 'package:xorder_pos/features/receipt/receipt_printing.dart';
import 'package:xorder_pos/features/receipt/reprint_dialog.dart';

/// Settling a sale puts a receipt on paper.
///
/// **This is the bug the suite was written for.** *Print & new* showed
/// "Receipt queued for the default printer" and then closed: nothing was
/// printed, nothing was queued, and the first person to discover that was a
/// customer holding no receipt. Every test here asserts what reached the
/// printer or the queue rather than what the toast said — the toast was the
/// part that was already lying.
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

  /// A takeaway rung up and paid for, built through the engine so the totals
  /// are the ones a real sale would carry.
  Ticket settled({TenderMethod method = cash}) {
    final rung = TicketEngine.addLine(
      Ticket(id: 'txn-1', orderType: OrderType.takeaway),
      const Product(
        id: 1,
        categoryId: 1,
        nameEn: 'Mixed Grill',
        price: Money(15000),
      ),
    ).ticket!;

    return TicketEngine.addTender(
      rung,
      typeId: method.id,
      label: method.wireLabel,
      countsAsCash: method.countsAsCash,
    ).ticket!;
  }

  Future<(FakeHardwarePorts, _MemoryQueue)> open(
    WidgetTester tester, {
    PrinterConfig printer = const PrinterConfig(name: '10.20.30.40:9100'),
    bool reachable = true,
    TenderMethod method = cash,
    PrintQueueRepository? queue,
    String locale = 'en',
    Uint8List? logo,
  }) async {
    final ports = FakeHardwarePorts()..reachable = reachable;
    final store = queue is _MemoryQueue ? queue : _MemoryQueue();

    tester.view
      ..physicalSize = const Size(1200, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hardwarePortsProvider.overrideWithValue(ports),
          printQueueRepositoryProvider.overrideWithValue(store),
          printerConfigProvider.overrideWith(() => _FixedPrinter(printer)),
          if (logo != null) _logoOverride(logo),
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
              ticket: settled(method: method),
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
    return (ports, store);
  }

  /// Tap *Print & new* and let the print actually finish.
  ///
  /// The `runAsync` is not ceremony. The slip is rasterised through `dart:ui`,
  /// and an image future is completed by the engine on the **real** event loop
  /// — a widget test's fake clock will pump frames at it for ever and it will
  /// never resolve. This is the one place the printing path has to touch real
  /// time, and it is the same concession every golden that decodes an image
  /// makes.
  Future<void> printAndNew(WidgetTester tester, AppStrings strings) async {
    await tester.tap(find.text(strings.printAndNew));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    // Pumped rather than settled: the toast is what the cashier reads, and
    // `pumpAndSettle` waits out its three seconds and then asserts against a
    // screen it has already dismissed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a settled sale reaches the printer as an ESC/POS job', (
    tester,
  ) async {
    const strings = EnStrings();
    final (ports, queue) = await open(tester);

    await printAndNew(tester, strings);

    expect(ports.jobs, isNotEmpty, reason: 'the button prints');
    // The receipt is the first thing sent; a cash sale's drawer kick follows
    // it as a job of its own — see the next test.
    final job = ports.jobs.first;

    // Reset first, because the previous job may have left the printer bold.
    expect(job.take(EscPos.initialise.length), EscPos.initialise);
    // The slip itself, as dots: `GS v 0`. Arabic and the ETA QR both have to
    // reach paper, and neither survives a code page.
    expect(job.join(','), contains([0x1D, 0x76, 0x30, 0x00].join(',')));
    // And a cut, or the next receipt prints onto this one.
    expect(job.skip(job.length - EscPos.cut.length), EscPos.cut);

    expect(queue.jobs, isEmpty, reason: 'a receipt that printed is not queued');
    expect(find.text(strings.receiptPrintedToast), findsOneWidget);
  });

  testWidgets('a cash sale kicks the drawer, in a job of its own', (
    tester,
  ) async {
    final (ports, _) = await open(tester);
    await printAndNew(tester, const EnStrings());

    // NOT inside the receipt's job. The kick used to ride in it, and the same
    // bytes are what a silent printer queues — so a cash sale rung up while
    // the printer was off sprang the drawer hours later, on the next shift,
    // when the printer came back and the queue drained. The drawer answers to
    // the money changing hands now; the receipt can wait, the kick cannot.
    expect(ports.jobs, hasLength(2));
    expect(
      ports.jobs.first.join(','),
      isNot(contains(EscPos.openDrawer.join(','))),
      reason: 'the receipt job must be safe to queue',
    );
    expect(ports.jobs.last, EscPos.openDrawer);
  });

  testWidgets('a cash sale started anew without printing still kicks', (
    tester,
  ) async {
    final (ports, queue) = await open(tester);
    await tester.tap(find.text(const EnStrings().newSale));
    await tester.pumpAndSettle();

    // Whether a slip is wanted and whether the drawer should open are two
    // different questions, and a cashier who skips the paper still has the
    // customer's cash to put away.
    expect(ports.jobs, [EscPos.openDrawer]);
    expect(queue.jobs, isEmpty);
  });

  testWidgets('a card sale prints and leaves the drawer shut', (tester) async {
    final (ports, _) = await open(tester, method: card);
    await printAndNew(tester, const EnStrings());

    expect(ports.jobs, hasLength(1));
    expect(
      ports.jobs.single.join(','),
      isNot(contains(EscPos.openDrawer.join(','))),
      reason: 'the drawer follows the tender, not the receipt',
    );
  });

  testWidgets('a printer that does not answer queues the receipt', (
    tester,
  ) async {
    const strings = EnStrings();
    // A card sale, so the only sentence owed is the one about the paper.
    final (ports, queue) = await open(tester, reachable: false, method: card);

    await printAndNew(tester, strings);

    expect(ports.jobs, isEmpty);
    expect(queue.jobs, hasLength(1), reason: 'the toast promised a queue');
    expect(queue.jobs.single.invoiceNumber, 'HST-000481');
    expect(find.text(strings.receiptQueuedToast), findsOneWidget);

    // And what was queued is the job itself, not a note to build one later. A
    // receipt re-rendered tomorrow would be rendered against tomorrow's
    // profile and tomorrow's language — a different slip to the one the
    // customer was promised.
    final queued = queue.jobs.single.bytes;
    expect(queued.take(EscPos.initialise.length), EscPos.initialise);
    expect(queued.skip(queued.length - EscPos.cut.length), EscPos.cut);
  });

  testWidgets('a cash sale on a silent printer queues the paper, never the '
      'kick, and says the drawer stayed shut', (tester) async {
    const strings = EnStrings();
    final (ports, queue) = await open(tester, reachable: false);

    await printAndNew(tester, strings);

    expect(ports.jobs, isEmpty);
    expect(queue.jobs, hasLength(1));
    expect(
      queue.jobs.single.bytes.join(','),
      isNot(contains(EscPos.openDrawer.join(','))),
      reason: 'the drain must not open the till on somebody else\'s shift',
    );
    // Two things went wrong and the toast holds one sentence. The drawer's
    // wins: the receipt prints itself when the printer returns, the cash in
    // the cashier's hand needs the key now.
    expect(find.text(strings.drawerCouldNotOpen), findsOneWidget);
  });

  testWidgets('a till with no printer disables the print button and says '
      'why on it', (tester) async {
    const strings = EnStrings();
    final (ports, queue) = await open(tester, printer: PrinterConfig.none);

    // The audit (S5-1) found a disabled control on this dialog with nothing
    // written on it. The button keeps its place — the two-button layout is
    // what hands learn — but it is disabled and carries the reason.
    expect(find.text(strings.printAndNew), findsNothing);
    expect(find.text(strings.receiptNoPrinter), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      strings.receiptNoPrinterToast,
    );

    // Tapping it does nothing: the dialog stays, nothing is printed and
    // nothing is queued. Deliberately not queued — a till with no printer
    // would otherwise spool a month of receipts and print all of them on
    // the day one is plugged in.
    await tester.tap(find.text(strings.receiptNoPrinter), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptDialog), findsOneWidget);
    expect(ports.jobs, isEmpty);
    expect(queue.jobs, isEmpty);

    // New sale still moves on. A cash sale also asks for the drawer, and a
    // till with no printer has nothing to kick it through — and says nothing
    // about it, because there is no printer to blame.
    await tester.tap(find.text(strings.newSale));
    await tester.pumpAndSettle();
    expect(ports.jobs, isEmpty);
    expect(find.text(strings.drawerCouldNotOpen), findsNothing);
  });

  testWidgets('and says it in Arabic on an Arabic till', (tester) async {
    const strings = ArStrings();
    await open(tester, printer: PrinterConfig.none, locale: 'ar');

    expect(find.text(strings.receiptNoPrinter), findsOneWidget);
    expect(find.text(strings.printAndNew), findsNothing);
  });

  testWidgets('a till with a printer keeps the live button', (tester) async {
    const strings = EnStrings();
    await open(tester);

    expect(find.text(strings.printAndNew), findsOneWidget);
    expect(find.text(strings.receiptNoPrinter), findsNothing);
  });

  testWidgets('the queue is retried before the receipt in hand', (
    tester,
  ) async {
    const strings = EnStrings();
    final queue = _MemoryQueue()
      ..jobs.add(
        _Queued(id: 1, printerName: '10.20.30.40:9100', bytes: const [1, 2, 3]),
      );

    final (ports, _) = await open(tester, queue: queue);
    await printAndNew(tester, strings);

    // Yesterday's paper first, so receipts come out in the order the sales
    // happened rather than the order the printer came back. Then today's,
    // then the drawer for today's cash.
    expect(ports.jobs, hasLength(3));
    expect(ports.jobs.first, const [1, 2, 3]);
    expect(ports.jobs.last, EscPos.openDrawer);
    expect(queue.jobs.single.printed, isTrue);
  });

  testWidgets('every outcome has its own sentence, in both languages', (
    tester,
  ) async {
    // The whole failure this suite exists for was one message standing in for
    // four different things that happened.
    for (final strings in const <AppStrings>[EnStrings(), ArStrings()]) {
      final said = {
        for (final outcome in PrintOutcome.values)
          printOutcomeMessage(strings, outcome),
      };
      expect(said, hasLength(PrintOutcome.values.length));
      for (final message in said) {
        expect(message.trim(), isNotEmpty);
      }
    }
  });

  group('a reprint', () {
    /// The same dialog the orders list opens, with a printer behind it.
    Future<(FakeHardwarePorts, _MemoryQueue)> openReprint(
      WidgetTester tester, {
      Uint8List? logo,
      PrinterConfig printer = const PrinterConfig(name: '10.20.30.40:9100'),
    }) async {
      final ports = FakeHardwarePorts();
      final store = _MemoryQueue();

      tester.view
        ..physicalSize = const Size(1200, 1600)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hardwarePortsProvider.overrideWithValue(ports),
            printQueueRepositoryProvider.overrideWithValue(store),
            printerConfigProvider.overrideWith(() => _FixedPrinter(printer)),
            auditRepositoryProvider.overrideWithValue(FakeAuditRepository()),
            signedInStaffProvider.overrideWith(_SignedIn.new),
            if (logo != null) _logoOverride(logo),
          ],
          child: MaterialApp(
            theme: buildPosTheme(PosPalette.light),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReprintDialog(
                detail: OrderRecordDetail(
                  order: OrderRecord(
                    id: 7,
                    clientTransactionId: 'txn-7',
                    invoiceNumber: 'HST-000481',
                    status: OrderStatus.paid,
                    orderType: OrderType.dineIn,
                    occurredAt: DateTime(2026, 9, 7, 13, 5),
                    subtotal: const Money(17500),
                    discount: Money.zero,
                    service: const Money(1750),
                    vat: const Money(2695),
                    total: const Money(21945),
                    servedByName: 'Nour Adel',
                  ),
                  lines: const [
                    OrderRecordLine(
                      id: 10,
                      lineKey: 'L1',
                      name: 'Mixed Grill',
                      quantity: 1,
                      unitPrice: Money(17500),
                      lineTotal: Money(17500),
                    ),
                  ],
                  payments: const [],
                  discounts: const [],
                ),
                refunds: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (ports, store);
    }

    testWidgets('goes down the same path as a settlement', (tester) async {
      final (ports, queue) = await openReprint(tester);

      await tester.tap(find.text(const EnStrings().receiptReprintConfirm));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(ports.jobs, hasLength(1));
      final job = ports.jobs.single;
      expect(job.join(','), contains([0x1D, 0x76, 0x30, 0x00].join(',')));
      expect(job.skip(job.length - EscPos.cut.length), EscPos.cut);
      // No money is moving. A drawer that springs open on a copy of an old
      // receipt is a drawer standing open for nobody.
      expect(job.join(','), isNot(contains(EscPos.openDrawer.join(','))));
      expect(queue.jobs, isEmpty);
    });

    testWidgets('a reprint prints the logo the till holds now', (tester) async {
      final mark = (await tester.runAsync(_logoPng))!;

      Future<List<int>> reprinted({Uint8List? logo}) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final (ports, _) = await openReprint(tester, logo: logo);
        await tester.tap(find.text(const EnStrings().receiptReprintConfirm));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        for (var i = 0; i < 20 && ports.jobs.isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        return ports.jobs.single;
      }

      final plain = await reprinted();
      final branded = await reprinted(logo: mark);

      expect(branded.length, greaterThan(plain.length));
    });
  });
  group('a preview', () {
    testWidgets('shows the slip and sends nothing to the printer', (
      tester,
    ) async {
      // Looking at what a customer was given should not cost a sheet of paper
      // and an audit row.
      final ports = FakeHardwarePorts();
      tester.view
        ..physicalSize = const Size(1200, 1600)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hardwarePortsProvider.overrideWithValue(ports),
            printerConfigProvider.overrideWith(
              () =>
                  _FixedPrinter(const PrinterConfig(name: '10.20.30.40:9100')),
            ),
          ],
          child: MaterialApp(
            theme: buildPosTheme(PosPalette.light),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReceiptPreviewDialog(
                detail: OrderRecordDetail(
                  order: OrderRecord(
                    id: 7,
                    clientTransactionId: 'txn-7',
                    invoiceNumber: 'HST-000481',
                    status: OrderStatus.paid,
                    orderType: OrderType.dineIn,
                    occurredAt: DateTime(2026, 9, 7, 13, 5),
                    subtotal: const Money(17500),
                    discount: Money.zero,
                    service: const Money(1750),
                    vat: const Money(2695),
                    total: const Money(21945),
                    servedByName: 'Nour Adel',
                  ),
                  lines: const [
                    OrderRecordLine(
                      id: 10,
                      lineKey: 'L1',
                      name: 'Mixed Grill',
                      quantity: 1,
                      unitPrice: Money(17500),
                      lineTotal: Money(17500),
                    ),
                  ],
                  payments: const [],
                  discounts: const [],
                ),
                refunds: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Mixed Grill'), findsWidgets);
      expect(find.textContaining('HST-000481'), findsWidgets);
      expect(find.text(const EnStrings().receiptPreviewNote), findsOneWidget);

      await tester.tap(find.text(const EnStrings().close));
      await tester.pumpAndSettle();
      expect(ports.jobs, isEmpty, reason: 'a preview prints nothing');
    });
  });

  group('the logo (XORD-024)', () {
    /// A logo adds two more turns of the real event loop (reading it, then
    /// decoding it) before a job exists; wait for the job, not for a time.
    Future<void> settle(WidgetTester tester, FakeHardwarePorts ports) async {
      for (var i = 0; i < 20 && ports.jobs.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }

    /// The bytes the printer was sent for the one receipt this test prints.
    Future<List<int>> printedSale(
      WidgetTester tester, {
      Uint8List? logo,
      PrinterConfig printer = const PrinterConfig(name: '10.20.30.40:9100'),
    }) async {
      // A fresh tree each time: a scope pumped over an old one keeps the old
      // overrides, and the second sale would be measured against the first's.
      await tester.pumpWidget(const SizedBox.shrink());
      final (ports, _) = await open(tester, logo: logo, printer: printer);
      await printAndNew(tester, const EnStrings());
      await settle(tester, ports);
      // A cash sale sends the drawer kick as a job of its own; the receipt is
      // the long one.
      return ports.jobs.reduce((a, b) => a.length >= b.length ? a : b);
    }

    testWidgets('a sale prints it when the till has one', (tester) async {
      final mark = (await tester.runAsync(_logoPng))!;

      final plain = await printedSale(tester);
      final branded = await printedSale(tester, logo: mark);

      // The slip is a picture; a logo makes the picture taller, and the job
      // is the picture. Same start and end: reset, ..., feed, cut.
      expect(branded.length, greaterThan(plain.length));
      expect(branded.skip(branded.length - EscPos.cut.length), EscPos.cut);
    });

    testWidgets('and not when this till is set to leave it off', (
      tester,
    ) async {
      final mark = (await tester.runAsync(_logoPng))!;

      final plain = await printedSale(tester);
      final off = await printedSale(
        tester,
        logo: mark,
        printer: const PrinterConfig(
          name: '10.20.30.40:9100',
          printLogo: false,
        ),
      );

      expect(off, plain);
    });

    testWidgets('a logo nobody can decode costs the sale nothing', (
      tester,
    ) async {
      final plain = await printedSale(tester);
      final broken = await printedSale(
        tester,
        logo: Uint8List.fromList([9, 9, 9]),
      );

      expect(broken, plain);
    });

    Future<void> previewing(
      WidgetTester tester, {
      Uint8List? logo,
      PrinterConfig printer = const PrinterConfig(name: '10.20.30.40:9100'),
    }) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, logo: logo, printer: printer);
    }

    testWidgets('the preview shows it', (tester) async {
      final mark = (await tester.runAsync(_logoPng))!;

      await previewing(tester, logo: mark);

      expect(find.byKey(const Key('receipt-logo')), findsOneWidget);
    });

    testWidgets('the preview shows none when this till leaves it off', (
      tester,
    ) async {
      final mark = (await tester.runAsync(_logoPng))!;

      await previewing(
        tester,
        logo: mark,
        printer: const PrinterConfig(
          name: '10.20.30.40:9100',
          printLogo: false,
        ),
      );

      expect(find.byKey(const Key('receipt-logo')), findsNothing);
    });

    testWidgets('and none when the restaurant has no logo', (tester) async {
      await previewing(tester);

      expect(find.byKey(const Key('receipt-logo')), findsNothing);
    });
  });
}

/// The till holds this logo (XORD-024).
Override _logoOverride(Uint8List bytes) => businessLogoProvider.overrideWith(
  (ref) async =>
      BusinessLogo(bytes: bytes, mime: 'image/png', source: LogoSource.local),
);

/// A PNG, drawn here: a black box 300 x 100.
Future<Uint8List> _logoPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 300, 100),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 100);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// A printer config that is simply what the test says it is.
class _FixedPrinter extends PrinterConfigController {
  _FixedPrinter(this.value);

  final PrinterConfig value;

  @override
  PrinterConfig build() => value;
}

class _Queued {
  _Queued({
    required this.id,
    required this.printerName,
    required this.bytes,
    this.invoiceNumber,
  });

  final int id;
  final String printerName;
  final List<int> bytes;
  final String? invoiceNumber;
  bool printed = false;
  int attempts = 0;
}

/// The print queue in memory. A test double, never a binding — the real one is
/// a table, because a receipt that failed to print is evidence about a sale.
class _MemoryQueue implements PrintQueueRepository {
  final jobs = <_Queued>[];

  @override
  Future<int> enqueue({
    required String printerName,
    required List<int> bytes,
    required bool isReprint,
    int? orderId,
    String? invoiceNumber,
  }) async {
    final job = _Queued(
      id: jobs.length + 1,
      printerName: printerName,
      bytes: bytes,
      invoiceNumber: invoiceNumber,
    );
    jobs.add(job);
    return job.id;
  }

  @override
  Future<List<QueuedPrintJob>> pending({int limit = 5}) async => [
    for (final job in jobs.where((j) => !j.printed).take(limit))
      QueuedPrintJob(
        id: job.id,
        printerName: job.printerName,
        bytes: job.bytes,
        attempts: job.attempts,
        invoiceNumber: job.invoiceNumber,
      ),
  ];

  @override
  Future<void> markPrinted(int id) async {
    jobs.firstWhere((j) => j.id == id).printed = true;
  }

  @override
  Future<void> markAttempted(int id, {String? error}) async {
    jobs.firstWhere((j) => j.id == id).attempts++;
  }
}

/// Somebody who may reprint. The permission gate is `reprint_test.dart`'s
/// subject; here the reprint is already allowed and the question is what
/// reaches the printer.
class _SignedIn extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 9,
    name: 'Hana Mostafa',
    capabilities: {PosCapability.operate, PosCapability.receiptReprint},
  );
}
