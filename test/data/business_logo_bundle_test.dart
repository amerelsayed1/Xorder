import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/cloud/bootstrap_bundle.dart';

/// XORD-021 — what the bundle's `branding` block means to a till.
///
/// No PostgreSQL needed: this is parsing only. The part that matters is the
/// difference between "the restaurant has no logo" (a block with a null) and
/// "this platform says nothing about logos" (no block), because one removes a
/// logo from the till and the other must leave it alone.
void main() {
  test('reads the logo address out of the branding block', () {
    final bundle = BootstrapBundle.tryParse({
      'config_version': 3,
      'branding': {'display_name': 'BL', 'logo_url': 'https://x.test/a.webp'},
    })!;
    expect(bundle.branding!.logoUrl, 'https://x.test/a.webp');
  });

  test('a block with a null logo means "none"', () {
    final bundle = BootstrapBundle.tryParse({
      'config_version': 3,
      'branding': {'logo_url': null},
    })!;
    expect(bundle.branding, isNotNull);
    expect(bundle.branding!.logoUrl, isNull);
  });

  test('an empty string is none too, not an address to fetch', () {
    final bundle = BootstrapBundle.tryParse({
      'config_version': 3,
      'branding': {'logo_url': ''},
    })!;
    expect(bundle.branding!.logoUrl, isNull);
  });

  test('no block, or a block of the wrong type, is no statement at all', () {
    expect(BootstrapBundle.tryParse({'config_version': 3})!.branding, isNull);
    expect(
      BootstrapBundle.tryParse({'config_version': 3, 'branding': 'x'})!
          .branding,
      isNull,
    );
    expect(
      BootstrapBundle.tryParse({
        'config_version': 3,
        'branding': [1],
      })!.branding,
      isNull,
    );
  });
}
