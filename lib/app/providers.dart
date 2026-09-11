import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../core/config/printer_config.dart';
import '../core/config/terminal_config.dart';
import '../core/config/terminal_profile.dart';
import '../core/l10n/app_strings.dart';
import '../core/money/money.dart';
import '../core/network/connectivity_probe.dart';
import '../data/backup/backup_service.dart';
import '../data/backup/pg_archive.dart';
import '../data/backup/pg_tools.dart';
import '../data/config/file_secret_store.dart';
import '../data/config/pos_db_secret_store.dart';
import '../data/config/terminal_config_store.dart';
import '../data/hardware/network_printer_ports.dart';
import '../data/postgres/pos_database.dart';
import '../data/postgres/postgres_admin_repositories.dart';
import '../data/postgres/postgres_backup_repository.dart';
import '../data/postgres/postgres_catalog_admin_repository.dart';
import '../data/postgres/postgres_catalog_repository.dart';
import '../data/postgres/postgres_directory_repositories.dart';
import '../data/postgres/postgres_discounts_repository.dart';
import '../data/postgres/postgres_reason_repository.dart';
import '../data/postgres/postgres_floor_repository.dart';
import '../data/postgres/postgres_order_history_repository.dart';
import '../data/postgres/postgres_business_day_repository.dart';
import '../data/postgres/postgres_cash_movements_repository.dart';
import '../data/postgres/postgres_order_types_repository.dart';
import '../data/postgres/postgres_orders_repository.dart';
import '../data/eta/filing_orders_repository.dart';
import '../domain/services/eta_filing.dart';
import '../data/eta/filing_refunds_repository.dart';
import '../data/eta/eta_filer.dart';
import '../data/postgres/postgres_eta_queue_repository.dart';
import '../data/postgres/postgres_receipt_profile_repository.dart';
import '../data/postgres/postgres_service_charges_repository.dart';
import '../domain/models/pos_unit.dart';
import '../domain/models/stock_item.dart';
import '../data/postgres/postgres_stock_items_repository.dart';
import '../data/postgres/postgres_units_repository.dart';
import '../data/postgres/postgres_suppliers_repository.dart';
import '../data/postgres/postgres_supplier_invoices_repository.dart';
import '../data/postgres/postgres_purchase_orders_repository.dart';
import '../data/postgres/postgres_receiving_repository.dart';
import '../data/postgres/postgres_settings_repository.dart';
import '../data/postgres/postgres_tender_types_repository.dart';
import '../data/postgres/postgres_refunds_repository.dart';
import '../data/postgres/money_config_codec.dart';
import '../data/postgres/postgres_parked_tickets.dart';
import '../data/postgres/postgres_print_queue_repository.dart';
import '../data/postgres/postgres_shift_repository.dart';
import '../data/unconfigured/unconfigured_repositories.dart';
import '../features/history/history_scope.dart';
import '../features/licensing/data/file_license_store.dart';
import '../features/licensing/data/licence_service.dart';
import '../features/licensing/data/license_keys.dart';
import '../features/licensing/data/license_store.dart';
import '../features/licensing/data/platform_licence_api.dart';
import '../features/licensing/domain/license_verifier.dart';
import '../features/licensing/domain/license.dart';
import '../features/setup/application/setup_controller.dart';
import '../domain/models/backup.dart';
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
import '../domain/models/order_type_config.dart';
import '../domain/models/permissions.dart';
import '../domain/models/purchase_order.dart';
import '../domain/models/tax.dart';
import '../domain/models/supplier.dart';
import '../domain/models/supplier_invoice.dart';
import '../domain/models/receipt_profile.dart';
import '../domain/models/service_charge.dart';
import '../domain/models/tender_method.dart';
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
  final filer = ref.watch(etaFilerProvider);
  if (filer == null) return synced;

  // Wherever sales are taken, the catch-up runs: a sale the settlement could
  // not file is found on the next pass rather than never.
  ref.watch(etaReconcilerProvider);

  return FilingOrdersRepository(
    synced,
    filer: filer,
    onProblem: (problem) => reportEtaProblem(ref.container, problem),
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
///
/// **Narrowed to what the person at the till may read** before it reaches the
/// repository — their own sales, without `order.view_all`. Here rather than
/// in the screen because this is the one road to the data: a second screen
/// built on this provider inherits the rule instead of having to remember it.
/// See [HistoryScope].
final orderHistoryProvider =
    FutureProvider.family<List<OrderRecord>, OrderHistoryQuery>((ref, query) {
      final scoped = HistoryScope.scope(
        query,
        ref.watch(signedInStaffProvider),
      );
      if (scoped == null) return const <OrderRecord>[];
      return ref.watch(orderHistoryRepositoryProvider).search(scoped);
    });

/// One order, opened from the list — or null when it is not the viewer's to
/// open, which the pane already shows as "no longer there".
final orderDetailProvider = FutureProvider.family<OrderRecordDetail?, int>((
  ref,
  orderId,
) async {
  final viewer = ref.watch(signedInStaffProvider);
  final repository = ref.watch(orderHistoryRepositoryProvider);
  final detail = await repository.detail(orderId);
  if (detail == null || !HistoryScope.mayOpen(detail.order, viewer)) {
    return null;
  }
  return detail;
});

/// The tills at this branch, for the history screen's terminal filter.
final historyTerminalsProvider = FutureProvider<List<HistoryTerminal>>(
  (ref) => ref.watch(orderHistoryRepositoryProvider).terminals(),
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
  final inner = PostgresRefundsRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    context: context,
    shiftId: ref.read(shiftProvider).valueOrNull?.id,
  );

  // A refund is a receipt too — a credit note naming the sale it undoes.
  // Filed the same way a sale is, and caught up the same way if it cannot be.
  final filer = ref.watch(etaFilerProvider);
  if (filer == null) return inner;
  return FilingRefundsRepository(
    inner,
    filer: filer,
    onProblem: (problem) => reportEtaProblem(ref.container, problem),
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

/// Which printer this till prints on, and how wide its paper is.
///
/// A property of the terminal, read from `config.json` before the first frame
/// and re-applied when the wizard finishes — the same shape as
/// [DeploymentController], and for the same reason: setup completes without a
/// restart, so the value in memory has to be updated as well as the file.
class PrinterConfigController extends Notifier<PrinterConfig> {
  @override
  PrinterConfig build() =>
      ref.watch(terminalBootProvider).config?.printer ?? PrinterConfig.none;

  void apply(PrinterConfig printer) => state = printer;

  void reset() => state = PrinterConfig.none;
}

final printerConfigProvider =
    NotifierProvider<PrinterConfigController, PrinterConfig>(
      PrinterConfigController.new,
    );

/// Receipts the printer would not take.
///
/// Null where there is no database to queue into, exactly like
/// [etaQueueRepositoryProvider]: a till mid-setup has nowhere to put a failed
/// print, and the receipt path says "not printed" rather than "queued".
final printQueueRepositoryProvider = Provider<PrintQueueRepository?>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  return PostgresPrintQueueRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    context: context,
  );
});

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

