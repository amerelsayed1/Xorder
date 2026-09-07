import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xorder_pos/data/config/file_secret_store.dart';

void main() {
  late Directory temp;
  FileSecretStore store(String key) =>
      FileSecretStore(key: key, directory: () async => temp);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pos-secrets-test');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('a written secret reads back, and clearing removes only its key', () async {
    final password = store(FileSecretStore.databasePasswordKey);
    final token = store(FileSecretStore.deviceTokenKey);

    await password.write('till-password');
    await token.write('xdt_abc123');

    expect(await password.read(), 'till-password');
    expect(await token.read(), 'xdt_abc123');

    // Both keys share one file — the reason a support engineer clearing "the
    // credentials" clears one thing.
    final file = File(p.join(temp.path, FileSecretStore.fileName));
    final onDisk = jsonDecode(file.readAsStringSync()) as Map;
    expect(onDisk.keys, containsAll([
      FileSecretStore.databasePasswordKey,
      FileSecretStore.deviceTokenKey,
    ]));

    await password.clear();
    expect(await password.read(), isNull);
    expect(await token.read(), 'xdt_abc123');
  });

  test('an empty or missing value reads as null, never empty string', () async {
    final s = store('anything');
    expect(await s.read(), isNull);
    await s.write('x');
    await s.clear();
    expect(await s.read(), isNull);
  });

  test('a damaged file is an empty store, not a crash', () async {
    File(p.join(temp.path, FileSecretStore.fileName))
        .writeAsStringSync('{not json');
    final s = store(FileSecretStore.databasePasswordKey);
    expect(await s.read(), isNull);
    // And it heals on the next write.
    await s.write('fresh');
    expect(await s.read(), 'fresh');
  });

  test('permissions are owner-only where the platform honours them', () async {
    if (Platform.isWindows) return;
    final s = store('k');
    await s.write('v');
    final mode = (await Process.run('stat', [
      '-f', '%Lp',
      p.join(temp.path, FileSecretStore.fileName),
    ])).stdout.toString().trim();
    expect(mode, '600');
  });
}
