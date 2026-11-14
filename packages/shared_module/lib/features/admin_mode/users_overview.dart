import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';

/// Which accounts the Users table shows, by whether their PIN works.
///
/// An enum rather than a nullable bool, so that the label switch in
/// `AdminText.staffStatus` is exhaustive — a fourth state added here fails to
/// compile until somebody names it in both languages.
enum StaffStatusFilter { all, active, disabled }

/// The Users table's filters: status, role and a name search.
///
/// In memory over the directory the pane has already loaded. A business has
/// tens of staff, not thousands, and a query per keystroke would put a round
/// trip to the branch server between a manager and a list that fits on screen.
class StaffFilter {
  const StaffFilter({
    this.status = StaffStatusFilter.all,
    this.roleId,
    this.search = '',
  });

  final StaffStatusFilter status;

  /// The person's own role — the one the table shows and they would call
  /// their job. Extra roles (§11) are deliberately not matched: filtering for
  /// "Cashier" and getting the supervisor who covers the odd shift would make
  /// the filter disagree with the role column beside it.
  final int? roleId;
  final String search;

  StaffFilter copyWith({
    StaffStatusFilter? status,
    int? Function()? roleId,
    String? search,
  }) => StaffFilter(
    status: status ?? this.status,
    roleId: roleId == null ? this.roleId : roleId(),
    search: search ?? this.search,
  );

  bool admits(PosStaff person) {
    final statusOk = switch (status) {
      StaffStatusFilter.all => true,
      StaffStatusFilter.active => person.isActive,
      StaffStatusFilter.disabled => !person.isActive,
    };
    if (!statusOk) return false;
    if (roleId != null && person.role?.id != roleId) return false;

    // A leading "@" is dropped because the table prints usernames that way,
    // and somebody copying what they see must find what they copied.
    final wanted = search.trim().toLowerCase().replaceFirst(RegExp('^@'), '');
    if (wanted.isEmpty) return true;
    return person.name.toLowerCase().contains(wanted) ||
        (person.username?.toLowerCase().contains(wanted) ?? false);
  }

  List<PosStaff> apply(List<PosStaff> people) => [
    for (final person in people)
      if (admits(person)) person,
  ];
}

/// The four figures over the Users table.
class UsersKpis {
  const UsersKpis({
    required this.total,
    required this.active,
    required this.openShifts,
    required this.roles,
  });

  factory UsersKpis.of({
    required List<PosStaff> people,
    required List<PosRole> roles,
    required ShiftActivity activity,
  }) => UsersKpis(
    total: people.length,
    active: people.where((p) => p.isActive).length,
    openShifts: activity.openShifts,
    roles: roles.length,
  );

  /// Every account, disabled included. Nobody is ever deleted, so this is
  /// everybody who has ever worked here — which is why [active] sits beside it.
  final int total;
  final int active;
  final int openShifts;
  final int roles;

  /// Active as a whole percentage of [total]; null when there is nobody.
  ///
  /// **Rounded down, here and only here.** Rounding to nearest would print
  /// "100%" for 199 of 200, and the one disabled account is the thing a
  /// manager reading that tile is looking for.
  int? get activePercent => total == 0 ? null : active * 100 ~/ total;
}

/// What each role grants, group by group — the matrix beside the Users table.
///
/// **Generated, never drawn.** Rows are [CapabilityGroup], the grouping the
/// Roles pane edits in, so a row here reads against the section of the editor
/// that changes it; columns are the business's roles as loaded; each cell is
/// counted from the role's own capability set. A hand-drawn table would have
/// been simpler to lay out and would have been wrong the first time an owner
/// ticked a box — and a matrix that disagrees with the Roles pane is worse
/// than none, because it is the one people read.
///
/// Grouped by [CapabilityGroup] rather than by the back-office tab each
/// capability unlocks, as plan 19 first sketched: half the capabilities —
/// selling, the drawer — unlock no tab at all, and would have had no row.
///
/// **Role grants only.** A person's extra roles and their ALLOW / DENY
/// exceptions are not here; the pane says so under the matrix.
class RoleMatrix {
  RoleMatrix(this.roles)
    : _held = {
        for (final role in roles)
          role.id: PosCapability.canonicalAll(role.capabilities),
      };

  final List<PosRole> roles;

  /// Canonical, because a role saved by an older build may still hold a
  /// capability under its former name, and `Authorization.check` honours it.
  final Map<int, Set<String>> _held;

  static const groups = CapabilityGroup.values;

  /// How many of [group]'s capabilities [role] grants.
  int held(CapabilityGroup group, PosRole role) {
    final held = _held[role.id] ?? const <String>{};
    return group.capabilities.where(held.contains).length;
  }

  static int size(CapabilityGroup group) => group.capabilities.length;
}
