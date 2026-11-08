import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'package:shared_module/core/ui/tokens.dart';

/// The Reports tab's three charts (plan 19 §2.3), drawn rather than imported.
///
/// **No chart package.** None is in `pubspec.yaml` and none is to be added.
/// The packages that exist draw rounded bars, hover tooltips and drop
/// shadows by default — three things this design forbids
/// (`07-design-system.md`) and three settings somebody would have to find and
/// turn off on every chart, forever. A line, a bar and a stacked bar are a
/// page of painting.
///
/// **Integers until the pixel.** Every value arrives as minor units, a count
/// or basis points. The only doubles here are positions on the screen, worked
/// out at the last step from those integers; no figure is ever held as one.
///
/// **Mirrored in Arabic, all three.** On an Arabic page time runs right to
/// left, as the text does, and a bar grows from the start edge. A canvas has
/// no direction of its own — its x runs left to right whatever the locale —
/// so each painter takes the page's and flips its own axis. Reading
/// `Directionality` in the widget and passing it down is what makes that one
/// decision rather than three.

/// The token colours a series takes, in order, cycling past the seventh.
///
/// Accent first, then ink: the two strongest marks in the palette for the
/// two largest shares. No tints — a pastel slice is a pastel tile by
/// another name.
List<Color> chartSeries(PosPalette pos) => [
  pos.accent,
  pos.ink,
  pos.ok,
  pos.warn,
  pos.chipText,
  pos.body,
  pos.muted,
];

/// The value range a trend is drawn over: always including zero, so a quiet
/// week is not stretched to fill the chart and read as a boom.
({int top, int bottom}) _trendRange(List<int?> values) {
  var top = 0;
  var bottom = 0;
  for (final value in values) {
    if (value == null) continue;
    if (value > top) top = value;
    if (value < bottom) bottom = value;
  }
  return (top: top, bottom: bottom);
}

/// Where each of [values] sits in a plot of [plot]'s size — the first date at
/// the start edge, which is the right in Arabic. Null where the value is.
List<Offset?> trendPoints(
  List<int?> values,
  Size plot,
  TextDirection direction,
) {
  final (:top, :bottom) = _trendRange(values);
  final span = top - bottom;
  double x(int i) {
    final along = values.length == 1
        ? plot.width / 2
        : plot.width * i / (values.length - 1);
    return direction == TextDirection.rtl ? plot.width - along : along;
  }

  double y(int value) =>
      span == 0 ? plot.height : plot.height * (top - value) / span;

  return [
    for (final (i, value) in values.indexed)
      value == null ? null : Offset(x(i), y(value)),
  ];
}

/// The line: one mark per business date, joined where both ends exist.
class TrendChart extends StatelessWidget {
  const TrendChart({required this.values, this.height = 180, super.key});

  /// One per date, in date order. See `trendValue`.
  final List<int?> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return CustomPaint(
      key: const Key('reports-trend-plot'),
      size: Size.fromHeight(height),
      painter: TrendPainter(
        values: values,
        direction: Directionality.of(context),
        line: pos.accent,
        grid: pos.line,
        baseline: pos.lineStrong,
      ),
    );
  }
}

class TrendPainter extends CustomPainter {
  const TrendPainter({
    required this.values,
    required this.direction,
    required this.line,
    required this.grid,
    required this.baseline,
  });

  final List<int?> values;
  final TextDirection direction;
  final Color line;
  final Color grid;
  final Color baseline;

  /// Inset so a mark on the edge is drawn whole rather than cut in half.
  static const _inset = 4.0;

