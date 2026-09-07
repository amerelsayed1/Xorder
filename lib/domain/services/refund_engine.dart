import '../../core/money/money.dart';
import '../../core/money/rounding.dart';
import '../models/order_record.dart';
import '../models/refund.dart';

/// Why a refund was refused. Data, not strings, for the same reason
/// [TicketRefusal] is: the engine stays testable without a locale and
/// translatable without being edited.
sealed class RefundRefusal {
  const RefundRefusal();
}

/// The restaurant has refunds switched off.
class RefundsDisabled extends RefundRefusal {
  const RefundsDisabled();
}

/// The sale is older than the policy allows.
class OutsideRefundWindow extends RefundRefusal {
  const OutsideRefundWindow(this.window, this.soldAt);

  final RefundWindow window;
  final DateTime soldAt;
}

/// The order never took any money, or has already given all of it back.
class NothingLeftToRefund extends RefundRefusal {
  const NothingLeftToRefund(this.status);

  final OrderStatus status;
}

/// Nothing was selected, or everything selected came to zero.
class NothingSelected extends RefundRefusal {
  const NothingSelected();
}

/// A line was selected that is not on this order.
class LineNotOnOrder extends RefundRefusal {
  const LineNotOnOrder(this.orderLineId);

  final int orderLineId;
}

/// More of a line was selected than remains refundable.
///
/// Carries both numbers because "you asked for 3 and 1 is left" is the sentence
/// a cashier can act on; "too many" is not.
class MoreThanRemains extends RefundRefusal {
  const MoreThanRemains({
    required this.orderLineId,
    required this.asked,
    required this.remaining,
  });

  final int orderLineId;
  final int asked;
  final int remaining;
}

/// The amount asked for is more than the order has left to give.
class AboveRemainingValue extends RefundRefusal {
  const AboveRemainingValue({required this.asked, required this.remaining});

  final Money asked;
  final Money remaining;
}

/// Above the policy's ceiling for a single refund. Not an approval prompt —
/// a ceiling is a ceiling, and there is nobody to ask.
class AboveRefundLimit extends RefundRefusal {
  const AboveRefundLimit({required this.asked, required this.limit});

  final Money asked;
  final Money limit;
}

/// The policy requires a reason and none was given.
class RefundReasonRequired extends RefundRefusal {
  const RefundReasonRequired();
}

/// What a refund would come to, before it is issued.
///
/// Every figure here is computed once, shown to the operator, and then written.
/// The dialog never recomputes a total it has already displayed — a number that
/// changes between "confirm" and the row is the one somebody disputes later.
class RefundQuote {
  const RefundQuote({
    required this.subtotal,
    required this.discount,
    required this.service,
    required this.vat,
    required this.total,
    required this.kind,
    required this.lines,
    required this.requiresApproval,
  });

  final Money subtotal;
  final Money discount;
  final Money service;
  final Money vat;
  final Money total;

  final RefundKind kind;
  final List<RefundLineSelection> lines;

  /// The policy's threshold was passed. The caller has to fetch an approver
  /// before writing — the engine states the requirement, it does not enforce
  /// it, because enforcing it means showing a dialog.
  final bool requiresApproval;

  bool get isEmpty => total.minor <= 0;
}

