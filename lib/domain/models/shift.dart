import '../../core/money/money.dart';
import 'business_day.dart';
import 'tender_method.dart';
import 'permissions.dart';
import '../services/permission_resolver.dart';

/// A member of staff, as the till knows them.
///
/// Carries the id because a shift belongs to a *person*, not to a name: two
/// cashiers called Ahmed would otherwise share a drawer in the ledger.
class PosStaff {
  const PosStaff({
    required this.id,
    required this.name,
    this.capabilities = const {},
    this.role,
    this.username,
    this.isActive = true,
    this.extraRoles = const [],
    this.overrides = const [],
    this.limits = const {},
  });

  final int id;
  final String name;

  /// Granted to *this person*, on top of whatever [role] carries.
  ///
  /// Kept as well as the role rather than replaced by it because the exception
  /// is the common case in a small restaurant: one cashier who is also trusted
  /// to reprint. Making that person a whole new role, or promoting them to
  /// supervisor, are both worse answers than one extra grant against their
  /// name — and the audit trail records which of the two it was.
  final Set<String> capabilities;

  /// Null for a member of staff seeded before roles existed, or one whose role
  /// was deleted. They keep [capabilities] and nothing else, which is the
  /// conservative reading rather than the convenient one.
  final PosRole? role;

  /// The roles beyond [role] (§11).
  ///
  /// A supervisor who also covers shifts as a cashier holds two, and their
  /// permissions union. Separate from [role] rather than replacing it because
  /// [role] is what the staff list shows and what a person calls their job —
  /// collapsing the two would make the list say "2 roles" where it used to say
  /// "Supervisor".
  final List<PosRole> extraRoles;

  /// This person's exceptions to their roles (§105). DENY wins.
  final List<PermissionOverride> overrides;

  /// Numeric ceilings, already tightened across every role and this person's
  /// own. Keyed by [LimitKey]; absent means unlimited.
  final Map<String, PermissionLimit> limits;

  final String? username;
  final bool isActive;

  /// The role's capabilities and the direct grants, under their current names.
  ///
  /// Canonicalised on the way out rather than on the way in, because rows
  /// written by an older build are still on disk and a till that has not been
  /// migrated yet must still read them correctly.
  Set<String> get effectiveCapabilities => PermissionResolver.resolve(
    // Deliberately **not** gated on [isActive] here. `can` is "does this
    // person hold it"; whether they may use it right now is
    // `Authorization.check`'s question, and it asks both. Folding the two
    // together would make a disabled person's staff-editor page render as
    // though they had never been granted anything.
    isActive: true,
    roles: [?role, ...extraRoles],
    overrides: overrides,
  ).capabilities.union(PosCapability.canonicalAll(capabilities));

  /// The ceiling on [key], or unlimited when there is none.
  PermissionLimit limitFor(String key) =>
      limits[key] ?? PermissionLimit.unlimited;

  /// What a DENY override took away, for the staff editor to show.
  Set<String> get deniedByOverride => {
    for (final override in overrides)
      if (override.effect == OverrideEffect.deny)
        PosCapability.canonical(override.capability),
  };

  /// Whether this person may do the thing, ignoring any supervisor standing
  /// behind them. Override is a separate question — `Authorization.check`.
  bool can(String capability) =>
      effectiveCapabilities.contains(PosCapability.canonical(capability));

  PosStaff copyWith({
    String? name,
    Set<String>? capabilities,
    PosRole? role,
    String? username,
    bool? isActive,
    List<PosRole>? extraRoles,
    List<PermissionOverride>? overrides,
    Map<String, PermissionLimit>? limits,
  }) => PosStaff(
    id: id,
    name: name ?? this.name,
    capabilities: capabilities ?? this.capabilities,
    role: role ?? this.role,
    username: username ?? this.username,
    isActive: isActive ?? this.isActive,
    extraRoles: extraRoles ?? this.extraRoles,
    overrides: overrides ?? this.overrides,
    limits: limits ?? this.limits,
  );
}

