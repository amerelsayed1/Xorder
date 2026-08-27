import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/config/deployment.dart';
import '../core/l10n/app_strings.dart';
import '../core/money/money.dart';
import '../core/network/connectivity_probe.dart';
import '../data/postgres/pos_database.dart';
import '../data/postgres/postgres_catalog_repository.dart';
import '../data/postgres/postgres_directory_repositories.dart';
import '../data/postgres/postgres_floor_repository.dart';
import '../data/postgres/postgres_orders_repository.dart';
import '../data/postgres/postgres_shift_repository.dart';
import '../data/unconfigured/unconfigured_repositories.dart';
import '../features/licensing/data/file_license_store.dart';
import '../features/licensing/data/licence_service.dart';
import '../features/licensing/data/license_keys.dart';
import '../features/licensing/data/license_store.dart';
import '../features/licensing/domain/license_verifier.dart';
import '../features/licensing/domain/license.dart';
import '../domain/models/catalog.dart';
import '../domain/models/dining_table.dart';
import '../domain/models/ticket.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/ticket_engine.dart';

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
  if (PosDatabase.hostFor(config) == null) return const UnconfiguredCatalogRepository();

  // Scoped by tenant slug rather than by the numeric restaurant id, because the
  // catalogue is first pulled during setup — before a terminal has been claimed
  // and an id is known.
  return PostgresCatalogRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
  );
});

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
final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  final context = ref.watch(posWriteContextProvider);

  if (context == null || PosDatabase.hostFor(config) == null) {
    return const UnconfiguredOrdersRepository();
  }
  return PostgresOrdersRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
    context: context,
    // Read, not watched. A sale stamps the shift that was open when it was
    // rung up; rebuilding the repository mid-payment because a shift closed
    // elsewhere would be worse than an unattributed order.
    shiftId: ref.read(shiftProvider).valueOrNull?.id,
  );
});

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  if (PosDatabase.hostFor(config) == null) return const UnconfiguredBranchRepository();

  return PostgresBranchRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
  );
});

final provisioningRepositoryProvider = Provider<ProvisioningRepository>((ref) {
  final config = ref.watch(deploymentProvider);
  if (PosDatabase.hostFor(config) == null) {
    return const UnconfiguredProvisioningRepository();
  }
  return PostgresProvisioningRepository(
    database: ref.watch(posDatabaseProvider),
    config: config,
  );
});

/// Printer, drawer and scanner discovery.
///
/// Still unimplemented on every platform — it needs USB and network transports
/// behind a platform channel. It now reports **nothing found** rather than the
/// two plausible-looking printers it used to invent, which an operator could
/// select and then discover at service time was never attached.
final hardwarePortsProvider =
    Provider<HardwarePorts>((ref) => const UndiscoverableHardwarePorts());

final branchesProvider =
    FutureProvider<List<PosBranch>>((ref) => ref.watch(branchRepositoryProvider).forTenant());

final sessionProvider = FutureProvider<PosSession>(
  (ref) => ref.watch(sessionRepositoryProvider).current(),
);

final catalogProvider = FutureProvider<Catalog>(
  (ref) => ref.watch(catalogRepositoryProvider).load(),
);

final tablesProvider = FutureProvider<List<DiningTable>>(
  (ref) => ref.watch(tablesRepositoryProvider).liveFloor(),
);

/// Non-ticket screen state: which category is selected, what is in the search
/// box, and whether the terminal believes it is online.
class PosUiState {
  const PosUiState({
    this.selectedCategoryId,
    this.query = '',
    this.online = true,
    this.queuedCount = 0,
  });

  /// null = "All items".
  final int? selectedCategoryId;
  final String query;
  final bool online;
  final int queuedCount;

