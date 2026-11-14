import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_module/data/config/file_secret_store.dart';
import 'package:shared_module/data/config/mac_keychain_secret_store.dart';
import 'package:shared_module/data/config/pos_db_secret_store.dart';
import 'package:shared_module/data/config/secret_store.dart';
import 'package:shared_module/data/config/windows_dpapi_secret_store.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/secret_store_contract.dart';

/// The secret stores' own rules, on the Linux machine the suite runs on.
///
/// DPAPI and the Keychain are reached here through stand-ins for their native
/// calls, so what is tested is everything *around* the call: the file format,
/// damage, per-key binding, status handling, the bounded delete. The calls
/// themselves are `os_secret_store_platform_test.dart`'s, on their own systems.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pos-secret-store-test');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<Directory> here() async => temp;

  final memory = InMemorySecretStore();
  secretStoreContract('the in-memory double', () async => memory);

  secretStoreContract(
    'the development file store',
    () async => DevelopmentFileSecretStore(directory: here),
  );

  secretStoreContract(
    'the DPAPI store (stand-in cipher)',
    () async => WindowsDpapiSecretStore(
      directory: here,
      cipher: const _StandInCipher(),
    ),
  );

  final keychain = _StandInKeychain();
  secretStoreContract(
    'the Keychain store (stand-in framework)',
    () async => MacKeychainSecretStore(backend: keychain),
  );

  group('SecretStore.forPlatform', () {
    test('plaintext only where nobody sells', () {
      // Every member, so a new platform added to the enum is a failing test
      // until somebody decides what it gets.
      for (final platform in SecretPlatform.values) {
        final store = SecretStore.forPlatform(
          platform: platform,
          directory: here,
        );
        expect(
          store.protectedByOperatingSystem,
          platform != SecretPlatform.development,
          reason: '$platform',
        );
      }
    });

    test('Windows gets DPAPI, macOS the Keychain, the rest the dev file', () {
      SecretStore forPlatform(SecretPlatform platform) =>
          SecretStore.forPlatform(platform: platform, directory: here);

      expect(
        forPlatform(SecretPlatform.windows),
        isA<WindowsDpapiSecretStore>(),
      );
      expect(
        forPlatform(SecretPlatform.macos),
        isA<MacKeychainSecretStore>(),
      );
      expect(
        forPlatform(SecretPlatform.development),
        isA<DevelopmentFileSecretStore>(),
      );
    });

    test('this machine is only a development platform if it is neither', () {
      final expected = Platform.isWindows
          ? SecretPlatform.windows
          : Platform.isMacOS
          ? SecretPlatform.macos
          : SecretPlatform.development;
      expect(SecretPlatform.host, expected);
    });
  });

  group('KeyedSecretStore', () {
    test('a refusing store reads as null and says why', () async {
      final store = InMemorySecretStore({'k': 'v'})..refusing = true;
      final keyed = KeyedSecretStore(store, 'k');

      expect(await keyed.read(), isNull);
      // The difference between "fresh install" and "broken keystore" that the
      // setup wizard's warning depends on.
      expect(keyed.lastFailure, isA<SecretStoreUnavailable>());

      store.refusing = false;
      expect(await keyed.read(), 'v');
      expect(keyed.lastFailure, isNull);
    });

    test('a refused write throws, as the wizard expects', () async {
      final store = InMemorySecretStore()..refusing = true;
      final keyed = KeyedSecretStore(store, 'k');

      // A PosDbSecretStoreException, so `complete()`'s existing catch shows it.
      await expectLater(
        keyed.write('secret'),
        throwsA(isA<PosDbSecretStoreException>()),
      );
      await expectLater(keyed.clear(), throwsA(isA<SecretStoreUnavailable>()));
      expect(keyed.lastFailure, isA<SecretStoreUnavailable>());
    });

    test('an empty write clears, and empty never reads back', () async {
      final store = InMemorySecretStore({'k': 'old'});
      final keyed = KeyedSecretStore(store, 'k');

      await keyed.write('');

      expect(store.values.containsKey('k'), isFalse);
      expect(await keyed.read(), isNull);
    });

    test('the refusal names the store and never the secret', () async {
      final store = InMemorySecretStore()..refusing = true;
      try {
        await KeyedSecretStore(store, 'k').write('hunter2');
        fail('should have refused');
      } on SecretStoreUnavailable catch (error) {
        expect('$error', contains(store.description));
        expect('$error', isNot(contains('hunter2')));
      }
    });

    test('the plain refusal never quotes a cause that may hold the secret', () {
      // What a parse of the secrets file throws: the excerpt it prints IS the
      // file. This used to be quoted whole into the wizard's banner.
      const parsing = PosDbSecretStoreException(
        FormatException('Unexpected character', '{"pos_db":"hunter2"'),
      );
      expect('$parsing', isNot(contains('hunter2')));
      expect('$parsing', contains('FormatException'));

      // A file error has a code and the OS's words, never a value: kept.
      const disk = PosDbSecretStoreException(
        FileSystemException(
          'Cannot open file',
          '/x/secrets.json',
          OSError('Permission denied', 13),
        ),
      );
      expect('$disk', contains('Cannot open file'));
      expect('$disk', contains('Permission denied, 13'));
    });
  });

  group('the DPAPI store', () {
    WindowsDpapiSecretStore store() =>
        WindowsDpapiSecretStore(directory: here, cipher: const _StandInCipher());
    File file() => File(p.join(temp.path, WindowsDpapiSecretStore.fileName));

    test('the file holds ciphertext, never the value', () async {
      await store().write(FileSecretStore.databasePasswordKey, 'till-password');

      final contents = file().readAsStringSync();
      expect(contents, isNot(contains('till-password')));
      expect(contents, contains(WindowsDpapiSecretStore.format));
      expect(
        File(p.join(temp.path, FileSecretStore.fileName)).existsSync(),
        isFalse,
        reason: 'and nothing is written to secrets.json',
      );
    });

    test('a blob moved to another key fails instead of answering', () async {
      final s = store();
      await s.write('a', 'secret-a');
      final json = jsonDecode(file().readAsStringSync()) as Map;
      final entries = json['entries'] as Map;
      entries['b'] = entries['a'];
      file().writeAsStringSync(jsonEncode(json));

      await expectLater(s.read('b'), throwsA(isA<SecretStoreUnavailable>()));
      expect(await s.read('a'), 'secret-a');
    });

    test('a damaged file refuses to read, rather than reading empty', () async {
      file().writeAsStringSync('{not json');

      await expectLater(
        store().read('anything'),
        throwsA(isA<SecretStoreUnavailable>()),
      );
    });

    test('a damaged file is set aside on the next write, not lost', () async {
      file().writeAsStringSync('{not json');

      await store().write('a', 'fresh');

      expect(await store().read('a'), 'fresh');
      final aside = temp
          .listSync()
          .map((entry) => p.basename(entry.path))
          .where((name) => name.contains('.damaged-'));
      expect(aside, hasLength(1));
    });

    test('a refusing cipher is a typed refusal', () async {
      final s = WindowsDpapiSecretStore(
        directory: here,
        cipher: const _RefusingCipher(),
      );
      await expectLater(
        s.write('a', 'x'),
        throwsA(isA<SecretStoreUnavailable>()),
      );
      expect(file().existsSync(), isFalse, reason: 'nothing half-written');
    });

    test('a folder that cannot be found is a typed refusal too', () async {
      final s = WindowsDpapiSecretStore(
        directory: () async => throw StateError('no Application Support'),
        cipher: const _StandInCipher(),
      );
      await expectLater(s.read('a'), throwsA(isA<SecretStoreUnavailable>()));
    });

    test('writes started together all land', () async {
      final s = store();
      await Future.wait([
        for (var i = 0; i < 8; i++) s.write('key$i', 'value$i'),
      ]);
      for (var i = 0; i < 8; i++) {
        expect(await store().read('key$i'), 'value$i');
      }
    });
  });

  group('the Keychain store', () {
    test('a locked keychain is a typed refusal that says so', () async {
      final backend = _StandInKeychain()
        ..status = KeychainStatus.interactionNotAllowed;
      final s = MacKeychainSecretStore(backend: backend);

      try {
        await s.read('a');
        fail('should have refused');
      } on SecretStoreUnavailable catch (error) {
        expect('$error', contains('locked'));
      }
      await expectLater(
        s.write('a', 'x'),
        throwsA(isA<SecretStoreUnavailable>()),
      );
      await expectLater(s.delete('a'), throwsA(isA<SecretStoreUnavailable>()));
    });

    test('a framework that will not load is a typed refusal', () async {
      final s = MacKeychainSecretStore(backend: _ThrowingKeychain());
      await expectLater(s.read('a'), throwsA(isA<SecretStoreUnavailable>()));
    });

    test('items are kept under the product service, one per key', () async {
      final backend = _StandInKeychain();
      await MacKeychainSecretStore(backend: backend).write('a', 'x');
      expect(backend.items.keys, [(MacKeychainSecretStore.service, 'a')]);
    });

    test('an item added between update and add is updated, not refused', () {
      final backend = _StandInKeychain()..raceOnAdd = true;
      expect(
        MacKeychainSecretStore(backend: backend).write('a', 'x'),
        completes,
      );
    });

    test('delete clears duplicates a release removes one at a time', () async {
      final backend = _StandInKeychain()..deletesOnePerCall = true;
      final s = MacKeychainSecretStore(backend: backend);
      await s.write('a', 'x');
      await s.write('b', 'y');

      await s.deleteAll();

      expect(backend.items, isEmpty);
    });

    test('a keychain that never empties does not hang the boot', () async {
      final backend = _StandInKeychain()..neverEmpties = true;
      await MacKeychainSecretStore(backend: backend).deleteAll();
      expect(backend.deleteCalls, lessThanOrEqualTo(64));
    });
  });
}

