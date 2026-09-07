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

  static const reportsView = 'reports.view';
  static const backupManage = 'backup.manage';

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
    shiftOpen,
    shiftClose,
    cashMovement,
    cashOpenWithoutSale,
    shiftViewExpectedCash,
    cashVarianceView,
    dayClose,
    dayForceClose,
    reportsView,
    backupManage,
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
    staffManage,
    terminalManage,
    settingsManage,
    backupManage,
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
    PosCapability.catalogManage,
    PosCapability.staffManage,
    PosCapability.terminalManage,
    PosCapability.settingsManage,
    PosCapability.reportsView,
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
