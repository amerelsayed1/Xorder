import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/payment/payment_screen.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import '../support/fakes.dart';

/// The physical keyboard on the payment screen. It was ignored: the amount
/// could only be built from the on-screen keypad.
void main() {
  Future<void> atPayment(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeRepositoryOverrides(),
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return SaleScreen(
                onLock: () {},
                onTables: () {},
                onOrders: () {},
                onCloseShift: () {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    ref.read(ticketProvider.notifier).setOrderType(OrderType.takeaway);
    await tester.tap(find.text('Soft Drink'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentScreen), findsOneWidget);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  testWidgets('digits, the numpad and a point build the amount; Backspace and '
      'Delete take it back', (tester) async {
    await atPayment(tester);

    await press(tester, LogicalKeyboardKey.digit2);
    await press(tester, LogicalKeyboardKey.numpad5);
    await press(tester, LogicalKeyboardKey.period);
    await press(tester, LogicalKeyboardKey.period); // a second point is ignored
    await press(tester, LogicalKeyboardKey.digit5);
    expect(find.text('25.5 EGP'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.backspace);
    expect(find.text('25. EGP'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.delete);
    expect(find.text('25. EGP'), findsNothing);
    expect(find.text('25.5 EGP'), findsNothing);
    expect(find.byKey(const Key('payment-after-entry')), findsNothing);
  });

  test('an Arabic layout\'s digit keys mean the digit they typed, whatever '
      'logical key they report', () {
    // With an Arabic layout on, the digit row reports the Arabic digit's own
    // logical key and character, not `digit5`.
    final arabicFive = LogicalKeyboardKey(0x0665);
    expect(amountDigitFor('٥', arabicFive), '5');
    expect(amountDigitFor('۷', arabicFive), '7'); // Persian
    expect(amountDigitFor('5', LogicalKeyboardKey.digit5), '5');
    // No character (some platforms): the key still says it.
    expect(amountDigitFor(null, LogicalKeyboardKey.numpad3), '3');
    // Letters and punctuation are not digits.
    expect(amountDigitFor('a', LogicalKeyboardKey.keyA), isNull);
  });

  testWidgets('Enter collects, as the green button does', (tester) async {
    await atPayment(tester);

    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(PaymentScreen), findsNothing,
        reason: 'the sale settled and the dialog closed');
  });

  testWidgets('keys typed into the reference box do not also land in the '
      'amount', (tester) async {
    await atPayment(tester);
    await tester.tap(find.text('Card').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextField, 'Authorisation / reference'));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.digit7);

    expect(find.text('7 EGP'), findsNothing);
    expect(find.byKey(const Key('payment-after-entry')), findsNothing);
  });
}
