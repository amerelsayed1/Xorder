import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr/qr.dart';

import '../../core/config/printer_config.dart';
import '../../core/ui/tokens.dart' show PosFonts;
import 'receipt_document.dart';
import 'receipt_qr.dart';
import 'slip_style.dart';

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
/// runs in `flutter test`. What keeps it the same slip as the preview is that
/// both walk the same blocks with the same `SlipMetrics`.
abstract final class ReceiptRaster {
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
    final image = await paint(document, widthDots: widthDots);
    try {
      return await pack(image);
    } finally {
      image.dispose();
    }
  }

  /// The slip before it is thresholded to one bit — what [render] packs.
  ///
  /// Exposed so a picture of the slip can be taken without a printer.
  /// Everything on it is already black or white; the only grey is the
  /// antialiased edge of a glyph, which [pack] decides.
  static Future<ui.Image> paint(
    ReceiptDocument document, {
    int widthDots = PrinterConfig.width80mm,
  }) => _Layout(document, widthDots).paint();

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

/// The three columns of the items table, in dots from the paper's left edge.
typedef _Columns = ({
  double name,
  double qty,
  double price,
  double nameX,
  double qtyX,
  double priceX,
});

/// Lays the blocks out once, then paints them.
///
/// Two passes because [ui.Picture.toImage] needs the height up front, and the
/// height is the sum of paragraphs that have to be laid out to be measured.
/// Keeping the laid-out paragraphs between the passes avoids doing the
/// expensive half twice.
class _Layout {
  _Layout(this.document, this.widthDots)
    : scale = widthDots / SlipMetrics.printableDots;

  final ReceiptDocument document;
  final int widthDots;
  final double scale;

  static const _black = ui.Color(0xFF000000);
  static const _white = ui.Color(0xFFFFFFFF);

  /// The margin is **not** scaled: it is the part of a head that drifts, and
  /// that is a number of physical dots whatever the roll.
  double get _left => SlipMetrics.margin;
  double get _content => widthDots - 2 * SlipMetrics.margin;

  bool get _rtl => document.rightToLeft;
  ui.TextDirection get _direction =>
      _rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr;

  /// The side a label starts from, and the side a figure is pinned to.
  ui.TextAlign get _inner => _rtl ? ui.TextAlign.right : ui.TextAlign.left;
  ui.TextAlign get _outer => _rtl ? ui.TextAlign.left : ui.TextAlign.right;

  double _d(double dots) => dots * scale;

