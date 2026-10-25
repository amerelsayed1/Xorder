/// How much of something, when "how much" is not a whole number.
///
/// **Sales quantities are integers and purchases are not.** A cashier sells two
/// grills; a restaurant buys 12.5 kg of chicken and 0.75 litres of oil. The
/// ticket has never needed a fraction and should not grow one — but the moment
/// purchasing exists, so does the question, and answering it with a `double`
/// would put binary floating point directly upstream of every cost price, every
/// stock valuation and every margin the reports will eventually show.
///
/// So a quantity is an **integer of thousandths**, exactly as [Money] is an
/// integer of minor units, and for exactly the same reason. 12.5 kg is 12500.
/// Three decimal places is what a kitchen scale reads and what a supplier's
/// docket says; nobody buys a microgram.
///
/// **There is no unit conversion here, deliberately.** A quantity in kilograms
/// and one in grams do not add, and this refuses rather than converting: a
/// product is bought in one unit, and a system that silently turned 500 g into
/// 0.5 kg would eventually turn 500 boxes into half a something.
library;

import '../text/digits.dart';
import 'rounding.dart';

/// What a quantity is counted in.
///
/// **A code, not a closed list.** The seven below are the units every
/// restaurant starts with (migration 39 seeds them), and the back office can
/// add its own — a sack, a tray of thirty. A code this build has never seen is
/// kept as that code rather than read as "each": "1 of something" was the old
/// fallback, and on a unit the restaurant added on purpose it is simply wrong.
///
/// Still a label rather than a conversion table. See the library note.
class QuantityUnit {
  const QuantityUnit(this.wire);

  static const each = QuantityUnit('ea');
  static const kilogram = QuantityUnit('kg');
  static const gram = QuantityUnit('g');
  static const litre = QuantityUnit('l');
  static const millilitre = QuantityUnit('ml');
  static const box = QuantityUnit('box');
  static const pack = QuantityUnit('pack');

  /// The built-in seven, in the order the back office lists them.
  static const values = [each, kilogram, gram, litre, millilitre, box, pack];

  final String wire;

  bool get isBuiltIn => values.contains(this);

  /// Nothing recorded reads as [each] — a row older than units reads as one
  /// of something, which is what it always meant. Anything else is kept.
  static QuantityUnit fromWire(String? value) {
    final code = value?.trim();
    if (code == null || code.isEmpty) return each;
    return QuantityUnit(code);
  }

  @override
  bool operator ==(Object other) => other is QuantityUnit && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => wire;
}

class Quantity {
  const Quantity(this.milli, {this.unit = QuantityUnit.each});

  static const zero = Quantity(0);

  /// A whole number of things — the common case, and the one that must not
  /// require the caller to think in thousandths.
  const Quantity.of(int count, {QuantityUnit unit = QuantityUnit.each})
    : this(count * 1000, unit: unit);

  /// Thousandths. 12.5 kg is 12500.
  final int milli;

  final QuantityUnit unit;

  bool get isZero => milli == 0;
  bool get isNegative => milli < 0;

  /// Whether this is a whole number of units, for a screen that would rather
  /// print "2" than "2.000".
  bool get isWhole => milli % 1000 == 0;

  Quantity operator +(Quantity other) => Quantity(milli + _same(other), unit: unit);
  Quantity operator -(Quantity other) => Quantity(milli - _same(other), unit: unit);

  bool operator <(Quantity other) => milli < _same(other);
  bool operator >(Quantity other) => milli > _same(other);
  bool operator <=(Quantity other) => milli <= _same(other);
  bool operator >=(Quantity other) => milli >= _same(other);

  int _same(Quantity other) {
    assert(
      other.unit == unit,
      'Refusing to combine ${unit.wire} with ${other.unit.wire} — '
      'a quantity in one unit and a quantity in another are not the same '
      'question, and converting them silently is how 500 boxes becomes half a '
      'something.',
    );
    return other.milli;
  }

  /// What this much costs at [unitCostMinor] each.
  ///
  /// **The single rounding point for a purchase line**, half-up, exactly as
  /// the VAT line is for a sale. 12.5 kg at 47.30 is 591.25, which rounds to
  /// 591.25 — but 0.333 kg at 47.30 is 15.7509, and where that lands has to be
  /// decided once, here, rather than wherever somebody happened to multiply.
  int costAt(int unitCostMinor) => roundHalfUp(milli * unitCostMinor, 1000);

  /// As a decimal string, trimmed: 2000 → "2", 12500 → "12.5".
  ///
  /// Trailing zeroes are dropped because a docket says 12.5 kg and not 12.500,
  /// and a screen that padded them would look like a precision nobody claimed.
  String format() {
    final negative = milli < 0;
    final whole = milli.abs() ~/ 1000;
    final fraction = milli.abs() % 1000;
    final sign = negative ? '-' : '';
    if (fraction == 0) return '$sign$whole';
    final digits = fraction.toString().padLeft(3, '0').replaceAll(
      RegExp(r'0+$'),
      '',
    );
    return '$sign$whole.$digits';
  }

  /// Parses what somebody typed. Null on anything that is not a number, never
  /// a throw and never a `double` — the string is split on the point and each
  /// half read as an integer.
  static Quantity? tryParse(
    String input, {
    QuantityUnit unit = QuantityUnit.each,
  }) {
    final trimmed = foldDigits(input).trim();
    if (trimmed.isEmpty) return null;

    final negative = trimmed.startsWith('-');
    final body = negative ? trimmed.substring(1) : trimmed;
    final parts = body.split('.');
    if (parts.length > 2) return null;

    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
    if (whole == null || whole < 0) return null;

    var fraction = 0;
    if (parts.length == 2) {
      // More than three decimals is not a rounding question, it is somebody
      // typing something this cannot represent. Refused rather than truncated.
      if (parts[1].isEmpty || parts[1].length > 3) return null;
      final read = int.tryParse(parts[1]);
      if (read == null || read < 0) return null;
      fraction = read * (parts[1].length == 1 ? 100 : (parts[1].length == 2 ? 10 : 1));
    }

    final milli = whole * 1000 + fraction;
    return Quantity(negative ? -milli : milli, unit: unit);
  }

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.milli == milli && other.unit == unit;

  @override
  int get hashCode => Object.hash(milli, unit);

  @override
  String toString() => '${format()} ${unit.wire}';
}