/// An open or closed till session.
class PosShift {
  const PosShift({
    required this.id,
    required this.openedAt,
    required this.openingFloat,
    required this.openedByName,
    this.openedById,
    this.closedAt,
  });

  final int id;
  final DateTime openedAt;
  final Money openingFloat;
  final String openedByName;

  /// The staff row that opened it — the drawer's owner.
  ///
  /// A name cannot answer this: two people called Ahmed is a restaurant, not a
  /// corner case, and the question "is this your drawer" has to be settled by
  /// identity. Null only for a shift read by an older build, which is why
  /// [openedBy] treats null as "unknown" rather than as "not you".
  final int? openedById;
  final DateTime? closedAt;

  /// Whether [staffId] is the person this drawer belongs to.
  ///
  /// Unknown owners answer TRUE. A shift written before the id was recorded has
  /// nobody to compare against, and a till that cannot be cashed up at all is a
  /// worse outcome than one cashed up by the wrong person.
  bool openedBy(int staffId) => openedById == null || openedById == staffId;

  bool get isOpen => closedAt == null;

  /// Derived from the id rather than stored.
  ///
  /// A denormalised reference is a string that drifts: renumber, restore from a
  /// backup, or copy a row, and the label stops matching the thing it labels.
  String get reference => 'SHIFT #${id.toString().padLeft(4, '0')}';
}

/// Who has held a drawer at this branch — the Users section's two shift facts.
///
/// **Last shift, not last login.** No sign-in is stored anywhere: there is no
/// `last_login_at` on `pos_staff` and no sign-in audit action. The last shift
/// somebody opened is the nearest thing that is recorded, and it is labelled
/// as what it is rather than passed off as the thing the mockup asked for.
///
/// Both halves come from one read of `pos_shifts`, so the "current shifts"
/// tile and the "on shift now" rows cannot disagree with each other — two
/// reads a second apart could, and a manager counting rows against the tile
/// would find the screen contradicting itself.
class ShiftActivity {
  const ShiftActivity({
    required this.openShifts,
    required this.lastOpenedAt,
    this.onShift = const {},
  });

  /// Nothing recorded, or nowhere to read it from.
  static const empty = ShiftActivity(openShifts: 0, lastOpenedAt: {});

  /// Open drawers across every terminal of the branch, not just this one.
  final int openShifts;

  /// Staff id to the newest `opened_at` of any shift they opened here.
  final Map<int, DateTime> lastOpenedAt;

  /// Staff ids with a shift open right now.
  final Set<int> onShift;
}

/// One tender type's contribution to a shift.
class ShiftTenderTotal {
  const ShiftTenderTotal({
    required this.label,
    required this.count,
    required this.amount,
    this.typeId,
    bool? countsAsCash,
    // The field is private and the parameter is not: callers set it, readers
    // go through the getter that supplies the fallback.
    // ignore: prefer_initializing_formals
  }) : _countsAsCash = countsAsCash;

  final String label;
  final int count;
  final Money amount;

  /// `pos_order_payments.tender_type_id`. Carried so the drawer's cash is found
  /// by what the method *is* rather than by what it is called — see
  /// [TenderMethod.countsAsCash].
  final int? typeId;

  final bool? _countsAsCash;

  /// Whether this line's money is in the drawer.
  ///
  /// **Read from the payment row**, which snapshotted it when the money moved,
  /// and only falls back to the seeded list for rows written before that column
  /// existed. Resolving it against today's tender configuration would make last
  /// week's cash-up change when somebody edits a payment method this week —
  /// which is exactly the number a variance investigation is checking.
  bool get countsAsCash => _countsAsCash ?? TenderMethod.isCash(typeId);
}

