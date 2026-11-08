/// Opening the trading day, and saying when it is not as it should be.
///
/// **Why this exists.** `BusinessDayRepository.open` was written, tested and
/// never called: nothing in the product opened a day. So `pos_business_days`
/// stayed empty, every sale kept a NULL `business_day_id`, Home read "no
/// business day opened yet" next to a paid sale, and "Close the day" — shown
/// only while a day is open — and the backup that hangs off it could never be
/// reached. Found driving the real till offline (report 2026-10-24, F-3).
///
/// **The rules, as approved:**
///  * A day opens with the first shift opened or resumed, for the business date
///    [DayPolicy.dateFor] says the moment belongs to.
///  * A day that is already open is used, whatever its date — the database
///    allows one open day per branch, and closing is a person's decision with
///    a blocker list, never something the till does for them.
///  * **The till never stops selling because of the day.** Whatever goes wrong
///    is returned, not thrown; the shift opens and the rows stay unstamped, as
///    they always have.
library;

import '../models/business_day.dart';
import '../models/pos_settings.dart';
import '../repositories/repositories.dart';

/// What [ensureBusinessDay] found or did.
enum BusinessDayOutcome {
  /// No day was open; this one was opened.
  opened,

  /// A day was already open (possibly opened by another till a moment ago).
  reused,

  /// The moment's business date was already closed, and `open` refuses to
  /// resurrect a day somebody deliberately ended. Selling carries on unstamped.
  dateAlreadyClosed,

  /// The database could not say. Selling carries on unstamped; the next sign-in
  /// tries again.
  failed,
}

class BusinessDayResult {
  const BusinessDayResult(this.outcome, {this.day, this.error});

  final BusinessDayOutcome outcome;

  /// The day in force, for [BusinessDayOutcome.opened] and `reused`.
  final BusinessDay? day;

  /// What went wrong, for `failed` — logged by the caller, never shown raw.
  final Object? error;
}

/// Make sure the branch is trading in a day. Never throws.
///
/// [now] is a parameter so the roll-over (02:00 still belongs to yesterday) is
/// testable without a clock.
Future<BusinessDayResult> ensureBusinessDay({
  required BusinessDayRepository days,
  required DayPolicy policy,
  required DateTime now,
  required PosStaff by,
}) async {
  final date = policy.dateFor(now);
  try {
    final open = await days.current();
    if (open != null) {
      return BusinessDayResult(BusinessDayOutcome.reused, day: open);
    }

    try {
      final opened = await days.open(date: date, by: by);
      return BusinessDayResult(BusinessDayOutcome.opened, day: opened);
    } on Object catch (error) {
      // Two tills starting together lose to the one-open-day index. The loser
      // wants the winner's day, not an error a cashier has to read at 7 a.m.
      final raced = await days.current();
      if (raced != null) {
        return BusinessDayResult(BusinessDayOutcome.reused, day: raced);
      }

      // Otherwise: is this date already closed? Asked of the repository rather
      // than read off the exception, which is a sentence for a developer.
      final nextDay = DateTime(date.year, date.month, date.day + 1);
      final closed = await days.lastClosed(before: nextDay);
      if (closed != null && _sameDate(closed.date, date)) {
        return const BusinessDayResult(BusinessDayOutcome.dateAlreadyClosed);
      }
      return BusinessDayResult(BusinessDayOutcome.failed, error: error);
    }
  } on Object catch (error) {
    return BusinessDayResult(BusinessDayOutcome.failed, error: error);
  }
}

/// Something worth telling the person at the start screen.
enum DayNoticeKind {
  /// A day opened on an earlier date is still open: somebody did not close the
  /// night. Sales keep going into it until somebody does.
  staleOpenDay,

  /// Today's business date was closed and a shift is selling anyway, so these
  /// sales are not filed under any day.
  todayAlreadyClosed,
}

class DayNotice {
  const DayNotice(this.kind, this.date);

  final DayNoticeKind kind;

  /// The business date the sentence is about.
  final DateTime date;
}

/// What, if anything, to say about the day. Pure, so the start screen derives
/// it from current state and it cannot go stale in a stored flag.
DayNotice? dayNotice({
  required BusinessDay? open,
  required BusinessDay? lastClosed,
  required DayPolicy policy,
  required DateTime now,
  required bool shiftOpen,
}) {
  final today = policy.dateFor(now);
  if (open != null) {
    final date = DateTime(open.date.year, open.date.month, open.date.day);
    return date.isBefore(today)
        ? DayNotice(DayNoticeKind.staleOpenDay, date)
        : null;
  }
  if (shiftOpen && lastClosed != null && _sameDate(lastClosed.date, today)) {
    return DayNotice(DayNoticeKind.todayAlreadyClosed, today);
  }
  return null;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
