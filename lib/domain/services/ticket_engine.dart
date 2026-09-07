import 'package:collection/collection.dart';

import '../../core/money/money.dart';
import '../models/catalog.dart';
import '../models/discount.dart';
import '../models/ticket.dart';

/// Why an operation was refused. The UI turns these into toasts; keeping them
/// as data rather than strings means the engine stays testable and translatable.
sealed class TicketRefusal {
  const TicketRefusal();
}

class OutOfStock extends TicketRefusal {
  const OutOfStock(this.product);
  final Product product;
}

class RequiredGroupUnsatisfied extends TicketRefusal {
  const RequiredGroupUnsatisfied(this.group);
  final ModifierGroup group;
}

class TooManySelected extends TicketRefusal {
  const TooManySelected(this.group);
  final ModifierGroup group;
}

class NothingToTender extends TicketRefusal {
  const NothingToTender();
}

class ZeroTender extends TicketRefusal {
  const ZeroTender();
}

/// The line is already voided. Voiding it twice is not a second act.
class AlreadyVoided extends TicketRefusal {
  const AlreadyVoided(this.lineKey);

  final String lineKey;
}

/// A cancel was aimed at a line the kitchen has already made, or a void at one
/// it has not.
///
/// The two acts are not interchangeable and the caller picked the wrong one —
/// which, on a screen, means the button offered the wrong thing.
class WrongStageForAct extends TicketRefusal {
  const WrongStageForAct(this.lineKey, this.stage);

  final String lineKey;
  final LineStage stage;
}

/// A one-off charge with nothing written on it.
///
/// The name is what the customer reads on the receipt and what a manager sees
/// on the report; "Item" against 200.00 is a line nobody can account for later.
class OpenItemNeedsName extends TicketRefusal {
  const OpenItemNeedsName();
}

/// The price asked for is the price the line already carries.
///
/// Refused rather than accepted quietly: an override that changes nothing still
/// writes an audit row naming somebody, and a ledger full of no-ops is a ledger
/// nobody reads.
class PriceUnchanged extends TicketRefusal {
  const PriceUnchanged(this.lineKey);

  final String lineKey;
}

/// A negative unit price. Zero is legitimate — a comp — and below zero is a
/// refund wearing a disguise, which has its own flow and its own permission.
class PriceBelowZero extends TicketRefusal {
  const PriceBelowZero();
}

/// The reduction is past what this person may give away.
///
/// **A price override is a discount by another name.** Without this, a cashier
/// with `price.override` and a 10% discount ceiling could reprice a 50.00 dish
/// to 5.00 and take 90% off a line the discount sheet would have refused. The
/// same [DiscountLimit] therefore governs both, and the UI escalates to a
/// supervisor in the same way.
class PriceBelowLimit extends TicketRefusal {
  const PriceBelowLimit({
    required this.lineKey,
    required this.reduction,
    required this.base,
  });

  final String lineKey;

  /// What the whole line's price would drop by.
  final Money reduction;

  /// What the line would have cost at menu prices — the figure the percentage
  /// ceiling is measured against.
  final Money base;
}

/// There is nothing for a discount to come off.
class NothingToDiscount extends TicketRefusal {
  const NothingToDiscount();
}

/// The line a discount was aimed at is not on the ticket.
class LineNotOnTicket extends TicketRefusal {
  const LineNotOnTicket(this.lineKey);

  final String lineKey;
}

/// The discount is not being offered — inactive, outside its dates, its days or
/// its hours, or not applicable to this order type or this product.
class DiscountNotOffered extends TicketRefusal {
  const DiscountNotOffered(this.discount);

  final Discount discount;
}

/// The discount is configured to need a customer on the order, and there is
/// none. Loyalty and staff pricing both use this.
class DiscountRequiresCustomer extends TicketRefusal {
  const DiscountRequiresCustomer(this.discount);

  final Discount discount;
}

