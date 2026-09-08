/// What the restaurant has asked a supplier for, and what has arrived.
///
/// **A purchase order is a sale read backwards**, and the same discipline
/// applies: the totals are snapshotted when it is sent, quantities and costs
/// are integers, and a line that has been received cannot be edited — because
/// the goods are in the kitchen and the paper has to keep saying what came.
library;

import '../../core/money/money.dart';
import '../../core/money/quantity.dart';

/// Where a purchase order has got to.
///
/// Five states, and the two in the middle are the ones that matter: a
/// restaurant almost never receives exactly what it ordered, and a model that
/// only knew *ordered* and *received* would have to lie about the Tuesday when
/// eight of ten crates turned up.
enum PurchaseStatus {
  /// Being written. Editable, and not yet a commitment to anybody.
  draft('draft'),

  /// Sent to the supplier. The totals are fixed from here — what was agreed is
  /// what the invoice will be checked against.
  sent('sent'),

  /// Some of it arrived. The order stays open because the rest is still owed.
  partiallyReceived('partially_received'),

  /// All of it arrived, or somebody closed the difference deliberately.
  received('received'),

  /// Called off. Never deleted: an order somebody sent and then cancelled is a
  /// conversation with a supplier, and a purchase history that cannot show it
  /// cannot explain the gap.
  cancelled('cancelled');

  const PurchaseStatus(this.wire);

  final String wire;

  static PurchaseStatus fromWire(String value) => PurchaseStatus.values
      .firstWhere(
        (s) => s.wire == value,
        // An unknown status from a newer build is not something to guess at:
        // reading it as `received` would close an order nothing arrived for.
        orElse: () => throw ArgumentError.value(value, 'status', 'unknown'),
      );

  /// Whether the lines may still be changed.
  bool get isEditable => this == draft;

  /// Whether goods may still be booked in against it.
  bool get isOpen => this == sent || this == partiallyReceived;

  /// Whether it is finished, one way or the other.
  bool get isClosed => this == received || this == cancelled;
}

/// One thing ordered.
class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.id,
    required this.description,
    required this.ordered,
    required this.unitCost,
    this.received = Quantity.zero,
    this.productId,
    this.sku,
    this.taxRateBp = 0,
  });

  final int id;

  /// What it is, as it was written on the order.
  ///
  /// Snapshotted rather than joined to the product, for the same reason a
  /// settled order line keeps its name: a supplier's docket has to still make
  /// sense after somebody renames a menu item.
  final String description;

  /// The menu item this stocks, when it is one. Null for the things a
  /// restaurant buys that it does not sell — cleaning supplies, packaging,
  /// gas — which is most of a purchase order by line count.
  final int? productId;

  final String? sku;

  final Quantity ordered;
  final Quantity received;

  /// What one unit costs, before tax, in minor units.
  final Money unitCost;

  /// The rate on this line, snapshotted. Input VAT is reclaimable and the
  /// return needs the rate that was actually charged, not today's.
  final int taxRateBp;

  /// What is still owed on this line. Never negative: over-delivery is
  /// recorded as what arrived, and the shortfall closes at zero rather than
  /// becoming a debt the supplier owes back.
  Quantity get outstanding {
    final remaining = ordered.milli - received.milli;
    return Quantity(remaining > 0 ? remaining : 0, unit: ordered.unit);
  }

  bool get isFullyReceived => received.milli >= ordered.milli;

  /// More arrived than was asked for. Its own question because it is not an
  /// error — suppliers round up to a full crate — and a screen that flagged it
  /// as one would train somebody to ignore the flag.
  bool get isOverReceived => received.milli > ordered.milli;

  /// The cost of what was ordered, before tax.
  Money get lineTotal => unitCost.copyWith(minor: ordered.costAt(unitCost.minor));

  /// The tax on this line, rounded once.
  Money get lineTax => lineTotal.percentBp(taxRateBp);

  PurchaseOrderLine copyWith({
    String? description,
    Quantity? ordered,
    Quantity? received,
    Money? unitCost,
    int? taxRateBp,
  }) => PurchaseOrderLine(
    id: id,
    description: description ?? this.description,
    productId: productId,
    sku: sku,
    ordered: ordered ?? this.ordered,
    received: received ?? this.received,
    unitCost: unitCost ?? this.unitCost,
    taxRateBp: taxRateBp ?? this.taxRateBp,
  );
}

