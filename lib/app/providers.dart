import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/config/deployment.dart';
import '../core/config/lan_tls.dart';
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
import '../core/security/attempt_limiter.dart';
import '../core/network/connectivity_probe.dart';
import '../data/backup/backup_service.dart';
import '../data/backup/pg_archive.dart';
import '../data/backup/pg_tools.dart';
import '../data/config/file_secret_store.dart';
import '../data/config/installer_credentials.dart';
import '../data/config/pos_db_secret_store.dart';
import '../data/config/secret_store.dart';
import '../data/config/setup_progress_store.dart';
import '../data/config/terminal_config_store.dart';
import '../data/hardware/network_printer_ports.dart';
import '../data/hardware/spooler_printer_ports.dart';
import '../data/postgres/pos_database.dart';
import '../data/postgres/pos_tls.dart';
import '../data/postgres/local_bootstrap.dart';
import '../data/postgres/postgres_admin_repositories.dart';
import '../data/postgres/postgres_backup_repository.dart';
import '../data/postgres/postgres_business_logo_repository.dart';
import '../data/postgres/postgres_catalog_admin_repository.dart';
import '../data/postgres/postgres_catalog_repository.dart';
import '../data/postgres/postgres_customers_repository.dart';
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
import '../domain/models/stock_level.dart';
import '../data/postgres/postgres_stock_items_repository.dart';
import '../data/postgres/postgres_stock_levels_repository.dart';
import '../data/postgres/postgres_units_repository.dart';
import '../data/postgres/postgres_suppliers_repository.dart';
import '../data/postgres/postgres_supplier_invoices_repository.dart';
import '../data/postgres/postgres_purchase_orders_repository.dart';
import '../data/postgres/postgres_receiving_repository.dart';
import '../data/postgres/postgres_settings_repository.dart';
import '../data/postgres/postgres_financial_accounts_admin_repository.dart';
import '../data/postgres/postgres_financial_accounts_repository.dart';
import '../data/postgres/postgres_tender_types_repository.dart';
import '../data/postgres/postgres_refunds_repository.dart';
import '../data/postgres/money_config_codec.dart';
import '../data/postgres/postgres_parked_tickets.dart';
import '../data/postgres/postgres_print_queue_repository.dart';
import '../data/postgres/postgres_shift_repository.dart';
import '../data/postgres/postgres_sync_queue_repository.dart';
import '../data/postgres/postgres_site_licence.dart';
import '../data/unconfigured/unconfigured_repositories.dart';
import '../features/admin/application/admin_session.dart'
    show adminSessionProvider;
import '../features/history/history_scope.dart';
import '../features/licensing/data/file_license_store.dart';
import '../features/licensing/data/licence_check_gate.dart';
import '../features/licensing/data/licence_check_store.dart';
import '../features/licensing/data/licence_service.dart';
import '../features/licensing/data/license_keys.dart';
import '../features/licensing/data/license_store.dart';
import '../features/licensing/data/online_licence_service.dart';
import '../features/licensing/data/platform_licence_api.dart';
import '../features/licensing/data/site_licence.dart';
import '../features/licensing/domain/license_verifier.dart';
import '../features/licensing/domain/license.dart';
import '../features/licensing/domain/online_verdict.dart';
import '../features/setup/application/setup_controller.dart';
import '../domain/models/backup.dart';
import '../domain/models/held_sync.dart';
import '../domain/models/catalog.dart';
import '../domain/models/customer.dart';
import '../domain/models/dining_table.dart';
import '../domain/models/ticket.dart';
import '../domain/models/discount.dart';
import '../domain/models/order_record.dart';
import '../domain/models/business_day.dart';
import '../domain/models/pos_settings.dart';
import '../domain/models/refund.dart';
import '../domain/models/refund_history.dart';
import '../domain/models/reason_code.dart';
import '../domain/models/eta_submission.dart';
import '../domain/models/order_type_config.dart';
import '../domain/models/business_logo.dart';
import '../domain/models/content_languages.dart';
import '../domain/models/permissions.dart';
import '../domain/models/purchase_order.dart';
import '../domain/models/tax.dart';
import '../domain/models/supplier.dart';
import '../domain/models/supplier_invoice.dart';
import '../domain/models/receipt_profile.dart';
import '../domain/models/service_charge.dart';
import '../domain/models/financial_account.dart';
import '../domain/models/tender_method.dart';
import '../domain/repositories/admin_repositories.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/authorization.dart';
import '../domain/services/business_day_service.dart';
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
    // No shift here. A sale names the shift open when it is rung up, and the
    // repository asks the database for that inside the sale's own transaction
    // (`openShiftIdFor`) — a value captured when this provider built would go
    // on naming a shift that had since closed.
    onQueued: () => ref.read(cloudSyncProvider)?.nudge(),
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
/// **Narrowed to what the person acting may read** before it reaches the
/// repository — their own sales, without `order.view_all`. Here rather than
/// in the screen because this is the one road to the data: a second screen
/// built on this provider inherits the rule instead of having to remember it.
/// `/orders` and the back office's Sales tab are two such screens, and they
/// show the same rows for the same person because they read them here.
/// See [HistoryScope] and [actingStaffProvider].
///
/// **Dropped when nobody is looking** (`autoDispose`, since BO-2). Every
/// filter combination is its own entry, and each used to stay cached for the
/// life of the app. And these now hang off the Admin Mode session through
/// [actingStaffProvider]; that session ends just after the back office's
/// widgets have gone, and a list still held then would be re-read for nobody
/// — on a bare event-loop timer, because the widget tree that paced it is
/// gone too.
final orderHistoryProvider = FutureProvider.autoDispose
    .family<List<OrderRecord>, OrderHistoryQuery>((ref, query) {
      final scoped = HistoryScope.scope(
        query,
        ref.watch(actingStaffProvider),
      );
      if (scoped == null) return const <OrderRecord>[];
      return ref.watch(orderHistoryRepositoryProvider).search(scoped);
    });

/// The strip over the list (BO-3): the figures for every page of
/// [orderHistoryProvider]'s filter.
///
/// **The same scope, applied the same way.** A cashier's totals are their own
/// sales' totals for the reason their list is their own list: this is a
/// road to the same rows, and a figure that summed the branch over a list of
/// one person's sales would say more than the list may.
///
/// Keyed by [OrderHistoryQuery.unpaged], so turning a page does not re-read
/// the totals. Read apart from the page rather than in one snapshot with it:
/// a sale committed between the two reads shows in the strip before the list
/// is next read, and the price of one snapshot would be summing every sale in
/// the window on every page turn.
final orderHistorySummaryProvider = FutureProvider.autoDispose
    .family<OrderHistorySummary, OrderHistoryQuery>((ref, query) {
      final scoped = HistoryScope.scope(
        query.unpaged,
        ref.watch(actingStaffProvider),
      );
      if (scoped == null) return OrderHistorySummary.empty;
      return ref.watch(orderHistoryRepositoryProvider).summarise(scoped);
    });

