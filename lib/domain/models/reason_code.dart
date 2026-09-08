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

  /// Cancelling a supplier's invoice.
  ///
  /// Its own scope rather than folded into [voidAct]: a voided sale and a
  /// voided purchase invoice are asked about by different people for different
  /// reasons, and one list serving both would offer "Customer changed their
  /// mind" to a bookkeeper holding a duplicate from a dairy.
  invoiceVoid('invoice_void'),

  /// Reversing a payment to a supplier.
  paymentVoid('payment_void'),

  // ── Not yet used. Wave L. ────────────────────────────────────────────────
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

  /// Why cash goes into a drawer outside a sale (§22).
  ///
  /// Its own list, because [seeded] is written for the four acts that reduce a
  /// bill — "Staff meal" and "Manager comp" are not reasons anybody puts money
  /// *in* a till, and offering them would be offering nonsense.
  static const cashIn =
      <({String code, String nameEn, String nameAr, bool requiresNote})>[
        (
          code: 'float_top_up',
          nameEn: 'Float top-up',
          nameAr: 'تعزيز العهدة',
          requiresNote: false,
        ),
        (
          code: 'owner_deposit',
          nameEn: 'Owner deposit',
          nameAr: 'إيداع من المالك',
          requiresNote: false,
        ),
        (
          code: 'correction',
          nameEn: 'Correcting a count',
          nameAr: 'تصحيح جرد',
          requiresNote: true,
        ),
        (
          code: 'other',
          nameEn: 'Other — note required',
          nameAr: 'أخرى — يلزم كتابة ملاحظة',
          requiresNote: true,
        ),
      ];

  /// Why cash leaves a drawer outside a refund (§22).
  static const cashOut =
      <({String code, String nameEn, String nameAr, bool requiresNote})>[
        (
          code: 'supplier',
          nameEn: 'Supplier payment',
          nameAr: 'دفعة لمورّد',
          requiresNote: true,
        ),
        (
          code: 'petty_expense',
          nameEn: 'Petty expense',
          nameAr: 'مصروف نثري',
          requiresNote: true,
        ),
        (
          code: 'staff_advance',
          nameEn: 'Staff advance',
          nameAr: 'سلفة موظف',
          requiresNote: true,
        ),
        (
          code: 'bank_drop',
          nameEn: 'Bank drop',
          nameAr: 'توريد للبنك',
          requiresNote: false,
        ),
        (
          code: 'correction',
          nameEn: 'Correcting a count',
          nameAr: 'تصحيح جرد',
          requiresNote: true,
        ),
        (
          code: 'other',
          nameEn: 'Other — note required',
          nameAr: 'أخرى — يلزم كتابة ملاحظة',
          requiresNote: true,
        ),
      ];

  /// The list a scope is seeded from.
  ///
  /// Waste and adjustment still get nothing: Wave L is what records one, and
  /// seeding a list before anything can use it would put choices on screen that
  /// no screen shows.
  static List<({String code, String nameEn, String nameAr, bool requiresNote})>
  seededFor(ReasonScope scope) => switch (scope) {
    ReasonScope.payIn => cashIn,
    ReasonScope.payOut => cashOut,
    ReasonScope.invoiceVoid => invoiceVoided,
    ReasonScope.paymentVoid => paymentReversed,
    _ => seeded,
  };

  /// Why a purchase invoice is being cancelled.
  ///
  /// **Entered twice leads the list**, because it is what actually happens: two
  /// people type the same delivery note, or one person types it and then the
  /// bookkeeper does. The database refuses the duplicate by number, so the ones
  /// that get this far are the ones where the number was mistyped too.
  static const invoiceVoided =
      <({String code, String nameEn, String nameAr, bool requiresNote})>[
        (
          code: 'entered_twice',
          nameEn: 'Entered twice',
          nameAr: 'مُدخلة مرتين',
          requiresNote: false,
        ),
        (
          code: 'wrong_supplier',
          nameEn: 'Wrong supplier',
          nameAr: 'مورّد خطأ',
          requiresNote: false,
        ),
        (
          code: 'wrong_amount',
          nameEn: 'Wrong amount',
          nameAr: 'مبلغ خطأ',
          requiresNote: false,
        ),
        (
          code: 'credit_note',
          nameEn: 'Cancelled by a credit note',
          nameAr: 'أُلغيت بإشعار دائن',
          requiresNote: false,
        ),
        (
          code: 'goods_returned',
          nameEn: 'Goods returned',
          nameAr: 'مرتجع للمورّد',
          requiresNote: false,
        ),
        (
          code: 'other',
          nameEn: 'Other — note required',
          nameAr: 'أخرى — يلزم كتابة ملاحظة',
          requiresNote: true,
        ),
      ];

  /// Why a payment to a supplier is being reversed.
  static const paymentReversed =
      <({String code, String nameEn, String nameAr, bool requiresNote})>[
        (
          code: 'wrong_amount',
          nameEn: 'Wrong amount',
          nameAr: 'مبلغ خطأ',
          requiresNote: false,
        ),
        (
          code: 'wrong_invoice',
          nameEn: 'Paid against the wrong invoice',
          nameAr: 'سُدِّدت على فاتورة خطأ',
          requiresNote: false,
        ),
        (
          code: 'wrong_supplier',
          nameEn: 'Paid the wrong supplier',
          nameAr: 'سُدِّدت لمورّد خطأ',
          requiresNote: false,
        ),
        (
          code: 'cheque_bounced',
          nameEn: 'Cheque returned',
          nameAr: 'شيك مرتجع',
          requiresNote: false,
        ),
        (
          code: 'entered_twice',
          nameEn: 'Entered twice',
          nameAr: 'مُدخلة مرتين',
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
  static const seededScopes = <ReasonScope>[
    ReasonScope.voidAct,
    ReasonScope.refund,
    ReasonScope.discount,
    ReasonScope.priceOverride,
    // Wave B records both, so both now have somewhere to appear.
    ReasonScope.payIn,
    ReasonScope.payOut,
    // And Wave D's purchasing ledger records both of these.
    ReasonScope.invoiceVoid,
    ReasonScope.paymentVoid,
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
        ReasonScope.priceOverride ||
        // Cancelling a debt and un-paying a supplier are the two acts in the
        // back office that money can leave through. Both are required, for the
        // same reason a refund is.
        ReasonScope.invoiceVoid ||
        ReasonScope.paymentVoid => ReasonRequirement.required,
        ReasonScope.payIn ||
        ReasonScope.payOut ||
        ReasonScope.waste ||
        ReasonScope.adjustment => ReasonRequirement.optional,
      };
}
