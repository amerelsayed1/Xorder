import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../models/catalog.dart';
import '../models/discount.dart';
import '../models/reason_code.dart';
import '../models/permissions.dart';
import '../models/dining_table.dart';
import '../models/order_record.dart';
import '../models/refund.dart';
import '../services/refund_engine.dart' show RefundQuote;
import '../models/shift.dart';
import '../models/ticket.dart';

export '../models/shift.dart'
    show PosStaff, PosShift, ShiftSummary, ShiftTenderTotal, ShiftClose;

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
  ///
  /// [servedBy] is who rang it up, taken at settlement rather than read from
  /// whoever the repository was built for. On a seated table the person who
  /// opened the ticket and the person who takes the payment are routinely two
  /// different people, and the sale belongs to the one who closed it. Null is
  /// permitted — a till selling before anybody has signed in still records the
  /// order, unattributed, rather than refusing it.
  Future<SubmitOrderResult> submit(Ticket ticket, {PosStaff? servedBy});

  /// How many settled sales this terminal still owes the platform.
  ///
  /// Zero in offline mode, always — sales are not owed to anyone there, and a
  /// number that only ever went up would be reporting a debt that does not
  /// exist. Read from the queue rather than counted in memory, so it survives a
  /// restart: a till that forgot its backlog when someone rebooted it would
  /// report "synced" while holding a day of unsent takings.
  Future<int> pendingSyncCount();

  /// Record an order that was made and then thrown away.
  ///
  /// **Only for a ticket the kitchen has already seen.** An unsent ticket that
  /// somebody clears is not a business event — nothing was made, nothing was
  /// wasted, and writing a row for it would fill the ledger with abandoned
  /// keystrokes. Once food has been fired, the opposite is true: the cost is
  /// real and a restaurant that cannot total it cannot manage it.
  ///
  /// The order is written with its **real totals** and `status = 'VOIDED'`, not
  /// zeroed. What was thrown away is the number a waste report exists to show,
  /// and a voided order recording nothing would erase it. It takes an invoice
  /// number for the same reason: a gap in the sequence is a question nobody can
  /// answer, and a voided entry is one anybody can.
  ///
  /// Idempotent on `ticket.id`, exactly as [submit] is.
  Future<SubmitOrderResult> voidOrder(
    Ticket ticket, {
    required PosStaff by,
    int? reasonId,
    String? note,
    PosStaff? approvedBy,
    PosStaff? servedBy,
  });
}

/// Reading back what was already sold.
///
/// Separate from [OrdersRepository] on purpose. That one writes, in a
/// transaction, against a terminal's own write context; this one only reads,
/// and it is the surface refunds, reprints and the void report will all be
/// built on. Keeping them apart means a screen that merely *looks* at history
/// cannot be handed something that can settle a sale.
abstract interface class OrderHistoryRepository {
  /// Newest first, capped at [OrderHistoryQuery.limit].
  Future<List<OrderRecord>> search(OrderHistoryQuery query);

  /// One order with its lines, payments and discounts.
  ///
  /// Null when the id names nothing — a row can be gone by the time somebody
  /// clicks it, and that is a "no longer there", not an exception.
  Future<OrderRecordDetail?> detail(int orderId);

  /// The single order carrying this invoice number, or null.
  ///
  /// Exact match. A refund is issued against *the* order on the receipt in
  /// somebody's hand, and "did you mean one of these four" is not a question to
  /// ask while money is being given back.
  Future<OrderRecord?> byInvoiceNumber(String invoiceNumber);
}

/// The outcome of issuing a refund.
class RefundResult {
  const RefundResult({
    required this.clientRefundId,
    required this.refundId,
    required this.replayed,
  });

  final String clientRefundId;
  final int refundId;

  /// This id had already been written, so nothing new happened and the original
  /// is what came back. A retry after a timeout must never hand money back
  /// twice.
  final bool replayed;
}

/// Money going back.
///
/// Deliberately not a method on [OrdersRepository]. A refund is its own record
/// with its own provenance, and the screens that read history must be able to
/// show refunds without holding anything that can issue one.
abstract interface class RefundsRepository {
  /// Write a refund, its lines and how the money went back — in one
  /// transaction, or not at all.
  ///
  /// The caller supplies a [RefundQuote] rather than raw figures. Every number
  /// written is one the operator was shown; nothing is recalculated between the
  /// confirmation and the row.
  ///
  /// Idempotent on [clientRefundId], exactly as an order is on its transaction
  /// id. Pass the same id to retry a call that timed out.
  Future<RefundResult> issue({
    required OrderRecord order,
    required RefundQuote quote,
    required PosStaff by,
    required List<RefundTender> tenders,
    required String clientRefundId,
    PosStaff? approvedBy,
    int? reasonId,
    String? note,
  });

