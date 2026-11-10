import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The handheld ships the link package and Flutter, nothing of the till
/// (waiter-app, D-WA4) — not even as a dev dependency, whose plugins a debug
/// build would still register. An import of it would pull PostgreSQL, the
/// encrypted SQLite engine and the desktop screens into a phone app.
void main() {
  test('nothing under lib/ imports the till or either till app', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final forbidden in ['package:shared_module/', 'package:xorder_pos_offline/', 'package:xorder_pos_cloud/']) {
        if (source.contains(forbidden)) offenders.add('${entity.path}: $forbidden');
      }
    }
    expect(offenders, isEmpty);
  });
}
