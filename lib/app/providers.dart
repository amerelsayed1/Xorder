import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/config/deployment.dart';
import '../data/cloud/cloud_api.dart';
import '../data/cloud/cloud_provisioning_repository.dart';
import '../data/cloud/cloud_sync.dart';
import '../data/cloud/device_token_vault.dart';
import '../data/cloud/outbox_drain.dart';
import '../core/config/platform_endpoint.dart';
import '../core/config/terminal_config.dart';
import '../core/config/terminal_profile.dart';
import '../core/l10n/app_strings.dart';
import '../core/money/money.dart';
import '../core/network/connectivity_probe.dart';
import '../data/config/terminal_config_store.dart';
import '../data/hardware/network_printer_ports.dart';
import '../data/postgres/pos_database.dart';
import '../data/postgres/postgres_admin_repositories.dart';
import '../data/postgres/postgres_catalog_admin_repository.dart';
import '../data/postgres/postgres_catalog_repository.dart';
import '../data/postgres/postgres_directory_repositories.dart';
import '../data/postgres/postgres_discounts_repository.dart';
import '../data/postgres/postgres_reason_repository.dart';
import '../data/postgres/postgres_floor_repository.dart';
import '../data/postgres/postgres_order_history_repository.dart';
import '../data/postgres/postgres_business_day_repository.dart';
import '../data/postgres/postgres_cash_movements_repository.dart';
import '../data/postgres/postgres_orders_repository.dart';
import '../data/eta/filing_orders_repository.dart';
import '../data/postgres/postgres_eta_queue_repository.dart';
import '../data/postgres/postgres_receipt_profile_repository.dart';
import '../data/postgres/postgres_settings_repository.dart';
import '../data/postgres/postgres_refunds_repository.dart';
import '../data/postgres/money_config_codec.dart';
import '../data/postgres/postgres_parked_tickets.dart';
import '../data/postgres/postgres_shift_repository.dart';
import '../data/unconfigured/unconfigured_repositories.dart';
import '../features/licensing/data/file_license_store.dart';
import '../features/licensing/data/licence_service.dart';
import '../features/licensing/data/license_keys.dart';
import '../features/licensing/data/license_store.dart';
import '../features/licensing/data/platform_licence_api.dart';
import '../features/licensing/domain/license_verifier.dart';
import '../features/licensing/domain/license.dart';
import '../features/setup/application/setup_controller.dart';
import '../domain/models/catalog.dart';
import '../domain/models/dining_table.dart';
import '../domain/models/ticket.dart';
import '../domain/models/discount.dart';
import '../domain/models/order_record.dart';
import '../domain/models/business_day.dart';
import '../domain/models/pos_settings.dart';
import '../domain/models/refund.dart';
import '../domain/models/reason_code.dart';
import '../domain/models/eta_submission.dart';
import '../domain/models/permissions.dart';
import '../domain/models/receipt_profile.dart';
import '../domain/repositories/admin_repositories.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/authorization.dart';
import '../domain/services/floor_overlay.dart';
import '../domain/services/ticket_engine.dart';

/// `TerminalProfile` moved to `core/config/` when it started being written to
/// disk. Re-exported so the fifty-odd files that reach it through this one
/// import did not all have to change to say the same thing.
export '../core/config/terminal_profile.dart';

const _uuid = Uuid();

/// Repository bindings.
///
/// **Every one of these reads the branch server's PostgreSQL, or returns
/// nothing.** Until recently they all resolved to a `Fake…` implementation, and
/// because nothing distinguished a release build from a debug one, that meant a
/// real restaurant installing the till opened it to a menu, a floor plan and a
/// cashier belonging to a fictional restaurant — while the money path wrote real
/// rows to a real database. Convincing and wrong is the worst combination a
/// point of sale can have.
///
/// The pattern below is the same in each case, and matches
/// [ordersRepositoryProvider]: use PostgreSQL when this terminal has a branch
/// server it can reach, and an `Unconfigured…` binding otherwise. Falling back
/// rather than throwing is deliberate — a terminal mid-setup has no database
/// yet, and a provider that threw would take the app down before the wizard
/// could fix it.
///
/// The `Fake…` implementations still exist in `lib/data/fakes/`. They are test
/// doubles now, injected by tests that want them, rather than what the app runs
/// on.
///
/// The day an `Api…` implementation exists for a contract in
/// `docs/coordination/BACKEND_TO_POS.md`, it replaces the Postgres branch here
/// and nothing in `domain/` or `features/` changes.
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  if (PosDatabase.hostFor(config) == null) {
    return const UnconfiguredCatalogRepository();
  }

  // Scoped by tenant slug rather than by the numeric restaurant id, because the
  // catalogue is first pulled during setup — before a terminal has been claimed
  // and an id is known.
  return PostgresCatalogRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    // So per-branch prices and availability resolve at the read.
    branchId: ref.watch(posWriteContextProvider)?.branchId,
  );
});

/// The discounts this restaurant offers, and the ceiling a role may give away.
final discountsRepositoryProvider = Provider<DiscountsRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredDiscountsRepository();
  }
  // Currency and exponent are left at their defaults, which are `Ticket`'s
  // defaults too — a discount priced in a different currency from the ticket it
  // comes off would not add up. When currency becomes configurable (SRS §93,
  // Wave D) both read it from the same place.
  return PostgresDiscountsRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
  );
});

/// Everything the restaurant currently offers. Refreshed when the till does.
final discountsProvider = FutureProvider<List<Discount>>(
  (ref) => ref.watch(discountsRepositoryProvider).all(),
);

/// What the person at the till may take off without a supervisor.
final discountLimitProvider = FutureProvider<DiscountLimit>(
  (ref) => ref
      .watch(discountsRepositoryProvider)
      .limitFor(ref.watch(signedInStaffProvider)),
);

/// The reason lists this restaurant picks from.
final reasonsRepositoryProvider = Provider<ReasonsRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredReasonsRepository();
  }
  return PostgresReasonsRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
  );
});

/// The reasons offered for one act.
final reasonCodesProvider =
    FutureProvider.family<List<ReasonCode>, ReasonScope>(
      (ref, scope) => ref.watch(reasonsRepositoryProvider).forScope(scope),
    );

final tablesRepositoryProvider = Provider<TablesRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredTablesRepository();
  }
  return PostgresFloorRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredSessionRepository();
  }
  return PostgresSessionRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
});

