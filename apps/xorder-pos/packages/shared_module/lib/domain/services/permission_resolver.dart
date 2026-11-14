/// Working out what one person may actually do (§106).
///
/// **Pure, and separate from [Authorization] on purpose.** Resolution happens
/// once, when a staff row is read: the roles are unioned, the overrides are
/// applied, the limits are tightened, and the result is carried on the
/// [PosStaff] for the rest of the session. `Authorization.check` then answers a
/// single question against an already-resolved set, which is why every widget
/// in the app can ask it on every build without touching a database.
///
/// Doing it the other way — resolving inside each check — would put five
/// queries behind a greyed-out button.
library;

import '../models/permissions.dart';

/// What somebody may do, after everything has been taken into account.
class EffectivePermissions {
  const EffectivePermissions({
    required this.capabilities,
    this.limits = const {},
    this.deniedByOverride = const {},
  });

  static const none = EffectivePermissions(capabilities: {});

  final Set<String> capabilities;

  /// Ceilings, by [LimitKey]. Absent means unlimited.
  final Map<String, PermissionLimit> limits;

  /// What a DENY override took away that the roles had granted.
  ///
  /// Kept rather than discarded so the staff editor can show *"denied for this
  /// person"* instead of an unticked box that looks identical to one nobody
  /// ever ticked. Those are different facts and a manager reviewing access
  /// needs to tell them apart.
  final Set<String> deniedByOverride;

  bool holds(String capability) =>
      capabilities.contains(PosCapability.canonical(capability));

  PermissionLimit limitFor(String key) =>
      limits[key] ?? PermissionLimit.unlimited;
}

abstract final class PermissionResolver {
  /// §106, in order.
  ///
  /// 1. is the person active; 2. does this terminal permit them; 3. gather
  /// roles; 4. union their permissions; 5. apply overrides, DENY winning;
  /// 6. tighten limits; 7. hand back the result.
  ///
  /// Steps 1 and 2 are absolute: an inactive person and a person barred from
  /// this till both resolve to nothing at all rather than to a smaller set. A
  /// disabled account that kept its low-risk permissions would be an account
  /// that can still sell.
  static EffectivePermissions resolve({
    required bool isActive,
    required Iterable<PosRole> roles,
    Iterable<PermissionOverride> overrides = const [],
    Map<String, PermissionLimit> roleLimits = const {},
    Map<String, PermissionLimit> staffLimits = const {},
    bool terminalPermits = true,
  }) {
    if (!isActive || !terminalPermits) return EffectivePermissions.none;

    // 3–4. The union. Two roles that each hold half of what somebody needs is
    // the ordinary reason for having two.
    final granted = <String>{
      for (final role in roles)
        for (final capability in role.capabilities)
          PosCapability.canonical(capability),
    };

    // 5. Overrides. DENY is applied after ALLOW rather than in one pass, so an
    // ALLOW and a DENY on the same key resolve to DENY however they were
    // ordered in the table — "this person, despite everything" is what an
    // override is for, and the safe direction has to be the one that wins.
    final denied = <String>{};
    for (final override in overrides) {
      if (override.effect == OverrideEffect.allow) {
        granted.add(PosCapability.canonical(override.capability));
      }
    }
    for (final override in overrides) {
      if (override.effect == OverrideEffect.deny) {
        final key = PosCapability.canonical(override.capability);
        if (granted.remove(key)) denied.add(key);
      }
    }

    // 6. Limits. The person's own ceiling tightens the role's rather than
    // replacing it: a manager capped at 20% who is personally capped at 5% is
    // capped at 5%, and one personally set to 50% is still capped at 20%. A
    // per-person limit that could *raise* a role's would be a way to grant
    // authority without granting a permission, which is exactly the thing the
    // audit trail could not then explain.
    final limits = <String, PermissionLimit>{};
    for (final key in {...roleLimits.keys, ...staffLimits.keys}) {
      final fromRole = roleLimits[key] ?? PermissionLimit.unlimited;
      final fromStaff = staffLimits[key] ?? PermissionLimit.unlimited;
      final tightened = fromRole.tightenedBy(fromStaff);
      if (!tightened.isUnlimited) limits[key] = tightened;
    }

    return EffectivePermissions(
      capabilities: granted,
      limits: limits,
      deniedByOverride: denied,
    );
  }

  /// The tightest ceiling across several roles, for one key.
  ///
  /// Used when a person holds more than one role: see
  /// [PermissionLimit.tightenedBy] for why the tighter one wins.
  static Map<String, PermissionLimit> tightest(
    Iterable<Map<String, PermissionLimit>> perRole,
  ) {
    final result = <String, PermissionLimit>{};
    for (final limits in perRole) {
      for (final entry in limits.entries) {
        result[entry.key] =
            (result[entry.key] ?? PermissionLimit.unlimited).tightenedBy(
              entry.value,
            );
      }
    }
    return result;
  }
}
