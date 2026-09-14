/// What a member of staff is allowed to do, and who is allowed to say so.
///
/// Pure Dart on purpose: the same catalogue is read by the widgets that grey a
/// button out, by the repositories that refuse a write, and by the migration
/// CLI that seeds the system roles. A capability that only existed in the UI
/// would be a capability a determined cashier could route around.
library;

/// The permission names, exactly as they are stored.
///
/// **These strings are data.** They live in `pos_roles.capabilities` and
/// `pos_staff.capabilities` on every branch server that has ever run this
/// build, so renaming one is a migration, not an edit — see
/// [PosCapability.canonical] and migration 5.
abstract final class PosCapability {
  /// Ring up a sale at all. The floor, the sale screen and payment are behind
  /// this; without it a person can sign in but the till will not sell.
  static const operate = 'pos.operate';

  /// See the menu. Separate from [operate] because a manager who never touches
  /// the till still needs to read the catalogue to manage it.
  static const catalogView = 'catalog.view';

  /// Create, price, archive and restore categories, products and modifiers.
  static const catalogManage = 'catalog.manage';

  static const staffManage = 'staff.manage';
  static const terminalManage = 'terminal.manage';
  static const settingsManage = 'settings.manage';

  /// Look at every order this branch has taken, not only the live ticket.
  ///
  /// The counterpart `order.view_own` is a Wave C key: scoping history to "mine"
  /// is only meaningful once `pos_orders.served_by` has data behind it, and
  /// every order written before migration 11 has none. Until then this is the
  /// whole of order visibility, and a cashier reaches a specific order through
  /// the receipt they just printed rather than by browsing the day's takings.
  static const orderViewAll = 'order.view_all';

  static const discountApply = 'discount.apply';
  static const priceOverride = 'price.override';
  static const orderVoid = 'order.void';

  /// Taking a line off before the kitchen has seen it. Routine — a cashier
  /// correcting a mis-tap, and the SRS is explicit that this is not the same
  /// act as the one below.
  static const orderItemCancel = 'order.item.delete_before_send';

  /// Throwing away a line the kitchen has already made. Waste, with a cost.
  static const orderItemVoid = 'order.item.delete_after_send';
  static const orderRefund = 'order.refund';
  static const receiptReprint = 'receipt.reprint';

  /// Take a payment back off a bill that has not been settled yet.
  ///
  /// It had no key at all: anybody at the payment screen could tap a tender
  /// off. It is the act a card-for-cash swap is made of — tender by card, take
  /// it off, keep the cash — so it has one now. Overridable, because a cashier
  /// who keyed the wrong amount is corrected with a supervisor watching; and
  /// seeded to the supervisor and the manager, who could do it before.
  static const paymentRemove = 'payment.remove';

  static const shiftOpen = 'shift.open';
  static const shiftClose = 'shift.close';
  static const cashMovement = 'cash.movement';

  /// Open the drawer without ringing up a sale (§23).
  ///
  /// Its own key rather than part of [cashMovement], because it is the one
  /// drawer act that moves no money and is therefore the one a dishonest
  /// cashier wants most.
  static const cashOpenWithoutSale = 'cash.open_without_sale';

  /// See what the drawer *should* hold, before counting it (§24, §25).
  ///
  /// Withholding this is what makes a blind count blind.
  static const shiftViewExpectedCash = 'shift.view_expected_cash';

  /// See the variance *after* the count is committed.
  ///
  /// A separate question from the one above, and separating them is what makes
  /// a blind close meaningful: a cashier can be trusted to learn whether they
  /// were right without being told the answer in advance. The SRS names
  /// `cash.view_expected` for the first question as well; that spelling is
  /// folded into [shiftViewExpectedCash] by [canonical] rather than existing
  /// as a third key nobody can tell apart from the other two.
  static const cashVarianceView = 'cash.variance.view';

  /// Close the trading day (§28), and close it over the top of blockers.
  static const dayClose = 'day.close';
  static const dayForceClose = 'day.force_close';

