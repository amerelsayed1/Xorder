/// An order as it exists **after** it was rung up — read from the ledger, not
/// built in a cart.
///
/// This is deliberately not a [Ticket]. A ticket is a thing being assembled: it
/// holds a live tax configuration, it recalculates, and every number on it is
/// derived from the catalogue as it stands right now. A recorded order is the
/// opposite — every number on it was decided once, written down, and must never
/// move again because the menu price changed afterwards. Reusing `Ticket` here
/// would put a `totals` getter on history that recomputes what a customer
/// already paid, which is the one thing history exists to prevent.
///
/// So the totals below are **read**, never computed. There is no `totals`
/// getter on [OrderRecord] and that absence is the point.
library;

import 'package:collection/collection.dart';

import '../../core/money/money.dart';
import '../services/payment_status.dart';
import 'ticket.dart' show OrderType;

/// Where an order stands.
///
/// **These strings are data** — they are the `status` column's CHECK constraint
/// in migration 9, so a member added here without being added there writes a
/// row the database refuses.
enum OrderStatus {
  /// Being typed. Nothing is committed and the kitchen has seen nothing.
  draft('DRAFT'),

  /// Committed, unpaid, nothing fired yet.
  open('OPEN'),

  /// The kitchen has it.
  sentToKitchen('SENT_TO_KITCHEN'),

  /// The kitchen is finished with it.
  ready('READY'),

  /// Paid for. Everything the till has written until now is this.
  paid('PAID'),

  /// Paid and finished with — the table is cleared, the day may close.
  closed('CLOSED'),

  /// Thrown away after the kitchen saw it. The money was never taken and the
  /// food was made, which is why the row keeps its real totals.
  voided('VOIDED'),

  /// Abandoned before the kitchen saw it.
  cancelled('CANCELLED'),

  refunded('REFUNDED'),
  partiallyRefunded('PARTIALLY_REFUNDED');

  const OrderStatus(this.wire);

  /// What is stored.
  final String wire;

  static OrderStatus? fromWire(String value) {
    for (final status in OrderStatus.values) {
      if (status.wire == value) return status;
    }
    return null;
  }

  /// Money changed hands and has not been fully given back.
  ///
  /// The set a Z report totals, and the set a refund may be issued against.
  bool get tookMoney => switch (this) {
    OrderStatus.paid ||
    OrderStatus.closed ||
    OrderStatus.partiallyRefunded => true,
    _ => false,
  };

  /// Nothing is owed and nothing was taken — the order exists as a record of
  /// something that did not become a sale.
  bool get isDead => switch (this) {
    OrderStatus.voided || OrderStatus.cancelled || OrderStatus.refunded => true,
    _ => false,
  };
}

/// One line as it was sold.
///
/// `name` is the snapshot written at sale time, not a lookup: a dish renamed in
/// March must not rewrite what a receipt said in January.
class OrderRecordLine {
  const OrderRecordLine({
    required this.id,
    required this.lineKey,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.modifierSummary,
    this.note,
    this.menuItemId,
    this.refundedQuantity = 0,
    this.voidedAt,
    this.voidedByName,
  });

  /// `pos_order_lines.id`. A refund references this row, so it is carried even
  /// though nothing on screen shows it.
  final int id;
  final String lineKey;
  final String name;
  final int quantity;
  final Money unitPrice;
  final Money lineTotal;
  final String? modifierSummary;
  final String? note;
  final int? menuItemId;

  /// How much of this line has already gone back. Maintained by the refund
  /// tables (migration 12), read here so a second refund can be offered only
  /// the part that is left.
  final int refundedQuantity;

  /// Set when the line was voided while the order was still open. The line
  /// stays on the record — a voided line that vanished would leave a kitchen
  /// docket referring to food nobody can account for.
  final DateTime? voidedAt;
  final String? voidedByName;

  bool get isVoided => voidedAt != null;

  /// What may still be given back.
  int get refundableQuantity =>
      isVoided ? 0 : (quantity - refundedQuantity).clamp(0, quantity);
}

/// How money arrived.
class OrderRecordPayment {
  const OrderRecordPayment({
    required this.label,
    required this.amount,
    this.tenderTypeId,
    this.reference,
    this.occurredAt,
  });

  final String label;
  final Money amount;
  final int? tenderTypeId;
  final String? reference;
  final DateTime? occurredAt;
}

/// A discount as it was given — the snapshot, never the configuration.
class OrderRecordDiscount {
  const OrderRecordDiscount({
    required this.name,
    required this.amount,
    this.lineKey,
    this.appliedByName,
    this.approvedByName,
    this.appliedAt,
  });

