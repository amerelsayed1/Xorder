import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import 'receipt_paper.dart';

/// The QR square on a printed receipt.
///
/// **Painted, not fetched.** A receipt has to print on a till with no line to
/// anywhere, so the square is rendered from the payload here rather than pulled
/// as an image — and it is painted as plain black rectangles, because a thermal
/// printer has two colours and antialiasing between them is what makes a code
/// unreadable at 203dpi.
///
/// The payload itself is **not** computed by this app. ETA's integration
/// toolkit generates it alongside the seal, and it encodes more than the
/// receipt's uuid; a square this app invented would scan to nothing. So the
/// widget takes a string and draws it, and prints nothing at all when there
/// isn't one — a slip without a QR is honest, a slip with a broken one is not.
/// The code itself, built once for both the screen and the paper.
///
/// Extracted when printing arrived. The raster cannot use the widget — it has
/// no widget tree — so it would otherwise build its own [QrCode], and the two
/// would be one edit away from disagreeing about the error-correction level.
/// A preview at M and a printed square at L is a difference nobody would see
/// until a customer's phone would not read the paper.
abstract final class ReceiptQrCode {
  /// Error correction M, not L. A receipt gets folded, rained on and left in a
  /// pocket, and the extra redundancy costs a few modules.
  static QrImage imageOf(String payload) => QrImage(
    QrCode.fromData(data: payload, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
}

class ReceiptQr extends StatelessWidget {
  const ReceiptQr({super.key, required this.payload, this.size = 132});

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = ReceiptQrCode.imageOf(payload);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QrPainter(image)),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final modules = image.moduleCount;
    // Floored to a whole device pixel, so no module lands on a half pixel and
    // comes out grey. The leftover is used to centre the code rather than
    // stretch it.
    final module = (size.width / modules).floorToDouble();
    final drawn = module * modules;
    final offset = ((size.width - drawn) / 2).floorToDouble();

    final paint = Paint()
      // The slip's own ink, not a raw black. The receipt pins one palette
      // because paper is white in a dark room too, and a QR that reached for
      // its own colour would be the one thing on the page that did.
      ..color = receiptPalette.ink
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    for (var x = 0; x < modules; x++) {
      for (var y = 0; y < modules; y++) {
        if (!image.isDark(y, x)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            offset + x * module,
            offset + y * module,
            module,
            module,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