/// **The swap point.**
///
/// Today: PostgreSQL on the branch server when this terminal is provisioned for
/// one, and the fake otherwise. The day `POS-BE-006` is `READY`, an
/// `ApiOrdersRepository` replaces the Postgres branch here and nothing in
/// `lib/domain/` or `lib/features/` changes — that is the entire point of the
/// repository contract.
///
/// Falling back to the fake rather than throwing is deliberate. A terminal that
/// has not finished setup has no database to write to, and a provider that threw
/// would take the whole app down before the wizard could fix it.
final Provider<OrdersRepository>
ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredOrdersRepository();
  }
  final inner = PostgresOrdersRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    context: context,
    // Read, not watched. A sale stamps the shift that was open when it was
    // rung up; rebuilding the repository mid-payment because a shift closed
    // elsewhere would be worse than an unattributed order.
    shiftId: ref.read(shiftProvider).valueOrNull?.id,
  );

  // On a cloud terminal every settled sale pokes the drain, so "sold" and
  // "synced" are seconds apart rather than a timer apart. The write itself is
  // identical either way — PostgreSQL first, outbox claim in the same
  // transaction.
  final sync = ref.watch(cloudSyncProvider);
  final synced = sync == null ? inner : SyncingOrdersRepository(inner, sync.kick);

  // And then the tax authority, on top of everything else. Outermost on
  // purpose: the platform sync must happen whether or not this branch files
  // e-receipts, and a filing failure must not take the sync down with it.
  final queue = ref.watch(etaQueueRepositoryProvider);
  if (queue == null) return synced;

  return FilingOrdersRepository(
    synced,
    queue: queue,
    // Read at settlement, not held: a profile completed in Management five
    // minutes ago is the one this sale is filed under.
    profile: () =>
        ref.read(receiptProfileProvider).valueOrNull ??
        const ReceiptProfile(branchId: 0),
    // ETA's chain is per POS serial. The terminal id is what this product has
    // that is stable per till and unique per restaurant; the serial registered
    // with the authority is set alongside the seal, and until that exists this
    // keeps two tills in one branch on two chains, which is the property that
    // matters.
    deviceSerial: context.terminalId,
  );
});

/// Reading settled orders back — history, and everything built on it.
///
/// A separate binding from [ordersRepositoryProvider] even though both talk to
/// the same tables. That one writes and is wrapped in the sync kicker; this one
/// only reads, so a screen that lists history cannot be handed something that
/// can settle a sale.
final orderHistoryRepositoryProvider = Provider<OrderHistoryRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredOrderHistoryRepository();
  }
  return PostgresOrderHistoryRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    // Branch-scoped, not merely restaurant-scoped. A till lists the orders
    // taken at the counter it is standing on; showing another shop's takings
    // would be a privacy problem before it was a usability one.
    branchId: context.branchId,
  );
});

/// One slice of history. Keyed by the query, so changing a filter is a new
/// read rather than a mutation of a list somebody is looking at.
final orderHistoryProvider =
    FutureProvider.family<List<OrderRecord>, OrderHistoryQuery>(
      (ref, query) => ref.watch(orderHistoryRepositoryProvider).search(query),
    );

/// One order, opened from the list.
final orderDetailProvider = FutureProvider.family<OrderRecordDetail?, int>(
  (ref, orderId) => ref.watch(orderHistoryRepositoryProvider).detail(orderId),
);

/// Money going back.
///
/// Takes the shift by `read`, not `watch`, for the same reason the orders
/// repository does: a refund stamps the shift that was open when it was given,
/// and rebuilding this mid-transaction because a shift closed at another till
/// would be worse than an unattributed refund.
final refundsRepositoryProvider = Provider<RefundsRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredRefundsRepository();
  }
  return PostgresRefundsRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    context: context,
    shiftId: ref.read(shiftProvider).valueOrNull?.id,
  );
});

/// Every refund already issued against one order.
///
/// The refund engine needs these, not merely the total: the remainder rule
/// works off what each previous refund gave back part by part.
final refundsForOrderProvider = FutureProvider.family<List<Refund>, int>(
  (ref, orderId) => ref.watch(refundsRepositoryProvider).forOrder(orderId),
);

/// Whether the branch database is answering.
///
/// **The question an offline till actually has.** A terminal in offline mode is
/// not "offline" — that is its permanent and intended state, and a status pill
/// announcing it reads as a fault on a machine where nothing is wrong. What can
/// genuinely go wrong is the branch server: unplugged switch, wrong address,
/// Postgres not running. That is what stops the till selling, and that is what
/// the pill shows instead.
///
/// Null while the first probe is in flight. `PosDbFailure` when it failed,
/// naming which of the four things went wrong; the absence of one means healthy.
final branchDatabaseProvider = FutureProvider<PosDbFailure?>((ref) async {
  final config = ref.watch(deploymentProvider);
  // Not configured at all — the setup wizard has not run. `tcp` is the
  // honest classification: there is nothing to reach.
  if (PosDatabase.hostFor(config) == null) return PosDbFailure.tcp;
  return ref.watch(posDatabaseProvider).probe(config);
});

/// What the restaurant has configured.
///
/// Read once and resolved — restaurant, then branch, then terminal. Everything
/// policy-shaped is derived from this rather than read out of it directly: see
/// the note on [PosSettings] about the map never being the public surface.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredSettingsRepository();
  }
  return PostgresSettingsRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
});

final settingsProvider = FutureProvider<PosSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).load(),
);

/// The three value objects the settings resolve into.
///
/// Each falls back to its own defaults while the read is in flight or has
/// failed. A screen blocked on a spinner because nobody has configured a
/// refund window would be worse than one running on the SRS's own answer —
/// which is what an unconfigured till is *supposed* to run on.
final refundPolicyProvider = Provider<RefundPolicy>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings == null
      ? RefundPolicy.defaults
      : RefundPolicy.from(settings);
});

final dayPolicyProvider = Provider<DayPolicy>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings == null ? DayPolicy.defaults : DayPolicy.from(settings);
});

final cashPolicyProvider = Provider<CashPolicy>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings == null ? CashPolicy.defaults : CashPolicy.from(settings);
});

/// The trading day.
final businessDayRepositoryProvider = Provider<BusinessDayRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredBusinessDayRepository();
  }
  return PostgresBusinessDayRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    context: context,
  );
});

/// The day this branch is currently trading in, if anybody has opened one.
final businessDayProvider = FutureProvider<BusinessDay?>(
  (ref) => ref.watch(businessDayRepositoryProvider).current(),
);

/// Money into and out of the drawer that is not a sale.
final cashMovementsRepositoryProvider = Provider<CashMovementsRepository>((
  ref,
) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredCashMovementsRepository();
  }
  return PostgresCashMovementsRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    context: context,
  );
});