/// Something is already discounted, and stacking is not allowed.
///
/// One discount per line and one on the order, deliberately. Two discounts on
/// one line cannot be reported on individually once they are summed, and the
/// order in which they compound is a decision nobody at a till should be making
/// under time pressure.
class AlreadyDiscounted extends TicketRefusal {
  const AlreadyDiscounted(this.existing);

  final AppliedDiscount existing;
}

/// The discount is larger than the person may give without approval.
///
/// **Not a denial.** The UI turns this into a manager-approval prompt, and the
/// same call succeeds when [DiscountLimit] is passed as null after a supervisor
/// has lent the permission — which is why the limit is a parameter rather than
/// something the engine looks up.
class DiscountAboveLimit extends TicketRefusal {
  const DiscountAboveLimit({
    required this.limit,
    required this.requested,
    required this.base,
  });

  final DiscountLimit limit;

  /// What the discount would come to.
  final Money requested;

  /// What it would come off, so the caller can state the percentage a cashier
  /// actually asked for rather than the one they typed.
  final Money base;
}

/// Result of a ticket operation: either the new ticket, or a refusal.
///
/// Deliberately not an exception — a cashier hitting a required-modifier rule
/// is normal operation, not an error condition.
class TicketResult {
  const TicketResult.ok(this.ticket) : refusal = null;
  const TicketResult.refused(this.refusal) : ticket = null;

  final Ticket? ticket;
  final TicketRefusal? refusal;

  bool get isOk => ticket != null;
}

/// All ticket mutations, as pure functions.
///
/// Nothing here touches Flutter, the network or the database. That is the whole
/// point: the money rules are unit-tested directly, and the same functions run
/// identically online and offline.
abstract final class TicketEngine {
  /// Validate a modifier selection against its groups.
  ///
  /// Returns null when the selection is addable. Required groups block the add;
  /// exceeding `maxSelect` blocks it too.
  static TicketRefusal? validateSelection(
    List<ModifierGroup> groups,
    List<Modifier> selected,
  ) {
    for (final group in groups) {
      final chosen = selected.where((m) => m.groupId == group.id).toList();

      if (group.isRequired && chosen.isEmpty) {
        return RequiredGroupUnsatisfied(group);
      }
      if (chosen.length > group.maxSelect) {
        return TooManySelected(group);
      }
    }
    return null;
  }

  /// Apply a tap on a modifier, honouring the group's selection rule.
  ///
  /// Single-select groups replace; multi-select groups stop at `maxSelect`
  /// rather than silently dropping the oldest choice — a cashier who hits the
  /// cap should be told, not quietly corrected.
  static List<Modifier> toggleModifier(
    List<Modifier> current,
    ModifierGroup group,
    Modifier modifier,
  ) {
    final isSelected = current.any((m) => m.id == modifier.id);
    final others = current.where((m) => m.groupId != group.id).toList();
    final sameGroup = current.where((m) => m.groupId == group.id).toList();

    if (isSelected) {
      return [...others, ...sameGroup.where((m) => m.id != modifier.id)];
    }
    if (group.isSingleSelect) {
      return [...others, modifier];
    }
    if (sameGroup.length >= group.maxSelect) {
      return current; // at the cap — caller shows the toast
    }
    return [...others, ...sameGroup, modifier];
  }

  /// Add a product to the ticket, merging into an existing draft line when the
  /// product and its modifiers match exactly.
  ///
  /// Only **draft** lines merge. A line already fired to the kitchen must stay
  /// as it was sent, or the printed round and the bill stop agreeing.
  static TicketResult addLine(
    Ticket ticket,
    Product product, {
    List<Modifier> modifiers = const [],
    List<ModifierGroup> groups = const [],
    int quantity = 1,
    String? note,
  }) {
    if (!product.isAvailable) {
      return TicketResult.refused(OutOfStock(product));
    }

    final refusal = validateSelection(groups, modifiers);
    if (refusal != null) return TicketResult.refused(refusal);

    final key = TicketLine.keyFor(product, modifiers);
    final lines = [...ticket.lines];
    final index = lines.indexWhere(
      (l) => l.stage == LineStage.draft && l.key == key && l.note == note,
    );

    if (index >= 0) {
      lines[index] = lines[index].copyWith(
        quantity: lines[index].quantity + quantity,
      );
    } else {
      lines.add(
        TicketLine(
          product: product,
          quantity: quantity,
          modifiers: modifiers,
          note: note,
        ),
      );
    }

    return TicketResult.ok(ticket.copyWith(lines: lines));
  }

