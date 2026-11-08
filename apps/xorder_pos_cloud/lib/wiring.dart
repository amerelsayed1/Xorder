/// "XOrder POS - Cloud": what this app binds over the shared till
/// (pos-split-apps, stage 3).
///
/// The shared package (`packages/xorder_pos`) leaves four things to the app
/// that runs cloud mode, each behind a provider whose shared default is "no
/// platform": the sync loop, provisioning against the hosted platform,
/// seeding from a bootstrap bundle, and the branch view's platform source.
/// Plus the back office, which on a cloud till is a signpost to the dashboard
/// (CB-07). Everything here used to be inline in `providers.dart`; it moved
/// verbatim, and the shared code reads it through `SalesSync`,
/// `BootstrapSeeding`, `BranchSalesSource` and `BackOffice`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_pos/app/bootstrap_seeding.dart';
import 'package:xorder_pos/app/branch_sales_providers.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/sales_sync.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/features/licensing/data/file_license_store.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/data/unconfigured/unconfigured_repositories.dart';
import 'package:xorder_pos/domain/models/branch_sales_source.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin_mode/back_office_contract.dart';
import 'package:xorder_pos/features/licensing/domain/online_verdict.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';

import 'data/cloud/bootstrap_bundle.dart';
import 'data/cloud/bootstrap_seeder.dart';
import 'data/cloud/branch_sales_api.dart';
import 'data/cloud/cloud_provisioning_repository.dart';
import 'data/cloud/cloud_sync.dart';
import 'features/cloud_back_office_screen.dart';

/// The cloud app's overrides, added by `runPos` after the shared bindings.
List<Override> cloudOverrides() => [
  cloudSyncProvider.overrideWith(_cloudSync),
  provisioningRepositoryProvider.overrideWith(_provisioning),
  platformBranchSalesProvider.overrideWith(_platformBranchSales),
  bootstrapSeedingProvider.overrideWith(
    (ref) => _CloudBootstrapSeeding(ref),
  ),
  backOfficeProvider.overrideWithValue(const CloudBackOffice()),
];

/// The background conversation with the platform: heartbeat, config-version
/// refresh, and the outbox drain. Null when there is nothing to talk to or
/// nothing to say (unprovisioned).
///
/// Under [SyncPolicy.automatic] a pass runs shortly after boot and then on the
/// cadence [SyncSchedule] sets — four hours when everything is through, thirty
/// minutes while anything is still queued or the platform is unreachable.
/// Every settled sale also kicks one immediately, which is what keeps a busy
/// till's money moving between the slow ticks. Under [SyncPolicy.manual]
/// nothing runs on its own — the operator drains from the sync pill, and
/// closing a shift offers to drain first.
SalesSync? _cloudSync(Ref ref) {
  final config = ref.watch(deploymentProvider);
  final api = ref.watch(posCloudApiProvider);
  final context = ref.watch(posWriteContextProvider);
  if (api == null || context == null) return null;

  // One disposer for the provider, not one per sync pass: a callback that
  // registered its own would leak a listener every three minutes.
  var alive = true;
  ref.onDispose(() => alive = false);

  final sync = CloudSync(
    database: ref.watch(posDatabaseProvider),
    config: config,
    api: api,
    vault: ref.watch(deviceTokenVaultProvider),
    profile: ref.watch(terminalProfileProvider),
    onChanged: (outcome) {
      // Invalidate through the CONTAINER, not through this provider's own
      // ref. `pendingSyncCountProvider` reads the orders repository, which
      // reads this provider — so `ref.invalidate` from inside here is a
      // dependency cycle, and Riverpod throws CircularDependencyError. That
      // exception escaped mid-pass and killed the drain: a cloud till would
      // stop sending money and say nothing. Scheduling the invalidation
      // outside the current build breaks the cycle and keeps the refresh.
      Future.microtask(() {
        if (!alive) return;
        applySyncOutcome(ref.container, outcome);
      });
    },
  );

  if (config.syncPolicy == SyncPolicy.automatic) {
    // Self-rescheduling rather than `Timer.periodic`: the gap to the next pass
    // is decided by how the last one went, which a fixed period cannot express.
    // Each pass is AWAITED before the next is scheduled, so a slow drain can
    // never stack passes on top of each other — the old periodic timer could,
    // and `CloudSync.run` had to serialise them itself.
    Timer? next;
    void schedule(Duration delay) {
      next = Timer(delay, () async {
        if (!alive) return;
        // A nudge may have just run a pass — the start screen asks for one
        // on launch, two seconds before this first tick. Yield to it rather
        // than heartbeat twice in the same breath.
        final since = sync.sinceLastPass;
        if (since != null && since < SyncSchedule.nudgeFloor) {
          schedule(SyncSchedule.nudgeFloor - since);
          return;
        }
        final outcome = await sync.run();
        if (!alive) return;
        schedule(SyncSchedule.after(outcome));
      });
    }

    schedule(const Duration(seconds: 5));
    ref.onDispose(() => next?.cancel());
  }
  ref.onDispose(sync.dispose);
  return sync;
}

