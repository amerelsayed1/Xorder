import '../../core/money/money.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/held_sync.dart';
import '../../domain/models/ticket.dart';
import '../../domain/models/permissions.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';

/// What the till uses before it has a branch database to read.
///
/// These exist because a provider cannot throw at construction — a terminal
/// halfway through setup has no connection yet, and a binding that blew up
/// would take the app down before the wizard could fix it.
///
/// **They return nothing rather than something.** The bindings that used to sit
/// here were the `Fake…` repositories, which meant an unconfigured till — and,
/// because nothing distinguished a release build, *every* till — opened showing
/// a menu, a floor plan and a cashier belonging to a business that does not
/// exist. Empty is the honest answer to "what is on this terminal's menu"
/// before anyone has told it. The one thing that must never be quietly empty is
/// taking money, so [UnconfiguredOrdersRepository] refuses out loud instead.
class UnconfiguredCatalogRepository implements CatalogRepository {
  const UnconfiguredCatalogRepository();

  @override
  Future<Catalog> load({DateTime? since}) async => Catalog.empty;
}

class UnconfiguredTablesRepository implements TablesRepository {
  const UnconfiguredTablesRepository();

  @override
  Future<List<DiningTable>> liveFloor() async => const [];
}

class UnconfiguredBranchRepository implements BranchRepository {
  const UnconfiguredBranchRepository();

  @override
  Future<List<PosBranch>> forTenant() async => const [];
}

class UnconfiguredSessionRepository implements SessionRepository {
  const UnconfiguredSessionRepository();

  /// Throws rather than returning a placeholder person. The screens that read a
  /// session are all behind completed setup, so reaching this is a real fault,
  /// and a made-up cashier name would print on receipts.
  @override
  Future<PosSession> current() async => throw StateError(
    'This terminal has no branch database configured, so it cannot say who '
    'is working it. Finish setup, or check the connection in Settings.',
  );

  @override
  Future<bool> verifyPin(String pin) async => false;

  @override
  Future<PosStaff?> signInAs({
    required String username,
    required String pin,
  }) async => null;

  @override
  Future<PosStaff?> signIn(String pin) async => null;

  @override
  Future<PosStaff?> signInWithPassword({
    required String username,
    required String password,
  }) async => null;
}

/// Refuses to open a shift, because there is nowhere to record one.
///
/// [current] returns null rather than throwing: the start screen asks whether a
/// shift is already open on every build, and an unconfigured till answering
/// "no" is both true and harmless.
class UnconfiguredShiftRepository implements ShiftRepository {
  const UnconfiguredShiftRepository();

  static StateError get _noDatabase => StateError(
    'This terminal has no branch database, so it cannot record a shift or '
    'account for a drawer. Finish setup first.',
  );

  @override
  Future<PosShift?> current() async => null;

  @override
  Future<PosShift> open({
    required PosStaff by,
    required Money openingFloat,
  }) async => throw _noDatabase;

  @override
  Future<ShiftSummary> summarise(PosShift shift) async => throw _noDatabase;

  /// Nothing, for the same reason [current] is null: no shift can have been
  /// opened on a till with nowhere to record one, so "none" is the truth.
  @override
  Future<ShiftActivity> activity() async => ShiftActivity.empty;

  /// None, for the same reason again.
  @override
  Future<List<OpenDrawer>> openDrawers() async => const [];

  /// None, and for the same reason: an empty list is the truth here, where
  /// throwing would put an error on a back-office screen for a till that has
  /// simply not been set up.
  @override
  Future<ShiftHistory> history(ShiftHistoryQuery query) async =>
      ShiftHistory.empty;

  @override
  Future<ShiftClose> close({
    required PosShift shift,
    required PosStaff by,
    required Money countedCash,
    String? note,
    Approval? approval,
  }) async => throw _noDatabase;
}

class UnconfiguredProvisioningRepository implements ProvisioningRepository {
  const UnconfiguredProvisioningRepository();

  static const _message = ClaimResult(
    code: 'NO_DATABASE',
    message:
        'This terminal cannot reach a branch database yet. Go back to the '
        'connection step and test it.',
  );

  @override
  Future<ClaimResult> claimByCode({
    required String tenantSlug,
    required String code,
  }) async => _message;

  @override
  Future<TenantConnection> connect({
    required String tenantSlug,
    required String username,
    required String password,
  }) async => const TenantConnection(
    code: 'NO_PLATFORM',
    message:
        'This terminal has no platform address yet. Go back to the '
        'connection step and set one.',
  );

  @override
  Future<ClaimResult> registerManually({
    required String tenantSlug,
    required String username,
    required String password,
    required String terminalName,
    required int branchId,
    required String? installId,
  }) async => _message;

  @override
  Future<ClaimResult> adoptTerminal({
    required String tenantSlug,
    required String username,
    required String password,
    required int terminalId,
  }) async => _message;
}

/// Refuses to take money, loudly.
///
/// The binding this replaced recorded the sale in a list in memory and reported
/// it as *queued*, which printed `QUEUED OFFLINE — WILL SYNC` on the customer's
/// receipt for a sale that had been written precisely nowhere. A till that
/// cannot record a sale must refuse it at the counter, where somebody can still
/// take the money another way.
class UnconfiguredOrdersRepository implements OrdersRepository {
  const UnconfiguredOrdersRepository();

