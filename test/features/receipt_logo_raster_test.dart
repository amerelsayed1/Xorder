import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/printer_config.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/receipt/receipt_data.dart';
import 'package:xorder_pos/features/receipt/receipt_document.dart';
import 'package:xorder_pos/features/receipt/receipt_raster.dart';
import 'package:xorder_pos/features/receipt/slip_style.dart';

/// XORD-024: the business's logo on the printed slip.
///
/// The logos here are PNGs drawn in the test, so what is asserted is what the
/// printer's bitmap does with a real image: how big it comes out, where it
/// sits, what a bad one does to the slip, and that a light or transparent one
/// is not lost.
void main() {
  /// A PNG of [width] x [height] filled with [colour], over a transparent
  /// background when [margin] is set (a coloured box with a clear border).
  Future<Uint8List> png(
    int width,
    int height, {
    ui.Color colour = const ui.Color(0xFF000000),
    int margin = 0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(
        margin.toDouble(),
        margin.toDouble(),
        (width - 2 * margin).toDouble(),
        (height - 2 * margin).toDouble(),
      ),
      ui.Paint()..color = colour,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return bytes!.buffer.asUint8List();
  }

  bool inked(ReceiptBitmap bitmap, int x, int y) =>
      (bitmap.bits[y * bitmap.rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1 == 1;

  /// The box around every inked dot: (left, top, right, bottom), or null.
  (int, int, int, int)? inkBox(ReceiptBitmap bitmap) {
    var left = bitmap.width;
    var top = bitmap.height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < bitmap.height; y++) {
      for (var x = 0; x < bitmap.width; x++) {
        if (!inked(bitmap, x, y)) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return right < 0 ? null : (left, top, right, bottom);
  }

  Future<ReceiptBitmap> only(Uint8List logo, {int width = 576}) =>
      ReceiptRaster.render(
        ReceiptDocument(rightToLeft: false, blocks: [SlipLogo(logo)]),
        widthDots: width,
      );

  group('the logo alone', () {
    test(
      'is no taller than 120 dots and no wider than the content at 80mm',
      () async {
        final box = inkBox(await only(await png(1000, 200)))!;
        final (left, top, right, bottom) = box;

        expect(right - left + 1, lessThanOrEqualTo(576 - 2 * 12));
        expect(bottom - top + 1, lessThanOrEqualTo(120));
        expect(
          bottom - top + 1,
          greaterThan(100),
          reason: 'and not shrunk needlessly',
        );
      },
    );

    test('scales with the roll: at 58mm it is 80 dots tall at most', () async {
      final (left, top, right, bottom) = inkBox(
        await only(await png(300, 300), width: PrinterConfig.width58mm),
      )!;

      expect(bottom - top + 1, lessThanOrEqualTo(80));
      expect(right - left + 1, lessThanOrEqualTo(384 - 2 * 12));
    });

    test('is never enlarged past its own pixels', () async {
      final (left, top, right, bottom) = inkBox(await only(await png(64, 64)))!;

      expect(right - left + 1, 64);
      expect(bottom - top + 1, 64);
    });

    test('is centred on the paper', () async {
      final bitmap = await only(await png(100, 100));
      final (left, _, right, _) = inkBox(bitmap)!;

      final before = left;
      final after = bitmap.width - 1 - right;
      expect((before - after).abs(), lessThanOrEqualTo(1));
    });

    test(
      'a mid-tone coloured logo comes out as dots, not as nothing or a block',
      () async {
        final bitmap = await only(
          await png(120, 80, colour: const ui.Color(0xFF7090B0)),
        );
        // A colour of middling brightness: a plain threshold makes it all white
        // or all black; the dither makes about half of it ink.
        final all = bitmap.width * bitmap.height;
        expect(bitmap.inkedDots, greaterThan(0));
        expect(bitmap.inkedDots, lessThan(all ~/ 4), reason: 'not a black box');
        final (left, top, right, bottom) = inkBox(bitmap)!;
        final box = (right - left + 1) * (bottom - top + 1);
        expect(
          bitmap.inkedDots,
          greaterThan(box ~/ 5),
          reason: 'not near-empty',
        );
        expect(
          bitmap.inkedDots,
          lessThan(box * 4 ~/ 5),
          reason: 'not a solid block',
        );
      },
    );
  });

  group('what a bad or pale logo does', () {
    test(
      'a light-coloured logo still prints, where a threshold would lose it',
      () async {
        final bitmap = await only(
          await png(120, 120, colour: const ui.Color(0xFFFFF096)),
        );

        expect(bitmap.inkedDots, greaterThan(0));
      },
    );

    test('a transparent logo adds nothing but its height', () async {
      final clear = await png(100, 100, colour: const ui.Color(0x00000000));
      final bitmap = await only(clear);

      expect(bitmap.inkedDots, 0);
    });

    test(
      'a logo with a clear border prints the box and not the border',
      () async {
        final (left, top, right, bottom) = inkBox(
          await only(await png(100, 100, margin: 20)),
        )!;

        expect(right - left + 1, 60);
        expect(bottom - top + 1, 60);
      },
    );
  });

  group('the slip with a logo', () {
    ReceiptData sale({String? qr}) => ReceiptData(
      invoiceNumber: 'HST-000481',
      orderType: OrderType.takeaway,
      occurredAt: DateTime(2026, 10, 26, 2, 14),
      lines: const [
        ReceiptLine(name: 'Mixed Grill', quantity: 2, lineTotal: Money(30000)),
      ],
      subtotal: const Money(30000),
      discount: Money.zero,
      service: Money.zero,
      vat: const Money(4200),
      total: const Money(34200),
      paid: const Money(34200),
      change: Money.zero,
      taxLines: const [ReceiptTaxLine(rateBp: 1400, amount: Money(4200))],
      etaQrPayload: qr,
    );

    ReceiptDocument slip({Uint8List? logo, String? qr}) => ReceiptDocument.of(
      sale(qr: qr),
      strings: const EnStrings(),
      profile: const ReceiptProfile(branchId: 1, tradeName: 'Cafe Aziz'),
      tenantName: 'Cafe Aziz',
      terminalCode: 'T1',
      cashierName: 'Nour',
      logo: logo,
    );

    test(
      'a logo that will not decode prints the slip exactly as without one',
      () async {
        final without = await ReceiptRaster.render(slip());
        final broken = await ReceiptRaster.render(
          slip(logo: Uint8List.fromList([1, 2, 3, 4, 5])),
        );

        expect(broken.height, without.height);
        expect(broken.bits, without.bits);
      },
    );

    test('a real logo adds its height and keeps everything else', () async {
      final without = await ReceiptRaster.render(slip());
      final mark = await png(300, 100);
      final withLogo = await ReceiptRaster.render(slip(logo: mark));

      final added = withLogo.height - without.height;
      expect(added, greaterThanOrEqualTo(100));
      expect(added, lessThan(100 + 24));
      expect(withLogo.inkedDots, greaterThan(without.inkedDots));
    });

    test('the QR still prints in full under a logo', () async {
      const payload = 'https://eta.example/receipt/abc123';
      final without = await ReceiptRaster.render(slip(qr: payload));
      final withLogo = await ReceiptRaster.render(
        slip(logo: await png(300, 100), qr: payload),
      );

      // The slip is longer by the logo and no more: the square was neither
      // dropped nor shrunk to make room.
      final shift = withLogo.height - without.height;
      expect(shift, inInclusiveRange(100, 124));
      // And everything under the logo is the same dots as without one, moved
      // down: name, QR, totals, thank-you, untouched.
      for (var y = 0; y < without.height; y++) {
        for (var b = 0; b < without.rowBytes; b++) {
          expect(
            withLogo.bits[(y + shift) * withLogo.rowBytes + b],
            without.bits[y * without.rowBytes + b],
            reason: 'row $y byte $b',
          );
        }
      }
      expect(withLogo.inkedDots, greaterThan(without.inkedDots));
      // Never wider than the roll, never cut at the edge.
      final box = inkBox(withLogo)!;
      expect(box.$1, greaterThanOrEqualTo(SlipMetrics.margin.floor() - 1));
      expect(
        box.$3,
        lessThanOrEqualTo(withLogo.width - SlipMetrics.margin.floor()),
      );
    });
  });
}