/// What a purchase order comes to.
class PurchaseTotals {
  const PurchaseTotals({
    required this.subtotal,
    required this.tax,
    required this.total,
  });

  final Money subtotal;
  final Money tax;
  final Money total;
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.supplierId,
    required this.reference,
    required this.status,
    required this.lines,
    this.supplierName,
    this.orderedAt,
    this.expectedAt,
    this.notes,
    this.currency = 'EGP',
    this.exponent = 2,
  });

  final int id;
  final int supplierId;

  /// The supplier as the order named them. Snapshotted for the same reason the
  /// line description is.
  final String? supplierName;

  /// The restaurant's own number for it — `PO-2026-000042`.
  final String reference;

  final PurchaseStatus status;
  final List<PurchaseOrderLine> lines;

  /// When it was sent. Null while it is a draft, which is what makes "sent" a
  /// fact about the order rather than a flag somebody set.
  final DateTime? orderedAt;

  final DateTime? expectedAt;
  final String? notes;
  final String currency;
  final int exponent;

  Money get _zero => Money(0, currency: currency, exponent: exponent);

  /// What it comes to, computed from the lines.
  ///
  /// **Tax is rounded per rate, not per line and not once at the end** — the
  /// same rule the ticket uses, and for the same reason: a return is filed by
  /// rate, and three lines at 14% rounding separately do not sum to the same
  /// number as their total taxed once.
  PurchaseTotals get totals {
    var subtotal = _zero;
    final basesByRate = <int, Money>{};

    for (final line in lines) {
      final amount = line.lineTotal;
      subtotal += amount;
      if (line.taxRateBp > 0) {
        basesByRate[line.taxRateBp] =
            (basesByRate[line.taxRateBp] ?? _zero) + amount;
      }
    }

    var tax = _zero;
    for (final entry in basesByRate.entries) {
      tax += entry.value.percentBp(entry.key);
    }

    return PurchaseTotals(
      subtotal: subtotal,
      tax: tax,
      total: subtotal + tax,
    );
  }

  /// What has actually arrived, at the ordered cost.
  ///
  /// Not the same as [totals] the moment anything is short, and it is this
  /// number — not the ordered one — that a supplier's invoice should match.
  Money get receivedValue => lines.fold(
    _zero,
    (sum, line) =>
        sum + line.unitCost.copyWith(minor: line.received.costAt(line.unitCost.minor)),
  );

  /// What has arrived, with tax — the figure a supplier's invoice should say.
  ///
  /// Tax is rounded per rate here too, and on the *received* quantities rather
  /// than the ordered ones: an order for ten crates that arrived as eight
  /// should be invoiced for eight, and comparing against [totals] would flag
  /// every short delivery as a pricing dispute.
  Money get receivedTotal {
    final basesByRate = <int, Money>{};
    var net = _zero;

    for (final line in lines) {
      final amount = line.unitCost.copyWith(
        minor: line.received.costAt(line.unitCost.minor),
      );
      net += amount;
      if (line.taxRateBp > 0) {
        basesByRate[line.taxRateBp] =
            (basesByRate[line.taxRateBp] ?? _zero) + amount;
      }
    }

    var tax = _zero;
    for (final entry in basesByRate.entries) {
      tax += entry.value.percentBp(entry.key);
    }
    return net + tax;
  }

  bool get isFullyReceived =>
      lines.isNotEmpty && lines.every((l) => l.isFullyReceived);

  bool get isPartiallyReceived =>
      !isFullyReceived && lines.any((l) => l.received.milli > 0);

  /// What the status *should* be, given what has arrived.
  ///
  /// Derived rather than set, so a receipt of goods cannot leave the status
  /// saying something the lines disagree with. The caller writes it; this
  /// decides it.
  PurchaseStatus get statusFromReceipts {
    if (status == PurchaseStatus.cancelled || status == PurchaseStatus.draft) {
      return status;
    }
    if (isFullyReceived) return PurchaseStatus.received;
    if (isPartiallyReceived) return PurchaseStatus.partiallyReceived;
    return PurchaseStatus.sent;
  }

  PurchaseOrder copyWith({
    PurchaseStatus? status,
    List<PurchaseOrderLine>? lines,
    DateTime? orderedAt,
    DateTime? expectedAt,
    String? notes,
    String? reference,
  }) => PurchaseOrder(
    id: id,
    supplierId: supplierId,
    supplierName: supplierName,
    reference: reference ?? this.reference,
    status: status ?? this.status,
    lines: lines ?? this.lines,
    orderedAt: orderedAt ?? this.orderedAt,
    expectedAt: expectedAt ?? this.expectedAt,
    notes: notes ?? this.notes,
    currency: currency,
    exponent: exponent,
  );
}

