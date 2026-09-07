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
  });

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

  /// What has already gone back. Zero until Wave A's refunds land.
  final Money refundedTotal;

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
  });

  final OrderRecord order;
  final List<OrderRecordLine> lines;
  final List<OrderRecordPayment> payments;
  final List<OrderRecordDiscount> discounts;

  /// Lines that were actually charged for.
  Iterable<OrderRecordLine> get chargedLines =>
      lines.where((line) => !line.isVoided);

  /// Whether any part of this order can still be given back.
  bool get hasRefundableLines =>
      order.status.tookMoney &&
      lines.any((line) => line.refundableQuantity > 0);
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
    this.search,
    this.limit = 200,
  });

  /// Inclusive lower bound on `occurred_at`. Null means "as far back as there
  /// is".
  final DateTime? from;

  /// Exclusive upper bound.
  final DateTime? to;

  /// Empty means every status.
  final Set<OrderStatus> statuses;

  /// Empty means every type.
  final Set<OrderType> orderTypes;

  final int? servedByStaffId;

  /// Matches an invoice number or a table label. Cashiers type the last few
  /// digits off a receipt, so this matches anywhere in the number rather than
  /// only at the start.
  final String? search;

  /// A hard ceiling, always applied. Not a page size — a till that tried to
  /// hold a year of orders in memory would fail slowly and confusingly, and
  /// "narrow the dates" is a better answer than a spinner that never ends.
  final int limit;

  bool get isFiltered =>
      statuses.isNotEmpty ||
      orderTypes.isNotEmpty ||
      servedByStaffId != null ||
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
    String? search,
    int? limit,
  }) => OrderHistoryQuery(
    from: clearFrom ? null : (from ?? this.from),
    to: clearTo ? null : (to ?? this.to),
    statuses: statuses ?? this.statuses,
    orderTypes: orderTypes ?? this.orderTypes,
    servedByStaffId: clearServedBy
        ? null
        : (servedByStaffId ?? this.servedByStaffId),
    search: search ?? this.search,
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
      other.search == search &&
      other.limit == limit &&
      const SetEquality<OrderStatus>().equals(other.statuses, statuses) &&
      const SetEquality<OrderType>().equals(other.orderTypes, orderTypes);

  @override
  int get hashCode => Object.hash(
    from,
    to,
    servedByStaffId,
    search,
    limit,
    const SetEquality<OrderStatus>().hash(statuses),
    const SetEquality<OrderType>().hash(orderTypes),
  );

  /// Midnight-to-midnight in the terminal's own time zone.
  ///
  /// Local, not UTC: "today" at a till in Cairo means the day the people
  /// standing at it are having. A UTC day would roll over at 2 a.m. local and
  /// split a late shift's takings across two lists.
  ///
  /// It is **not** the business day (§92) — that arrives with Wave B, and once
  /// it does this becomes the fallback for a branch that has not configured
  /// one.
  static OrderHistoryQuery today({DateTime? now}) {
    final at = now ?? DateTime.now();
    final start = DateTime(at.year, at.month, at.day);
    return OrderHistoryQuery(
      from: start,
      to: start.add(const Duration(days: 1)),
    );
  }
}
