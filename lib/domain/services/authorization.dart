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
  const Allowed({this.approvedBy, this.reason});

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
      return const Allowed();
    }
    if (PosCapability.overridable.contains(wanted)) {
      return NeedsOverride(wanted);
    }
    return Denied(wanted);
  }

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
    if (!PosCapability.overridable.contains(wanted)) return Denied(wanted);
    if (approver == null || !approver.isActive || !approver.can(wanted)) {
      return NeedsOverride(wanted);
    }
    return Allowed(approvedBy: approver, reason: reason);
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
