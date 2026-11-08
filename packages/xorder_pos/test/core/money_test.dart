import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/currency.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/rounding.dart';

void main() {
  group('roundHalfUp', () {
    test('rounds .5 up, not to even', () {
      // The server rounds half-up; banker's rounding here would put the tax
      // line one piastre out on roughly half of all tickets.
      expect(roundHalfUp(5, 10), 1);
      expect(roundHalfUp(15, 10), 2);
      expect(roundHalfUp(25, 10), 3);
    });

    test('rounds below .5 down', () {
      expect(roundHalfUp(4, 10), 0);
      expect(roundHalfUp(14, 10), 1);
    });

    test('mirrors exactly for negatives, so a refund reverses a sale', () {
      expect(roundHalfUp(-5, 10), -1);
      expect(roundHalfUp(-15, 10), -2);
      expect(roundHalfUp(-4, 10), 0);
    });
  });

  group('Money.tryParse', () {
    test('parses major units without touching a double', () {
      expect(Money.tryParse('1338.68')?.minor, 133868);
      expect(Money.tryParse('0.05')?.minor, 5);
      expect(Money.tryParse('7')?.minor, 700);
      expect(Money.tryParse('.5')?.minor, 50);
    });

    test('strips thousands separators the cashier may paste', () {
      expect(Money.tryParse('1,338.68')?.minor, 133868);
    });

    test('truncates excess precision rather than rounding it up', () {
      // Rounding a typo upward would silently overcharge.
      expect(Money.tryParse('1.999')?.minor, 199);
    });

    test('honours a three-decimal currency', () {
      final kwd = Money.tryParse('1.234', currency: 'KWD', exponent: 3);
      expect(kwd?.minor, 1234);
      expect(kwd?.format(), '1.234');
    });

    test('returns null on junk instead of throwing', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.2.3'), isNull);
    });
  });

  group('arithmetic', () {
    test('multiplies by quantity exactly', () {
      expect((const Money(38500) * 3).minor, 115500);
    });

    test('applies a basis-point rate with half-up rounding', () {
      // 385.00 at 12% = 46.20 exactly.
      expect(const Money(38500).percentBp(1200).minor, 4620);
      // 0.01 at 14% = 0.0014 → rounds to 0.00.
      expect(const Money(1).percentBp(1400).minor, 0);
      // 0.04 at 14% = 0.0056 → rounds to 0.01.
      expect(const Money(4).percentBp(1400).minor, 1);
    });

    test('never yields a negative due once clamped', () {
      expect(const Money(-500).clampToZero().minor, 0);
      expect(const Money(500).clampToZero().minor, 500);
    });
  });

  group('format', () {
    test('groups thousands and pads the fraction', () {
      expect(const Money(133868).format(), '1,338.68');
      expect(const Money(5).format(), '0.05');
      expect(const Money(100000000).format(), '1,000,000.00');
    });

    test('keeps the sign in front', () {
      expect(const Money(-133868).format(), '-1,338.68');
    });
  });

  group('currencyExponent', () {
    test('knows the three-decimal currencies the server supports', () {
      for (final code in ['KWD', 'BHD', 'OMR', 'JOD']) {
        expect(currencyExponent(code), 3, reason: '$code has three decimals');
      }
      for (final code in ['EGP', 'SAR', 'AED', 'USD']) {
        expect(currencyExponent(code), 2);
      }
    });
  });
}
