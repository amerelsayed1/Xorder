import 'package:collection/collection.dart';

import '../../core/money/money.dart';
import 'catalog.dart';
import 'discount.dart';

/// The order types the till can sell. Which of these are *offered* comes from
/// `branch.supported_order_types` (POS-BE-005) — never hardcoded on screen.
enum OrderType {
  dineIn('dine_in'),
  takeaway('takeaway'),
  delivery('delivery'),
  driveThru('drive_thru');

  /// No display label here on purpose: the ticket is pure domain, and the words
  /// for these belong to whichever language the till speaks. See
  /// `app/labels.dart`.
  const OrderType(this.wire);

  final String wire;

  /// Wire values that mean one of these by another name.
  ///
  /// The platform has two vocabularies for the same idea: the onboarding
  /// wizard and the plan features say `pickup`, the POS says `takeaway`.
  /// They are the same act — a customer collecting food — and a branch
  /// onboarded through the wizard must not lose its takeaway tab because two
  /// screens disagree about a word. Same tolerance `DeploymentMode.fromWire`
  /// already applies to its own legacy names.
  static const _synonyms = <String, OrderType>{
    'pickup': OrderType.takeaway,
    'take_away': OrderType.takeaway,
    'dinein': OrderType.dineIn,
    'drivethru': OrderType.driveThru,
    'drive_through': OrderType.driveThru,
  };

  static OrderType? fromWire(String value) =>
      OrderType.values.firstWhereOrNull((t) => t.wire == value) ??
      _synonyms[value];
}

/// Whether a line has been fired to the kitchen yet.
enum LineStage { draft, sent }

/// A line that was thrown away after the kitchen had already made it.
///
/// **Only ever set on a sent line.** Removing something before it is fired is
/// housekeeping and leaves no trace on the bill; voiding one after it is cooked
/// is waste with a cost attached, and the two must not be recorded as the same
/// act — that distinction is the whole reason this type exists rather than a
/// boolean.
class LineVoid {
  const LineVoid({
    required this.byStaffId,
    required this.at,
    this.reasonId,
    this.note,
    this.approvedByStaffId,
    this.approvedByName,
  });

  final int byStaffId;
  final DateTime at;
  final int? reasonId;
  final String? note;

  /// Set when the person doing it needed a supervisor to lend the permission.
  final int? approvedByStaffId;
  final String? approvedByName;
}

/// What happened to a line, for the record.
///
/// Accumulated on the ticket and written to `pos_order_line_events` at
/// settlement. It has to ride the ticket rather than be written as it happens,
/// because a line cancelled before the first round is sent belongs to an order
/// row that does not exist yet — which is exactly why the table keys on
/// `line_key` rather than a line id.
/// A line sold at a price that is not the menu price.
///
/// A snapshot, like [LineVoid] — it carries the price that was replaced as well
/// as the one that replaced it, because "was 50.00, now 40.00" is the sentence
/// a receipt and an audit both need, and the menu price will have moved on by
/// the time anybody asks.
///
/// It overrides the **whole unit price**, modifiers folded in. That is what a
/// cashier means by "make it 40": the customer pays 40 for that item, not 40
/// plus whatever the extras came to.
class PriceOverride {
  const PriceOverride({
    required this.price,
    required this.original,
    required this.byStaffId,
    required this.at,
    this.reasonId,
    this.note,
    this.approvedByStaffId,
    this.approvedByName,
  });

  /// What the customer pays per unit now.
  final Money price;

  /// What they would have paid. Kept so the cart can strike it through and the
  /// ledger can say what the change was worth.
  final Money original;

  final int byStaffId;
  final DateTime at;
  final int? reasonId;
  final String? note;

  /// Set when the reduction was past the person's limit and a supervisor lent
  /// the permission. Both names on the record, as everywhere else.
  final int? approvedByStaffId;
  final String? approvedByName;

  /// What the restaurant gave up, per unit. Negative when the price went *up*,
  /// which is legitimate and rare.
  Money get reduction => original - price;
}

class TicketLineEvent {
  const TicketLineEvent({
    required this.lineKey,
    required this.event,
    required this.staffId,
    required this.at,
    this.quantityBefore,
    this.quantityAfter,
    this.unitPriceBefore,
    this.unitPriceAfter,
    this.reasonId,
    this.note,
    this.approvedByStaffId,
  });

