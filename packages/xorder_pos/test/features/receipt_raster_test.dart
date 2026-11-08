import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/printer_config.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/hardware/network_printer_ports.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/receipt/receipt_data.dart';
import 'package:xorder_pos/features/receipt/receipt_document.dart';
import 'package:xorder_pos/features/receipt/receipt_raster.dart';

/// The slip, as dots.
///
/// **What this suite is really asserting is that Arabic reaches paper.**
/// `EscPos.text` maps anything above 0xFF to `?` and says so in a comment —
/// printing Arabic through a printer code page is a bet on firmware nobody
/// controls. The receipt is therefore rendered to a bitmap, and the way to know
/// that worked is to count the ink where the Arabic went.
void main() {
  ReceiptData sale({String? qr}) => ReceiptData(
    invoiceNumber: 'HST-000481',
    orderType: OrderType.dineIn,
    tableLabel: 'T12',
    occurredAt: DateTime(2026, 9, 9, 21, 14),
    lines: const [
      ReceiptLine(name: 'Mixed Grill', quantity: 2, lineTotal: Money(30000)),
      ReceiptLine(name: 'Mint tea', quantity: 1, lineTotal: Money(2500)),
    ],
    subtotal: const Money(32500),
    discount: Money.zero,
    service: const Money(3250),
    vat: const Money(5005),
    total: const Money(40755),
    paid: const Money(50000),
    change: const Money(9245),
    serviceBp: 1000,
    taxLines: const [ReceiptTaxLine(rateBp: 1400, amount: Money(5005))],
    etaQrPayload: qr,
  );

  ReceiptDocument document({
    AppStrings strings = const EnStrings(),
    String tradeName = 'Hosny Grill',
    String? qr,
  }) => ReceiptDocument.of(
    sale(qr: qr),
    strings: strings,
    profile: ReceiptProfile(branchId: 1, tradeName: tradeName),
    tenantName: tradeName,
    terminalCode: 'T1',
    cashierName: 'Nour',
  );

  group('the picture', () {
    test('is exactly as wide as the paper it is going on', () async {
      // Not scaled by the printer: a raster wider than the head loses its
      // right-hand columns, which on a receipt is the entire totals column.
      final wide = await ReceiptRaster.render(document());
      expect(wide.width, PrinterConfig.width80mm);
      expect(wide.rowBytes, 72);

      final narrow = await ReceiptRaster.render(
        document(),
        widthDots: PrinterConfig.width58mm,
      );
      expect(narrow.width, PrinterConfig.width58mm);
      expect(narrow.rowBytes, 48);
      // A smaller slip, not a clipped one — the type scales with the paper.
      expect(narrow.height, lessThan(wide.height));
    });

    test('is ink on paper, not a black page', () async {
      // The failure this catches is a real one and costs a whole roll: an
      // unpainted canvas is transparent, transparent reads as luminance zero,
      // and the entire receipt rasterises as solid ink.
      final bitmap = await ReceiptRaster.render(document());

      expect(bitmap.inkedDots, greaterThan(1000));
      // Half, not a tenth, because the harness has no real fonts: the test
      // font draws every glyph as a filled box, so a slip that would be a
      // tenth ink on a printer is nearly half ink here. What is being caught is
      // the total failure — a page of solid black — not the typography.
      expect(
        bitmap.inkedDots,
        lessThan(bitmap.width * bitmap.height ~/ 2),
        reason: 'a receipt is mostly paper',
      );
    });
  });

  group('Arabic', () {
    test('prints, rather than becoming a row of question marks', () async {
      final arabic = await ReceiptRaster.render(
        document(strings: const ArStrings(), tradeName: 'مطعم حسني'),
      );

      // The trade name is the first thing on the slip, set largest. If Arabic
      // were being dropped this band would be blank paper.
      expect(
        arabic.inkedDotsBetween(0, 60),
        greaterThan(200),
        reason: 'the business name is Arabic and it has to be on the paper',
      );
      expect(arabic.inkedDots, greaterThan(1000));
    });

    test('is a slip of its own, not the English one with a stamp', () async {
      // Different words, different lengths, different direction — the two
      // bitmaps must not be identical, which is what a renderer that quietly
      // fell back to English would produce.
      final english = await ReceiptRaster.render(document());
      final arabic = await ReceiptRaster.render(
        document(strings: const ArStrings(), tradeName: 'مطعم حسني'),
      );

      expect(arabic.bits, isNot(english.bits));
    });
  });

  group('the ETA QR', () {
    test('reaches paper when there is a payload', () async {
      final without = await ReceiptRaster.render(document());
      final with_ = await ReceiptRaster.render(
        document(qr: '1234567890abcdef' * 8),
      );

      // A QR is a solid block of modules: it makes the slip both taller and
      // markedly darker.
      expect(with_.height, greaterThan(without.height + 100));
      expect(with_.inkedDots, greaterThan(without.inkedDots + 2000));
    });

    test('and no square at all when there is not', () async {
      // A slip without a QR is honest; one with a QR this app invented would
      // scan to nothing.
      final data = sale();
      expect(data.etaQrPayload, isNull);
      expect(
        document().blocks.whereType<SlipQr>(),
        isEmpty,
      );
    });
  });

  group('GS v 0', () {
    test('carries the width in bytes and the height in rows', () async {
      final bitmap = await ReceiptRaster.render(document());
      final bytes = EscPos.raster(
        width: bitmap.width,
        height: bitmap.height,
        bits: bitmap.bits,
      );

      expect(bytes.take(4), [0x1D, 0x76, 0x30, 0x00]);
      // 576 dots is 72 bytes a row, little-endian.
      expect(bytes.skip(4).take(2), [72, 0]);
    });

    test('is sent in bands a small printer can hold', () async {
      // A printer that accepts a 65535-row command and then runs out of image
      // buffer half way down prints the rest as noise.
      final bitmap = await ReceiptRaster.render(document());
      final bytes = EscPos.raster(
        width: bitmap.width,
        height: bitmap.height,
        bits: bitmap.bits,
      );

      final commands = _headerCount(bytes, bitmap.rowBytes);
      expect(commands, greaterThan(1), reason: 'a receipt is taller than a band');
      // And every dot is accounted for: the payload plus one 8-byte header per
      // band is the whole stream.
      expect(bytes.length, bitmap.bits.length + commands * 8);
    });

    test('an empty picture is no command at all', () {
      expect(EscPos.raster(width: 0, height: 0, bits: const []), isEmpty);
    });
  });
}

/// How many `GS v 0` headers the stream carries, walked rather than searched:
/// the payload can contain the header bytes by coincidence, and a naive scan
/// would count those too.
int _headerCount(List<int> bytes, int rowBytes) {
  var index = 0;
  var count = 0;
  while (index < bytes.length) {
    expect(bytes.skip(index).take(4), [0x1D, 0x76, 0x30, 0x00]);
    final rows = bytes[index + 6] | (bytes[index + 7] << 8);
    index += 8 + rows * rowBytes;
    count++;
  }
  return count;
}