  /// Change a draft line's quantity. Dropping to zero removes the line.
  ///
  /// Sent lines have no steppers in the design, and this enforces that rule at
  /// the engine level rather than trusting the UI to hide the buttons.
  static Ticket changeQuantity(Ticket ticket, String lineKey, int delta) {
    final lines = <TicketLine>[];

    for (final line in ticket.lines) {
      if (line.stage != LineStage.draft || line.key != lineKey) {
        lines.add(line);
        continue;
      }
      final next = line.quantity + delta;
      if (next > 0) lines.add(line.copyWith(quantity: next));
    }

    return ticket.copyWith(lines: lines);
  }

  static Ticket removeLine(Ticket ticket, String lineKey) => ticket.copyWith(
    lines: ticket.lines
        .where((l) => !(l.stage == LineStage.draft && l.key == lineKey))
        .toList(),
  );

  // ── Cancelling and voiding ────────────────────────────────────────────────
  //
  // **Two acts, and the schema, the permissions and the screens all keep them
  // apart.** Taking a line off before the kitchen has seen it is housekeeping:
  // nothing was made, nothing was wasted, and the line leaves the ticket. Once
  // it has been fired, removing it is waste with a cost — so the line *stays*,
  // struck through, with a reason and a name against it, and the customer can
  // be shown exactly what happened.
  //
  // A system that recorded both as "line gone" could never afterwards be asked
  // which occurred, and that question is the one a month-end review asks first.

  /// Take an unsent line off the ticket.
  ///
  /// Refuses a sent line rather than quietly voiding it: a caller that reached
  /// here with something already cooking has offered the wrong control, and
  /// silently upgrading the act would record waste as housekeeping.
  static TicketResult cancelLine(
    Ticket ticket,
    String lineKey, {
    required int by,
    required DateTime now,
    int? reasonId,
    String? note,
  }) {
    final line = ticket.lines.firstWhereOrNull((l) => l.key == lineKey);
    if (line == null) return TicketResult.refused(LineNotOnTicket(lineKey));
    if (line.stage != LineStage.draft) {
      return TicketResult.refused(WrongStageForAct(lineKey, line.stage));
    }

    return TicketResult.ok(
      ticket.copyWith(
        lines: ticket.lines.where((l) => l.key != lineKey).toList(),
        // Any discount on it goes with it. A discount on a line nobody is
        // being charged for is money off nothing.
        discounts: ticket.discounts
            .where((d) => d.lineKey != lineKey)
            .toList(),
        lineEvents: [
          ...ticket.lineEvents,
          TicketLineEvent(
            lineKey: lineKey,
            event: TicketLineEventKind.removedBeforeSend,
            staffId: by,
            at: now,
            quantityBefore: line.quantity,
            quantityAfter: 0,
            reasonId: reasonId,
            note: note,
          ),
        ],
      ),
    );
  }