/// One shift's non-sale movements, totalled.
final cashMovementsProvider =
    FutureProvider.family<CashMovementTotals, int>((ref, shiftId) async {
      final movements = await ref
          .watch(cashMovementsRepositoryProvider)
          .forShift(shiftId);
      return CashMovementTotals.of(movements);
    });

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  if (PosDatabase.hostFor(config) == null) {
    return const UnconfiguredBranchRepository();
  }

  return PostgresBranchRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
  );
});

final provisioningRepositoryProvider = Provider<ProvisioningRepository>((ref) {
  final config = ref.watch(deploymentProvider);

  // A cloud terminal claims against the hosted platform (POS-BE-023), gets its
  // device token (POS-BE-011 Option C), and seeds its local database from the
  // bootstrap bundle the claim carries. Offline terminals keep claiming
  // against the branch server's own PostgreSQL, as before.
  if (config.mode == DeploymentMode.cloud) {
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
      // The bundle's licence embed installs through the same verified path a
      // typed key uses — signature checked, tenant checked, stored on disk.
      installLicence: (licence) async {
        await ref
            .read(licenceServiceProvider)
            .activate(
              deployment: config,
              key: '',
              fileContents: jsonEncode(licence),
            );
        ref.invalidate(licenceEntitlementProvider);
      },
    );
  }

  if (PosDatabase.hostFor(config) == null) {
    return const UnconfiguredProvisioningRepository();
  }
  return PostgresProvisioningRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
  );
});

/// The hosted platform, or null when this terminal has no business talking to
/// one — offline mode, or a cloud terminal whose base URL is not yet set.
final posCloudApiProvider = Provider<PosCloudApi?>((ref) {
  final config = ref.watch(deploymentProvider);
  final base = config.baseUrl;
  if (!config.mode.syncsSalesToPlatform || base == null || base.isEmpty) {
    return null;
  }
  final vault = ref.watch(deviceTokenVaultProvider);
  return PosCloudApi(baseUrl: base, deviceToken: () => vault.token);
});

/// The terminal's device credential. The default is in-memory; `main()`
/// overrides it with the keychain-backed vault, restored before the first
/// frame — the same arrangement as the database password.
final deviceTokenVaultProvider = Provider<DeviceTokenVault>(
  (ref) => DeviceTokenVault(),
);

/// The background conversation with the platform: heartbeat, config-version
/// refresh, and the outbox drain. Null when there is nothing to talk to or
/// nothing to say (unprovisioned).
///
/// Under [SyncPolicy.automatic] a pass runs shortly after boot and then every
/// three minutes; every settled sale also kicks one immediately. Under
/// [SyncPolicy.manual] nothing runs on its own — the operator drains from the
/// sync pill, and closing a shift offers to drain first.
final Provider<CloudSync?> cloudSyncProvider = Provider<CloudSync?>((ref) {
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
    final first = Timer(const Duration(seconds: 5), sync.kick);
    final periodic = Timer.periodic(
      const Duration(minutes: 3),
      (_) => sync.kick(),
    );
    ref.onDispose(() {
      first.cancel();
      periodic.cancel();
    });
  }
  return sync;
});

/// Printer and drawer, over the network.
///
/// Real: it sweeps this machine's own /24 for anything listening on the RAW
/// port every ESC/POS thermal printer uses, and *Test print* sends actual
/// commands — including the drawer kick, because proving the drawer opens is
/// half of what an installer is checking.
///
/// It replaced a binding that invented two plausible-looking printers, which an
/// operator could select and then discover at service time was never attached.
///
/// **USB printers are not covered.** They need a platform channel per OS, and
/// nothing here pretends otherwise: discovery reports what is on the network
/// and says nothing about what is plugged in.
final hardwarePortsProvider = Provider<HardwarePorts>(
  (ref) => const NetworkPrinterPorts(),
);

final branchesProvider = FutureProvider<List<PosBranch>>(
  (ref) => ref.watch(branchRepositoryProvider).forTenant(),
);

final sessionProvider = FutureProvider<PosSession>(
  (ref) => ref.watch(sessionRepositoryProvider).current(),
);

final catalogProvider = FutureProvider<Catalog>(
  (ref) => ref.watch(catalogRepositoryProvider).load(),
);

final tablesProvider = FutureProvider<List<DiningTable>>(
  (ref) => ref.watch(tablesRepositoryProvider).liveFloor(),
);

/// Tickets parked on tables — the till's own floor state.
///
/// One entry per seated table. Parking happens when the cashier leaves a
/// seated, non-empty ticket for the floor; resuming happens when its table is
/// tapped; settlement frees the table. In memory for now — a restart loses
/// parked (unpaid, unsent) tickets, the same loss the single live ticket
/// already suffers; persisting the open floor into the local database is the
/// follow-up that fixes both at once.
class OpenTicketsController extends Notifier<Map<int, Ticket>> {
  @override
  Map<int, Ticket> build() {
    ref.onDispose(() => _disposed = true);
    // Put the floor back the way the restart found it. Async on purpose —
    // the first frame must not wait on a database — and merge-not-replace,
    // so a table seated in the seconds before hydration lands wins over its
    // own stale disk copy.
    Future.microtask(_hydrate);
    return const {};
  }

  bool _disposed = false;

  PostgresParkedTickets? get _store {
    final config = ref.read(deploymentProvider);
    final restaurantId = ref.read(terminalProfileProvider).restaurantId;
    if (restaurantId == null || PosDatabase.hostFor(config) == null) {
      return null;
    }
    return PostgresParkedTickets(
      database: ref.read(posDatabaseProvider),
      config: config,
      restaurantId: restaurantId,
    );
  }

  Future<void> _hydrate() async {
    final store = _store;
    if (store == null) return;
    try {
      final catalog = await ref.read(catalogProvider.future);
      final parked = await store.load(catalog);
      if (_disposed || parked.isEmpty) return;
      state = {...parked, ...state};
    } on Object {
      // A floor that cannot hydrate is empty, not broken — parking still
      // works and writes through from here on.
    }
  }

  /// Park a seated ticket on its table. A ticket with no table or no lines
  /// has nothing to hold a table with, and is ignored rather than refused —
  /// leaving the sale screen with an empty ticket is normal, not an error.
  void park(Ticket ticket) {
    final tableId = ticket.tableId;
    if (tableId == null || ticket.lines.isEmpty) return;
    state = {...state, tableId: ticket};
    unawaited(_store?.save(ticket) ?? Future.value());
  }

  Ticket? at(int tableId) => state[tableId];

  /// The table's money reached the till — the seat is free again.
  void settle(int? tableId) {
    if (tableId == null) return;
    if (state.containsKey(tableId)) {
      state = {...state}..remove(tableId);
    }
    // The disk row goes regardless of what memory held: a settled table must
    // not resurrect on the next boot.
    unawaited(_store?.remove(tableId) ?? Future.value());
  }
}