/// Everything this till has open but is not ringing up right now.
///
/// **Two collections, because only one kind of open ticket has a table to hold
/// it.** [onTables] is the dine-in floor, keyed by table id, and it is what the
/// floor screen paints. [held] is every parked ticket with no table — a
/// takeaway or a delivery the cashier put down to serve the person behind, and
/// until now a ticket the till had no way to put down at all.
///
/// The alternative was one map keyed by the client transaction id with the
/// table as an attribute. It was rejected because the floor's question is
/// "what is on table 12", asked on every repaint of every tile: answering it
/// from a transaction-keyed map means a scan per tile, and the one invariant
/// that matters most on a floor — at most one open ticket per table — stops
/// being a property of the data structure and becomes something code has to
/// remember to check.
class OpenTickets {
  const OpenTickets({this.onTables = const {}, this.held = const []});

  /// Parked dine-in tickets, by table id.
  final Map<int, Ticket> onTables;

  /// Parked tickets with no table, oldest first.
  final List<Ticket> held;

  bool get isEmpty => onTables.isEmpty && held.isEmpty;

  /// The held tickets that are not the one on screen.
  ///
  /// A resumed hold keeps its parked row until it is paid or voided — a crash
  /// between resume and payment must not lose the sale — so the live ticket is
  /// routinely still in [held]. Offering it back to the cashier as something to
  /// resume would be offering them the screen they are already looking at.
  List<Ticket> heldOtherThan(String liveTicketId) => [
    for (final ticket in held)
      if (ticket.id != liveTicketId) ticket,
  ];

  OpenTickets copyWith({Map<int, Ticket>? onTables, List<Ticket>? held}) =>
      OpenTickets(
        onTables: onTables ?? this.onTables,
        held: held ?? this.held,
      );
}

/// The till's parked work: the dine-in floor, and the tickets on the counter.
///
/// Write-through to `pos_parked_tickets`, so all of it survives a restart:
/// parking upserts, settling and voiding delete, and the boot hydrates.
class OpenTicketsController extends Notifier<OpenTickets> {
  @override
  OpenTickets build() {
    ref.onDispose(() => _disposed = true);
    // Put the floor back the way the restart found it. Async on purpose —
    // the first frame must not wait on a database — and merge-not-replace,
    // so a table seated in the seconds before hydration lands wins over its
    // own stale disk copy.
    Future.microtask(_hydrate);
    return const OpenTickets();
  }

