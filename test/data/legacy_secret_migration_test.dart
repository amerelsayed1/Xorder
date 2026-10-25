import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xorder_pos/data/config/file_secret_store.dart';
import 'package:xorder_pos/data/config/legacy_secret_migration.dart';
import 'package:xorder_pos/data/config/secret_store.dart';

import '../support/fakes.dart';

/// The one-time move of an older build's `secrets.json` into the OS store.
///
/// Real files in a temporary folder, through the same `FileSecretStore` that
/// wrote them in the field, so the file under migration is the file a till
/// actually has. The OS store is the in-memory double, which can be told to
/// refuse at any step.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pos-secret-migration-test');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<Directory> here() async => temp;
  File legacy() => File(p.join(temp.path, FileSecretStore.fileName));

  /// The four secrets a till that had opened Management carries, written the
  /// way the old build wrote them.
  Future<Map<String, String>> writeLegacy() async {
    final values = {
      FileSecretStore.databasePasswordKey: 'till-password',
      FileSecretStore.deviceTokenKey: 'xdt_abc123',
      FileSecretStore.backupPasswordKey: 'backup-password',
      FileSecretStore.adminPasswordKey: 'admin-password',
    };
    for (final MapEntry(:key, :value) in values.entries) {
      await FileSecretStore(key: key, directory: here).write(value);
    }
    return values;
  }

  LegacySecretMigration migrate(SecretStore target) =>
      LegacySecretMigration(target: target, directory: here);

  test('every value moves, is verified, and the file is gone', () async {
    final values = await writeLegacy();
    final store = InMemorySecretStore();

    final result = await migrate(store).run();

    expect(result, isA<LegacySecretsMigrated>());
    expect(store.values, values);
    expect(legacy().existsSync(), isFalse);
    expect(result.storeRefused, isFalse);
  });

  test('the file is zeroed before it is deleted', () async {
    // Watched through the one gap the wipe leaves: a file whose delete fails.
    // A read-only folder lets the overwrite happen and refuses the unlink.
    // No POSIX folder modes on Windows, and root ignores them everywhere.
    if (Platform.isWindows) return;
    if ((Process.runSync('id', ['-u']).stdout as String).trim() == '0') return;
    await writeLegacy();
    final length = legacy().lengthSync();
    await Process.run('chmod', ['500', temp.path]);
    addTearDown(() => Process.run('chmod', ['700', temp.path]));

    final result = await migrate(InMemorySecretStore()).run();

    expect(result, isA<LegacySecretsNotWiped>());
    final left = legacy().readAsBytesSync();
    expect(left, hasLength(length));
    expect(left.every((byte) => byte == 0), isTrue);
  });

  test('a zeroed remnant is finished off on the next launch', () async {
    legacy().writeAsBytesSync(List.filled(64, 0));
    final store = InMemorySecretStore({'kept': 'value'});

    final result = await migrate(store).run();

    expect(result, isA<NoLegacySecrets>());
    expect(legacy().existsSync(), isFalse);
    expect(store.values, {'kept': 'value'}, reason: 'nothing written over');
  });

  test('a refusing store leaves the file byte for byte, and warns', () async {
    await writeLegacy();
    final before = legacy().readAsBytesSync();
    final store = InMemorySecretStore()..refusing = true;

    final result = await migrate(store).run();

    expect(result, isA<LegacySecretsNotMigrated>());
    expect(result.storeRefused, isTrue);
    expect(legacy().readAsBytesSync(), before);
  });

  test('a refusal half way puts back what it wrote', () async {
    await writeLegacy();
    final before = legacy().readAsBytesSync();
    // The OS store already holds an older till password. Two writes get
    // through (that key, then the device token), the third is refused.
    final store = InMemorySecretStore({
      FileSecretStore.databasePasswordKey: 'older-till-password',
    })..refuseWritesAfter = 2;

    final result = await migrate(store).run();

    expect(result, isA<LegacySecretsNotMigrated>());
    expect(legacy().readAsBytesSync(), before, reason: 'file untouched');
    // Roll-back: the device token had no earlier value, so it is deleted
    // again. The till password had one, and putting it back is a write the
    // store refuses too — which the result says rather than hides.
    expect(store.values.containsKey(FileSecretStore.deviceTokenKey), isFalse);
    expect(
      (result as LegacySecretsNotMigrated).restoredAfterwards,
      isFalse,
    );
  });

  test('a refusal half way with nothing to restore leaves no trace', () async {
    await writeLegacy();
    final store = InMemorySecretStore()..refuseWritesAfter = 2;

    final result = await migrate(store).run();

    expect(result, isA<LegacySecretsNotMigrated>());
    expect((result as LegacySecretsNotMigrated).restoredAfterwards, isTrue);
    expect(store.values, isEmpty, reason: 'no half state');
    expect(legacy().existsSync(), isTrue);
  });

  test('a read-back that differs is a failure, not a success', () async {
    await writeLegacy();
    final before = legacy().readAsBytesSync();
    final store = _ForgetfulStore();

    final result = await migrate(store).run();

    expect(result, isA<LegacySecretsNotMigrated>());
    expect(legacy().readAsBytesSync(), before);
  });

  test('a damaged file is left alone, and is not the store\'s fault', () async {
    legacy().writeAsStringSync('{not json');
    final store = InMemorySecretStore();

    final result = await migrate(store).run();

    expect(result, isA<LegacySecretsUnreadable>());
    expect(result.storeRefused, isFalse);
    expect(legacy().readAsStringSync(), '{not json');
    expect(store.writes, 0);
  });

  test('run twice: the second run finds nothing to do', () async {
    final values = await writeLegacy();
    final store = InMemorySecretStore();

    await migrate(store).run();
    final second = await migrate(store).run();

    expect(second, isA<NoLegacySecrets>());
    expect(store.values, values);
  });

  test('a crash after the copy and before the wipe is harmless', () async {
    // The state such a crash leaves: values in both places.
    final values = await writeLegacy();
    final store = InMemorySecretStore(values);

    final result = await migrate(store).run();

    expect(result, isA<LegacySecretsMigrated>());
    expect(store.values, values);
    expect(legacy().existsSync(), isFalse);
  });

  test('the file is newer than the store, so the file wins', () async {
    await writeLegacy();
    final store = InMemorySecretStore({
      FileSecretStore.databasePasswordKey: 'from-before-a-downgrade',
    });

    await migrate(store).run();

    expect(store.values[FileSecretStore.databasePasswordKey], 'till-password');
  });

  test('a stranded temp file from the old store is wiped too', () async {
    final stranded = File('${legacy().path}.tmp')
      ..writeAsStringSync(jsonEncode({'pos_till_database_password': 'x'}));

    final result = await migrate(InMemorySecretStore()).run();

    expect(result, isA<NoLegacySecrets>());
    expect(stranded.existsSync(), isFalse);
  });

  test('never runs against the development store, which IS the file', () async {
    final values = await writeLegacy();

    final result = await migrate(
      DevelopmentFileSecretStore(directory: here),
    ).run();

    expect(result, isA<LegacySecretsNotApplicable>());
    final onDisk = jsonDecode(legacy().readAsStringSync()) as Map;
    expect(onDisk, values);
  });
}

/// Accepts every write and reads back something else: a store that lies.
class _ForgetfulStore extends InMemorySecretStore {
  @override
  Future<String?> read(String key) async {
    final value = await super.read(key);
    return value == null ? null : '$value-but-different';
  }
}