  /// Buying: suppliers, purchase orders, receiving, supplier invoices and
  /// payments.
  ///
  /// One key rather than five, for now. The SRS's granular list splits
  /// purchasing several ways, and splitting it before there is a screen for
  /// each would put keys in the catalogue that nothing checks — the thing
  /// Wave C deferred §50's sixteen settings keys for.
  static const purchaseManage = 'purchase.manage';

  static const reportsView = 'reports.view';

  /// Take the Reports tab or the Sales list away as an Excel file (BO-11).
  ///
  /// Its own key rather than part of [reportsView], because reading a figure
  /// on a screen and carrying every sale of a month out of the building on a
  /// USB stick are different acts: the second leaves no trace this till can
  /// see and cannot be taken back. The owner holds it and no other role is
  /// seeded with it (owner decision, 14 Sep 2026) — Roles is where it is
  /// handed out.
  ///
  /// Critical, as [backupManage] is, for the same reason: it is a copy of the
  /// data. So it is never lent — a supervisor watching a refund is not
  /// watching a spreadsheet leave — and the button is not drawn for somebody
  /// without it. Rejected: `high` beside [reportsView]'s `medium`, which
  /// would have made it a greyed button and a key a manager's PIN could lend
  /// if somebody later added it to [overridable].
  static const reportExport = 'report.export';

  static const backupManage = 'backup.manage';

  /// Enter Admin Mode: the back office, behind a hidden shortcut and a
  /// username and PIN.
  ///
  /// Its own key rather than [staffManage], which is what used to open the back
  /// office. Managing staff is one job inside it; being let in at all is a
  /// different question, and the owner decides who else is asked it (owner
  /// decision, 12 Sep 2026): the Owner holds it, no other role is seeded with
  /// it, and Roles is where it is handed out. Critical, so it is never lent —
  /// a manager's PIN approves one refund and never opens the back office.
  static const adminEnter = 'admin.enter';

  /// Every capability the product defines, in the order the role editor shows
  /// them. A role holding a string that is not in here is not an error — it is
  /// a capability from a newer build that this till has not been updated to
  /// understand yet, and silently dropping it would quietly demote somebody.
  static const all = <String>[
    operate,
    catalogView,
    orderViewAll,
    catalogManage,
    staffManage,
    terminalManage,
    settingsManage,
    discountApply,
    priceOverride,
    orderVoid,
    orderItemCancel,
    orderItemVoid,
    orderRefund,
    receiptReprint,
    paymentRemove,
    shiftOpen,
    shiftClose,
    cashMovement,
    cashOpenWithoutSale,
    shiftViewExpectedCash,
    cashVarianceView,
    dayClose,
    dayForceClose,
    purchaseManage,
    reportsView,
    reportExport,
    backupManage,
    adminEnter,
  ];

  /// Capabilities a supervisor can lend for one action.
  ///
  /// The test is whether the answer to *"may I do this once, with someone
  /// watching?"* is sensible. Discounting a line is: the supervisor is standing
  /// at the till and the audit row names them both. Restoring a database is
  /// not — an override there is just an unlogged second way to hold
  /// [backupManage], and nobody supervises a restore by watching it happen.
  static const overridable = <String>{
    discountApply,
    priceOverride,
    orderVoid,
    // Voiding a cooked item is on the SRS's own list of things a supervisor
    // may approve at the till. Cancelling an unsent one is not on it — it needs
    // no approval because it costs nothing.
    orderItemVoid,
    orderRefund,
    receiptReprint,
    paymentRemove,
    shiftClose,
    cashMovement,
    // A supervisor standing at the till can allow one drawer opening. They
    // cannot lend the right to *see* the expected figure — that would make a
    // blind count a formality, which is the whole thing it exists not to be.
    cashOpenWithoutSale,
    dayForceClose,
  };

  /// Capabilities no cashier role may hold.
  ///
  /// Enforced when a role is saved, not merely documented, because the
  /// requirement — *cashiers must not receive catalogue or database
  /// administration permissions* — is about what the till can be talked into,
  /// and a checkbox nobody re-reads is not a control.
  static const backOffice = <String>{
    catalogManage,
    purchaseManage,
    staffManage,
    terminalManage,
    settingsManage,
    backupManage,
    adminEnter,
    // A month of the branch's sales on a stick, from a login that sits on a
    // machine in a public room.
    reportExport,
  };