  bool _disposed = false;

  PostgresParkedTickets? get _store {
    final config = ref.read(deploymentProvider);
    // The write context rather than the restaurant id alone, because a parked
    // ticket with no table can only say which shop it belongs to by carrying
    // the branch — and a held ticket the day-close check cannot see is an
    // unpaid sale that disappears at midnight. A till that cannot name its
    // branch parks in memory only, which is what it already did before it was
    // adopted.
    final context = ref.read(posWriteContextProvider);
    if (context == null || PosDatabase.hostFor(config) == null) return null;

    return PostgresParkedTickets(
      database: ref.read(posDatabaseProvider),
      config: config,
      restaurantId: context.restaurantId,
      branchId: context.branchId,
    );
  }

  Future<void> _hydrate() async {
    final store = _store;
    if (store == null) return;
    try {
      final catalog = await ref.read(catalogProvider.future);
      final parked = await store.load(catalog);
      if (_disposed || (parked.onTables.isEmpty && parked.held.isEmpty)) {
        return;
      }
      // Merge, never replace: a ticket parked in the seconds before hydration
      // landed wins over its own stale disk copy — and is not listed twice
      // beside it, which is what a plain concatenation would have done.
      final live = {for (final ticket in state.held) ticket.id};
      state = OpenTickets(
        onTables: {...parked.onTables, ...state.onTables},
        held: [
          for (final ticket in parked.held)
            if (!live.contains(ticket.id)) ticket,
          ...state.held,
        ],
      );
    } on Object {
      // A floor that cannot hydrate is empty, not broken — parking still
      // works and writes through from here on.
    }
  }

  /// Put a ticket down.
  ///
  /// A seated ticket goes onto its table; anything else joins [OpenTickets.held]
  /// under its own transaction id. An empty ticket is ignored rather than
  /// refused — leaving the sale screen with nothing rung up is normal, not an
  /// error, and there is nothing to come back to.
  void park(Ticket ticket) {
    if (ticket.lines.isEmpty) return;
    final tableId = ticket.tableId;

    state = tableId != null
        ? state.copyWith(onTables: {...state.onTables, tableId: ticket})
        // Keyed on the transaction id, so parking the same ticket twice
        // replaces the earlier copy instead of holding two versions of one
        // sale — which is what a cashier does when they add a line to a
        // resumed hold and put it down again.
        : state.copyWith(
            held: [
              for (final held in state.held)
                if (held.id != ticket.id) held,
              ticket,
            ],
          );

    unawaited(_store?.save(ticket) ?? Future.value());
  }

  Ticket? at(int tableId) => state.onTables[tableId];

  /// This ticket's money has been dealt with — paid, or voided. Let it go.
  ///
  /// Takes the whole ticket rather than a table id: a held ticket has no table
  /// to be identified by, and a ticket that was seated when it was parked and
  /// is not now (somebody switched a dine-in order to takeaway, which clears
  /// the table) has to release the row it actually left behind.
  void settle(Ticket ticket) {
    final tables = {...state.onTables}
      ..removeWhere(
        (tableId, parked) =>
            tableId == ticket.tableId || parked.id == ticket.id,
      );
    final held = [
      for (final parked in state.held)
        if (parked.id != ticket.id) parked,
    ];

    if (tables.length != state.onTables.length ||
        held.length != state.held.length) {
      state = OpenTickets(onTables: tables, held: held);
    }
    // The disk row goes regardless of what memory held: a settled sale must
    // not resurrect on the next boot.
    unawaited(
      _store?.remove(tableId: ticket.tableId, transactionId: ticket.id) ??
          Future.value(),
    );
  }
}

final openTicketsProvider =
    NotifierProvider<OpenTicketsController, OpenTickets>(
      OpenTicketsController.new,
    );