/// One order, opened from the list — or null when it is not the viewer's to
/// open, which the pane already shows as "no longer there".
///
/// `autoDispose` for the same reason as [orderHistoryProvider].
final orderDetailProvider = FutureProvider.autoDispose
    .family<OrderRecordDetail?, int>((ref, orderId) async {
  final viewer = ref.watch(actingStaffProvider);
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

/// One page of Returns (المرتجعات), narrowed to what the person acting may
/// read — the refunds against their own sales, without `order.view_all`.
///
/// The one road to the rows, as [orderHistoryProvider] is for sales, and
/// scoped here for the same reason: a screen built on it later inherits the
/// rule. `autoDispose` for the reason that one gives.
final refundHistoryProvider = FutureProvider.autoDispose
    .family<List<RefundRecord>, RefundHistoryQuery>((ref, query) {
      final scoped = HistoryScope.scopeRefunds(
        query,
        ref.watch(actingStaffProvider),
      );
      if (scoped == null) return const <RefundRecord>[];
      return ref.watch(orderHistoryRepositoryProvider).refunds(scoped);
    });

/// The strip over Returns, over every page of [refundHistoryProvider]'s
/// filter, under the same scope. Keyed by [RefundHistoryQuery.unpaged] so a
/// page turn is not a fresh total.
final refundHistorySummaryProvider = FutureProvider.autoDispose
    .family<RefundHistorySummary, RefundHistoryQuery>((ref, query) {
      final scoped = HistoryScope.scopeRefunds(
        query.unpaged,
        ref.watch(actingStaffProvider),
      );
      if (scoped == null) return RefundHistorySummary.empty;
      return ref.watch(orderHistoryRepositoryProvider).summariseRefunds(scoped);
    });

/// Money going back.
///
/// Takes the shift by `read`, not `watch`, for the same reason the orders
/// repository does: a refund stamps the shift that was open when it was given,
/// and rebuilding this mid-transaction because a shift closed at another till
/// would be worse than an unattributed refund. Read when the refund is
/// written, through a function, not once here — a captured id outlived the
/// shift it named.
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
    onQueued: () => ref.read(cloudSyncProvider)?.nudge(),
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

/// Make sure the branch is trading in a day, for [PosStaff] who is signing in
/// or opening a shift. **Never throws and never blocks selling** — see
/// `ensureBusinessDay`. A provider holding a function so a test can hand the
/// screens a double, and so the two doors (the shift dialog and the lock
/// screen) cannot drift apart.
final ensureBusinessDayProvider =
    Provider<Future<BusinessDayResult> Function(PosStaff by)>((ref) {
      return (by) async {
        // Guarded here as well as inside `ensureBusinessDay`: the two doors
        // await this inside their own `try`, whose `catch` would stop the shift
        // opening and print the raw exception. "The till never stops selling
        // because of the day" is held by this guard, not by everything below it
        // happening never to throw.
        try {
          final result = await ensureBusinessDay(
            days: ref.read(businessDayRepositoryProvider),
            policy: ref.read(dayPolicyProvider),
            now: DateTime.now(),
            by: by,
          );
          if (result.outcome == BusinessDayOutcome.failed) {
            // Logged, not shown: the shift opens regardless and the next
            // sign-in tries again.
            debugPrint('business day: could not open one: ${result.error}');
          }
          // The close button, Home and the start-screen notice all read the
          // day; the notice watches it, so this refreshes all three.
          ref.invalidate(businessDayProvider);
          return result;
        } on Object catch (error) {
          debugPrint('business day: unexpected failure: $error');
          return BusinessDayResult(BusinessDayOutcome.failed, error: error);
        }
      };
    });

/// What the start screen should say about the day, if anything. Derived from
/// current state each time rather than stored, so it cannot outlive the
/// condition it describes. Not `autoDispose`, like [businessDayProvider]: it is
/// refreshed by invalidation, and a disposal timer outliving a screen is what
/// the start-screen tests would trip over.
final dayNoticeProvider = FutureProvider<DayNotice?>((ref) async {
  final open = await ref.watch(businessDayProvider.future);
  final shiftOpen = ref.watch(shiftProvider).valueOrNull != null;
  final lastClosed = open == null
      ? await ref.watch(businessDayRepositoryProvider).lastClosed()
      : null;
  return dayNotice(
    open: open,
    lastClosed: lastClosed,
    policy: ref.watch(dayPolicyProvider),
    now: DateTime.now(),
    shiftOpen: shiftOpen,
  );
});

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
    onQueued: () => ref.read(cloudSyncProvider)?.nudge(),
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
  //
  // A child tablet registers against its main device's PostgreSQL whatever
  // mode that main device runs in: the platform has never heard of it, and it
  // holds no device token to claim with.
  if (config.mode == DeploymentMode.cloud && !config.isChild) {
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
  // A child of a cloud main device included: its sales reach the platform
  // through the main device's outbox drain, and it has no token of its own.
  if (!config.mode.syncsSalesToPlatform ||
      config.isChild ||
      base == null ||
      base.isEmpty) {
    return null;
  }
  final vault = ref.watch(deviceTokenVaultProvider);
  return PosCloudApi(baseUrl: base, deviceToken: () => vault.token);
});

/// The terminal's device credential. The default is in-memory; `main()`
/// overrides it with a vault backed by [secretStoreProvider]'s store (DPAPI on
/// Windows, the Keychain on macOS), restored before the first frame — the same
/// arrangement as the database password.
final deviceTokenVaultProvider = Provider<DeviceTokenVault>(
  (ref) => DeviceTokenVault(),
);

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
});

