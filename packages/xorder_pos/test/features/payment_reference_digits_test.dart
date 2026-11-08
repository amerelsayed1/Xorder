import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/payment/payment_screen.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The authorisation / reference box on the payment screen (XORD-004 follow-up).
///
/// A cashier on an Arabic keyboard typed `١١١٥٨…` into it, and the code was
/// stored and shown that way — so searching for the same code with Western
/// digits found nothing. The box folds digits as they are typed, like the
/// amount and phone fields.
void main() {
  testWidgets('Arabic-Indic and Persian digits typed in the reference become '
      'ASCII; letters survive', (tester) async {
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

    // Card is a method that asks for a reference.
    await tester.tap(find.text('Card').first);
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, 'Authorisation / reference');
    expect(field, findsOneWidget);

    await tester.enterText(field, '١١١٥٨٤٨٩ab۱۲۳');
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, '11158489ab123');
  });
}