  @override
  Future<SubmitOrderResult> submit(
    Ticket ticket, {
    PosStaff? servedBy,
    int? parkedVersion,
  }) async => throw StateError(
    'This terminal has nowhere to record a sale. It is not connected to a '
    'database, so this sale cannot be taken on this till.',
  );

  /// Nothing was ever taken here, so nothing is owed.
  @override
  Future<int> pendingSyncCount() async => 0;

  /// Refuses out loud, for the same reason [submit] does. A void that reported
  /// success while writing nowhere would tell a manager the waste was recorded
  /// when it was not.
  @override
  Future<SubmitOrderResult> voidOrder(
    Ticket ticket, {
    required PosStaff by,
    int? reasonId,
    String? note,
    Approval? approval,
    PosStaff? servedBy,
    int? parkedVersion,
  }) async => throw StateError(
    'This terminal has nowhere to record a void. It is not connected to a '
    'database, so this cannot be recorded on this till.',
  );
}

/// Hardware discovery is not implemented on any platform yet.
///
/// Returns nothing rather than the two invented printers that used to be here.
/// A till with no printer is a valid till — setup completes, the receipt
/// queues, and the UI says so — which is exactly what an empty list produces.
class UndiscoverableHardwarePorts implements HardwarePorts {
  const UndiscoverableHardwarePorts();

  @override
  Future<List<DiscoveredPrinter>> discoverPrinters() async => const [];

  @override
  Future<bool> testPrint(String printerName) async => false;

  /// Nothing was sent, and it says so. The receipt path queues on false, so a
  /// terminal bound to this loses no paper — it just prints none.
  @override
  Future<bool> sendJob({
    required String printerName,
    required List<int> bytes,
  }) async => false;
}

/// Administration before there is a database to administer.
///
/// Reads come back empty and writes come back refused with
/// [NoDatabaseConfigured], so the Management screen renders its "this terminal
/// is not set up" state rather than either crashing or — worse — showing an
/// empty staff list that reads as a business with nobody working at it.
class UnconfiguredRolesRepository implements RolesRepository {
  const UnconfiguredRolesRepository();

  @override
  Future<List<PosRole>> all() async => const [];

  @override
  Future<AdminResult<PosRole>> save(
    PosRole role, {
    required PosStaff by,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<void>> delete(
    PosRole role, {
    required PosStaff by,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}

class UnconfiguredStaffDirectoryRepository implements StaffDirectoryRepository {
  const UnconfiguredStaffDirectoryRepository();

  @override
  Future<List<PosStaff>> all({bool includeInactive = true}) async => const [];

  @override
  Future<PosStaff?> byPin(String pin) async => null;

  @override
  Future<AdminResult<PosStaff>> create({
    required PosStaff by,
    required String name,
    required String username,
    required String pin,
    required int roleId,
    int? branchId,
    Set<String> directGrants = const {},
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<PosStaff>> update({
    required PosStaff by,
    required int staffId,
    String? name,
    String? username,
    int? roleId,
    Set<String>? directGrants,
    int? branchId,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<PosStaff>> setActive({
    required PosStaff by,
    required int staffId,
    required bool isActive,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<void>> resetPin({
    required PosStaff by,
    required int staffId,
    required String pin,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<Set<int>> withPassword() async => const {};

  @override
  Future<AdminResult<void>> setOwnPassword({
    required PosStaff by,
    required String password,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<void>> clearPassword({
    required PosStaff by,
    required int staffId,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<String?>> clearPasswordAsTechnician({
    required String username,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<PosStaff>> setGrants({
    required PosStaff by,
    required int staffId,
    required Set<int> extraRoleIds,
    required List<PermissionOverride> overrides,
    required Map<String, PermissionLimit> limits,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}

/// Silently drops what it is given.
///
/// The one place a no-op is right: an audit call must never be the reason a
/// sale or a shift fails. On a configured till the ledger write shares the
/// transaction with the change it describes, so it cannot be lost there; here
/// there is no change to describe either.
class UnconfiguredAuditRepository implements AuditRepository {
  const UnconfiguredAuditRepository();

  @override
  Future<void> record({
    required PosStaff by,
    required String action,
    required String entityType,
    PosStaff? approvedBy,
    String? entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String? reason,
  }) async {}

  @override
  Future<List<AuditEntry>> recent({
    int limit = 100,
    String? entityType,
    String? entityId,
    int? staffId,
  }) async => const [];
}

/// Nothing held, because there is nothing to hold it in.
///
/// Also what an offline till binds: it owes the platform nothing, so it has no
/// queue for the platform to refuse anything from. Release refuses rather than
/// pretending, for the reason every write here does.
class UnconfiguredSyncQueueRepository implements SyncQueueRepository {
  const UnconfiguredSyncQueueRepository();

  @override
  Future<List<HeldSyncItem>> listHeldSync() async => const [];

  @override
  Future<int> heldSyncCount() async => 0;

  @override
  Future<AdminResult<HeldSyncItem>> releaseHeldSync(
    HeldSyncItem item, {
    required PosStaff by,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}
