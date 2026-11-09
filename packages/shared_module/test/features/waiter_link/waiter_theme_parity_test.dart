import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/ui/tokens.dart';

/// The waiter handheld copies this till's light palette rather than depend on
/// this package (waiter-app, D-WA4: no till code, not even a dev dependency, in
/// a phone app). This keeps the copy honest from this side: it reads the
/// handheld's `theme.dart` as text and fails the moment a colour differs.
void main() {
  test("the waiter handheld's colours are this till's light palette", () {
    final file = File('../../apps/xorder_pos_waiter/lib/theme.dart');
    expect(file.existsSync(), isTrue, reason: 'run from packages/shared_module');
    final copied = {
      for (final m in RegExp(r'static const (\w+) = Color\((0x[0-9A-Fa-f]{8})\);').allMatches(file.readAsStringSync()))
        m.group(1)!: Color(int.parse(m.group(2)!)),
    };

    const till = PosPalette.light;
    final expected = <String, Color>{
      'accent': till.accent,
      'accentSoft': till.accentSoft,
      'onAccent': till.onAccent,
      'page': till.page,
      'surface': till.surface,
      'ink': till.ink,
      'body': till.body,
      'muted': till.muted,
      'line': till.line,
      'lineStrong': till.lineStrong,
      'ok': till.ok,
      'okSoft': till.okSoft,
      'warn': till.warn,
      'warnSoft': till.warnSoft,
      'danger': till.danger,
      'dangerSoft': till.dangerSoft,
      // The shell family (WA2 design pass): the pairing and PIN screens are
      // shell screens, as the till's start and lock screens are.
      'shell': till.shell,
      'shellCard': till.shellCard,
      'shellLine': till.shellLine,
      'shellText': till.shellText,
      'shellMuted': till.shellMuted,
    };
    expect(copied.keys.toSet(), expected.keys.toSet());
    for (final name in expected.keys) {
      expect(copied[name], expected[name], reason: name);
    }
  });
}
