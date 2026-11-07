/// The business logo (XORD-021): the business's mark, kept on the till.
///
/// **Stored as the image itself, not as a link.** A link is gone the moment the
/// till is offline, and the whole point of an offline install is that nothing
/// it shows depends on a server it cannot reach. The bytes live in
/// `pos_businesses` in the branch database, so every till on the branch shares
/// one copy and a restart changes nothing.
///
/// **Inspected, not trusted.** Whatever arrives (a file the owner picked, or a
/// download the platform pointed at) passes through [BusinessLogoRules.inspect]
/// before a byte is stored: the content must really be the type it claims, fit
/// the size cap, and have dimensions a start screen can draw. The check reads
/// the file's own header rather than its name, because a file named `.png`
/// proves nothing.
library;

import 'dart:typed_data';

/// What the image really is, read from its first bytes.
enum LogoFormat {
  png('image/png'),
  jpeg('image/jpeg'),
  webp('image/webp');

  const LogoFormat(this.mime);

  final String mime;

  static LogoFormat? fromMime(String? mime) => switch (mime) {
    'image/png' => png,
    'image/jpeg' => jpeg,
    'image/webp' => webp,
    _ => null,
  };
}

/// Where the logo on this till came from.
enum LogoSource {
  /// Chosen in this till's own back office (an offline install).
  local('local'),

  /// Downloaded because the platform's bundle named it (a cloud till).
  platform('platform');

  const LogoSource(this.wire);

  final String wire;

  static LogoSource? fromWire(String? value) => switch (value) {
    'local' => local,
    'platform' => platform,
    _ => null,
  };
}

/// Why a file was turned away. One reason each, so the screen can say which.
enum LogoRefusal {
  empty,
  tooLarge,

  /// Not PNG or JPEG (or WebP, where the source allows it).
  unsupported,

  /// The header says it is an image the decoder could not read.
  unreadable,
  tooSmall,
  tooBig,
}