/// Printer and drawer — on the network, or plugged into the till.
///
/// Real: it sweeps this machine's own /24 for anything listening on the RAW
/// port every ESC/POS thermal printer uses, asks the OS spooler what is
/// installed, and *Test print* sends actual commands — including the drawer
/// kick, because proving the drawer opens is half of what an installer is
/// checking.
///
/// It replaced a binding that invented two plausible-looking printers, which an
/// operator could select and then discover at service time was never attached.
///
/// USB printers arrive through the spooler as RAW jobs (owner decision,
/// 22 Sep 2026: "it can be usb or network"). Most Egyptian restaurants own a
/// USB printer, and until this a till with one always landed on the hardware
/// screen with nothing found. Which port a job goes down is decided by the
/// shape of the printer's name — see [PrinterConfig.transportOf].
final hardwarePortsProvider = Provider<HardwarePorts>(
  (ref) => CompositeHardwarePorts(
    network: const NetworkPrinterPorts(),
    spooler: SpoolerPrinterPorts(SpoolerBackend.forThisPlatform()),
  ),
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
  Future<bool> park(Ticket ticket) async {
    if (ticket.lines.isEmpty) return true;
    try {
      await _store?.save(ticket);
    } on Object {
      // Do not change the visible floor until the durable copy exists.  The
      // caller keeps the live ticket and can tell the cashier exactly that.
      return false;
    }
    if (_disposed) return false;
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

    return true;
  }

  Ticket? at(int tableId) => state.onTables[tableId];

  /// This ticket's money has been dealt with — paid, or voided. Let it go.
  ///
  /// Takes the whole ticket rather than a table id: a held ticket has no table
  /// to be identified by, and a ticket that was seated when it was parked and
  /// is not now (somebody switched a dine-in order to takeaway, which clears
  /// the table) has to release the row it actually left behind.
  Future<void> settle(Ticket ticket) async {
    try {
      await _store?.remove(tableId: ticket.tableId, transactionId: ticket.id);
    } on Object {
      // The order/void has already committed.  `load` excludes a parked row
      // with a committed order, so a failed cleanup cannot resurrect a bill.
      // Keeping the UI blocked here would instead invite the cashier to take
      // the money a second time.
    }
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
  }

  /// Forget where [ticket] was parked — the table it is leaving, when it is
  /// moved to another. The same forgetting a settlement does; a second name
  /// because the ticket is very much still open.
  Future<void> release(Ticket ticket) => settle(ticket);
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
///
/// **What the next pass will try** — not what the drain has held for a person,
/// which is [heldSyncCountProvider]. The two were one number until a single
/// refused sale left the pill reading "1 unsent" for ever.
final FutureProvider<int> pendingSyncCountProvider = FutureProvider<int>(
  (ref) => ref.watch(ordersRepositoryProvider).pendingSyncCount(),
);

/// The records the drain has held for a person (D1/D2/D13).
///
/// Unconfigured — empty — on an offline till as well as on one with no
/// database: an offline till owes the platform nothing, so nothing it holds
/// would ever be drained, and a Retry button there would do nothing at all.
/// On the till's credential, which already holds UPDATE on both outboxes; see
/// [PostgresSyncQueueRepository].
final Provider<SyncQueueRepository> syncQueueRepositoryProvider =
    Provider<SyncQueueRepository>((ref) {
      final config = ref.watch(deploymentProvider);
      final context = ref.watch(posWriteContextProvider);
      if (context == null ||
          PosDatabase.hostFor(config) == null ||
          !config.mode.syncsSalesToPlatform) {
        return const UnconfiguredSyncQueueRepository();
      }
      return PostgresSyncQueueRepository(
        database: ref.watch(posDatabaseProvider),
        config: config,
        restaurantId: context.restaurantId,
        branchId: context.branchId,
        terminalId: context.terminalId,
      );
    });

/// How many records are held. Invalidated with [pendingSyncCountProvider].
final FutureProvider<int> heldSyncCountProvider = FutureProvider<int>(
  (ref) => ref.watch(syncQueueRepositoryProvider).heldSyncCount(),
);

/// The held records themselves, for the Sync pane.
final FutureProvider<List<HeldSyncItem>> heldSyncItemsProvider =
    FutureProvider<List<HeldSyncItem>>(
      (ref) => ref.watch(syncQueueRepositoryProvider).listHeldSync(),
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
  container
    ..invalidate(pendingSyncCountProvider)
    // A pass that held something moves it from one count to the other.
    ..invalidate(heldSyncCountProvider)
    ..invalidate(heldSyncItemsProvider);

  // Written on every pass, not only on rejection, so a till that gets
  // re-paired clears the banner by itself instead of carrying it until
  // someone restarts the app.
  final rejected = container.read(terminalRejectedProvider.notifier);
  if (rejected.state != outcome.deviceTokenRejected) {
    rejected.state = outcome.deviceTokenRejected;
  }

  // A new or removed logo, whether it arrived with a bundle or alone.
  if (outcome.reseeded || outcome.logoChanged) {
    container.invalidate(businessLogoProvider);
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

/// Which languages the menu is written in (XORD-005).
///
/// Read from the restaurant row, where an offline install authors it and a cloud
/// till's bundle writes it. `both` while the query is in flight and on a till
/// with no database: asking for more fields than necessary is the safe way to
/// be wrong, and it is exactly how every till behaved before this existed.
final contentLanguagesProvider = FutureProvider<ContentLanguages>((ref) async {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) {
    return ContentLanguages.both;
  }
  final rows = await ref
      .watch(posDatabaseProvider)
      .query(
        config,
        'SELECT content_languages FROM pos_restaurants WHERE id = @r',
        parameters: {'r': context.restaurantId},
      );
  return rows.isEmpty
      ? ContentLanguages.both
      : ContentLanguages.fromWire(rows.first[0] as String?);
});

/// The business logo this till shows (XORD-021), or null for "none yet".
///
/// Read from the restaurant row on the till's own credential, so it is the copy
/// stored on the branch server: no network is involved and a restart changes
/// nothing. **Never throws.** A missing database, an unreadable row or a bad
/// column is "no logo", because the start screen that draws this must open
/// whatever the logo does: a failure here is the bundled mark, not an error.
final businessLogoProvider = FutureProvider<BusinessLogo?>((ref) async {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) return null;
  try {
    final rows = await ref
        .watch(posDatabaseProvider)
        .query(
          config,
          'SELECT logo_bytes, logo_mime, logo_source, logo_updated_at '
          'FROM pos_restaurants WHERE id = @r AND logo_bytes IS NOT NULL',
          parameters: {'r': context.restaurantId},
        );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final bytes = row[0];
    final source = LogoSource.fromWire(row[2] as String?);
    if (bytes is! Uint8List || bytes.isEmpty || source == null) return null;
    return BusinessLogo(
      bytes: bytes,
      mime: row[1] as String? ?? '',
      source: source,
      updatedAt: row[3] as DateTime?,
    );
  } on Object {
    return null;
  }
});

/// The logo a receipt carries (XORD-024): the restaurant's, as bytes, or null.
///
/// Null when this till is set not to print it (Settings › Printer) and null
/// when there is none. **Never throws**, like [businessLogoProvider] beneath
/// it: a logo that cannot be read is a receipt without one, never a receipt
/// that does not print. Offline and cloud tills read the same row.
final receiptLogoProvider = FutureProvider<Uint8List?>((ref) async {
  if (!ref.watch(printerConfigProvider).printLogo) return null;
  try {
    return (await ref.watch(businessLogoProvider.future))?.bytes;
  } on Object {
    return null;
  }
});

/// Where the owner changes the logo: offline installs only, on the
/// administrator connection like every other authoring repository. Null on a
/// cloud till, whose logo is the platform's.
final businessLogoRepositoryProvider = Provider<BusinessLogoRepository?>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (config.mode != DeploymentMode.offline) return null;
  if (context == null || PosDatabase.hostFor(config) == null) return null;

  return PostgresBusinessLogoRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    adminAvailable: ref.watch(adminDbCredentialProvider) != null,
    offline: true,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    terminalId: context.terminalId,
  );
});

/// The same answer, synchronously, for a form that cannot wait on a future.
final contentLanguagesNowProvider = Provider<ContentLanguages>(
  (ref) =>
      ref.watch(contentLanguagesProvider).valueOrNull ?? ContentLanguages.both,
);