/// Working out what a refund gives back.
///
/// **The problem this solves.** A sale is priced in one direction: lines make a
/// subtotal, a discount comes off it, service is charged on what is left, and
/// VAT on the sum of those. Refunding part of that sale has to run the same
/// arithmetic backwards, and the naive answer — recompute service and VAT from
/// today's configured rates — is wrong twice over. The rates may have changed
/// since the sale, and even where they have not, a rate applied to a fraction
/// of a bill does not generally reproduce a fraction of the original tax.
///
/// **So nothing here recomputes tax.** Every part of a partial refund is a
/// *share* of what the order actually charged, pro-rated and rounded half-up,
/// exactly as `Money.percentBp` rounds. The order's own numbers are the only
/// input; the tax configuration is not consulted at all.
///
/// **And the last refund takes the remainder.** If a refund clears the order —
/// every remaining line, or the whole remaining value — its parts are the
/// order's parts less everything already given back, rather than a fresh
/// pro-rata calculation. Without that rule, refunding a bill in three parts
/// could leave a piastre stranded against an order that has nothing left in it,
/// and `pos_orders.refunded_minor <= total_minor` would eventually refuse a
/// refund that is arithmetically correct.
abstract final class RefundEngine {
  /// A refund of particular lines and quantities.
  ///
  /// [previous] is every refund already issued against this order. It is needed
  /// for the remainder rule above, and passing it in rather than deriving it
  /// from `order.refundedTotal` is what lets each *part* be exact rather than
  /// only the total.
  static (RefundQuote?, RefundRefusal?) quoteForLines({
    required OrderRecordDetail detail,
    required Map<int, int> quantities,
    required List<Refund> previous,
    required RefundPolicy policy,
    required DateTime at,
    bool sameShift = false,
  }) {
    final blocked = _guard(
      detail: detail,
      previous: previous,
      policy: policy,
      at: at,
      sameShift: sameShift,
    );
    if (blocked != null) return (null, blocked);

    final order = detail.order;
    final zero = _zero(order);
    final byId = {for (final line in detail.lines) line.id: line};

    final selection = <RefundLineSelection>[];
    var subtotal = zero;

    for (final entry in quantities.entries) {
      if (entry.value <= 0) continue;

      final line = byId[entry.key];
      if (line == null) return (null, LineNotOnOrder(entry.key));

      if (entry.value > line.refundableQuantity) {
        return (
          null,
          MoreThanRemains(
            orderLineId: entry.key,
            asked: entry.value,
            remaining: line.refundableQuantity,
          ),
        );
      }

      final chosen = RefundLineSelection(
        orderLineId: line.id,
        name: line.name,
        quantity: entry.value,
        unitPrice: line.unitPrice,
      );
      selection.add(chosen);
      subtotal += chosen.lineTotal;
    }

    if (selection.isEmpty || subtotal.minor <= 0) {
      return (null, const NothingSelected());
    }

    // Does this clear the order? Two conditions, and the second is not
    // redundant.
    //
    // The first: every refundable line, in full. `>=` rather than `==` because
    // a line already partly refunded contributes only its remainder, and a
    // voided line contributes nothing.
    //
    // The second: the value adds up. Taking every line in [detail] on trust
    // means a short read — a query that returned some of the lines — would be
    // read as "the whole order", and the remainder rule would then hand back
    // the entire bill. Requiring the subtotal to reconcile makes that failure
    // fall back to a pro-rata refund of what was actually selected, which is
    // wrong by a rounding unit rather than by the price of a meal.
    final everyLineTaken = detail.lines.every((line) {
      final taking = quantities[line.id] ?? 0;
      return taking >= line.refundableQuantity;
    });
    final refundedBefore = _sum(previous, (r) => r.subtotal, order);
    final clears =
        everyLineTaken &&
        subtotal.minor + refundedBefore.minor >= order.subtotal.minor;

    return _finish(
      order: order,
      previous: previous,
      lines: selection,
      subtotal: subtotal,
      clears: clears,
      policy: policy,
    );
  }

  /// A refund of a flat amount against the bill as a whole.
  ///
  /// [gross] is what the customer gets back — the figure they and the cashier
  /// are actually discussing. Its parts are that same fraction of the order's
  /// own subtotal, discount, service and VAT, so a report of refunded tax stays
  /// consistent with a report of refunded sales.
  ///
  /// No lines are attached, which is deliberate: nobody said *which* food this
  /// was for, and inventing an attribution would move `refunded_quantity` on a
  /// line the operator never chose. The order-level ceiling still applies.
  static (RefundQuote?, RefundRefusal?) quoteForAmount({
    required OrderRecordDetail detail,
    required Money gross,
    required List<Refund> previous,
    required RefundPolicy policy,
    required DateTime at,
    bool sameShift = false,
  }) {
    final blocked = _guard(
      detail: detail,
      previous: previous,
      policy: policy,
      at: at,
      sameShift: sameShift,
    );
    if (blocked != null) return (null, blocked);

    if (gross.minor <= 0) return (null, const NothingSelected());

    final order = detail.order;
    final remaining = order.total - _sum(previous, (r) => r.total, order);
    if (gross.minor > remaining.minor) {
      return (null, AboveRemainingValue(asked: gross, remaining: remaining));
    }

    if (!policy.permits(gross)) {
      return (null, AboveRefundLimit(asked: gross, limit: policy.maxValue!));
    }

    final clears = gross.minor == remaining.minor;
    if (clears) {
      return _remainder(
        order: order,
        previous: previous,
        lines: const [],
        policy: policy,
      );
    }

    // One ratio for every part, so they still sum to the gross the cashier was
    // shown — give or take the single unit the reconciliation below removes.
    Money share(Money part) => _share(part, gross.minor, order.total.minor);

    final subtotal = share(order.subtotal);
    final discount = share(order.discount);
    final service = share(order.service);
    var vat = share(order.vat);

    // The parts are rounded independently, so they can miss the gross by a
    // unit. VAT absorbs it, because the gross is what the customer is handed
    // and it must be the number that is exact.
    final drift =
        gross.minor - (subtotal.minor - discount.minor + service.minor + vat.minor);
    vat = vat.copyWith(minor: vat.minor + drift);

    return (
      RefundQuote(
        subtotal: subtotal,
        discount: discount,
        service: service,
        vat: vat,
        total: gross,
        kind: RefundKind.partial,
        lines: const [],
        requiresApproval: policy.needsApproval(gross),
      ),
      null,
    );
  }