  /// The points as painted into [size] — public so a test can hold the RTL
  /// claim to the geometry, not to a screenshot.
  List<Offset?> pointsIn(Size size) => [
    for (final point in trendPoints(
      values,
      Size(size.width - 2 * _inset, size.height - 2 * _inset),
      direction,
    ))
      point?.translate(_inset, _inset),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final (:top, :bottom) = _trendRange(values);
    final span = top - bottom;
    final plotHeight = size.height - 2 * _inset;
    final zero =
        _inset + (span == 0 ? plotHeight : plotHeight * top / span);

    final hairline = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas
      ..drawLine(Offset(0, _inset), Offset(size.width, _inset), hairline)
      ..drawLine(
        Offset(0, zero),
        Offset(size.width, zero),
        Paint()
          ..color = baseline
          ..strokeWidth = 1,
      );

    final points = pointsIn(size);
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < points.length; i++) {
      final (from, to) = (points[i - 1], points[i]);
      if (from != null && to != null) canvas.drawLine(from, to, stroke);
    }
    // Square marks: the design's corners are square, and so are its dots.
    final fill = Paint()..color = line;
    for (final point in points) {
      if (point == null) continue;
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 6, height: 6),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(TrendPainter old) =>
      !listEquals(old.values, values) ||
      old.direction != direction ||
      old.line != line ||
      old.grid != grid ||
      old.baseline != baseline;
}

/// Each share's span along a bar [width] wide, in order from the start edge.
///
/// Placed from the running total rather than share by share, so the last
/// span ends exactly at the far edge: shares that sum to 10,000 fill the bar
/// with no hairline of background left over from rounding each on its own.
List<(double, double)> shareSpans(
  List<int> basisPoints,
  double width,
  TextDirection direction,
) {
  var before = 0;
  final spans = <(double, double)>[];
  for (final share in basisPoints) {
    final start = width * before / 10000;
    before += share;
    final end = width * before / 10000;
    spans.add(
      direction == TextDirection.rtl
          ? (width - end, width - start)
          : (start, end),
    );
  }
  return spans;
}

/// A 100% stacked bar — the plan's replacement for the mockup's donut: square
/// like everything else here, and a legend beside it reads in Arabic, where a
/// ring of labels does not (plan 19 §2.3).
class ShareBar extends StatelessWidget {
  const ShareBar({
    required this.basisPoints,
    required this.colors,
    this.height = 20,
    super.key,
  });

  final List<int> basisPoints;
  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: const Key('reports-share-bar'),
    size: Size.fromHeight(height),
    painter: ShareBarPainter(
      basisPoints: basisPoints,
      colors: colors,
      direction: Directionality.of(context),
      outline: context.pos.lineStrong,
    ),
  );
}

class ShareBarPainter extends CustomPainter {
  const ShareBarPainter({
    required this.basisPoints,
    required this.colors,
    required this.direction,
    required this.outline,
  });

  final List<int> basisPoints;
  final List<Color> colors;
  final TextDirection direction;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, (start, end))
        in shareSpans(basisPoints, size.width, direction).indexed) {
      canvas.drawRect(
        Rect.fromLTRB(start, 0, end, size.height),
        Paint()..color = colors[i % colors.length],
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(ShareBarPainter old) =>
      !listEquals(old.basisPoints, basisPoints) ||
      !listEquals(old.colors, colors) ||
      old.direction != direction ||
      old.outline != outline;
}

/// How far along [width] a bar of [value] reaches, against the [longest].
double rankLength(int value, int longest, double width) =>
    longest <= 0 || value <= 0 ? 0 : width * value / longest;

/// One product's bar, from the start edge, against the top seller's.
class RankBar extends StatelessWidget {
  const RankBar({
    required this.value,
    required this.longest,
    this.height = 8,
    super.key,
  });

  final int value;
  final int longest;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.fromHeight(height),
    painter: RankBarPainter(
      value: value,
      longest: longest,
      direction: Directionality.of(context),
      fill: context.pos.accent,
      track: context.pos.line,
    ),
  );
}

class RankBarPainter extends CustomPainter {
  const RankBarPainter({
    required this.value,
    required this.longest,
    required this.direction,
    required this.fill,
    required this.track,
  });

  final int value;
  final int longest;
  final TextDirection direction;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final length = rankLength(value, longest, size.width);
    canvas.drawRect(
      direction == TextDirection.rtl
          ? Rect.fromLTRB(size.width - length, 0, size.width, size.height)
          : Rect.fromLTRB(0, 0, length, size.height),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(RankBarPainter old) =>
      old.value != value ||
      old.longest != longest ||
      old.direction != direction ||
      old.fill != fill ||
      old.track != track;
}
