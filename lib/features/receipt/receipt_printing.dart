import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/printer_config.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/hardware/network_printer_ports.dart';
import '../../domain/repositories/repositories.dart';
import 'receipt_document.dart';
import 'receipt_raster.dart';

/// What happened when the till tried to print.
///
/// Four answers, not two, because the cashier is told which one it was and
/// three of them mean different things to do next. *Print & new* used to show
/// "Receipt queued for the default printer" unconditionally while printing
/// nothing and queuing nothing — the toast is the till's only account of itself
/// here, and it was a lie in every case.
enum PrintOutcome {
  /// The printer took it.
  printed,

  /// The printer did not answer and the receipt is in the queue. It goes out on
  /// the next sale's attempt.
  queued,

  /// The printer did not answer and the queue could not be written either —
  /// which means the branch database is unreachable too. Rare, and it must not
  /// be reported as "queued", because nothing was.
  failed,

  /// No printer is set up on this till. Nothing was printed and nothing was
  /// queued, deliberately: a till with no printer would otherwise spool a
  /// month of receipts and print them all on the day one is plugged in.
  noPrinter,
}

/// What the cashier is told. Enum-keyed, so a new outcome does not fall through
/// to a sentence about a different one.
String printOutcomeMessage(AppStrings strings, PrintOutcome outcome) =>
    switch (outcome) {
      PrintOutcome.printed => strings.receiptPrintedToast,
      PrintOutcome.queued => strings.receiptQueuedToast,
      PrintOutcome.failed => strings.receiptNotPrintedToast,
      PrintOutcome.noPrinter => strings.receiptNoPrinterToast,
    };

/// Builds a receipt job and gets it onto paper.
///
/// **One job, one connection.** The picture, the feed, the drawer kick and the
/// cut are a single stream of bytes to a single socket. Kicking the drawer
/// through a second call would open it on a receipt that failed to print, which
/// is a drawer standing open for a sale nobody can hand over.
class ReceiptPrinter {
  const ReceiptPrinter({
    required this.ports,
    required this.printer,
    this.queue,
  });

  final HardwarePorts ports;
  final PrinterConfig printer;

  /// Null when this terminal has no database — a till mid-setup. Then a failed
  /// print is [PrintOutcome.failed] rather than a promise nothing kept.
  final PrintQueueRepository? queue;

  /// Print a slip.
  ///
  /// [openDrawer] comes from the tender that settled it — see
  /// `TenderMethod.opensDrawer`. It rides inside this job.
  Future<PrintOutcome> printReceipt(
    ReceiptDocument document, {
    bool openDrawer = false,
    bool isReprint = false,
    int? orderId,
    String? invoiceNumber,
  }) async {
    final name = printer.name?.trim();
    if (name == null || name.isEmpty) return PrintOutcome.noPrinter;

    final bytes = await buildJob(
      document,
      widthDots: printer.paperWidthDots,
      openDrawer: openDrawer,
    );

    // Yesterday's paper first, so the receipts come out in the order the sales
    // happened. A customer handed the slip above theirs is a customer holding
    // somebody else's total.
    await drain();

    if (await ports.sendJob(printerName: name, bytes: bytes)) {
      return PrintOutcome.printed;
    }

    final store = queue;
    if (store == null) return PrintOutcome.failed;
    try {
      await store.enqueue(
        printerName: name,
        bytes: bytes,
        isReprint: isReprint,
        orderId: orderId,
        invoiceNumber: invoiceNumber,
      );
      return PrintOutcome.queued;
    } on Object {
      // The printer is off AND the database is unreachable. Nothing more can be
      // done for this receipt, and saying "queued" would be the same lie again.
      return PrintOutcome.failed;
    }
  }

  /// Try the outstanding jobs. Returns how many reached paper.
  ///
  /// **Stops at the first failure.** A printer that has just refused one job
  /// will refuse the next, and hammering it holds up the sale behind it — the
  /// cashier is waiting on this before the receipt they are actually printing.
  Future<int> drain() async {
    final store = queue;
    final name = printer.name?.trim();
    if (store == null || name == null || name.isEmpty) return 0;

    var printed = 0;
    try {
      for (final job in await store.pending()) {
        // The printer the job was queued for, not the one configured now: a
        // terminal repointed at a different printer must still print the paper
        // it owes, and the address it owes it to is on the row.
        final ok = await ports.sendJob(
          printerName: job.printerName,
          bytes: job.bytes,
        );
        if (!ok) {
          await store.markAttempted(job.id, error: 'The printer did not answer.');
          break;
        }
        await store.markPrinted(job.id);
        printed++;
      }
    } on Object {
      // A drain that throws must never take a sale down with it. The jobs stay
      // pending, which is the state that makes them come back.
      return printed;
    }
    return printed;
  }

  /// The whole ESC/POS job: reset, picture, feed, kick, cut.
  ///
  /// Static and pure so a test can read the bytes without a printer, a socket
  /// or a widget tree.
  static Future<List<int>> buildJob(
    ReceiptDocument document, {
    int widthDots = PrinterConfig.width80mm,
    bool openDrawer = false,
  }) async {
    final bitmap = await ReceiptRaster.render(document, widthDots: widthDots);

    return [
      // Reset first, always: the previous job may have left the printer bold,
      // upside down, or in a code page nobody chose.
      ...EscPos.initialise,
      ...EscPos.alignLeft,
      ...EscPos.raster(
        width: bitmap.width,
        height: bitmap.height,
        bits: bitmap.bits,
      ),
      // Enough paper past the head that the cut lands below the last line.
      ...EscPos.feed(3),
      // After the picture, so the drawer springs as the paper appears rather
      // than while the customer is still being told the total.
      if (openDrawer) ...EscPos.openDrawer,
      ...EscPos.cut,
    ];
  }
}

/// The till's printer, assembled from what setup saved and what is reachable.
final receiptPrinterProvider = Provider<ReceiptPrinter>(
  (ref) => ReceiptPrinter(
    ports: ref.watch(hardwarePortsProvider),
    printer: ref.watch(printerConfigProvider),
    queue: ref.watch(printQueueRepositoryProvider),
  ),
);
