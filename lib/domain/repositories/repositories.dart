import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import 'admin_repositories.dart';
import '../models/catalog.dart';
import '../models/order_type_config.dart';
import '../models/purchase_order.dart';
import '../services/stock_costing.dart';
import '../models/service_charge.dart';
import '../models/supplier.dart';
import '../models/supplier_invoice.dart';
import '../models/tender_method.dart';
import '../models/eta_submission.dart';
import '../services/eta_serialization.dart';
import '../models/discount.dart';
import '../models/reason_code.dart';
import '../models/permissions.dart';
import '../models/dining_table.dart';
import '../models/business_day.dart';
import '../models/order_record.dart';
import '../models/pos_settings.dart';
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

/// The queue of receipts owed to Egypt's tax authority.
///
/// Deliberately not the platform outbox. They look alike and are not: the
/// outbox carries whatever the platform wants, in whatever order, and a failed
/// row can be retried forever. This one carries documents in a **chain**, each
/// naming the uuid of the one before it from the same device, and has a legal
/// deadline attached. One drain deciding retry policy for both would get one
/// of them wrong, and the wrong answer here is a receipt filed late.
abstract interface class EtaQueueRepository {
  /// Builds a receipt against the current chain head and queues it, in one
  /// transaction.
  ///
  /// The document is built by the caller's [build] because only the caller
  /// knows the order — but it is built *here*, inside the lock, because the
  /// predecessor it names has to be the one this receipt is actually written
  /// after. Handing back a head and trusting the caller to use it would be the
  /// race with extra steps.
  Future<EtaEnqueued> enqueue({
    required int orderId,
    required String deviceSerial,
    required String receiptNumber,
    required String receiptType,
    required DateTime issuedAt,
    required EtaObject Function(String previousUuid) build,
    int? refundId,
  });

  /// Everything not yet filed, oldest first.
  Future<List<EtaSubmission>> outstanding({int limit = 200});

  /// The queue at a glance, against the caller's clock.
  Future<EtaQueueSummary> summary({required DateTime now});

  /// The exact text that was hashed, for signing. Null if the row is gone.
  Future<String?> canonicalFor(int id);

  Future<void> markSigned(int id, String signature);

  Future<void> markAccepted(
    int id, {
    required String submissionUuid,
    String? longId,
  });

  /// The authority looked at it and refused. Needs a person.
  Future<void> markRejected(int id, String message);

  /// A try that did not reach a verdict — a dropped line, a timeout. The
  /// status is deliberately untouched: a network failure is not a rejection,
  /// and putting a person in front of a problem no person can fix is how a
  /// queue stops being read.
  Future<void> markAttempted(int id, String message);
}

/// What [EtaQueueRepository.enqueue] wrote.
class EtaEnqueued {
  const EtaEnqueued({
    required this.id,
    required this.uuid,
    required this.previousUuid,
    required this.document,
  });

  final int id;
  final String uuid;
  final String previousUuid;
  final EtaObject document;
}

/// The payment methods this restaurant takes (§40).
///
/// A repository rather than a constant since Wave D. Two lists of tender types
/// is how a till ends up refunding to a method it cannot take payment on, so
/// settlement and refunds both read this one.
abstract interface class TenderTypesRepository {
  /// Active methods, in the order the restaurant put them in.
  ///
  /// [includeInactive] is for the editor, which has to show a retired method to
  /// let somebody bring it back — and for a receipt reprint, where the method a
  /// sale was taken on may since have been retired.
  Future<List<TenderMethod>> all({bool includeInactive = false});
}

/// What the restaurant adds on top of the food (§38).
///
/// Read on every sale — the ticket has to be priced — and written only from
/// Management, which is why the reads and the writes go to different
/// credentials in the implementation.
abstract interface class ServiceChargesRepository {
  Future<List<ServiceCharge>> all({bool includeInactive = false});

  /// `id == 0` creates. No delete: a charge is retired with `isActive`, because
  /// an order priced with it has its total snapshotted and somebody will ask
  /// what the twelve percent on last month's bill was.
  Future<AdminResult<ServiceCharge>> save(
    ServiceCharge charge, {
    required PosStaff by,
  });
}

/// What each kind of order requires (§31).
abstract interface class OrderTypesRepository {
  Future<List<OrderTypeConfig>> all({bool includeInactive = false});
}

/// Who the restaurant buys from.
///
/// Back office only, on the administrator credential: a till does not buy
/// anything, and giving the counter SELECT on who the restaurant owes money to
/// would hand out its commercial position for no operational benefit.
abstract interface class SuppliersRepository {
  Future<List<Supplier>> all({bool includeInactive = false});

  /// `id == 0` creates. No delete: a supplier is retired with `isActive`,
  /// because their invoices name them and a purchase history that cannot say
  /// who supplied something is not a purchase history.
  Future<AdminResult<Supplier>> save(Supplier supplier, {required PosStaff by});
}

/// What the restaurant has asked its suppliers for.
abstract interface class PurchaseOrdersRepository {
  /// Everything still owed — sent, or part-delivered.
  Future<List<PurchaseOrder>> open();