  PosUiState copyWith({
    int? selectedCategoryId,
    String? query,
    bool? online,
    int? queuedCount,
    bool clearCategory = false,
  }) =>
      PosUiState(
        selectedCategoryId:
            clearCategory ? null : (selectedCategoryId ?? this.selectedCategoryId),
        query: query ?? this.query,
        online: online ?? this.online,
        queuedCount: queuedCount ?? this.queuedCount,
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

  void noteQueued(int count) => state = state.copyWith(queuedCount: count);
}

final posUiProvider =
    NotifierProvider<PosUiController, PosUiState>(PosUiController.new);

/// The live ticket.
///
/// All mutations delegate to [TicketEngine], which is pure and unit-tested. The
/// controller's only job is to hold the current value and surface refusals.
class TicketController extends Notifier<Ticket> {
  @override
  Ticket build() => Ticket(id: _uuid.v4(), orderType: OrderType.dineIn);

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
  }) =>
      _apply(TicketEngine.addLine(
        state,
        product,
        modifiers: modifiers,
        groups: groups,
        quantity: quantity,
      ));

  void changeQuantity(String lineKey, int delta) =>
      state = TicketEngine.changeQuantity(state, lineKey, delta);

  void removeLine(String lineKey) =>
      state = TicketEngine.removeLine(state, lineKey);

  void sendRound() => state = TicketEngine.sendRound(state);

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
  }) =>
      _apply(TicketEngine.addTender(
        state,
        typeId: typeId,
        label: label,
        amount: amount,
        reference: reference,
      ));

  void removeTenderAt(int index) =>
      state = TicketEngine.removeTenderAt(state, index);

  /// Start a fresh ticket with a **new** client transaction id. The id must
  /// change here and only here — reusing one would make the next sale look like
  /// a replay of the last.
  void reset() => state = TicketEngine.clear(state, newId: _uuid.v4());
}

final ticketProvider =
    NotifierProvider<TicketController, Ticket>(TicketController.new);


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
final signedInStaffProvider = NotifierProvider<SignedInStaffController, PosStaff?>(
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
final connectivityProbeProvider =
    Provider<ConnectivityProbe>((ref) => const FakeConnectivityProbe());

/// Licence verification.
///
/// **Signatures are checked for real.** This used to be bound to
/// `FakeLicenceService`, which accepted any non-empty key — `HELLO` licensed a
/// terminal for a year — and skipped the signature check entirely. The verifier
/// now holds the Ed25519 public key that ships in the binary, and only a file
/// signed by the matching private key activates anything.
///
/// `remote` is null because no licence server exists yet, so *Activate online*
/// is not offered at all rather than offered and always failing. Licences are
/// issued with `bin/pos_licence.dart` and installed from the `.xlic` file.
///
/// The fingerprint follows the terminal id — generated once on this machine and
/// never reissued — so a licence can be pinned to a till. It is hashed, so what
/// a licence carries says nothing about the machine or the person on it.
final licenceServiceProvider = Provider<LicenceService>((ref) {
  return DefaultLicenceService(
    verifier: LicenseVerifier(publicKeyBytes: LicenseKeys.current),
    store_: ref.watch(licenseStoreProvider),
    fingerprint: TerminalIdFingerprint(ref.watch(terminalProfileProvider).terminalId),
    clock: DateTime.now,
  );
});

/// Where the installed licence lives between launches.
///
/// On disk, not in memory: a licence that had to be reinstalled on every launch
/// would make the till unusable the first morning somebody restarted it.
final licenseStoreProvider = Provider<LicenseStore>((ref) => FileLicenseStore());

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
  Locale build() => const Locale('en');

  void apply(String languageCode) => state = Locale(languageCode);
}

final localeProvider =
    NotifierProvider<TerminalLocaleController, Locale>(TerminalLocaleController.new);

/// The till's words, for code that has no [BuildContext] to reach them
/// through — controllers that produce operator-facing text, mainly.
final stringsProvider =
    Provider<AppStrings>((ref) => AppStrings.of(ref.watch(localeProvider)));

