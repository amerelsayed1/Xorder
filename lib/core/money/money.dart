import 'rounding.dart';

/// Money as **integer minor units**, never a double.
///
/// The Flutter build sheet is explicit: money is int minor units end to end,
/// rounded half-up once at the tax line to match the Laravel `Order::total`
/// `decimal:2` cast. Floating point never touches a price in this app.
///
/// The exponent is carried because `CurrencyEnum` on the server already
/// contains three-decimal currencies (KWD, BHD, OMR, JOD) alongside two-decimal
/// ones. Hard-coding 100 would be wrong for a Kuwaiti tenant.
class Money implements Comparable<Money> {
  const Money(this.minor, {this.currency = 'EGP', this.exponent = 2});

  /// Amount in minor units — piastres, halalas, fils.
  final int minor;
  final String currency;
  final int exponent;

  static const zero = Money(0);

  /// Parse a major-unit string ("1338.68") without going through a double.
  ///
  /// Returns null on anything unparseable rather than throwing: this is fed by
  /// cashier keypad input and by JSON from a server that may send a decimal
  /// string, and neither should be able to crash a till.
  static Money? tryParse(
    String input, {
    String currency = 'EGP',
    int exponent = 2,
  }) {
    final trimmed = input.trim().replaceAll(',', '');
    if (trimmed.isEmpty) return null;

    final match = RegExp(r'^(-?)(\d*)(?:\.(\d*))?$').firstMatch(trimmed);
    if (match == null) return null;

    final whole = match.group(2) ?? '';
    final fraction = match.group(3) ?? '';
    if (whole.isEmpty && fraction.isEmpty) return null;

    // Pad or truncate the fraction to the currency's exponent. Truncation is
    // deliberate: a cashier typing more precision than the currency has is a
    // typo, and rounding it up would silently overcharge.
    final padded = fraction.padRight(exponent, '0').substring(0, exponent);
    final magnitude = int.parse('${whole.isEmpty ? '0' : whole}$padded');

    return Money(
      match.group(1) == '-' ? -magnitude : magnitude,
      currency: currency,
      exponent: exponent,
    );
  }

  int get _scale => switch (exponent) {
    0 => 1,
    2 => 100,
    3 => 1000,
    _ => _pow10(exponent),
  };

  static int _pow10(int e) {
    var result = 1;
    for (var i = 0; i < e; i++) {
      result *= 10;
    }
    return result;
  }

  bool get isZero => minor == 0;
  bool get isPositive => minor > 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) => _combine(other, minor + other.minor);
  Money operator -(Money other) => _combine(other, minor - other.minor);
  Money operator -() => copyWith(minor: -minor);

  /// Multiply by a whole quantity. Exact — no rounding needed.
  Money operator *(int quantity) => copyWith(minor: minor * quantity);

  /// Apply a rate given in **basis points** (1400 = 14%), rounded half-up.
  ///
  /// Basis points rather than a double for the same reason money is minor
  /// units: 0.14 is not representable in binary floating point, and a tax line
  /// that is one piastre off on every ticket is a real reconciliation problem.
  Money percentBp(int basisPoints) =>
      copyWith(minor: roundHalfUp(minor * basisPoints, 10000));

  /// The tax **already inside** this amount, at [basisPoints].
  ///
  /// Where [percentBp] adds a rate on top, this takes one out: 114.00 holding
  /// 14% contains 14.00, not 15.96. The formula is `gross × rate ÷ (10000 +
  /// rate)`, and it is a separate method rather than a flag on [percentBp]
  /// because the two are different arithmetic and a caller that picked the
  /// wrong one would be out by the square of the rate — an error small enough
  /// to survive a spot check and large enough to matter over a month.
  ///
  /// Rounded half-up, once, exactly like [percentBp].
  Money taxWithinBp(int basisPoints) => copyWith(
    minor: roundHalfUp(minor * basisPoints, 10000 + basisPoints),
  );

  Money _combine(Money other, int result) {
    assert(
      other.currency == currency && other.exponent == exponent,
      'Refusing to combine $currency with ${other.currency} — '
      'mixing currencies in one ticket is a bug, not a rounding question.',
    );
    return copyWith(minor: result);
  }

  Money copyWith({int? minor}) =>
      Money(minor ?? this.minor, currency: currency, exponent: exponent);

  Money clampToZero() => minor < 0 ? copyWith(minor: 0) : this;

  /// The major-unit projection, for display and for the `decimal:2` column the
  /// server still keeps. Not used for arithmetic.
  String format({bool withCurrency = false}) {
    final negative = minor < 0;
    final magnitude = negative ? -minor : minor;
    final whole = magnitude ~/ _scale;
    final fraction = magnitude % _scale;

    final buffer = StringBuffer();
    if (negative) buffer.write('-');
    buffer.write(_group(whole));
    if (exponent > 0) {
      buffer
        ..write('.')
        ..write(fraction.toString().padLeft(exponent, '0'));
    }
    if (withCurrency) {
      buffer
        ..write(' ')
        ..write(currency);
    }
    return buffer.toString();
  }

  static String _group(int value) {
    final digits = value.toString();
    if (digits.length <= 3) return digits;

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minor == minor &&
      other.currency == currency &&
      other.exponent == exponent;

  @override
  int get hashCode => Object.hash(minor, currency, exponent);

  @override
  String toString() => '${format()} $currency';
}
