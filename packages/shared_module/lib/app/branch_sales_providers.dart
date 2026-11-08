import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/postgres/pos_database.dart';
import '../data/postgres/postgres_branch_sales_repository.dart';
import '../domain/models/branch_sales_source.dart';
import '../domain/models/permissions.dart';
import '../domain/services/authorization.dart';
import 'providers.dart';

/// The branch view's sources (§3a, C4). Kept out of `providers.dart` so the
/// feature can land, and be removed, as one file.

/// The shared-database source. Null on a terminal that has not finished setup
/// — the same rule every repository binding in `providers.dart` follows.
///
/// Also built on a per-till cloud terminal, where it is not the branch view's
/// source but still answers the one local question that shape has: how many
/// of this till's sales the platform has not received.
final postgresBranchSalesProvider = Provider<PostgresBranchSalesRepository?>((
  ref,
) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;
  return PostgresBranchSalesRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    businessId: context.businessId,
    branchId: context.branchId,
  );
});

/// The branch's sales as the PLATFORM holds them (POS-BE-029), for a per-till
/// cloud terminal whose own database holds only its own sales.
///
/// **pos-split-apps, stage 3.** The client and the source over it are cloud
/// code in `apps/xorder_pos_cloud`, which binds them here; the offline app
/// binds nothing, and [branchSalesSourceProvider] never asks it to — an
/// offline branch reads every terminal's rows locally. Null when the platform
/// cannot be reached for an address: unprovisioned, or no base URL yet.
final platformBranchSalesProvider = Provider<BranchSalesSource?>(
  (ref) => null,
);

/// Where this till's branch view reads from — the two rows of §3a's table.
///
/// **Per-till** is a cloud terminal whose database is on loopback: its own
/// database holds only its own sales, so the branch has to come from the
/// platform. **Everything else** — an offline install, or a cloud branch whose
/// tills share a LAN database — reads every terminal's rows locally and needs
/// no connection. Decided by where the database is, not by the mode alone:
/// the mode says whether sales sync, and a cloud branch on a shared hub has
/// the whole branch under its feet regardless.
///
/// Null when there is nothing to read: unprovisioned, or a per-till cloud
/// terminal with no platform address yet.
final branchSalesSourceProvider = Provider<BranchSalesSource?>((ref) {
  final config = ref.watch(deploymentProvider);
  final local = ref.watch(postgresBranchSalesProvider);
  final context = ref.watch(posWriteContextProvider);
  if (local == null || context == null) return null;

  if (!(config.mode.syncsSalesToPlatform && config.isLoopback)) return local;

  return ref.watch(platformBranchSalesProvider);
});

/// Whether the signed-in operator may open the branch view (§3a:
/// `reports.view`). Through [Authorization.check], never
/// `capabilities.contains` — that field is direct grants only and misses the
/// role.
final branchSalesAllowedProvider = Provider<bool>(
  (ref) => Authorization.check(
    ref.watch(signedInStaffProvider),
    PosCapability.reportsView,
  ).isAllowed,
);
