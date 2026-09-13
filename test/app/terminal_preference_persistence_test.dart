import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';

/// Switching language or theme must never throw, whatever the disk does.
///
/// Both choices apply to the screen immediately and are written to the config
/// file in a future nobody awaits — "silent on failure", in the controllers'
/// own words, because a file that cannot be written is a reason to lose the
/// choice at the next restart, not a reason to fail the one on screen now.
///
/// They caught `Exception` only. The failures that actually happen are mostly
/// `Error`s — no platform binding, a missing plugin, a support directory the OS
/// will not name — and those escaped as unhandled errors. It surfaced as a
/// database test crashing on a language switch that had already worked.
///
/// These are plain `test`s ON PURPOSE: no widget binding means the real file
/// store's platform call throws an `Error`, which is exactly the condition that
/// escaped. An unhandled async error fails a test by itself, so reaching the
/// end is the assertion.
void main() {
  /// Long enough for the unawaited write to run and fail.
  Future<void> letTheWriteFail() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('a language switch survives a store that throws an Error', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(localeProvider.notifier).apply('ar');
    await letTheWriteFail();

    // And the screen still got what was asked for.
    expect(container.read(localeProvider).languageCode, 'ar');
  });

  test('and so does a theme switch', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(brightnessProvider.notifier).apply(Brightness.dark);
    await letTheWriteFail();

    expect(container.read(brightnessProvider), Brightness.dark);
  });
}
