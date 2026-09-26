/// How big everything on the slip is, and the three small pictures on it.
///
/// **One table of sizes for two renderers.** The paper is painted in dots by
/// `ReceiptRaster`; the preview is a widget tree in `receipt_paper.dart`. They
/// used to carry their own sizes — 34 dots for the name on paper, 17px on
/// screen, chosen separately — and the preview showed a receipt the printer
/// never produced. Both now read these numbers, in dots at the 80mm reference,
/// and scale them to what they are drawing on. The preview is the paper at a
/// smaller size, not a sketch of it.
///
/// Doubles here are geometry, not money. Nothing on this page is a price.
library;

import 'dart:ui' as ui;

import '../../core/config/printer_config.dart';
import 'receipt_document.dart';

abstract final class SlipMetrics {
  /// What an 80mm head can print, in dots. Everything below is sized against
  /// it, and a 58mm printer gets the same slip scaled down.
  static const printableDots = PrinterConfig.width80mm;

  /// The whole roll, including the strip each side the head cannot reach —
  /// 80mm at 8 dots a millimetre. The preview draws the paper this wide so
  /// its margins are the margins the customer sees.
  static const paperDots = 640;
  static const paperEdge = 32.0;

  /// White down each edge of the printable area. A head's outermost columns
  /// drift as the roll wanders, so nothing is printed there.
  static const margin = 12.0;
  static const contentDots = printableDots - 2 * margin;

  static const top = 8.0;
  static const tail = 16.0;

  // Type, in dots at 203dpi. 22 dots is about 2.7mm of cap height, which is
  // what a receipt has been printed at since receipts existed.
  static const titleSize = 38.0;
  static const strongSize = 26.0;
  static const bodySize = 22.0;
  static const smallSize = 18.0;
  static const headerSize = 20.0;
  static const stampSize = 26.0;
  static const totalLabelSize = 34.0;
  static const totalAmountSize = 56.0;
  static const currencySize = 18.0;

  static const glyphSize = 20.0;
  static const glyphGap = 8.0;

  // The items table. Fixed columns rather than measured ones, so the prices
  // on one slip line up under each other whatever their lengths — 140 dots
  // holds "999,999.99" in the body mono.
  static const qtyColumn = 64.0;
  static const priceColumn = 140.0;
  static const columnGap = 8.0;
  static const headerPad = 6.0;

  static const rowGap = 4.0;
  static const lineGap = 4.0;

  static const ruleAbove = 8.0;
  static const ruleBelow = 10.0;
  static const dash = 8.0;
  static const dashGap = 6.0;

  static const stampPad = 5.0;
  static const stampInset = 6.0;
  static const stampBorder = 3.0;
  static const stampAfter = 8.0;

  static const ornamentLine = 48.0;
  static const ornamentGap = 10.0;
  static const ornamentHeart = 22.0;

  static double centreSize(SlipEmphasis emphasis) => switch (emphasis) {
    SlipEmphasis.title => titleSize,
    SlipEmphasis.strong => strongSize,
    SlipEmphasis.body => bodySize,
    SlipEmphasis.small => smallSize,
  };

  static bool centreBold(SlipEmphasis emphasis) => switch (emphasis) {
    SlipEmphasis.title || SlipEmphasis.strong => true,
    SlipEmphasis.body || SlipEmphasis.small => false,
  };

  static double ruleThickness(SlipRuleWeight weight) => switch (weight) {
    SlipRuleWeight.solid || SlipRuleWeight.dashed => 2.0,
    SlipRuleWeight.heavy => 5.0,
  };

  /// The QR's module, in whole dots, for a code [modules] wide on [content]
  /// dots of paper.
  ///
  /// Three fifths of the width at most. The square used to take the whole
  /// width — 66mm of QR on an 80mm slip — which scans no better than 40mm and
  /// pushes the thank-you off the first fold. Whole dots, never fractions: a
  /// module on half a dot prints at half strength and reads as noise. Two dots
  /// minimum, because one-dot modules do not survive a folded receipt.
  static int qrModule(int modules, double content) =>
      (content * 3 / 5 / (modules + 8)).floor().clamp(2, 12);
}

/// Paint [glyph] into [box] with [ink].
///
/// **Drawn, not typed.** The Material icon font would put a phone on the
/// preview and, on the raster, whatever the engine resolves a private-use code
/// point to on a till that may not have the font loaded — and it cannot be
/// loaded headless, which is where a queued job is re-rendered. Three paths on
/// a 24-unit grid draw the same on both.
void paintSlipGlyph(
  ui.Canvas canvas,
  SlipGlyph glyph,
  ui.Rect box,
  ui.Paint ink,
) {
  final unit = box.width / 24;
  double x(double v) => box.left + v * unit;
  double y(double v) => box.top + v * unit;

  final path = ui.Path();
  switch (glyph) {
    case SlipGlyph.phone:
      // A handset, earpiece at the top left.
      path
        ..moveTo(x(5), y(3))
        ..lineTo(x(9), y(3))
        ..lineTo(x(10.5), y(7.5))
        ..lineTo(x(8), y(9.5))
        ..cubicTo(x(9.2), y(12.2), x(11.8), y(14.8), x(14.5), y(16))
        ..lineTo(x(16.5), y(13.5))
        ..lineTo(x(21), y(15))
        ..lineTo(x(21), y(19))
        ..cubicTo(x(21), y(20.1), x(20.1), y(21), x(19), y(21))
        ..cubicTo(x(10.2), y(21), x(3), y(13.8), x(3), y(5))
        ..cubicTo(x(3), y(3.9), x(3.9), y(3), x(5), y(3))
        ..close();
    case SlipGlyph.pin:
      path
        ..fillType = ui.PathFillType.evenOdd
        ..moveTo(x(12), y(22))
        ..cubicTo(x(12), y(22), x(5), y(14.5), x(5), y(9))
        ..arcToPoint(
          ui.Offset(x(19), y(9)),
          radius: ui.Radius.circular(7 * unit),
        )
        ..cubicTo(x(19), y(14.5), x(12), y(22), x(12), y(22))
        ..close()
        ..addOval(
          ui.Rect.fromCircle(center: ui.Offset(x(12), y(9)), radius: 2.6 * unit),
        );
    case SlipGlyph.heart:
      path
        ..moveTo(x(12), y(21))
        ..cubicTo(x(5), y(16), x(2), y(12), x(2), y(8))
        ..cubicTo(x(2), y(5), x(4.5), y(3), x(7), y(3))
        ..cubicTo(x(9), y(3), x(11), y(4.2), x(12), y(6))
        ..cubicTo(x(13), y(4.2), x(15), y(3), x(17), y(3))
        ..cubicTo(x(19.5), y(3), x(22), y(5), x(22), y(8))
        ..cubicTo(x(22), y(12), x(19), y(16), x(12), y(21))
        ..close();
  }
  canvas.drawPath(path, ink);
}
