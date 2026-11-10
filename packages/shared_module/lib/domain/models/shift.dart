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
  /// is the common case in a small business: one cashier who is also trusted
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
    this.clientTransactionId,
  });

  final int id;
  final DateTime openedAt;
  final Money openingFloat;
  final String openedByName;

  /// The staff row that opened it — the drawer's owner.
  ///
  /// A name cannot answer this: two people called Ahmed is a business, not a
  /// corner case, and the question "is this your drawer" has to be settled by
  /// identity. Null only for a shift read by an older build, which is why
  /// [openedBy] treats null as "unknown" rather than as "not you".
  final int? openedById;
  final DateTime? closedAt;

  /// The shift-open idempotency key used by cloud records that belong to this
  /// drawer.  Older local shifts legitimately have none and remain readable;
  /// they are never guessed into a different platform shift.
  final String? clientTransactionId;

  /// Whether [staffId] is the person this drawer belongs to.
  ///
  /// Unknown owners answer TRUE. A shift written before the id was recorded has
  /// nobody to compare against, and a till that cannot be cashed up at all is a
  /// worse outcome than one cashed up by the wrong person.
  bool openedBy(int staffId) => openedById == null || openedById == staffId;

  bool get isOpen => closedAt == null;

  /// The four-digit number alone — `0001` — for a screen that puts its own
  /// word in front of it.
  ///
  /// [reference] bakes the English word in, which is fine for a ledger row and
  /// wrong for a label: the Arabic top bar read "SHIFT #0001" because the word
  /// travelled with the number. A screen asks `AppStrings.shiftLabel` for the
  /// word in its own language and hands it this.
  String get number => id.toString().padLeft(4, '0');

  /// Derived from the id rather than stored.
  ///
  /// A denormalised reference is a string that drifts: renumber, restore from a
  /// backup, or copy a row, and the label stops matching the thing it labels.
  String get reference => 'SHIFT #$number';
}

/// Who has held a drawer at this branch — the Users section's two shift facts.
///
/// **Last shift, not last login.** No sign-in is stored anywhere: there is no
/// `last_login_at` on `pos_users` and no sign-in audit action. The last shift
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
    this.cashRefunded = Money.zero,
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

  /// The part of [refunds] that physically left this shift's drawer.  It is
  /// snapshotted on `pos_refund_payments`, just like sale cash, so changing a
  /// tender configuration later cannot rewrite an old cash-up.
  final Money cashRefunded;

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

  /// What the business kept: everything charged, less everything given back.
  Money get net => gross - refunds;

  /// Tax and service together — the part of [gross] that was never the
  /// business's to keep.
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
  /// matching anything at all the day a business renamed its methods into
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
  /// Cash refunds leave the drawer and must be subtracted. Card/wallet refunds
  /// do not touch it, so subtracting the refund headline would manufacture a
  /// shortage for every electronic return.
  Money get expectedCash =>
      shift.openingFloat + cashTaken + cashIn - cashOut - cashRefunded;

  /// Positive means more cash in the drawer than the sales explain.
  Money varianceAgainst(Money counted) => counted - expectedCash;
}

/// A drawer open at this branch right now, and what it should hold (BO-10).
///
/// **The expected figure is the Z report's, not a second sum.** [summary] is
/// built by the same `summarise` the cash-up closes against, so the Finance
/// tab and the cash-up cannot disagree about a drawer — an "expected in
/// drawers" worked out separately would be the number a manager holds up
/// against the Z report at midnight and finds 40 piastres off.
class OpenDrawer {
  const OpenDrawer({
    required this.terminalId,
    required this.summary,
    this.terminalName,
  });

  /// `pos_shifts.terminal_id` as text.
  final String terminalId;

  /// Null for a till whose row is gone; the drawer is still listed, by id.
  final String? terminalName;

  final ShiftSummary summary;

  PosShift get shift => summary.shift;

  Money get expectedCash => summary.expectedCash;
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

// ── People › Shifts and Finance › Settlements ──────────────────────────────

/// What became of a shift, as the back office names it.
///
/// **Force-closed is a handover, because nothing else is recorded.**
/// `pos_shifts` has no forced flag, and a forced *day* close leaves its
/// shifts open rather than closing them. What the till does record is a drawer
/// counted by somebody other than the person who opened it — which the
/// repository allows only on a manager's approval for that shift. That is the
/// close a manager wants picked out, so it is the one this names. Inventing a
/// column for it would have needed migration 50 and a writer nothing calls.
///
/// An enum and a total switch for the words (`shiftStatusLabel`), so a fourth
/// state cannot reach the list unlabelled.
enum ShiftStatus { open, closed, forceClosed }

/// Which shifts the Shifts and Settlements lists ask for.
///
/// [from] inclusive, [to] exclusive, both **business dates**, filed by the rule
/// the sales list files a sale by — so "this week" is the same seven trading
/// days on every tab. **An open shift is listed whatever the dates**: a drawer
/// still out is today's question however long ago it was opened, and a range
/// that hid last night's unclosed drawer would hide the one row that matters.
///
/// A family key, so it has value equality.
class ShiftHistoryQuery {
  ShiftHistoryQuery({
    required DateTime from,
    required DateTime to,
    this.terminalId,
    this.staffId,
    this.statuses = const {},
  }) : from = DateTime(from.year, from.month, from.day),
       to = DateTime(to.year, to.month, to.day);