final openTicketsProvider =
    NotifierProvider<OpenTicketsController, Map<int, Ticket>>(
      OpenTicketsController.new,
    );

/// The floor as the cashier sees it: the seeded plan overlaid with this
/// till's parked tickets — busy tiles carry their item count and total.
final floorTablesProvider = FutureProvider<List<DiningTable>>((ref) async {
  final tables = await ref.watch(tablesProvider.future);
  return overlayOpenTickets(tables, ref.watch(openTicketsProvider));
});

/// How many settled sales this terminal still owes the platform.
///
/// Read from the outbox rather than counted as sales happen. A number held only
/// in memory resets to zero on the next launch, which would show "synced" to a
/// till holding a day of unsent takings — the one thing this pill exists to
/// prevent it saying.
///
/// Invalidate it after anything that enqueues or drains.
final FutureProvider<int> pendingSyncCountProvider = FutureProvider<int>(
  (ref) => ref.watch(ordersRepositoryProvider).pendingSyncCount(),
);

/// Fan a finished sync pass out into the providers that care.
///
/// Top-level and public so a test can drive it with a hand-built outcome. The
/// regression that made this necessary was not a wrong reaction to a sync
/// result — it was NO reaction: `deviceTokenRejected` was computed by
/// [CloudSync] and read by nobody, and a silent field is not something a
/// widget test can notice. Keeping the handling here means the wiring itself
/// is the thing under test.
void applySyncOutcome(ProviderContainer container, SyncOutcome outcome) {
  container.invalidate(pendingSyncCountProvider);

  // Written on every pass, not only on rejection, so a till that gets
  // re-paired clears the banner by itself instead of carrying it until
  // someone restarts the app.
  final rejected = container.read(terminalRejectedProvider.notifier);
  if (rejected.state != outcome.deviceTokenRejected) {
    rejected.state = outcome.deviceTokenRejected;
  }

  if (outcome.reseeded) {
    // The platform re-authored the till's world; every cache of it is stale
    // at once.
    container.invalidate(catalogProvider);
    container.invalidate(tablesProvider);
    container.invalidate(branchesProvider);
    container.invalidate(sessionProvider);
    container.invalidate(staffDirectoryProvider);
    container.invalidate(moneyConfigProvider);
  }
}

/// The platform no longer recognises this terminal's device credential.
///
/// Set when a sync pass comes back `DEVICE_TOKEN_INVALID` — the terminal was
/// deleted, or its token was rotated past this till. Until this existed the
/// flag was computed by [CloudSync] and read by nobody, so a till whose
/// terminal had been removed went on looking perfectly healthy while every
/// sync pass failed silently. Nothing on screen changed, and the only symptom
/// was a pending count climbing where no one was watching.
///
/// Deliberately NOT persisted. It is a statement about the last conversation
/// with the platform, so it must be re-earned each launch rather than
/// surviving as a stale accusation against a till that has since been
/// re-paired. Cleared by the first pass that succeeds.
final StateProvider<bool> terminalRejectedProvider = StateProvider<bool>(
  (ref) => false,
);

/// Non-ticket screen state: which category is selected, what is in the search
/// box, and whether the terminal believes it is online.
class PosUiState {
  const PosUiState({
    this.selectedCategoryId,
    this.query = '',
    this.online = true,
  });

  /// null = "All items".
  final int? selectedCategoryId;
  final String query;
  final bool online;

  PosUiState copyWith({
    int? selectedCategoryId,
    String? query,
    bool? online,
    bool clearCategory = false,
  }) => PosUiState(
    selectedCategoryId: clearCategory
        ? null
        : (selectedCategoryId ?? this.selectedCategoryId),
    query: query ?? this.query,
    online: online ?? this.online,
  );
}

class PosUiController extends Notifier<PosUiState> {
  @override
  PosUiState build() => const PosUiState();

  void selectCategory(int? id) => state = id == null
      ? state.copyWith(clearCategory: true)
      : state.copyWith(selectedCategoryId: id);

  void setQuery(String value) => state = state.copyWith(query: value);

  /// The sync pill in the top bar toggles this in the prototype. In production
  /// it is driven by connectivity plus the outcome of the last flush — a
  /// reachable network that returns 401 is not "online" for our purposes.
  void toggleOnline() => state = state.copyWith(online: !state.online);
}

final posUiProvider = NotifierProvider<PosUiController, PosUiState>(
  PosUiController.new,
);

/// The order types THIS branch actually offers (POS-BE-005).
///
/// The till must never show a type the branch does not support: the cashier
/// would ring a whole ticket and only discover at settlement that the server
/// refuses it. The rule is mirrored from `PosOrderService` exactly — an empty
/// list on the branch means "everything allowed" there, so it means the same
/// here. An unknown wire value is dropped rather than throwing (rule 11).
final branchOrderTypesProvider = Provider<List<OrderType>>((ref) {
  final branchId = ref.watch(terminalProfileProvider).branchId;
  final branches = ref.watch(branchesProvider).valueOrNull;
  if (branchId == null || branches == null) return OrderType.values;

  final branch = branches.where((b) => b.id == branchId).firstOrNull;
  final wire = branch?.supportedOrderTypes ?? const <String>[];
  if (wire.isEmpty) return OrderType.values;

  final supported = [for (final value in wire) ?OrderType.fromWire(value)];
  // A branch whose every value this build fails to parse still has to sell.
  return supported.isEmpty ? OrderType.values : supported;
});

/// How much tax and service this till charges.
///
/// **Authored by the platform** (POS-BE-013): the bootstrap bundle carries the
/// tenant's rules, the seeder stores them, and this reads them back. Falls
/// back to the device default only when the till has never been seeded — and
/// that fallback is what `TaxSource.deviceConfig` makes a receipt disclose.
final taxConfigProvider = Provider<TaxConfig>((ref) {
  return ref.watch(moneyConfigProvider).valueOrNull ?? const TaxConfig();
});

final moneyConfigProvider = FutureProvider<TaxConfig?>((ref) async {
  final config = ref.watch(deploymentProvider);
  final restaurantId = ref.watch(terminalProfileProvider).restaurantId;
  if (restaurantId == null || PosDatabase.hostFor(config) == null) return null;

  try {
    final rows = await ref
        .watch(posDatabaseProvider)
        .query(
          config,
          'SELECT payload FROM pos_money_config WHERE restaurant_id = @restaurant',
          parameters: {'restaurant': restaurantId},
        );
    if (rows.isEmpty) return null;
    final payload = switch (rows.first[0]) {
      final Map<String, Object?> m => m,
      final Map m => m.cast<String, Object?>(),
      final String raw => switch (jsonDecode(raw)) {
        final Map m => m.cast<String, Object?>(),
        _ => null,
      },
      _ => null,
    };
    return payload == null ? null : MoneyConfigCodec.toTaxConfig(payload);
  } on Object {
    // A till that cannot read its rules keeps the device default and says so
    // on the slip, rather than refusing to sell.
    return null;
  }
});

