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
    expect(await _mode(p.join(temp.path, FileSecretStore.fileName)), '600');
  });

  test('a rewrite leaves nothing readable behind it', () async {
    // The write is empty-file -> chmod 600 -> fill -> rename, so the secret is
    // never on disk at the umask default (0644 on stock macOS). Written first
    // and chmodded after, it was — for the length of the write and the rename.
    //
    // The ordering itself is not observable from out here without a
    // filesystem race, so what is asserted is the pair of things that ARE:
    // the live file is owner-only after repeated writes, and no half-written
    // temporary is left lying next to it.
    if (Platform.isWindows) return;
    final s = store('k');
    await s.write('v');
    await s.write('v2');
    await s.write('v3');

    expect(
      File(p.join(temp.path, '${FileSecretStore.fileName}.tmp')).existsSync(),
      isFalse,
      reason: 'the temporary is renamed onto the target, never orphaned',
    );

    expect(
      await _mode(p.join(temp.path, FileSecretStore.fileName)),
      '600',
      reason: 'rename preserves the mode it was given',
    );
    expect(await s.read(), 'v3');
  });

}

/// A file's permission bits in octal, e.g. `600`.
///
/// `stat` takes its format differently on the two platforms this runs on: BSD
/// and macOS read `-f %Lp`, GNU reads `-c %a` — and on GNU `-f` means "report
/// the filesystem", which printed a block of free-space figures where this
/// expected a mode and failed on every Linux runner.
Future<String> _mode(String path) async {
  final result = await Process.run(
    'stat',
    Platform.isMacOS ? ['-f', '%Lp', path] : ['-c', '%a', path],
  );
  return result.stdout.toString().trim();
}
