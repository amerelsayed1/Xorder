import '../models/permissions.dart';
import '../models/reason_code.dart';
import '../models/shift.dart';

/// The answer to "may this person do this?".
///
/// Three outcomes rather than a boolean, because *no* and *not without a
/// supervisor* lead to completely different screens: one is a greyed-out button
/// with an explanation, the other is a PIN prompt with somebody's manager
/// walking over. Collapsing them would either hide a workflow the restaurant
/// needs or offer an override for things nobody can override.
sealed class PermissionDecision {
  const PermissionDecision();

  bool get isAllowed => this is Allowed;
}

class Allowed extends PermissionDecision {
  const Allowed({this.approvedBy, this.reason, this.limit});

  /// The ceiling that came with the permission, when there is one.
  ///
  /// Carried on the decision so a caller can say *"allowed, up to 10%"* from
  /// one question instead of asking twice — and, more usefully, so a caller
  /// that forgets to look at it still gets the right answer from
  /// [Authorization.checkWithin]. A limit that had to be fetched separately is
  /// a limit somebody will eventually not fetch.
  final PermissionLimit? limit;

  /// Set when the permission was lent for this one action. The caller must put
  /// it on the audit row: an approved discount with no approver on the record
  /// is indistinguishable from one nobody approved.
  final PosStaff? approvedBy;

  /// Why, when the approval flow asked. Travels on the decision rather than
  /// being returned alongside it, so a caller cannot commit the act and forget
  /// to record the reason — the two arrive together or not at all.
  final ReasonSelection? reason;

  bool get wasOverridden => approvedBy != null;
}

/// The person lacks [capability], but somebody who holds it may approve this
/// one action at the till.
class NeedsOverride extends PermissionDecision {
  const NeedsOverride(this.capability);

  final String capability;
}

/// The person lacks [capability] and no override exists for it.
class Denied extends PermissionDecision {
  const Denied(this.capability);

  final String capability;
}

/// The person **holds** [capability], but not for an amount this large.
///
/// A third refusal rather than a `Denied`, because it is the one that turns a
/// 30% discount request from a cashier capped at 10% into a manager walking
/// over — not a flat "you may not discount", which is both untrue and the
/// wrong instruction. The requested and permitted figures travel with it so the
/// prompt can say which is which.
class DeniedByLimit extends PermissionDecision {
  const DeniedByLimit({
    required this.capability,
    required this.limit,
    this.requestedBp,
    this.requestedMinor,
  });

  final String capability;
  final PermissionLimit limit;
  final int? requestedBp;
  final int? requestedMinor;

  /// Whether somebody holding a higher ceiling could approve this at the till.
  bool get mayBeLent => PosCapability.mayBeLent(capability);
}

/// Whether a capability may be exercised, and by whom.
///
/// Every check in the app goes through here — the widgets that disable a
/// control and the repositories that refuse a write ask the same question of
/// the same function, so a screen can never be more permissive than the data
/// layer behind it. The reverse would be a UI that offers an action the write
/// then rejects; this way the UI can only ever be *less* permissive, which is
/// the harmless direction.
abstract final class Authorization {
  /// [staff] is null when nobody has signed in. That is a denial, not a
  /// permissive default: an unattended till must not be a till with every
  /// permission.
  static PermissionDecision check(PosStaff? staff, String capability) {
    final wanted = PosCapability.canonical(capability);
    if (staff != null && staff.isActive && staff.can(wanted)) {
      return Allowed(limit: staff.limitFor(_limitKeyFor(wanted)));
    }
    // `mayBeLent`, not the raw set: a CRITICAL permission is never lendable,
    // however it was listed. See [PermissionRisk.mayBeLent].
    if (PosCapability.mayBeLent(wanted)) return NeedsOverride(wanted);
    return Denied(wanted);
  }

