import '../../core/money/money.dart';
import '../models/catalog.dart';
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
      lines.add(TicketLine(
        product: product,
        quantity: quantity,
        modifiers: modifiers,
        note: note,
      ));
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

  /// Fire the draft to the kitchen. Draft becomes sent; the table stays open.
  static Ticket sendRound(Ticket ticket) {
    if (!ticket.hasDraft) return ticket;

    final round = ticket.roundsSent + 1;
    return ticket.copyWith(
      roundsSent: round,
      lines: ticket.lines
          .map((l) => l.stage == LineStage.draft
              ? l.copyWith(stage: LineStage.sent, roundNumber: round)
              : l)
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
  }) =>
      ticket.copyWith(
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

    return TicketResult.ok(ticket.copyWith(
      tenders: [
        ...ticket.tenders,
        Tender(typeId: typeId, label: label, amount: value, reference: reference),
      ],
    ));
  }

  static Ticket removeTenderAt(Ticket ticket, int index) {
    if (index < 0 || index >= ticket.tenders.length) return ticket;

    final tenders = [...ticket.tenders]..removeAt(index);
    return ticket.copyWith(tenders: tenders);
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
