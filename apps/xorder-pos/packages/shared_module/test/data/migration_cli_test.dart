@Tags(['tool'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `bin/pos_migrate.dart` has to run under a plain `dart run`.
///
/// It is an install-time act performed before the app exists on the machine —
/// there is no Flutter engine, and `dart:ui` is not available. Nothing it
/// imports may reach `package:flutter`, however indirectly.
///
/// This is a real regression, not a hypothetical: wiring the OS keystore into
/// `MutablePosDbCredentials` pulled `package:flutter/services.dart` into
/// `pos_database.dart`, which the tool imports — and the tool stopped starting.
void main() {
  test('the migration tool starts without a Flutter engine', () async {
    final result = await Process.run(
      'dart',
      ['run', 'bin/pos_migrate.dart', '--help'],
      workingDirectory: Directory.current.path,
    );

    final output = '${result.stdout}${result.stderr}';

    expect(
      output,
      isNot(contains("Dart library 'dart:ui' is not available")),
      reason: 'something under bin/pos_migrate.dart now imports package:flutter',
    );
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('--database'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