  /// What the first build shipped, mapped onto what the strings are now.
  ///
  /// The seed in `bin/pos_migrate.dart` wrote `pos.shift_open` and friends
  /// before the permission model had a specification to follow. Those rows are
  /// on real branch servers. Migration 5 rewrites them, and this map is what it
  /// rewrites them with — kept here rather than inlined in the SQL so that a
  /// till reading a row an older migrator wrote still understands it.
  static const _renamed = <String, String>{
    // §22 and §24 name the same question twice. One key, so a role editor does
    // not offer two checkboxes that cannot disagree.
    'cash.view_expected': shiftViewExpectedCash,
    'pos.discount': discountApply,
    'pos.shift_open': shiftOpen,
    'pos.shift_close': shiftClose,
    'pos.cash_movement': cashMovement,
    'pos.reprint': receiptReprint,
    'pos.void': orderVoid,
    'pos.refund': orderRefund,
    'pos.price_override': priceOverride,
    'pos.reports': reportsView,
  };

  /// The current name for [stored]. Unknown strings pass through unchanged.
  static String canonical(String stored) => _renamed[stored] ?? stored;

  static Set<String> canonicalAll(Iterable<String> stored) => {
    for (final capability in stored) canonical(capability),
  };

  static bool isKnown(String capability) => all.contains(capability);

  /// What each capability costs when it is held by the wrong person (§107).
  ///
  /// Every key in [all] appears here — asserted by a test rather than trusted,
  /// because a capability with no risk level would fall to the default and the
  /// default has to be *some* answer. The one chosen is [PermissionRisk.high]:
  /// a new permission nobody has classified is treated as dangerous until
  /// somebody says otherwise, which fails in the direction that asks a question
  /// rather than the one that grants access.
  static const _risk = <String, PermissionRisk>{
    operate: PermissionRisk.low,
    catalogView: PermissionRisk.low,
    orderViewAll: PermissionRisk.low,
    receiptReprint: PermissionRisk.low,
    orderItemCancel: PermissionRisk.low,
    shiftOpen: PermissionRisk.low,

    discountApply: PermissionRisk.medium,
    orderItemVoid: PermissionRisk.medium,
    cashMovement: PermissionRisk.medium,
    shiftClose: PermissionRisk.medium,
    reportsView: PermissionRisk.medium,
    dayClose: PermissionRisk.medium,

    // Each of these either moves money the shift cannot absorb or changes the
    // record of money that already moved.
    priceOverride: PermissionRisk.high,
    orderVoid: PermissionRisk.high,
    orderRefund: PermissionRisk.high,
    paymentRemove: PermissionRisk.high,
    cashOpenWithoutSale: PermissionRisk.high,
    shiftViewExpectedCash: PermissionRisk.high,
    cashVarianceView: PermissionRisk.high,
    dayForceClose: PermissionRisk.high,
    catalogManage: PermissionRisk.high,
    // Money leaving the business, and the cost prices every margin is measured
    // against. Not critical: it is an ordinary job somebody does, and a
    // manager should be able to see the control they lack.
    purchaseManage: PermissionRisk.high,

    // Access control and the data itself. A person holding any of these can
    // grant themselves the rest.
    staffManage: PermissionRisk.critical,
    terminalManage: PermissionRisk.critical,
    settingsManage: PermissionRisk.critical,
    backupManage: PermissionRisk.critical,
    // The door to all of the above at once.
    adminEnter: PermissionRisk.critical,
    // A copy of the data, like a backup. See [reportExport].
    reportExport: PermissionRisk.critical,
  };

  /// The risk level of [capability]. Unknown keys are [PermissionRisk.high] —
  /// see [_risk].
  static PermissionRisk riskOf(String capability) =>
      _risk[canonical(capability)] ?? PermissionRisk.high;

