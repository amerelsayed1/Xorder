import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud/branch_sales_api.dart';
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

/// POS-BE-029's client. Null when this terminal does not talk to the platform.
final branchSalesApiProvider = Provider<BranchSalesApi?>((ref) {
  final config = ref.watch(deploymentProvider);
  final base = config.baseUrl;
  if (!config.mode.syncsSalesToPlatform || base == null || base.isEmpty) {
    return null;
  }
  final vault = ref.watch(deviceTokenVaultProvider);
  return BranchSalesApi(baseUrl: base, deviceToken: () => vault.token);
});

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

  final api = ref.watch(branchSalesApiProvider);
  if (api == null) return null;
  return PlatformBranchSalesSource(
    api: api,
    branchId: context.branchId,
    unsyncedOnThisTill: (day) =>
        local.unsyncedSalesOn(day, terminalId: context.terminalId),
    // Read at request time, not watched: a change of operator must not throw
    // away the snapshot this source is holding for the offline case.
    actingUserId: () => ref.read(signedInStaffProvider)?.id,
  );
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
