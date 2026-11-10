import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr/qr.dart';

import '../../core/config/printer_config.dart';
import '../../core/ui/tokens.dart' show PosFonts;
import 'logo_bitmap.dart';
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
/// that is right on the printer we tested and wrong on the one the business
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

  /// How wide the slip's amounts are, as one number.
  ///
  /// Every amount row is drawn in a box this wide and its text is right-aligned
  /// inside it, so the decimal points of a stack of figures share one x. A
  /// figure measured on its own and pinned to the edge, as these used to be,
  /// lines up its *first* digit on an Arabic slip, where the edge is the left.
  late final double _amountWidth = () {
    final cap = _content * 2 / 3;
    var widest = 0.0;
    for (final block in document.blocks) {
      if (block is! SlipRow || !block.amount) continue;
      final width = _natural(
        _text(
          block.value,
          size: SlipMetrics.bodySize,
          width: cap,
          mono: true,
          ltr: true,
        ),
      );
      if (width > widest) widest = width;
    }
    return widest.clamp(0.0, cap);
  }();

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
    try {
      return await _paint(placed);
    } finally {
      // Wherever it stopped: a logo decoded before a later block threw is still
      // a picture held by the engine.
      for (final item in placed) {
        if (item is _PlacedLogo) item.image.dispose();
      }
    }
  }

  Future<ui.Image> _paint(List<_Placed> placed) async {
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
        case SlipLogo(:final bytes):
          y = await _logo(placed, bytes, y);
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

  /// The business's logo, centred, as black and white dots (XORD-024).
  ///
  /// **It cannot fail the slip.** A logo that will not decode, has no size, or
  /// anything else that throws here is skipped and the slip prints as it would
  /// without one: nothing in its place, and no XOrder mark either.
  ///
  /// Sized to fit the content width and [SlipMetrics.logoMaxHeight] and never
  /// enlarged past its own pixels, decoded at that size so a 4000-pixel upload
  /// is not dithered at 4000 pixels, then turned into pure black and white by
  /// [LogoBitmap] so the packer's plain threshold leaves it as it is.
  Future<double> _logo(List<_Placed> placed, Uint8List bytes, double y) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? sized;
    ui.Image? scaled;
    try {
      // The size from the file's header: a 4000-pixel upload is not decoded in
      // full just to find out how big it is.
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final naturalWidth = descriptor.width;
      final naturalHeight = descriptor.height;
      if (naturalWidth < 1 || naturalHeight < 1) return y;

      final room = _d(SlipMetrics.logoMaxHeight);
      var ratio = _content / naturalWidth;
      if (room / naturalHeight < ratio) ratio = room / naturalHeight;
      if (ratio > 1) ratio = 1;
      final width = (naturalWidth * ratio).floor().clamp(1, naturalWidth);
      final height = (naturalHeight * ratio).floor().clamp(1, naturalHeight);

      sized = await descriptor.instantiateCodec(
        targetWidth: width,
        targetHeight: height,
      );
      scaled = (await sized.getNextFrame()).image;
      final pixels = await scaled.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (pixels == null) return y;

      final dots = LogoBitmap.oneBit(
        pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
        scaled.width,
        scaled.height,
      );
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        dots,
        scaled.width,
        scaled.height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      final image = await done.future;

      final x = (_left + (_content - image.width) / 2).floorToDouble();
      final top = y.ceilToDouble();
      placed.add(_PlacedLogo(image, ui.Offset(x, top)));
      return top + image.height + _d(SlipMetrics.logoAfter);
    } on Object {
      return y;
    } finally {
      sized?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      scaled?.dispose();
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
      _text(
        block.text,
        size: size,
        width: room,
        mono: block.numeric,
        bold: bold,
      ),
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
      _PlacedText(
        paragraph,
        ui.Offset(textX, y + (height - paragraph.height) / 2),
      ),
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
  ///
  /// **Nothing is cut.** A long cashier name, tender name or label wraps onto
  /// as many lines as it needs; this used to stop at two and end in an
  /// ellipsis, which on a receipt is a figure or a name that is not there.
  /// The label and the value sit on one baseline, so a quieter label
  /// ([SlipRow.secondary]) does not float above the figure beside it.
  double _row(List<_Placed> placed, SlipRow row, double y) {
    // The value is measured at its natural width and pinned to the far edge;
    // the label gets what is left. Sharing the width evenly would wrap a long
    // label while leaving half a line of blank paper beside the figure. Capped
    // at two thirds so a long cashier name cannot push its label off the slip.
    const size = SlipMetrics.bodySize;
    final labelSize = row.secondary ? SlipMetrics.bodySecondary : size;
    final cap = _content * 2 / 3;
    final gap = _d(SlipMetrics.columnGap);

    final valueWidth = row.amount
        ? _amountWidth
        : _natural(
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
      // An amount ends at the right of its box in either language, so decimals
      // line up; anything else keeps the slip's own outer edge.
      align: row.amount ? ui.TextAlign.right : _outer,
    );

    final labelWidth = _content - valueWidth - gap;
    final label = _text(
      row.label,
      size: labelSize,
      width: labelWidth,
      struck: row.struck,
    );

    final labelX = _rtl ? _left + valueWidth + gap : _left;
    final valueX = _rtl ? _left : _left + _content - valueWidth;

    // One baseline: the later of the two first baselines, so neither moves up.
    final baseline = _max(label.alphabeticBaseline, value.alphabeticBaseline);
    final labelY = y + baseline - label.alphabeticBaseline;
    final valueY = y + baseline - value.alphabeticBaseline;
    placed.add(_PlacedText(label, ui.Offset(labelX, labelY)));
    placed.add(_PlacedText(value, ui.Offset(valueX, valueY)));

    final bottom = _max(labelY + label.height, valueY + value.height);
    return bottom + _d(SlipMetrics.rowGap);
  }

  /// The price column: [SlipMetrics.priceColumn] dots, wider when a price on
  /// this slip needs it, so a large figure is printed whole and never cut to
  /// an ellipsis. At most 45% of the paper; names keep the rest.
  late final double _priceColumn = () {
    final reference = _d(SlipMetrics.priceColumn);
    final cap = _content * 0.45;
    var widest = 0.0;
    for (final block in document.blocks) {
      if (block is! SlipItem) continue;
      final width = _natural(
        _text(
          block.price,
          size: SlipMetrics.bodySize,
          width: _content,
          mono: true,
          ltr: true,
        ),
      );
      if (width > widest) widest = width;
    }
    return widest.clamp(reference, cap < reference ? reference : cap);
  }();

  _Columns _columns() {
    final gap = _d(SlipMetrics.columnGap);
    final qty = _d(SlipMetrics.qtyColumn);
    final price = _priceColumn;
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
      // Over the end of the figures, which are right-aligned in both languages.
      align: ui.TextAlign.right,
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

    // The whole name, over as many lines as it takes (owner's brief, 26 Oct
    // 2026): it stopped at two with an ellipsis, so a long dish was a different
    // dish on the paper. The quantity and price stay in their own columns.
    final name = _text(
      item.name,
      size: size,
      width: columns.name,
      struck: item.struck,
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
      align: ui.TextAlign.right,
      maxLines: 1,
    );

    placed.add(_PlacedText(name, ui.Offset(columns.nameX, y)));
    placed.add(_PlacedText(qty, ui.Offset(columns.qtyX, y)));
    placed.add(_PlacedText(price, ui.Offset(columns.priceX, y)));
    final height = _max(_max(name.height, qty.height), price.height);
    return y + height + _d(SlipMetrics.itemGap);
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
      // Under the end of the figure, where the other amounts' codes end.
      align: ui.TextAlign.right,
      maxLines: 1,
    );
    final figure = amount.height + currency.height;

    final label = _text(
      total.label,
      size: SlipMetrics.totalLabelSize,
      width: _content - amountWidth - gap,
      bold: true,
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

/// The logo, already black and white dots, drawn 1:1 at whole-dot coordinates
/// so nothing resamples it back to grey.
class _PlacedLogo extends _Placed {
  const _PlacedLogo(this.image, this.at);

  final ui.Image image;
  final ui.Offset at;

  @override
  void paint(ui.Canvas canvas, ui.Paint ink, _Layout layout) =>
      canvas.drawImage(
        image,
        at,
        ui.Paint()
          ..filterQuality = ui.FilterQuality.none
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