  /// Whether somebody has actually decided this capability's risk level.
  ///
  /// The difference between "classified as high" and "unclassified, so treated
  /// as high" is invisible in [riskOf] and matters to exactly one reader: the
  /// test that asserts nobody shipped a capability without classifying it.
  static bool isClassified(String capability) =>
      _risk.containsKey(canonical(capability));

  /// Whether a supervisor may lend [capability] for one action.
  ///
  /// Both conditions, not either: on the curated list **and** not critical.
  static bool mayBeLent(String capability) {
    final wanted = canonical(capability);
    return overridable.contains(wanted) && riskOf(wanted).mayBeLent;
  }
}

/// Which numeric ceiling a limit is about.
///
/// Keys rather than fields on a settings object, because a limit is attached to
/// a *subject* — a role or one person — and the set of subjects is open. A
/// column per ceiling would need a migration every time a new one is added.
abstract final class LimitKey {
  /// The largest discount this subject may give, as a share and as a cash
  /// ceiling. Both apply: see [PermissionLimit].
  static const discount = 'discount.max';

  /// The largest refund they may authorise on their own.
  static const refund = 'refund.max';

  /// The largest pay-out they may take from the drawer.
  static const cashPayOut = 'cash.pay_out.max';

  static const all = <String>[discount, refund, cashPayOut];
}

/// A numeric ceiling on what somebody may do (§16, §18).
///
/// Held as raw stored values — basis points and minor units — rather than as a
/// [Money], because a limit belongs to a role and a role outlives the currency
/// question: the row says `50000`, and which currency that is depends on the
/// restaurant reading it.
class PermissionLimit {
  const PermissionLimit({this.maxBp, this.maxMinor});

  /// No ceiling of any kind. What an owner holds.
  static const unlimited = PermissionLimit();

  final int? maxBp;
  final int? maxMinor;

  bool get isUnlimited => maxBp == null && maxMinor == null;

  /// The tighter of two ceilings, field by field.
  ///
  /// **Tighter wins, and it wins per field.** Somebody holding two roles — a
  /// supervisor who also covers as a cashier — gets the *cashier's* discount
  /// cap if it is lower, because the alternative is that adding a role can only
  /// ever increase what a person may do, which makes a limit something you
  /// escape by collecting roles.
  PermissionLimit tightenedBy(PermissionLimit other) => PermissionLimit(
    maxBp: _lower(maxBp, other.maxBp),
    maxMinor: _lower(maxMinor, other.maxMinor),
  );

  static int? _lower(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a < b ? a : b;
  }

  @override
  bool operator ==(Object other) =>
      other is PermissionLimit &&
      other.maxBp == maxBp &&
      other.maxMinor == maxMinor;

  @override
  int get hashCode => Object.hash(maxBp, maxMinor);
}

/// Whether a per-person override adds a permission or takes one away (§105).
///
/// **DENY wins over ALLOW, and both win over roles.** The reason is what an
/// override is *for*: it is how a restaurant says "this one person, despite
/// their role". A DENY that could be outvoted by a second role would be a
/// safety measure somebody could undo by accident.
enum OverrideEffect {
  allow('ALLOW'),
  deny('DENY');

  const OverrideEffect(this.wire);

  final String wire;

  static OverrideEffect? fromWire(String value) {
    for (final effect in values) {
      if (effect.wire == value) return effect;
    }
    // Unknown effect from a newer build. Null rather than a guess: reading an
    // unrecognised effect as ALLOW would grant a permission somebody wrote a
    // row to control, and reading it as DENY would silently demote them.
    return null;
  }
}

/// One person's exception to their roles.
class PermissionOverride {
  const PermissionOverride({
    required this.capability,
    required this.effect,
    this.grantedById,
    this.grantedAt,
  });

  final String capability;
  final OverrideEffect effect;
  final int? grantedById;
  final DateTime? grantedAt;
}

