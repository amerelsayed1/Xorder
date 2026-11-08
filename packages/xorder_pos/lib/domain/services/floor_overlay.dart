import '../models/dining_table.dart';
import '../models/ticket.dart';

/// Lay the till's parked tickets over the floor plan.
///
/// This is the single-terminal floor truth: a table is busy because THIS till
/// parked a ticket on it. Multi-till consistency — two terminals refusing to
/// double-seat one table — is the branch server's whole reason to exist and is
/// deliberately not faked here; a cloud till shows its own seating, honestly.
///
/// Pure, so the mapping is testable without a widget tree or a database:
/// a parked ticket with tenders is a bill in progress (`billAsked` styling),
/// one without is simply open, and the tile carries the running item count
/// and total the cashier glances at on the way past.
List<DiningTable> overlayOpenTickets(
  List<DiningTable> tables,
  Map<int, Ticket> open,
) => [
  for (final table in tables)
    if (open[table.id] case final ticket?)
      DiningTable(
        id: table.id,
        label: table.label,
        seats: table.seats,
        state: ticket.tenders.isNotEmpty
            ? TableState.billAsked
            : TableState.open,
        openLineCount: ticket.lines.fold(
          0,
          (count, line) => count + line.quantity,
        ),
        openTotal: ticket.totals.total,
        areaName: table.areaName,
      )
    else
      table,
];