/// The floor as the cashier sees it: the seeded plan overlaid with this
/// till's parked tickets — busy tiles carry their item count and total.
final floorTablesProvider = FutureProvider<List<DiningTable>>((ref) async {
  final tables = await ref.watch(tablesProvider.future);
  return overlayOpenTickets(tables, ref.watch(openTicketsProvider).onTables);
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
/// What each kind of order requires — tables, a customer, an address (§31).
///
/// Falls back to the seeded four while the query is in flight or on a till
/// with no database. A till that believed nothing was seated would hide its
/// own floor plan.
final orderTypeRulesProvider = Provider<OrderTypeRules>((ref) {
  return ref.watch(orderTypeConfigProvider).valueOrNull ??
      OrderTypeRules.fallback;
});

final orderTypeConfigProvider = FutureProvider<OrderTypeRules>((ref) async {
  final repository = ref.watch(orderTypesRepositoryProvider);
  if (repository == null) return OrderTypeRules.fallback;
  final configured = await repository.all();
  return configured.isEmpty
      ? OrderTypeRules.fallback
      : OrderTypeRules(configured);
});

/// Every order type, including the ones a branch has turned off — the editor's
/// list, not the till's. The till reads `orderTypeConfigProvider`, which hides
/// them, because a cashier must never be offered a type the branch refuses.
final orderTypesAllProvider = FutureProvider<List<OrderTypeConfig>>((
  ref,
) async {
  final repository = ref.watch(orderTypesRepositoryProvider);
  if (repository == null) return OrderTypeConfig.seeded;
  final configured = await repository.all(includeInactive: true);
  // Seeded rather than empty: migration 25 seeds four rows, and a restaurant
  // whose seed has not run yet still has four types to name.
  return configured.isEmpty ? OrderTypeConfig.seeded : configured;
});

final orderTypesRepositoryProvider = Provider<OrderTypesRepository?>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;
  return PostgresOrderTypesRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
  );
});

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
  final stored = ref.watch(moneyConfigProvider).valueOrNull ?? const TaxConfig();
  // §38's charges are folded in here rather than read separately by the ticket,
  // so there is still exactly one object that says what a sale costs on top of
  // the food. An empty list leaves `stored` untouched, which is why every
  // restaurant that has not opened the new screen is charged exactly what it
  // was.
  final charges = ref.watch(serviceChargesProvider).valueOrNull ?? const [];
  final withCharges = charges.isEmpty
      ? stored
      : stored.withServiceCharges(charges);

  // **And the named rates, which nothing loaded.** `pos_tax_groups` has been
  // seeded since the installer wrote it and `pos_products.tax_group_id` has
  // pointed at it since Wave M, but `TaxConfig.taxGroups` arrived empty on every
  // till — so `defaultTaxGroup` answered every lookup, and a bottle of water a
  // restaurant had marked zero-rated was charged the standard rate anyway. Same
  // shape as the charges above: empty changes nothing.
  final groups = ref.watch(taxGroupsProvider).valueOrNull ?? const [];
  return groups.isEmpty ? withCharges : withCharges.withTaxGroups(groups);
});

/// The restaurant's named rates (§17).
///
/// On the **till's** credential, unlike the editor's write: a ticket cannot be
/// priced without them, and the catalogue query already reads the group id off
/// every product.
final taxGroupsProvider = FutureProvider<List<TaxGroup>>((ref) async {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return const [];

  try {
    final rows = await ref.watch(posDatabaseProvider).query(
      config,
      'SELECT id, name_en, name_ar, rate_bp, is_default FROM pos_tax_groups '
      'WHERE restaurant_id = @r AND is_active ORDER BY is_default DESC, id',
      parameters: {'r': context.restaurantId},
    );
    return [
      for (final row in rows)
        TaxGroup(
          id: row[0]! as int,
          nameEn: row[1]! as String,
          nameAr: row[2] as String?,
          rateBp: row[3]! as int,
          isDefault: row[4]! as bool,
        ),
    ];
  } on Object {
    // A till that cannot read its rates keeps the single configured one rather
    // than refusing to sell — the same choice `moneyConfigProvider` makes, and
    // for the same reason.
    return const [];
  }
});