  final String name;
  final Money amount;

  /// Null for an order-level discount.
  final String? lineKey;
  final String? appliedByName;

  /// Set only when somebody had to authorise it. That it is usually null is
  /// what makes the times it is not worth reading.
  final String? approvedByName;
  final DateTime? appliedAt;
}

/// A method a sale was paid in, as its row in the list names it.
///
/// Not an [OrderRecordPayment]: that is one row of money with its amount,
/// read when a sale is opened. This is once per method however many payments
/// were taken in it, and carries no amount — a column that summed them would
/// be a second, smaller copy of the detail pane, and the first to disagree
/// with it.
class OrderRecordTender {
  const OrderRecordTender({required this.tenderTypeId, required this.label});

  /// Kept beside the label so the name is translated the way every other
  /// tender name is — by `tenderName`, which honours a renamed method.
  final int tenderTypeId;

  /// The label written on the payment when it was taken.
  final String label;
}

/// One row in the history list.
///
/// Everything a person scanning for an order needs, and nothing more. The lines
/// and payments are a second query, made when a row is opened — a hundred rows
/// each dragging their lines along is how a list becomes slow at exactly the
/// moment somebody is in a hurry.
class OrderRecord {
  const OrderRecord({
    required this.id,
    required this.clientTransactionId,
    required this.invoiceNumber,
    required this.status,
    required this.orderType,
    required this.occurredAt,
    required this.subtotal,
    required this.discount,
    required this.service,
    required this.vat,
    required this.total,
    this.tableLabel,
    this.guestCount,
    this.servedByStaffId,
    this.servedByName,
    this.voidedAt,
    this.voidedByName,
    this.voidReason,
    this.voidReasonAr,
    this.voidNote,
    this.refundedTotal = Money.zero,
    this.paidTotal = Money.zero,
    this._paymentStatus,
    this.businessDate,
    this.terminalId,
    this.terminalName,
    this.tenders = const [],
  });

  /// The day `served_by` became trustworthy.
  ///
  /// Before the username sign-in fix, a PIN shared by two people signed in as
  /// whichever of them had the lowest staff id, and every sale they rang up
  /// was credited to that one person. Those rows cannot be repaired — nobody
  /// knows who was really at the till — so the screens say so rather than
  /// presenting a per-cashier figure that is wrong in a way that looks right.
  static final servedByReliableFrom = DateTime(2026, 9, 10);

  final int id;
  final String clientTransactionId;
  final String invoiceNumber;
  final OrderStatus status;
  final OrderType orderType;
  final DateTime occurredAt;

  final Money subtotal;
  final Money discount;
  final Money service;
  final Money vat;
  final Money total;

  final String? tableLabel;
  final int? guestCount;

  /// Null on every order written before migration 11. Shown as a blank rather
  /// than as a guess.
  final int? servedByStaffId;
  final String? servedByName;

  final DateTime? voidedAt;
  final String? voidedByName;
  /// The reason as configured, in both languages. Carried as text rather than
  /// as an id because a reason renamed next year must not rewrite what this
  /// void said when it happened.
  final String? voidReason;
  final String? voidReasonAr;
  final String? voidNote;

  /// What has already gone back — the sum of this sale's `pos_refunds` rows.
  final Money refundedTotal;

  /// What was taken — the sum of this sale's `pos_order_payments` rows, which
  /// record the amount applied, never the amount tendered.
  final Money paidTotal;

  final PaymentStatus? _paymentStatus;

  /// Where the money stands, beside [status] which says where the order does.
  ///
  /// The database's answer when this record was read from it; the same rule
  /// applied to [paidTotal] and [refundedTotal] otherwise. Both routes are one
  /// rule — see `payment_status.dart` — so a record built by hand cannot show a
  /// status the ledger would not.
  PaymentStatus get paymentStatus =>
      _paymentStatus ??
      paymentStatusFromSums(
        totalMinor: total.minor,
        paidMinor: paidTotal.minor,
        refundedMinor: refundedTotal.minor,
      );

  /// The trading day this sale belongs to — midnight, local. Null when no
  /// business day covers it, and the list then files it by its calendar date.
  final DateTime? businessDate;

  /// The till that rang it up, and what that till is called. The name is null
  /// for a terminal whose row is gone; the sale still appears.
  final String? terminalId;
  final String? terminalName;

