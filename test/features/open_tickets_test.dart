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

  Ticket ringUpTakeaway() {
    final tickets = container.read(ticketProvider.notifier);
    tickets.setOrderType(OrderType.takeaway);
    tickets.addProduct(_burger());
    return container.read(ticketProvider);
  }

  test('park → resume round-trips the exact ticket, id included', () async {
    final ticket = seatAndRing();
    final open = container.read(openTicketsProvider.notifier);

    expect(await open.park(ticket), isTrue);
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

  test('an unseated ticket is held, not dropped on the floor', () async {
    // The bug this suite used to assert *for*: `park` returned early on a null
    // table, so a takeaway could not be put down at all and therefore survived
    // nothing — not a restart, not a cashier who had to serve somebody else.
    final ticket = ringUpTakeaway();
    final open = container.read(openTicketsProvider.notifier);

    expect(await open.park(ticket), isTrue);

    expect(container.read(openTicketsProvider).onTables, isEmpty);
    expect(container.read(openTicketsProvider).held, hasLength(1));
    expect(container.read(openTicketsProvider).held.single.id, ticket.id);
  });

  test('an empty ticket is not held — there is nothing to come back to', () async {
    container.read(ticketProvider.notifier).setOrderType(OrderType.takeaway);
    expect(
      await container
          .read(openTicketsProvider.notifier)
          .park(container.read(ticketProvider)),
      isTrue,
    );

    expect(container.read(openTicketsProvider).isEmpty, isTrue);
  });

  test('parking a held ticket again replaces it rather than doubling it', () async {
    final open = container.read(openTicketsProvider.notifier);
    final first = ringUpTakeaway();
    expect(await open.park(first), isTrue);

    // Resumed, one more item rung up, put down again — the same sale.
    container.read(ticketProvider.notifier).adopt(first);
    container.read(ticketProvider.notifier).addProduct(_burger());
    expect(await open.park(container.read(ticketProvider)), isTrue);

    final held = container.read(openTicketsProvider).held;
    expect(held, hasLength(1));
    expect(held.single.id, first.id);
    expect(held.single.lines.single.quantity, 2);
  });

  test('the live ticket is not offered back to itself', () async {
    final open = container.read(openTicketsProvider.notifier);
    final ticket = ringUpTakeaway();
    expect(await open.park(ticket), isTrue);

    // A resumed hold keeps its parked row until it is paid, so it is still
    // held while it is on screen. It must not be listed as something to resume.
    expect(container.read(openTicketsProvider).heldOtherThan(ticket.id), isEmpty);
    expect(
      container.read(openTicketsProvider).heldOtherThan('another-txn'),
      hasLength(1),
    );
  });

  test('settlement frees the table; settling a free table is a no-op', () async {
    final ticket = seatAndRing();
    final open = container.read(openTicketsProvider.notifier);
    expect(await open.park(ticket), isTrue);
    expect(container.read(openTicketsProvider).onTables, hasLength(1));

    await open.settle(ticket);
    expect(container.read(openTicketsProvider).isEmpty, isTrue);

    await open.settle(ticket);
    expect(container.read(openTicketsProvider).isEmpty, isTrue);
  });

  test('settling a held ticket lets go of it', () async {
    final open = container.read(openTicketsProvider.notifier);
    final ticket = ringUpTakeaway();
    expect(await open.park(ticket), isTrue);

    await open.settle(ticket);
    expect(container.read(openTicketsProvider).held, isEmpty);
  });

  test('a ticket that lost its table on the way still releases its row', () async {
    // Switching a seated order to takeaway clears the table (`setOrderType`),
    // so the ticket that reaches settlement no longer names the row it left
    // behind. Matching on the transaction id as well is what stops that row
    // coming back on the floor as a bill nobody owes.
    final open = container.read(openTicketsProvider.notifier);
    final seated = seatAndRing();
    expect(await open.park(seated), isTrue);

    container.read(ticketProvider.notifier).setOrderType(OrderType.takeaway);
    await open.settle(container.read(ticketProvider));

    expect(container.read(openTicketsProvider).isEmpty, isTrue);
  });
}
