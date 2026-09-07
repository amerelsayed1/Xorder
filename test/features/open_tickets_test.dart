import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/ticket.dart';

import '../support/fakes.dart';

Product _burger() => const Product(
      id: 101,
      categoryId: 1,
      nameEn: 'Burger',
      price: Money(9500),
    );

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
  });

  Ticket seatAndRing() {
    final tickets = container.read(ticketProvider.notifier);
    tickets.attachTable(const DiningTable(id: 12, label: 'T12', seats: 4));
    tickets.addProduct(_burger(), quantity: 2);
    return container.read(ticketProvider);
  }

  test('park → resume round-trips the exact ticket, id included', () {
    final ticket = seatAndRing();
    final open = container.read(openTicketsProvider.notifier);

    open.park(ticket);
    // Resuming must hand back the SAME transaction: the parked ticket is the
    // sale in progress, and a new id on resume would make its settlement a
    // different sale to the server's idempotency.
    final resumed = open.at(12);
    expect(resumed, isNotNull);
    expect(resumed!.id, ticket.id);
    expect(resumed.lines, hasLength(1));

    container.read(ticketProvider.notifier).adopt(resumed);
    expect(container.read(ticketProvider).id, ticket.id);
  });

  test('an empty or unseated ticket cannot hold a table', () {
    final open = container.read(openTicketsProvider.notifier);

    // Unseated with lines.
    final tickets = container.read(ticketProvider.notifier);
    tickets.setOrderType(OrderType.takeaway);
    tickets.addProduct(_burger());
    open.park(container.read(ticketProvider));
    expect(container.read(openTicketsProvider), isEmpty);
  });

  test('settlement frees the table; settling a free table is a no-op', () {
    final ticket = seatAndRing();
    final open = container.read(openTicketsProvider.notifier);
    open.park(ticket);
    expect(container.read(openTicketsProvider), hasLength(1));

    open.settle(12);
    expect(container.read(openTicketsProvider), isEmpty);

    open.settle(12);
    open.settle(null);
    expect(container.read(openTicketsProvider), isEmpty);
  });
}