  Future<List<PurchaseOrder>> all({int limit = 100});

  Future<PurchaseOrder?> byId(int id);

  /// Writes a draft, lines and all. `id == 0` creates and claims a reference.
  ///
  /// Refuses once the order has been sent: the supplier is holding a copy, and
  /// changing what it says here would leave the two of them with different
  /// pieces of paper.
  Future<AdminResult<PurchaseOrder>> saveDraft(
    PurchaseOrder order, {
    required PosStaff by,
  });

  /// Move it on — sent, cancelled, or the status the receipts imply.
  Future<AdminResult<PurchaseOrder>> setStatus(
    int orderId, {
    required PurchaseStatus status,
    required PosStaff by,
    DateTime? orderedAt,
  });
}

/// Booking goods in against a purchase order.
abstract interface class ReceivingRepository {
  /// Records what arrived, by purchase-order line.
  ///
  /// Everything happens together: the line's received quantity, a movement in
  /// the ledger, the new position, and the order's status — which is *derived*
  /// from the lines rather than passed in, so a receipt cannot leave an order
  /// saying something its own lines contradict.
  Future<AdminResult<void>> receive({
    required int purchaseOrderId,
    required Map<int, Quantity> byLine,
    required PosStaff by,
    DateTime? at,
    String? note,
  });

  /// What is on hand and what it cost, or null for a product never stocked.
  Future<StockPosition?> positionFor(int productId);
}

/// What the restaurant owes its suppliers, and what it has paid them (§37).
///
/// Back office only, like the rest of purchasing. **The reads return invoices
/// with `paid` already filled in**, because every question worth asking of this
/// table is about the unpaid part and a screen that had to make a second call
/// per row would either make it or quietly stop asking.
abstract interface class SupplierInvoicesRepository {
  /// Everything with money still on it, oldest due date first — which is the
  /// order somebody pays in.
  Future<List<SupplierInvoice>> unpaid({int? supplierId});

  Future<List<SupplierInvoice>> all({int? supplierId, int limit = 200});

  Future<SupplierInvoice?> byId(int id);

  /// `id == 0` creates. Refuses a number this supplier already has on a live
  /// invoice — entering the same one twice is the commonest error in purchase
  /// bookkeeping, and the database refuses it too.
  Future<AdminResult<SupplierInvoice>> save(
    SupplierInvoice invoice, {
    required PosStaff by,
  });

  /// Cancels it, keeping the row. Refused while payments are allocated to it:
  /// the money would be pointing at a bill that no longer exists.
  ///
  /// [reasonId] is one of the restaurant's `ReasonScope.invoiceVoid` codes, so
  /// that "how many were cancelled for *entered twice*" is answerable.
  Future<AdminResult<SupplierInvoice>> voidInvoice(
    int id, {
    required int reasonId,
    required PosStaff by,
    String? note,
  });

  /// Money out. `invoiceId` null pays **on account** — against the running tab
  /// rather than a particular bill.
  ///
  /// [fromShiftId] takes the cash out of that shift's drawer: a `pay_out`
  /// movement is written in the **same transaction** as the payment and linked
  /// from [SupplierPayment.cashMovementId], so the shift's expected cash falls
  /// by the amount. A payment with a dangling drawer movement, or a drawer
  /// movement with no payment behind it, are both worse than the shortage this
  /// exists to prevent — which is why it is one transaction and not two calls.
  ///
  /// Cash only, and it needs `cash.movement` on top of `purchase.manage`.
  Future<AdminResult<SupplierPayment>> pay(
    SupplierPayment payment, {
    required PosStaff by,
    int? fromShiftId,
  });

  /// Reverses a payment, keeping the row, and frees the room it took on the
  /// invoice it was allocated to.
  ///
  /// A payment that came out of a drawer is put back with a **compensating
  /// `pay_in`** on the same shift, while that shift is still open. Once it has
  /// been counted, the void is refused unless [note] says where the cash went —
  /// the drawer has already been reconciled and only a person knows. See the
  /// implementation for the reasoning and what was rejected.
  Future<AdminResult<SupplierPayment>> voidPayment(
    int id, {
    required int reasonId,
    required PosStaff by,
    String? note,
  });

  Future<List<SupplierPayment>> payments({int? supplierId, int limit = 200});

  /// The whole account for one supplier, as at [asOf] — every live invoice and
  /// every live payment, so the balance, the overdue part and the unallocated
  /// money are all one subtraction away.
  Future<SupplierAccount> accountFor(int supplierId, {DateTime? asOf});

  /// What every supplier is owed. One query rather than one per supplier: the
  /// purchasing pane shows them as a list.
  Future<List<SupplierBalance>> balances({DateTime? asOf});
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

  /// The tills at this branch, for the terminal filter.
  Future<List<HistoryTerminal>> terminals();
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

/// What the restaurant has configured.
///
/// Read as a whole and resolved once — restaurant, then branch, then terminal,
/// most specific winning. A per-key read would be a query per question, and the
/// questions are asked on every screen.
abstract interface class SettingsRepository {
  Future<PosSettings> load();

