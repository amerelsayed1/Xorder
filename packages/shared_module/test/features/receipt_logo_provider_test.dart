import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/printer_config.dart';
import 'package:shared_module/domain/models/business_logo.dart';

/// XORD-024: which logo a receipt carries.
void main() {
  final bytes = Uint8List.fromList([137, 80, 78, 71]);

  BusinessLogo logo(LogoSource source) =>
      BusinessLogo(bytes: bytes, mime: 'image/png', source: source);

  Future<Uint8List?> read({
    required PrinterConfig printer,
    required Future<BusinessLogo?> Function() stored,
  }) {
    final container = ProviderContainer(
      overrides: [
        printerConfigProvider.overrideWith(() => _Fixed(printer)),
        businessLogoProvider.overrideWith((ref) => stored()),
      ],
    );
    addTearDown(container.dispose);
    return container.read(receiptLogoProvider.future);
  }

  test('is the stored logo when the till prints logos', () async {
    expect(
      await read(
        printer: const PrinterConfig(),
        stored: () async => logo(LogoSource.local),
      ),
      bytes,
    );
  });

  test('is the same for a logo the platform sent (cloud) as one made here (offline)', () async {
    for (final source in LogoSource.values) {
      expect(
        await read(
          printer: const PrinterConfig(),
          stored: () async => logo(source),
        ),
        bytes,
        reason: source.name,
      );
    }
  });

  test('is none when this till is set to leave it off', () async {
    expect(
      await read(
        printer: const PrinterConfig(printLogo: false),
        stored: () async => logo(LogoSource.local),
      ),
      isNull,
    );
  });

  test('is none when the business has no logo', () async {
    expect(
      await read(printer: const PrinterConfig(), stored: () async => null),
      isNull,
    );
  });

  test('is none, not an error, when reading the logo fails', () async {
    expect(
      await read(
        printer: const PrinterConfig(),
        stored: () async => throw StateError('the database went away'),
      ),
      isNull,
    );
  });
}

class _Fixed extends PrinterConfigController {
  _Fixed(this._value);

  final PrinterConfig _value;

  @override
  PrinterConfig build() => _value;
}
