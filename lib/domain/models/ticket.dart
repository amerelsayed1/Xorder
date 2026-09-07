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
  });

  final Product product;
  final int quantity;
  final List<Modifier> modifiers;
  final String? note;
  final LineStage stage;
  final int? roundNumber;

  /// Merge key. Sorted so selection order never splits a line.
  static String keyFor(Product product, List<Modifier> modifiers) {
    final ids = modifiers.map((m) => m.id).toList()..sort();
    return '${product.id}:${ids.join(",")}';
  }

  String get key => keyFor(product, modifiers);

  /// Price of one unit including its modifiers. Exact integer arithmetic.
  Money get unitPrice => modifiers.fold(
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
  }) => TicketLine(
    product: product,
    quantity: quantity ?? this.quantity,
    modifiers: modifiers,
    note: note ?? this.note,
    stage: stage ?? this.stage,
    roundNumber: roundNumber ?? this.roundNumber,
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

  final TaxConfig taxConfig;
  final String currency;
  final int exponent;
  final int roundsSent;

  Money get _zero => Money(0, currency: currency, exponent: exponent);

  List<TicketLine> get draftLines =>
      lines.where((l) => l.stage == LineStage.draft).toList();

  List<TicketLine> get sentLines =>
      lines.where((l) => l.stage == LineStage.sent).toList();

  bool get isEmpty => lines.isEmpty;
  bool get hasDraft => draftLines.isNotEmpty;

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
    final subtotal = lines.fold(_zero, (sum, line) => sum + line.lineTotal);
    final discount = discounts.fold(_zero, (sum, d) => sum + d.amount);

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
    taxConfig: taxConfig ?? this.taxConfig,
    currency: currency,
    exponent: exponent,
    roundsSent: roundsSent ?? this.roundsSent,
  );
}