/// What the shift did — the Z report, in the only form that matters at the
/// drawer: how much cash *should* be in it.
class ShiftSummary {
  const ShiftSummary({
    required this.shift,
    required this.saleCount,
    required this.gross,
    required this.tenders,
    this.subtotal = Money.zero,
    this.discounts = Money.zero,
    this.service = Money.zero,
    this.vat = Money.zero,
    this.refunds = Money.zero,
    this.voids = Money.zero,
    this.voidCount = 0,
    this.refundCount = 0,
    this.movements,
  });

  final PosShift shift;
  final int saleCount;

  /// Everything charged, however it was paid — the sum of the totals on every
  /// settled order.
  final Money gross;
  final List<ShiftTenderTotal> tenders;

  // ── §27's required totals ─────────────────────────────────────────────────

  /// Food and drink at menu prices, before anything was taken off.
  final Money subtotal;

  /// What was given away — line and order discounts together.
  final Money discounts;

  final Money service;
  final Money vat;

  /// Money handed back during this shift.
  ///
  /// **Not netted off [gross].** A shift that sold 1,000 and refunded 200 did
  /// both things, and a report showing only 800 hides the 200 — which is the
  /// number a manager is actually looking for. [net] is where they meet.
  final Money refunds;

  /// What was thrown away after the kitchen had made it.
  ///
  /// Never in [gross]: a voided order took no money. It is here because it is
  /// the cost of the evening even though it is not a sale.
  final Money voids;

  final int voidCount;
  final int refundCount;

  /// Money into and out of the drawer that was not a sale. Null until it has
  /// been read — a summary built without it is not wrong, it is incomplete,
  /// and the cash-up screen is the thing that needs it.
  final CashMovementTotals? movements;

  /// What the restaurant kept: everything charged, less everything given back.
  Money get net => gross - refunds;

  /// Tax and service together — the part of [gross] that was never the
  /// restaurant's to keep.
  Money get taxAndService => vat + service;

  Money get cashIn => movements?.paidIn ?? Money.zero;
  Money get cashOut => movements?.paidOut ?? Money.zero;
  int get drawerOpens => movements?.drawerOpens ?? 0;

  /// Everything that was not cash. The Z report's "card and other" line.
  Money get nonCashTaken => tenders
      .where((t) => !t.countsAsCash)
      .fold(Money.zero, (sum, t) => sum + t.amount);

  /// Cash tenders only. Card and wallet do not end up in the drawer, so
  /// counting them against it would manufacture a variance every single shift.
  ///
  /// Selected by tender **type**, not by a substring of its label. The old
  /// `label.contains('cash')` matched "Cashback voucher" and would have stopped
  /// matching anything at all the day a restaurant renamed its methods into
  /// Arabic. See [TenderMethod.countsAsCash].
  Money get cashTaken => tenders
      .where((t) => t.countsAsCash)
      .fold(Money.zero, (sum, t) => sum + t.amount);

  /// What the drawer should hold.
  ///
  /// The float it started with, plus the cash taken, plus what was paid in,
  /// less what was paid out. A cash-up that ignored the pay-outs would report
  /// a shortage every time somebody paid a supplier out of the till — which is
  /// the whole reason §22 records them.
  ///
  /// Refunds do not appear here as a term of their own: a cash refund is a
  /// tender going the other way and Wave B does not yet write one into
  /// `pos_order_payments`. When it does, it belongs in [cashTaken], not here,
  /// so that the drawer's arithmetic stays "float plus what came in, less what
  /// went out".
  Money get expectedCash =>
      shift.openingFloat + cashTaken + cashIn - cashOut;

  /// Positive means more cash in the drawer than the sales explain.
  Money varianceAgainst(Money counted) => counted - expectedCash;
}

/// The outcome of counting the drawer.
class ShiftClose {
  const ShiftClose({
    required this.summary,
    required this.countedCash,
    required this.variance,
    required this.closedAt,
  });

  final ShiftSummary summary;
  final Money countedCash;
  final Money variance;
  final DateTime closedAt;

  bool get balances => variance.minor == 0;
}
