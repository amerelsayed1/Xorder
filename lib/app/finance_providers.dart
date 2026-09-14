import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/finance_report.dart';
import '../domain/models/order_record.dart';
import '../domain/models/permissions.dart';
import '../domain/models/sales_report.dart';
import '../domain/models/shift.dart';
import '../domain/services/authorization.dart';
import 'providers.dart';
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

// ── BO-10 ───────────────────────────────────────────────────────────────────

/// Whether the supplier ledger counts in Finance for the person reading —
/// and when it does not, which of the two reasons the label gives.
///
/// **The deployment first, by the rule that hides Purchasing.** A cloud till
/// is one with no catalogue administrator (`catalogAdminRepositoryProvider`
/// null), which is exactly what `ManagementScreen` asks to decide that this
/// terminal does not author purchasing. A capability alone would not do: roles
/// are the till's own even on cloud, so a local Owner still holds
/// `purchase.manage` there, over a ledger the platform keeps.
///
/// **Then `purchase.manage`, of the person acting** — the administrator in
/// Admin Mode, not the cashier still signed in at the till behind them —
/// through `Authorization.check`, which reads the role as well as the direct
/// grants. The repositories under Purchasing check it on every write and on
/// none of their reads; this is where a read is refused.
final supplierFiguresProvider = Provider.autoDispose<SupplierFigures>((ref) {
  if (ref.watch(catalogAdminRepositoryProvider) == null) {
    return SupplierFigures.onPlatform;
  }
  return Authorization.check(
        ref.watch(actingStaffProvider),
        PosCapability.purchaseManage,
      ).isAllowed
      ? SupplierFigures.included
      : SupplierFigures.notPermitted;
});

/// Drawer pay-outs and supplier payments over one range. Null without
/// `reports.view`, as every Finance figure is.
///
/// Two credentials, deliberately. The pay-outs are the till's rows, read on
/// the till's connection as the Z report reads them; the supplier ledger is
/// read through `supplierInvoicesRepositoryProvider`, which is bound to the
/// administrator's pool — and not asked at all unless [supplierFiguresProvider]
/// says so, so a cloud till or a manager without purchasing sends no query to
/// a table that is not theirs.
final expenseReportProvider =
    FutureProvider.autoDispose.family<ExpenseReport?, ReportFilter>((
      ref,
      filter,
    ) async {
      if (!ref.watch(reportsAllowedProvider)) return null;
      final figures = ref.watch(supplierFiguresProvider);
      final drawers = ref.watch(cashMovementsRepositoryProvider);
      final ledger = figures == SupplierFigures.included
          ? ref.watch(supplierInvoicesRepositoryProvider)
          : null;
      final payOuts = await drawers.between(filter);
      final suppliers = await ledger?.spending(filter);
      return ExpenseReport(
        filter: filter,
        payOuts: payOuts,
        supplierFigures: figures,
        suppliers: suppliers,
      );
    });

/// Every drawer open at the branch now, by the Z report's rule. Null without
/// `reports.view`.
///
/// **Not the period's.** A drawer holds what it holds at this moment; a range
/// would be a question about drawers that have since been counted, and the Z
/// reports already answer it.
final openDrawersProvider = FutureProvider.autoDispose<List<OpenDrawer>?>((
  ref,
) async {
  if (!ref.watch(reportsAllowedProvider)) return null;
  return ref.watch(shiftRepositoryProvider).openDrawers();
});

/// What is owed to suppliers against [businessDate]. Null without
/// `reports.view`, and null unless the supplier ledger is this person's here —
/// which is what makes the bills card absent on a cloud till and without
/// `purchase.manage`, whatever screen draws it.
final billsDueProvider = FutureProvider.autoDispose
    .family<BillsDue?, DateTime>((ref, businessDate) async {
      if (!ref.watch(reportsAllowedProvider)) return null;
      if (ref.watch(supplierFiguresProvider) != SupplierFigures.included) {
        return null;
      }
      final unpaid = await ref
          .watch(supplierInvoicesRepositoryProvider)
          .unpaid();
      return BillsDue.of(unpaid, businessDate: businessDate);
    });

/// The transactions table over one range. Null without `reports.view`.
///
/// **The sales are the Sales tab's rows**, read through
/// `orderHistoryProvider` and so scoped as that list is: a manager without
/// `order.view_all` sees their own sales here, as they would on the tab the
/// row drills into. A table that listed sales its drill-down then refused to
/// open would be a list of doors that do not open. The totals elsewhere in
/// Finance are the branch's; this is rows, and rows follow the list's rule.
final financeTransactionsProvider =
    FutureProvider.autoDispose.family<FinanceTransactions?, ReportFilter>((
      ref,
      filter,
    ) async {
      if (!ref.watch(reportsAllowedProvider)) return null;
      final sales = ref.watch(
        orderHistoryProvider(
          OrderHistoryQuery(
            from: filter.from,
            to: filter.to,
            limit: FinanceTransactions.limit,
          ),
        ).future,
      );
      final expenses = ref.watch(expenseReportProvider(filter).future);
      final listed = await sales;
      final spent = await expenses;
      if (spent == null) return null;
      return FinanceTransactions.of(
        sales: listed,
        salesCut: listed.length >= FinanceTransactions.limit,
        expenses: spent,
      );
    });