  final DateTime from;
  final DateTime to;

  /// `pos_terminals.id` as text.
  final String? terminalId;

  /// Who opened the shift — the drawer's owner, not whoever counted it.
  final int? staffId;

  /// Empty means every state.
  final Set<ShiftStatus> statuses;

  @override
  bool operator ==(Object other) =>
      other is ShiftHistoryQuery &&
      other.from == from &&
      other.to == to &&
      other.terminalId == terminalId &&
      other.staffId == staffId &&
      other.statuses.length == statuses.length &&
      other.statuses.containsAll(statuses);

  @override
  int get hashCode => Object.hash(
    from,
    to,
    terminalId,
    staffId,
    Object.hashAllUnordered(statuses),
  );
}

/// One shift, its Z report, and its cash-up once there is one.
class ShiftRecord {
  const ShiftRecord({
    required this.summary,
    required this.terminalId,
    this.terminalName,
    this.closedById,
    this.closedByName,
    this.countedCash,
    this.recordedExpected,
    this.recordedVariance,
    this.note,
    this.approvedByName,
  });

  /// By `summarise` — the Z report's own rule, the one `close` stored its
  /// expected figure from and Finance's drawers read.
  final ShiftSummary summary;

  final String terminalId;

  /// Null for a till whose row is gone; the shift is still listed, by id.
  final String? terminalName;

  final int? closedById;
  final String? closedByName;

  /// `counted_cash_minor`, `expected_cash_minor` and `variance_minor` as the
  /// cash-up stored them. Null while the shift is open.
  final Money? countedCash;
  final Money? recordedExpected;
  final Money? recordedVariance;

  /// `closing_note`.
  final String? note;

  /// The manager on the shift's `shift.closed` ledger row, when the count was
  /// approved — the handover, or a cashier who could not close alone.
  final String? approvedByName;

  PosShift get shift => summary.shift;

  ShiftStatus get status => switch (shift.closedAt) {
    null => ShiftStatus.open,
    // Compared by id, as `PosShift.openedBy` compares: two Ahmeds are two
    // people. An owner read by an older build is unknown, and unknown is not
    // somebody else.
    _ when closedById != null &&
        shift.openedById != null &&
        closedById != shift.openedById =>
      ShiftStatus.forceClosed,
    _ => ShiftStatus.closed,
  };

  /// What the drawer should hold.
  ///
  /// **The stored figure once counted, the live one while open.** The stored
  /// one is what the count was judged against, and it was computed by the same
  /// `summarise` in the same transaction as the close. Recomputing it here
  /// would be right on every shift where nothing moved since, and would
  /// quietly rewrite the one where something did — which is the shift a
  /// manager is investigating.
  Money get expectedCash => recordedExpected ?? summary.expectedCash;

  /// Counted less expected, as stored. Positive is over. Null while open.
  Money? get overShort => recordedVariance;
}

/// The shifts a query found, and the tills and people that appear across its
/// dates — for the filters, which must offer what the dates hold rather than
/// what the current filter left.
class ShiftHistory {
  const ShiftHistory({
    required this.shifts,
    this.tills = const [],
    this.staff = const [],
    this.cut = false,
  });

  static const empty = ShiftHistory(shifts: []);

  /// Each row is summarised by the Z report's rule, four statements a shift,
  /// in one transaction — so a month of a busy branch is capped rather than
  /// left to take as long as it takes. Newest kept; [cut] says so.
  static const limit = 200;

  /// Open first, then newest first.
  final List<ShiftRecord> shifts;

  /// `(terminal id, name)`. The name falls back to the id for a till whose row
  /// is gone.
  final List<(String, String)> tills;

  /// `(staff id, name)` of whoever opened a shift in the dates.
  final List<(int, String)> staff;

  /// More shifts matched than [limit].
  final bool cut;
}

/// The Settlements strip: the cash-ups among [ShiftRecord]s, summed.
///
/// **Made from the rows, not asked of the database separately**, so the strip
/// is the table under it by construction — a second query could be read a
/// moment later and include a drawer the table does not.
class CashUpTotals {
  const CashUpTotals({
    required this.count,
    required this.over,
    required this.short,
  });

  factory CashUpTotals.of(Iterable<ShiftRecord> records) {
    var count = 0;
    var over = Money.zero;
    var short = Money.zero;
    for (final record in records) {
      final variance = record.overShort;
      if (variance == null) continue;
      count++;
      if (variance.isNegative) {
        short += variance;
      } else {
        over += variance;
      }
    }
    return CashUpTotals(count: count, over: over, short: short);
  }

  final int count;

  /// Every drawer that held more than expected, summed. Zero or positive.
  final Money over;

  /// Every drawer that held less, summed — **negative**, as the variances
  /// are, so it reads as money missing and draws in the danger colour.
  final Money short;

  Money get net => over + short;
}