/// How much damage holding a permission wrongly does (§107).
///
/// **This is not a synonym for "important".** It drives two decisions and
/// nothing else: whether a supervisor may lend the permission for one action,
/// and whether a control the person lacks is *disabled* or *hidden*. A `low`
/// permission missing is a greyed button with a tooltip; a [critical] one is a
/// button that was never drawn, because offering somebody a database restore
/// they cannot perform is an invitation to go and find someone who can.
enum PermissionRisk {
  /// Routine. Losing it inconveniences somebody.
  low,

  /// Money moves, in small amounts, with a record.
  medium,

  /// Money moves in amounts a shift cannot absorb, or the record itself
  /// changes.
  high,

  /// The restaurant's data or its access control. Never overridable (§107),
  /// and hidden rather than disabled (§112).
  critical;

  /// Whether a supervisor standing at the till may lend this for one action.
  ///
  /// [critical] is excluded here as well as in [PosCapability.overridable], so
  /// the rule holds even if somebody adds a key to that set by hand. Two
  /// statements of the same rule is worth it for this one: an overridable
  /// `critical` permission is a manager PIN that restores a database.
  bool get mayBeLent => this != critical;

  /// Whether a control for a permission the person lacks appears at all.
  bool get isHidden => this == critical;
}

/// How the role editor groups the checkboxes.
///
/// Grouping is presentation, but it lives here because the grouping *is* the
/// argument for what a role should hold: somebody ticking every box under
/// "Back office" for a cashier should be able to see that is what they are
/// doing.
enum CapabilityGroup {
  selling([
    PosCapability.operate,
    PosCapability.catalogView,
    PosCapability.orderViewAll,
  ]),
  money([
    PosCapability.discountApply,
    PosCapability.priceOverride,
    PosCapability.orderVoid,
    PosCapability.orderItemCancel,
    PosCapability.orderItemVoid,
    PosCapability.orderRefund,
    PosCapability.receiptReprint,
    PosCapability.paymentRemove,
  ]),
  drawer([
    PosCapability.shiftOpen,
    PosCapability.shiftClose,
    PosCapability.cashMovement,
    PosCapability.cashOpenWithoutSale,
    PosCapability.shiftViewExpectedCash,
    PosCapability.cashVarianceView,
    PosCapability.dayClose,
    PosCapability.dayForceClose,
  ]),
  backOffice([
    PosCapability.adminEnter,
    PosCapability.catalogManage,
    PosCapability.purchaseManage,
    PosCapability.staffManage,
    PosCapability.terminalManage,
    PosCapability.settingsManage,
    PosCapability.reportsView,
    PosCapability.reportExport,
    PosCapability.backupManage,
  ]);

  const CapabilityGroup(this.capabilities);

  final List<String> capabilities;
}

/// A named set of capabilities, owned by one restaurant.
///
/// Roles are per-restaurant rather than global because two restaurants sharing
/// a branch server must not share a definition of "manager" — one of them
/// changing what a manager may do would silently change it for the other.
class PosRole {
  const PosRole({
    required this.id,
    required this.code,
    required this.nameEn,
    required this.capabilities,
    this.nameAr,
    this.isSystem = false,
  });

  final int id;

  /// Stable, machine-readable, never shown. Renaming a role must not change
  /// what the seed and the tests refer to.
  final String code;

  final String nameEn;
  final String? nameAr;
  final Set<String> capabilities;

  /// Seeded by the installer. The name and the capabilities are editable — a
  /// restaurant's idea of a supervisor is its own — but a system role cannot be
  /// deleted, because deleting the last role that holds [PosCapability.staffManage]
  /// locks everybody out of the screen that would fix it.
  final bool isSystem;

  bool holds(String capability) => capabilities.contains(capability);

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  PosRole copyWith({
    String? nameEn,
    String? nameAr,
    Set<String>? capabilities,
  }) => PosRole(
    id: id,
    code: code,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    capabilities: capabilities ?? this.capabilities,
    isSystem: isSystem,
  );
}