  /// Every refund already issued against one order, oldest first.
  ///
  /// The engine needs these: the remainder rule works off what each previous
  /// refund gave back part by part, which `pos_orders.refunded_minor` alone
  /// cannot answer.
  Future<List<Refund>> forOrder(int orderId);
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

  /// Canonicalises the name being asked about, exactly as [PosStaff.can] does.
  ///
  /// A till running an older binary against a migrated database will ask about
  /// `pos.reprint` while the row now says `receipt.reprint`, and the honest
  /// answer to "may this person reprint" does not depend on which build is
  /// asking.
  bool can(String capability) =>
      capabilities.contains(PosCapability.canonical(capability));

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

/// The discounts a restaurant offers, and the ceiling a person may give away.
///
/// Read-only at the till. Authoring belongs to Settings (Wave D) — a cashier
/// applies a discount, they do not invent one.
abstract interface class DiscountsRepository {
  /// Everything configured, live or not. [Discount.isLiveAt] decides what is
  /// actually on offer, and it takes the time as an argument so a till cannot
  /// be tested only at the hour the test happens to run.
  Future<List<Discount>> all();

  /// What [staff] may take off by hand before a supervisor is needed.
  ///
  /// Comes from the role, until Wave C's `pos_permission_limits` can express it
  /// per person too. A person with no role, or a role with no ceiling
  /// configured, is [DiscountLimit.unlimited] — see that class for why the
  /// absent case must not read as zero.
  Future<DiscountLimit> limitFor(PosStaff? staff);
}

/// The reason lists a restaurant picks from.
abstract interface class ReasonsRepository {
  /// Active reasons for one act, in the restaurant's own order — which is the
  /// order the picker's number keys follow.
  Future<List<ReasonCode>> forScope(ReasonScope scope);
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

/// The result of verifying credentials and pulling the tenant's configuration
/// before anything is registered — the first half of the credentials path.
///
/// Refusals are data, same reasoning as [ClaimResult]: a mistyped password is
/// normal operation on a shop floor, not an exception.
class TenantConnection {
  const TenantConnection({
    this.tenantName,
    this.branches = const [],
    this.terminals = const [],
    this.code,
    this.message,
  });

  final String? tenantName;

  /// The tenant's branches, straight from the platform — what the branch step
  /// shows on a terminal whose local database has not been seeded yet.
  final List<PosBranch> branches;

  /// Terminals the platform ALREADY has for this tenant, unclaimed ones first.
  ///
  /// Empty is a normal answer, not a failure: a tenant is created with a
  /// licence and no terminals at all, so the first till to arrive legitimately
  /// finds nothing to adopt and creates one.
  final List<PosTerminalSummary> terminals;

  final String? code;
  final String? message;

  bool get succeeded => code == null;
}

/// A terminal the platform holds, as the setup wizard needs to show it.
class PosTerminalSummary {
  const PosTerminalSummary({
    required this.id,
    required this.name,
    required this.branchId,
    required this.state,
  });

  /// The platform's numeric row id — what the pairing-code call addresses.
  /// Deliberately not the `terminal_id` UUID: that identifies the till to
  /// itself, this identifies the row to the dashboard API.
  final int id;
  final String name;
  final int? branchId;

  /// `provisioned` | `active` | `revoked`.
  final String state;

  /// Waiting for a device. The only state a till may adopt: `active` already
  /// belongs to another machine and adopting it would silently steal the seat
  /// out from under a working till, and `revoked` is dead.
  bool get isAdoptable => state == 'provisioned';
}

/// How this terminal gets provisioned (POS-BE-023).
///
/// Two paths, both landing on the same `pos_terminals` row:
/// * [claimByCode] — the dashboard created the terminal and issued a pairing
///   code.
/// * [connect] then [registerManually] — the phase-1 cloud flow: slug + admin
///   credentials pull the tenant's configuration first, and registration
///   happens once the branch and till name have been chosen from it.
abstract interface class ProvisioningRepository {
  Future<ClaimResult> claimByCode({
    required String tenantSlug,
    required String code,
  });

  /// Verify the credentials and pull what the following setup steps display.
  /// Registers nothing and changes nothing on the platform.
  Future<TenantConnection> connect({
    required String tenantSlug,
    required String username,
    required String password,
  });

  Future<ClaimResult> registerManually({
    required String tenantSlug,
    required String username,
    required String password,
    required String terminalName,
    required int branchId,
  });

  /// Adopt a terminal the dashboard already created, rather than making
  /// another one beside it. The preferred path since tenant creation started
  /// leaving terminals provisioned and waiting: [registerManually] is now the
  /// fallback for a tenant that genuinely has none.
  Future<ClaimResult> adoptTerminal({
    required String tenantSlug,
    required String username,
    required String password,
    required int terminalId,
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
