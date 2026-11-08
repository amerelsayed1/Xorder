import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/config/secret_store.dart';

/// What every [SecretStore] must do, run against each implementation.
///
/// One suite rather than one per store, so the in-memory double the widget
/// tests lean on is held to the same promises as DPAPI and the Keychain. A
/// double that answered differently would let a widget test pass against a
/// store that does not exist.
///
/// [open] must return a store over the SAME backing each time it is called:
/// the second call is how "it survives a restart" is asked. [keyPrefix] keeps
/// a run against a real keychain off the till's own entries, and
/// [includeDeleteAll] is false there for the same reason: `deleteAll` on the
/// developer's real login keychain would take their real till's passwords.
void secretStoreContract(
  String name,
  Future<SecretStore> Function() open, {
  String keyPrefix = '',
  bool includeDeleteAll = true,
}) {
  final a = '${keyPrefix}contract_a';
  final b = '${keyPrefix}contract_b';

  group('$name keeps the SecretStore contract', () {
    tearDown(() async {
      final store = await open();
      await store.delete(a);
      await store.delete(b);
    });

    test('a key never written reads as null', () async {
      expect(await (await open()).read(a), isNull);
    });

    test('a written value reads back exactly, from a fresh instance', () async {
      // Arabic, quotes, a backslash, an emoji: a password is whatever the
      // installer generated or the owner typed, and every byte must survive.
      const value = 'كلمة-السر "quoted" \\ ∆ 🔑 x';
      await (await open()).write(a, value);
      expect(await (await open()).read(a), value);
    });

    test('a second write replaces the first', () async {
      final store = await open();
      await store.write(a, 'first');
      await store.write(a, 'second');
      expect(await store.read(a), 'second');
    });

    test('keys are independent, and delete removes only its own', () async {
      final store = await open();
      await store.write(a, 'value-a');
      await store.write(b, 'value-b');

      await store.delete(a);

      expect(await store.read(a), isNull);
      expect(await store.read(b), 'value-b');
    });

    test('deleting what is not there is not an error', () async {
      final store = await open();
      await store.delete(a);
      await store.delete(a);
      expect(await store.read(a), isNull);
    });

    if (includeDeleteAll) {
      test('deleteAll leaves nothing, and is safe to repeat', () async {
        final store = await open();
        await store.write(a, 'value-a');
        await store.write(b, 'value-b');

        await store.deleteAll();
        await store.deleteAll();

        expect(await (await open()).read(a), isNull);
        expect(await (await open()).read(b), isNull);
      });
    }
  });
}