/// Stands in for DPAPI: binds the blob to its entropy, and is not readable.
///
/// Prefixes the entropy, then XORs the value, so a blob opened with another
/// key's entropy fails as DPAPI would (ERROR_INVALID_DATA, 13), and the file
/// never contains the value in the clear.
class _StandInCipher implements DpapiCipher {
  const _StandInCipher();

  @override
  Uint8List protect(Uint8List plain, Uint8List entropy) => Uint8List.fromList([
    ...entropy,
    0,
    for (final byte in plain) byte ^ 0x5a,
  ]);

  @override
  Uint8List unprotect(Uint8List sealed, Uint8List entropy) {
    final prefix = entropy.length + 1;
    final bound =
        sealed.length >= prefix &&
        sealed[entropy.length] == 0 &&
        Iterable<int>.generate(
          entropy.length,
        ).every((i) => sealed[i] == entropy[i]);
    if (!bound) throw const DpapiFailure('CryptUnprotectData', 13);
    return Uint8List.fromList([
      for (final byte in sealed.skip(prefix)) byte ^ 0x5a,
    ]);
  }
}

class _RefusingCipher implements DpapiCipher {
  const _RefusingCipher();

  @override
  Uint8List protect(Uint8List plain, Uint8List entropy) =>
      throw const DpapiFailure('CryptProtectData', 5);

