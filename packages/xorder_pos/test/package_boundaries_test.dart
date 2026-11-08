import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one rule the package split exists for (pos-split-apps, AC-2):
///
///  * the shared package imports neither app;
///  * neither app depends on the other;
///  * the cloud-only and offline-only code is not in the shared package.
///
/// Checked by reading files, not by running them, so a dependency sneaking in
/// fails here before it fails on a customer's machine as a binary carrying
/// the other product. Run from `packages/xorder_pos`; the paths below are
/// relative to that folder, as `flutter test` runs it.
void main() {
  final shared = Directory('lib');
  final offlinePubspec = File('../../apps/xorder_pos_offline/pubspec.yaml');
  final cloudPubspec = File('../../apps/xorder_pos_cloud/pubspec.yaml');

  test('the shared package never imports an app', () {
    final offenders = <String>[];
    for (final file in shared.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final line in file.readAsLinesSync()) {
        if (line.startsWith('import ') || line.startsWith('export ')) {
          if (line.contains('package:xorder_pos_cloud/') ||
              line.contains('package:xorder_pos_offline/')) {
            offenders.add('${file.path}: $line');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('neither app depends on the other', () {
    expect(offlinePubspec.existsSync(), isTrue);
    expect(cloudPubspec.existsSync(), isTrue);
    expect(
      offlinePubspec.readAsStringSync(),
      isNot(contains('xorder_pos_cloud')),
    );
    expect(
      cloudPubspec.readAsStringSync(),
      isNot(contains('xorder_pos_offline')),
    );
  });

  test('cloud-only and offline-only code is not in the shared package', () {
    // What may stay under data/cloud: the API client the offline app renews
    // its licence through, and the device token's store.
    final cloud = Directory('lib/data/cloud')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(cloud, {'cloud_api.dart', 'device_token_vault.dart'});
    expect(Directory('lib/features/admin').existsSync(), isFalse);
    // The Admin Mode door and the back-office contract are shared on purpose.
    expect(Directory('lib/features/admin_mode').existsSync(), isTrue);
  });
}