/// An image that passed [BusinessLogoRules.inspect].
class LogoImage {
  const LogoImage({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final LogoFormat format;
  final int width;
  final int height;

  String get mime => format.mime;
}

/// The answer of [BusinessLogoRules.inspect]: an image, or the reason not.
class LogoCheck {
  const LogoCheck.ok(LogoImage this.image) : refusal = null;
  const LogoCheck.refused(LogoRefusal this.refusal) : image = null;

  final LogoImage? image;
  final LogoRefusal? refusal;

  bool get accepted => image != null;
}

/// The logo as the till holds it.
class BusinessLogo {
  const BusinessLogo({
    required this.bytes,
    required this.mime,
    required this.source,
    this.updatedAt,
  });

  final Uint8List bytes;
  final String mime;
  final LogoSource source;
  final DateTime? updatedAt;
}

abstract final class BusinessLogoRules {
  /// What an owner may upload. Two megabytes is generous for a mark that is
  /// drawn at a few hundred pixels, and small enough that every till on the
  /// branch can read it with the rest of the business row without noticing.
  static const maxBytes = 2 * 1024 * 1024;

  /// What the platform may hand us. Its own upload cap is 4 MB, so the till
  /// accepts what the platform could legitimately have stored.
  static const maxPlatformBytes = 4 * 1024 * 1024;

  /// Below this a logo is a smudge on a start screen; above [maxSide] it is a
  /// photograph that every till would decode for no gain.
  static const minSide = 64;
  static const maxSide = 4096;

  /// Reads [bytes] and says whether they are a logo this till will keep.
  ///
  /// [fromPlatform] widens two things and nothing else: WebP is allowed (the
  /// platform re-encodes every upload to WebP), and so is the larger cap. An
  /// owner choosing a file is held to PNG or JPEG and [maxBytes].
  static LogoCheck inspect(Uint8List bytes, {bool fromPlatform = false}) {
    if (bytes.isEmpty) return const LogoCheck.refused(LogoRefusal.empty);
    if (bytes.length > (fromPlatform ? maxPlatformBytes : maxBytes)) {
      return const LogoCheck.refused(LogoRefusal.tooLarge);
    }

    final format = _sniff(bytes);
    if (format == null || (format == LogoFormat.webp && !fromPlatform)) {
      return const LogoCheck.refused(LogoRefusal.unsupported);
    }

    final size = switch (format) {
      LogoFormat.png => _pngSize(bytes),
      LogoFormat.jpeg => _jpegSize(bytes),
      LogoFormat.webp => _webpSize(bytes),
    };
    if (size == null) return const LogoCheck.refused(LogoRefusal.unreadable);

    final (width, height) = size;
    if (width < minSide || height < minSide) {
      return const LogoCheck.refused(LogoRefusal.tooSmall);
    }
    if (width > maxSide || height > maxSide) {
      return const LogoCheck.refused(LogoRefusal.tooBig);
    }
    return LogoCheck.ok(
      LogoImage(bytes: bytes, format: format, width: width, height: height),
    );
  }

  static LogoFormat? _sniff(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return LogoFormat.png;
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return LogoFormat.jpeg;
    }
    if (b.length >= 12 && _ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WEBP')) {
      return LogoFormat.webp;
    }
    return null;
  }

  static bool _ascii(Uint8List b, int at, String text) {
    if (b.length < at + text.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (b[at + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _be32(Uint8List b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static int _be16(Uint8List b, int at) => (b[at] << 8) | b[at + 1];

  static int _le24(Uint8List b, int at) =>
      b[at] | (b[at + 1] << 8) | (b[at + 2] << 16);

  /// IHDR is always the first chunk: 8 signature bytes, a 4-byte length, the
  /// tag, then width and height as big-endian 32-bit integers.
  static (int, int)? _pngSize(Uint8List b) {
    if (b.length < 24 || !_ascii(b, 12, 'IHDR')) return null;
    final w = _be32(b, 16);
    final h = _be32(b, 20);
    return w <= 0 || h <= 0 ? null : (w, h);
  }

  /// Walks the marker segments to the first start-of-frame, which carries the
  /// dimensions. Anything that runs off the end of the file is unreadable.
  static (int, int)? _jpegSize(Uint8List b) {
    var at = 2;
    while (at + 4 <= b.length) {
      if (b[at] != 0xFF) return null;
      final marker = b[at + 1];
      if (marker == 0xFF) {
        at++; // fill byte
        continue;
      }
      // Standalone markers carry no length.
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        at += 2;
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) return null; // end / scan: no frame
      final length = _be16(b, at + 2);
      if (length < 2) return null;
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) {
        if (at + 9 > b.length) return null;
        final h = _be16(b, at + 5);
        final w = _be16(b, at + 7);
        return w <= 0 || h <= 0 ? null : (w, h);
      }
      at += 2 + length;
    }
    return null;
  }

  /// The three WebP flavours keep their size in three different places.
  static (int, int)? _webpSize(Uint8List b) {
    if (b.length < 30) return null;
    if (_ascii(b, 12, 'VP8X')) {
      final w = _le24(b, 24) + 1;
      final h = _le24(b, 27) + 1;
      return (w, h);
    }
    if (_ascii(b, 12, 'VP8L')) {
      if (b[20] != 0x2F) return null;
      final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
    }
    if (_ascii(b, 12, 'VP8 ')) {
      // Frame tag (3 bytes), start code 9D 01 2A, then 14-bit sizes.
      if (b[23] != 0x9D || b[24] != 0x01 || b[25] != 0x2A) return null;
      final w = (b[26] | (b[27] << 8)) & 0x3FFF;
      final h = (b[28] | (b[29] << 8)) & 0x3FFF;
      return w <= 0 || h <= 0 ? null : (w, h);
    }
    return null;
  }
}
