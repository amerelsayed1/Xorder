import '../../core/money/money.dart';

enum TableState {
  /// No open visit. Tile is `surface` with a 1px lineStrong border.
  free,

  /// An open bill. Tile is `accentSoft` with a 2px accent border.
  open,

  /// The diner asked for the bill. Tile is `dangerSoft` with a 2px danger border.
  billAsked,
}

/// A table on the floor screen.
class DiningTable {
  const DiningTable({
    required this.id,
    required this.label,
    required this.seats,
    this.state = TableState.free,
    this.openLineCount = 0,
    this.openTotal,
    this.areaName,
    this.sortOrder = 0,
    this.guestCount,
    this.seatedAt,
    this.lastSentAt,
    this.hasUnsentDraft = false,
  });

  final int id;
  final String label;
  final int seats;
  final TableState state;
  final int openLineCount;
  final Money? openTotal;

  /// The section this table stands in — "Terrace", "Bar", "Upstairs".
  /// Free text the manager typed; null is the unnamed main room.
  final String? areaName;

  /// The manager's order on the floor, within and across sections.
  final int sortOrder;

  // ── Only set while a ticket sits on the table ──────────────────────────────

  /// How many people are at it, when the ticket says.
  final int? guestCount;

  /// When the party was seated — the ticket's own clock, not when it was last
  /// parked, so a table that was opened at 19:00 and touched at 21:00 still
  /// reads as two hours old.
  final DateTime? seatedAt;

  /// When the kitchen last got a round. Null while nothing has been fired.
  final DateTime? lastSentAt;

  /// Lines rung up but not yet sent — a round waiting on the cashier, not the
  /// kitchen.
  final bool hasUnsentDraft;

  bool get isFree => state == TableState.free;

  /// Time at the table, against the caller's clock. Null when nobody is seated.
  Duration? seatedFor(DateTime now) =>
      seatedAt == null ? null : _nonNegative(now.difference(seatedAt!));

  /// Time since the kitchen last heard from this table. Falls back to the
  /// seating time when nothing has been fired yet — the number the floor
  /// wants is "how long have they been waiting", whichever clock answers it.
  Duration? quietFor(DateTime now) {
    final since = lastSentAt ?? seatedAt;
    return since == null ? null : _nonNegative(now.difference(since));
  }

  static Duration _nonNegative(Duration d) => d.isNegative ? Duration.zero : d;
}