  /// A paragraph in the house faces.
  ///
  /// The families are named because the raster used to name none, and a slip
  /// with no family is drawn in whatever the engine's default is on that
  /// machine — Segoe UI on one till, Helvetica on the next — while the preview
  /// beside it was in IBM Plex. Mono is 600 at its heaviest, the Arabic face
  /// 700, and a weight a face does not have is synthesised badly.
  ui.Paragraph _text(
    String text, {
    required double size,
    required double width,
    bool mono = false,
    bool bold = false,
    bool ltr = false,
    bool struck = false,
    ui.TextAlign? align,
    int? maxLines,
  }) {
    final family = mono ? PosFonts.mono : PosFonts.ui;
    final fallback = mono ? PosFonts.monoFallback : PosFonts.uiFallback;
    final weight = !bold
        ? ui.FontWeight.w400
        : (mono ? ui.FontWeight.w600 : ui.FontWeight.w700);
    final fontSize = _d(size);

    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: align ?? _inner,
              textDirection: ltr ? ui.TextDirection.ltr : _direction,
              maxLines: maxLines,
              ellipsis: maxLines == null ? null : '…',
              fontFamily: family,
              fontSize: fontSize,
              fontWeight: weight,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: _black,
              fontFamily: family,
              fontFamilyFallback: fallback,
              fontSize: fontSize,
              fontWeight: weight,
              decoration: struck ? ui.TextDecoration.lineThrough : null,
              decorationColor: _black,
            ),
          )
          ..addText(text);

    return builder.build()
      ..layout(ui.ParagraphConstraints(width: width < 1 ? 1 : width));
  }

  double _natural(ui.Paragraph paragraph) =>
      paragraph.maxIntrinsicWidth.ceilToDouble();

  static double _max(double a, double b) => a > b ? a : b;

  /// The whole slip, painted black ink on white at [widthDots] across.
  Future<ui.Image> paint() async {
    final placed = <_Placed>[];
    var y = _d(SlipMetrics.top);

    for (final block in document.blocks) {
      switch (block) {
        case SlipGap(:final dots):
          y += _d(dots.toDouble());
        case SlipRule(:final weight):
          y = _rule(placed, weight, y);
        case SlipCentre():
          y = _centre(placed, block, y);
        case SlipStamp(:final text):
          y = _stamp(placed, text, y);
        case SlipRow():
          y = _row(placed, block, y);
        case SlipItemsHeader():
          y = _itemsHeader(placed, block, y);
        case SlipItem():
          y = _item(placed, block, y);
        case SlipGrandTotal():
          y = _grandTotal(placed, block, y);
        case SlipQr(:final payload):
          final square = _qr(payload);
          placed.add(_PlacedQr(square, y));
          y += square.size + _d(SlipMetrics.rowGap);
        case SlipOrnament():
          y = _ornament(placed, y);
      }
    }

    // The tail the printer needs under the last line so the cut falls below the
    // text rather than through it. The feed before the cut adds more; this is
    // the part that belongs to the picture.
    y += _d(SlipMetrics.tail);

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
      // rules, glyphs and QR modules must land on whole dots.
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

  double _rule(List<_Placed> placed, SlipRuleWeight weight, double y) {
    final top = (y + _d(SlipMetrics.ruleAbove)).roundToDouble();
    final thickness = _d(SlipMetrics.ruleThickness(weight)).ceilToDouble();
    final band = ui.Rect.fromLTWH(_left, top, _content, thickness);
    placed.add(
      weight == SlipRuleWeight.dashed ? _PlacedDashes(band) : _PlacedFill(band),
    );
    return top + thickness + _d(SlipMetrics.ruleBelow);
  }

  double _centre(List<_Placed> placed, SlipCentre block, double y) {
    final size = SlipMetrics.centreSize(block.emphasis);
    final bold = SlipMetrics.centreBold(block.emphasis);
    final gap = _d(SlipMetrics.lineGap);

    final glyph = block.glyph;
    if (glyph == null) {
      final paragraph = _text(
        block.text,
        size: size,
        width: _content,
        mono: block.numeric,
        bold: bold,
        ltr: block.numeric,
        align: ui.TextAlign.center,
      );
      placed.add(_PlacedText(paragraph, ui.Offset(_left, y)));
      return y + paragraph.height + gap;
    }

    // Glyph and text centred together as one unit, the glyph on the side the
    // slip reads from — so on an Arabic slip it leads from the right.
    final side = _d(SlipMetrics.glyphSize).roundToDouble();
    final spacing = _d(SlipMetrics.glyphGap);
    final room = _content - side - spacing;
    final width = _natural(
      _text(block.text, size: size, width: room, mono: block.numeric, bold: bold),
    ).clamp(1.0, room);
    final paragraph = _text(
      block.text,
      size: size,
      width: width,
      mono: block.numeric,
      bold: bold,
      ltr: block.numeric,
      align: ui.TextAlign.center,
    );

    final start = _left + (_content - side - spacing - width) / 2;
    final textX = _rtl ? start : start + side + spacing;
    final glyphX = _rtl ? start + width + spacing : start;
    final height = _max(paragraph.height, side);

    placed.add(
      _PlacedText(paragraph, ui.Offset(textX, y + (height - paragraph.height) / 2)),
    );
    placed.add(
      _PlacedGlyph(
        glyph,
        ui.Rect.fromLTWH(
          glyphX.roundToDouble(),
          (y + (height - side) / 2).roundToDouble(),
          side,
          side,
        ),
      ),
    );
    return y + height + gap;
  }

  double _stamp(List<_Placed> placed, String text, double y) {
    final inset = _d(SlipMetrics.stampInset);
    final pad = _d(SlipMetrics.stampPad);
    final paragraph = _text(
      text,
      size: SlipMetrics.stampSize,
      width: _content - 2 * inset,
      mono: true,
      bold: true,
      align: ui.TextAlign.center,
    );
    final height = paragraph.height + 2 * pad;
    placed.add(_PlacedBox(ui.Rect.fromLTWH(_left, y, _content, height)));
    placed.add(_PlacedText(paragraph, ui.Offset(_left + inset, y + pad)));
    return y + height + _d(SlipMetrics.stampAfter);
  }

  /// A label against a value. Returns where the next block starts.
  double _row(List<_Placed> placed, SlipRow row, double y) {
    // The value is measured at its natural width and pinned to the far edge;
    // the label gets what is left. Sharing the width evenly would wrap a long
    // label while leaving half a line of blank paper beside the figure. Capped
    // at two thirds so a long cashier name cannot push its label off the slip.
    const size = SlipMetrics.bodySize;
    final cap = _content * 2 / 3;
    final gap = _d(SlipMetrics.columnGap);

    final valueWidth = _natural(
      _text(
        row.value,
        size: size,
        width: cap,
        mono: row.numeric,
        ltr: row.numeric,
        struck: row.struck,
      ),
    ).clamp(0.0, cap);
    final value = _text(
      row.value,
      size: size,
      width: valueWidth,
      mono: row.numeric,
      // Numbers are LTR and Latin on an Arabic slip too — the house rule, and
      // on a receipt also what lets somebody who does not read Arabic check
      // what they were charged.
      ltr: row.numeric,
      struck: row.struck,
      align: _outer,
      maxLines: 2,
    );

    final labelWidth = _content - valueWidth - gap;
    final label = _text(
      row.label,
      size: size,
      width: labelWidth,
      struck: row.struck,
      maxLines: 2,
    );

    final labelX = _rtl ? _left + valueWidth + gap : _left;
    final valueX = _rtl ? _left : _left + _content - valueWidth;
    placed.add(_PlacedText(label, ui.Offset(labelX, y)));
    placed.add(_PlacedText(value, ui.Offset(valueX, y)));

    return y + _max(label.height, value.height) + _d(SlipMetrics.rowGap);
  }

  _Columns _columns() {
    final gap = _d(SlipMetrics.columnGap);
    final qty = _d(SlipMetrics.qtyColumn);
    final price = _d(SlipMetrics.priceColumn);
    final name = _content - qty - price - 2 * gap;
    return _rtl
        ? (
            name: name,
            qty: qty,
            price: price,
            priceX: _left,
            qtyX: _left + price + gap,
            nameX: _left + price + gap + qty + gap,
          )
        : (
            name: name,
            qty: qty,
            price: price,
            nameX: _left,
            qtyX: _left + name + gap,
            priceX: _left + name + gap + qty + gap,
          );
  }

  double _itemsHeader(List<_Placed> placed, SlipItemsHeader header, double y) {
    final columns = _columns();
    const size = SlipMetrics.headerSize;
    final pad = _d(SlipMetrics.headerPad);

    final name = _text(
      header.item,
      size: size,
      width: columns.name,
      bold: true,
      maxLines: 1,
    );
    final qty = _text(
      header.quantity,
      size: size,
      width: columns.qty,
      bold: true,
      align: ui.TextAlign.center,
      maxLines: 1,
    );
    final price = _text(
      header.price,
      size: size,
      width: columns.price,
      bold: true,
      align: _outer,
      maxLines: 1,
    );

    final inner = _max(_max(name.height, qty.height), price.height);
    final band = ui.Rect.fromLTWH(_left, y, _content, inner + 2 * pad);
    placed.add(_PlacedShade(band));
    placed.add(_PlacedText(name, ui.Offset(columns.nameX, y + pad)));
    placed.add(_PlacedText(qty, ui.Offset(columns.qtyX, y + pad)));
    placed.add(_PlacedText(price, ui.Offset(columns.priceX, y + pad)));
    return y + band.height + _d(SlipMetrics.rowGap);
  }

  double _item(List<_Placed> placed, SlipItem item, double y) {
    final columns = _columns();
    const size = SlipMetrics.bodySize;

    final name = _text(
      item.name,
      size: size,
      width: columns.name,
      struck: item.struck,
      maxLines: 2,
    );
    final qty = _text(
      item.quantity,
      size: size,
      width: columns.qty,
      mono: true,
      ltr: true,
      struck: item.struck,
      align: ui.TextAlign.center,
    );
    final price = _text(
      item.price,
      size: size,
      width: columns.price,
      mono: true,
      ltr: true,
      struck: item.struck,
      align: _outer,
      maxLines: 1,
    );

    placed.add(_PlacedText(name, ui.Offset(columns.nameX, y)));
    placed.add(_PlacedText(qty, ui.Offset(columns.qtyX, y)));
    placed.add(_PlacedText(price, ui.Offset(columns.priceX, y)));
    final height = _max(_max(name.height, qty.height), price.height);
    return y + height + _d(SlipMetrics.rowGap);
  }

  double _grandTotal(List<_Placed> placed, SlipGrandTotal total, double y) {
    final gap = _d(SlipMetrics.columnGap);
    final cap = _content * 3 / 4;

    final amountWidth = _natural(
      _text(
        total.amount,
        size: SlipMetrics.totalAmountSize,
        width: cap,
        mono: true,
        bold: true,
        ltr: true,
      ),
    ).clamp(1.0, cap);
    final amount = _text(
      total.amount,
      size: SlipMetrics.totalAmountSize,
      width: amountWidth,
      mono: true,
      bold: true,
      ltr: true,
      align: ui.TextAlign.center,
      maxLines: 1,
    );
    final currency = _text(
      total.currency,
      size: SlipMetrics.currencySize,
      width: amountWidth,
      mono: true,
      ltr: true,
      align: ui.TextAlign.center,
      maxLines: 1,
    );
    final figure = amount.height + currency.height;

    final label = _text(
      total.label,
      size: SlipMetrics.totalLabelSize,
      width: _content - amountWidth - gap,
      bold: true,
      maxLines: 2,
    );

    final height = _max(figure, label.height);
    final amountX = _rtl ? _left : _left + _content - amountWidth;
    final labelX = _rtl ? _left + amountWidth + gap : _left;
    final figureY = y + (height - figure) / 2;

    placed.add(_PlacedText(amount, ui.Offset(amountX, figureY)));
    placed.add(
      _PlacedText(currency, ui.Offset(amountX, figureY + amount.height)),
    );
    placed.add(
      _PlacedText(label, ui.Offset(labelX, y + (height - label.height) / 2)),
    );
    return y + height + _d(SlipMetrics.rowGap);
  }

  double _ornament(List<_Placed> placed, double y) {
    final line = _d(SlipMetrics.ornamentLine);
    final gap = _d(SlipMetrics.ornamentGap);
    final heart = _d(SlipMetrics.ornamentHeart).roundToDouble();
    final thickness = _d(
      SlipMetrics.ruleThickness(SlipRuleWeight.solid),
    ).ceilToDouble();

    final start = (_left + (_content - 2 * line - 2 * gap - heart) / 2)
        .roundToDouble();
    final top = y.roundToDouble();
    final lineY = (top + (heart - thickness) / 2).roundToDouble();

    placed.add(_PlacedFill(ui.Rect.fromLTWH(start, lineY, line, thickness)));
    placed.add(
      _PlacedGlyph(
        SlipGlyph.heart,
        ui.Rect.fromLTWH(start + line + gap, top, heart, heart),
      ),
    );
    placed.add(
      _PlacedFill(
        ui.Rect.fromLTWH(start + line + 2 * gap + heart, lineY, line, thickness),
      ),
    );
    return top + heart + _d(SlipMetrics.lineGap);
  }

  /// The QR, in whole dots. See [SlipMetrics.qrModule].
  _QrSquare _qr(String payload) {
    final image = ReceiptQrCode.imageOf(payload);
    final module = SlipMetrics.qrModule(image.moduleCount, _content);
    // A quiet zone of four modules each side, which the specification
    // requires and which is the usual reason a printed code will not scan.
    final size = module * (image.moduleCount + 8);
    return _QrSquare(
      image: image,
      module: module.toDouble(),
      size: size.toDouble(),
    );
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
/// when another kind of mark arrives — the same reason nothing in this
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

/// A solid rule, or one arm of the ornament.
class _PlacedFill extends _Placed {
  const _PlacedFill(this.rect);

  final ui.Rect rect;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) =>
      canvas.drawRect(rect, ink);
}

class _PlacedDashes extends _Placed {
  const _PlacedDashes(this.band);

  final ui.Rect band;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) {
    // Drawn rather than typed. `'-' * 42` is a row of glyphs whose printed
    // length depends on the font the machine happens to have; dashes drawn as
    // rectangles are the same width on every till.
    final dash = SlipMetrics.dash * layout.scale;
    final step = dash + SlipMetrics.dashGap * layout.scale;
    for (var x = band.left; x < band.right; x += step) {
      final right = x + dash < band.right ? x + dash : band.right;
      canvas.drawRect(ui.Rect.fromLTRB(x, band.top, right, band.bottom), ink);
    }
  }
}

