import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/finance_report.dart';
import '../domain/models/shift.dart';
import 'providers.dart';
import 'reports_providers.dart';

/// People › Shifts and Finance › Settlements. A file of its own, as Finance's
/// is, so the two panes land — and could be taken out — without touching the
/// shell or the providers the till runs on.

/// The dates People › Shifts shows. Its own, not [financePeriodProvider]:
/// Settlements shares Finance's choice because it is a Finance pane, and
/// moving a People pane's chips would otherwise move Finance's figures from
/// under somebody who never touched them.
///
/// This week by default. Today at 9 a.m. is one open drawer and nothing else.
final shiftsPeriodProvider = StateProvider<FinancePeriod>(
  (ref) => FinancePeriod.thisWeek,
);

/// The shifts [ShiftHistoryQuery] covers, each by the Z report's rule. Null
/// without `reports.view`.
///
/// **`reports.view`, the gate Finance's drawers are read through**, and not
/// `staff.manage`. That capability guards writes to the staff directory; the
/// only screen that shows a shift's money in the back office today is
/// Finance › Drawers, read through [reportsAllowedProvider], and a list of
/// expected cash and shortfalls is that screen's figures over more days.
/// Gating it on `staff.manage` would show a rota manager the cash Finance
/// hides from them.
///
/// Asked of the person **acting** — the administrator in Admin Mode, not the
/// cashier still signed in at the till behind them. On the till's credential,
/// which already reads every table this names.
final shiftHistoryProvider = FutureProvider.autoDispose
    .family<ShiftHistory?, ShiftHistoryQuery>((ref, query) async {
      if (!ref.watch(reportsAllowedProvider)) return null;
      return ref.watch(shiftRepositoryProvider).history(query);
    });