/// The live ticket.
///
/// All mutations delegate to [TicketEngine], which is pure and unit-tested. The
/// controller's only job is to hold the current value and surface refusals.
class TicketController extends Notifier<Ticket> {
  @override
  Ticket build() {
    // READ, never watch. A Notifier rebuilds when a watched provider changes,
    // and rebuilding this one throws the live ticket away — so watching the
    // tax config meant that the moment the platform's rates finished loading,
    // the cashier's seated table and every line on it vanished mid-sale.
    //
    // The rates still arrive: the listener below folds them onto the ticket
    // in place, which is the difference between updating a bill and losing
    // one.
    ref.listen<TaxConfig>(taxConfigProvider, (previous, next) {
      if (previous == next) return;
      state = state.copyWith(taxConfig: next);
    });

    return Ticket(
      id: _uuid.v4(),
      orderType: OrderType.dineIn,
      // The platform's rates when it has sent any; otherwise the read-only
      // device default, which every receipt then discloses. What must never
      // happen — and used to — is the till inventing a rate the platform does
      // not charge: the customer pays it, the ledger does not record it, and
      // only `totals_mismatch` notices after the money has moved.
      taxConfig: ref.read(taxConfigProvider),
    );
  }

  /// Set by the last operation that was refused, so the screen can toast it.
  TicketRefusal? lastRefusal;

  bool _apply(TicketResult result) {
    lastRefusal = result.refusal;
    if (result.isOk) state = result.ticket!;
    return result.isOk;
  }

  bool addProduct(
    Product product, {
    List<Modifier> modifiers = const [],
    List<ModifierGroup> groups = const [],
    int quantity = 1,
  }) => _apply(
    TicketEngine.addLine(
      state,
      product,
      modifiers: modifiers,
      groups: groups,
      quantity: quantity,
    ),
  );

  void changeQuantity(String lineKey, int delta) =>
      state = TicketEngine.changeQuantity(state, lineKey, delta);

  void removeLine(String lineKey) =>
      state = TicketEngine.removeLine(state, lineKey);

  void sendRound() => state = TicketEngine.sendRound(state);

  /// Take back a ticket a sheet has edited.
  ///
  /// Distinct from [adopt], which takes over a *different* ticket wholesale
  /// when a table is resumed. This is the same sale, changed: the discount
  /// sheet prices against a copy — it has to, because it shows the resulting
  /// total before the cashier commits — so what comes back is a whole ticket
  /// rather than an instruction.
  ///
  /// Guarded on the id, so a sheet still open when the sale was cleared cannot
  /// resurrect the ticket it was editing.
  void applyEdit(Ticket next) {
    if (next.id != state.id) return;
    state = next;
  }

  void setLineNote(String lineKey, String note) {
    final result = TicketEngine.setLineNote(state, lineKey, note);
    if (result.isOk) state = result.ticket!;
  }

  void setOrderType(OrderType type) =>
      state = TicketEngine.setOrderType(state, type);

  void attachTable(DiningTable table) => state = TicketEngine.attachTable(
    state,
    table.id,
    table.label,
    guests: table.seats,
  );

  bool addTender({
    required int typeId,
    required String label,
    Money? amount,
    String? reference,
  }) => _apply(
    TicketEngine.addTender(
      state,
      typeId: typeId,
      label: label,
      amount: amount,
      reference: reference,
    ),
  );

  void removeTenderAt(int index) =>
      state = TicketEngine.removeTenderAt(state, index);

  /// Take over a parked ticket wholesale — resuming a table from the floor.
  /// The id comes with it: the parked ticket IS the transaction, and minting
  /// a new id on resume would make its eventual settlement look like a
  /// different sale to the server's idempotency.
  void adopt(Ticket ticket) => state = ticket;

  /// Start a fresh ticket with a **new** client transaction id. The id must
  /// change here and only here — reusing one would make the next sale look like
  /// a replay of the last.
  void reset() => state = TicketEngine.clear(state, newId: _uuid.v4());
}

final ticketProvider = NotifierProvider<TicketController, Ticket>(
  TicketController.new,
);

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredShiftRepository();
  }
  return PostgresShiftRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
});

/// Who entered a PIN on this till.
///
/// Null until somebody signs in. The till deliberately does not remember across
/// a restart: whoever opens the drawer next has to say who they are, because the
/// shift they open makes them answerable for what is in it.
final signedInStaffProvider =
    NotifierProvider<SignedInStaffController, PosStaff?>(
      SignedInStaffController.new,
    );

class SignedInStaffController extends Notifier<PosStaff?> {
  @override
  PosStaff? build() => null;

  void signIn(PosStaff staff) => state = staff;

  /// Closing a shift signs the person out with it. The next shift is somebody
  /// else's responsibility until they say otherwise.
  void signOut() => state = null;
}

/// The shift this terminal currently has open, if any.
///
/// Re-read rather than held: a till restarted mid-service must come back to the
/// same open shift, because the drawer never closed.
final shiftProvider = FutureProvider<PosShift?>(
  (ref) => ref.watch(shiftRepositoryProvider).current(),
);

/// Endpoint probe. Swapped for a real HTTP HEAD against `/api/health` once a
/// backend contract exists to point at.
final connectivityProbeProvider = Provider<ConnectivityProbe>(
  (ref) => const FakeConnectivityProbe(),
);

/// Licence verification.
///
/// **Signatures are checked for real.** This used to be bound to
/// `FakeLicenceService`, which accepted any non-empty key — `HELLO` licensed a
/// terminal for a year — and skipped the signature check entirely. The verifier
/// now holds the Ed25519 public key that ships in the binary, and only a file
/// signed by the matching private key activates anything.
///
/// `remote` points at the **hosted platform**, never at the terminal's own
/// `baseUrl`. Licence activation is now the first step of setup, before any
/// address has been typed, and an offline terminal never has one at all — see
/// `PlatformEndpoint`. Importing a signed `.xlic` file remains the other path,
/// and is the only one that works with no internet at all.
///
/// The fingerprint follows the terminal id — generated once on this machine and
/// never reissued — so a licence can be pinned to a till. It is hashed, so what
/// a licence carries says nothing about the machine or the person on it.
final licenceServiceProvider = Provider<LicenceService>((ref) {
  final platform = ref.watch(platformLicenceApiProvider);
  return DefaultLicenceService(
    verifier: LicenseVerifier(publicKeyBytes: LicenseKeys.current),
    store_: ref.watch(licenseStoreProvider),
    fingerprint: TerminalIdFingerprint(
      ref.watch(terminalProfileProvider).installationId,
    ),
    clock: DateTime.now,
    remote: platform.fetchByKey,
  );
});

