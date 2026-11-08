import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/business_logo.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/domain/models/shift.dart';

/// XORD-021 — what a logo is allowed to be, decided from the file's own header.
///
/// The images here are headers and nothing else: the check reads dimensions and
/// type, never pixels, and a test that shipped real pictures would be testing
/// the encoder.
void main() {
  Uint8List png(int w, int h, {int pad = 0}) {
    final b = BytesBuilder();
    b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    b.add([0, 0, 0, 13]);
    b.add('IHDR'.codeUnits);
    b.add([w >> 24, w >> 16, w >> 8, w, h >> 24, h >> 16, h >> 8, h]);
    b.add([8, 6, 0, 0, 0]);
    b.add(List.filled(pad, 0));
    return b.toBytes();
  }

  Uint8List jpeg(int w, int h, {bool app0First = true, bool noFrame = false}) {
    final b = BytesBuilder();
    b.add([0xFF, 0xD8]);
    if (app0First) {
      b.add([0xFF, 0xE0, 0x00, 0x10]);
      b.add('JFIF'.codeUnits);
      b.add(List.filled(10, 0)); // 2 + 4 + 10 = the 0x10 the segment declares
    }
    if (noFrame) {
      b.add([0xFF, 0xDA, 0x00, 0x02]);
    } else {
      b.add([0xFF, 0xC0, 0x00, 0x11, 8, h >> 8, h & 255, w >> 8, w & 255]);
      b.add(List.filled(10, 0));
    }
    return b.toBytes();
  }

  Uint8List riff(String kind, List<int> chunk) {
    final b = BytesBuilder();
    b.add('RIFF'.codeUnits);
    b.add([0, 0, 0, 0]);
    b.add('WEBP'.codeUnits);
    b.add(kind.codeUnits);
    b.add(chunk);
    return b.toBytes();
  }

  Uint8List webpX(int w, int h) => riff('VP8X', [
    0, 0, 0, 0, // chunk size
    0, 0, 0, 0, // flags + reserved
    (w - 1) & 255, ((w - 1) >> 8) & 255, ((w - 1) >> 16) & 255,
    (h - 1) & 255, ((h - 1) >> 8) & 255, ((h - 1) >> 16) & 255,
    ...List.filled(8, 0),
  ]);

  Uint8List webpL(int w, int h) {
    final bits = (w - 1) | ((h - 1) << 14);
    return riff('VP8L', [
      0, 0, 0, 0,
      0x2F,
      bits & 255, (bits >> 8) & 255, (bits >> 16) & 255, (bits >> 24) & 255,
      ...List.filled(8, 0),
    ]);
  }

  Uint8List webpLossy(int w, int h) => riff('VP8 ', [
    0, 0, 0, 0, // chunk size
    0, 0, 0, // frame tag
    0x9D, 0x01, 0x2A,
    w & 255, (w >> 8) & 255, h & 255, (h >> 8) & 255,
    ...List.filled(8, 0),
  ]);

  group('a picture an owner may choose', () {
    test('a PNG is accepted and its size read from the header', () {
      final check = BusinessLogoRules.inspect(png(512, 256));
      expect(check.accepted, isTrue);
      expect(check.image!.format, LogoFormat.png);
      expect((check.image!.width, check.image!.height), (512, 256));
      expect(check.image!.mime, 'image/png');
    });

    test('a JPEG is accepted, with an APP0 segment before the frame', () {
      final check = BusinessLogoRules.inspect(jpeg(300, 200));
      expect(check.accepted, isTrue, reason: '${check.refusal}');
      expect(check.image!.format, LogoFormat.jpeg);
      expect((check.image!.width, check.image!.height), (300, 200));
    });

    test('a JPEG whose frame comes first is accepted too', () {
      expect(BusinessLogoRules.inspect(jpeg(100, 100, app0First: false)).accepted, isTrue);
    });

    test('the limits are inclusive at both ends', () {
      expect(BusinessLogoRules.inspect(png(64, 64)).accepted, isTrue);
      expect(BusinessLogoRules.inspect(png(4096, 4096)).accepted, isTrue);
    });
  });

  group('a picture it turns away, with the reason', () {
    LogoRefusal? why(Uint8List bytes, {bool fromPlatform = false}) =>
        BusinessLogoRules.inspect(bytes, fromPlatform: fromPlatform).refusal;

    test('nothing', () => expect(why(Uint8List(0)), LogoRefusal.empty));

    test('more than 2 MB', () {
      expect(why(png(512, 512, pad: BusinessLogoRules.maxBytes)), LogoRefusal.tooLarge);
      // …and exactly the cap is fine.
      final exact = png(512, 512, pad: BusinessLogoRules.maxBytes - 29);
      expect(exact.length, BusinessLogoRules.maxBytes);
      expect(BusinessLogoRules.inspect(exact).accepted, isTrue);
    });

    test('a file that only claims to be an image', () {
      // A text file saved as logo.png: the extension proves nothing.
      expect(why(Uint8List.fromList('hello, I am a logo'.codeUnits)), LogoRefusal.unsupported);
      // A GIF is a real image this till does not take.
      expect(
        why(Uint8List.fromList([...'GIF89a'.codeUnits, ...List.filled(40, 0)])),
        LogoRefusal.unsupported,
      );
    });

    test('a PNG cut off before its header ends', () {
      expect(why(png(512, 512).sublist(0, 20)), LogoRefusal.unreadable);
    });

    test('a PNG whose first chunk is not IHDR', () {
      final bad = png(512, 512);
      bad.setRange(12, 16, 'IDAT'.codeUnits);
      expect(why(bad), LogoRefusal.unreadable);
    });

    test('a JPEG that reaches the scan without ever stating its size', () {
      expect(why(jpeg(300, 200, noFrame: true)), LogoRefusal.unreadable);
    });

    test('a zero-sized picture', () {
      expect(why(png(0, 100)), LogoRefusal.unreadable);
    });

    test('too small to be seen, on either side', () {
      expect(why(png(63, 200)), LogoRefusal.tooSmall);
      expect(why(png(200, 63)), LogoRefusal.tooSmall);
    });

    test('too big to be a logo, on either side', () {
      expect(why(png(4097, 200)), LogoRefusal.tooBig);
      expect(why(png(200, 4097)), LogoRefusal.tooBig);
    });
  });

  group('WebP, which only the platform sends', () {
    test('an owner may not choose one', () {
      expect(BusinessLogoRules.inspect(webpX(300, 300)).refusal, LogoRefusal.unsupported);
    });

    test('all three flavours read their size from where each keeps it', () {
      for (final (name, bytes) in <(String, Uint8List)>[
        ('VP8X', webpX(640, 320)),
        ('VP8L', webpL(640, 320)),
        ('VP8 ', webpLossy(640, 320)),
      ]) {
        final check = BusinessLogoRules.inspect(bytes, fromPlatform: true);
        expect(check.accepted, isTrue, reason: '$name: ${check.refusal}');
        expect((check.image!.width, check.image!.height), (640, 320), reason: name);
        expect(check.image!.format, LogoFormat.webp);
      }
    });

    test('the platform may send up to 4 MB, an owner only 2', () {
      final big = Uint8List(3 * 1024 * 1024)..setRange(0, 30, webpX(300, 300));
      expect(BusinessLogoRules.inspect(big).refusal, LogoRefusal.tooLarge);
      expect(BusinessLogoRules.inspect(big, fromPlatform: true).accepted, isTrue);
      final huge = Uint8List(4 * 1024 * 1024 + 1)..setRange(0, 30, webpX(300, 300));
      expect(BusinessLogoRules.inspect(huge, fromPlatform: true).refusal, LogoRefusal.tooLarge);
    });

    test('a RIFF file that is not WebP is not one', () {
      final wav = Uint8List.fromList([
        ...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits, ...List.filled(40, 0),
      ]);
      expect(BusinessLogoRules.inspect(wav, fromPlatform: true).refusal, LogoRefusal.unsupported);
    });
  });

  group('the branding capability', () {
    PosStaff holding(Set<String> capabilities) => PosStaff(
      id: 1,
      name: 'T',
      role: PosRole(id: 1, code: 'x', nameEn: 'X', capabilities: capabilities),
    );

    test('is the owner\'s key, spelt as the brief names it', () {
      expect(PosCapability.brandingManage, 'business.branding.manage');
    });

    test('is in the registry, classified, grouped and never a cashier\'s', () {
      expect(PosCapability.all, contains(PosCapability.brandingManage));
      expect(PosCapability.isClassified(PosCapability.brandingManage), isTrue);
      expect(PosCapability.backOffice, contains(PosCapability.brandingManage));
      expect(
        CapabilityGroup.values.where(
          (g) => g.capabilities.contains(PosCapability.brandingManage),
        ),
        isNotEmpty,
      );
    });

    test('the seeded roles: only the owner holds it', () {
      expect(SystemRoles.owner, contains(PosCapability.brandingManage));
      expect(SystemRoles.manager, isNot(contains(PosCapability.brandingManage)));
      expect(SystemRoles.supervisor, isNot(contains(PosCapability.brandingManage)));
      expect(SystemRoles.cashier, isNot(contains(PosCapability.brandingManage)));
    });

    test('is allowed with the key and refused without it', () {
      expect(
        Authorization.check(holding({PosCapability.brandingManage}), PosCapability.brandingManage).isAllowed,
        isTrue,
      );
      expect(
        Authorization.check(holding({PosCapability.settingsManage}), PosCapability.brandingManage).isAllowed,
        isFalse,
        reason: 'settings.manage is not the logo key',
      );
    });
  });
}