/// Why a purchase order cannot be changed as asked.
///
/// Data rather than exceptions, exactly as `TicketRefusal` is: a buyer trying
/// to edit an order that has already gone out is normal operation, not a bug.
sealed class PurchaseRefusal {
  const PurchaseRefusal();
}

class OrderNotEditable extends PurchaseRefusal {
  const OrderNotEditable(this.status);

  final PurchaseStatus status;
}

class OrderHasNoLines extends PurchaseRefusal {
  const OrderHasNoLines();
}

class LineQuantityNotPositive extends PurchaseRefusal {
  const LineQuantityNotPositive();
}

class OrderAlreadyClosed extends PurchaseRefusal {
  const OrderAlreadyClosed(this.status);

  final PurchaseStatus status;
}

/// The result of asking to change one.
class PurchaseResult {
  const PurchaseResult.ok(PurchaseOrder this.order) : refusal = null;
  const PurchaseResult.refused(PurchaseRefusal this.refusal) : order = null;

  final PurchaseOrder? order;
  final PurchaseRefusal? refusal;

  bool get succeeded => refusal == null;
}

/// Every change a purchase order can undergo, as pure functions.
///
/// The same shape as `TicketEngine`, and for the same reason: the rules about
/// what may be edited when are the part worth testing without a database, and
/// a repository that enforced them itself would enforce them slightly
/// differently from the screen.
abstract final class PurchaseEngine {
  /// Add a line to a draft.
  static PurchaseResult addLine(PurchaseOrder order, PurchaseOrderLine line) {
    if (!order.status.isEditable) {
      return PurchaseResult.refused(OrderNotEditable(order.status));
    }
    if (line.ordered.milli <= 0) {
      return const PurchaseResult.refused(LineQuantityNotPositive());
    }
    return PurchaseResult.ok(
      order.copyWith(lines: [...order.lines, line]),
    );
  }

  /// Send it to the supplier. From here the totals are what the invoice is
  /// checked against.
  static PurchaseResult send(PurchaseOrder order, {required DateTime at}) {
    if (order.status != PurchaseStatus.draft) {
      return PurchaseResult.refused(OrderNotEditable(order.status));
    }
    if (order.lines.isEmpty) {
      return const PurchaseResult.refused(OrderHasNoLines());
    }
    return PurchaseResult.ok(
      order.copyWith(status: PurchaseStatus.sent, orderedAt: at),
    );
  }

  /// Call it off.
  ///
  /// Allowed from draft and from sent, and refused once anything has arrived:
  /// goods in the kitchen are not cancellable, and the way out of a part
  /// delivery is to close the difference rather than to pretend the order
  /// never happened.
  static PurchaseResult cancel(PurchaseOrder order) {
    if (order.status.isClosed) {
      return PurchaseResult.refused(OrderAlreadyClosed(order.status));
    }
    if (order.status == PurchaseStatus.partiallyReceived) {
      return PurchaseResult.refused(OrderAlreadyClosed(order.status));
    }
    return PurchaseResult.ok(order.copyWith(status: PurchaseStatus.cancelled));
  }
}