  final String lineKey;

  /// One of the values `pos_order_line_events.event` allows. A string this
  /// build invents that the CHECK constraint does not know would fail the whole
  /// settlement transaction, which is why it is only ever set from
  /// [TicketLineEventKind].
  final String event;

  final int staffId;
  final DateTime at;
  final int? quantityBefore;
  final int? quantityAfter;

  /// Minor units, and only on a `price_overridden` event. Migration 9
  /// provisioned both columns for exactly this.
  final int? unitPriceBefore;
  final int? unitPriceAfter;

  final int? reasonId;
  final String? note;
  final int? approvedByStaffId;
}

/// The events this build writes. Mirrors migration 9's CHECK constraint.
abstract final class TicketLineEventKind {
  static const removedBeforeSend = 'removed_before_send';
  static const voidedAfterSend = 'voided_after_send';
  static const priceOverridden = 'price_overridden';
}

/// One line on a ticket.
///
/// The line *key* — product id plus sorted modifier ids — is what merges
/// quantities. Two "Mixed Grill, medium, extra bread" become `2×`; the same
/// product with different modifiers stays a separate line.
class TicketLine {
  TicketLine({
    required this.product,
    required this.quantity,
    this.modifiers = const [],
    this.note,
    this.stage = LineStage.draft,
    this.roundNumber,
    this.voided,
    this.priceOverride,
  });

  final Product product;
  final int quantity;
  final List<Modifier> modifiers;
  final String? note;
  final LineStage stage;
  final int? roundNumber;

  /// Non-null once this line has been voided. The line **stays on the ticket**
  /// — see `Ticket.totals` for what that costs, and the cart panel for why.
  final LineVoid? voided;

  /// Non-null when this line is being sold at a price somebody set by hand.
  final PriceOverride? priceOverride;

  bool get isVoided => voided != null;
  bool get isRepriced => priceOverride != null;

  /// Merge key. Sorted so selection order never splits a line.
  static String keyFor(Product product, List<Modifier> modifiers) {
    final ids = modifiers.map((m) => m.id).toList()..sort();
    return '${product.id}:${ids.join(",")}';
  }

  String get key => keyFor(product, modifiers);

  /// Price of one unit including its modifiers. Exact integer arithmetic.
  ///
  /// An override replaces the whole figure rather than adjusting it, so adding
  /// a modifier to a repriced line does not quietly walk the price back up
  /// past what was agreed.
  Money get unitPrice => priceOverride?.price ?? menuUnitPrice;

  /// What this line would cost at menu prices. Struck through in the cart when
  /// [priceOverride] is set, and the base a limit is measured against.
  Money get menuUnitPrice => modifiers.fold(
    product.effectivePrice,
    (total, modifier) => total + modifier.priceDelta,
  );

  Money get lineTotal => unitPrice * quantity;

  String modifierSummary(String locale) =>
      modifiers.map((m) => m.displayName(locale)).join(' · ');

  TicketLine copyWith({
    int? quantity,
    LineStage? stage,
    int? roundNumber,
    String? note,
    LineVoid? voided,
    PriceOverride? priceOverride,
    /// Put the line back on the menu price. Needed as a flag because null in
    /// [priceOverride] already means "leave it alone", and every other
    /// `copyWith` here reads the same way.
    bool clearPriceOverride = false,
  }) => TicketLine(
    product: product,
    quantity: quantity ?? this.quantity,
    modifiers: modifiers,
    note: note ?? this.note,
    stage: stage ?? this.stage,
    roundNumber: roundNumber ?? this.roundNumber,
    voided: voided ?? this.voided,
    priceOverride: clearPriceOverride
        ? null
        : (priceOverride ?? this.priceOverride),
  );
}

/// A tender taken against a ticket. Split payment is n of these.
class Tender {
  const Tender({
    required this.typeId,
    required this.label,
    required this.amount,
    this.reference,
  });

  final int typeId;
  final String label;
  final Money amount;

  /// Card auth code for a payment taken on a standalone bank terminal. The POS
  /// is not a payment processor and stores no card data.
  final String? reference;
}

