import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/core/text/digits.dart';
import 'package:shared_module/core/ui/widgets/fold_digits_formatter.dart';

/// XORD-004 — Arabic digits in phone and price entry.
void main() {
  group('foldDigits', () {
    test('the QA table', () {
      expect(foldDigits('٠١٠١٢٣٤٥٦٧٨'), '01012345678');
      expect(foldDigits('١٢٥٠'), '1250');
      expect(foldDigits('١٢٥٫٥٠'), '125.50');
      expect(foldDigits('١٢3٤٥'), '12345', reason: 'mixed script');
    });

    test('Persian digits fold too', () {
      expect(foldDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    });

    test('leading zeros and a leading + survive: it works on characters', () {
      expect(foldDigits('+٢٠١٠١٢٣٤٥٦٧٨'), '+201012345678');
      expect(foldDigits('٠٠٢٠١'), '00201');
    });

    test('nothing else is touched, and the length never changes', () {
      for (final s in ['abc', '', '1,250.5', '-١٢', 'ab١٢cd ٣٤', '٬٫']) {
        expect(foldDigits(s).length, s.length, reason: s);
      }
      expect(foldDigits('ab١٢cd'), 'ab12cd');
      expect(foldDigits('1,250.5'), '1,250.5');
    });

    test('the same instance comes back when there is nothing to fold', () {
      const plain = '12345';
      expect(identical(foldDigits(plain), plain), isTrue);
    });
  });

  group('parsers', () {
    test('Money reads Arabic digits, decimal mark and thousands mark', () {
      expect(Money.tryParse('١٢٥٫٥٠')?.minor, 12550);
      expect(Money.tryParse('١٢٥.٥٠')?.minor, 12550);
      expect(Money.tryParse('١٬٢٥٠')?.minor, 125000);
      expect(Money.tryParse('١٢٥٠')?.minor, 125000);
    });

    test('Money still refuses what is not a number', () {
      expect(Money.tryParse('١٢أ'), isNull);
      expect(Money.tryParse('١.٢.٣'), isNull);
      expect(Money.tryParse(''), isNull);
    });

    test('Quantity reads Arabic digits and refuses a thousands mark', () {
      expect(Quantity.tryParse('١٢٫٥')?.milli, 12500);
      expect(Quantity.tryParse('١٬٢٥٠'), isNull,
          reason: 'ambiguous for a quantity: refused, not reinterpreted');
    });
  });

  group('FoldDigitsFormatter', () {
    const formatter = FoldDigitsFormatter();

    TextEditingValue format(String text, {int? caret}) =>
        formatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: caret ?? text.length),
          ),
        );

    test('folds as it is typed, and the caret does not move', () {
      final out = format('١٢٣٤', caret: 2);
      expect(out.text, '1234');
      expect(out.selection, const TextSelection.collapsed(offset: 2));
    });

    test('a selection and a composing range are carried over', () {
      final out = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'x٣٤y',
          selection: TextSelection(baseOffset: 1, extentOffset: 3),
          composing: TextRange(start: 1, end: 3),
        ),
      );
      expect(out.text, 'x34y');
      expect(out.selection, const TextSelection(baseOffset: 1, extentOffset: 3));
      expect(out.composing, const TextRange(start: 1, end: 3));
    });

    testWidgets('in a numeric field the Arabic key is not dropped', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              inputFormatters: [
                const FoldDigitsFormatter(),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '١٢٥٫٥٠');
      expect(controller.text, '125.50');

      // Paste over the middle of what is there: mixed script, still ASCII.
      await tester.enterText(find.byType(TextField), '١٢3٤٥');
      expect(controller.text, '12345');
    });
  });
}