/// A cloud main device claims against the hosted platform (POS-BE-023), gets
/// its device token (POS-BE-011 Option C), and seeds its local database from
/// the bootstrap bundle the claim carries. A child tablet registers against
/// its main device's PostgreSQL whatever mode that main device runs in: the
/// platform has never heard of it, and it holds no device token to claim with
/// — so for a child this falls through to the shared binding.
ProvisioningRepository _provisioning(Ref ref) {
  final config = ref.watch(deploymentProvider);
  if (config.mode != DeploymentMode.cloud || config.isChild) {
    return branchProvisioningRepository(ref, config);
  }
  final api = ref.watch(posCloudApiProvider);
  if (api == null) return const UnconfiguredProvisioningRepository();
  return CloudProvisioningRepository(
    api: api,
    vault: ref.watch(deviceTokenVaultProvider),
    database: ref.watch(posDatabaseProvider),
    config: config,
    fingerprint: TerminalIdFingerprint(
      ref.watch(terminalProfileProvider).installationId,
    ).value,
    // The bundle's licence embed goes through the same verified path a typed
    // key uses — signature checked, tenant checked — and is then HELD by the
    // wizard rather than written, exactly like a typed one. A claim happens
    // at step six of ten, and an installer can still walk away at any of the
    // four that follow; `SetupController.complete()` is the only place a
    // licence reaches this machine's disk.
    installLicence: (licence) async {
      final installed = await ref
          .read(licenceServiceProvider)
          .activate(
            deployment: config,
            key: '',
            fileContents: jsonEncode(licence),
            persist: false,
          );
      if (installed.file case final file?) {
        ref.read(setupProvider.notifier).holdLicence(file);
      }
      // Where this till takes its verdict from (POS-BE-031). Absent from an
      // older platform, and then nothing is recorded: the till keeps its file.
      if (licence['enforcement'] case final String enforcement) {
        try {
          final store = ref.read(licenceCheckStoreProvider);
          final record = await store.read() ?? const LicenceCheckRecord();
          await store.write(record.copyWith(enforcement: enforcement));
        } on Object {
          // A cache, not a gate: the first check learns it again.
        }
      }
    },
  );
}

/// POS-BE-029: the branch's sales as the platform holds them, for a per-till
/// cloud terminal. Null without an address or before provisioning.
BranchSalesSource? _platformBranchSales(Ref ref) {
  final config = ref.watch(deploymentProvider);
  final base = config.baseUrl;
  final local = ref.watch(postgresBranchSalesProvider);
  final context = ref.watch(posWriteContextProvider);
  if (!config.mode.syncsSalesToPlatform || base == null || base.isEmpty) {
    return null;
  }
  if (local == null || context == null) return null;

  final vault = ref.watch(deviceTokenVaultProvider);
  final api = BranchSalesApi(baseUrl: base, deviceToken: () => vault.token);
  return PlatformBranchSalesSource(
    api: api,
    branchId: context.branchId,
    unsyncedOnThisTill: (day) =>
        local.unsyncedSalesOn(day, terminalId: context.terminalId),
    // Read at request time, not watched: a change of operator must not throw
    // away the snapshot this source is holding for the offline case.
    actingUserId: () => ref.read(signedInStaffProvider)?.id,
  );
}

/// The wizard's menu download: parse the bootstrap reply and seed from it.
final class _CloudBootstrapSeeding implements BootstrapSeeding {
  const _CloudBootstrapSeeding(this._ref);

  final Ref _ref;

  @override
  Future<bool> seed(
    Map<String, Object?> body, {
    required DeploymentConfig config,
    required bool force,
  }) async {
    final bundle = BootstrapBundle.tryParse(body);
    if (bundle == null || !bundle.seedable) return false;
    await BootstrapSeeder(
      database: _ref.read(posDatabaseProvider),
      config: config,
    ).seed(bundle, force: force);
    return true;
  }
}

/// What a cloud till shows where an offline till shows its back office: a
/// signpost to the dashboard, and no menus in the window bar (CB-07, D2).
final class CloudBackOffice implements BackOffice {
  const CloudBackOffice();

  @override
  Widget screen(
    BuildContext context, {
    required ManagementDestination destination,
    required VoidCallback onClose,
    required VoidCallback onReconfigure,
  }) => CloudBackOfficeScreen(onClose: onClose);

  @override
  List<ManagementBarMenu> barMenus(
    AppStrings s, {
    required PosStaff admin,
    required bool authorsItsOwnCatalogue,
  }) => const [];
}
