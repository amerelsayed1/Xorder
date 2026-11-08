import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../domain/models/receipt_profile.dart';
import '../../domain/models/tender_method.dart';
import 'receipt_data.dart';
import 'receipt_document.dart';
import 'receipt_qr.dart';
import 'slip_style.dart';

/// A receipt is paper, and paper is white in a dark room too.
///
/// This renders a PRINTED artefact rather than a screen: white stock, black
/// impact ink. Theming it would put the dark theme's near-white ink on white
/// stock and hand the operator a blank preview of a receipt that will print
/// perfectly well.
const receiptPalette = PosPalette.light;

/// The slip itself, on screen.
///
/// **The same blocks the printer gets, at the same proportions.** This used to
/// be its own widget tree, sized by eye, beside a raster that was sized in
/// dots — and the preview showed a receipt the printer never produced. It now
/// builds the [ReceiptDocument] the raster prints and draws each block with the
/// raster's own `SlipMetrics`, scaled from dots to the width it has. What
/// differs is only what a screen can do and a head cannot: antialiasing, and
/// the table heading's shading, which paper renders as a dot screen.
///
/// Both paths hand this the same [ReceiptData], which holds no catalogue and
/// no tax configuration — so there is nothing here that *could* recompute a
/// total.
class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper({
    super.key,
    required this.data,
    required this.tenantName,
    required this.terminalCode,
    required this.cashierName,
    this.profile = const ReceiptProfile(branchId: 0),
    this.tenderMethods = TenderMethod.seeded,
    this.logo,
  });

  final ReceiptData data;

  /// The business's logo, or null for none (XORD-024). The caller decides
  /// whether this till prints it; see `receiptLogoProvider`.
  final Uint8List? logo;

  /// Who this branch is, as Management entered it.
  ///
  /// Defaults to a blank profile so a till that has never been set up still
  /// prints — it just prints less. Every line that reads this is conditional
  /// for exactly that reason.
  final ReceiptProfile profile;

  /// The tenant as the session knows it. Still here because it is what a till
  /// has before anybody opens Management, and [ReceiptProfile.tradeName] wins
  /// once somebody has.
  final String tenantName;
  final String terminalCode;
  final String cashierName;

  /// See `ReceiptDocument.of`.
  final List<TenderMethod> tenderMethods;

  /// Used only when the paper is given unbounded width, which no caller does.
  /// The receipt dialogs are 360 wide, and a preview that threw instead would
  /// take the dialog with it.
  static const _fallbackWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final document = ReceiptDocument.of(
      data,
      strings: context.strings,
      tenantName: tenantName,
      terminalCode: terminalCode,
      cashierName: cashierName,
      profile: profile,
      tenderMethods: tenderMethods,
      logo: logo,
    );

    return ColoredBox(
      color: receiptPalette.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _fallbackWidth;
          final slip = _Slip(
            document,
            width / SlipMetrics.paperDots,
            // What a Text here is really drawn with: the theme's default
            // style underneath ours, and the user's text scale. The amounts
            // are measured with the same, or the box is narrower than the
            // text and the currency code wraps under the figure.
            base: DefaultTextStyle.of(context).style,
            textScaler: MediaQuery.textScalerOf(context),
          );

          return Directionality(
            textDirection: document.rightToLeft
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: slip.d(SlipMetrics.paperEdge + SlipMetrics.margin),
                vertical: slip.d(SlipMetrics.paperEdge),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in document.blocks) slip.block(block),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One block at a time, at [scale] logical pixels to the dot.
///
/// Every size in here is a `SlipMetrics` value through [d] — no number is
/// chosen for the screen alone. A size typed here instead would be the first
/// step back to a preview that disagrees with the paper.
class _Slip {
  _Slip(
    this.document,
    this.scale, {
    this.base = const TextStyle(),
    this.textScaler = TextScaler.noScaling,
  });

  final ReceiptDocument document;
  final double scale;

  /// See where this is built.
  final TextStyle base;
  final TextScaler textScaler;

  Color get _ink => receiptPalette.ink;
  bool get _rtl => document.rightToLeft;
  TextAlign get _outer => _rtl ? TextAlign.left : TextAlign.right;

  double d(double dots) => dots * scale;

  /// How wide the slip's amounts are — the raster's `_amountWidth`, measured
  /// the same way. Each amount sits in a box this wide with its text ending at
  /// the right, so the decimal points of a stack of figures share one x, on an
  /// Arabic slip as on an English one (XORD-025).
  /// The price column: [SlipMetrics.priceColumn] dots, wider when a price on
  /// this slip needs it, as the raster does — a large figure is shown whole,
  /// not cut to an ellipsis. At most 45% of the paper.
  late final double _priceColumn = () {
    final reference = d(SlipMetrics.priceColumn);
    final cap = d(SlipMetrics.contentDots) * 0.45;
    var widest = 0.0;
    for (final block in document.blocks) {
      if (block is! SlipItem) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: block.price,
          style: base.merge(_style(SlipMetrics.bodySize, mono: true)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return (widest.ceilToDouble() + 1).clamp(
      reference,
      cap < reference ? reference : cap,
    );
  }();

  late final double _amountWidth = () {
    final cap = d(SlipMetrics.contentDots) * 2 / 3;
    var widest = 0.0;
    for (final block in document.blocks) {
      if (block is! SlipRow || !block.amount) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: block.value,
          style: base.merge(_style(SlipMetrics.bodySize, mono: true)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    // Rounded up a pixel: a box the width of the text to the last fraction
    // wraps it on the rounding.
    return (widest.ceilToDouble() + 1).clamp(0.0, cap);
  }();

  /// The raster's faces and weights: 600 for mono, 700 for the Arabic face.
  TextStyle _style(
    double dots, {
    bool mono = false,
    bool bold = false,
    bool struck = false,
  }) {
    final base = mono
        ? PosText.mono(
            color: _ink,
            size: d(dots),
            weight: bold ? FontWeight.w600 : FontWeight.w400,
          )
        : PosText.ui(
            color: _ink,
            size: d(dots),
            weight: bold ? FontWeight.w700 : FontWeight.w400,
          );
    return struck
        ? base.copyWith(
            decoration: TextDecoration.lineThrough,
            decorationColor: _ink,
          )
        : base;
  }

  Widget _ltr(Widget child) =>
      Directionality(textDirection: TextDirection.ltr, child: child);

  Widget block(SlipBlock block) => switch (block) {
    SlipGap(:final dots) => SizedBox(height: d(dots.toDouble())),
    SlipRule(:final weight) => _rule(weight),
    SlipCentre() => _centre(block),
    SlipStamp(:final text) => _stamp(text),
    SlipLogo(:final bytes) => _logo(bytes),
    SlipRow() => _row(block),
    SlipItemsHeader() => _itemsHeader(block),
    SlipItem() => _item(block),
    SlipGrandTotal() => _grandTotal(block),
    SlipQr(:final payload) => _qr(payload),
  };

  Widget _rule(SlipRuleWeight weight) => Padding(
    padding: EdgeInsets.only(
      top: d(SlipMetrics.ruleAbove),
      bottom: d(SlipMetrics.ruleBelow),
    ),
    child: SizedBox(
      height: d(SlipMetrics.ruleThickness(weight)),
      child: weight == SlipRuleWeight.dashed
          ? CustomPaint(
              painter: _Dashes(
                dash: d(SlipMetrics.dash),
                gap: d(SlipMetrics.dashGap),
                colour: _ink,
              ),
            )
          : ColoredBox(color: _ink),
    ),
  );

  Widget _centre(SlipCentre block) {
    Widget text = Text(
      block.text,
      textAlign: TextAlign.center,
      style: _style(
        SlipMetrics.centreSize(block.emphasis),
        mono: block.numeric,
        bold: SlipMetrics.centreBold(block.emphasis),
      ),
    );
    if (block.numeric) text = _ltr(text);

    final glyph = block.glyph;
    return Padding(
      padding: EdgeInsets.only(bottom: d(SlipMetrics.lineGap)),
      child: glyph == null
          ? text
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _glyph(glyph, d(SlipMetrics.glyphSize)),
                SizedBox(width: d(SlipMetrics.glyphGap)),
                Flexible(child: text),
              ],
            ),
    );
  }

  /// The business's logo. In greyscale and un-dithered: a screen can show
  /// the picture, but the one-bit conversion the printer gets is a pixel pass
  /// this synchronous widget does not run. The paper is the reference; this is
  /// the same box in the same place. A logo that will not decode is left out,
  /// as it is on paper.
  Widget _logo(Uint8List bytes) => Padding(
    padding: EdgeInsets.only(bottom: d(SlipMetrics.logoAfter)),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: d(SlipMetrics.contentDots),
          maxHeight: d(SlipMetrics.logoMaxHeight),
        ),
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.299, 0.587, 0.114, 0, 0, //
            0.299, 0.587, 0.114, 0, 0,
            0.299, 0.587, 0.114, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: Image.memory(
            bytes,
            key: const Key('receipt-logo'),
            // One logo pixel is one dot of paper, which is `scale` pixels on
            // this screen: so a small logo previews as small as it prints, and
            // a large one is held to the box by `fit` and the constraints.
            scale: 1 / scale,
            // Never decoded larger than the box can show, whatever the upload.
            cacheWidth: (d(SlipMetrics.contentDots) * 2).ceil(),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );

  /// A banner across the top of the slip. Boxed and centred, because it has to
  /// survive being photographed, faxed and photocopied.
  Widget _stamp(String text) => Container(
    margin: EdgeInsets.only(bottom: d(SlipMetrics.stampAfter)),
    padding: EdgeInsets.symmetric(
      vertical: d(SlipMetrics.stampPad),
      horizontal: d(SlipMetrics.stampInset),
    ),
    decoration: BoxDecoration(
      border: Border.all(color: _ink, width: d(SlipMetrics.stampBorder)),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: _style(SlipMetrics.stampSize, mono: true, bold: true),
    ),
  );

  Widget _row(SlipRow row) {
    // Nothing is cut: a long name wraps (the raster does the same). The label
    // and the value share a baseline, so a quieter label does not float above
    // the figure beside it.
    Widget value = Text(
      row.value,
      textAlign: row.amount ? TextAlign.right : _outer,
      style: _style(
        SlipMetrics.bodySize,
        mono: row.numeric,
        struck: row.struck,
      ),
    );
    if (row.amount) value = SizedBox(width: _amountWidth, child: value);
    if (row.numeric) value = _ltr(value);

    return Padding(
      padding: EdgeInsets.only(bottom: d(SlipMetrics.rowGap)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              row.label,
              style: _style(
                row.secondary
                    ? SlipMetrics.bodySecondary
                    : SlipMetrics.bodySize,
                struck: row.struck,
              ),
            ),
          ),
          SizedBox(width: d(SlipMetrics.columnGap)),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: d(SlipMetrics.contentDots) * 2 / 3,
            ),
            child: value,
          ),
        ],
      ),
    );
  }

  /// Name, quantity, price — in that order from the side the slip reads from,
  /// so an Arabic slip mirrors the whole table rather than only its words.
  Widget _columns(Widget name, Widget quantity, Widget price) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: name),
      SizedBox(width: d(SlipMetrics.columnGap)),
      SizedBox(width: d(SlipMetrics.qtyColumn), child: quantity),
      SizedBox(width: d(SlipMetrics.columnGap)),
      SizedBox(width: _priceColumn, child: price),
    ],
  );

  Widget _itemsHeader(SlipItemsHeader header) {
    final style = _style(SlipMetrics.headerSize, bold: true);
    return Padding(
      padding: EdgeInsets.only(bottom: d(SlipMetrics.rowGap)),
      child: ColoredBox(
        color: receiptPalette.chipBg,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: d(SlipMetrics.headerPad)),
          child: _columns(
            Text(header.item, maxLines: 1, style: style),
            Text(
              header.quantity,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: style,
            ),
            Text(
              header.price,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: style,
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(SlipItem item) {
    final figure = _style(
      SlipMetrics.bodySize,
      mono: true,
      struck: item.struck,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: d(SlipMetrics.itemGap)),
      child: _columns(
        // The whole name, over as many lines as it takes.
        Text(
          item.name,
          style: _style(SlipMetrics.bodySize, struck: item.struck),
        ),
        _ltr(Text(item.quantity, textAlign: TextAlign.center, style: figure)),
        _ltr(
          Text(
            item.price,
            textAlign: TextAlign.right,
            maxLines: 1,
            style: figure,
          ),
        ),
      ),
    );
  }

  Widget _grandTotal(SlipGrandTotal total) => Padding(
    padding: EdgeInsets.only(bottom: d(SlipMetrics.rowGap)),
    child: Row(
      children: [
        Expanded(
          child: Text(
            total.label,
            style: _style(SlipMetrics.totalLabelSize, bold: true),
          ),
        ),
        SizedBox(width: d(SlipMetrics.columnGap)),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: d(SlipMetrics.contentDots) * 3 / 4,
          ),
          child: _ltr(
            Column(
              mainAxisSize: MainAxisSize.min,
              // The code ends where the figure ends, not under its middle.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  total.amount,
                  // Ending at the box's edge, where the code under it ends: a
                  // text box a little wider than its glyphs would otherwise
                  // leave the figure short of it.
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: _style(
                    SlipMetrics.totalAmountSize,
                    mono: true,
                    bold: true,
                  ),
                ),
                Text(
                  total.currency,
                  style: _style(SlipMetrics.currencySize, mono: true),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// The square at the paper's size, quiet zone included — the preview used
  /// to draw it at a fixed 132px while the paper printed it the full width of
  /// the roll.
  Widget _qr(String payload) {
    final modules = ReceiptQrCode.imageOf(payload).moduleCount;
    final module = SlipMetrics.qrModule(
      modules,
      SlipMetrics.contentDots,
    ).toDouble();
    return Padding(
      padding: EdgeInsets.only(bottom: d(SlipMetrics.rowGap)),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(d(module * 4)),
          child: ReceiptQr(payload: payload, size: d(module * modules)),
        ),
      ),
    );
  }

  Widget _glyph(SlipGlyph glyph, double side) => SizedBox.square(
    dimension: side,
    child: CustomPaint(painter: _GlyphPainter(glyph, _ink)),
  );
}

class _Dashes extends CustomPainter {
  const _Dashes({required this.dash, required this.gap, required this.colour});

  final double dash;
  final double gap;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = colour;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      final right = x + dash < size.width ? x + dash : size.width;
      canvas.drawRect(Rect.fromLTRB(x, 0, right, size.height), ink);
    }
  }

  @override
  bool shouldRepaint(_Dashes old) =>
      old.dash != dash || old.gap != gap || old.colour != colour;
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.colour);

  final SlipGlyph glyph;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) => paintSlipGlyph(
    canvas,
    glyph,
    Offset.zero & size,
    Paint()..color = colour,
  );

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.colour != colour;
}