  /// Every method this sale was paid in, once each, in the order first taken
  /// — a split bill lists both. Empty for a sale that took no money.
  final List<OrderRecordTender> tenders;

  /// What is still with the restaurant.
  Money get netTotal => Money(
    total.minor - refundedTotal.minor,
    currency: total.currency,
    exponent: total.exponent,
  );

  bool get isVoided => status == OrderStatus.voided;
  bool get isSeated => tableLabel != null;
}

/// A row plus everything hanging off it.
class OrderRecordDetail {
  const OrderRecordDetail({
    required this.order,
    required this.lines,
    required this.payments,
    required this.discounts,
    this.events = const [],
  });

  final OrderRecord order;
  final List<OrderRecordLine> lines;
  final List<OrderRecordPayment> payments;
  final List<OrderRecordDiscount> discounts;

  /// What happened to this sale after it was rung up, oldest first.
  final List<SaleEvent> events;

  /// Lines that were actually charged for.
  Iterable<OrderRecordLine> get chargedLines =>
      lines.where((line) => !line.isVoided);

  /// Whether any part of this order can still be given back.
  bool get hasRefundableLines =>
      order.status.tookMoney &&
      lines.any((line) => line.refundableQuantity > 0);
}

/// What kind of thing happened to a sale.
///
/// An enum rather than the wire strings of the tables it is read from, so the
/// label switch is exhaustive and a new kind cannot fall through to a blank
/// row. [audit] is the one open-ended member: an audit row this build has no
/// kind for is still shown, under the Activity pane's own label for it.
enum SaleEventKind {
  /// The receipt came out of the printer.
  printed,

  /// The receipt is queued and has not printed yet. Not a failure — the queue
  /// retries — but a customer holding no receipt is the question it answers.
  printPending,

  /// A copy came out of the printer.
  reprinted,

  /// A copy is queued and has not printed yet.
  reprintPending,

  /// Somebody asked for a copy. Separate from [reprinted] because the person
  /// is on the audit row and the paper is on the print job — a copy asked for
  /// and never printed is exactly the pair that shows it.
  reprintRequested,

  voided,
  refunded,

  /// Any other audit row against this order — an approval lent, for one.
  audit,
}

/// One line in a sale's activity.
///
/// Assembled from four tables — print jobs, audit rows, the order's own void
/// columns and its refunds — because none of them alone is the history. Each
/// keeps its own table's truth: the print queue knows whether paper came out,
/// the audit log knows who asked.
class SaleEvent {
  const SaleEvent({
    required this.kind,
    required this.at,
    this.actorName,
    this.approvedByName,
    this.auditAction,
    this.amount,
  });

  final SaleEventKind kind;
  final DateTime at;
  final String? actorName;
  final String? approvedByName;

  /// The audit row's action, for [SaleEventKind.audit] only.
  final String? auditAction;

  /// Set for a refund: how much went back.
  final Money? amount;
}

/// A till that has sold at this branch, for the terminal filter.
class HistoryTerminal {
  const HistoryTerminal({required this.id, this.name});

  /// `pos_terminals.id`, as text — the column is a uuid and nothing here does
  /// arithmetic on it.
  final String id;
  final String? name;
}

/// Which slice of history to read.
///
/// A till holds every sale the branch ever made. The default is *today*, not
/// everything, because the question a cashier actually has at the counter is
/// about an order from the last few hours — and a list that opens on nine
/// months of trading answers it slowest.
class OrderHistoryQuery {
  const OrderHistoryQuery({
    this.from,
    this.to,
    this.statuses = const {},
    this.orderTypes = const {},
    this.servedByStaffId,
    this.tenderTypeId,
    this.terminalId,
    this.search,
    this.afterOrderId,
    this.limit = pageSize,
  });

  /// Rows per page (BO-3).
  ///
  /// Fixed, with no picker, as on the cloud (`OrdersView.vue`). Fifty rather
  /// than the two hundred this used to cap at: the cap was there because a
  /// list with no pager had to hold everything it showed, and a page is only
  /// what somebody reads before they narrow the filter or press Next.
  static const pageSize = 50;

  /// Inclusive lower bound, as a **business date** — local midnight of the
  /// trading day. Null means "as far back as there is".
  ///
  /// A sale belongs to the business day that was open when it was rung up, not
  /// to the calendar date on its timestamp: a restaurant trading until 2 a.m.
  /// sees one night as one date (plan 17 §0 rule 5). A sale no business day
  /// covers — a branch that never opens one — is filed by its local calendar
  /// date instead, which is what this filter meant before and is still the
  /// honest answer when there is no trading day to ask.
  final DateTime? from;

