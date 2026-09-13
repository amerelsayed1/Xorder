import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr/qr.dart';

import '../../core/config/printer_config.dart';
import 'receipt_document.dart';
import 'receipt_qr.dart';

/// The receipt as dots, ready for `GS v 0`.
///
/// **Why a picture and not a code page.** A thermal printer will happily print
/// text if you send it bytes in whatever code page it has loaded, and cheap
/// ones disagree wildly about which that is — `EscPos.text` says so and maps
/// anything above 0xFF to `?` rather than printing confident mojibake. Arabic
/// on a receipt is not optional in Egypt, so the choice is between a code page
/// that is right on the printer we tested and wrong on the one the restaurant
/// bought, and sending the whole slip as a bitmap. A bitmap prints the same on
/// every printer that speaks ESC/POS at all, carries the ETA QR without a
/// second mechanism, and cannot silently substitute a glyph.
///
/// The cost is honest and worth naming: about 40KB per receipt on the wire
/// instead of about 400 bytes, and a slip that cannot be re-flowed by the
/// printer. Neither matters over a LAN socket to a device that prints one page.
///
/// **Rendered through `dart:ui` directly, not by capturing a widget.** A
/// `RepaintBoundary` capture needs the receipt to be on screen, and the two
/// paths that matter most — a queued job retried after the printer came back,
/// and a reprint from the orders list — have no live widget for the slip. This
/// is a pure function from [ReceiptDocument] to dots, so it works headless and
/// runs in `flutter test`.
abstract final class ReceiptRaster {
  /// White margin down each edge, in dots.
  ///
  /// A thermal head's first and last few columns are the ones that drift out of
  /// alignment as the roll wanders, so nothing is printed there.
  static const _margin = 12;

  /// Everything below is sized for an 80mm roll and scaled from it, so a 58mm
  /// printer gets a smaller slip rather than a clipped one.
  static const _referenceWidth = PrinterConfig.width80mm;

  /// Render the whole slip.
  ///
  /// [widthDots] must be the printer's real printable width — see
  /// [PrinterConfig.paperWidthDots]. Too wide and the printer throws away the
  /// columns it has no head for, which loses the right-hand side of every
  /// total.
  static Future<ReceiptBitmap> render(
    ReceiptDocument document, {
    int widthDots = PrinterConfig.width80mm,
  }) async {
    final layout = _Layout(document, widthDots);
    final image = await layout.paint();
    try {
      return await pack(image);
    } finally {
      image.dispose();
    }
  }

  /// One bit per dot, MSB first, rows padded to a whole byte — the layout `GS
  /// v 0` expects, so no shuffling happens in the transport.
  ///
  /// The threshold is a plain 50% on luminance. Dithering was considered and
  /// rejected: a receipt is text and a QR, both of which are already black or
  /// white, and dithering the antialiased edge of a glyph makes it *fuzzier* on
  /// a head that has exactly two states.
  static Future<ReceiptBitmap> pack(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('The receipt could not be rasterised.');
    }

    final width = image.width;
    final height = image.height;
    final rowBytes = (width + 7) ~/ 8;
    final bits = Uint8List(rowBytes * height);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final r = data.getUint8(offset);
        final g = data.getUint8(offset + 1);
        final b = data.getUint8(offset + 2);
        // Rec. 601 luma, integer: the same weighting every thermal driver uses,
        // and it keeps a mid-grey antialiased edge on the ink side of the line
        // where a plain average would drop it.
        final luma = (r * 299 + g * 587 + b * 114) ~/ 1000;
        if (luma >= 128) continue;
        bits[y * rowBytes + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }

    return ReceiptBitmap(width: width, height: height, bits: bits);
  }
}

/// A 1-bit image of a receipt. `1` is ink.
class ReceiptBitmap {
  const ReceiptBitmap({
    required this.width,
    required this.height,
    required this.bits,
  });

  final int width;
  final int height;
  final Uint8List bits;

  int get rowBytes => (width + 7) ~/ 8;

  /// How many dots are inked. Cheap, and the only way a test can ask "did the
  /// Arabic actually print" without reading the paper.
  int get inkedDots {
    var count = 0;
    for (final byte in bits) {
      var value = byte;
      while (value != 0) {
        count += value & 1;
        value >>= 1;
      }
    }
    return count;
  }

  /// The inked dots in a horizontal band, so a test can ask about one line of
  /// the slip rather than the whole page.
  int inkedDotsBetween(int fromRow, int toRow) {
    var count = 0;
    final from = fromRow.clamp(0, height);
    final to = toRow.clamp(0, height);
    for (var y = from; y < to; y++) {
      for (var x = 0; x < rowBytes; x++) {
        var value = bits[y * rowBytes + x];
        while (value != 0) {
          count += value & 1;
          value >>= 1;
        }
      }
    }
    return count;
  }
}