/// Every group including the retired ones — the editor's list.
final taxGroupsAllProvider = FutureProvider<List<TaxGroup>>((ref) async {
  final config = ref.watch(adminDeploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || ref.watch(adminDbCredentialProvider) == null) {
    return const [];
  }

  final rows = await ref.watch(adminPosDatabaseProvider).query(
    config,
    'SELECT id, name_en, name_ar, rate_bp, is_default, is_active '
    'FROM pos_tax_groups WHERE restaurant_id = @r '
    'ORDER BY is_default DESC, id',
    parameters: {'r': context.restaurantId},
  );
  return [
    for (final row in rows)
      TaxGroup(
        id: row[0]! as int,
        nameEn: row[1]! as String,
        nameAr: row[2] as String?,
        rateBp: row[3]! as int,
        isDefault: row[4]! as bool,
        isActive: row[5]! as bool,
      ),
  ];
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

  void setOrderType(OrderType type) => state = TicketEngine.setOrderType(
    state,
    type,
    // The restaurant's answer, not a comparison against `dineIn`. Read rather
    // than watched: switching type is a one-off act, and rebuilding the
    // controller because somebody edited an order type in the back office
    // mid-ticket would be worse than reading a value one second stale.
    seated: ref.read(orderTypeRulesProvider).requiresTable(type),
  );

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
    bool countsAsCash = false,
  }) => _apply(
    TicketEngine.addTender(
      state,
      typeId: typeId,
      label: label,
      amount: amount,
      reference: reference,
      countsAsCash: countsAsCash,
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
/// The person working this till, for everything that SHOWS or PRINTS a name.
///
/// Empty until somebody enters a PIN, and empty on purpose. The name used to
/// come off `PosSession.userName`, which the branch server answers with the
/// first active staff row for the branch — `ORDER BY st.id LIMIT 1` — rather
/// than with whoever is standing at the till. On a shared terminal that put one
/// cashier's name in the top bar all day and on the receipts every other
/// cashier printed, which is worse than showing nothing: a blank is visibly
/// missing, a plausible wrong name is not. (POS-BE-024.)
final operatorNameProvider = Provider<String>(
  (ref) => ref.watch(signedInStaffProvider)?.name ?? '',
);

/// The same person's initials, for the avatar. Empty when nobody has signed in,
/// so the chip is absent rather than showing a "?" for a person who is not
/// missing — nobody has arrived yet.
final operatorInitialsProvider = Provider<String>((ref) {
  final name = ref.watch(operatorNameProvider).trim();
  if (name.isEmpty) return '';

  final parts = name.split(RegExp(r'\s+'));
  String first(String s) => s.isEmpty ? '' : s.substring(0, 1).toUpperCase();
  return parts.length == 1
      ? first(parts.first)
      : '${first(parts.first)}${first(parts[1])}';
});

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
      Locale(ref.watch(terminalBootProvider).config?.languageCode ?? _default);

  /// Arabic, because the restaurants this ships to are in Egypt.
  ///
  /// Only the fallback moves: a terminal that has been set up reads its own
  /// `languageCode` and keeps whatever was chosen, so this is what a machine
  /// with no configuration yet opens in — the wizard, and the first frame after
  /// a reset. An installer who wants English is one item away in the Settings
  /// bar, on every screen including that first one.
  static const _default = 'ar';

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
    } on Object {
      // See above: the language on screen is already correct.
      //
      // `Object`, not `Exception`. The failures that actually reach here are
      // mostly not exceptions: a platform with no binding, a missing plugin, a
      // support directory the OS will not name all arrive as `Error`s, and an
      // `on Exception` let them escape a future nobody awaits — an unhandled
      // error thrown from a language switch that had already succeeded on
      // screen. The bargain stated above is "silent on failure", and it has to
      // hold for every kind of failure or it is not the bargain.
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
    } on Object {
      // See above — including why this is `Object` and not `Exception`.
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

/// What this terminal believes is on disk **now**.
///
/// [terminalBootProvider] is the snapshot `main()` took before the first frame,
/// and it is an override — nothing inside a running process can correct it. So
/// a reset that deleted `config.json` left everything seeded from that snapshot
/// still holding the configuration the operator had just cleared, until the
/// next launch. The wizard is where that showed: reset a till, activate another
/// restaurant's licence, and the tenant read off the DELETED config refused the
/// new one as a mismatch — naming a restaurant no longer on the machine, and
/// blaming a licence that was perfectly good.
///
/// The same value, made correctable. Read this; override [terminalBootProvider].
class TerminalSeed extends Notifier<TerminalBoot> {
  @override
  TerminalBoot build() => ref.watch(terminalBootProvider);

  /// Nothing on disk any more — called by [TerminalReset] once the file is
  /// actually gone, so that whatever rebuilds from here rebuilds as the fresh
  /// install this machine now is.
  void clear() => state = TerminalBoot.none;
}

final terminalSeedProvider = NotifierProvider<TerminalSeed, TerminalBoot>(
  TerminalSeed.new,
);

/// Where a finished setup is written. The one place that knows there is a file.
final terminalConfigStoreProvider = Provider<TerminalConfigStore>(
  (ref) => FileTerminalConfigStore(),
);

/// How this terminal is deployed. Written once by the setup wizard, then read
/// by everything that needs to know whether a server exists to talk to.
class DeploymentController extends Notifier<DeploymentConfig> {
  @override
  DeploymentConfig build() =>
      ref.watch(terminalSeedProvider).config?.deployment ??
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
  bool build() => ref.watch(terminalSeedProvider).isConfigured;

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

    // Then the snapshot the process booted from, which now describes a file
    // that is gone. Without this the wizard reopens seeded from the terminal
    // just cleared — and the tenant on that dead config refuses the next
    // restaurant's licence as though the licence were the thing at fault.
    _ref.read(terminalSeedProvider.notifier).clear();

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

// ── Purchasing ──────────────────────────────────────────────────────────────
//
// All three run on the administrator connection and none on the till's: a
// counter credential has no use for who the restaurant owes money to.

bool _canBuy(Ref ref) => ref.watch(adminDbCredentialProvider) != null;

final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) {
  final context = ref.watch(posWriteContextProvider);
  if (context == null) return const UnconfiguredSuppliersRepository();
  return PostgresSuppliersRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: _canBuy(ref),
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

final suppliersProvider = FutureProvider<List<Supplier>>(
  (ref) => ref.watch(suppliersRepositoryProvider).all(),
);

final purchaseOrdersRepositoryProvider = Provider<PurchaseOrdersRepository>((
  ref,
) {
  final context = ref.watch(posWriteContextProvider);
  if (context == null) return const UnconfiguredPurchaseOrdersRepository();
  return PostgresPurchaseOrdersRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: _canBuy(ref),
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>(
  (ref) => ref.watch(purchaseOrdersRepositoryProvider).all(),
);

final receivingRepositoryProvider = Provider<ReceivingRepository>((ref) {
  final context = ref.watch(posWriteContextProvider);
  if (context == null) return const UnconfiguredReceivingRepository();
  return PostgresReceivingRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: _canBuy(ref),
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

final supplierInvoicesRepositoryProvider =
    Provider<SupplierInvoicesRepository>((ref) {
  final context = ref.watch(posWriteContextProvider);
  if (context == null) return const UnconfiguredSupplierInvoicesRepository();
  return PostgresSupplierInvoicesRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: _canBuy(ref),
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

/// Everything with money still on it, oldest due first.
///
/// **The unpaid list rather than every invoice**, because a restaurant that has
/// been open three years has thousands of settled ones and the screen is a
/// worklist: what has to be paid, and what is late.
final unpaidInvoicesProvider = FutureProvider<List<SupplierInvoice>>(
  (ref) => ref.watch(supplierInvoicesRepositoryProvider).unpaid(),
);

/// What has been paid recently, so a bounced cheque can be reversed.
final supplierPaymentsProvider = FutureProvider<List<SupplierPayment>>(
  (ref) => ref.watch(supplierInvoicesRepositoryProvider).payments(limit: 100),
);

/// What every supplier is owed, for the supplier list.
final supplierBalancesProvider = FutureProvider<List<SupplierBalance>>(
  (ref) => ref.watch(supplierInvoicesRepositoryProvider).balances(),
);

/// What the restaurant adds on top of the food (§38).
///
/// Reads on the till's credential because a ticket cannot be priced without
/// them; writes on Management's.
final serviceChargesRepositoryProvider = Provider<ServiceChargesRepository>((
  ref,
) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredServiceChargesRepository();
  }
  return PostgresServiceChargesRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    readDatabase: ref.watch(posDatabaseProvider),
    readConfig: config,
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

/// What the restaurant buys and counts. Read on the till's credential,
/// written on the administrator's — see [PostgresStockItemsRepository].
final stockItemsRepositoryProvider = Provider<StockItemsRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredStockItemsRepository();
  }
  return PostgresStockItemsRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    readDatabase: ref.watch(posDatabaseProvider),
    readConfig: config,
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

/// Items in use — what a purchase line can name.
final stockItemsProvider = FutureProvider<List<StockItem>>(
  (ref) => ref.watch(stockItemsRepositoryProvider).all(),
);

/// Every item, retired ones too — the Stock items pane's list.
final stockItemsAllProvider = FutureProvider<List<StockItem>>(
  (ref) => ref.watch(stockItemsRepositoryProvider).all(includeInactive: true),
);

/// The units stock is counted and bought in. Read on the till's credential,
/// written on the administrator's — see [PostgresUnitsRepository].
final unitsRepositoryProvider = Provider<UnitsRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredUnitsRepository();
  }
  return PostgresUnitsRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    readDatabase: ref.watch(posDatabaseProvider),
    readConfig: config,
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

/// Units in use — what a purchase line can be written in.
final unitsProvider = FutureProvider<List<PosUnit>>(
  (ref) => ref.watch(unitsRepositoryProvider).all(),
);

/// Every unit, retired ones too — the Units pane's list.
final unitsAllProvider = FutureProvider<List<PosUnit>>(
  (ref) => ref.watch(unitsRepositoryProvider).all(includeInactive: true),
);

final serviceChargesProvider = FutureProvider<List<ServiceCharge>>(
  (ref) => ref.watch(serviceChargesRepositoryProvider).all(),
);

/// The same list including retired charges, for the editor.
final serviceChargesAllProvider = FutureProvider<List<ServiceCharge>>(
  (ref) =>
      ref.watch(serviceChargesRepositoryProvider).all(includeInactive: true),
);

/// The payment methods this restaurant takes (§40).
///
/// Read on the till's own credential — a cashier needs the list to take money,
/// and a back-office password at the counter is not a thing that can exist.
final tenderTypesRepositoryProvider = Provider<TenderTypesRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredTenderTypesRepository();
  }
  return PostgresTenderTypesRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
  );
});

/// What the payment screen offers.
///
/// Falls back to the seeded four while it loads rather than to an empty list: a
/// payment screen with no methods on it is a till that cannot take money, and
/// the four are what the migration writes anyway.
final tenderTypesProvider = FutureProvider<List<TenderMethod>>(
  (ref) => ref.watch(tenderTypesRepositoryProvider).all(),
);

/// The same list including retired methods, for the editor.
///
/// A separate provider rather than a family: the till and the back office ask
/// different questions, and a family keyed on a bool would let a screen ask
/// the wrong one by passing the wrong literal.
final tenderTypesAllProvider = FutureProvider<List<TenderMethod>>(
  (ref) => ref.watch(tenderTypesRepositoryProvider).all(includeInactive: true),
);

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

/// Files the receipt a recorded sale or refund owes, from its rows.
///
/// Null where there is no queue. See [EtaFiler] for why it reads the database
/// rather than the ticket, and why each till files only its own.
final etaFilerProvider = Provider<EtaFiler?>((ref) {
  final queue = ref.watch(etaQueueRepositoryProvider);
  final context = ref.watch(posWriteContextProvider);
  if (queue == null || context == null) return null;

  return EtaFiler(
    database: ref.watch(posDatabaseProvider),
    config: ref.watch(deploymentProvider),
    branchId: context.branchId,
    // ETA's chain is per POS serial. The terminal id is what this product has
    // that is stable per till and unique per restaurant; the serial registered
    // with the authority is set alongside the seal, and until that exists this
    // keeps two tills in one branch on two chains, which is the property that
    // matters.
    terminalId: context.terminalId,
    queue: queue,
    // Read on every call: a profile completed in Management five minutes ago
    // is the one the next receipt is filed under.
    profile: () => ref.read(receiptProfileProvider.future),
  );
});

/// The catch-up: every sale and refund this till recorded and has not filed.
///
/// On a timer rather than only at settlement, because the cases it exists for
/// have no settlement to hang on — the profile completed on Thursday for
/// Tuesday's sales, the crash between the sale's write and its receipt's.
/// Ten seconds after start, then every five minutes.
final etaReconcilerProvider = Provider<EtaReconciler?>((ref) {
  final filer = ref.watch(etaFilerProvider);
  if (filer == null) return null;

  var alive = true;
  ref.onDispose(() => alive = false);

  final reconciler = EtaReconciler(
    filer,
    // Through the CONTAINER, after the current build — the same cycle the
    // cloud sync hit: these providers read ones that read this one.
    onReport: (report) => Future.microtask(() {
      if (alive) applyEtaReport(ref.container, report);
    }),
  );

  final first = Timer(const Duration(seconds: 10), reconciler.run);
  final periodic = Timer.periodic(
    const Duration(minutes: 5),
    (_) => reconciler.run(),
  );
  ref.onDispose(() {
    first.cancel();
    periodic.cancel();
  });
  return reconciler;
});

/// The filing problem a person can fix, or null when there is none.
///
/// Only what somebody can act on reaches here — a half-typed receipt profile,
/// a queue that refused a write. Held so the screens a manager actually opens
/// can say it: an alarm raised into nothing is how a restaurant files nothing
/// for a month and hears it from the authority.
class EtaFilingProblem extends Notifier<EtaFilingSkipped?> {
  @override
  EtaFilingSkipped? build() => null;

  void report(EtaFilingSkipped problem) => state = problem;

  void clear() => state = null;
}

final etaFilingProblemProvider =
    NotifierProvider<EtaFilingProblem, EtaFilingSkipped?>(EtaFilingProblem.new);

/// Raise [problem] where the screens read it.
void reportEtaProblem(ProviderContainer container, EtaFilingSkipped problem) =>
    Future.microtask(
      () => container.read(etaFilingProblemProvider.notifier).report(problem),
    );

/// What a reconcile pass means for the screens: its problem, or the all-clear,
/// and a fresh queue when it filed anything.
void applyEtaReport(ProviderContainer container, EtaReconcileReport report) {
  final problem = report.problem;
  final notifier = container.read(etaFilingProblemProvider.notifier);
  if (problem == null) {
    notifier.clear();
  } else {
    notifier.report(problem);
  }
  if (report.salesFiled + report.refundsFiled > 0) {
    container
      ..invalidate(etaQueueSummaryProvider)
      ..invalidate(etaOutstandingProvider);
  }
}

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
    // Who works here is the platform's on a cloud till — see the field's own
    // note. Not a reason to hide the pane: roles and permissions are local
    // there and stay editable.
    offline: config.mode == DeploymentMode.offline,
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

// ── Backup ──────────────────────────────────────────────────────────────────
//
// A restaurant on one Windows box with no backup is one failed disk away from
// losing its whole trading history. Everything here exists to make that not be
// true, and to be loud about the ways in which it still is — see
// `BackupService` for what a copy on the same disk does and does not protect
// against.

/// Where the copies of this database are recorded.
///
/// On the **till's** connection, like the audit ledger and for the same reason:
/// the automatic copy is taken when the trading day is closed, at a machine on
/// which nobody has opened the back office. `pos_backups` is granted SELECT and
/// INSERT to both roles and nothing else.
final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredBackupRepository();
  }
  return PostgresBackupRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
});