/// The order types THIS branch actually offers the cashier (POS-BE-005, §31).
///
/// Two filters, and both have to pass. The branch's own list from the platform:
/// the till must never show a type the branch does not support, or the cashier
/// rings a whole ticket and only discovers at settlement that the server
/// refuses it. That rule is mirrored from `PosOrderService` exactly — an empty
/// list on the branch means "everything allowed" there, so it means the same
/// here, and an unknown wire value is dropped rather than thrown on (rule 11).
///
/// And the restaurant's own switch in the back office. Turning delivery off
/// there used to change nothing on the till, because this read only the
/// branch; `orderTypeConfigProvider` already hides the inactive rows, and it
/// also supplies the order the restaurant sorted them into.
final branchOrderTypesProvider = Provider<List<OrderType>>((ref) {
  final active = ref.watch(orderTypeRulesProvider).active;
  final branchId = ref.watch(terminalProfileProvider).branchId;
  final branches = ref.watch(branchesProvider).valueOrNull;

  var supported = OrderType.values;
  if (branchId != null && branches != null) {
    final branch = branches.where((b) => b.id == branchId).firstOrNull;
    final wire = branch?.supportedOrderTypes ?? const <String>[];
    final parsed = [for (final value in wire) ?OrderType.fromWire(value)];
    // A branch whose every value this build fails to parse still has to sell.
    if (parsed.isNotEmpty) supported = parsed;
  }

  final offered = [
    for (final type in active)
      if (supported.contains(type)) type,
  ];
  // Nothing in common — the back office turned on only what the platform
  // refuses here — and a till with no order type cannot sell at all. The
  // platform's list wins, because it is the one settlement enforces.
  return offered.isEmpty ? supported : offered;
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

    // The back office can turn a kind of order off while this till is open,
    // and the restaurant's rules arrive a beat after the first ticket does. An
    // empty ticket left on a type nobody offers any more moves to the first one
    // that is. A ticket with lines or a table keeps its type: switching it
    // would detach a seated party's bill, and the cashier can see the bar.
    ref.listen<List<OrderType>>(branchOrderTypesProvider, (_, offered) {
      if (offered.contains(state.orderType)) return;
      if (!state.isEmpty || state.tableId != null) return;
      setOrderType(offered.first);
    });

    final offered = ref.read(branchOrderTypesProvider);
    return Ticket(
      id: _uuid.v4(),
      // Dine in when the till sells it, as it always has; otherwise whatever
      // the restaurant sorted first. Never empty — see the provider.
      orderType: offered.contains(OrderType.dineIn)
          ? OrderType.dineIn
          : offered.first,
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

  /// Move this ticket to [table]: "Change table" on the cart.
  ///
  /// False when another ticket already sits there — the floor shows that
  /// table as taken, and a move onto it would stack two bills on one table.
  /// Otherwise the old table is released, so the floor stops showing the
  /// order there, and the ticket is seated at the new one with its lines and
  /// rounds intact. Before this, "Change table" parked the ticket on its OLD
  /// table and started a fresh one for the new table, so the order never
  /// moved and the cashier found it still on the first table (16 Oct 2026).
  Future<bool> moveTo(DiningTable table) async {
    final parked = ref.read(openTicketsProvider.notifier);
    final other = parked.at(table.id);
    if (other != null && other.id != state.id) return false;
    await parked.release(state);
    attachTable(table);
    return true;
  }

  /// Who the food is for (POS-BE-014), or null to take them off again.
  ///
  /// Never refuses and never touches the totals — a customer is who, not what.
  /// A cashier who picked the wrong person simply opens the dialog again.
  ///
  /// **Needs `pos.operate`** (XORD-001): choosing who an order is for is part
  /// of ringing it up. Returns whether it was done; the cart is never touched
  /// either way.
  bool setCustomer(PosCustomer? customer) {
    if (ref.read(canProvider(PosCapability.operate)) is! Allowed) return false;
    state = customer == null
        ? TicketEngine.detachCustomer(state)
        : TicketEngine.attachCustomer(state, customer);
    return true;
  }

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

  /// Null when the payment came off; the refusal when it did not.
  TicketRefusal? removeTenderAt(
    int index, {
    required PosStaff? by,
    Approval? approval,
  }) {
    final result = TicketEngine.removeTenderAt(
      state,
      index,
      by: by,
      approval: approval,
    );
    if (result.ticket case final ticket?) state = ticket;
    return result.refusal;
  }

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
    onQueued: () => ref.read(cloudSyncProvider)?.nudge(),
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

  /// Here rather than on each door — the start screen's shift dialog and the
  /// lock screen both sign people in — so the till remembers whoever came
  /// through either one, and a third door added later cannot forget to.
  void signIn(PosStaff staff) {
    state = staff;
    ref.read(lastUsernameProvider.notifier).remember(staff.username);
  }

  /// Closing a shift signs the person out with it. The next shift is somebody
  /// else's responsibility until they say otherwise. So does five idle minutes
  /// (`TillIdleLock`): an unattended till is nobody's.
  void signOut() => state = null;
}

/// The clock the till's sign-in doors and its idle lock read. A provider so a
/// test can move it instead of waiting thirty seconds or five minutes — the
/// same reason as `adminClockProvider`, kept apart from it because Admin Mode's
/// clock belongs to Admin Mode's tests.
final tillClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Wrong PINs at the till's own doors: the lock screen, the open-shift
/// sign-in and the supervisor keypad. See [AttemptLimiter].
///
/// **One limiter for all three**, because they check the same PINs: separate
/// counts would give somebody five guesses at the lock screen, five more in the
/// shift dialog and five at the keypad for every lockout window. Keyed by the
/// username typed at the two doors that ask for one, and by
/// [AttemptLimiter.anyone] at the keypad, which asks for a PIN alone — and the
/// terminal-wide ceiling is shared across all of it. A PIN submitted at the
/// lock screen with the name left empty lands on the keypad's key too: it is
/// the same kind of try, a PIN with no claim of who.
///
/// Admin Mode keeps its own (see `AdminSessionController`). Held for the life
/// of the process and lost on restart; see [AttemptLimiter] for why that is
/// accepted for now.
final signInLimiterProvider = Provider<AttemptLimiter>(
  (ref) => AttemptLimiter(clock: () => ref.read(tillClockProvider)()),
);

/// Whether something on screen is in the middle of moving money, so the idle
/// lock must wait for it.
///
/// **A plain object, not provider state.** Nothing rebuilds when it changes —
/// only the idle lock asks, and only when its timer fires — so a payment
/// screen marking itself on every build costs nothing and cannot trip
/// Riverpod's rule against changing state while widgets build. Holders are a
/// set, so holding twice is holding once and a holder that is disposed
/// releases exactly what it held.
///
/// Rejected: closing the payment dialog from under the cashier, as locking
/// does to every other dialog. A settlement awaiting the database when its
/// dialog went would commit the order with nobody left to print the receipt,
/// free the table or start the next ticket — the sale screen would still be
/// showing a bill the drawer has already been paid for.
class IdleLockGuard {
  final _holders = <Object>{};

  bool get isHeld => _holders.isNotEmpty;

  void hold(Object holder) => _holders.add(holder);

  void release(Object holder) => _holders.remove(holder);
}

final idleLockGuardProvider = Provider<IdleLockGuard>((ref) => IdleLockGuard());

/// The username of whoever signed in at this till last, for the lock screen
/// to offer back.
///
/// **A prefill, not an identity.** The PIN still has to belong to the name,
/// and the name is one tap away from being somebody else's — what this saves
/// is the same cashier typing their own name on a keypad screen at every
/// lock, which the audit (S3-2) watched happen all shift.
///
/// A property of the terminal, kept in the terminal's config file beside the
/// language and the brightness, and with their bargain: written without
/// being awaited, because unlocking must not wait on a file, and silent on
/// failure, because the name is already in [state] for this process and the
/// worst a lost write costs is one typed name tomorrow morning.
class LastUsernameController extends Notifier<String?> {
  @override
  String? build() => ref.watch(terminalBootProvider).config?.lastUsername;

  void remember(String? username) {
    final name = username?.trim();
    if (name == null || name.isEmpty) return;
    state = name;
    unawaited(_persist(name));
  }

  /// See [TerminalLocaleController._persist] for why a terminal with no
  /// config yet is left alone, and why this catches `Object`.
  Future<void> _persist(String username) async {
    final store = ref.read(terminalConfigStoreProvider);
    try {
      final saved = await store.read();
      if (saved == null || saved.lastUsername == username) return;
      await store.write(saved.copyWith(lastUsername: username));
    } on Object {
      // The name on screen is already right; see above.
    }
  }
}

final lastUsernameProvider = NotifierProvider<LastUsernameController, String?>(
  LastUsernameController.new,
);

/// Who can take this till by name and PIN: the active staff with a username,
/// for the lock screen to show as tiles.
///
/// Read through the staff directory, which is bound on the till's own
/// credential for exactly this reason (see [staffDirectoryRepositoryProvider]):
/// a cashier switching user at the counter must not need the back office's
/// password to see who works here. Nobody without a username is listed —
/// they cannot sign in at a till at all, and a tile that leads to a refusal
/// is worse than no tile.
final signInCandidatesProvider = FutureProvider<List<PosStaff>>((ref) async {
  final staff = await ref
      .watch(staffDirectoryRepositoryProvider)
      .all(includeInactive: false);
  return [
    for (final person in staff)
      if (person.username?.trim().isNotEmpty ?? false) person,
  ];
});

/// Who is acting on this terminal right now: whoever came through Admin
/// Mode's door while its session lasts, and the person signed in at the till
/// the rest of the time.
///
/// **Two people can be signed in at once** — Admin Mode is separate from the
/// till on purpose (`AdminSession`). That did not matter while nothing the
/// till's operator does was reachable from inside the back office. With the
/// order history there as the Sales tab (BO-2) it does: the owner's refund
/// would be booked to the cashier still signed in at the till, and on a
/// locked till — nobody signed in — the owner would see no sales and no
/// Refund at all.
///
/// Never the two at once in practice: Admin Mode is a whole screen and its
/// session ends when that screen goes (`ManagementScreen.dispose`), so no till
/// flow runs while this answers with the administrator.
///
/// Rejected: overriding [signedInStaffProvider] in a nested `ProviderScope`
/// around the Sales tab. Every provider derived from it would need
/// `dependencies`, and the refund and reprint dialogs are built on the root
/// navigator's overlay, outside that scope — each would have to carry the
/// container by hand, and the one somebody forgot would quietly act as the
/// till's cashier.
///
/// `autoDispose`, so it goes with the history lists that hold it: kept alive
/// with nobody listening, the session ending after the back office's widgets
/// had gone would still re-run it, for nothing.
final actingStaffProvider = Provider.autoDispose<PosStaff?>(
  (ref) =>
      ref.watch(adminSessionProvider)?.staff ??
      ref.watch(signedInStaffProvider),
);

/// The shift this terminal currently has open, if any.
///
/// Re-read rather than held: a till restarted mid-service must come back to the
/// same open shift, because the drawer never closed.
final shiftProvider = FutureProvider<PosShift?>(
  (ref) => ref.watch(shiftRepositoryProvider).current(),
);

/// Open drawers across the branch, and each person's last shift — the Users
/// section's tile and column.
///
/// Auto-disposed, where [shiftProvider] is not: shifts open and close at the
/// counter while the back office is shut, so a figure cached from the last
/// visit would be a count of drawers that may since have been cashed up.
final shiftActivityProvider = FutureProvider.autoDispose<ShiftActivity>(
  (ref) => ref.watch(shiftRepositoryProvider).activity(),
);

/// Endpoint probe used by the setup wizard before it persists a cloud address.
final connectivityProbeProvider = Provider<ConnectivityProbe>(
  (ref) => HttpConnectivityProbe(),
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
///
/// **A child tablet reads its main device's licence instead** — see
/// [SiteLicenceService]. Same public key, same policy; the file simply lives in
/// the database they share rather than on the tablet.
final licenceServiceProvider = Provider<LicenceService>((ref) {
  final verifier = LicenseVerifier(
    publicKeyBytes: LicenseKeys.current,
    keyId: LicenseKeys.currentId,
  );
  if (ref.watch(deploymentProvider).isChild) {
    return SiteLicenceService(
      source: ref.watch(siteLicenceSourceProvider) ?? InMemorySiteLicenceSource(),
      verifySignature: verifier.verifySignature,
      clock: DateTime.now,
      restaurantId: ref.watch(terminalProfileProvider).restaurantId,
      keyId: LicenseKeys.currentId,
    );
  }
  final platform = ref.watch(platformLicenceApiProvider);
  final fingerprint = TerminalIdFingerprint(
    ref.watch(terminalProfileProvider).installationId,
  );
  final file = DefaultLicenceService(
    verifier: verifier,
    store_: ref.watch(licenseStoreProvider),
    fingerprint: fingerprint,
    clock: DateTime.now,
    remote: platform.fetchByKey,
  );
  // A till that talks to the platform may be told to take its verdict from
  // it (POS-BE-031). Everything but the verdict stays with the file service,
  // and a till never told `online` keeps the file — see OnlineLicenceService.
  final api = ref.watch(posCloudApiProvider);
  if (api == null) return file;
  final vault = ref.watch(deviceTokenVaultProvider);
  return OnlineLicenceService(
    inner: file,
    checks: ref.watch(licenceCheckStoreProvider),
    // Not paired yet: nothing to ask with, so no request at all.
    check: (body) async => (vault.token?.isNotEmpty ?? false)
        ? api.checkLicence(body)
        : const CloudReply.offline(),
    fingerprint: fingerprint,
    clock: DateTime.now,
    appVersion: posAppVersion,
    gate: ref.watch(licenceCheckGateProvider),
  );
});

/// The one [LicenceCheckGate] for the process.
///
/// **No dependencies, on purpose.** [licenceServiceProvider] is rebuilt as
/// the vault, the deployment config and the cloud API settle at launch, and
/// every rebuild used to be a new service sending its own check — three
/// identical `POST /api/pos/license/check` in the first second (S3-4). This
/// provider never rebuilds, so the gate remembers across them.
final licenceCheckGateProvider = Provider<LicenceCheckGate>(
  (ref) => LicenceCheckGate(),
);

/// The last online licence verdict and where this till takes its verdict from
/// (POS-BE-031). On disk, beside the licence file — see [LicenceCheckStore].
final licenceCheckStoreProvider = Provider<LicenceCheckStore>(
  (ref) => FileLicenceCheckStore(),
);

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

/// The role the Windows installer wrote down for this machine, read once in
/// `main()` before the first frame. Null wherever the installer never ran —
/// a Mac, a hand-built machine, every install from before the marker — and
/// null means "what it always was". See `InstalledRole`.
final installedRoleProvider = Provider<TerminalRole?>((ref) => null);

/// The role a FRESH install takes. A saved config keeps the role it was set
/// up with; this only decides which wizard a new machine opens on.
///
/// A tablet is a child, always — see [TerminalRole]. Decided by the operating
/// system rather than by screen size: a large Android tablet is still the
/// device carried round the floor, and a small Windows till is still the one
/// with the database on it.
///
/// A desktop is a main device unless the installer said otherwise: "Till
/// only" installs no PostgreSQL, so the machine has no database to be the
/// main device of, and it joins the one that does as a child (owner decision,
/// 22 Sep 2026). Before the marker existed such a machine opened the
/// main-device wizard and, on the cloud path, a database screen with nothing
/// to point at.
final deviceRoleProvider = Provider<TerminalRole>((ref) {
  if (Platform.isAndroid || Platform.isIOS) return TerminalRole.child;
  return ref.watch(installedRoleProvider) ?? TerminalRole.main;
});

/// The licence a main device shares with its children, in their database.
/// Null until there is a database to find it in.
final siteLicenceSourceProvider = Provider<SiteLicenceSource?>((ref) {
  final config = ref.watch(deploymentProvider);
  if (PosDatabase.hostFor(config) == null) return null;
  return _PostgresSiteLicenceSource(
    PostgresSiteLicence(
      database: ref.watch(posDatabaseProvider),
      config: config,
    ),
  );
});

/// [PostgresSiteLicence]'s plain rows, as the licensing types.
class _PostgresSiteLicenceSource implements SiteLicenceSource {
  const _PostgresSiteLicenceSource(this._table);

  final PostgresSiteLicence _table;

  @override
  Future<SiteLicence?> read({int? restaurantId}) async {
    final row = await _table.read(restaurantId: restaurantId);
    if (row == null) return null;
    return SiteLicence(
      file: LicenseFile(
        payloadB64: row.payload,
        signatureB64: row.signature,
        keyId: row.keyId,
      ),
      restaurantId: row.restaurantId,
      // The CHECK constraint admits only the two wire values, so the fallback
      // is for a newer build's mode this one does not know.
      mode: DeploymentMode.fromWire(row.mode) ?? DeploymentMode.offline,
      terminalCount: row.terminalCount,
    );
  }

  @override
  Future<void> publish({
    required int restaurantId,
    required LicenseFile file,
    required DeploymentMode mode,
  }) => _table.publish(
    SiteLicenceRow(
      restaurantId: restaurantId,
      payload: file.payloadB64,
      signature: file.signatureB64,
      keyId: file.keyId,
      mode: mode.wire,
    ),
  );
}

final siteLicencePublisherProvider = Provider<SiteLicencePublisher>(
  SiteLicencePublisher.new,
);

/// Shares this main device's licence with its children.
///
/// Run when the start screen opens and after a renewal — the two moments a
/// main device's licence can have changed — rather than once at setup, so a
/// main device installed before children existed shares its licence the next
/// time anybody reaches its start screen, and a renewal reaches every tablet
/// without anyone touching them.
class SiteLicencePublisher {
  SiteLicencePublisher(this._ref);

  final Ref _ref;

  /// Never throws. Sharing is for the children's benefit, and a main device
  /// that could not write the row must still open its own shift.
  Future<void> publish() async {
    final config = _ref.read(deploymentProvider);
    if (config.isChild) return;
    final restaurantId = _ref.read(terminalProfileProvider).restaurantId;
    final source = _ref.read(siteLicenceSourceProvider);
    if (restaurantId == null || source == null) return;

    try {
      final file = await _ref.read(licenceServiceProvider).installed();
      if (file == null) return;
      // A one-terminal licence has nobody to share with.
      if ((LicenseVerifier.claimsOf(file)?.maxTerminals ?? 1) <= 1) return;
      await source.publish(
        restaurantId: restaurantId,
        file: file,
        mode: config.mode,
      );
    } on Object catch (error) {
      debugPrint('site licence not shared: $error');
    }
  }
}

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

/// Where an unfinished cloud setup is kept, so a restart after the claim
/// carries on rather than asking for a pairing code that is already spent.
/// See [SetupProgress].
final setupProgressStoreProvider = Provider<SetupProgressStore>(
  (ref) => FileSetupProgressStore(),
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
    // And a claim the wizard never finished with. A reset is "start over", and
    // a progress file left behind would reopen the wizard halfway through the
    // last attempt, on the last restaurant's terminal.
    await _ref.read(setupProgressStoreProvider).clear();
    await _ref.read(posDbCredentialsStoreProvider).forget();
    // And the back office's. A till moved onto another restaurant's database
    // must not arrive holding the last one's administrator password.
    await _ref.read(adminDbSecretStoreProvider).clear();
    _ref.read(adminDbCredentialProvider.notifier).forget();

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

  /// **Back to a blank till.** Everything [run] does, and also what it keeps on
  /// purpose: the licence file and its cached verdict, every saved password and
  /// token (everything in [secretStoreProvider]'s store, not only the two
  /// entries [run] touches, and any legacy `secrets.json`), and this machine's
  /// identity, so the wizard opens on "enter a licence key" as on a machine
  /// that has never run it.
  ///
  /// **It erases this machine's memory, nothing more.** No database is dropped,
  /// no sale, backup or platform record is touched; the dialog that offers it
  /// says so. Every file goes through its own store, and every store resolves
  /// its folder the same way (`getApplicationSupportDirectory`), so this is the
  /// same wipe on macOS and Windows. Files the installer wrote elsewhere (the
  /// Windows `ProgramData` role and credentials) are not this till's to delete.
  Future<void> runHard() async {
    await run();
    await _ref.read(licenseStoreProvider).clear();
    await _ref.read(licenceCheckStoreProvider).clear();
    await _ref.read(secretsFileProvider).deleteFile();
    // The OS store as well as the file. On Windows and macOS the secrets have
    // not been in `secrets.json` since the migration, and deleting only the
    // file would hand the next restaurant this one's device token.
    await _ref.read(secretStoreProvider).deleteAll();

    _ref.read(terminalProfileProvider.notifier).renew();
    _ref.read(signedInStaffProvider.notifier).signOut();

    // The wizard and everything that read the licence start again from disk.
    _ref.invalidate(licenceEntitlementProvider);
    _ref.invalidate(licenceClaimsProvider);
    _ref.invalidate(setupProvider);
  }
}

final terminalResetProvider = Provider<TerminalReset>(TerminalReset.new);

/// The shared `secrets.json`, for the hard reset to delete whole. A provider so
/// a test can point it at a temporary folder.
///
/// On Windows and macOS nothing writes this file any more; it is deleted here
/// in case a migration could not finish, or an older build wrote it again
/// after a downgrade. Deleting is all this provider is used for.
final secretsFileProvider = Provider<FileSecretStore>(
  (ref) => FileSecretStore(key: FileSecretStore.databasePasswordKey),
);

/// Where every secret this till keeps actually lives: DPAPI on Windows, the
/// Keychain on macOS, and a plaintext development file only on machines that
/// do not sell (ADR-006). The choice is [SecretStore.forPlatform]'s.
///
/// `main()` overrides this with the instance it migrated and restored at boot,
/// so the whole process shares one store. The DPAPI store serialises writes
/// to its file, and two instances would each do it on their own. Widget tests
/// get an in-memory store from `fakeRepositoryOverrides`.
final secretStoreProvider = Provider<SecretStore>(
  (ref) => SecretStore.forPlatform(),
);

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

  /// A brand-new installation: no terminal id, a new installation id. The hard
  /// reset's counterpart to [reset], which deliberately keeps both.
  void renew() => state = TerminalProfile(installationId: _uuid.v4());
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
/// Kept in the OS store between launches — Keychain on macOS, DPAPI on
/// Windows, see [secretStoreProvider] — never in `config.json`: a database
/// password written to a file is a password that gets emailed to support. The
/// store is attached in `main()`, so a widget test gets the in-memory one and
/// touches no keychain.
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

/// Reads which certificate a database server presents, for pairing.
///
/// Opens a socket and sends nothing but PostgreSQL's SSLRequest and a TLS
/// handshake it refuses; tests that reach a TLS failure override it.
final serverCertificateProbeProvider = Provider<ServerCertificateProbe>(
  (ref) => const PostgresCertificateProbe(),
);

/// This machine's own LAN certificate, as the installer published it — what
/// a technician reads off the main device to pair a till with it. Null on
/// a machine the installer did not open to the LAN, and everywhere but
/// Windows.
final publishedServerCertificateSourceProvider =
    Provider<PublishedServerCertificateSource>(
      (ref) => const FilePublishedServerCertificate(),
    );

final publishedServerCertificateProvider =
    FutureProvider<PresentedCertificate?>(
      (ref) => ref.watch(publishedServerCertificateSourceProvider).read(),
    );

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

/// The administrator database password, for the length of an Admin Mode
/// session.
///
/// Null outside Admin Mode. Entering loads it from [adminDbSecretStoreProvider]
/// and leaving — by Exit, by the inactivity timer, by the till being locked —
/// forgets it, so nothing that writes through [adminPosDatabaseProvider] works
/// for anybody who is not in. It used to be held from the first time anybody
/// typed it until the app quit, which is how a locked till opened the back
/// office.
///
/// `bin/pos_migrate.dart` still refuses to grant the till role and the
/// administrator role to the same name: the split between the two credentials
/// stands even now both are kept on this machine — see
/// [adminDbSecretStoreProvider] for what keeping this one costs.
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

/// Whether [password] gets the administrator role into the branch database.
///
/// A pool of its own, opened for the question and closed after it — not
/// [adminPosDatabaseProvider], which is built from the password already held.
/// Trying a password on that pool meant holding it first, and a held password
/// is what opens Management: the back office opened on one nobody had checked,
/// for as long as the check took. See `AdminSessionController.signIn`. A
/// function, so a test can answer the question without a server.
final adminPasswordProbeProvider =
    Provider<Future<PosDbFailure?> Function(String password)>((ref) {
      final config = ref.watch(adminDeploymentProvider);
      return (password) async {
        final database = PosDatabase(
          credentials: InMemoryPosDbCredentials(password),
        );
        try {
          return await database.probe(config);
        } finally {
          await database.close();
        }
      };
    });

/// The technician's reset of somebody's Admin Mode password (ADR-006b D5.4).
typedef TechnicianPasswordReset =
    Future<AdminResult<String?>> Function({
      required String username,
      required String databasePassword,
    });

/// Clears [username]'s Admin Mode password on a pool of its own, opened on
/// the database password the technician has just typed and closed after.
///
/// **Not [staffDirectoryRepositoryProvider].** That one writes on
/// [adminDbCredentialProvider], which holds the password this till KEEPS —
/// and the kept one is the one thing that must not be enough: anybody at the
/// till could then clear the owner's password and choose a new one with the
/// owner's PIN. Typing it is the proof, as on the forced reset. The caller
/// (`AdminSessionController.technicianClearPassword`) has already probed it
/// and counted a wrong one against Admin Mode's lockout. A function, so a
/// test can answer without a server.
final technicianPasswordResetProvider = Provider<TechnicianPasswordReset>((
  ref,
) {
  final config = ref.watch(adminDeploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  return ({required username, required databasePassword}) async {
    if (context == null || PosDatabase.hostFor(config) == null) {
      return const AdminResult<String?>.refused(NoDatabaseConfigured());
    }
    final database = PosDatabase(
      credentials: InMemoryPosDbCredentials(databasePassword),
    );
    try {
      return await PostgresStaffDirectoryRepository(
        database: database,
        config: config,
        restaurantId: context.restaurantId,
        branchId: context.branchId,
        terminalId: context.terminalId,
      ).clearPasswordAsTechnician(username: username);
    } finally {
      await database.close();
    }
  };
});

/// Applies the migrations this build carries and the database lacks, as the
/// back office's administrator.
///
/// **The only thing that upgrades an installed till.** The till's own role has
/// no DDL, the wizard runs once, and `bin/pos_migrate.dart` is a command nobody
/// at a restaurant runs — so a new version met a database a version behind it,
/// and the first pane that read a new table said so in SQL. The back-office
/// door is the one moment the app holds a credential that can change the
/// schema, so that is where this runs.
///
/// Null where there is nothing this till may upgrade: no database, or a
/// tablet, whose main device owns the schema and may be running an older build
/// that has never heard of what a newer tablet would add.
final schemaUpgraderProvider = Provider<Future<List<int>> Function()?>((ref) {
  final config = ref.watch(deploymentProvider);
  if (config.isChild || PosDatabase.hostFor(config) == null) return null;
  return () => LocalBootstrap(
    ref.read(adminPosDatabaseProvider),
  ).upgrade(ref.read(adminDeploymentProvider), till: config);
});

/// Where the cloud wizard looks for the database the installer built.
///
/// A provider so a test can say what kind of machine this is. The real source
/// reads a Windows path and answers null everywhere else, which is precisely
/// the fallback the wizard's connecting step is written around.
final installerCredentialsProvider = Provider<InstallerCredentialsSource>(
  (ref) => const FileInstallerCredentials(),
);

/// What building this machine's database did, so the wizard can say it.
class DatabaseBuildReport {
  const DatabaseBuildReport({
    required this.created,
    required this.migrations,
    this.tillRoleCreated = false,
  });

  /// False when the database was already there — the ordinary case on a machine
  /// the installer prepared, and not a failure.
  final bool created;
  final int migrations;

  /// True when the till's own PostgreSQL account had to be made here. False on
  /// a machine the installer prepared, where it was made before the wizard
  /// ever ran. See [LocalBootstrap.ensureTillRole].
  final bool tillRoleCreated;
}

/// Create the database, apply every migration this build carries, and grant the
/// till and the administrator what each needs — all as the administrator role.
///
/// A function provider for the same reason [schemaUpgraderProvider] is one: it
/// opens a PostgreSQL connection, and a widget test has none. The offline path
/// deliberately does NOT come through here — `bootstrapDatabase` also seeds a
/// restaurant, a branch, the system roles and the first person, none of which a
/// cloud terminal wants, because all of them arrive in the bootstrap bundle and
/// would be written over by it on the next seed.
final databaseBuilderProvider =
    Provider<
      Future<DatabaseBuildReport> Function(DeploymentConfig, String, String)
    >((ref) {
      return (config, adminPassword, tillPassword) async {
        // The admin connection: same host and database, a different role. The
        // password is used here and dropped with the pool.
        final admin = config.copyWith(databaseUser: config.adminDatabaseUser);
        final credentials = MutablePosDbCredentials()..set(adminPassword);
        final database = PosDatabase(credentials: credentials);
        final bootstrap = LocalBootstrap(database);

        try {
          final created = await LocalBootstrap.createDatabase(
            admin,
            adminPassword,
            config.databaseName,
          );
          // BEFORE the grants, because they are what needs it. On a machine
          // the installer prepared this finds the role and does nothing; on
          // the fallback path — a PostgreSQL somebody installed by hand, which
          // is the whole reason these fields are on screen — nobody has ever
          // made `pos_till`, and the build used to get all the way to
          // `GRANT … TO "pos_till"` before dying on a role that was not there.
          //
          // Skipped with no password to create it with, rather than refused:
          // the role is usually already there, and the GRANT below says so
          // plainly if it is not.
          final tillRoleCreated =
              tillPassword.isNotEmpty &&
              await LocalBootstrap.ensureTillRole(
                admin,
                adminPassword,
                name: config.databaseUser,
                password: tillPassword,
              );
          final applied = await bootstrap.migrate(admin);
          await bootstrap.applyGrants(admin, [
            ...LocalBootstrap.tillGrants(
              database: config.databaseName,
              role: config.databaseUser,
              // A cloud till runs `BootstrapSeeder`, so it is granted what that
              // writes. See [LocalBootstrap.tillGrants].
              cloudSeeding: true,
            ),
            ...LocalBootstrap.administrativeGrants(
              role: config.adminDatabaseUser,
            ),
          ]);
          return DatabaseBuildReport(
            created: created,
            migrations: applied.length,
            tillRoleCreated: tillRoleCreated,
          );
        } finally {
          await database.close();
        }
      };
    });

/// Seed what the bundle has no field for, as the administrator role.
///
/// Void, refund, discount and price-override reasons, and what each kind of
/// order requires. The platform authors the restaurant and `BootstrapSeeder`
/// writes it, but neither carries these — they are the till's own defaults,
/// and on the offline path `bootstrapDatabase` seeds them. The cloud path
/// never did, so a cloud till opened with an empty list behind every void and
/// pay-out dialog. Found in the 22 Sep 2026 review.
///
/// **Not the tax group.** On a cloud till the platform's money config IS the
/// rate (POS-BE-013), and `TaxConfig.defaultTaxGroup` prefers a stored
/// `is_default` row over `vatBp` — so a local 14% default would silently
/// override whatever the dashboard set. Products from the bundle name no
/// group, and an empty table costs nothing.
///
/// A function provider for the reason [databaseBuilderProvider] is one. Runs
/// AFTER the seeder, because the lists hang off a restaurant row only the
/// bundle can create. Upserts on the code, so a re-run keeps a renamed or
/// retired reason.
final cloudDefaultsSeederProvider =
    Provider<Future<void> Function(DeploymentConfig, String, int)>((ref) {
      return (config, adminPassword, restaurantId) async {
        final admin = config.copyWith(databaseUser: config.adminDatabaseUser);
        final credentials = MutablePosDbCredentials()..set(adminPassword);
        final database = PosDatabase(credentials: credentials);
        final bootstrap = LocalBootstrap(database);

        try {
          await bootstrap.seedReasonCodes(admin, restaurantId);
          await bootstrap.seedOrderTypes(admin, restaurantId);
        } finally {
          await database.close();
        }
      };
    });

/// Why the last upgrade at the back-office door failed, or null.
///
/// Held rather than thrown: a failed upgrade must not keep anybody out of the
/// back office — Backup is in there — so it is said above the panes instead.
class SchemaUpgradeFailure extends Notifier<String?> {
  @override
  String? build() => null;

  void report(String message) => state = message;

  void clear() => state = null;
}

final schemaUpgradeFailureProvider =
    NotifierProvider<SchemaUpgradeFailure, String?>(SchemaUpgradeFailure.new);

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

/// The categories turned off. The till's grid never sees these
/// (`catalogProvider` is active-only); the Menu and Sections panes list them so
/// the owner can switch one back on.
final inactiveCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final repository = ref.watch(catalogAdminRepositoryProvider);
  return repository == null ? const [] : repository.inactiveCategories();
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

/// What each counted item stands at here. On the administrator's credential:
/// the till holds no grant on stock levels.
final stockLevelsRepositoryProvider = Provider<StockLevelsRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredStockLevelsRepository();
  }
  return PostgresStockLevelsRepository(
    database: ref.watch(adminPosDatabaseProvider),
    config: ref.watch(adminDeploymentProvider),
    restaurantId: context.restaurantId,
    branchId: context.branchId,
  );
});

/// Auto-disposed, so the pane reads fresh each time it is opened — after the
/// delivery that was received a minute ago, not before it.
final stockLevelsProvider = FutureProvider.autoDispose<List<StockLevel>>(
  (ref) => ref.watch(stockLevelsRepositoryProvider).all(),
);

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
/// Who the food is for (POS-BE-014). Searched locally, always — see
/// [CustomersRepository].
final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);
  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredCustomersRepository();
  }
  return PostgresCustomersRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    restaurantId: context.restaurantId,
    branchId: context.branchId,
    syncsToPlatform: config.mode.syncsSalesToPlatform,
    onQueued: () => ref.read(cloudSyncProvider)?.nudge(),
  );
});

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