  @override
  Uint8List unprotect(Uint8List sealed, Uint8List entropy) =>
      throw const DpapiFailure('CryptUnprotectData', 5);
}

/// Stands in for Security.framework, answering with real `OSStatus` codes.
class _StandInKeychain implements KeychainBackend {
  final items = <(String, String), Uint8List>{};

  /// Every call answers this when set: a locked keychain, say.
  int? status;

  /// The next add finds the item already there, as if another call won.
  bool raceOnAdd = false;

  /// Delete removes one match per call, as some macOS releases have.
  bool deletesOnePerCall = false;

  /// Delete answers success and removes nothing.
  bool neverEmpties = false;

  int deleteCalls = 0;

  @override
  KeychainRead read(String service, String account) {
    if (status case final failure?) return KeychainRead(failure);
    final data = items[(service, account)];
    return data == null
        ? const KeychainRead(KeychainStatus.itemNotFound)
        : KeychainRead(KeychainStatus.success, data);
  }

  @override
  int add(String service, String account, Uint8List data) {
    if (status case final failure?) return failure;
    if (raceOnAdd) {
      raceOnAdd = false;
      items[(service, account)] = Uint8List(0);
      return KeychainStatus.duplicateItem;
    }
    if (items.containsKey((service, account))) {
      return KeychainStatus.duplicateItem;
    }
    items[(service, account)] = data;
    return KeychainStatus.success;
  }

  @override
  int update(String service, String account, Uint8List data) {
    if (status case final failure?) return failure;
    if (!items.containsKey((service, account))) {
      return KeychainStatus.itemNotFound;
    }
    items[(service, account)] = data;
    return KeychainStatus.success;
  }

  @override
  int delete(String service, String? account) {
    deleteCalls++;
    if (status case final failure?) return failure;
    if (neverEmpties) return KeychainStatus.success;
    final matches = [
      for (final key in items.keys)
        if (key.$1 == service && (account == null || key.$2 == account)) key,
    ];
    if (matches.isEmpty) return KeychainStatus.itemNotFound;
    for (final key in deletesOnePerCall ? matches.take(1) : matches) {
      items.remove(key);
    }
    return KeychainStatus.success;
  }
}

class _ThrowingKeychain implements KeychainBackend {
  @override
  KeychainRead read(String service, String account) =>
      throw ArgumentError('Failed to load dynamic library');

  @override
  int add(String service, String account, Uint8List data) =>
      throw ArgumentError('Failed to load dynamic library');

  @override
  int update(String service, String account, Uint8List data) =>
      throw ArgumentError('Failed to load dynamic library');

  @override
  int delete(String service, String? account) =>
      throw ArgumentError('Failed to load dynamic library');
}