/// Lays the blocks out once, then paints them.
///
/// Two passes because [ui.Picture.toImage] needs the height up front, and the
/// height is the sum of paragraphs that have to be laid out to be measured.
/// Keeping the laid-out paragraphs between the passes avoids doing the
/// expensive half twice.
class _Layout {
  _Layout(this.document, this.widthDots)
    : scale = widthDots / ReceiptRaster._referenceWidth;

  final ReceiptDocument document;
  final int widthDots;
  final double scale;

  static const _black = ui.Color(0xFF000000);
  static const _white = ui.Color(0xFFFFFFFF);

  double get _content => widthDots - 2.0 * ReceiptRaster._margin;

  ui.TextDirection get _direction =>
      document.rightToLeft ? ui.TextDirection.rtl : ui.TextDirection.ltr;

  double _size(SlipEmphasis emphasis) =>
      switch (emphasis) {
        // Sized in dots at 203dpi: 22 dots is about 2.7mm of cap height, which
        // is what a receipt has been printed at since receipts existed.
        SlipEmphasis.title => 34.0,
        SlipEmphasis.strong => 30.0,
        SlipEmphasis.body => 22.0,
        SlipEmphasis.small => 18.0,
      } *
      scale;

  ui.FontWeight _weight(SlipEmphasis emphasis) => switch (emphasis) {
    SlipEmphasis.title || SlipEmphasis.strong => ui.FontWeight.w800,
    SlipEmphasis.body || SlipEmphasis.small => ui.FontWeight.w400,
  };

  ui.Paragraph _paragraph(
    String text, {
    required double width,
    required SlipEmphasis emphasis,
    ui.TextAlign align = ui.TextAlign.left,
    ui.TextDirection? direction,
    bool struck = false,
    int? maxLines,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: align,
              textDirection: direction ?? _direction,
              maxLines: maxLines,
              ellipsis: maxLines == null ? null : '…',
              fontSize: _size(emphasis),
              fontWeight: _weight(emphasis),
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: _black,
              fontSize: _size(emphasis),
              fontWeight: _weight(emphasis),
              decoration: struck ? ui.TextDecoration.lineThrough : null,
              decorationColor: _black,
            ),
          )
          ..addText(text);

    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  /// The whole slip, painted white-on-black-ink at [widthDots] across.
  Future<ui.Image> paint() async {
    final placed = <_Placed>[];
    var y = 8.0 * scale;

    for (final block in document.blocks) {
      switch (block) {
        case SlipGap(:final dots):
          y += dots * scale;

        case SlipRule():
          y += 4 * scale;
          placed.add(_PlacedRule(y));
          y += 6 * scale;

        case SlipCentre(:final text, :final emphasis):
          final paragraph = _paragraph(
            text,
            width: _content,
            emphasis: emphasis,
            align: ui.TextAlign.center,
          );
          placed.add(
            _PlacedText(
              paragraph,
              ui.Offset(ReceiptRaster._margin.toDouble(), y),
            ),
          );
          y += paragraph.height + 2 * scale;

        case SlipStamp(:final text):
          final paragraph = _paragraph(
            text,
            width: _content - 12 * scale,
            emphasis: SlipEmphasis.strong,
            align: ui.TextAlign.center,
          );
          final height = paragraph.height + 10 * scale;
          placed.add(
            _PlacedBox(
              ui.Rect.fromLTWH(
                ReceiptRaster._margin.toDouble(),
                y,
                _content,
                height,
              ),
            ),
          );
          placed.add(
            _PlacedText(
              paragraph,
              ui.Offset(ReceiptRaster._margin + 6 * scale, y + 5 * scale),
            ),
          );
          y += height + 8 * scale;

        case SlipRow(:final label, :final amount, :final emphasis, :final struck):
          y += _row(placed, label, amount, emphasis, struck, y);

        case SlipQr(:final payload):
          final square = _qr(payload);
          placed.add(_PlacedQr(square, y));
          y += square.size + 4 * scale;
      }
    }

    // The tail the printer needs under the last line so the cut falls below the
    // text rather than through it. The feed before the cut adds more; this is
    // the part that belongs to the picture.
    y += 16 * scale;

    final height = y.ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, widthDots.toDouble(), height.toDouble()),
    );
    // Paper first. Without it every untouched pixel is transparent black, and
    // the whole receipt rasterises as one solid block of ink — which is a full
    // roll of black paper and a service call.
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, widthDots.toDouble(), height.toDouble()),
      ui.Paint()..color = _white,
    );

    final ink = ui.Paint()
      ..color = _black
      ..style = ui.PaintingStyle.fill
      // A head has two states, so nothing on this canvas is allowed to be grey
      // on purpose. Text antialiasing is thresholded in [ReceiptRaster.pack];
      // rules and QR modules must land on whole dots.
      ..isAntiAlias = false;

    for (final item in placed) {
      item.paint(canvas, ink, this);
    }

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(widthDots, height);
    } finally {
      picture.dispose();
    }
  }

  /// A label against a figure. Returns the height it used.
  double _row(
    List<_Placed> placed,
    String label,
    String amount,
    SlipEmphasis emphasis,
    bool struck,
    double y,
  ) {
    // The figure is measured at its natural width and pinned to the far edge;
    // the label gets what is left. Sharing the width evenly would wrap "Mixed
    // Grill Platter" while leaving half a line of blank paper beside the price.
    final measured = _paragraph(
      amount,
      width: _content,
      emphasis: emphasis,
      // Numbers are LTR and Latin on an Arabic slip too — the house rule, and
      // on a receipt also what lets somebody who does not read Arabic check
      // what they were charged.
      direction: ui.TextDirection.ltr,
      struck: struck,
    );
    final amountWidth = measured.maxIntrinsicWidth.ceilToDouble();

    final amountParagraph = _paragraph(
      amount,
      width: amountWidth,
      emphasis: emphasis,
      direction: ui.TextDirection.ltr,
      align: ui.TextAlign.left,
      struck: struck,
    );

    final gap = 8 * scale;
    final labelWidth = (_content - amountWidth - gap).clamp(1.0, _content);
    final labelParagraph = _paragraph(
      label,
      width: labelWidth,
      emphasis: emphasis,
      align: document.rightToLeft ? ui.TextAlign.right : ui.TextAlign.left,
      struck: struck,
      maxLines: 2,
    );

    const margin = ReceiptRaster._margin;
    final labelX = document.rightToLeft
        ? margin + amountWidth + gap
        : margin.toDouble();
    final amountX = document.rightToLeft
        ? margin.toDouble()
        : margin + _content - amountWidth;

    placed.add(_PlacedText(labelParagraph, ui.Offset(labelX, y)));
    placed.add(_PlacedText(amountParagraph, ui.Offset(amountX, y)));

    final height = labelParagraph.height > amountParagraph.height
        ? labelParagraph.height
        : amountParagraph.height;
    return height + 3 * scale;
  }

  /// The QR, in whole dots.
  ///
  /// The module size is floored to an integer number of dots for the same
  /// reason `ReceiptQr` floors it on screen: a module landing on a fraction of
  /// a dot is a module the head prints at half strength, and a scanner reads
  /// that as noise. Two dots minimum — one-dot modules do not survive a folded
  /// receipt.
  _QrSquare _qr(String payload) {
    final image = ReceiptQrCode.imageOf(payload);
    final modules = image.moduleCount;
    // A quiet zone of four modules, which the specification requires and which
    // is the usual reason a printed code will not scan.
    final available = _content - 8 * scale;
    final module = (available / (modules + 8)).floor().clamp(2, 12);
    final size = module * (modules + 8);

    return _QrSquare(image: image, module: module.toDouble(), size: size.toDouble());
  }
}

