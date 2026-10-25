import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';

/// Admin Mode's password: the stored format, the derivation under it, and the
/// rule a new one must meet (ADR-006b slice D, as the owner narrowed it).
///
/// Pure Dart and no database. The round trips run at a thousand iterations
/// rather than 600 000 — the count is stored in the row, so verifying reads it
/// back from there — and exactly one case pays for the real figure, to pin the
/// default a till actually writes.
void main() {
  List<int> hex(String digits) => [
    for (var i = 0; i < digits.length; i += 2)
      int.parse(digits.substring(i, i + 2), radix: 16),
  ];

  group('PasswordHash.derive is PBKDF2-HMAC-SHA256', () {
    // Published vectors, so a disagreement with any other verifier — the
    // database-side check slice E brings, a support tool — shows up as this
    // side being wrong about the algorithm, not as somebody's password
    // "suddenly" failing.
    test('"password" / "salt", one iteration', () async {
      expect(
        await PasswordHash.derive('password', utf8.encode('salt'), 1),
        hex('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'),
      );
    });

    test('"password" / "salt", 4096 iterations', () async {
      expect(
        await PasswordHash.derive('password', utf8.encode('salt'), 4096),
        hex('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a'),
      );
    });

    test('RFC 7914 §11, "passwd" / "salt", one iteration (first block)',
        () async {
      expect(
        await PasswordHash.derive('passwd', utf8.encode('salt'), 1),
        hex('55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'),
      );
    });
  });

  group('PasswordHash round trip', () {
    test('the right password verifies and a wrong one does not', () async {
      final stored = await PasswordHash.create('correct horse', rounds: 1000);
      expect(await PasswordHash.verify('correct horse', stored), isTrue);
      expect(await PasswordHash.verify('correct horsE', stored), isFalse);
      expect(
        await PasswordHash.verify('correct horse ', stored),
        isFalse,
        reason: 'never trimmed: the space is part of the secret',
      );
    });

    test('an Arabic password is hashed as typed', () async {
      final stored = await PasswordHash.create('كلمة سر قوية', rounds: 1000);
      expect(await PasswordHash.verify('كلمة سر قوية', stored), isTrue);
      expect(await PasswordHash.verify('كلمة سر قويه', stored), isFalse);
    });

    test('the stored form names its scheme and work, and each salt is fresh',
        () async {
      final first = await PasswordHash.create('same password', rounds: 1000);
      final second = await PasswordHash.create('same password', rounds: 1000);
      expect(first, isNot(second));

      final parts = PasswordHash.parse(first)!;
      expect(parts.iterations, 1000);
      expect(parts.salt, hasLength(PasswordHash.saltLength));
      expect(parts.key, hasLength(PasswordHash.keyLength));
      // The shape migration 54's CHECK holds every writer to.
      expect(
        RegExp(
          r'^pbkdf2-sha256\$[0-9]{1,9}\$[A-Za-z0-9+/]+={0,2}\$'
          r'[A-Za-z0-9+/]+={0,2}$',
        ).hasMatch(first),
        isTrue,
        reason: first,
      );
    });

    test('a till writes 600 000 iterations unless told otherwise', () async {
      final stored = await PasswordHash.create('the real figure');
      expect(stored, startsWith('pbkdf2-sha256\$600000\$'));
      expect(PasswordHash.needsRehash(stored), isFalse);
      expect(await PasswordHash.verify('the real figure', stored), isTrue);
    });

    test('a row made with less work than this build asks for says so',
        () async {
      final stored = await PasswordHash.create('older row', rounds: 1000);
      expect(PasswordHash.needsRehash(stored), isTrue);
      expect(PasswordHash.needsRehash('not a hash'), isTrue);
    });
  });

  group('PasswordHash refuses what it does not read', () {
    late String stored;
    setUpAll(() async {
      stored = await PasswordHash.create('a fine password', rounds: 1000);
    });

    String withField(int index, String value) {
      final fields = stored.split(r'$');
      fields[index] = value;
      return fields.join(r'$');
    }

    test('another scheme is not guessed at', () async {
      final newer = withField(0, 'argon2id');
      expect(PasswordHash.parse(newer), isNull);
      expect(await PasswordHash.verify('a fine password', newer), isFalse);
    });

    test('malformed rows are no password at all, never a crash', () async {
      for (final bad in [
        '',
        'a fine password',
        'pbkdf2-sha256\$1000\$onlythree',
        withField(1, '0'),
        withField(1, 'many'),
        withField(1, '${PasswordHash.maxIterations + 1}'),
        withField(2, 'not*base64'),
        withField(2, base64.encode(List<int>.filled(8, 1))),
        withField(3, base64.encode(List<int>.filled(16, 1))),
        '$stored\$extra',
      ]) {
        expect(PasswordHash.parse(bad), isNull, reason: bad);
        expect(
          await PasswordHash.verify('a fine password', bad),
          isFalse,
          reason: bad,
        );
      }
    });

    test('a tampered key or count does not verify', () async {
      final key = PasswordHash.parse(stored)!.key.toList();
      key[0] ^= 1;
      expect(
        await PasswordHash.verify(
          'a fine password',
          withField(3, base64.encode(key)),
        ),
        isFalse,
      );
      expect(
        await PasswordHash.verify('a fine password', withField(1, '1001')),
        isFalse,
      );
    });

    test('the unmatchable stand-in is well formed, at the real work', () {
      final parts = PasswordHash.parse(PasswordHash.unmatchable);
      expect(parts, isNotNull);
      expect(parts!.iterations, PasswordHash.iterations);
    });
  });

  group('PasswordPolicy', () {
    test('ten characters is the floor', () {
      expect(PasswordPolicy.validate('123456789'), PasswordProblem.tooShort);
      expect(PasswordPolicy.validate('1234567890'), isNull);
      expect(PasswordPolicy.minLength, 10);
    });

    test('counted in characters as typed — Arabic and emoji included', () {
      expect(PasswordPolicy.validate('كلمةسرطويل'), isNull, reason: '10 letters');
      expect(
        PasswordPolicy.validate('كلمةسرطوي'),
        PasswordProblem.tooShort,
        reason: '9 letters',
      );
      // Eighteen UTF-16 units, nine characters: String.length would let it in.
      expect(PasswordPolicy.validate('😀' * 9), PasswordProblem.tooShort);
      expect(PasswordPolicy.validate('😀' * 10), isNull);
    });

    test('a ceiling of 128, never lower', () {
      expect(PasswordPolicy.validate('a' * 128), isNull);
      expect(PasswordPolicy.validate('a' * 129), PasswordProblem.tooLong);
      expect(PasswordPolicy.maxLength, greaterThanOrEqualTo(128));
    });

    test('not the username, whatever the case or the spaces', () {
      expect(
        PasswordPolicy.validate(' AmerMahsoub ', username: 'amermahsoub'),
        PasswordProblem.sameAsUsername,
      );
      expect(
        PasswordPolicy.validate('amermahsoub1', username: 'amermahsoub'),
        isNull,
      );
    });

    test('not the PIN — said as that, not as "too short"', () {
      expect(
        PasswordPolicy.validate('4321', pin: '4321'),
        PasswordProblem.sameAsPin,
      );
      expect(PasswordPolicy.validate('1234', pin: '4321'), PasswordProblem.tooShort);
    });

    test('and no rules about what the characters are', () {
      expect(PasswordPolicy.validate('aaaaaaaaaa'), isNull);
      expect(PasswordPolicy.validate('just ten c'), isNull);
    });
  });
}
