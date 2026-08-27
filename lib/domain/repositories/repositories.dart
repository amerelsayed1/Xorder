import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../models/catalog.dart';
import '../models/dining_table.dart';
import '../models/shift.dart';
import '../models/ticket.dart';

export '../models/shift.dart' show PosStaff, PosShift, ShiftSummary, ShiftTenderTotal, ShiftClose;

/// Repository contracts.
///
/// The UI depends on these, never on HTTP. That is what lets the POS keep being
/// built while every backend contract in `docs/coordination/POS_TO_BACKEND.md`
/// is still `PROPOSED` — each interface has a `Fake…` implementation today and
/// an `Api…` implementation the day Agent 2 marks the contract `READY`.
abstract interface class CatalogRepository {
  /// Full catalog pull. `since` requests a delta (POS-BE-012, still PROPOSED);
  /// implementations that cannot do deltas ignore it and return everything.
  Future<Catalog> load({DateTime? since});
}

abstract interface class TablesRepository {
  Future<List<DiningTable>> liveFloor();
}

/// Outcome of submitting an order.
///
/// [invoiceNumber] is null while the order is queued offline — the till prints a
/// provisional, terminal-scoped reference and marks the receipt provisional. The
/// authoritative number is assigned by the server on sync (POS-BE-008).
class SubmitOrderResult {
  const SubmitOrderResult({
    required this.clientTransactionId,
    required this.queued,
    this.serverId,
    this.invoiceNumber,
    this.totalsMismatch = false,
  });

  final String clientTransactionId;
  final bool queued;
  final int? serverId;
  final String? invoiceNumber;

  /// The server re-priced and disagreed with what the till charged. Money has
  /// already changed hands, so this is a reconciliation prompt, not a failure.
  final bool totalsMismatch;
}

abstract interface class OrdersRepository {
  /// Submit a settled ticket.
  ///
  /// Implementations must be safe to call repeatedly with the same
  /// `ticket.id` — that is the `client_transaction_id` the server deduplicates
  /// on (POS-BE-007). **A submission is never silently discarded.**
  Future<SubmitOrderResult> submit(Ticket ticket);
}

/// A signed-in cashier and the terminal they are working.
class PosSession {
  const PosSession({
    required this.userName,
    required this.tenantName,
    required this.branchName,
    required this.terminalCode,
    required this.shiftReference,
    this.capabilities = const {},
  });

  final String userName;
  final String tenantName;
  final String branchName;
  final String terminalCode;
  final String shiftReference;

  /// Mirrors `UserResource.capabilities[]`. The client gates UI on these; the
  /// server re-gates on every write, so this is convenience, not security.
  final Set<String> capabilities;

  bool can(String capability) => capabilities.contains(capability);

  String get initials {
    final parts = userName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters;
    return '${parts.first.characters}${parts[1].characters}';
  }
}

extension on String {
  String get characters => isEmpty ? '' : substring(0, 1).toUpperCase();
}

abstract interface class SessionRepository {
  Future<PosSession> current();

  /// Verify a cashier PIN against the cached hash, so the lock screen works
  /// offline. Never round-trips.
  Future<bool> verifyPin(String pin);

  /// Identify *who* just entered that PIN.
  ///
  /// Separate from [verifyPin] because the two questions are genuinely
  /// different: unlocking a terminal only needs to know that somebody who works
  /// here is present, while opening a shift needs a name to put against the
  /// money. Returns null when no active member of staff has that PIN.
  Future<PosStaff?> signIn(String pin);
}

/// Opening and closing a till session, and counting the drawer.
///
/// The rule the implementation must hold is **one open shift per terminal**. Two
/// means two people each believe they are answerable for the same drawer, and
/// the second cash-up silently contradicts the first.
abstract interface class ShiftRepository {
  /// The shift this terminal currently has open, if any.
  Future<PosShift?> current();

  Future<PosShift> open({required PosStaff by, required Money openingFloat});

  /// Everything the shift took, for the Z report and the expected drawer total.
  Future<ShiftSummary> summarise(PosShift shift);

