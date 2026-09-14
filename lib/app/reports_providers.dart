import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/postgres/pos_database.dart';
import '../data/postgres/postgres_reports_repository.dart';
import '../domain/models/permissions.dart';
import '../domain/models/sales_report.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/authorization.dart';
import 'providers.dart';

/// The reports' sources (plan 19 BO-5). Kept out of `providers.dart`, as the
/// branch view's are, so the feature lands — and could be taken out — as one
/// file. No screen reads these yet; BO-6 draws them.

/// The shared-database reports. Null on a terminal that has not finished
/// setup — the same rule the branch view's binding follows. There is no
/// fallback source: an empty report would read as a day with no sales.
final reportsRepositoryProvider = Provider<ReportsRepository?>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;
  return PostgresReportsRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    // The branch this till trades at, and no other (plan 17 §2).
    branchId: context.branchId,
  );
});

/// Whether the signed-in operator may read the reports: `reports.view`,
/// through [Authorization.check] — never `capabilities.contains`, which is
/// direct grants only and would refuse a manager whose role carries it.
///
/// **The figures are the branch's; `order.view_all` does not narrow them.**
/// That is §3a's rule for the branch view, which these extend to a range:
/// the totals need `reports.view`, and it is the drill-down — the sales list,
/// through `HistoryScope` — that shows somebody without `order.view_all` only
/// their own sales. Narrowing the figures as well was the alternative, and
/// would make a manager whose role lacks `order.view_all` see a branch that
/// sold only what they rang up.
final reportsAllowedProvider = Provider<bool>(
  (ref) => Authorization.check(
    ref.watch(signedInStaffProvider),
    PosCapability.reportsView,
  ).isAllowed,
);

/// One report. Null without `reports.view`, or with nothing to read.
///
/// The gate is here, on the one road to the data, and not in the tab that
/// will draw it: a hidden tab is not a rule, and the next screen built on
/// this provider inherits the check instead of having to remember it.
final salesReportProvider = FutureProvider.family<SalesReport?, ReportFilter>(
  (ref, filter) async {
    if (!ref.watch(reportsAllowedProvider)) return null;
    final repository = ref.watch(reportsRepositoryProvider);
    if (repository == null) return null;
    return repository.sales(filter);
  },
);

/// The key of [topProductsProvider]. A record, so two built alike are equal.
typedef TopProductsQuery = ({ReportFilter filter, ProductRanking by});

/// The top five, ranked one way. Empty without `reports.view`.
final topProductsProvider =
    FutureProvider.family<List<ProductSales>, TopProductsQuery>((
      ref,
      query,
    ) async {
      if (!ref.watch(reportsAllowedProvider)) return const [];
      final repository = ref.watch(reportsRepositoryProvider);
      if (repository == null) return const [];
      return repository.topProducts(query.filter, by: query.by);
    });
