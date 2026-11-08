import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/floor_overlay.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

Product _burger() => const Product(
      id: 101,
      categoryId: 1,
      nameEn: 'Burger',
      price: Money(9500),
    );

Ticket _seatedTicket({int tableId = 12, bool withTender = false}) {
  var ticket = Ticket(id: 'txn-1', orderType: OrderType.dineIn);
  ticket = TicketEngine.attachTable(ticket, tableId, 'T$tableId', guests: 2);
  ticket = TicketEngine.addLine(ticket, _burger(), quantity: 2).ticket!;
  if (withTender) {
    ticket = TicketEngine.addTender(
      ticket,
      typeId: 1,
      label: 'Cash',
      amount: const Money(1000),
    ).ticket!;
  }
  return ticket;
}

const _floor = [
  DiningTable(id: 12, label: 'T12', seats: 4),
  DiningTable(id: 13, label: 'T13', seats: 2),
];

void main() {
  test('a parked ticket turns its table busy with count and total', () {
    final overlaid = overlayOpenTickets(_floor, {12: _seatedTicket()});

    final busy = overlaid.firstWhere((t) => t.id == 12);
    expect(busy.state, TableState.open);
    expect(busy.openLineCount, 2);
    expect(busy.openTotal, isNotNull);
    expect(busy.openTotal!.minor, greaterThan(0));

    // The neighbour is untouched — free, no invented totals.
    final free = overlaid.firstWhere((t) => t.id == 13);
    expect(free.state, TableState.free);
    expect(free.openTotal, isNull);
  });

  test('a ticket with money against it reads as bill-in-progress', () {
    final overlaid =
        overlayOpenTickets(_floor, {12: _seatedTicket(withTender: true)});
    expect(overlaid.first.state, TableState.billAsked);
  });

  test('an empty overlay changes nothing', () {
    final overlaid = overlayOpenTickets(_floor, const {});
    expect(overlaid, hasLength(2));
    expect(overlaid.every((t) => t.state == TableState.free), isTrue);
  });
}
