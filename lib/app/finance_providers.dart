import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/finance_report.dart';
import '../domain/models/sales_report.dart';
import 'reports_providers.dart';

/// Finance's sources (plan 19 BO-9). A file of its own, as the reports' are,
/// so the tab lands — and could be taken out — without touching theirs.
///
/// **Revenue is not here.** Finance reads it through `salesReportProvider`,
/// the provider the Reports tab reads, so the two tabs show one query's
/// figure for the same range. A Finance-only revenue provider was the
/// alternative, and would be the second number a manager reconciles by hand.

/// Tax by rate for one range. Null without `reports.view`, or with nothing to
/// read — through the same gate as every report, on the one road to the data.
/// `autoDispose` as the reports are, for the reasons given there.
final taxReportProvider =
    FutureProvider.autoDispose.family<TaxReport?, ReportFilter>((
      ref,
      filter,
    ) async {
      if (!ref.watch(reportsAllowedProvider)) return null;
      final repository = ref.watch(reportsRepositoryProvider);
      if (repository == null) return null;
      return repository.taxes(filter);
    });

/// The payments of one range's sales. Null as [taxReportProvider] is.
final paymentLedgerProvider =
    FutureProvider.autoDispose.family<PaymentLedger?, ReportFilter>((
      ref,
      filter,
    ) async {
      if (!ref.watch(reportsAllowedProvider)) return null;
      final repository = ref.watch(reportsRepositoryProvider);
      if (repository == null) return null;
      return repository.payments(filter);
    });

/// The period Finance's four panes share. One choice for the tab, so moving
/// from Revenue to Taxes does not quietly move from this month to today.
///
/// This month by default: tax is filed by month, and "today" at 9 a.m. is a
/// page of zeros.
final financePeriodProvider = StateProvider<FinancePeriod>(
  (ref) => FinancePeriod.thisMonth,
);