/// Overridden in tests so activation never reaches the network.
final platformLicenceApiProvider = Provider<PlatformLicenceApi>(
  (ref) => PlatformLicenceApi(
    baseUrl: () {
      final config = ref.read(deploymentProvider);

      // Most specific first. An address typed on the licence step wins over
      // everything — it is the operator saying "not that platform, this one",
      // which is the only way to activate a key issued somewhere else.
      final licenceServer = config.licenceServerUrl;
      if (licenceServer != null && licenceServer.isNotEmpty) {
        return licenceServer;
      }

      // Then the terminal's own platform, on the cloud path: the platform that
      // takes this till's money is the platform that licenses it, and a dev
      // till pointed at localhost must not send its key to production.
      final configured = config.baseUrl;
      return (configured == null || configured.isEmpty)
          ? PlatformEndpoint.base
          : configured;
    },
    tenantSlug: () => ref.read(deploymentProvider).tenantSlug,
    deploymentMode: () => ref.read(deploymentProvider).mode.wire,
  ),
);

/// Where the installed licence lives between launches.
///
/// On disk, not in memory: a licence that had to be reinstalled on every launch
/// would make the till unusable the first morning somebody restarted it.
final licenseStoreProvider = Provider<LicenseStore>(
  (ref) => FileLicenseStore(),
);

/// The language this terminal is operated in.
///
/// A property of the **terminal**, not of the person signed into it. A till in
/// Maadi is set up once in Arabic and stays Arabic through every shift; making
/// it follow the cashier would mean the screen changed shape at handover, in
/// the middle of service.
///
/// Applied the moment it is chosen in the wizard rather than at the end of it,
/// so picking العربية shows the installer what they are actually choosing —
/// mirrored layout and all — while they can still change their mind.
class TerminalLocaleController extends Notifier<Locale> {
  @override
  Locale build() =>
      Locale(ref.watch(terminalBootProvider).config?.languageCode ?? 'en');

  /// Switches the language NOW and writes it to the terminal's config file.
  ///
  /// The write is what makes the choice a property of the terminal rather than
  /// of the session. Without it, `build()` re-reads the language the wizard
  /// wrote on the next launch, so a till switched to العربية from the Settings
  /// menu came back up in English the following morning — the language looked
  /// like it had simply been ignored.
  ///
  /// Deliberately not awaited. The screen must flip on this frame; a config
  /// file is not worth a spinner in front of a queue. And deliberately silent
  /// on failure: a read-only config file is a reason to lose the choice at the
  /// next restart, not a reason to refuse the one on screen now.
  void apply(String languageCode) {
    state = Locale(languageCode);
    unawaited(_persist(languageCode));
  }

  /// Rewrites the saved config with [languageCode], leaving every other field
  /// as it was.
  ///
  /// A terminal with no config yet is left alone rather than given a partial
  /// one: that is a machine still inside the wizard, and the wizard writes the
  /// whole file — language included — when it finishes.
  Future<void> _persist(String languageCode) async {
    final store = ref.read(terminalConfigStoreProvider);
    try {
      final saved = await store.read();
      if (saved == null || saved.languageCode == languageCode) return;
      await store.write(saved.copyWith(languageCode: languageCode));
    } on Exception {
      // See above: the language on screen is already correct.
    }
  }
}

final localeProvider = NotifierProvider<TerminalLocaleController, Locale>(
  TerminalLocaleController.new,
);

/// Light or dark, for the whole app. `null` = follow the machine.
///
/// A nullable [Brightness] rather than material's `ThemeMode`, so this file
/// keeps importing `widgets.dart` alone — the providers are shared with pure
/// Dart tests and pulling material in for one enum is a poor trade. `null`
/// carries exactly what `ThemeMode.system` would.
///
/// A property of the **terminal**, like the language: a till set up facing a
/// window stays light through every shift, and one in a dim back room stays
/// dark, whoever is signed in.
class BrightnessController extends Notifier<Brightness?> {
  @override
  Brightness? build() => ref.watch(terminalBootProvider).config?.brightness;

  /// Pass null to hand the choice back to the machine.
  void apply(Brightness? brightness) {
    state = brightness;
    unawaited(_persist(brightness));
  }

  /// Flip away from what is on screen NOW, not from `state`: while following
  /// the system, `state` is null and says nothing about which way the toggle
  /// should go — flipping from it would make the first tap a no-op half the
  /// time.
  void toggle(Brightness showing) =>
      apply(showing == Brightness.dark ? Brightness.light : Brightness.dark);

  /// Written for the same reason the language is, and with the same bargain:
  /// not awaited, because the repaint must not wait on a file, and silent on
  /// failure, because what is on screen is already what was asked for. See
  /// [TerminalLocaleController.apply].
  Future<void> _persist(Brightness? brightness) async {
    final store = ref.read(terminalConfigStoreProvider);
    try {
      final saved = await store.read();
      if (saved == null || saved.brightness == brightness) return;
      await store.write(saved.copyWith(brightness: brightness));
    } on Exception {
      // See above.
    }
  }
}

final brightnessProvider = NotifierProvider<BrightnessController, Brightness?>(
  BrightnessController.new,
);

/// The till's words, for code that has no [BuildContext] to reach them
/// through — controllers that produce operator-facing text, mainly.
final stringsProvider = Provider<AppStrings>(
  (ref) => AppStrings.of(ref.watch(localeProvider)),
);

/// What this process found on disk before its first frame.
///
/// Overridden in `main()` with the configuration the last completed setup wrote
/// and the credential the keystore returned. A plain value rather than a
/// `FutureProvider` on purpose: the router decides where the first frame goes
/// by reading it synchronously, and a till that flashed the setup wizard for
/// one frame every morning before redirecting would read as broken to the
/// person opening the restaurant.
///
/// [TerminalBoot.none] — the default — is what every widget test gets, and what
/// a machine that has never been set up gets: the wizard.
final terminalBootProvider = Provider<TerminalBoot>((ref) => TerminalBoot.none);

/// Where a finished setup is written. The one place that knows there is a file.
final terminalConfigStoreProvider = Provider<TerminalConfigStore>(
  (ref) => FileTerminalConfigStore(),
);

/// How this terminal is deployed. Written once by the setup wizard, then read
/// by everything that needs to know whether a server exists to talk to.
class DeploymentController extends Notifier<DeploymentConfig> {
  @override
  DeploymentConfig build() =>
      ref.watch(terminalBootProvider).config?.deployment ??
      DeploymentConfig.unconfigured;