  /// The same question, for an act with a size to it.
  ///
  /// Checked here rather than by each caller because the two halves belong
  /// together: a screen that asked "may I discount?" and then applied its own
  /// idea of the ceiling would be a screen that could be more permissive than
  /// the rule, and the whole point of routing every check through this file is
  /// that it cannot.
  ///
  /// [base] and [amount] are both taken so a fixed-value request can be
  /// measured against a percentage ceiling — a cashier capped at 10% reaching
  /// for 50 off a 100 order is asking for 50%, and checking only the cash
  /// ceiling would make the percentage one avoidable by picking the other kind.
  static PermissionDecision checkWithin(
    PosStaff? staff,
    String capability, {
    required int baseMinor,
    required int amountMinor,
  }) {
    final decision = check(staff, capability);
    if (decision is! Allowed) return decision;

    final limit = decision.limit;
    if (limit == null || limit.isUnlimited) return decision;

    final cap = limit.maxMinor;
    final overCash = cap != null && amountMinor > cap;
    // Cross-multiplied rather than divided, so there is no rounding step
    // sitting on the boundary: exactly at the limit is permitted, one piastre
    // over it is not.
    final bp = limit.maxBp;
    final overShare =
        bp != null && baseMinor > 0 && amountMinor * 10000 > baseMinor * bp;

    if (!overCash && !overShare) return decision;

    return DeniedByLimit(
      capability: PosCapability.canonical(capability),
      limit: limit,
      requestedMinor: amountMinor,
      requestedBp: baseMinor > 0 ? (amountMinor * 10000) ~/ baseMinor : null,
    );
  }

  /// Which ceiling, if any, governs [capability].
  ///
  /// A map rather than a field on the capability because most capabilities
  /// have no size to them: opening a drawer is not larger or smaller.
  static String _limitKeyFor(String capability) => switch (capability) {
    PosCapability.discountApply || PosCapability.priceOverride =>
      LimitKey.discount,
    PosCapability.orderRefund => LimitKey.refund,
    PosCapability.cashMovement => LimitKey.cashPayOut,
    _ => '',
  };

  /// Resolve a [NeedsOverride] with the person who just entered their PIN.
  ///
  /// An approver who does not hold the capability is refused rather than
  /// treated as absent — the alternative is a supervisor discovering that their
  /// PIN "worked" for something they were never granted.
  static PermissionDecision approve({
    required PosStaff? approver,
    required String capability,
    ReasonSelection? reason,
  }) {
    final wanted = PosCapability.canonical(capability);
    if (!PosCapability.mayBeLent(wanted)) return Denied(wanted);
    if (approver == null || !approver.isActive || !approver.can(wanted)) {
      return NeedsOverride(wanted);
    }
    // The approver's ceiling, not the requester's: the act is being performed
    // on the approver's authority, so it is their limit that binds it. A
    // supervisor capped at 20% cannot approve 30% by standing next to somebody
    // capped at 10%.
    return Allowed(
      approvedBy: approver,
      reason: reason,
      limit: approver.limitFor(_limitKeyFor(wanted)),
    );
  }

  /// Why a role cannot be saved as written, or null if it can.
  ///
  /// Two rules, both of them requirements rather than taste: the owner role
  /// keeps everything, so a restaurant can always reach the screen that grants
  /// permissions; and a cashier role holds nothing from
  /// [PosCapability.backOffice], so the credential sitting on a machine in a
  /// public room cannot reprice the menu.
  static RoleRefusal? validateRole(PosRole role) {
    if (role.code == SystemRoles.ownerCode &&
        !PosCapability.all.every(role.capabilities.contains)) {
      return const OwnerMustKeepEverything();
    }
    if (role.code == SystemRoles.cashierCode) {
      final forbidden = role.capabilities.intersection(
        PosCapability.backOffice,
      );
      if (forbidden.isNotEmpty) return CashiersAreNotAdministrators(forbidden);
    }
    return null;
  }
}

sealed class RoleRefusal {
  const RoleRefusal();
}

class OwnerMustKeepEverything extends RoleRefusal {
  const OwnerMustKeepEverything();
}

class CashiersAreNotAdministrators extends RoleRefusal {
  const CashiersAreNotAdministrators(this.capabilities);

  final Set<String> capabilities;
}