/// The shaded ground of the items table's heading.
///
/// **A thermal head has no grey.** The preview paints this band in a light
/// token; the same colour sent to paper thresholds to white in [ReceiptRaster.
/// pack] and the shading disappears. So the paper gets a screen instead — one
/// dot in eight, staggered — which reads as a light grey band and leaves the
/// bold heading on top of it legible. Solid black with white text was the
/// alternative, and on a cheap head that has been running all day a reversed
/// band is where the paper streaks first.
class _PlacedShade extends _Placed {
  const _PlacedShade(this.band);

  final ui.Rect band;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) {
    final top = band.top.ceil();
    final left = band.left.ceil();
    for (var y = top; y < band.bottom; y += 2) {
      final stagger = ((y - top) ~/ 2).isOdd ? 2 : 0;
      for (var x = left + stagger; x < band.right; x += 4) {
        canvas.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          ink,
        );
      }
    }
  }
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
      ..strokeWidth = SlipMetrics.stampBorder * layout.scale
      ..isAntiAlias = false,
  );
}

class _PlacedGlyph extends _Placed {
  const _PlacedGlyph(this.glyph, this.box);

  final SlipGlyph glyph;
  final ui.Rect box;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) =>
      paintSlipGlyph(canvas, glyph, box, ink);
}

class _PlacedQr extends _Placed {
  const _PlacedQr(this.square, this.at);

  final _QrSquare square;
  final double at;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) {
    final quiet = square.module * 4;
    // Floored so every module starts on a whole dot.
    final left = (SlipMetrics.margin + (layout._content - square.size) / 2)
        .floorToDouble();
    final top = at.floorToDouble();

    for (var x = 0; x < square.image.moduleCount; x++) {
      for (var y = 0; y < square.image.moduleCount; y++) {
        if (!square.image.isDark(y, x)) continue;
        canvas.drawRect(
          ui.Rect.fromLTWH(
            left + quiet + x * square.module,
            top + quiet + y * square.module,
            square.module,
            square.module,
          ),
          ink,
        );
      }
    }
  }
}
