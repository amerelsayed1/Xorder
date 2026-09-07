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

  static const discountApply = 'discount.apply';
  static const priceOverride = 'price.override';
  static const orderVoid = 'order.void';
  static const orderRefund = 'order.refund';
  static const receiptReprint = 'receipt.reprint';

  static const shiftOpen = 'shift.open';
  static const shiftClose = 'shift.close';
  static const cashMovement = 'cash.movement';

  static const reportsView = 'reports.view';
  static const backupManage = 'backup.manage';

  /// Every capability the product defines, in the order the role editor shows
  /// them. A role holding a string that is not in here is not an error — it is
  /// a capability from a newer build that this till has not been updated to
  /// understand yet, and silently dropping it would quietly demote somebody.
  static const all = <String>[
    operate,
    catalogView,
    catalogManage,
    staffManage,
    terminalManage,
    settingsManage,
    discountApply,
    priceOverride,
    orderVoid,
    orderRefund,
    receiptReprint,
    shiftOpen,
    shiftClose,
    cashMovement,
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
    orderRefund,
    receiptReprint,
    shiftClose,
    cashMovement,
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
  selling([PosCapability.operate, PosCapability.catalogView]),
  money([
    PosCapability.discountApply,
    PosCapability.priceOverride,
    PosCapability.orderVoid,
    PosCapability.orderRefund,
    PosCapability.receiptReprint,
  ]),
  drawer([
    PosCapability.shiftOpen,
    PosCapability.shiftClose,
    PosCapability.cashMovement,
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
    PosCapability.discountApply,
    PosCapability.priceOverride,
    PosCapability.orderVoid,
    PosCapability.orderRefund,
    PosCapability.receiptReprint,
    PosCapability.shiftOpen,
    PosCapability.shiftClose,
    PosCapability.cashMovement,
    PosCapability.reportsView,
  };

  /// The person on the floor at 1am. Everything a shift needs, nothing that
  /// changes what the restaurant sells or who works there.
  static const supervisor = <String>{
    PosCapability.operate,
    PosCapability.catalogView,
    PosCapability.discountApply,
    PosCapability.priceOverride,
    PosCapability.orderVoid,
    PosCapability.orderRefund,
    PosCapability.receiptReprint,
    PosCapability.shiftOpen,
    PosCapability.shiftClose,
    PosCapability.cashMovement,
    PosCapability.reportsView,
  };

  /// Sell, open the drawer they are answerable for, close it, reprint what they
  /// just printed. Nothing in [PosCapability.backOffice], by requirement.
  static const cashier = <String>{
    PosCapability.operate,
    PosCapability.catalogView,
    PosCapability.receiptReprint,
    PosCapability.shiftOpen,
    PosCapability.shiftClose,
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
