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
  const Allowed({this.approvedBy, this.reason, this.limit, this.approval});

  /// The record of the one act a supervisor approved, when one did. What a
  /// repository is shown before it writes — see [Authorization.authorize].
  final Approval? approval;

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

/// One act a supervisor approved at the till: what, by whom, and for what.
///
/// **A record, and a spent one once used.** An approval used to be a name the
/// screen carried to the write. Nothing said which act it was for, and nothing
/// stopped the same name being carried to a second one. Now it states the
/// capability and — where the screen knows it — the thing it was for (an
/// order, a ticket, a shift), and [Authorization.authorize] spends it the first
/// time it lets somebody do what they could not do on their own.
///
/// In-process, so not a cryptographic token: code inside the app could build
/// one without anybody's PIN, through [Authorization.approve]. What it stops is
/// the flow mistake — an approval kept from an earlier act, or one approval
/// stretched over two refunds — and what it keeps is who answered for the act.
class Approval {
  Approval._({
    required this.capability,
    required this.approver,
    this.subject,
    this.reason,
  });

  final String capability;
  final PosStaff approver;

  /// What it was given for, in the caller's words — an order id, a ticket id,
  /// a shift id. Null when the act has no single thing (opening the drawer).
  final String? subject;
  final ReasonSelection? reason;

  bool _spent = false;

  /// Whether an act has already been allowed on it.
  bool get isSpent => _spent;
}

/// A repository was asked to write something the person may not do.
///
/// **An exception, where refusals in this codebase are usually data** — and
/// deliberately. Every screen asks [Authorization] first and turns "no" into
/// words or a supervisor prompt. A write that still arrives without authority
/// has gone round a screen, which is a defect to surface loudly rather than an
/// ordinary outcome to render.
class PermissionRefused implements Exception {
  const PermissionRefused(this.capability, this.decision);

  final String capability;
  final PermissionDecision decision;

  @override
  String toString() =>
      'PermissionRefused: $capability (${decision.runtimeType})';
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
  ///
  /// [subject] is what the approval is for — see [Approval.subject].
  static PermissionDecision approve({
    required PosStaff? approver,
    required String capability,
    ReasonSelection? reason,
    String? subject,
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
      approval: Approval._(
        capability: wanted,
        approver: approver,
        subject: subject,
        reason: reason,
      ),
    );
  }

  /// What a repository asks before it writes: may [by] do this, on their own
  /// authority or on [approval]'s?
  ///
  /// The screens ask first and bring a supervisor over; this is the backstop
  /// that holds when something goes round a screen. [approval] counts only if
  /// it was given for [capability] — and for [subject], when both name one —
  /// by somebody who may still give it, and has not been spent. It is spent
  /// here, and only when it was needed: shown by somebody who holds the
  /// permission anyway, it stays unspent.
  ///
  /// [approvalRequired] is for the acts that need a **second person** whoever
  /// is doing them: a refund above the restaurant's threshold, somebody else's
  /// drawer. Holding the permission is then not enough, and the approver may
  /// not be the person asking — otherwise "a second person approved it" is a
  /// supervisor typing their own PIN twice.
  static PermissionDecision authorize(
    PosStaff? by,
    String capability, {
    Approval? approval,
    String? subject,
    bool approvalRequired = false,
  }) {
    final own = check(by, capability);
    if (own is Allowed && !approvalRequired) return own;

    final wanted = PosCapability.canonical(capability);
    // What to answer when the approval does not stand up: the person's own
    // answer, or — when they hold it but a second person was needed — the
    // prompt that brings one over.
    final refused = own is Allowed ? NeedsOverride(wanted) : own;

    if (approval == null) return refused;
    if (approval.isSpent || approval.capability != wanted) return refused;
    if (approval.subject != null &&
        subject != null &&
        approval.subject != subject) {
      return refused;
    }
    if (approvalRequired && by != null && approval.approver.id == by.id) {
      return refused;
    }

    // Re-asked of the approver, not trusted from when it was given: somebody
    // disabled, or moved off a role, between the PIN and the write no longer
    // answers for anything.
    final lent = approve(
      approver: approval.approver,
      capability: wanted,
      reason: approval.reason,
      subject: approval.subject,
    );
    if (lent is! Allowed) return refused;

    approval._spent = true;
    return Allowed(
      approvedBy: approval.approver,
      reason: approval.reason,
      limit: lent.limit,
      approval: approval,
    );
  }

  /// [authorize], for a repository: the decision when it allows, and a
  /// [PermissionRefused] when it does not.
  static Allowed require(
    PosStaff? by,
    String capability, {
    Approval? approval,
    String? subject,
    bool approvalRequired = false,
  }) => switch (authorize(
    by,
    capability,
    approval: approval,
    subject: subject,
    approvalRequired: approvalRequired,
  )) {
    final Allowed allowed => allowed,
    final refused => throw PermissionRefused(capability, refused),
  };

  /// Why a role cannot be saved as written, or null if it can.
  ///
  /// Two rules, both of them requirements rather than taste: the owner role
  /// keeps everything, so a restaurant can always reach the screen that grants
  /// permissions; and a cashier role holds nothing from
  /// [PosCapability.backOffice], so the credential sitting on a machine in a
  /// public room cannot reprice the menu.
  static RoleRefusal? validateRole(PosRole role, {PosStaff? editedBy}) {
    // §48 — a person may only grant a permission they hold themselves.
    //
    // **This is the rule that stops the permission model being decorative.**
    // Without it, anybody with `staff.manage` — a shift manager, say — writes
    // themselves a role holding `backup.manage` and the whole catalogue of
    // permissions becomes one checkbox deep. It is enforced here rather than in
    // the role editor because a widget is not a control: the repository asks
    // the same function before it writes.
    //
    // Only what the edit is *adding* is checked. Somebody who cannot refund is
    // still allowed to rename a role that grants refunds, and to take the
    // permission away — removing authority you do not hold is safe, and
    // refusing it would mean a manager could not revoke anything an owner had
    // granted.
    if (editedBy != null) {
      final adding = role.capabilities
          .map(PosCapability.canonical)
          .where((c) => !editedBy.can(c))
          .toSet();
      if (adding.isNotEmpty) return CannotGrantWhatYouLack(adding);
    }
    return _validateRoleShape(role);
  }

  static RoleRefusal? _validateRoleShape(PosRole role) {
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

/// §48 — the editor tried to grant something they do not hold.
///
/// Names the capabilities rather than saying "not permitted", because the
/// person doing this is a manager who almost certainly did not realise: they
/// ticked a box on a template. Telling them which one is the difference between
/// a fixable mistake and a screen that refuses without saying why.
class CannotGrantWhatYouLack extends RoleRefusal {
  const CannotGrantWhatYouLack(this.capabilities);

  final Set<String> capabilities;
}
