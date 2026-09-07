import '../../core/money/money.dart';
import 'ticket.dart';

/// How a discount is worked out.
enum DiscountKind {
  /// A share of what it applies to, in basis points — 1250 is 12.5%.
  percentage('percentage'),

  /// A flat amount off, in minor units.
  fixed('fixed');

  const DiscountKind(this.wire);

  final String wire;

  static DiscountKind? fromWire(String value) {
    for (final kind in DiscountKind.values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// What a discount comes off.
enum DiscountScope {
  /// The whole bill. Renders in the totals block, never inside a line.
  order('order'),

  /// One line. Renders as a child row of that line, naming its approver.
  item('item');

  const DiscountScope(this.wire);

  final String wire;

  static DiscountScope? fromWire(String value) {
    for (final scope in DiscountScope.values) {
      if (scope.wire == value) return scope;
    }
    return null;
  }
}

/// What a configured discount may be applied to.
///
/// **No targets means everything.** That reading is deliberate and matches the
/// licence's `modes[]`: parsing an absent restriction into an empty set and
/// then matching nothing would make every newly-created discount silently
/// inapplicable, with no way for a manager to tell why.
class DiscountTargets {
  const DiscountTargets({
    this.categoryIds = const {},
    this.productIds = const {},
    this.orderTypes = const {},
  });

  final Set<int> categoryIds;
  final Set<int> productIds;
  final Set<OrderType> orderTypes;

  bool get isUnrestricted =>
      categoryIds.isEmpty && productIds.isEmpty && orderTypes.isEmpty;

  bool allowsOrderType(OrderType type) =>
      orderTypes.isEmpty || orderTypes.contains(type);

  /// Whether a line selling [productId] from [categoryId] is in scope.
  ///
  /// Product and category are checked **independently**, and either one
  /// matching is enough: "10% off Grills" and "10% off the Mixed Grill" are
  /// both things a restaurant says, and a discount naming both means either.
  bool allowsProduct({required int productId, required int categoryId}) {
    if (categoryIds.isEmpty && productIds.isEmpty) return true;
    return productIds.contains(productId) || categoryIds.contains(categoryId);
  }
}

/// A discount the restaurant offers, as configured.
///
/// Distinct from [AppliedDiscount], which is what was actually taken off a
/// sale. This one is editable and may change tomorrow; that one is a snapshot
/// and may not.
class Discount {
  const Discount({
    required this.id,
    required this.code,
    required this.nameEn,
    required this.kind,
    required this.scope,
    this.nameAr,
    this.valueBp,
    this.valueMinor,
    this.minOrder,
    this.maxDiscount,
    this.startsAt,
    this.endsAt,
    this.daysOfWeek = const {},
    this.timeFrom,
    this.timeTo,
    this.requiresCustomer = false,
    this.requiresManager = false,
    this.isRestricted = false,
    this.isActive = true,
    this.targets = const DiscountTargets(),
    this.revision = 1,
  });

  final int id;

  /// Stable and machine-readable. Renaming a promotion must not change what a
  /// year of reports groups on.
  final String code;

  final String nameEn;
  final String? nameAr;
  final DiscountKind kind;
  final DiscountScope scope;

  /// Set for [DiscountKind.percentage], in basis points.
  final int? valueBp;

  /// Set for [DiscountKind.fixed].
  final Money? valueMinor;

  final Money? minOrder;

  /// The ceiling on a percentage — "20% off, up to 50 EGP".
  final Money? maxDiscount;

  final DateTime? startsAt;
  final DateTime? endsAt;

  /// ISO-8601 day numbers, 1 = Monday. Empty means every day.
  final Set<int> daysOfWeek;

  /// Minutes past midnight, so a window is comparable without a date. A window
  /// that wraps — 22:00 to 02:00 — is legitimate and handled by [isLiveAt].
  final int? timeFrom;
  final int? timeTo;

  final bool requiresCustomer;
  final bool requiresManager;

  /// Hidden from the ordinary list; needs `discount.apply_restricted`.
  final bool isRestricted;

  final bool isActive;
  final DiscountTargets targets;
  final int revision;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// Whether this discount is being offered at [now].
  ///
  /// Pure, and takes the time rather than reading a clock, because a till that
  /// decides what it offers from `DateTime.now()` inside a widget is a till
  /// nobody can write a test for.
  bool isLiveAt(DateTime now) {
    if (!isActive) return false;
    if (startsAt != null && now.isBefore(startsAt!)) return false;
    if (endsAt != null && !now.isBefore(endsAt!)) return false;
    if (daysOfWeek.isNotEmpty && !daysOfWeek.contains(now.weekday)) return false;

    final from = timeFrom;
    final to = timeTo;
    if (from == null || to == null) return true;

    final minutes = now.hour * 60 + now.minute;
    // A window that does not wrap is the ordinary case; one that does is a
    // late-night offer, and treating `from > to` as a mistake would quietly
    // switch those off between midnight and closing.
    return from <= to
        ? minutes >= from && minutes < to
        : minutes >= from || minutes < to;
  }

  /// What this comes to against [base], before any permission limit.
  ///
  /// [maxDiscount] is applied here rather than at the call site, because it is
  /// part of what the discount *is* — a caller that forgot it would charge a
  /// customer less than the restaurant agreed to.
  ///
  /// Never more than [base]: a discount larger than the thing it comes off is
  /// a negative sale, and the database refuses to hold one.
  Money amountOn(Money base) {
    final raw = switch (kind) {
      DiscountKind.percentage => base.percentBp(valueBp ?? 0),
      DiscountKind.fixed => valueMinor ?? base.copyWith(minor: 0),
    };

    final capped = maxDiscount != null && raw.minor > maxDiscount!.minor
        ? base.copyWith(minor: maxDiscount!.minor)
        : raw;

    return capped.minor > base.minor ? base : capped;
  }
}

/// How much a person may take off by hand before a supervisor is needed.
///
/// SRS §16: *"Cashier 10%, Manager 30%, Owner unlimited."* This is a **limit,
/// not a permission** — exceeding it is not a refusal but a manager-approval
/// prompt, and the same discount succeeds once somebody has approved it.
///
/// Null in either field means **unlimited**, never zero. Reading a missing cap
/// as zero would leave a role that nobody has configured unable to discount
/// anything, which is the opposite of what "not configured" means. A deliberate
/// zero is a real and different answer: *may not discount at all*.
class DiscountLimit {
  const DiscountLimit({this.maxBp, this.maxAmount});

  /// No ceiling of any kind. What an owner holds.
  static const unlimited = DiscountLimit();

  /// The largest share of the base this person may give away.
  final int? maxBp;

  /// The largest cash value, whatever the percentage works out to.
  final Money? maxAmount;

  bool get isUnlimited => maxBp == null && maxAmount == null;

  /// Whether [amount] off [base] is within this ceiling.
  ///
  /// **Both ceilings apply to every discount, whatever its kind.** A cashier
  /// capped at 10% who reaches for a fixed 50 EGP off a 100 EGP order is asking
  /// for 50%, and checking `maxBp` only against percentage discounts would make
  /// the cap trivially avoidable by picking the other kind — which is precisely
  /// what somebody working around a limit would do.
  ///
  /// The percentage comparison is cross-multiplied rather than divided, so
  /// there is no rounding step to sit on the boundary: at exactly the limit it
  /// is permitted, one piastre over it is not.
  bool permits({required Money base, required Money amount}) {
    final cap = maxAmount;
    if (cap != null && amount.minor > cap.minor) return false;

    final bp = maxBp;
    if (bp == null) return true;
    // A discount off nothing is nothing, and no percentage of zero exceeds a
    // limit — guarding here keeps the comparison below from dividing by it.
    if (base.minor <= 0) return amount.minor <= 0;

    return amount.minor * 10000 <= bp * base.minor;
  }
}

/// A discount as it was taken off a sale.
///
/// **Everything here is a snapshot.** A restaurant that renames "Staff meal" or
/// moves 10% to 15% must not thereby rewrite what a customer was charged in
/// March — the same rule `TicketLine`'s stored name and price already follow.
class AppliedDiscount {
  const AppliedDiscount({
    required this.nameSnapshot,
    required this.kind,
    required this.amount,
    required this.appliedByStaffId,
    this.discountId,
    this.lineKey,
    this.valueBp,
    this.valueMinor,
    this.reasonId,
    this.note,
    this.approvedByName,
    this.approvedByStaffId,
  });

  /// Who took the money off.
  ///
  /// Carried on the record rather than looked up when it is written, because
  /// the person applying a discount is known at the moment they apply it and
  /// not afterwards — a repository asking "who is signed in?" at settlement
  /// would name whoever is standing there when the bill is paid, which on a
  /// dine-in table is often somebody else entirely.
  ///
  /// Zero means unattributed, and can only arise from a payload that was
  /// hand-edited: nothing in this build writes a discount without a person.
  final int appliedByStaffId;

  /// Kept for reporting. Null when the discount it came from has since been
  /// deleted — which is exactly why the name is snapshotted beside it.
  final int? discountId;

  /// Which line this came off, or **null for the whole order**.
  ///
  /// The distinction is load-bearing on screen as well as in the ledger: a line
  /// discount renders inside its line in the cart, an order discount renders in
  /// the totals block.
  final String? lineKey;

  final String nameSnapshot;
  final DiscountKind kind;
  final int? valueBp;
  final Money? valueMinor;

  /// What it actually came to. This is the number that reduces the bill; the
  /// value above is only how it was worked out.
  final Money amount;

  final int? reasonId;
  final String? note;

  /// The supervisor who lent the permission, when the discount was above the
  /// applier's limit. Snapshotted for the same reason the name is.
  final String? approvedByName;

  /// The same person, by id, for the ledger.
  ///
  /// Both, and neither is redundant. The **name** survives that person being
  /// renamed or deleted, which is what a receipt and a parked ticket need. The
  /// **id** is what "every discount Hana approved last month" joins on, and a
  /// report cannot join on a string somebody has since edited.
  final int? approvedByStaffId;

  bool get isOrderLevel => lineKey == null;
  bool get wasApproved => approvedByName != null;
}