/// The four roles the installer seeds, and what they hold.
///
/// Seeded rather than hardcoded: these are a starting point a restaurant edits,
/// not a set of privileges the code enforces. What the code enforces is that
/// [ownerCode] keeps every capability — see `RolesRepository.save`.
abstract final class SystemRoles {
  static const ownerCode = 'owner';
  static const managerCode = 'manager';
  static const supervisorCode = 'supervisor';
  static const cashierCode = 'cashier';

  /// Everything, always. The role that can grant capabilities must hold them
  /// all, or a restaurant can reach a state where nobody can grant a capability
  /// that nobody holds.
  static const owner = <String>{...PosCapability.all};

  static const manager = <String>{
    PosCapability.operate,
    PosCapability.catalogView,
    PosCapability.catalogManage,
    PosCapability.staffManage,
    PosCapability.settingsManage,
    PosCapability.purchaseManage,
    PosCapability.orderViewAll,
    PosCapability.discountApply,
    PosCapability.priceOverride,
    PosCapability.orderVoid,
    PosCapability.orderItemCancel,
    PosCapability.orderItemVoid,
    PosCapability.orderRefund,
    PosCapability.receiptReprint,
    PosCapability.paymentRemove,
    PosCapability.shiftOpen,
    PosCapability.shiftClose,
    PosCapability.cashMovement,
    PosCapability.cashOpenWithoutSale,
    PosCapability.shiftViewExpectedCash,
    PosCapability.cashVarianceView,
    PosCapability.dayClose,
    PosCapability.dayForceClose,
    PosCapability.reportsView,
  };

  /// The person on the floor at 1am. Everything a shift needs, nothing that
  /// changes what the restaurant sells or who works there.
  static const supervisor = <String>{
    PosCapability.operate,
    PosCapability.catalogView,
    PosCapability.orderViewAll,
    PosCapability.discountApply,
    PosCapability.priceOverride,
    PosCapability.orderVoid,
    PosCapability.orderItemCancel,
    PosCapability.orderItemVoid,
    PosCapability.orderRefund,
    PosCapability.receiptReprint,
    PosCapability.paymentRemove,
    PosCapability.shiftOpen,
    PosCapability.shiftClose,
    PosCapability.cashMovement,
    PosCapability.cashOpenWithoutSale,
    PosCapability.shiftViewExpectedCash,
    PosCapability.cashVarianceView,
    // Closing the night is theirs; forcing it past open tables is not.
    PosCapability.dayClose,
    PosCapability.reportsView,
  };

  /// Sell, open the drawer they are answerable for, close it, reprint what they
  /// just printed. Nothing in [PosCapability.backOffice], by requirement.
  static const cashier = <String>{
    PosCapability.operate,
    PosCapability.catalogView,
    // Correcting a mis-tap before the kitchen sees it is part of ringing up a
    // sale, not a privilege. Voiding something already cooked is not here: a
    // cashier reaches it through a supervisor, which is the point.
    PosCapability.orderItemCancel,
    PosCapability.receiptReprint,
    PosCapability.shiftOpen,
    PosCapability.shiftClose,
    // Deliberately absent: `shift.view_expected_cash` and `cash.variance.view`.
    // A cashier counts the drawer without being told the answer first, which is
    // the entire point of §25's blind close. They learn the variance from a
    // supervisor, not from the screen.
  };