// ── Financial accounts (XORD-015, stage 1) ─────────────────────────────────
//
// Where the business keeps its money, and which account each payment method
// pays into. Nothing reads them to move money yet.

final financialAccountsRepositoryProvider =
    Provider<FinancialAccountsRepository>((ref) {
      final config = ref.watch(deploymentProvider);
      final context = ref.watch(posWriteContextProvider);
      if (context == null || PosDatabase.hostFor(config) == null) {
        return const UnconfiguredFinancialAccountsRepository();
      }
      return PostgresFinancialAccountsRepository(
        database: ref.watch(posDatabaseProvider),
        config: config,
        restaurantId: context.restaurantId,
      );
    });

/// Every account including switched-off ones, for the back office, which has
/// to show a retired one to let somebody bring it back.
final financialAccountsProvider = FutureProvider<List<FinancialAccount>>(
  (ref) => ref
      .watch(financialAccountsRepositoryProvider)
      .accounts(includeInactive: true),
);

/// The branches an account can be tied to.
final accountBranchesProvider = FutureProvider<List<PosBranch>>(
  (ref) => ref.watch(financialAccountsRepositoryProvider).branches(),
);

final tenderAccountDefaultsProvider =
    FutureProvider<List<TenderAccountDefault>>(
      (ref) => ref.watch(financialAccountsRepositoryProvider).defaults(),
    );

