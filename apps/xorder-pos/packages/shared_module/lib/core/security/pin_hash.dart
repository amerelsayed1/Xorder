import 'dart:convert';
import 'dart:isolate';
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
/// How long a cashier PIN is — one constant, because both ends have to agree.
///
/// Every keypad in the till submits the moment this many digits are in: there
/// is no confirm key to press, by design, so a cashier unlocks in four taps.
/// The consequence is that a PIN of any *other* length cannot be typed at all.
/// A staff pane that accepted "four or more" therefore created accounts whose
/// owner could never sign in — the keypad refused the fifth digit and sent the
/// first four. Creation is held to exactly this length for that reason.
abstract final class PinRules {
  static const length = 4;

  static final _digits = RegExp(r'^[0-9]+$');

  /// Whether this is a PIN the till could actually accept at a keypad.
  static bool isWellFormed(String pin) =>
      pin.length == length && _digits.hasMatch(pin);
}

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

/// Why a password was refused. Enum-keyed so the screen that says it is a
/// switch the compiler checks — see `AdminText.passwordProblem`.
enum PasswordProblem {
  /// The PIN typed again. Checked first, because it is the likeliest mistake:
  /// the first time somebody sets a password they have just typed their PIN
  /// into the door, and "too short" would not tell them what they did.
  sameAsPin,

  /// Fewer than [PasswordPolicy.minLength] characters.
  tooShort,

  /// More than [PasswordPolicy.maxLength] characters.
  tooLong,

  /// The username, give or take case and spaces.
  sameAsUsername,
}

/// What an Admin Mode password must be (ADR-006b D4, as the owner narrowed it).
///
/// **Length, and two refusals, and nothing else.** No "one digit, one symbol":
/// composition rules make people write `Password1!` on a sticky note, and a
/// long phrase in Arabic is a better secret than anything they produce. So
/// the rule is ten characters or more, not the username, not the PIN.
///
/// **Characters are runes, not UTF-16 units.** `String.length` would count an
/// emoji as two and let a nine-character password through; runes count what a
/// person typed. Arabic letters are one rune each, so "كلمة سر قوية" is the
/// length it looks. Diacritics (harakat) are runes of their own and count —
/// accepted, since they are also typed.
///
/// **Never trimmed, never case-folded, never normalised.** A space at the end
/// is part of the secret. No NFC normalisation either: Dart core has none, and
/// normalising on one side only would refuse a right password. If two
/// keyboard layouts ever produce different code points for the same Arabic
/// glyph, the fix is to normalise on every writer and verifier at once.
///
/// Pure Dart, so the admin repository can ask it again before it writes — the
/// form asking is a courtesy, the write asking is the rule.
abstract final class PasswordPolicy {
  /// The owner's figure (25 Oct 2026). There is no second factor, so the one
  /// factor carries the weight; ten is two more than the common floor.
  static const minLength = 10;

  /// A bound on input, not on strength. Nobody types more, and a field with
  /// no bound is a way of handing the door a megabyte to hash on every try.
  /// The owner asked that the limit never be set below this.
  static const maxLength = 128;

  static int lengthOf(String password) => password.runes.length;

  /// Null when [password] may be used; otherwise the first reason it may not.
  ///
  /// [username] and [pin] are the account's own, when known. The PIN check is
  /// unreachable for any PIN [PinRules] accepts today (four digits is shorter
  /// than [minLength]) and kept anyway: it gives the specific message for the
  /// specific mistake, and it holds if the PIN rules ever change.
  static PasswordProblem? validate(
    String password, {
    String? username,
    String? pin,
  }) {
    if (pin != null && pin.isNotEmpty && password == pin) {
      return PasswordProblem.sameAsPin;
    }
    final length = lengthOf(password);
    if (length < minLength) return PasswordProblem.tooShort;
    if (length > maxLength) return PasswordProblem.tooLong;
    final name = username?.trim().toLowerCase() ?? '';
    if (name.isNotEmpty && password.trim().toLowerCase() == name) {
      return PasswordProblem.sameAsUsername;
    }
    return null;
  }
}

/// The parts of a stored password, as [PasswordHash.parse] read them.
class PasswordHashParts {
  const PasswordHashParts({
    required this.iterations,
    required this.salt,
    required this.key,
  });

  final int iterations;
  final List<int> salt;
  final List<int> key;
}