  /// Six more starting points a restaurant can pick from (§49).
  ///
  /// **Templates, not roles.** Nothing seeds these and nothing enforces them —
  /// they are what the role editor offers when somebody presses *New role*, so
  /// that a restaurant creating an accountant does not start from an empty
  /// checklist and tick things until the screen stops complaining. Choosing one
  /// creates an ordinary role the restaurant then edits.
  ///
  /// They are deliberately *narrow*. A template that granted a bit too much
  /// would be a template that quietly widened access every time somebody used
  /// it, and the cost of a missing permission is a manager adding it back
  /// knowingly.
  static const templates =
      <String, ({String nameEn, String nameAr, Set<String> capabilities})>{
        'shift_manager': (
          nameEn: 'Shift manager',
          nameAr: 'مدير وردية',
          capabilities: {
            PosCapability.operate,
            PosCapability.catalogView,
            PosCapability.orderViewAll,
            PosCapability.discountApply,
            PosCapability.orderVoid,
            PosCapability.orderItemCancel,
            PosCapability.orderItemVoid,
            PosCapability.receiptReprint,
            PosCapability.shiftOpen,
            PosCapability.shiftClose,
            PosCapability.cashMovement,
            PosCapability.shiftViewExpectedCash,
            PosCapability.cashVarianceView,
            PosCapability.reportsView,
          },
        ),
        // Reads the menu to know what a ticket is asking for, and nothing else.
        // No till, no drawer, no money: a kitchen screen is not a place from
        // which anybody should be able to void a sale.
        'kitchen': (
          nameEn: 'Kitchen',
          nameAr: 'المطبخ',
          capabilities: {PosCapability.catalogView},
        ),
        // Authors the menu. Not the floor, not the people, not the money rules
        // — those belong to a manager, and an inventory clerk who could change
        // the VAT rate is a permission model with a hole in it.
        'inventory': (
          nameEn: 'Inventory manager',
          nameAr: 'مسؤول المخزون',
          capabilities: {
            PosCapability.catalogView,
            PosCapability.catalogManage,
            PosCapability.purchaseManage,
            PosCapability.reportsView,
          },
        ),
        // Sees everything and touches nothing. The one template whose value is
        // in what it lacks: an accountant who could void a sale could rewrite
        // the record they are there to check.
        'accountant': (
          nameEn: 'Accountant',
          nameAr: 'محاسب',
          capabilities: {
            PosCapability.catalogView,
            PosCapability.orderViewAll,
            PosCapability.reportsView,
            PosCapability.shiftViewExpectedCash,
            PosCapability.cashVarianceView,
            PosCapability.receiptReprint,
          },
        ),
        // Rings up and settles delivery orders. No drawer: a driver carrying a
        // float is a cash-handling arrangement the restaurant makes, not a
        // permission the till grants.
        'delivery': (
          nameEn: 'Delivery staff',
          nameAr: 'مندوب توصيل',
          capabilities: {
            PosCapability.operate,
            PosCapability.catalogView,
            PosCapability.orderItemCancel,
            PosCapability.receiptReprint,
          },
        ),
        // Everything a manager has except the people. A restaurant group's
        // branch manager runs the branch; who works there is head office's.
        'restaurant_manager': (
          nameEn: 'Restaurant manager',
          nameAr: 'مدير المطعم',
          // Spelled out rather than derived from [manager] minus one key: a
          // derived set changes silently every time somebody edits `manager`,
          // and a template that quietly gained `backup.manage` because a
          // different constant grew would be a template nobody reviewed.
          capabilities: {
            PosCapability.operate,
            PosCapability.catalogView,
            PosCapability.catalogManage,
            PosCapability.settingsManage,
            PosCapability.orderViewAll,
            PosCapability.discountApply,
            PosCapability.priceOverride,
            PosCapability.orderVoid,
            PosCapability.orderItemCancel,
            PosCapability.orderItemVoid,
            PosCapability.orderRefund,
            PosCapability.receiptReprint,
            PosCapability.shiftOpen,
            PosCapability.shiftClose,
            PosCapability.cashMovement,
            PosCapability.cashOpenWithoutSale,
            PosCapability.shiftViewExpectedCash,
            PosCapability.cashVarianceView,
            PosCapability.dayClose,
            PosCapability.dayForceClose,
            PosCapability.reportsView,
          },
        ),
      };

  static const seeded =
      <String, ({String nameEn, String nameAr, Set<String> capabilities})>{
        ownerCode: (nameEn: 'Owner', nameAr: 'المالك', capabilities: owner),
        managerCode: (nameEn: 'Manager', nameAr: 'مدير', capabilities: manager),
        supervisorCode: (
          nameEn: 'Supervisor',
          nameAr: 'مشرف',
          capabilities: supervisor,
        ),
        cashierCode: (
          nameEn: 'Cashier',
          nameAr: 'كاشير',
          capabilities: cashier,
        ),
      };
}
