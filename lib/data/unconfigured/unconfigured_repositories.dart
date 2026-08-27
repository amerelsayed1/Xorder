import '../../core/money/money.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/ticket.dart';
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
/// a menu, a floor plan and a cashier belonging to a restaurant that does not
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
  Future<PosStaff?> signIn(String pin) async => null;
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
  Future<PosShift> open({required PosStaff by, required Money openingFloat}) async =>
      throw _noDatabase;

  @override
  Future<ShiftSummary> summarise(PosShift shift) async => throw _noDatabase;

  @override
  Future<ShiftClose> close({
    required PosShift shift,
    required PosStaff by,
    required Money countedCash,
    String? note,
  }) async =>
      throw _noDatabase;
}

class UnconfiguredProvisioningRepository implements ProvisioningRepository {
  const UnconfiguredProvisioningRepository();

  static const _message = ClaimResult(
    code: 'NO_DATABASE',
    message: 'This terminal cannot reach a branch database yet. Go back to the '
        'connection step and test it.',
  );

  @override
  Future<ClaimResult> claimByCode({required String tenantSlug, required String code}) async =>
      _message;

  @override
  Future<ClaimResult> registerManually({
    required String tenantSlug,
    required String username,
    required String password,
    required String terminalName,
    required int branchId,
  }) async =>
      _message;
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
  Future<SubmitOrderResult> submit(Ticket ticket) async => throw StateError(
        'This terminal has nowhere to record a sale. It is not connected to a '
        'branch database, and there is no local queue yet — so this sale cannot '
        'be taken on this till.',
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
}