/// Tax and service configuration.
///
/// **This is read-only device config until POS-BE-013 is `READY`.** The server
/// must become the author of tax; a till that invents its own tax rate produces
/// numbers nobody can audit. Every receipt printed from device config says so.
class TaxConfig {
  const TaxConfig({
    this.serviceBp = 1200,
    this.vatBp = 1400,
    this.serviceDineInOnly = true,
    this.source = TaxSource.deviceConfig,
  });

  /// Service charge in basis points — 1200 = 12%.
  final int serviceBp;

  /// VAT in basis points — 1400 = 14%. Applied to subtotal + service.
  final int vatBp;
  final bool serviceDineInOnly;
  final TaxSource source;

  bool appliesServiceTo(OrderType type) =>
      !serviceDineInOnly || type == OrderType.dineIn;

  /// Value equality, because callers compare configurations to decide whether
  /// anything actually changed — and an identity comparison there would
  /// rewrite a live ticket on every sync pass.
  @override
  bool operator ==(Object other) =>
      other is TaxConfig &&
      other.serviceBp == serviceBp &&
      other.vatBp == vatBp &&
      other.serviceDineInOnly == serviceDineInOnly &&
      other.source == source;

  @override
  int get hashCode => Object.hash(serviceBp, vatBp, serviceDineInOnly, source);
}

enum TaxSource {
  /// Local, read-only, provisional. Receipts must disclose this.
  deviceConfig,

  /// Authored by the server via `GET /api/pos/config` (POS-BE-013).
  server,
}

/// Computed money for a ticket. Pure data — no widget builds this itself.
class TicketTotals {
  const TicketTotals({
    required this.subtotal,
    required this.service,
    required this.vat,
    required this.total,
    required this.paid,
    required this.due,
    required this.change,
    this.discount = const Money(0),
  });

  final Money subtotal;

  /// Everything taken off, line discounts and order discounts together.
  ///
  /// Always positive, never a negative subtotal: a discount is its own line on
  /// a receipt and folding it into the goods would make it unauditable.
  final Money discount;

  /// [subtotal] less [discount] — what the food actually came to.
  ///
  /// **This, not [subtotal], is what service and tax are charged on.** See
  /// `Ticket.totals` for why.
  Money get net => subtotal - discount;

  final Money service;
  final Money vat;
  final Money total;
  final Money paid;

  /// What is still owed. Never negative — overpayment is `change`.
  final Money due;
  final Money change;

  bool get isSettled => due.isZero || due.isNegative;
}

/// The whole ticket. Immutable; every mutation returns a new instance, which is
/// what makes the engine testable without a widget tree.
class Ticket {
  Ticket({
    required this.id,
    required this.orderType,
    this.tableId,
    this.tableLabel,
    this.guestCount,
    this.lines = const [],
    this.tenders = const [],
    this.discounts = const [],
    this.lineEvents = const [],
    this.taxConfig = const TaxConfig(),
    this.currency = 'EGP',
    this.exponent = 2,
    this.roundsSent = 0,
  });

  /// Client-generated. This is the `client_transaction_id` the server will
  /// deduplicate on (POS-BE-007) — generated at commit time, not sync time, so
  /// a retry after a timeout carries the same key.
  final String id;
  final OrderType orderType;
  final int? tableId;
  final String? tableLabel;
  final int? guestCount;
  final List<TicketLine> lines;
  final List<Tender> tenders;

  /// What has been taken off, each one a snapshot of the discount as applied.
  ///
  /// One list rather than a field on [TicketLine], because an order-level
  /// discount belongs to no line and putting it on one would be a lie about
  /// what it came off. [AppliedDiscount.lineKey] carries the association.
  final List<AppliedDiscount> discounts;

  /// What has happened to the lines, in order, for `pos_order_line_events`.
  ///
  /// Append-only in practice: nothing removes an event, because the record of a
  /// line being cancelled is not itself cancellable.
  final List<TicketLineEvent> lineEvents;

  final TaxConfig taxConfig;
  final String currency;
  final int exponent;
  final int roundsSent;

  Money get _zero => Money(0, currency: currency, exponent: exponent);

  List<TicketLine> get draftLines =>
      lines.where((l) => l.stage == LineStage.draft).toList();

  List<TicketLine> get sentLines =>
      lines.where((l) => l.stage == LineStage.sent).toList();