  /// Count the drawer and close.
  ///
  /// The variance is computed and **stored** rather than derived later: it is
  /// the number a manager argues about, and recomputing it from rows that may
  /// have moved on would quietly rewrite history.
  Future<ShiftClose> close({
    required PosShift shift,
    required PosStaff by,
    required Money countedCash,
    String? note,
  });
}


/// What a terminal learns about itself when it takes its place in a restaurant.
///
/// The dashboard creates the terminal first and the till claims it
/// (POS-BE-023). That inversion is what makes an offline terminal trackable at
/// all: the record exists before the machine does, so a till that never claims
/// is visibly a till that never activated, rather than one nobody knew about.
class TerminalClaim {
  const TerminalClaim({
    required this.terminalId,
    required this.terminalName,
    required this.branchId,
    required this.branchName,
    required this.syncPolicy,
    this.restaurantId,
    this.branchCode,
  });

  /// Server-assigned, not device-generated, on the provisioned path — the
  /// dashboard already named this till before anyone unboxed it.
  final String terminalId;
  final String terminalName;
  final int branchId;
  final String branchName;

  /// Chosen by whoever provisioned the terminal, so a manager sets the policy
  /// for a branch rather than each cashier deciding at the counter.
  final SyncPolicy syncPolicy;

  /// The tenant this terminal belongs to. Every row the till writes is stamped
  /// with it, and it is never read from user input.
  final int? restaurantId;

  /// Invoice prefix (POS-BE-005). `MAADI` in `MAADI-2026-001042`.
  final String? branchCode;
}

/// Outcome of a claim attempt.
///
/// A mistyped or expired pairing code is normal operation, not an exceptional
/// one, so refusals come back as data — the same reasoning as `TicketRefusal`.
/// [code] mirrors the machine-readable error codes asked for in POS-BE-019 so
/// the wizard can say *"this code was already used"* rather than *"invalid"*.
class ClaimResult {
  const ClaimResult({this.claim, this.code, this.message});

  final TerminalClaim? claim;
  final String? code;
  final String? message;

  bool get succeeded => claim != null;
}

/// How this terminal gets provisioned (POS-BE-023).
///
/// Two paths, both landing on the same `pos_terminals` row:
/// * [claimByCode] — the dashboard created the terminal and issued a pairing
///   code. This is the default, because the alternative puts a restaurant
///   admin's password into every till an installer touches.
/// * [registerManually] — no dashboard access at setup time, so the till
///   authenticates and creates its own record.
abstract interface class ProvisioningRepository {
  Future<ClaimResult> claimByCode({required String tenantSlug, required String code});

  Future<ClaimResult> registerManually({
    required String tenantSlug,
    required String username,
    required String password,
    required String terminalName,
    required int branchId,
  });
}

/// A branch the terminal can be assigned to during setup.
class PosBranch {
  const PosBranch({
    required this.id,
    required this.name,
    this.code,
    this.supportedOrderTypes = const [],
    this.isActive = true,
  });

  final int id;
  final String name;

  /// Wanted as the invoice prefix (POS-BE-008). Not yet serialised by the
  /// backend's `BranchResource` — POS-BE-005.
  final String? code;

  /// Which order types this branch actually offers. The till shows only these;
  /// it never hardcodes a set.
  final List<String> supportedOrderTypes;
  final bool isActive;
}

abstract interface class BranchRepository {
  Future<List<PosBranch>> forTenant();
}

/// A printer the terminal can see.
class DiscoveredPrinter {
  const DiscoveredPrinter({required this.name, required this.transport});

  final String name;

  /// `usb` | `network` | `spool` | `bluetooth`.
  final String transport;
}

/// Hardware discovery, behind a port so no business logic ever imports a
/// platform channel. A terminal with nothing attached is a valid terminal:
/// setup completes, the receipt queues, and the UI says so.
abstract interface class HardwarePorts {
  Future<List<DiscoveredPrinter>> discoverPrinters();

  /// Returns false when there is nothing to print to, rather than throwing —
  /// a failed test print must not abort setup.
  Future<bool> testPrint(String printerName);
}
