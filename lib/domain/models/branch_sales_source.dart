import 'branch_sales.dart';

/// How far a [BranchSalesReading] can be trusted, as data — the screen renders
/// a different sentence for each, and "never silently stale" (§3a) means the
/// difference cannot be left to whoever reads a timestamp.
enum BranchSalesFreshness {
  /// Read just now, from the source of record.
  live,

  /// The last snapshot that WAS read, shown with the time it was read, because
  /// this refresh failed.
  stale,

  /// Nothing to show: the refresh failed and nothing was ever read.
  unavailable,
}

/// Why a refresh did not produce figures.
enum BranchSalesRefreshFailure {
  /// No answer at all — no route, timeout, connection refused.
  offline,

  /// The platform answered and said no: a capability, a revoked terminal, a
  /// branch it will not resolve for this till (404). The code is kept on the
  /// reading so the screen can say which.
  refused,

  /// The platform answered 2xx with something this build cannot trust — a
  /// money figure that is not an integer, another branch's id, another day.
  /// Shown as a failure rather than parsed as zeros: invented zeros are the
  /// most convincing wrong answer a report can give.
  unreadable,
}

/// One answer to "what did the branch take today", with how fresh it is.
class BranchSalesReading {
  const BranchSalesReading({
    required this.freshness,
    this.sales,
    this.asOf,
    this.failure,
    this.failureCode,
    this.unsyncedOnThisTill = 0,
    this.totalsMismatch = false,
  });

  final BranchSalesFreshness freshness;

  /// Null only when [freshness] is [BranchSalesFreshness.unavailable].
  final BranchSales? sales;

  /// When [sales] was read. Always set alongside [sales]; on a stale reading it
  /// is the time of the last successful fetch, which is the whole point of it.
  final DateTime? asOf;

  final BranchSalesRefreshFailure? failure;

  /// The POS-BE-019 code the platform gave, when it gave one.
  final String? failureCode;

  /// This till's own settled sales for the day that the platform has not
  /// received yet. **Counted beside the totals, never added into them** (§3a):
  /// adding them would double-count every one the moment it synced, and the
  /// branch total would stop being the sum of its rows. Null when the count
  /// itself could not be read. Always 0 from a shared database, which already
  /// holds every till's rows.
  final int? unsyncedOnThisTill;

  /// The platform sent branch totals that do not equal the sum of the terminal
  /// rows it sent. The screen still shows the sum of the rows (rule 1); this
  /// says the platform has a bug worth reporting, rather than hiding it.
  final bool totalsMismatch;
}

/// The drill-down into one other terminal's sales (per-till shape only).
class BranchTerminalSalesReading {
  const BranchTerminalSalesReading({
    required this.freshness,
    this.sales,
    this.asOf,
    this.failure,
    this.failureCode,
  });

  /// Never [BranchSalesFreshness.stale]: §3a says drilling into another
  /// terminal needs the connection, so there is no cached list to fall back on.
  final BranchSalesFreshness freshness;
  final List<BranchTerminalSale>? sales;
  final DateTime? asOf;
  final BranchSalesRefreshFailure? failure;
  final String? failureCode;
}

/// Where the branch view's numbers come from — the two shapes in §3a's table.
///
/// The shared-database shape reads every terminal's rows directly; the
/// per-till shape asks the platform (POS-BE-029). Both answer with rows and no
/// total of their own — see [BranchSales].
abstract interface class BranchSalesSource {
  Future<BranchSalesReading> summary(DateTime businessDay);
}