  void apply(DeploymentConfig config) => state = config;

  void reset() => state = DeploymentConfig.unconfigured;
}

final deploymentProvider =
    NotifierProvider<DeploymentController, DeploymentConfig>(
      DeploymentController.new,
    );

/// True once first-run setup has been completed on this terminal.
///
/// Read from the saved configuration at boot, which is what makes the wizard a
/// genuinely one-time screen. `SavedTerminalConfig.isUsable` is what decides:
/// a config naming no terminal, or no database to reach, is not a setup that
/// finished, whatever the flag in the file says.
class SetupCompletionController extends Notifier<bool> {
  @override
  bool build() => ref.watch(terminalBootProvider).isConfigured;

  void markComplete() => state = true;

  void reset() => state = false;
}

final setupCompleteProvider = NotifierProvider<SetupCompletionController, bool>(
  SetupCompletionController.new,
);

/// Send this terminal back to the setup wizard.
///
/// Needed for the two things that actually happen to a till: it moves to a new
/// branch server, or its keystore loses the database password and nobody can
/// tell it a new one. Without an escape hatch the only route out of either is
/// deleting `config.json` by hand from Application Support, which is a support
/// call and a screen-share.
///
/// **The terminal id survives.** It is what the licence is pinned to, so
/// reissuing it here would turn a reconfiguration into a licence support
/// ticket. Sales are untouched: they are rows in PostgreSQL, not files on this
/// machine.
class TerminalReset {
  TerminalReset(this._ref);

  final Ref _ref;

  Future<void> run() async {
    // Disk first. A reset that cleared memory and then failed to clear the file
    // would come back on the next launch, which is the opposite of what the
    // operator just asked for.
    await _ref.read(terminalConfigStoreProvider).clear();
    await _ref.read(posDbCredentialsStoreProvider).forget();

    _ref.read(setupCompleteProvider.notifier).reset();
    _ref.read(deploymentProvider.notifier).reset();
    _ref.read(terminalProfileProvider.notifier).reset();
    // Drop any draft left over from the wizard's last run, so it reopens seeded
    // from what is actually still true rather than from a half-filled attempt.
    _ref.invalidate(setupProvider);
  }
}

final terminalResetProvider = Provider<TerminalReset>(TerminalReset.new);

/// The licence entitlement currently in force.
///
/// Re-read at boot and before each shift opens rather than cached for the
/// process lifetime, so a renewal takes effect without restarting the till.
final licenceEntitlementProvider = FutureProvider<LicenseEntitlement>(
  (ref) =>
      ref.watch(licenceServiceProvider).current(ref.watch(deploymentProvider)),
);

/// The claims of the licence currently installed, or null when there is none.
///
/// Separate from [licenceEntitlementProvider] because an entitlement is a
/// verdict — may this till sell, may it open a shift — and the claims are the
/// terms behind it. The management screens need the terms: `max_users` is a
/// number somebody has to be shown and refused against, and no verdict carries
/// it.
final licenceClaimsProvider = FutureProvider<LicenseClaims?>((ref) async {
  final file = await ref.watch(licenceServiceProvider).installed();
  return file == null ? null : LicenseVerifier.claimsOf(file);
});

class TerminalProfileController extends Notifier<TerminalProfile> {
  @override
  TerminalProfile build() =>
      ref.watch(terminalBootProvider).config?.terminal ??
      TerminalProfile(installationId: _uuid.v4());

  void apply(TerminalProfile profile) => state = profile;

  /// Keeps the terminal id: it is what the licence is pinned to, and a till
  /// that reissued it on every reconfiguration would need a new licence each
  /// time.
  void reset() => state = TerminalProfile(
    terminalId: state.terminalId,
    installationId: state.installationId,
  );
}

final terminalProfileProvider =
    NotifierProvider<TerminalProfileController, TerminalProfile>(
      TerminalProfileController.new,
    );

/// The password the setup wizard collected, held for this process.
///
/// Separate from [posDbCredentialsProvider] only so the wizard has something
/// typed to write to while everything else depends on the interface. Both
/// resolve to the same object in production.
final posDbCredentialsStoreProvider = Provider<MutablePosDbCredentials>(
  (ref) => MutablePosDbCredentials(),
);

/// Where the till's database password comes from.
///
/// The role is `pos_till` — granted `SELECT` and `INSERT` on the POS tables and
/// nothing else. Never a superuser, never `DELETE`, never DDL, so a recovered
/// credential cannot rewrite history.
///
/// Kept in the OS keystore between launches — Keychain on macOS, DPAPI on
/// Windows — never in `config.json`: a database password written to a file is a
/// password that gets emailed to support. The keystore binding is attached in
/// `main()`, so a widget test gets the in-memory one and touches no keychain.
final posDbCredentialsProvider = Provider<PosDbCredentials>(
  (ref) => ref.watch(posDbCredentialsStoreProvider),
);

/// The connection pool to the branch server. One per app.
final posDatabaseProvider = Provider<PosDatabase>((ref) {
  final database = PosDatabase(
    credentials: ref.watch(posDbCredentialsProvider),
  );
  ref.onDispose(database.close);
  return database;
});

/// Which tenant, branch and terminal a write belongs to.
///
/// Null until provisioning has supplied all four facts — which is deliberate:
/// an order that cannot say which restaurant and branch it belongs to must not
/// be written at all.
final posWriteContextProvider = Provider<PosWriteContext?>((ref) {
  final profile = ref.watch(terminalProfileProvider);
  final restaurantId = profile.restaurantId;
  final branchId = profile.branchId;
  final terminalId = profile.terminalId;
  final branchCode = profile.branchCode;

  if (restaurantId == null ||
      branchId == null ||
      terminalId == null ||
      branchCode == null) {
    return null;
  }
  return PosWriteContext(
    restaurantId: restaurantId,
    branchId: branchId,
    terminalId: terminalId,
    branchCode: branchCode,
  );
});

// ---------------------------------------------------------------------------
// Administration
// ---------------------------------------------------------------------------

/// The administrator database password, for this session only.
///
/// Null until somebody opening Management supplies it. Deliberately NOT
/// persisted: `bin/pos_migrate.dart` refuses to grant the till role and the
/// administrator role to the same name, and says why — the till credential
/// sits on a machine in a public room, often with its password in a file
/// beside it. Writing the administrator's password to that same disk would
/// hand back everything the split was protecting.
///
/// Lost on exit, by design. A manager entering the back office types it; a
/// cashier at the counter never sees it.
class AdminDbCredential extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = (value?.isEmpty ?? true) ? null : value;

  void forget() => state = null;
}