  /// Void a line the kitchen has already made.
  ///
  /// The line **stays on the ticket**, marked, and stops counting toward every
  /// total. Removing it would leave the cashier unable to show a customer what
  /// happened and what it cost, and would leave the kitchen's ticket and the
  /// bill describing different meals.
  static TicketResult voidLine(
    Ticket ticket,
    String lineKey, {
    required int by,
    required DateTime now,
    int? reasonId,
    String? note,
    int? approvedByStaffId,
    String? approvedByName,
  }) {
    final line = ticket.lines.firstWhereOrNull((l) => l.key == lineKey);
    if (line == null) return TicketResult.refused(LineNotOnTicket(lineKey));
    if (line.isVoided) return TicketResult.refused(AlreadyVoided(lineKey));
    if (line.stage != LineStage.sent) {
      return TicketResult.refused(WrongStageForAct(lineKey, line.stage));
    }

    final voided = LineVoid(
      byStaffId: by,
      at: now,
      reasonId: reasonId,
      note: note,
      approvedByStaffId: approvedByStaffId,
      approvedByName: approvedByName,
    );

    return TicketResult.ok(
      ticket.copyWith(
        lines: [
          for (final l in ticket.lines)
            if (l.key == lineKey) l.copyWith(voided: voided) else l,
        ],
        lineEvents: [
          ...ticket.lineEvents,
          TicketLineEvent(
            lineKey: lineKey,
            event: TicketLineEventKind.voidedAfterSend,
            staffId: by,
            at: now,
            quantityBefore: line.quantity,
            quantityAfter: 0,
            reasonId: reasonId,
            note: note,
            approvedByStaffId: approvedByStaffId,
          ),
        ],
      ),
    );
  }

  /// Fire the draft to the kitchen. Draft becomes sent; the table stays open.
  static Ticket sendRound(Ticket ticket) {
    if (!ticket.hasDraft) return ticket;

    final round = ticket.roundsSent + 1;
    return ticket.copyWith(
      roundsSent: round,
      lines: ticket.lines
          .map(
            (l) => l.stage == LineStage.draft
                ? l.copyWith(stage: LineStage.sent, roundNumber: round)
                : l,
          )
          .toList(),
    );
  }

  /// Switch order mode.
  ///
  /// Leaving dine-in detaches the table — a bill never follows a mode switch.
  /// This is a rule from the design sheet and it exists because the alternative
  /// silently moves a seated party's money onto a takeaway ticket.
  static Ticket setOrderType(Ticket ticket, OrderType type) {
    if (type == ticket.orderType) return ticket;

    return ticket.copyWith(
      orderType: type,
      clearTable: type != OrderType.dineIn,
    );
  }

  static Ticket attachTable(
    Ticket ticket,
    int tableId,
    String label, {
    int? guests,
  }) => ticket.copyWith(
    orderType: OrderType.dineIn,
    tableId: tableId,
    tableLabel: label,
    guestCount: guests,
  );

  /// Take a tender.
  ///
  /// A null [amount] means "the whole remaining due", which is what an empty
  /// keypad entry means in the payment screen.
  static TicketResult addTender(
    Ticket ticket, {
    required int typeId,
    required String label,
    Money? amount,
    String? reference,
  }) {
    if (ticket.isEmpty) return const TicketResult.refused(NothingToTender());

    final due = ticket.totals.due;
    final value = amount ?? due;

    if (value.isZero || value.isNegative) {
      return const TicketResult.refused(ZeroTender());
    }

    return TicketResult.ok(
      ticket.copyWith(
        tenders: [
          ...ticket.tenders,
          Tender(
            typeId: typeId,
            label: label,
            amount: value,
            reference: reference,
          ),
        ],
      ),
    );
  }

  static Ticket removeTenderAt(Ticket ticket, int index) {
    if (index < 0 || index >= ticket.tenders.length) return ticket;

    final tenders = [...ticket.tenders]..removeAt(index);
    return ticket.copyWith(tenders: tenders);
  }

  // ── Discounts ─────────────────────────────────────────────────────────────
  //
  // Two rules shape all of it.
  //
  // **One discount per line, one on the order.** Stacking is refused rather
  // than compounded: two discounts summed onto one line cannot afterwards be
  // reported on separately, and the order in which they compound is a decision
  // nobody at a till should be making with a queue in front of them.
  //
  // **An order discount comes off what is left after the line discounts.**
  // Otherwise "20% off the order" plus "50% off one line" can between them
  // exceed the goods, and the total the database refuses to hold is the one the
  // customer was shown.