  /// Exclusive upper bound, the same kind of date as [from].
  final DateTime? to;

  /// Empty means every status.
  final Set<OrderStatus> statuses;

  /// Empty means every type.
  final Set<OrderType> orderTypes;

  final int? servedByStaffId;

  /// Sales with at least one payment in this tender. A split bill matches
  /// every method it was paid in — "show me the card sales" includes the one
  /// that was half card.
  final int? tenderTypeId;

  /// `pos_terminals.id` as text.
  final String? terminalId;

  /// Matches an invoice number or a table label. Cashiers type the last few
  /// digits off a receipt, so this matches anywhere in the number rather than
  /// only at the start.
  final String? search;

  /// The page begins after this order: the id of the last row of the page
  /// before. Null is the first page.
  ///
  /// **Keyset, not an offset.** `OFFSET 100` counts rows at the moment it is
  /// asked, so a sale rung up while somebody reads page two pushes a row from
  /// page two onto page three, where they see it again — and one voided off
  /// the top hides one they never saw. A position named by a row cannot move.
  ///
  /// An id rather than an (instant, id) pair, and the repository looks the
  /// instant up. A timestamp carried out to Dart and back is only as exact as
  /// every conversion on the way; the row it came from is exact by definition.
  ///
  /// Narrows `search` only. `summarise` ignores it, and [limit], because a
  /// total is over every page.
  final int? afterOrderId;

  /// Rows per page, always applied — a till that tried to hold a year of
  /// orders in memory would fail slowly and confusingly.
  final int limit;

  /// The same filter from its first page: what the summary is keyed by, so
  /// turning a page is not a fresh read of the totals.
  OrderHistoryQuery get unpaged => afterOrderId == null && limit == pageSize
      ? this
      : copyWith(clearAfter: true, limit: pageSize);

  bool get isFiltered =>
      statuses.isNotEmpty ||
      orderTypes.isNotEmpty ||
      servedByStaffId != null ||
      tenderTypeId != null ||
      terminalId != null ||
      (search != null && search!.trim().isNotEmpty);

  OrderHistoryQuery copyWith({
    DateTime? from,
    DateTime? to,
    bool clearFrom = false,
    bool clearTo = false,
    Set<OrderStatus>? statuses,
    Set<OrderType>? orderTypes,
    int? servedByStaffId,
    bool clearServedBy = false,
    int? tenderTypeId,
    bool clearTenderType = false,
    String? terminalId,
    bool clearTerminal = false,
    String? search,
    int? afterOrderId,
    bool clearAfter = false,
    int? limit,
  }) => OrderHistoryQuery(
    from: clearFrom ? null : (from ?? this.from),
    to: clearTo ? null : (to ?? this.to),
    statuses: statuses ?? this.statuses,
    orderTypes: orderTypes ?? this.orderTypes,
    servedByStaffId: clearServedBy
        ? null
        : (servedByStaffId ?? this.servedByStaffId),
    tenderTypeId: clearTenderType ? null : (tenderTypeId ?? this.tenderTypeId),
    terminalId: clearTerminal ? null : (terminalId ?? this.terminalId),
    search: search ?? this.search,
    afterOrderId: clearAfter ? null : (afterOrderId ?? this.afterOrderId),
    limit: limit ?? this.limit,
  );

  /// Value equality, and it is load-bearing rather than a nicety.
  ///
  /// This is the key of a `FutureProvider.family`, and the screen builds a
  /// fresh query object on every rebuild. Without this, each rebuild is a new
  /// family entry — a new read against a table holding every sale the branch
  /// ever made, whose arrival rebuilds the screen, which asks again. The first
  /// widget test written against the screen hung on exactly that loop.
  ///
  /// The sets need deep equality for the same reason: `{OrderStatus.voided}`
  /// built twice is two objects, and identity would make a filter that has not
  /// changed look like one that has.
  @override
  bool operator ==(Object other) =>
      other is OrderHistoryQuery &&
      other.from == from &&
      other.to == to &&
      other.servedByStaffId == servedByStaffId &&
      other.tenderTypeId == tenderTypeId &&
      other.terminalId == terminalId &&
      other.search == search &&
      other.afterOrderId == afterOrderId &&
      other.limit == limit &&
      const SetEquality<OrderStatus>().equals(other.statuses, statuses) &&
      const SetEquality<OrderType>().equals(other.orderTypes, orderTypes);

