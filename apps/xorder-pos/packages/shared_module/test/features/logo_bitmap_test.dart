import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/features/receipt/logo_bitmap.dart';

/// XORD-024: a logo made into black and white dots for a thermal head.
void main() {
  Uint8List solid(int r, int g, int b, int a, {int size = 16}) {
    final pixels = Uint8List(size * size * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
      pixels[i + 3] = a;
    }
    return pixels;
  }

  test('black stays black and white stays white', () {
    expect(
      LogoBitmap.inkCount(LogoBitmap.oneBit(solid(0, 0, 0, 255), 16, 16)),
      256,
    );
    expect(
      LogoBitmap.inkCount(LogoBitmap.oneBit(solid(255, 255, 255, 255), 16, 16)),
      0,
    );
  });

  test('a fully transparent logo is paper, whatever colour is under it', () {
    // Black under an alpha of zero: composited onto white it is nothing.
    expect(
      LogoBitmap.inkCount(LogoBitmap.oneBit(solid(0, 0, 0, 0), 16, 16)),
      0,
    );
  });

  test('a mid grey comes out about half ink, not all white or all black', () {
    final ink = LogoBitmap.inkCount(
      LogoBitmap.oneBit(solid(128, 128, 128, 255), 16, 16),
    );
    expect(ink, inInclusiveRange(100, 156));
  });

  test(
    'a light colour still prints, where a plain threshold would lose it',
    () {
      // Light yellow: luma about 230, which a 50% threshold turns into white.
      final ink = LogoBitmap.inkCount(
        LogoBitmap.oneBit(solid(255, 240, 150, 255, size: 32), 32, 32),
      );
      expect(ink, greaterThan(0));
      expect(ink, lessThan(32 * 32 ~/ 3));
    },
  );

  test('every pixel is opaque black or opaque white, and the size is kept', () {
    final input = solid(90, 160, 200, 200, size: 20);
    final out = LogoBitmap.oneBit(input, 20, 20);
    expect(out.length, input.length);
    for (var i = 0; i < out.length; i += 4) {
      expect(out[i] == 0 || out[i] == 255, isTrue);
      expect(out[i + 1], out[i]);
      expect(out[i + 2], out[i]);
      expect(out[i + 3], 255);
    }
  });

  test('a half-transparent black is lighter than an opaque one', () {
    final half = LogoBitmap.inkCount(
      LogoBitmap.oneBit(solid(0, 0, 0, 128), 16, 16),
    );
    expect(half, inInclusiveRange(100, 156));
  });
}
