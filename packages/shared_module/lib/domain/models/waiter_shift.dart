/// Waiter shifts, clocked on the XOrder Waiter handheld (migration 66), as the
/// back office reads them.
///
/// Plain Dart, here rather than beside the SQL that fills it, so People ›
/// Waiter shifts depends on a model and an interface and not on
/// `data/postgres/` — the seam every other pane respects.
library;

/// One waiter shift.
class WaiterShiftRecord {
  const WaiterShiftRecord({
    required this.id,
    required this.staffId,
    required this.startedAt,
    this.staffName,
    this.endedAt,
    this.startedDevice,
    this.endedDevice,
  });

  final int id;
  final int staffId;

  /// Filled by the back-office listing (`WaiterShiftReader.between`).
  final String? staffName;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// The handhelds' names, for the listing.
  final String? startedDevice;
  final String? endedDevice;

  bool get isOpen => endedAt == null;

  /// How long it ran, or has run so far at [now].
  Duration length(DateTime now) => (endedAt ?? now).difference(startedAt);
}

/// One waiter's time over the period: what the pane's summary shows.
class WaiterShiftTotal {
  const WaiterShiftTotal({
    required this.staffId,
    required this.name,
    required this.shifts,
    required this.minutes,
    required this.onShift,
  });

  final int staffId;
  final String name;
  final int shifts;

  /// Whole minutes, the sum of the rows' own — see [WaiterShiftHistory.minutesOf].
  final int minutes;

  /// Still clocked in, so [minutes] is still growing.
  final bool onShift;
}

/// The shifts a period overlaps, as the back office lists them.
class WaiterShiftHistory {
  /// Open shifts first, then newest first. The reader answers newest first
  /// with the open ones mixed in by start time; a waiter who clocked in
  /// yesterday and never out would sit under today's finished shifts, and the
  /// one row a manager has to act on would be the one they scroll past.
  WaiterShiftHistory({
    required List<WaiterShiftRecord> shifts,
    required this.readAt,
  }) : shifts = [
         ...shifts.where((s) => s.isOpen),
         ...shifts.where((s) => !s.isOpen),
       ];

  static final empty = WaiterShiftHistory(
    shifts: const [],
    readAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final List<WaiterShiftRecord> shifts;

  /// When the rows were read: an open shift's length is counted to here, so
  /// every open row and its waiter's total agree with each other, and a page
  /// left on screen does not count one row to 2 p.m. and another to 3.
  final DateTime readAt;

  /// [record]'s length in **whole minutes, truncated** — the one place a
  /// shift's length is rounded.
  ///
  /// Truncated per row, and the totals summed from these, so a manager adding
  /// up the column with a pencil gets the figure in the summary. Summing the
  /// exact durations and rounding once at the total was the alternative: more
  /// exact by a minute or two a week, and a summary that disagrees with the
  /// rows above it is a phone call about which one is wrong.
  ///
  /// Never negative: a handheld's clock does not write these (the database's
  /// `now()` does), but a till whose clock is behind the database's would
  /// otherwise draw an open shift as minus a few minutes.
  int minutesOf(WaiterShiftRecord record) {
    final minutes = record.length(readAt).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  /// One line per waiter, most hours first.
  ///
  /// **Whole shifts, as listed** — a shift that began before the period or
  /// runs past it counts in full, not clipped to the dates. Clipping would
  /// make a waiter's 18:00–02:00 close-out count six hours on one day and two
  /// on the next, and the total would no longer be the sum of the lengths
  /// the table shows beside it.
  List<WaiterShiftTotal> get totals {
    final byStaff = <int, List<WaiterShiftRecord>>{};
    for (final shift in shifts) {
      byStaff.putIfAbsent(shift.staffId, () => []).add(shift);
    }
    final totals = [
      for (final MapEntry(key: id, value: own) in byStaff.entries)
        WaiterShiftTotal(
          staffId: id,
          name: own.first.staffName ?? '#$id',
          shifts: own.length,
          minutes: own.fold(0, (sum, s) => sum + minutesOf(s)),
          onShift: own.any((s) => s.isOpen),
        ),
    ]..sort((a, b) {
        final byMinutes = b.minutes.compareTo(a.minutes);
        return byMinutes != 0 ? byMinutes : a.name.compareTo(b.name);
      });
    return totals;
  }
}

/// Hours and minutes, `7:05` — never a decimal of hours. A manager paying by
/// the hour reads 7.08 as seven hours eight minutes, which it is not.
String waiterShiftHours(int minutes) =>
    '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
