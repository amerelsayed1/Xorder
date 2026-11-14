import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/postgres/pos_database.dart';
import '../data/postgres/postgres_waiter_shifts.dart';
import '../domain/models/finance_report.dart';
import '../domain/models/waiter_shift.dart';
import '../domain/repositories/repositories.dart';
import 'providers.dart';
import 'reports_providers.dart';

/// People › Waiter shifts: the handheld's shift clock, read in the back
/// office. A file of its own, as `shift_history_providers.dart` is, so the
/// pane lands — and could be taken out — without touching the providers the
/// till runs on.

/// The dates People › Waiter shifts shows. Its own, not `shiftsPeriodProvider`:
/// the two panes sit side by side, and a manager checking last month's
/// waiters should not find the cashiers' page moved to last month too.
///
/// This week by default, for People › Shifts' reason: today at 9 a.m. is one
/// open shift and nothing else.
final waiterShiftsPeriodProvider = StateProvider<FinancePeriod>(
  (ref) => FinancePeriod.thisWeek,
);

/// The shift clock's record on this branch, or null with no database.
///
/// Null rather than an empty reader, as `customerDirectoryRepositoryProvider`
/// is, so [waiterShiftsProvider] decides what "no database" draws — and it
/// draws nothing, never a waiter nobody employs.
final waiterShiftReaderProvider = Provider<WaiterShiftReader?>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;
  return PostgresWaiterShifts(
    database: ref.watch(posDatabaseProvider),
    config: config,
    businessId: context.businessId,
    // This branch's waiters: the handhelds are paired to this branch's till.
    branchId: context.branchId,
  );
});

/// What an open shift's length is counted to. A provider so a test can stop
/// the clock; the app never overrides it.
final waiterShiftClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The shifts that overlap [period], open ones first. Null without
/// `reports.view`; empty on a till with no database.
///
/// **`reports.view`, People › Shifts' gate**, and not `staff.manage`: hours
/// worked are what wages are paid on, which is the same kind of figure as a
/// drawer's takings, and `staff.manage` is a write to the directory. Asked of
/// the person **acting** — the administrator in Admin Mode, not the cashier
/// still signed in behind them — here, on the one road to the rows, so a pane
/// reached round the bar still draws nothing.
///
/// **[period] is local midnights, compared with the shift's timestamps.** The
/// cashier shifts are filed by business date through `pos_business_days`; a
/// waiter shift has no business day of its own to be filed by, so a shift
/// that starts after midnight on a night that runs to 2 a.m. falls on the
/// next calendar date. Joining it to the open day by time was the
/// alternative, and would have put a query this pane does not own into the
/// waiter link's repository for an edge a manager reading a week never sees.
final waiterShiftsProvider = FutureProvider.autoDispose
    .family<WaiterShiftHistory?, ({DateTime from, DateTime to})>((
      ref,
      period,
    ) async {
      if (!ref.watch(reportsAllowedProvider)) return null;
      final reader = ref.watch(waiterShiftReaderProvider);
      if (reader == null) return WaiterShiftHistory.empty;
      final shifts = await reader.between(period.from, period.to);
      return WaiterShiftHistory(
        shifts: shifts,
        readAt: ref.read(waiterShiftClockProvider)(),
      );
    });
