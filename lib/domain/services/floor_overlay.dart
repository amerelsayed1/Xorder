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
        sortOrder: table.sortOrder,
        guestCount: ticket.guestCount,
        seatedAt: ticket.seatedAt,
        lastSentAt: ticket.lastSentAt,
        hasUnsentDraft: ticket.hasDraft,
      )
    else
      table,
];

/// A section of the floor — one tab on the floor screen.
class FloorSection {
  const FloorSection({required this.name, required this.tables});

  /// Null for the unnamed main room.
  final String? name;
  final List<DiningTable> tables;

  int get free => tables.where((t) => t.isFree).length;
  int get busy => tables.length - free;
}

/// Split the floor into its sections, in the order the manager laid them out.
///
/// Sections appear in the order their first table does (by `sort_order`), so
/// the room the manager put first is the first tab; tables with no section
/// come last as the main room. One table per section is fine — a restaurant
/// with a single VIP table still wants it on its own tab.
List<FloorSection> floorSections(List<DiningTable> tables) {
  final named = <String, List<DiningTable>>{};
  final unnamed = <DiningTable>[];
  final sorted = [...tables]..sort(_byOrder);
  for (final table in sorted) {
    final area = table.areaName?.trim();
    if (area == null || area.isEmpty) {
      unnamed.add(table);
    } else {
      named.putIfAbsent(area, () => []).add(table);
    }
  }
  return [
    for (final entry in named.entries)
      FloorSection(name: entry.key, tables: entry.value),
    if (unnamed.isNotEmpty) FloorSection(name: null, tables: unnamed),
  ];
}

int _byOrder(DiningTable a, DiningTable b) {
  final order = a.sortOrder.compareTo(b.sortOrder);
  return order != 0 ? order : a.id.compareTo(b.id);
}

/// What a busy table needs from the floor staff right now.
///
/// Ordered by urgency so the legend and the sort can compare them.
enum TableAttention {
  /// Free, or busy and fine.
  none,

  /// Rung up but never fired: the cashier parked a draft and the kitchen has
  /// not heard of this table. Food is not coming.
  unsentRound,

  /// Nothing has gone to the kitchen in a while and nobody has asked for the
  /// bill — somebody should walk past.
  quiet,

  /// The bill was asked for and money is still outstanding past the limit.
  billWaiting,
}

/// The thresholds. One place, so a café that turns tables in twenty minutes
/// and a restaurant that seats for three hours disagree in exactly one
/// object rather than in widget code.
class FloorAttentionRules {
  const FloorAttentionRules({
    this.unsentAfter = const Duration(minutes: 3),
    this.quietAfter = const Duration(minutes: 25),
    this.billWaitingAfter = const Duration(minutes: 8),
  });

  /// Seated with a draft and nothing fired for this long.
  final Duration unsentAfter;

  /// No round to the kitchen for this long.
  final Duration quietAfter;

  /// Bill asked and still unpaid for this long.
  final Duration billWaitingAfter;

  static const defaults = FloorAttentionRules();
}

/// Judge one table against the clock.
///
/// Pure: takes `now` rather than reading it, so a test can seat a table at
/// 19:00 and ask what it looks like at 19:30 without waiting half an hour.
TableAttention attentionFor(
  DiningTable table,
  DateTime now, {
  FloorAttentionRules rules = FloorAttentionRules.defaults,
}) {
  if (table.isFree) return TableAttention.none;

  final seated = table.seatedFor(now);
  final quiet = table.quietFor(now);

  if (table.state == TableState.billAsked) {
    // The bill clock starts at the last kitchen activity, which is the best
    // proxy the ticket carries for "when they asked". A bill asked moments ago
    // is not an emergency.
    return quiet != null && quiet >= rules.billWaitingAfter
        ? TableAttention.billWaiting
        : TableAttention.none;
  }

  // A round that was never sent outranks a quiet table: a quiet table has
  // eaten, an unsent one has not been cooked for.
  if (table.hasUnsentDraft &&
      table.lastSentAt == null &&
      seated != null &&
      seated >= rules.unsentAfter) {
    return TableAttention.unsentRound;
  }

  if (quiet != null && quiet >= rules.quietAfter) {
    return TableAttention.quiet;
  }

  return TableAttention.none;
}
