import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

/// What the open tickets come to, for the close-shift warning (S3-5).
///
/// Each ticket's total as it would be charged — service and VAT included,
/// rounded once per charge line as everywhere else — then added up. The
/// figure a manager sees before closing over parked work has to be the figure
/// those tickets will settle for, or it is a different number from the one
/// the drawer will see tomorrow.
void main() {
  const grill = Product(
    id: 101,
    categoryId: 1,
    nameEn: 'Mixed Grill',
    price: Money(38500),
  );
  const drink = Product(
    id: 501,
    categoryId: 5,
    nameEn: 'Soft Drink',
    price: Money(2500),
  );

  Ticket onTable() => TicketEngine.addLine(
    Ticket(
      id: 'on-table',
      orderType: OrderType.dineIn,
      tableId: 4,
      tableLabel: 'T4',
    ),
    grill,
  ).ticket!;

  Ticket held() => TicketEngine.addLine(
    Ticket(id: 'held', orderType: OrderType.takeaway),
    drink,
  ).ticket!;

  test('nothing open comes to nothing', () {
    expect(TicketEngine.totalOf(const []), Money.zero);
  });

  test('each ticket counts at what it would be charged', () {
    // Dine-in: 385.00 + 12% service = 431.20, + 14% VAT (60.368 → 60.37)
    // = 491.57. Takeaway: 25.00 + 14% VAT = 28.50. No service on takeaway.
    expect(onTable().totals.total.minor, 49157);
    expect(held().totals.total.minor, 2850);
    expect(TicketEngine.totalOf([onTable(), held()]).minor, 52007);
  });

  test('is the sum, however the tickets arrive', () {
    final both = TicketEngine.totalOf([held(), onTable()]);
    expect(both.minor, 52007);
    expect(TicketEngine.totalOf([held(), held(), held()]).minor, 8550);
  });
}
