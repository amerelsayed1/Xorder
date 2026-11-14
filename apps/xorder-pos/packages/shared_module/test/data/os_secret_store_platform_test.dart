import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/config/mac_keychain_secret_store.dart';
import 'package:shared_module/data/config/windows_dpapi_secret_store.dart';

import 'package:xorder_pos_test_support/secret_store_contract.dart';

/// The real operating-system stores, each on its own system only.
///
/// Skipped everywhere else, which means skipped on the Linux machine the rest
/// of the suite usually runs on. This is the test that proves the native calls
/// work, so run it on a Windows till and on a Mac before a release.
void main() {
  group('Windows DPAPI', () {
    if (!Platform.isWindows) {
      test('needs Windows', () {}, skip: 'Windows only');
      return;
    }

    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pos-dpapi-test');
    });
    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    secretStoreContract(
      'the DPAPI store',
      () async => WindowsDpapiSecretStore(directory: () async => temp),
    );

    test('seals and opens with the same entropy, not with another', () {
      const cipher = Win32DpapiCipher();
      final plain = Uint8List.fromList(utf8.encode('till-password'));
      final entropy = WindowsDpapiSecretStore.entropyFor('a');

      final sealed = cipher.protect(plain, entropy);

      expect(
        utf8.decode(sealed, allowMalformed: true),
        isNot(contains('till-password')),
      );
      expect(cipher.unprotect(sealed, entropy), plain);
      expect(
        () => cipher.unprotect(sealed, WindowsDpapiSecretStore.entropyFor('b')),
        throwsA(isA<DpapiFailure>()),
      );
    });
  });

  group('macOS Keychain', () {
    if (!Platform.isMacOS) {
      test('needs macOS', () {}, skip: 'macOS only');
      return;
    }

    // The real login keychain, so: prefixed keys, and no deleteAll, which
    // would remove the developer's own till's passwords with the test's.
    secretStoreContract(
      'the Keychain store',
      () async => MacKeychainSecretStore(),
      keyPrefix: 'xorder-pos-test-${DateTime.now().microsecondsSinceEpoch}-',
      includeDeleteAll: false,
    );
  });
}