/// Authoring accounts. Null on a CLOUD till: the platform is the single author
/// there and `BootstrapSeeder` replaces these rows from the bundle, so an
/// account made here would last until the next sync. Null is also "no
/// database", and the pane reads both as "read, do not offer to write".
final financialAccountsAdminRepositoryProvider =
    Provider<FinancialAccountsAdminRepository?>((ref) {
      final config = ref.watch(deploymentProvider);
      final context = ref.watch(posWriteContextProvider);

      if (config.mode != DeploymentMode.offline) return null;
      if (context == null || PosDatabase.hostFor(config) == null) return null;

      return PostgresFinancialAccountsAdminRepository(
        database: ref.watch(adminPosDatabaseProvider),
        config: ref.watch(adminDeploymentProvider),
        adminAvailable: ref.watch(adminDbCredentialProvider) != null,
        offline: true,
        restaurantId: context.restaurantId,
        branchId: context.branchId,
        terminalId: context.terminalId,
      );
    });

/// Whether e-receipts are filed on this build. See [etaFilingEnabled].
///
/// A provider so a test of the filing screens can turn it on.
final etaFilingEnabledProvider = Provider<bool>((_) => etaFilingEnabled);

/// The queue of receipts owed to Egypt's tax authority.
///
/// Null where there is no database to queue into, and wherever filing is off —
/// which takes the filer, the reconciler and every warning they raise with it.
/// Not null on a cloud till: the obligation is the restaurant's, not the
/// deployment's, and a cloud terminal in Cairo owes the same receipts an
/// offline one does.
final etaQueueRepositoryProvider = Provider<EtaQueueRepository?>((ref) {
  if (!ref.watch(etaFilingEnabledProvider)) return null;
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
/// Beside the till's own, in the OS store ([secretStoreProvider]) — see
/// [FileSecretStore.backupPasswordKey] for why keeping this one is safe and
/// keeping the administrator's is not.
final backupPasswordStoreProvider = Provider<PosDbSecretStore>(
  (ref) => KeyedSecretStore(
    ref.watch(secretStoreProvider),
    FileSecretStore.backupPasswordKey,
  ),
);

/// The back office's database password, kept on this machine.
///
/// **This reverses a rule, deliberately.** Until 12 September 2026 the
/// administrator's password was never kept anywhere: it was typed at the
/// back-office door and held in memory. The owner chose Admin Mode to be a
/// username and a PIN and nothing else (owner decision, 12 Sep 2026), which
/// leaves no field to type it into — so the setup wizard keeps it here, beside
/// the till's, and Admin Mode loads it into [adminDbCredentialProvider] only
/// for the length of a session. An install from before that asks for it once.
///
/// What that costs, stated rather than implied. It is in the OS store now
/// ([secretStoreProvider]), so a copy of the till's files is no longer a copy
/// of it. But DPAPI and the login keychain open for anything running as the
/// till's own OS account, so anybody with that session has the
/// administrator's rights to the branch database without a PIN. What still
/// holds: nobody at the till's screen gets a pane without a username and PIN
/// holding `admin.enter`, and every write still goes through the repositories'
/// own permission checks. Whether this one should be kept at all is open
/// (GAPS Q17; ADR-006 proposes not), and is not decided here.
final adminDbSecretStoreProvider = Provider<PosDbSecretStore>(
  (ref) => KeyedSecretStore(
    ref.watch(secretStoreProvider),
    FileSecretStore.adminPasswordKey,
  ),
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

/// Who has an Admin Mode password, by staff id — what the staff pane's Clear
/// password button asks. Not a field read by `all()`: that query is also the
/// lock screen's roster ([signInCandidatesProvider]), which must keep working
/// on a database the upgrade that adds this column has not reached.
final staffWithPasswordProvider = FutureProvider<Set<int>>(
  (ref) => ref.watch(staffDirectoryRepositoryProvider).withPassword(),
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