/// How this terminal is deployed. Written once by the setup wizard, then read
/// by everything that needs to know whether a server exists to talk to.
class DeploymentController extends Notifier<DeploymentConfig> {
  @override
  DeploymentConfig build() => DeploymentConfig.unconfigured;

  void apply(DeploymentConfig config) => state = config;
}

final deploymentProvider =
    NotifierProvider<DeploymentController, DeploymentConfig>(DeploymentController.new);

/// True once first-run setup has been completed on this terminal.
///
/// Kept in memory here; the persistent implementation reads the saved
/// deployment file, which is what makes the wizard a genuinely one-time screen.
class SetupCompletionController extends Notifier<bool> {
  @override
  bool build() => false;

  void markComplete() => state = true;
}

final setupCompleteProvider =
    NotifierProvider<SetupCompletionController, bool>(SetupCompletionController.new);

/// The licence entitlement currently in force.
///
/// Re-read at boot and before each shift opens rather than cached for the
/// process lifetime, so a renewal takes effect without restarting the till.
final licenceEntitlementProvider = FutureProvider<LicenseEntitlement>(
  (ref) => ref.watch(licenceServiceProvider).current(ref.watch(deploymentProvider)),
);


/// What the setup wizard decided about *this* terminal.
///
/// Kept separate from [sessionProvider], which describes the signed-in person
/// and comes from the server. Branch and till name are properties of the
/// machine, chosen once at setup, and must survive a different cashier signing
/// in — so they are not read off the session.
class TerminalProfile {
  const TerminalProfile({
    this.branchId,
    this.branchName,
    this.terminalName,
    this.terminalId,
    this.provisioned = false,
    this.restaurantId,
    this.branchCode,
  });

  /// Stamped on every row this till writes. Comes from provisioning, never from
  /// anything the cashier can type.
  final int? restaurantId;

  /// Invoice prefix (POS-BE-005).
  final String? branchCode;

  final int? branchId;
  final String? branchName;
  final String? terminalName;
  final String? terminalId;

  /// True when this terminal was created in the dashboard and claimed with a
  /// pairing code, rather than registering itself. Worth keeping: a provisioned
  /// terminal's id came from the server, so it is the same row Super Admin is
  /// already tracking (POS-BE-023).
  final bool provisioned;

  bool get isSet => terminalName?.isNotEmpty ?? false;
}

class TerminalProfileController extends Notifier<TerminalProfile> {
  @override
  TerminalProfile build() => const TerminalProfile();

  void apply(TerminalProfile profile) => state = profile;
}

final terminalProfileProvider =
    NotifierProvider<TerminalProfileController, TerminalProfile>(TerminalProfileController.new);

/// The password the setup wizard collected, held for this process.
///
/// Separate from [posDbCredentialsProvider] only so the wizard has something
/// typed to write to while everything else depends on the interface. Both
/// resolve to the same object in production.
final posDbCredentialsStoreProvider =
    Provider<MutablePosDbCredentials>((ref) => MutablePosDbCredentials());

/// Where the till's database password comes from.
///
/// The role is `pos_till` — granted `SELECT` and `INSERT` on the POS tables and
/// nothing else. Never a superuser, never `DELETE`, never DDL, so a recovered
/// credential cannot rewrite history.
///
/// Held in memory today, which means the operator retypes it after a restart.
/// That is deliberate until `flutter_secure_storage` is wired: a database
/// password written to a file is a password that gets emailed to support.
final posDbCredentialsProvider =
    Provider<PosDbCredentials>((ref) => ref.watch(posDbCredentialsStoreProvider));

/// The connection pool to the branch server. One per app.
final posDatabaseProvider = Provider<PosDatabase>((ref) {
  final database = PosDatabase(credentials: ref.watch(posDbCredentialsProvider));
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

  if (restaurantId == null || branchId == null || terminalId == null || branchCode == null) {
    return null;
  }
  return PosWriteContext(
    restaurantId: restaurantId,
    branchId: branchId,
    terminalId: terminalId,
    branchCode: branchCode,
  );
});
