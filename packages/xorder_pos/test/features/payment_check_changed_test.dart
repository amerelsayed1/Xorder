import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/payment/payment_screen.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The datastore refusing the sale because the table's check moved on.
class _ChangedElsewhere extends FakeOrdersRepository {
  @override
  Future<SubmitOrderResult> submit(
    Ticket ticket, {
    PosStaff? servedBy,
    int? parkedVersion,
  }) async => throw CheckChangedElsewhere(ticket.tableId!);
}

/// XORD-045 at the till: paying a check another till changed since.
///
/// The refusal itself is proven against PostgreSQL in
/// `parked_tickets_schema_test.dart` ("paying it"); this is what the cashier
/// sees — the payment is not taken, the tender comes back off, and the screen
/// says why in words a cashier can act on.
void main() {
  testWidgets('a refused payment says the table changed and takes nothing',
      (tester) async {
    late WidgetRef ref;
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(),
          ordersRepositoryProvider.overrideWithValue(_ChangedElsewhere()),
        ],
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return SaleScreen(onLock: () {}, onTables: () {}, onOrders: () {});
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    ref.read(signedInStaffProvider.notifier).signIn(
          const PosStaff(
            id: 2,
            name: 'Rana A.',
            username: 'rana',
            role: FakeSessionRepository.cashier,
          ),
        );
    ref
        .read(ticketProvider.notifier)
        .attachTable(const DiningTable(id: 12, label: 'T12', seats: 4));
    await tester.tap(find.text('Soft Drink'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentScreen), findsOneWidget);

    // Enter with nothing typed tenders the whole amount due and settles.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(PaymentScreen), findsOneWidget, reason: 'not settled');
    expect(find.textContaining('Table T12 was changed on another till'),
        findsOneWidget);
    expect(ref.read(ticketProvider).tenders, isEmpty,
        reason: 'the tender is put back off');
    expect(ref.read(ticketProvider).lines, hasLength(1));
  });
}
