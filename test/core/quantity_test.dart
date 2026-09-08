import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/quantity.dart';

/// How much of something, when "how much" is not a whole number.
///
/// This type exists so that no cost price is ever computed from a `double`.
/// Sales quantities are integers; purchases are 12.5 kg of chicken, and a
/// float there would sit directly upstream of every margin the reports will
/// eventually show.
void main() {
  group('thousandths, like Money is minor units', () {
    test('a whole number does not make the caller think in thousandths', () {
      expect(const Quantity.of(2).milli, 2000);
      expect(const Quantity.of(2).isWhole, isTrue);
    });

    test('a fraction is exact', () {
      expect(const Quantity(12500, unit: QuantityUnit.kilogram).milli, 12500);
      expect(const Quantity(12500).isWhole, isFalse);
    });

    test('zero is zero either way', () {
      expect(Quantity.zero.isZero, isTrue);
      expect(const Quantity.of(0).isZero, isTrue);
    });
  });

  group('what a line costs', () {
    test('a whole quantity is exact', () {
      // 2 at 47.30 is 94.60, and nothing rounds.
      expect(const Quantity.of(2).costAt(4730), 9460);
    });

    test('a fractional one rounds once, half-up', () {
      // 0.333 kg at 47.30 is 15.7509 → 15.75.
      expect(const Quantity(333).costAt(4730), 1575);
      // 0.5 at 47.35 is 23.675 → 23.68, not 23.67.
      expect(const Quantity(500).costAt(4735), 2368);
    });

    test('zero of something costs nothing', () {
      expect(Quantity.zero.costAt(4730), 0);
    });

    test('it never goes through a double', () {
      // 0.1 + 0.2 in binary floating point is 0.30000000000000004. Three lots
      // of 0.1 kg at 33.33 is 9.999, which must land on 10.00 and not on
      // 9.99 — the arithmetic here is integer end to end.
      expect(const Quantity(100).costAt(3333) * 3, 333 * 3);
      expect(const Quantity(300).costAt(3333), 1000);
    });
  });

  group('arithmetic refuses to convert', () {
    test('same units add', () {
      const a = Quantity(1500, unit: QuantityUnit.kilogram);
      const b = Quantity(2500, unit: QuantityUnit.kilogram);
      expect((a + b).milli, 4000);
      expect((b - a).milli, 1000);
    });

    test('and compare', () {
      expect(const Quantity(1500) < const Quantity(2500), isTrue);
      expect(const Quantity(2500) >= const Quantity(2500), isTrue);
    });

    test('mixing units is an assertion, not a conversion', () {
      // A system that silently turned 500 g into 0.5 kg would eventually turn
      // 500 boxes into half a something.
      const kilos = Quantity(1000, unit: QuantityUnit.kilogram);
      const grams = Quantity(1000, unit: QuantityUnit.gram);
      expect(() => kilos + grams, throwsA(isA<AssertionError>()));
    });
  });

  group('showing it', () {
    test('a whole number prints without decimals', () {
      // A docket says 2 kg, not 2.000.
      expect(const Quantity.of(2).format(), '2');
    });

    test('a fraction prints only the digits it has', () {
      expect(const Quantity(12500).format(), '12.5');
      expect(const Quantity(12050).format(), '12.05');
      expect(const Quantity(12345).format(), '12.345');
    });

    test('less than one keeps its leading zero', () {
      expect(const Quantity(750).format(), '0.75');
    });

    test('negative survives the round trip', () {
      expect(const Quantity(-1500).format(), '-1.5');
    });

    test('it carries its unit when asked for the whole thing', () {
      expect(
        const Quantity(12500, unit: QuantityUnit.kilogram).toString(),
        '12.5 kg',
      );
    });
  });

  group('parsing what somebody typed', () {
    test('whole numbers and fractions', () {
      expect(Quantity.tryParse('2')!.milli, 2000);
      expect(Quantity.tryParse('12.5')!.milli, 12500);
      expect(Quantity.tryParse('0.75')!.milli, 750);
      expect(Quantity.tryParse('12.345')!.milli, 12345);
    });

    test('a lone fraction', () {
      expect(Quantity.tryParse('.5')!.milli, 500);
    });

    test('whitespace is trimmed', () {
      expect(Quantity.tryParse('  12.5  ')!.milli, 12500);
    });

    test('garbage is null, never a throw', () {
      for (final input in ['', 'abc', '1.2.3', '1.', '--1', '1e3']) {
        expect(Quantity.tryParse(input), isNull, reason: input);
      }
    });

    test('more than three decimals is refused, not truncated', () {
      // Not a rounding question — somebody typed something this cannot hold,
      // and quietly dropping a digit is how a stock count goes wrong by a
      // margin nobody can find.
      expect(Quantity.tryParse('1.2345'), isNull);
    });

    test('it carries the unit it was given', () {
      final read = Quantity.tryParse('12.5', unit: QuantityUnit.kilogram)!;
      expect(read.unit, QuantityUnit.kilogram);
    });
  });

  group('units', () {
    test('round-trip', () {
      for (final unit in QuantityUnit.values) {
        expect(QuantityUnit.fromWire(unit.wire), unit);
      }
    });

    test('an unknown unit reads as each rather than throwing', () {
      // A purchase order written on a newer build must still be readable.
      expect(QuantityUnit.fromWire('dozen'), QuantityUnit.each);
      expect(QuantityUnit.fromWire(null), QuantityUnit.each);
    });
  });

  test('equality is by value and unit', () {
    expect(const Quantity(1000), const Quantity(1000));
    expect(
      const Quantity(1000),
      isNot(const Quantity(1000, unit: QuantityUnit.kilogram)),
    );
  });
}
