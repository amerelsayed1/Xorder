/// Why somebody did something the restaurant will later ask about.
///
/// A void with no reason is a void nobody can investigate, and "the cashier
/// remembers" stops being true by the end of the shift. The SRS makes a reason
/// **required by default** for void and refund; this is the list they pick from.
///
/// One list, reused. The patterns handoff specifies a single reason picker
/// shared by void, refund, pay-out, price override, force-close and inventory
/// adjustment, and [ReasonScope] is what narrows it per act rather than each
/// act growing a list of its own that drifts from the others.
library;

/// Which act a reason may be given for.
///
/// **These strings are data** — they are the `scope` column's CHECK constraint
/// in migration 9, so adding a member here without adding it there writes a row
/// the database refuses.
enum ReasonScope {
  /// Cancelling or voiding a line or an order.
  voidAct('void'),

  /// Money going back to a customer.
  refund('refund'),

  /// A discount applied by hand, above and beyond a configured one.
  discount('discount'),

  /// Selling a line at a price that is not the menu price.
  priceOverride('price_override'),

  // ── Not yet used. Wave B and Wave L. ──────────────────────────────────────
  // Listed here, and in the CHECK constraint, because the alternative is a
  // migration per act. A scope with no rows seeded is simply an empty list.
  payIn('pay_in'),
  payOut('pay_out'),
  waste('waste'),
  adjustment('adjustment');

  const ReasonScope(this.wire);

  /// What is stored. `void` is a Dart keyword, which is the only reason the
  /// member is named [voidAct] — the stored value is plain `void`.
  final String wire;

  static ReasonScope? fromWire(String value) {
    for (final scope in ReasonScope.values) {
      if (scope.wire == value) return scope;
    }
    return null;
  }
}

/// One choice in the reason picker.
class ReasonCode {
  const ReasonCode({
    required this.id,
    required this.scope,
    required this.code,
    required this.nameEn,
    this.nameAr,
    this.requiresNote = false,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final int id;
  final ReasonScope scope;

  /// Stable and machine-readable. A restaurant renaming "Manager comp" must not
  /// change what a year of reports groups on.
  final String code;

  final String nameEn;
  final String? nameAr;

  /// True for *Other*, where the reason carries no information without one.
  ///
  /// A property of the reason, not of the list: within one picker some choices
  /// explain themselves and one does not, and putting this on the list would
  /// force a note for all of them or none.
  final bool requiresNote;

  final int sortOrder;
  final bool isActive;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;
}

/// A reason, and whatever the person typed beside it.
///
/// [reason] is null only when the list was [ReasonRequirement.disabled] — the
/// restaurant switched reasons off for that act, and the caller still needs
/// something to carry a note in.
class ReasonSelection {
  const ReasonSelection({this.reason, this.note});

  final ReasonCode? reason;

  /// Trimmed, and null rather than empty. An empty string in the `note` column
  /// reads as "somebody typed something" when nobody did.
  final String? note;

  int? get reasonId => reason?.id;
}

/// Whether a reason has to be given at all.
///
/// Configured per act by the restaurant (SRS §20). Until Settings can hold it
/// — Wave D — [SystemReasons.defaultRequirement] is the answer, and it follows
/// the SRS: required for anything that moves or unmakes money.
enum ReasonRequirement { required, optional, disabled }

/// The reasons every restaurant starts with.
///
/// Production copy from the patterns handoff, in both languages, used verbatim.
/// Seeded rather than hardcoded: a restaurant edits, adds to and retires these,
/// and the code never reads a reason by name.
///
/// Migration 9 carries a frozen copy of this list for restaurants that already
/// existed when it ran. **This constant is the living definition** — the
/// bootstrap seeds new restaurants from here, exactly as `SystemRoles` works.
abstract final class SystemReasons {
  /// The ten choices, in picker order. Position 10 is *Other*, which the picker
  /// keys to `0` because that is where a hand reaches for it on a keypad.
  static const seeded =
      <({String code, String nameEn, String nameAr, bool requiresNote})>[
        (
          code: 'customer_complaint',
          nameEn: 'Customer complaint',
          nameAr: 'شكوى عميل',
          requiresNote: false,
        ),
        (
          code: 'wrong_item',
          nameEn: 'Wrong item made',
          nameAr: 'صنف خطأ في التحضير',
          requiresNote: false,
        ),
        (
          code: 'unavailable',
          nameEn: "Item unavailable (86'd)",
          nameAr: 'الصنف غير متوفر',
          requiresNote: false,
        ),
        (
          code: 'staff_meal',
          nameEn: 'Staff meal',
          nameAr: 'وجبة موظفين',
          requiresNote: false,
        ),
        (
          code: 'manager_comp',
          nameEn: 'Manager comp',
          nameAr: 'ضيافة إدارة',
          requiresNote: false,
        ),
        (
          code: 'price_differs',
          nameEn: 'Price differs from menu',
          nameAr: 'سعر مختلف عن القائمة',
          requiresNote: false,
        ),
        (
          code: 'kitchen_delay',
          nameEn: 'Kitchen took too long',
          nameAr: 'تأخر التحضير',
          requiresNote: false,
        ),
        (
          code: 'training',
          nameEn: 'Training',
          nameAr: 'تدريب',
          requiresNote: false,
        ),
        (
          code: 'regular_gesture',
          nameEn: 'Regular-customer gesture',
          nameAr: 'مجاملة عميل دائم',
          requiresNote: false,
        ),
        (
          code: 'other',
          nameEn: 'Other — note required',
          nameAr: 'أخرى — يلزم كتابة ملاحظة',
          requiresNote: true,
        ),
      ];

  /// The scopes seeded on a new restaurant.
  ///
  /// Only the four Wave A uses. Seeding a list for pay-in, waste and adjustment
  /// before anything can record one would put choices on screen that no screen
  /// shows, and a restaurant editing them would be editing nothing.
  static const seededScopes = <ReasonScope>[
    ReasonScope.voidAct,
    ReasonScope.refund,
    ReasonScope.discount,
    ReasonScope.priceOverride,
  ];

  /// Whether an act must carry a reason, before Settings can say otherwise.
  ///
  /// The SRS: *"For void/refund operations it should default to Required."*
  /// Discount and price override join them because both change what a customer
  /// pays and both are the acts an audit asks about first.
  static ReasonRequirement defaultRequirement(ReasonScope scope) =>
      switch (scope) {
        ReasonScope.voidAct ||
        ReasonScope.refund ||
        ReasonScope.discount ||
        ReasonScope.priceOverride => ReasonRequirement.required,
        ReasonScope.payIn ||
        ReasonScope.payOut ||
        ReasonScope.waste ||
        ReasonScope.adjustment => ReasonRequirement.optional,
      };
}