  /// Take a configured discount off one line.
  /// Charge for something that is not on the menu (§17).
  ///
  /// A delivery fee, a birthday cake somebody brought in, a corkage. It becomes
  /// an ordinary line — it is discounted, voided, taxed and printed like any
  /// other — because the only thing unusual about it is that no menu item is
  /// behind it.
  ///
  /// **The id is allocated from the ticket, and is negative.** `TicketLine`
  /// merges on the product id, so two one-off charges sharing an id would
  /// become one line reading `2×` at whichever price was typed first. Negative
  /// keeps them clear of every real menu item; per-ticket uniqueness is all
  /// that is needed, because the key never leaves the ticket.
  static TicketResult addOpenPriceLine(
    Ticket ticket, {
    required String name,
    required Money price,
    int quantity = 1,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return TicketResult.refused(const OpenItemNeedsName());
    if (price.minor < 0) return TicketResult.refused(const PriceBelowZero());
    if (quantity <= 0) return TicketResult.refused(const NothingToTender());

    // One below the lowest already here, so re-adding after a removal cannot
    // reuse an id a discount or a void is still pointing at.
    final lowest = ticket.lines
        .map((l) => l.product.id)
        .fold(0, (min, id) => id < min ? id : min);

    return addLine(
      ticket,
      Product.openPrice(id: lowest - 1, name: trimmed, price: price),
      quantity: quantity,
    );
  }

  /// Set or clear what the kitchen is told about one line.
  ///
  /// An empty note clears it — an empty string in the `note` column reads as
  /// "somebody typed something" when nobody did.
  ///
  /// No refusals beyond the line existing, and deliberately no event row. A
  /// note changes nothing about what anybody is charged, and an audit ledger
  /// that recorded every typo in "no onions" would bury the rows that matter.
  static TicketResult setLineNote(Ticket ticket, String lineKey, String note) {
    final line = ticket.lines.firstWhereOrNull((l) => l.key == lineKey);
    if (line == null) return TicketResult.refused(LineNotOnTicket(lineKey));

    final trimmed = note.trim();
    return TicketResult.ok(
      ticket.copyWith(
        lines: [
          for (final l in ticket.lines)
            if (l.key == lineKey)
              TicketLine(
                product: l.product,
                quantity: l.quantity,
                modifiers: l.modifiers,
                // Passed positionally through the constructor rather than
                // `copyWith`, because `copyWith`'s null means "leave it alone"
                // and clearing a note has to be possible.
                note: trimmed.isEmpty ? null : trimmed,
                stage: l.stage,
                roundNumber: l.roundNumber,
                voided: l.voided,
                priceOverride: l.priceOverride,
              )
            else
              l,
        ],
      ),
    );
  }

  /// Sell one line at a price somebody set by hand.
  ///
  /// [price] is the **whole unit price**, modifiers included — what the
  /// customer pays for one of these. Anything else forces the cashier to do
  /// arithmetic in their head about extras, at a counter, which is where
  /// mistakes come from.
  ///
  /// Allowed at either stage. Repricing food the kitchen has already made is a
  /// money decision, not a kitchen one, and it is exactly the case a manager
  /// reaches for when a customer complains about a dish they have eaten half of.
  ///
  /// [limit] closes the discount bypass — see [PriceBelowLimit]. Pass null when
  /// a supervisor has already approved this specific reduction, exactly as the
  /// discount sheet does.
  static TicketResult overridePrice(
    Ticket ticket,
    String lineKey,
    Money price, {
    required int by,
    required DateTime now,
    DiscountLimit? limit,
    int? reasonId,
    String? note,
    String? approvedByName,
    int? approvedByStaffId,
  }) {
    final line = ticket.lines.firstWhereOrNull((l) => l.key == lineKey);
    if (line == null) return TicketResult.refused(LineNotOnTicket(lineKey));
    if (line.isVoided) return TicketResult.refused(AlreadyVoided(lineKey));
    if (price.minor < 0) return TicketResult.refused(const PriceBelowZero());
    if (price.minor == line.unitPrice.minor) {
      return TicketResult.refused(PriceUnchanged(lineKey));
    }

    // Measured against the **menu** price, not the current one. Otherwise two
    // overrides in a row each look small while together they clear the ceiling.
    final base = line.menuUnitPrice * line.quantity;
    final reduction = base - (price * line.quantity);

    // Only a reduction is limited. Charging *more* than the menu price gives
    // nothing away, so there is no ceiling to breach — it is still recorded,
    // still reasoned, and still shows on the receipt.
    if (limit != null &&
        reduction.minor > 0 &&
        !limit.permits(base: base, amount: reduction)) {
      return TicketResult.refused(
        PriceBelowLimit(lineKey: lineKey, reduction: reduction, base: base),
      );
    }

    final override = PriceOverride(
      price: price,
      // The menu price, not whatever a previous override left behind. "Was
      // 50.00" has to mean the menu, or a second override quotes the first
      // one's discount as if it were the list price.
      original: line.menuUnitPrice,
      byStaffId: by,
      at: now,
      reasonId: reasonId,
      note: note,
      approvedByStaffId: approvedByStaffId,
      approvedByName: approvedByName,
    );

    return TicketResult.ok(
      ticket.copyWith(
        lines: [
          for (final l in ticket.lines)
            if (l.key == lineKey) l.copyWith(priceOverride: override) else l,
        ],
        lineEvents: [
          ...ticket.lineEvents,
          TicketLineEvent(
            lineKey: lineKey,
            event: TicketLineEventKind.priceOverridden,
            staffId: by,
            at: now,
            unitPriceBefore: line.unitPrice.minor,
            unitPriceAfter: price.minor,
            reasonId: reasonId,
            note: note,
            approvedByStaffId: approvedByStaffId,
          ),
        ],
      ),
    );
  }

  /// Put a repriced line back on the menu price.
  ///
  /// Recorded as another `price_overridden` event rather than by deleting the
  /// first. The ledger says what happened, in order; a correction that erased
  /// its predecessor would let somebody reprice, sell, and tidy up after.
  static TicketResult clearPriceOverride(
    Ticket ticket,
    String lineKey, {
    required int by,
    required DateTime now,
  }) {
    final line = ticket.lines.firstWhereOrNull((l) => l.key == lineKey);
    if (line == null) return TicketResult.refused(LineNotOnTicket(lineKey));
    if (!line.isRepriced) return TicketResult.refused(PriceUnchanged(lineKey));

    return TicketResult.ok(
      ticket.copyWith(
        lines: [
          for (final l in ticket.lines)
            if (l.key == lineKey)
              l.copyWith(clearPriceOverride: true)
            else
              l,
        ],
        lineEvents: [
          ...ticket.lineEvents,
          TicketLineEvent(
            lineKey: lineKey,
            event: TicketLineEventKind.priceOverridden,
            staffId: by,
            at: now,
            unitPriceBefore: line.unitPrice.minor,
            unitPriceAfter: line.menuUnitPrice.minor,
          ),
        ],
      ),
    );
  }

  static TicketResult applyLineDiscount(
    Ticket ticket,
    String lineKey,
    Discount discount, {
    required DateTime now,
    required int appliedBy,
    DiscountLimit? limit,
    bool hasCustomer = false,
    int? reasonId,
    String? note,
    String? approvedByName,
    int? approvedByStaffId,
  }) {
    final line = ticket.lines.firstWhereOrNull((l) => l.key == lineKey);
    if (line == null) return TicketResult.refused(LineNotOnTicket(lineKey));

    final existing = ticket.discountOnLine(lineKey);
    if (existing != null) return TicketResult.refused(AlreadyDiscounted(existing));

    final refusal = _offered(
      discount,
      ticket: ticket,
      now: now,
      hasCustomer: hasCustomer,
      base: line.lineTotal,
      productId: line.product.id,
      categoryId: line.product.categoryId,
    );
    if (refusal != null) return TicketResult.refused(refusal);

    return _apply(
      ticket,
      base: line.lineTotal,
      amount: discount.amountOn(line.lineTotal),
      lineKey: lineKey,
      discount: discount,
      appliedBy: appliedBy,
      limit: limit,
      reasonId: reasonId,
      note: note,
      approvedByName: approvedByName,
      approvedByStaffId: approvedByStaffId,
    );
  }

  /// Take a configured discount off the whole bill.
  static TicketResult applyOrderDiscount(
    Ticket ticket,
    Discount discount, {
    required DateTime now,
    required int appliedBy,
    DiscountLimit? limit,
    bool hasCustomer = false,
    int? reasonId,
    String? note,
    String? approvedByName,
    int? approvedByStaffId,
  }) {
    final existing = ticket.orderDiscounts.firstOrNull;
    if (existing != null) return TicketResult.refused(AlreadyDiscounted(existing));

    final base = _orderDiscountBase(ticket);
    final refusal = _offered(
      discount,
      ticket: ticket,
      now: now,
      hasCustomer: hasCustomer,
      base: base,
    );
    if (refusal != null) return TicketResult.refused(refusal);

    return _apply(
      ticket,
      base: base,
      amount: discount.amountOn(base),
      lineKey: null,
      discount: discount,
      appliedBy: appliedBy,
      limit: limit,
      reasonId: reasonId,
      note: note,
      approvedByName: approvedByName,
      approvedByStaffId: approvedByStaffId,
    );
  }

  /// A discount a person typed rather than one the restaurant configured.
  ///
  /// SRS §16 `DISCOUNT.CUSTOM_VALUE`. It carries no `discountId` — there is no
  /// configuration behind it — and everything about it therefore has to be
  /// snapshotted, which the applied record does anyway.
  static TicketResult applyCustomDiscount(
    Ticket ticket, {
    required String name,
    required DiscountKind kind,
    required int appliedBy,
    int? valueBp,
    Money? valueMinor,
    String? lineKey,
    DiscountLimit? limit,
    int? reasonId,
    String? note,
    String? approvedByName,
    int? approvedByStaffId,
  }) {
    final Money base;
    if (lineKey == null) {
      final existing = ticket.orderDiscounts.firstOrNull;
      if (existing != null) {
        return TicketResult.refused(AlreadyDiscounted(existing));
      }
      base = _orderDiscountBase(ticket);
    } else {
      final line = ticket.lines.firstWhereOrNull((l) => l.key == lineKey);
      if (line == null) return TicketResult.refused(LineNotOnTicket(lineKey));
      final existing = ticket.discountOnLine(lineKey);
      if (existing != null) {
        return TicketResult.refused(AlreadyDiscounted(existing));
      }
      base = line.lineTotal;
    }

    if (base.isZero) return const TicketResult.refused(NothingToDiscount());

    // Priced through the same path a configured discount takes, so a typed 15%
    // and a configured 15% cannot round differently.
    final raw = switch (kind) {
      DiscountKind.percentage => base.percentBp(valueBp ?? 0),
      DiscountKind.fixed => valueMinor ?? base.copyWith(minor: 0),
    };
    final amount = raw.minor > base.minor ? base : raw;

    return _apply(
      ticket,
      base: base,
      amount: amount,
      lineKey: lineKey,
      nameSnapshot: name,
      kind: kind,
      valueBp: valueBp,
      valueMinor: valueMinor,
      appliedBy: appliedBy,
      limit: limit,
      reasonId: reasonId,
      note: note,
      approvedByName: approvedByName,
      approvedByStaffId: approvedByStaffId,
    );
  }

  /// Take a discount back off. [lineKey] null removes the order-level one.
  static Ticket removeDiscount(Ticket ticket, {String? lineKey}) =>
      ticket.copyWith(
        discounts: ticket.discounts
            .where((d) => d.lineKey != lineKey)
            .toList(),
      );

  /// What an order-level discount comes off: the goods, less anything already
  /// taken off individual lines.
  static Money _orderDiscountBase(Ticket ticket) {
    final subtotal = ticket.lines.fold(
      Money(0, currency: ticket.currency, exponent: ticket.exponent),
      (sum, line) => sum + line.lineTotal,
    );
    final lineDiscounts = ticket.lineDiscounts.fold(
      Money(0, currency: ticket.currency, exponent: ticket.exponent),
      (sum, d) => sum + d.amount,
    );
    return (subtotal - lineDiscounts).clampToZero();
  }

  /// Why this discount is not on offer here, or null if it is.
  static TicketRefusal? _offered(
    Discount discount, {
    required Ticket ticket,
    required DateTime now,
    required bool hasCustomer,
    required Money base,
    int? productId,
    int? categoryId,
  }) {
    if (base.isZero) return const NothingToDiscount();
    if (!discount.isLiveAt(now)) return DiscountNotOffered(discount);
    if (!discount.targets.allowsOrderType(ticket.orderType)) {
      return DiscountNotOffered(discount);
    }
    if (productId != null &&
        categoryId != null &&
        !discount.targets.allowsProduct(
          productId: productId,
          categoryId: categoryId,
        )) {
      return DiscountNotOffered(discount);
    }
    final minimum = discount.minOrder;
    if (minimum != null && base.minor < minimum.minor) {
      return DiscountNotOffered(discount);
    }
    if (discount.requiresCustomer && !hasCustomer) {
      return DiscountRequiresCustomer(discount);
    }
    return null;
  }

  /// The last step every path shares: check the ceiling, then record it.
  static TicketResult _apply(
    Ticket ticket, {
    required Money base,
    required Money amount,
    required String? lineKey,
    required int appliedBy,
    Discount? discount,
    String? nameSnapshot,
    DiscountKind? kind,
    int? valueBp,
    Money? valueMinor,
    DiscountLimit? limit,
    int? reasonId,
    String? note,
    String? approvedByName,
    int? approvedByStaffId,
  }) {
    if (amount.isZero) return const TicketResult.refused(NothingToDiscount());

    // Skipped entirely once a supervisor has approved: the caller passes no
    // limit on the second attempt, which is what "lent for this one action"
    // means.
    if (limit != null && !limit.permits(base: base, amount: amount)) {
      return TicketResult.refused(
        DiscountAboveLimit(limit: limit, requested: amount, base: base),
      );
    }

    return TicketResult.ok(
      ticket.copyWith(
        discounts: [
          ...ticket.discounts,
          AppliedDiscount(
            discountId: discount?.id,
            lineKey: lineKey,
            nameSnapshot: nameSnapshot ?? discount!.nameEn,
            kind: kind ?? discount!.kind,
            valueBp: valueBp ?? discount?.valueBp,
            valueMinor: valueMinor ?? discount?.valueMinor,
            amount: amount,
            appliedByStaffId: appliedBy,
            reasonId: reasonId,
            note: note,
            approvedByName: approvedByName,
            approvedByStaffId: approvedByStaffId,
          ),
        ],
      ),
    );
  }

  /// Discard everything. Used by "Void ticket" and by starting a new sale.
  static Ticket clear(Ticket ticket, {required String newId}) => Ticket(
    id: newId,
    orderType: ticket.orderType,
    taxConfig: ticket.taxConfig,
    currency: ticket.currency,
    exponent: ticket.exponent,
  );
}