final adminDbCredentialProvider = NotifierProvider<AdminDbCredential, String?>(
  AdminDbCredential.new,
);

/// The same deployment, connecting as the administrator role.
final adminDeploymentProvider = Provider<DeploymentConfig>((ref) {
  final config = ref.watch(deploymentProvider);
  return config.copyWith(databaseUser: config.adminDatabaseUser);
});

/// A SECOND pool, for the administrator connection.
///
/// Not the shared [posDatabaseProvider]: that keys its single pool on
/// host/port/database/user/password, so alternating a till query and an admin
/// query on one instance would close and reopen the pool every time. Two pools
/// cost two idle connections; one pool would cost a reconnect per statement.
final adminPosDatabaseProvider = Provider<PosDatabase>((ref) {
  final credentials = MutablePosDbCredentials()
    ..set(ref.watch(adminDbCredentialProvider));
  final database = PosDatabase(credentials: credentials);
  ref.onDispose(database.close);
  return database;
});

/// Roles, staff and the audit ledger, bound the same way as everything else:
/// PostgreSQL when this terminal has a branch server, and an `Unconfigured…`
/// binding that refuses out loud when it does not.
/// Authoring the menu. **Offline terminals only.**
///
/// Not a preference and not a feature flag: `BootstrapSeeder._seedCatalog`
/// DELETEs the whole catalogue and re-inserts the platform's rows, so a menu
/// authored on a CLOUD till survives until its next bundle and no longer. The
/// platform is the single author there — the coordination docs say so, and add
/// "do not build a merge path for data with one author". An offline restaurant
/// has no platform to be that author, which is the only reason this exists.
///
/// Returns null rather than an Unconfigured double, because "this terminal
/// does not author its menu" is a different statement from "this terminal has
/// no database", and the Menu pane should not appear at all in the first case.
final catalogAdminRepositoryProvider = Provider<CatalogAdminRepository?>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (config.mode != DeploymentMode.offline) return null;
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  return PostgresCatalogAdminRepository(
    // Writes only, so there is no read context here: the catalogue is READ
    // through `catalogRepositoryProvider` on the till's credential, which is
    // what the sale screen already uses.
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    offline: true,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
});

/// The queue of receipts owed to Egypt's tax authority.
///
/// Null where there is no database to queue into. Not null on a cloud till:
/// the obligation is the restaurant's, not the deployment's, and a cloud
/// terminal in Cairo owes the same receipts an offline one does.
final etaQueueRepositoryProvider = Provider<EtaQueueRepository?>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  return PostgresEtaQueueRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

/// What the queue looks like right now.
///
/// **Read on a clock that is passed in**, so the pill on the shell and the
/// screen behind it never disagree about which receipts are late.
final etaQueueSummaryProvider = FutureProvider<EtaQueueSummary>((ref) async {
  final repository = ref.watch(etaQueueRepositoryProvider);
  if (repository == null) return EtaQueueSummary.empty;
  return repository.summary(now: DateTime.now());
});

final etaOutstandingProvider = FutureProvider<List<EtaSubmission>>((ref) async {
  final repository = ref.watch(etaQueueRepositoryProvider);
  if (repository == null) return const [];
  return repository.outstanding();
});

/// Who the receipt says sold the food.
///
/// Bound whenever the TILL connection works, unlike the menu author: every
/// terminal prints a slip with the restaurant's name and address on it, cloud
/// and offline alike, and only the write side needs Management's credential.
final receiptProfileRepositoryProvider = Provider<ReceiptProfileRepository?>((
  ref,
) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  return PostgresReceiptProfileRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    readDatabase: ref.watch(posDatabaseProvider),
    readConfig: config,
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

/// The profile as the receipt reads it.
///
/// A blank profile on a branch nobody has set up, never an error: a till that
/// refused to print because nobody typed an address would be a till that
/// stopped the restaurant trading over a settings field.
final receiptProfileProvider = FutureProvider<ReceiptProfile>((ref) async {
  final repository = ref.watch(receiptProfileRepositoryProvider);
  if (repository == null) return const ReceiptProfile(branchId: 0);
  return repository.load();
});

final rolesRepositoryProvider = Provider<RolesRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  // Bound whenever the TILL connection works, credential or not: signing in
  // reads staff and roles, and a cashier at the counter must not need the
  // back office's password to do it. The writes inside refuse on their own.
  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredRolesRepository();
  }
  return PostgresRolesRepository(
    // Writes go through the administrator connection…
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    // …and reads through the till's, which holds SELECT and nothing more.
    readDatabase: ref.watch(posDatabaseProvider),
    readConfig: config,
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
});

final staffDirectoryRepositoryProvider = Provider<StaffDirectoryRepository>((
  ref,
) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  // Bound whenever the TILL connection works, credential or not: signing in
  // reads staff and roles, and a cashier at the counter must not need the
  // back office's password to do it. The writes inside refuse on their own.
  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredStaffDirectoryRepository();
  }
  return PostgresStaffDirectoryRepository(
    // Writes go through the administrator connection…
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    // …and reads through the till's, which holds SELECT and nothing more.
    readDatabase: ref.watch(posDatabaseProvider),
    readConfig: config,
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
});

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredAuditRepository();
  }
  // The ledger stays on the TILL connection: the till writes to it itself
  // when a shift opens or a receipt is reprinted, long before anybody is in
  // the back office. It is granted SELECT + INSERT and nothing else, and the
  // table's trigger refuses UPDATE and DELETE from any connection.
  return PostgresAuditRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
    // Read, not watched, for the same reason the orders repository does it: an
    // audit row belongs to the shift that was open when the thing happened.
    shiftId: ref.read(shiftProvider).valueOrNull?.id,
  );
});

final rolesProvider = FutureProvider<List<PosRole>>(
  (ref) => ref.watch(rolesRepositoryProvider).all(),
);

final staffDirectoryProvider = FutureProvider<List<PosStaff>>(
  (ref) => ref.watch(staffDirectoryRepositoryProvider).all(),
);

/// Whether the person currently signed in at this till may do something.
///
/// Reads [signedInStaffProvider], which is null until somebody enters a PIN —
/// and null is a denial, not a permissive default. An unattended till must not
/// be a till with every permission.
///
/// Widgets watch this to disable a control; the repositories ask
/// [Authorization] the same question before they write. The screen can
/// therefore only ever be *more* restrictive than the data layer, never less,
/// which is the harmless direction for the two to disagree in.
final canProvider = Provider.family<PermissionDecision, String>(
  (ref, capability) =>
      Authorization.check(ref.watch(signedInStaffProvider), capability),
);