  /// The lines that are actually being charged for.
  ///
  /// A voided line stays on the ticket so the cashier can show a customer what
  /// happened to it, and is excluded from every total — those two facts
  /// together are the whole point of voiding rather than deleting.
  List<TicketLine> get chargeableLines =>
      lines.where((l) => !l.isVoided).toList();

  bool get isEmpty => lines.isEmpty;

  /// Nothing left that anybody owes for. A ticket of nothing but voided lines
  /// is not an empty ticket — it is a record — but there is nothing to charge.
  bool get hasNothingToCharge => chargeableLines.isEmpty;

  bool get hasDraft => draftLines.any((l) => !l.isVoided);

  /// A seated table shows "Close table"; everything else shows "Charge".
  bool get isSeated => orderType == OrderType.dineIn && tableId != null;

  /// Totals over **every** line, sent and draft alike — the bill is the whole
  /// visit, not the current round.
  ///
  /// **Service and tax are charged on the discounted goods, not the gross.**
  /// That is the one judgement in this method and it is worth stating: if
  /// service were taken on `subtotal`, a fully comped meal would still charge
  /// 12% service and VAT on top of it, and the customer would be handed a bill
  /// for food the restaurant gave away. Discounting the food discounts what is
  /// charged on the food.
  ///
  /// Rounding is still applied **once per charge line** — service and VAT —
  /// which is what keeps the parts footing to the whole.
  TicketTotals get totals {
    final chargeable = chargeableLines;
    final subtotal = chargeable.fold(_zero, (sum, line) => sum + line.lineTotal);

    // A discount on a line that was later voided comes off with it. Leaving it
    // in would credit the customer for something they are no longer being
    // charged for — money off nothing.
    final live = {for (final line in chargeable) line.key};
    final discount = discounts
        .where((d) => d.lineKey == null || live.contains(d.lineKey))
        .fold(_zero, (sum, d) => sum + d.amount);

    // Clamped, not trusted. Nothing in the engine can build a ticket whose
    // discounts exceed its goods, but a ticket rebuilt from a parked payload
    // written by an older build could, and a negative net would propagate into
    // a negative tax and a receipt nobody can read.
    final net = (subtotal - discount).clampToZero();

    final service = taxConfig.appliesServiceTo(orderType)
        ? net.percentBp(taxConfig.serviceBp)
        : _zero;

    final vat = (net + service).percentBp(taxConfig.vatBp);
    final total = net + service + vat;
    final paid = tenders.fold(_zero, (sum, tender) => sum + tender.amount);
    final balance = total - paid;

    return TicketTotals(
      subtotal: subtotal,
      discount: subtotal.minor < discount.minor ? subtotal : discount,
      service: service,
      vat: vat,
      total: total,
      paid: paid,
      due: balance.clampToZero(),
      change: balance.isNegative ? -balance : _zero,
    );
  }

  /// Discounts already on this ticket, line-level and order-level together.
  List<AppliedDiscount> get lineDiscounts =>
      discounts.where((d) => !d.isOrderLevel).toList();

  List<AppliedDiscount> get orderDiscounts =>
      discounts.where((d) => d.isOrderLevel).toList();

  /// The discount sitting on [lineKey], if any.
  AppliedDiscount? discountOnLine(String lineKey) =>
      discounts.firstWhereOrNull((d) => d.lineKey == lineKey);

  Ticket copyWith({
    OrderType? orderType,
    int? tableId,
    String? tableLabel,
    int? guestCount,
    List<TicketLine>? lines,
    List<Tender>? tenders,
    List<AppliedDiscount>? discounts,
    List<TicketLineEvent>? lineEvents,
    TaxConfig? taxConfig,
    int? roundsSent,
    bool clearTable = false,
  }) => Ticket(
    id: id,
    orderType: orderType ?? this.orderType,
    tableId: clearTable ? null : (tableId ?? this.tableId),
    tableLabel: clearTable ? null : (tableLabel ?? this.tableLabel),
    guestCount: clearTable ? null : (guestCount ?? this.guestCount),
    lines: lines ?? this.lines,
    tenders: tenders ?? this.tenders,
    discounts: discounts ?? this.discounts,
    lineEvents: lineEvents ?? this.lineEvents,
    taxConfig: taxConfig ?? this.taxConfig,
    currency: currency,
    exponent: exponent,
    roundsSent: roundsSent ?? this.roundsSent,
  );
}