  /// Write one value at one scope.
  ///
  /// Upserts on (restaurant, scope, scope id, key), which is the database's own
  /// uniqueness constraint — so saving the same key twice is a change, not a
  /// second row.
  Future<void> save({
    required String key,
    required String value,
    required SettingScope scope,
    required PosStaff by,
    String scopeId = '',
  });
}

/// The trading day.
abstract interface class BusinessDayRepository {
  /// The open day for this branch, or null when nobody has started one.
  Future<BusinessDay?> current();

  /// Open the day [date] belongs to, or return the one already open.
  ///
  /// Idempotent by necessity rather than by choice: the database allows one
  /// open day per branch, so two tills starting the morning together must not
  /// race into a refusal a cashier has to read.
  Future<BusinessDay> open({required DateTime date, required PosStaff by});

  /// What is standing in the way of closing.
  Future<DayCloseCheck> check();

  /// Close it. [force] is required when [DayCloseCheck.blockers] is not empty,
  /// and carries the reason the database insists on.
  Future<BusinessDay> close({
    required BusinessDay day,
    required PosStaff by,
    bool force = false,
    String? forceReason,
  });
}

/// Money into and out of the drawer that is not a sale.
abstract interface class CashMovementsRepository {
  /// Record one. The amount is always positive — see [CashMovementKind].
  Future<CashMovement> record({
    required CashMovementKind kind,
    required Money amount,
    required PosStaff by,
    required int shiftId,
    int? reasonId,
    String? note,
    PosStaff? approvedBy,
    int? businessDayId,
  });

  /// Everything that happened to one shift's drawer, oldest first.
  Future<List<CashMovement>> forShift(int shiftId);
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

  /// Identify somebody by NAME and PIN, for the act of becoming the operator.
  ///
  /// Separate from [signIn] because the two acts carry different weight. A PIN
  /// alone is enough to approve a discount somebody is standing over, and it is
  /// not enough to take over a till: four digits are shared, watched over a
  /// shoulder and reused, and [signIn] hands the session to whichever active
  /// member of staff happens to hold them. Saying the name first makes the till
  /// check a claim rather than guess an identity.
  ///
  /// Returns null when no active member of staff has that username AND that
  /// PIN. Deliberately one answer for both, so this cannot be used to find out
  /// which usernames exist.
  Future<PosStaff?> signInAs({required String username, required String pin});
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

  /// Send a prepared job to a printer. False when the printer did not answer.
  ///
  /// **Bytes, not a receipt.** The obvious signature is
  /// `printReceipt(ReceiptData)`, and it was rejected twice over: it would put
  /// a `features/` type into a hardware port, and it would render inside the
  /// port, where the drawer kick would have to be a second call and therefore a
  /// second connection. A drawer that opens on a receipt which failed to print
  /// is a drawer that opens for nothing. So the receipt path builds one job —
  /// picture, feed, kick, cut — and this sends it, once.
  ///
  /// False rather than throwing, like everything else here: a printer that is
  /// off is an ordinary Tuesday, and the sale is already complete.
  Future<bool> sendJob({required String printerName, required List<int> bytes});
}

/// A receipt the printer would not take.
class QueuedPrintJob {
  const QueuedPrintJob({
    required this.id,
    required this.printerName,
    required this.bytes,
    required this.attempts,
    this.invoiceNumber,
  });

  final int id;
  final String printerName;

  /// The complete ESC/POS job, as it was built at settlement. Sent verbatim.
  final List<int> bytes;

  /// How many times this has been tried. Shown to nobody yet; it is the number
  /// a support engineer asks for first when a restaurant says the printer keeps
  /// stopping.
  final int attempts;

  final String? invoiceNumber;
}

/// Receipts owed to paper.
///
/// **The toast promised this before it existed.** *Print & new* has shown
/// "Receipt queued for the default printer" since the dialog was written, and
/// nothing was queued and nothing was printed — the customer found out, not the
/// cashier. This is the queue that makes the sentence true.
///
/// Not the outbox and not the ETA queue, though all three retry: those two are
/// about a *record* reaching a server and are ordered by a chain. This is about
/// a physical device at one counter, so it is keyed by terminal and its only
/// ordering rule is that paper comes out in the order the sales happened.
abstract interface class PrintQueueRepository {
  /// Returns the id of the queued job.
  Future<int> enqueue({
    required String printerName,
    required List<int> bytes,
    required bool isReprint,
    int? orderId,
    String? invoiceNumber,
  });

  /// This terminal's outstanding paper, oldest first.
  ///
  /// [limit] is a real limit, not paging: a till that has been off all night
  /// must not spool forty receipts at the counter while a customer waits. It
  /// catches up a few at a time over the next few sales.
  Future<List<QueuedPrintJob>> pending({int limit = 5});

  /// It is on paper. A job marked printed is never offered again — the database
  /// refuses to un-print it, see migration 34.
  Future<void> markPrinted(int id);

  /// It failed again. Counts the attempt and keeps the job.
  Future<void> markAttempted(int id, {String? error});
}