final backupsProvider = FutureProvider<List<BackupRecord>>(
  (ref) => ref.watch(backupRepositoryProvider).recent(),
);

final backupPolicyProvider = Provider<BackupPolicy>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings == null ? BackupPolicy.defaults : BackupPolicy.from(settings);
});

/// Where `pg_dump` and `pg_restore` are on this machine, or null.
///
/// Looked up once and cached for the process: the answer only changes when
/// somebody installs PostgreSQL, which they do while the app is closed. The
/// pane invalidates it when it is opened, so "install it and come back" works.
final pgToolsProvider = FutureProvider<PgToolset?>((ref) => PgTools.locate());

/// Taking a copy, proving it, and putting one back.
///
/// Null when this terminal has no database — there is then nothing to back up,
/// and a service that pretended otherwise would write a record of a copy of
/// nothing.
/// Whether this terminal has a database whose copies are worth talking about.
/// False on a till with no database configured, where there is nothing to back
/// up and a warning about it would be noise.
final backupsApplyProvider = Provider<bool>(
  (ref) => ref.watch(backupRepositoryProvider) is! UnconfiguredBackupRepository,
);

/// Whether a backup file is still on this machine.
///
/// A seam, because the list asks it of every row and a widget test has no
/// files: only the newest copies are kept, so an old row's file being gone is
/// the ordinary case rather than an error.
final backupFileExistsProvider = Provider<bool Function(String path)>(
  (ref) => (path) => File(path).existsSync(),
);