  @override
  int get hashCode => Object.hash(
    from,
    to,
    servedByStaffId,
    tenderTypeId,
    terminalId,
    search,
    afterOrderId,
    limit,
    const SetEquality<OrderStatus>().hash(statuses),
    const SetEquality<OrderType>().hash(orderTypes),
  );

  /// Today's calendar date, from midnight to midnight in the terminal's own
  /// time zone.
  ///
  /// Local, not UTC: "today" at a till in Cairo means the day the people
  /// standing at it are having. The history screen anchors on the open
  /// business day instead when there is one; this is the answer for a caller
  /// that has no business day to hand.
  static OrderHistoryQuery today({DateTime? now}) {
    final at = now ?? DateTime.now();
    final start = DateTime(at.year, at.month, at.day);
    return OrderHistoryQuery(
      from: start,
      to: start.add(const Duration(days: 1)),
    );
  }
}

/// The four figures over the sales list (BO-3): what the listed sales came
/// to, how many invoices there are, what was taken and what is still owed.
///
/// **Over exactly the rows the list pages through**, never a figure of its
/// own. `summarise` runs `search`'s WHERE, and [of] is the rule that turns
/// those rows into four numbers. `PostgresOrderHistoryRepository.summarise`
/// is its SQL twin, and `test/data/order_history_paging_test.dart` holds the
/// two to one answer for every combination of filters: the Dart rule applied
/// to every page of `search` must equal what the database summed.
class OrderHistorySummary {
  const OrderHistorySummary({
    required this.count,
    required this.dead,
    required this.total,
    required this.paid,
    required this.outstanding,
  });

  /// What a viewer who may read nothing is told, and what a terminal with no
  /// database answers.
  static const empty = OrderHistorySummary(
    count: 0,
    dead: 0,
    total: Money(0),
    paid: Money(0),
    outstanding: Money(0),
  );

  /// Every row the list holds, struck-through ones included, because they
  /// are rows somebody pages past. It is the pager's "of".
  final int count;

  /// How many of [count] are struck through on the list — voided, cancelled
  /// or refunded in full ([OrderStatus.isDead]).
  final int dead;

  /// The listed sales' totals, **except** the struck-through ones. The list
  /// draws a dead row's total with a line through it because it is not
  /// money, and a figure above that list which added it back would disagree
  /// with the rows under it. A part refund stays in at its full total, as its
  /// row does: what went back is on the sale, not taken off the bill.
  final Money total;

  /// What was taken against the live sales, before refunds — the payment
  /// rows, which record what was applied to the bill and never what was
  /// tendered.
  final Money paid;

  /// Total less taken, over the live sales whose money is unpaid or part paid
  /// (plan 19 §2.2). Live sales only: a void is UNPAID too, and a void is not
  /// money anybody owes.
  final Money outstanding;

  /// The rule, over rows already read.
  ///
  /// In the rows' own currency. One branch trades in one, and summing two
  /// would be meaningless whichever label the answer carried.
  static OrderHistorySummary of(Iterable<OrderRecord> rows) {
    var count = 0;
    var dead = 0;
    var total = 0;
    var paid = 0;
    var outstanding = 0;
    Money? unit;
    for (final row in rows) {
      unit ??= row.total;
      count++;
      if (row.status.isDead) {
        dead++;
        continue;
      }
      total += row.total.minor;
      paid += row.paidTotal.minor;
      // Over the enum, so a sixth payment status is a compile error here
      // rather than a sale that silently stops being owed.
      outstanding += switch (row.paymentStatus) {
        PaymentStatus.unpaid ||
        PaymentStatus.partiallyPaid => row.total.minor - row.paidTotal.minor,
        PaymentStatus.paid ||
        PaymentStatus.partiallyRefunded ||
        PaymentStatus.refunded => 0,
      };
    }
    Money money(int minor) => unit == null
        ? Money(minor)
        : Money(minor, currency: unit.currency, exponent: unit.exponent);
    return OrderHistorySummary(
      count: count,
      dead: dead,
      total: money(total),
      paid: money(paid),
      outstanding: money(outstanding),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OrderHistorySummary &&
      other.count == count &&
      other.dead == dead &&
      other.total == total &&
      other.paid == paid &&
      other.outstanding == outstanding;

  @override
  int get hashCode => Object.hash(count, dead, total, paid, outstanding);

  /// Minor units, for a failing test's message.
  @override
  String toString() =>
      'OrderHistorySummary(count: $count, dead: $dead, '
      'total: ${total.minor}, paid: ${paid.minor}, '
      'outstanding: ${outstanding.minor})';
}