/// Hashing for Admin Mode passwords: `pbkdf2-sha256$<iterations>$<salt>$<key>`.
///
/// **One self-describing text column, not three.** The PIN is stored as
/// `pin_salt` + `pin_hash` with the iteration count in code, which is why it
/// can never be raised: every stored PIN would stop verifying at once. Here
/// the scheme and the count travel with the row, so a later build can raise
/// [iterations] and re-hash on the next sign-in ([needsRehash]) while every
/// old row still verifies. Migration 55's CHECK holds the same shape, so no
/// writer — the CLI, a psql prompt — can put a plaintext in the column.
///
/// **600 000 iterations**, OWASP's 2023 figure for PBKDF2-HMAC-SHA256, against
/// the PIN's 120 000. A password is typed once per Admin Mode session, not per
/// unlock, so the till can afford five times the work. In pure Dart that is
/// roughly 0.3–0.6 s on a till PC (assumed, not measured — measure on the
/// slowest supported machine); it runs in [Isolate.run] so the door does not
/// freeze while it does. The PIN path is untouched: `PinHash` stays at 120 000 because the
/// cloud verifier and POS-BE-024 depend on it.
///
/// **Verified in Dart, on the till, against a hash the till role can read.**
/// ADR-006b wants the database to verify (a `SECURITY DEFINER` function, so
/// the till role never SELECTs the column); that is slice E. Until then a
/// stolen till credential can read every password hash and attack it offline
/// — 600 000 iterations is what makes that expensive, not impossible.
abstract final class PasswordHash {
  /// The version. A row with any other prefix does not verify — it is from a
  /// newer build or it is not a hash — rather than being guessed at.
  static const scheme = 'pbkdf2-sha256';

  static const iterations = 600000;
  static const saltLength = 16;
  static const keyLength = 32;

  /// The most a stored row may ask for. A row edited to two billion
  /// iterations would otherwise hang the door for hours on a single try.
  static const maxIterations = 10000000;

  static final _random = Random.secure();

  /// A fresh salt and a stored-form hash of [password].
  ///
  /// [rounds] exists for unit tests, which cannot spend half a second per
  /// case; every writer in `lib/` takes the default, and migration 55 refuses
  /// a row below it.
  static Future<String> create(String password, {int rounds = iterations}) async {
    final salt = List<int>.generate(saltLength, (_) => _random.nextInt(256));
    final key = await derive(password, salt, rounds);
    return encode(PasswordHashParts(iterations: rounds, salt: salt, key: key));
  }

  /// Whether [password] is the one [stored] was made from. False, never a
  /// throw, for a row that is not in this format: a malformed hash is a
  /// password nobody can sign in with, not a crash at the door.
  static Future<bool> verify(String password, String stored) async {
    final parts = parse(stored);
    if (parts == null) return false;
    final actual = await derive(password, parts.salt, parts.iterations);
    return _sameBytes(actual, parts.key);
  }

  /// The derived key, computed on another isolate.
  ///
  /// Public so a test can check it against a published PBKDF2-HMAC-SHA256
  /// vector — the one thing that catches this side and some other verifier
  /// disagreeing about the algorithm rather than the password.
  static Future<List<int>> derive(
    String password,
    List<int> salt,
    int rounds,
  ) {
    // Plain values only cross the isolate boundary: the string, the bytes and
    // the count. The algorithm object is built on the other side.
    final secret = utf8.encode(password);
    final nonce = List<int>.of(salt);
    return Isolate.run(() async {
      final key =
          await Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: rounds,
            bits: keyLength * 8,
          ).deriveKey(secretKey: SecretKey(secret), nonce: nonce);
      return List<int>.of(await key.extractBytes());
    });
  }

  static String encode(PasswordHashParts parts) =>
      '$scheme\$${parts.iterations}\$${base64.encode(parts.salt)}'
      '\$${base64.encode(parts.key)}';

  /// The parts of [stored], or null when it is not a hash this build reads.
  static PasswordHashParts? parse(String stored) {
    final fields = stored.split(r'$');
    if (fields.length != 4 || fields[0] != scheme) return null;
    final rounds = int.tryParse(fields[1]);
    if (rounds == null || rounds < 1 || rounds > maxIterations) return null;
    try {
      final salt = base64.decode(fields[2]);
      final key = base64.decode(fields[3]);
      if (salt.length < saltLength || key.length != keyLength) return null;
      return PasswordHashParts(iterations: rounds, salt: salt, key: key);
    } on FormatException {
      return null;
    }
  }

  /// Whether [stored] was made with less work than this build asks for. Not
  /// acted on yet — nothing re-hashes — but it is the question a later raise
  /// of [iterations] will need answered at sign-in.
  static bool needsRehash(String stored) =>
      (parse(stored)?.iterations ?? 0) < iterations;

  /// A well-formed hash nobody's password matches, for the sign-in to verify
  /// against when the username names nobody — so "no such person" costs the
  /// same 600 000 iterations as "wrong password" and the two cannot be told
  /// apart by how long the door takes to say no.
  static final String unmatchable = encode(
    PasswordHashParts(
      iterations: iterations,
      salt: List<int>.filled(saltLength, 0),
      key: List<int>.filled(keyLength, 0),
    ),
  );

  /// Constant time: every byte is compared whatever the first difference.
  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