/// Where the backup account's password is kept on this machine.
///
/// Beside the till's own, in `secrets.json` — see
/// [FileSecretStore.backupPasswordKey] for why that is safe for this one and
/// would not be for the administrator's.
final backupPasswordStoreProvider = Provider<PosDbSecretStore>(
  (ref) => FileSecretStore(key: FileSecretStore.backupPasswordKey),
);

/// The backup account's password, or null when none has been entered.
///
/// A store that cannot be read is "none": the copy then runs without one, which
/// works wherever the installer used `trust` or wrote a `.pgpass` — and where it
/// does not, the attempt is recorded as refused with the reason, which is the
/// honest outcome.
final backupPasswordProvider = FutureProvider<String?>((ref) async {
  try {
    return await ref.watch(backupPasswordStoreProvider).read();
  } on Object {
    return null;
  }
});

final backupServiceProvider = FutureProvider<BackupService?>((ref) async {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  final tools = await ref.watch(pgToolsProvider.future);
  final readerPassword = await ref.watch(backupPasswordProvider.future);

  final admin = ref.watch(adminDeploymentProvider);
  final adminPassword = ref.watch(adminDbCredentialProvider);

  return BackupService(
    // The till's pool and the till's config: the guard queries are counts the
    // till credential can already read, and the record and the audit row go
    // where every other till-written row goes.
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    directory: BackupPaths.resolve(ref.watch(backupPolicyProvider)),
    backups: ref.watch(backupRepositoryProvider),
    audit: ref.watch(auditRepositoryProvider),
    toolset: tools,
    // `pg_dump` runs as the read-only backup account, which is the one
    // credential that can read every table and is safe to keep on the till —
    // so the copy at day close works with nobody signed into the back office.
    reader: BackupConnection.forDeployment(
      config,
      user: BackupService.readerRole,
      password: readerPassword,
    ),
    // A restore runs as the database's owner, whose password is in memory
    // only while somebody has the back office open — and a restore is only
    // ever started from there.
    restorer: adminPassword == null
        ? null
        : BackupConnection.forDeployment(
            admin,
            user: admin.databaseUser,
            password: adminPassword,
          ),
    // Both pools, because `pg_restore --clean` drops every object in the
    // database and neither connection should be holding one when it does.
    quiesce: () async {
      await ref.read(posDatabaseProvider).close();
      await ref.read(adminPosDatabaseProvider).close();
    },
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
