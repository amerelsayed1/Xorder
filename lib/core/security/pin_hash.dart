import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Hashing for cashier PINs.
///
/// A till PIN is four digits — ten thousand possibilities. Any fast hash is
/// therefore not a hash at all: an attacker holding the database enumerates the
/// whole space in microseconds. PBKDF2 with a real iteration count is what makes
/// the search cost something, and the per-row salt is what stops one search
/// covering every member of staff at once.
///
/// Pure Dart, so `bin/pos_migrate.dart` can produce the same hashes the till
/// verifies against without a Flutter engine.
abstract final class PinHash {
  /// Deliberately slow. The till verifies a PIN once per unlock, so a hundred
  /// milliseconds is invisible to a cashier and expensive to an attacker doing
  /// it ten thousand times per member of staff.
  static const iterations = 120000;

  static final _random = Random.secure();

  static Pbkdf2 get _algorithm =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);

  /// A fresh 16-byte salt, base64 encoded for storage as text.
  static String newSalt() =>
      base64.encode(List<int>.generate(16, (_) => _random.nextInt(256)));

  static Future<String> hash(String pin, String salt) async {
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: base64.decode(salt),
    );
    return base64.encode(await key.extractBytes());
  }

  /// Compare in constant time.
  ///
  /// A `==` on the encoded strings leaks how much of the hash matched through
  /// timing. It is a small leak against a PIN, but the fix is three lines.
  static Future<bool> verify(
    String pin, {
    required String salt,
    required String expected,
  }) async {
    final actual = await hash(pin, salt);
    if (actual.length != expected.length) return false;

    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }
}
