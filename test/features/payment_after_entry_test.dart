import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/payment/payment_screen.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import '../support/fakes.dart';

/// What the typed amount leaves, shown BEFORE Collect.
///
/// The change due appeared only on the receipt after the sale; a cashier
/// counting out a note had to press Collect to learn how much to hand back.
void main() {
  late WidgetRef ref;

  Future<void> atPayment(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

  Finder line() => find.byKey(const Key('payment-after-entry'));
  String amount(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('payment-after-entry-amount')))
      .data!;

  testWidgets('nothing typed, or exactly the due: no line', (tester) async {
    await atPayment(tester);
    expect(line(), findsNothing);

    await tester.tap(find.text('Exact'));
    await tester.pump();
    expect(line(), findsNothing);
  });

  testWidgets('more than the due shows the change to give back', (tester) async {
    await atPayment(tester);
    final due = ref.read(ticketProvider).totals.due;

    await tester.tap(find.text('1000'));
    await tester.pump();

    expect(line(), findsOneWidget);
    expect(find.descendant(of: line(), matching: find.text('CHANGE DUE')),
        findsOneWidget);
    expect(amount(tester), (Money(100000) - due).format(withCurrency: true));
  });

  testWidgets('less than the due shows what is still owed', (tester) async {
    await atPayment(tester);
    final due = ref.read(ticketProvider).totals.due;

    // A one-unit entry, typed on the keypad.
    await tester.tap(
      find.descendant(
        of: find.byType(PaymentScreen),
        matching: find.text('1'),
      ),
    );
    await tester.pump();

    expect(line(), findsOneWidget);
    expect(find.descendant(of: line(), matching: find.text('REMAINING DUE')),
        findsOneWidget);
    expect(amount(tester), (due - Money(100)).format(withCurrency: true));
  });
}