class _QrSquare {
  const _QrSquare({
    required this.image,
    required this.module,
    required this.size,
  });

  final QrImage image;
  final double module;
  final double size;
}

/// Something measured, waiting to be drawn.
///
/// Sealed, so the paint pass switches over it and the compiler finds the gap
/// when a fifth kind of block arrives — the same reason nothing in this
/// codebase switches over a string.
sealed class _Placed {
  const _Placed();

  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout);
}

class _PlacedText extends _Placed {
  const _PlacedText(this.paragraph, this.offset);

  final ui.Paragraph paragraph;
  final ui.Offset offset;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) =>
      canvas.drawParagraph(paragraph, offset);
}

/// The box around a stamp — REPRINT, REFUNDED.
class _PlacedBox extends _Placed {
  const _PlacedBox(this.rect);

  final ui.Rect rect;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) => canvas.drawRect(
    rect,
    ui.Paint()
      // Three dots of border, because the banner has to survive being
      // photographed and photocopied.
      ..color = _Layout._black
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3 * layout.scale
      ..isAntiAlias = false,
  );
}

class _PlacedRule extends _Placed {
  const _PlacedRule(this.y);

  final double y;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) {
    // Drawn rather than typed. `'-' * 42` is a row of glyphs whose printed
    // length depends on the font the machine happens to have; dashes drawn as
    // rectangles are the same width on every till.
    final dash = 6 * layout.scale;
    for (
      var x = ReceiptRaster._margin.toDouble();
      x < layout.widthDots - ReceiptRaster._margin;
      x += dash * 2
    ) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x, y, dash, (2 * layout.scale).ceilToDouble()),
        ink,
      );
    }
  }
}

class _PlacedQr extends _Placed {
  const _PlacedQr(this.square, this.y);

  final _QrSquare square;
  final double y;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) {
    final quiet = square.module * 4;
    final left = ReceiptRaster._margin + (layout._content - square.size) / 2;

    for (var x = 0; x < square.image.moduleCount; x++) {
      for (var y = 0; y < square.image.moduleCount; y++) {
        if (!square.image.isDark(y, x)) continue;
        canvas.drawRect(
          ui.Rect.fromLTWH(
            left + quiet + x * square.module,
            this.y + quiet + y * square.module,
            square.module,
            square.module,
          ),
          ink,
        );
      }
    }
  }
}
