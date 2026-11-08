/// A logo for a head that has two states (XORD-024).
///
/// The receipt is thresholded at 50% luminance when it is packed
/// (`ReceiptRaster.pack`), which is right for text and a QR code — they are
/// black or white already — and wrong for a logo. A light-coloured mark falls
/// entirely on the white side and prints as nothing; a photograph becomes
/// black blobs. So the logo is turned into black and white dots **before** it
/// is drawn, by error diffusion, and the threshold afterwards sees nothing but
/// pure black and pure white and leaves it alone. Text and QR are not touched.
///
/// Pure Dart on a pixel buffer, no `dart:ui`: it runs in a plain unit test.
library;

import 'dart:typed_data';

abstract final class LogoBitmap {
  /// [rgba] is [width] x [height] pixels, four bytes each, **straight** (not
  /// premultiplied) alpha. Returns a buffer of the same size and shape in which
  /// every pixel is opaque black or opaque white.
  ///
  /// A transparent pixel is paper, so it is composited onto white first;
  /// otherwise a logo with a transparent background would print its
  /// background (whatever colour sits under an alpha of zero) as a black box.
  static Uint8List oneBit(Uint8List rgba, int width, int height) {
    assert(rgba.length == width * height * 4, 'not a $width x $height RGBA');

    final out = Uint8List(rgba.length);
    // Floyd-Steinberg, one row of error ahead. Integer arithmetic throughout.
    var current = List<int>.filled(width + 2, 0);
    var next = List<int>.filled(width + 2, 0);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final r = rgba[offset];
        final g = rgba[offset + 1];
        final b = rgba[offset + 2];
        final a = rgba[offset + 3];

        // Rec. 601 luma, as the packer uses, then over white.
        final luma = (r * 299 + g * 587 + b * 114) ~/ 1000;
        final seen = (luma * a + 255 * (255 - a)) ~/ 255;

        final wanted = seen + current[x + 1];
        final ink = wanted < 128;
        final shown = ink ? 0 : 255;
        final error = wanted - shown;

        current[x + 2] += (error * 7) ~/ 16;
        next[x] += (error * 3) ~/ 16;
        next[x + 1] += (error * 5) ~/ 16;
        next[x + 2] += error ~/ 16;

        out[offset] = shown;
        out[offset + 1] = shown;
        out[offset + 2] = shown;
        out[offset + 3] = 255;
      }
      final done = current;
      current = next;
      next = done..fillRange(0, done.length, 0);
    }
    return out;
  }

  /// How many pixels of [rgba] (as [oneBit] returns it) are ink.
  static int inkCount(Uint8List rgba) {
    var count = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i] == 0) count++;
    }
    return count;
  }
}
