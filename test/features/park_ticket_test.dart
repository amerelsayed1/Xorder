import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import '../support/fakes.dart';

/// The three-pane shell only exists above 1100dp, and the cart — where Park
/// lives — is only drawn there and in the medium shell.
const _desktop = Size(1440, 900);

Future<ProviderContainer> _pumpTill(WidgetTester tester) async {
  tester.view
    ..physicalSize = _desktop
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: fakeRepositoryOverrides());
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildPosTheme(),
        home: SaleScreen(
          onLock: () {},
          onTables: () {},
          onOrders: () {},
          onCloseShift: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// A takeaway with one line on it — the ticket that could never be parked.
void _ringUpTakeaway(ProviderContainer container) {
  final tickets = container.read(ticketProvider.notifier);
  tickets.setOrderType(OrderType.takeaway);
  tickets.addProduct(
    const Product(id: 101, categoryId: 1, nameEn: 'Burger', price: Money(9500)),
  );
}

void main() {
  testWidgets('the button labelled Park parks, and does not send a round', (
    tester,
  ) async {
    final container = await _pumpTill(tester);
    _ringUpTakeaway(container);
    await tester.pumpAndSettle();

    expect(find.text('Park  F4'), findsOneWidget);
    await tester.tap(find.text('Park  F4'));
    await tester.pumpAndSettle();

    expect(container.read(openTicketsProvider).held, hasLength(1));
    expect(container.read(openTicketsProvider).held.single.roundsSent, 0);
    expect(container.read(ticketProvider).isEmpty, isTrue);
  });

  testWidgets('F4 parks an unseated ticket too', (tester) async {
    final container = await _pumpTill(tester);
    _ringUpTakeaway(container);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await tester.pumpAndSettle();

    expect(container.read(openTicketsProvider).held, hasLength(1));
    expect(container.read(ticketProvider).isEmpty, isTrue);
  });

  testWidgets('F4 still sends the round on a seated ticket', (tester) async {
    final container = await _pumpTill(tester);
    final tickets = container.read(ticketProvider.notifier);
    tickets.attachTable(const DiningTable(id: 12, label: 'T12', seats: 4));
    tickets.addProduct(
      const Product(
        id: 101,
        categoryId: 1,
        nameEn: 'Burger',
        price: Money(9500),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await tester.pumpAndSettle();

    expect(container.read(ticketProvider).roundsSent, 1);
    expect(container.read(ticketProvider).isEmpty, isFalse);
  });

  testWidgets('a parked unseated ticket comes back from Held', (tester) async {
    final container = await _pumpTill(tester);
    _ringUpTakeaway(container);
    final parked = container.read(ticketProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Park  F4'));
    await tester.pumpAndSettle();

    // The counter is the only route back to a ticket with no table — there is
    // no tile for it on the floor, by design.
    expect(find.text('Held  1'), findsOneWidget);
    await tester.tap(find.text('Held  1'));
    await tester.pumpAndSettle();

    expect(find.text('Held tickets'), findsOneWidget);
    await tester.tap(find.text('Takeaway · 1 item'));
    await tester.pumpAndSettle();

    // The same transaction, not a copy: its eventual settlement has to look
    // like one sale to the server's idempotency.
    expect(container.read(ticketProvider).id, parked.id);
    expect(container.read(ticketProvider).lines, hasLength(1));
    // Still held, because the row is what makes it survive a crash between the
    // resume and the payment — but no longer offered back to itself.
    expect(find.text('Held  1'), findsNothing);
  });

  testWidgets('resuming a hold parks what was on screen first', (tester) async {
    final container = await _pumpTill(tester);
    _ringUpTakeaway(container);
    final first = container.read(ticketProvider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Park  F4'));
    await tester.pumpAndSettle();

    // A second walk-in, rung up and left on screen.
    _ringUpTakeaway(container);
    final second = container.read(ticketProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Held  1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Takeaway · 1 item'));
    await tester.pumpAndSettle();

    expect(container.read(ticketProvider).id, first.id);
    expect(
      container.read(openTicketsProvider).held.map((t) => t.id),
      containsAll([first.id, second.id]),
      reason: 'a resume that discarded the live ticket would lose a sale',
    );
  });
}