  /// Everything that is true before a single line has been chosen.
  static RefundRefusal? _guard({
    required OrderRecordDetail detail,
    required List<Refund> previous,
    required RefundPolicy policy,
    required DateTime at,
    required bool sameShift,
  }) {
    if (!policy.enabled) return const RefundsDisabled();

    final order = detail.order;
    if (!order.status.tookMoney) return NothingLeftToRefund(order.status);

    final remaining = order.total - _sum(previous, (r) => r.total, order);
    if (remaining.minor <= 0) return NothingLeftToRefund(order.status);

    if (!policy.allowsAt(
      order.occurredAt,
      issuedAt: at,
      sameShift: sameShift,
    )) {
      return OutsideRefundWindow(policy.window, order.occurredAt);
    }

    return null;
  }

  /// Pro-rate the order's parts by the refunded subtotal, or take the
  /// remainder when this refund clears the order.
  static (RefundQuote?, RefundRefusal?) _finish({
    required OrderRecord order,
    required List<Refund> previous,
    required List<RefundLineSelection> lines,
    required Money subtotal,
    required bool clears,
    required RefundPolicy policy,
  }) {
    if (clears) {
      return _remainder(
        order: order,
        previous: previous,
        lines: lines,
        policy: policy,
      );
    }

    // The base is the order's own subtotal, not its total: the lines coming
    // back are priced at their pre-discount value, which is exactly what
    // `subtotal_minor` is the sum of.
    Money share(Money part) =>
        _share(part, subtotal.minor, order.subtotal.minor);

    final discount = share(order.discount);
    final service = share(order.service);
    final vat = share(order.vat);
    final total = (subtotal - discount + service + vat).clampToZero();

    // A pro-rata refund can only ever be bounded by the order it comes off, but
    // rounding runs in both directions and previous refunds have already taken
    // their share. Checked rather than assumed, because the database will
    // refuse it and a refusal at the last moment is a customer standing at a
    // counter.
    final remaining = order.total - _sum(previous, (r) => r.total, order);
    if (total.minor > remaining.minor) {
      return (null, AboveRemainingValue(asked: total, remaining: remaining));
    }

    if (!policy.permits(total)) {
      return (null, AboveRefundLimit(asked: total, limit: policy.maxValue!));
    }

    return (
      RefundQuote(
        subtotal: subtotal,
        discount: discount,
        service: service,
        vat: vat,
        total: total,
        kind: RefundKind.partial,
        lines: lines,
        requiresApproval: policy.needsApproval(total),
      ),
      null,
    );
  }

  /// Exactly what is left, part by part.
  static (RefundQuote?, RefundRefusal?) _remainder({
    required OrderRecord order,
    required List<Refund> previous,
    required List<RefundLineSelection> lines,
    required RefundPolicy policy,
  }) {
    final total = order.total - _sum(previous, (r) => r.total, order);
    if (total.minor <= 0) return (null, NothingLeftToRefund(order.status));

    if (!policy.permits(total)) {
      return (null, AboveRefundLimit(asked: total, limit: policy.maxValue!));
    }

    return (
      RefundQuote(
        subtotal: order.subtotal - _sum(previous, (r) => r.subtotal, order),
        discount: order.discount - _sum(previous, (r) => r.discount, order),
        service: order.service - _sum(previous, (r) => r.service, order),
        vat: order.vat - _sum(previous, (r) => r.vat, order),
        total: total,
        // Nothing is left afterwards, so this refund is the one that closes the
        // order — whether or not it is the first.
        kind: RefundKind.full,
        lines: lines,
        requiresApproval: policy.needsApproval(total),
      ),
      null,
    );
  }

  /// [part] × [numerator] ÷ [denominator], half-up, in the part's currency.
  static Money _share(Money part, int numerator, int denominator) {
    if (denominator <= 0 || part.minor == 0) return part.copyWith(minor: 0);
    return part.copyWith(
      minor: roundHalfUp(part.minor * numerator, denominator),
    );
  }

  static Money _sum(
    List<Refund> refunds,
    Money Function(Refund) part,
    OrderRecord order,
  ) {
    var total = _zero(order);
    for (final refund in refunds) {
      total += part(refund);
    }
    return total;
  }

  static Money _zero(OrderRecord order) => Money(
    0,
    currency: order.total.currency,
    exponent: order.total.exponent,
  );
}
