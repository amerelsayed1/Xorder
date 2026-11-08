import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/deployment.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/destructive_confirm_dialog.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../application/users_overview.dart';
import 'admin_messages.dart';
import 'staff_grants_dialog.dart';
import '../../../core/security/pin_hash.dart';

/// Who works here — Settings › Users.
///
/// Nobody is ever deleted. A member of staff who left is still the person named
/// on last March's shifts and on the audit rows for everything they changed, so
/// the only thing this screen can do is disable them — which stops the PIN
/// working and leaves the history intact.
///
/// BO-7 laid the cloud's Users page over it: four tiles, filters, a last-shift
/// column and a matrix of what each role grants. Every action the pane had
/// before — add, permissions, PIN, disable, role — is on the same row, under
/// the same keys, because the owner rules in `owner_rule_test.dart` are
/// pinned to them.
class ManagementStaffPane extends ConsumerStatefulWidget {
  const ManagementStaffPane({
    required this.admin,
    this.onManageRoles,
    super.key,
  });

  final PosStaff admin;

  /// Opens Settings › Roles. Null hides the button, for a host with no Roles
  /// pane to open.
  final VoidCallback? onManageRoles;

  @override
  ConsumerState<ManagementStaffPane> createState() =>
      _ManagementStaffPaneState();
}

class _ManagementStaffPaneState extends ConsumerState<ManagementStaffPane> {
  var _filter = const StaffFilter();
  final _search = TextEditingController();

  PosStaff get admin => widget.admin;

  /// From this pane width the matrix sits beside the table, as the mockup
  /// draws it; below, it goes under the table.
  ///
  /// Beside needs the table's fixed columns — the buttons sized for Arabic,
  /// the longer language — plus a name worth reading, next to a matrix that
  /// holds a column per role. That is a 1920 screen. On a 1366 or 1440 one,
  /// beside would leave the name column an ellipsis.
  ///
  /// **1600 since the owner's map (14 Sep 2026) moved Users to People**, where
  /// no side nav stands beside it. 1400 was chosen under Settings, whose
  /// 232 px nav left a 1440 screen's pane at about 1208; with the whole width,
  /// the same 1440 screen crossed 1400 and put the matrix beside after all.
  /// The rule is the screens, not the number: beside on 1920, under on 1440.
  static const _matrixBesideFrom = 1600.0;
  static const _matrixWidth = 380.0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffDirectoryProvider);
    final roles = ref.watch(rolesProvider);
    // Read beside the directory, not before it: the shift facts are two
    // columns and a tile, and a branch server slow to answer them must not
    // hold the list of people — and every action on it — behind a spinner.
    // Until they arrive, or if they never do, they read "—".
    final activity = ref.watch(shiftActivityProvider).valueOrNull;
    // Beside the directory for the same reason: who has an Admin Mode
    // password is one button on some rows, and until it answers — or if it
    // never does — the button is simply not offered.
    final passwords = ref.watch(staffWithPasswordProvider).valueOrNull;

    return staff.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => _Centred(text: '$error'),
      data: (people) => _body(
        context,
        people,
        roles.valueOrNull,
        activity,
        passwords ?? const {},
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<PosStaff> people,
    List<PosRole>? roles,
    ShiftActivity? activity,
    Set<int> passwords,
  ) {
    // A role deleted while its filter was chosen: the dropdown already shows
    // "all roles" for a value it no longer offers, so the table must too, or
    // the two would disagree and the table would read as empty for no reason.
    final filter =
        _filter.roleId != null &&
            !(roles ?? const <PosRole>[]).any((r) => r.id == _filter.roleId)
        ? _filter.copyWith(roleId: () => null)
        : _filter;
    final shown = filter.apply(people);
    final ownerTaken = _hasActiveOwner(people);

    final table = _StaffTable(
      filtered: shown.length != people.length,
      rows: [
        for (final person in shown)
          _StaffRow(
            staff: person,
            isSelf: person.id == admin.id,
            admin: admin,
            roles: roles ?? const [],
            ownerTaken: ownerTaken,
            activity: activity,
            hasPassword: passwords.contains(person.id),
            onAction: (action) => _act(context, ref, person, action),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // On a cloud till the bundle owns who works here — see
        // `PostgresStaffDirectoryRepository.offline`. Said once at the top
        // rather than as four identical refusals: a manager who reads this
        // knows where to go, and the half that still works (roles and
        // permissions) is named in the same sentence.
        if (ref.watch(deploymentProvider).mode != DeploymentMode.offline)
          Container(
            padding: const EdgeInsets.all(PosSpace.lg),
            color: context.pos.warnSoft,
            child: Text(
              context.strings.staffComesFromPlatform,
              style: PosText.ui(
                size: 12.5,
                color: context.pos.warn,
                height: 1.5,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(PosSpace.xl),
          decoration: BoxDecoration(
            border: Border(bottom: context.pos.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _seatLine(context, ref, people),
                  style: PosText.ui(size: 13, color: context.pos.muted),
                ),
              ),
              if (widget.onManageRoles case final open?) ...[
                PosButton(
                  key: const Key('users-manage-roles'),
                  label: context.strings.manageRoles,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: open,
                ),
                const SizedBox(width: PosSpace.sm),
              ],
              PosButton(
                label: context.strings.addSomebody,
                background: context.pos.accent,
                foreground: Colors.white,
                fontWeight: FontWeight.w700,
                onPressed:
                    roles == null ||
                        ref.watch(deploymentProvider).mode !=
                            DeploymentMode.offline
                    ? null
                    : () => _add(context, ref, roles, people),
              ),
            ],
          ),
        ),
        _KpiStrip(
          kpis: UsersKpis.of(
            people: people,
            roles: roles ?? const [],
            activity: activity ?? ShiftActivity.empty,
          ),
          rolesKnown: roles != null,
          shiftsKnown: activity != null,
        ),
        _FilterBar(
          filter: filter,
          roles: roles ?? const [],
          search: _search,
          onChanged: (next) => setState(() => _filter = next),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final matrix = roles == null || roles.isEmpty
                  ? null
                  : _RoleMatrixPanel(matrix: RoleMatrix(roles));

              if (matrix != null &&
                  constraints.maxWidth >= _matrixBesideFrom) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: SingleChildScrollView(child: table)),
                    Container(
                      width: _matrixWidth,
                      decoration: BoxDecoration(
                        border: BorderDirectional(
                          start: context.pos.hairline,
                        ),
                      ),
                      child: SingleChildScrollView(child: matrix),
                    ),
                  ],
                );
              }

              // Under the table, in the same scroll, rather than pinned below
              // it: pinned, the matrix would take a quarter of the height
              // away from the list on every visit, to answer a question asked
              // once in a while.
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    table,
                    if (matrix != null)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(top: context.pos.hairline),
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _matrixWidth * 1.5,
                            ),
                            child: matrix,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<PosRole> roles,
    List<PosStaff> people,
  ) async {
    // Checked BEFORE the dialog, not after it. Asking somebody for a name, a
    // username and a PIN and only then saying the licence has no room for them
    // is a refusal that wastes the work it just asked for.
    //
    // Counted against ACTIVE staff: nobody is ever deleted here — a person who
    // left is still the name on last March's shifts — so counting rows would
    // let a business's history consume the seats it is paying for.
    final cap = ref.read(licenceClaimsProvider).valueOrNull?.maxUsers;
    if (cap != null && people.where((p) => p.isActive).length >= cap) {
      _report(context, ref, UserSeatsExhausted(cap));
      return;
    }

    // Owner is not offered while somebody holds it — the repository would
    // refuse it, and a choice that is always refused teaches people to stop
    // reading refusals.
    final draft = await StaffEditorDialog.show(
      context,
      roles: [
        for (final role in roles)
          if (role.code != SystemRoles.ownerCode || !_hasActiveOwner(people))
            role,
      ],
    );
    if (draft == null) return;

    final result = await ref
        .read(staffDirectoryRepositoryProvider)
        .create(
          by: admin,
          name: draft.name,
          username: draft.username,
          pin: draft.pin!,
          roleId: draft.roleId,
        );
    if (context.mounted) _report(context, ref, result.refusal);
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    PosStaff person,
    _StaffAction action,
  ) async {
    final repository = ref.read(staffDirectoryRepositoryProvider);

    final refusal = switch (action) {
      _SetActive(:final isActive) => (await repository.setActive(
        by: admin,
        staffId: person.id,
        isActive: isActive,
      )).refusal,
      _SetRole(:final roleId) => (await repository.update(
        by: admin,
        staffId: person.id,
        roleId: roleId,
      )).refusal,
      _ResetPin(:final pin) => (await repository.resetPin(
        by: admin,
        staffId: person.id,
        pin: pin,
      )).refusal,
      _ClearPassword() => (await repository.clearPassword(
        by: admin,
        staffId: person.id,
      )).refusal,
      _SetGrants(:final grants) => (await repository.setGrants(
        by: admin,
        staffId: person.id,
        extraRoleIds: grants.extraRoleIds,
        overrides: grants.overrides,
        limits: grants.limits,
      )).refusal,
    };

    if (context.mounted) _report(context, ref, refusal);
  }

  /// Whether somebody active already owns the business.
  ///
  /// Active only, as the repository counts: once the owner is disabled Owner
  /// is offered again, which is how ownership is handed over from this pane.
  static bool _hasActiveOwner(List<PosStaff> people) => people.any(
    (p) => p.isActive && p.role?.code == SystemRoles.ownerCode,
  );

  /// "4 of 7 active" — and, when the licence caps them, what the cap is.
  ///
  /// A manager who can see the seat count coming does not discover it by being
  /// refused halfway through hiring somebody.
  String _seatLine(BuildContext context, WidgetRef ref, List<PosStaff> people) {
    final active = people.where((p) => p.isActive).length;
    final cap = ref.watch(licenceClaimsProvider).valueOrNull?.maxUsers;

    return cap == null
        ? context.strings.staffCount(active, people.length)
        : context.strings.staffCountLicensed(active, people.length, cap);
  }

  void _report(BuildContext context, WidgetRef ref, AdminRefusal? refusal) {
    ref.invalidate(staffDirectoryProvider);
    ref.invalidate(staffWithPasswordProvider);
    if (refusal == null) return;

    // A refusal is shown where the action was, not as a toast that has gone by
    // the time somebody looks up from the keypad.
    //
    // Everything inside the dialog reads the dialog's OWN context. The pane's
    // can be gone by the time Close is tapped — the screen was swapped, the
    // till locked — and `Navigator.of` on an unmounted element throws "Null
    // check operator used on a null value" (XORD-010).
    showDialog<void>(
      context: context,
      barrierColor: context.pos.scrim,
      builder: (dialogContext) => Dialog(
        backgroundColor: dialogContext.pos.page,
        shape: RoundedRectangleBorder(
          side: dialogContext.pos.emphasis,
          borderRadius: PosBorders.radius,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(PosSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dialogContext.strings.notSaved, style: PosText.panelTitle(color: dialogContext.pos.ink)),
                const SizedBox(height: PosSpace.sm),
                Text(
                  AdminText.refusal(dialogContext.strings, refusal),
                  style: PosText.ui(
                    size: 13,
                    color: dialogContext.pos.body,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: PosSpace.lg),
                PosButton(
                  label: dialogContext.strings.close,
                  border: Border.fromBorderSide(dialogContext.pos.resting),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

sealed class _StaffAction {
  const _StaffAction();
}

class _SetActive extends _StaffAction {
  const _SetActive(this.isActive);

  final bool isActive;
}

class _SetRole extends _StaffAction {
  const _SetRole(this.roleId);

  final int roleId;
}

/// §105, §16 — the exceptions and ceilings dialog handed back its result.
class _SetGrants extends _StaffAction {
  const _SetGrants(this.grants);

  final StaffGrants grants;
}

class _ResetPin extends _StaffAction {
  const _ResetPin(this.pin);

  final String pin;
}

/// Their Admin Mode password taken away: next time they come in on their PIN
/// and choose a new one. Never offered on the owner's row — see
/// [OwnerPasswordIsTheirs].
class _ClearPassword extends _StaffAction {
  const _ClearPassword();
}

/// One person's line in the table.
///
/// A [TableRow] rather than a widget of its own, so that every column — the
/// buttons included — is as wide as its widest cell on any row, and the header
/// sits over what it names. The first cut was a `Row` per person with the
/// buttons in a fixed-width slot: the slot overflowed the moment the labels
/// were longer than guessed, and without it "Disable" against "Enable" moved
/// every column after them by the difference.
class _StaffRow {
  const _StaffRow({
    required this.staff,
    required this.isSelf,
    required this.roles,
    required this.onAction,
    required this.admin,
    required this.ownerTaken,
    required this.activity,
    required this.hasPassword,
  });

  final PosStaff staff;

  /// Whether they have an Admin Mode password. Shown as a line under the
  /// username, and the only rows that offer Clear password.
  final bool hasPassword;
  final bool isSelf;
  final List<PosRole> roles;
  final ValueChanged<_StaffAction> onAction;

  /// Whether somebody active owns the business. Owner is not offered on
  /// anybody else's row while they do.
  final bool ownerTaken;

  /// On the owner role, active or not. Their permissions are shut either way:
  /// nothing in that dialog means anything on the role that holds everything.
  bool get _onOwnerRole => staff.role?.code == SystemRoles.ownerCode;

  /// THE owner. Their role is fixed; a disabled former owner's is not, or they
  /// could never come back as anything else — see [OwnerIsFixed].
  bool get _isTheOwner => _onOwnerRole && staff.isActive;

  /// Who is editing. The grants dialog needs it for §48 — an ALLOW for
  /// something the editor lacks is granting a permission they do not hold.
  final PosStaff admin;

  /// The branch's shift facts; null until they load, or if they cannot.
  final ShiftActivity? activity;

  TableRow build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;

    // Faded rather than hidden: a disabled account is still the name on its
    // shifts, and still one button from working again.
    Widget cell(
      Widget child, {
      EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
        horizontal: PosSpace.sm,
        vertical: PosSpace.lg,
      ),
    }) => Opacity(
      opacity: staff.isActive ? 1 : 0.5,
      child: Padding(padding: padding, child: child),
    );

    return TableRow(
      key: ValueKey('staff-row-${staff.id}'),
      decoration: BoxDecoration(
        border: Border(bottom: pos.hairline),
      ),
      children: [
        cell(
          _Initials(name: staff.name),
          padding: const EdgeInsetsDirectional.fromSTEB(
            PosSpace.lg,
            PosSpace.lg,
            PosSpace.sm,
            PosSpace.lg,
          ),
        ),
        cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      staff.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PosText.ui(color: pos.inkWarm, size: 14, weight: FontWeight.w600),
                    ),
                  ),
                  if (isSelf) ...[
                    const SizedBox(width: PosSpace.sm),
                    Text(strings.you, style: PosText.microLabel(color: pos.muted)),
                  ],
                ],
              ),
              const SizedBox(height: PosSpace.xs),
              // `@username`, as the cloud prints it. Set LTR: a username is
              // Latin, and in Arabic an "@" that drifts to the far end of the
              // word reads as a typo.
              Text(
                staff.username == null ? '—' : '@${staff.username}',
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PosText.mono(size: 11.5, color: pos.muted),
              ),
              // The extra grants a person has beyond their role, as a count:
              // the common case is zero, and a column that is empty for
              // everybody teaches nothing.
              if (staff.capabilities.isNotEmpty) ...[
                const SizedBox(height: PosSpace.xs),
                Text(
                  strings.extraCapabilities(staff.capabilities.length),
                  style: PosText.ui(size: 12, color: pos.warn),
                ),
              ],
              if (hasPassword) ...[
                const SizedBox(height: PosSpace.xs),
                Text(
                  strings.passwordSetLabel,
                  key: Key('password-set-${staff.id}'),
                  style: PosText.ui(size: 12, color: pos.muted),
                ),
              ],
            ],
          ),
        ),
        cell(_rolePicker(strings, pos: pos)),
        cell(
          Text(
            AdminText.staffStatus(
              strings,
              staff.isActive
                  ? StaffStatusFilter.active
                  : StaffStatusFilter.disabled,
            ),
            key: Key('status-${staff.id}'),
            style: PosText.ui(
              size: 12.5,
              weight: FontWeight.w600,
              color: staff.isActive ? pos.ok : pos.muted,
            ),
          ),
        ),
        cell(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _lastShift(strings, pos),
          ),
        ),
        cell(
          padding: const EdgeInsetsDirectional.fromSTEB(
            PosSpace.sm,
            PosSpace.lg,
            PosSpace.lg,
            PosSpace.lg,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PosButton(
                key: Key('grants-${staff.id}'),
                label: strings.grantsAction,
                border: Border.fromBorderSide(pos.resting),
                // Shut on the owner rather than left to refuse: extra roles
                // and exceptions on somebody who holds everything mean
                // nothing, and a DENY is a lock-out.
                onPressed: _onOwnerRole
                    ? null
                    : () async {
                  final grants = await StaffGrantsDialog.show(
                    context,
                    person: staff,
                    // Owner is never an extra role — see
                    // [OwnerIsNotAnExtraRole].
                    roles: [
                      for (final role in roles)
                        if (role.code != SystemRoles.ownerCode) role,
                    ],
                    admin: admin,
                  );
                  if (grants != null) onAction(_SetGrants(grants));
                },
              ),
              const SizedBox(width: PosSpace.sm),
              PosButton(
                key: Key('reset-pin-${staff.id}'),
                label: strings.resetPin,
                border: Border.fromBorderSide(pos.resting),
                // Shut on the owner's row for everybody but the owner — see
                // [OwnerPinIsTheirs]. Shut rather than left to refuse, as
                // Grants is: a button whose only answer is no is a button
                // that gets pressed again.
                onPressed: _onOwnerRole && !isSelf
                    ? null
                    : () async {
                  final pin = await PinPromptDialog.show(
                    context,
                    title: strings.newPinFor(staff.name),
                  );
                  if (pin != null) onAction(_ResetPin(pin));
                },
              ),
              // Only where there is a password to clear, and never on the
              // owner's row. Absent there rather than shut, unlike Reset
              // PIN: a shut button reads as "not now", and for the owner it
              // is "never from here" — the way that works is the technician
              // reset on the Admin Mode door. Absent on rows with no
              // password too, so a branch where nobody has set one yet sees
              // the table it always did.
              if (hasPassword && !_onOwnerRole) ...[
                const SizedBox(width: PosSpace.sm),
                PosButton(
                  key: Key('clear-password-${staff.id}'),
                  label: strings.clearPasswordAction,
                  border: Border.fromBorderSide(pos.resting),
                  onPressed: () async {
                    final confirmed = await DestructiveConfirmDialog.show(
                      context,
                      title: strings.clearPasswordTitle(staff.name),
                      confirmLabel: strings.clearPasswordAction,
                      keepLabel: strings.keepPassword,
                      consequences: [strings.clearPasswordConsequence],
                      requirement: ReasonRequirement.disabled,
                    );
                    if (confirmed != null) onAction(const _ClearPassword());
                  },
                ),
              ],
              const SizedBox(width: PosSpace.sm),
              PosButton(
                label: staff.isActive ? strings.disable : strings.enable,
                foreground: staff.isActive ? pos.danger : pos.ok,
                border: Border.fromBorderSide(pos.resting),
                onPressed: () => onAction(_SetActive(!staff.isActive)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The last shift this person opened at the branch, or that one is open.
  ///
  /// "Never" and "—" are different answers on purpose: never is a fact read
  /// from `pos_shifts`, and the dash is a read that has not come back.
  Widget _lastShift(AppStrings strings, PosPalette pos) {
    final key = Key('last-shift-${staff.id}');
    final known = activity;
    if (known == null) {
      return Text('—', key: key, style: PosText.mono(size: 12, color: pos.muted));
    }
    if (known.onShift.contains(staff.id)) {
      return Text(
        strings.usersOnShiftNow,
        key: key,
        style: PosText.ui(size: 12.5, weight: FontWeight.w600, color: pos.ok),
      );
    }
    final at = known.lastOpenedAt[staff.id];
    if (at == null) {
      return Text(
        strings.usersNeverOnShift,
        key: key,
        style: PosText.ui(size: 12.5, color: pos.muted),
      );
    }
    return Text(
      _stamp(at),
      key: key,
      textDirection: TextDirection.ltr,
      style: PosText.mono(size: 12, color: pos.body),
    );
  }

  Widget _rolePicker(AppStrings strings, {required PosPalette pos}) {
    if (roles.isEmpty) {
      return Text(
        staff.role?.displayName(strings.languageCode) ?? strings.noRole,
        style: PosText.ui(size: 13, color: pos.muted),
      );
    }

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DropdownButton<int>(
        key: Key('role-${staff.id}'),
        value: roles.any((r) => r.id == staff.role?.id) ? staff.role?.id : null,
        hint: Text(
          strings.noRole,
          style: PosText.ui(size: 13, color: pos.muted),
        ),
        // A disabled DropdownButton shows its hint, not its value. Without
        // this the owner's row would read "No role" — on the one row where
        // what the role is matters most.
        disabledHint: Text(
          staff.role?.displayName(strings.languageCode) ?? strings.noRole,
          style: PosText.ui(size: 13, color: pos.muted),
        ),
        underline: const SizedBox.shrink(),
        // Expanded to its column: a long role name must ellipsise rather
        // than push the row off the screen.
        isExpanded: true,
        style: PosText.ui(color: pos.inkWarm, size: 13),
        items: [
          for (final role in roles)
            // Owner is withheld while somebody else holds it — but kept on the
            // row of anybody already on it, because a DropdownButton whose
            // value is not among its items asserts.
            if (role.code != SystemRoles.ownerCode ||
                !ownerTaken ||
                role.id == staff.role?.id)
              DropdownMenuItem(
                value: role.id,
                child: Text(role.displayName(strings.languageCode)),
              ),
        ],
        // Disabled on the owner rather than left to refuse: a picker every
        // choice of which ends in "not saved" is ownership one misclick away
        // from being given away, were the refusal ever to go.
        onChanged: _isTheOwner
            ? null
            : (id) {
                if (id != null && id != staff.role?.id) onAction(_SetRole(id));
              },
      ),
    );
  }
}

const _avatarWidth = 32.0;

/// The narrowest the name and role columns go; past it the table scrolls
/// sideways instead. Any narrower and the role picker has no room for its own
/// arrow.
const _nameFloor = 120.0;

/// The same shape the backup pane stamps its copies with: year first, 24-hour,
/// in the terminal's own time. Latin digits in both languages.
String _stamp(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// The header and the rows — or, when the filters leave nobody, a sentence
/// saying so rather than a blank that reads as a failure to load.
///
/// Not lazily built: a business has tens of staff, and a [Table] is what
/// keeps every column the width of its widest cell. See [_StaffRow].
class _StaffTable extends StatelessWidget {
  const _StaffTable({required this.rows, required this.filtered});

  final List<_StaffRow> rows;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;

    Widget head(String text, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.sm,
        vertical: PosSpace.sm,
      ),
      child: MicroLabel(text, key: key),
    );

    final table = Table(
      columnWidths: const {
        0: FixedColumnWidth(_avatarWidth + PosSpace.lg + PosSpace.sm),
        1: MaxColumnWidth(FlexColumnWidth(3), FixedColumnWidth(_nameFloor)),
        2: MaxColumnWidth(FlexColumnWidth(3), FixedColumnWidth(_nameFloor)),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: pos.hairline),
          ),
          children: [
            const SizedBox.shrink(),
            head(strings.fieldName),
            head(strings.fieldRole),
            head(strings.usersColumnStatus),
            head(
              strings.usersColumnLastShift,
              key: const Key('users-column-last-shift'),
            ),
            const SizedBox.shrink(),
          ],
        ),
        for (final row in rows) row.build(context),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // At least as wide as the pane, and wider only when its columns need
        // it — then it scrolls sideways. A table squeezed to the pane instead
        // would take the whole squeeze out of the names, because the buttons
        // and the fixed columns do not shrink. A guessed floor width was the
        // alternative, and it is wrong in whichever language it was not
        // guessed in.
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: table,
            ),
          ),
        ),
        if (rows.isEmpty && filtered) _Centred(text: strings.usersNoneMatch),
      ],
    );
  }
}

/// The four figures over the table.
///
/// Flat and bordered, not the mockup's tinted cards: a pastel tile is the one
/// thing the design system rules out by name, and a figure reads as well on
/// the surface colour as on a wash.
class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.kpis,
    required this.rolesKnown,
    required this.shiftsKnown,
  });

  final UsersKpis kpis;
  final bool rolesKnown;
  final bool shiftsKnown;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final percent = kpis.activePercent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PosSpace.xl,
        PosSpace.lg,
        PosSpace.xl,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: _KpiTile(
              valueKey: const Key('users-kpi-staff'),
              label: strings.usersKpiStaff,
              value: '${kpis.total}',
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: _KpiTile(
              valueKey: const Key('users-kpi-active'),
              label: strings.usersKpiActive,
              value: '${kpis.active}',
              note: percent == null ? null : strings.usersActiveShare(percent),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: _KpiTile(
              valueKey: const Key('users-kpi-shifts'),
              label: strings.usersKpiShifts,
              value: shiftsKnown ? '${kpis.openShifts}' : '—',
              note: strings.usersKpiShiftsNote,
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: _KpiTile(
              valueKey: const Key('users-kpi-roles'),
              label: strings.usersKpiRoles,
              value: rolesKnown ? '${kpis.roles}' : '—',
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.valueKey,
    required this.label,
    required this.value,
    this.note,
  });

  final Key valueKey;
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(
        color: pos.surface,
        border: Border.fromBorderSide(pos.resting),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(label),
          const SizedBox(height: PosSpace.sm),
          Text(
            value,
            key: valueKey,
            textDirection: TextDirection.ltr,
            style: PosText.mono(
              size: 26,
              weight: FontWeight.w600,
              color: pos.ink,
              height: 1,
            ),
          ),
          const SizedBox(height: PosSpace.xs),
          // Always a line, empty when there is nothing to say, so the four
          // tiles stay one height and their figures one baseline.
          Text(
            note ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PosText.ui(size: 12, color: pos.muted),
          ),
        ],
      ),
    );
  }
}

/// Status, role and search, over the table.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.roles,
    required this.search,
    required this.onChanged,
  });

  final StaffFilter filter;
  final List<PosRole> roles;
  final TextEditingController search;
  final ValueChanged<StaffFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(
        border: Border(bottom: pos.hairline),
      ),
      child: Wrap(
        spacing: PosSpace.sm,
        runSpacing: PosSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final status in StaffStatusFilter.values)
            _FilterChip(
              key: Key('users-status-${status.name}'),
              label: AdminText.staffStatus(strings, status),
              selected: filter.status == status,
              onTap: () => onChanged(filter.copyWith(status: status)),
            ),
          _RoleFilter(
            everyone: strings.usersAllRoles,
            options: [
              for (final role in roles)
                (role.id, role.displayName(strings.languageCode)),
            ],
            selected: filter.roleId,
            onChanged: (id) => onChanged(filter.copyWith(roleId: () => id)),
          ),
          SizedBox(
            width: 240,
            height: PosSize.filterChip,
            child: TextField(
              key: const Key('users-search'),
              controller: search,
              onChanged: (text) => onChanged(filter.copyWith(search: text)),
              // Fills the box: a TextField is only as tall as its text unless
              // told to expand, so the bare SizedBox drew a short strip beside
              // the status chips (same fix as the history search).
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.center,
              style: PosText.ui(size: 13, color: pos.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: strings.usersSearchHint,
                hintStyle: PosText.ui(size: 13, color: pos.muted),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: PosSpace.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: pos.resting,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: pos.resting,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: pos.accentBorder,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The order history's filter chip, in the same shape: selection is a border.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Material(
      color: selected ? pos.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: PosSize.filterChip,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              selected ? pos.accentBorder : pos.resting,
            ),
          ),
          // Sized to its label — a Container with an alignment fills the
          // Wrap's whole line; see the history screen's chip.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: PosText.ui(
                  size: 12.5,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? pos.inkWarm : pos.body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One role, or all of them — the history screen's pick filter, for roles.
class _RoleFilter extends StatelessWidget {
  const _RoleFilter({
    required this.everyone,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String everyone;
  final List<(int, String)> options;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    // A role no longer offered is shown as "all roles" rather than handed to
    // the dropdown, which asserts when its value is not among its items.
    final value = options.any((option) => option.$1 == selected)
        ? selected
        : null;
    return Container(
      height: PosSize.filterChip,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(
          value == null ? pos.resting : pos.accentBorder,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          key: const Key('users-role-filter'),
          value: value,
          isDense: true,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.zero,
          style: PosText.ui(size: 12.5, color: pos.body),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(everyone)),
            for (final (id, label) in options)
              DropdownMenuItem<int?>(value: id, child: Text(label)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// What each role grants, group by group — see [RoleMatrix].
///
/// Read-only. It is edited in Settings › Roles, which the header's "Manage
/// roles" opens; two places to tick the same box would be two places for them
/// to disagree.
class _RoleMatrixPanel extends StatelessWidget {
  const _RoleMatrixPanel({required this.matrix});

  final RoleMatrix matrix;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;

    return Padding(
      padding: const EdgeInsets.all(PosSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.roleMatrixTitle,
            style: PosText.ui(
              size: 14,
              weight: FontWeight.w700,
              color: pos.inkWarm,
            ),
          ),
          const SizedBox(height: PosSpace.md),
          Table(
            key: const Key('role-matrix'),
            columnWidths: const {0: FlexColumnWidth(1.6)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(
              top: pos.hairline,
              bottom: pos.hairline,
              horizontalInside: pos.hairline,
            ),
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  for (final role in matrix.roles)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: PosSpace.sm,
                        horizontal: PosSpace.xs,
                      ),
                      child: Text(
                        role.displayName(strings.languageCode),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PosText.ui(
                          size: 11,
                          weight: FontWeight.w600,
                          color: pos.muted,
                        ),
                      ),
                    ),
                ],
              ),
              for (final group in RoleMatrix.groups)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: PosSpace.sm,
                      ),
                      child: Text(
                        AdminText.group(strings, group),
                        style: PosText.ui(size: 12.5, color: pos.body),
                      ),
                    ),
                    for (final role in matrix.roles)
                      _MatrixCell(
                        key: Key('matrix-${group.name}-${role.id}'),
                        held: matrix.held(group, role),
                        of: RoleMatrix.size(group),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: PosSpace.md),
          Text(
            strings.roleMatrixNote,
            style: PosText.ui(size: 11.5, color: pos.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// "3/8": how many of a group's permissions a role grants.
///
/// A count rather than a tick, because the groups are what a role is edited
/// in and a partial group is the common case — a tick would round "may
/// discount but not refund" to one answer or the other.
class _MatrixCell extends StatelessWidget {
  const _MatrixCell({super.key, required this.held, required this.of});

  final int held;
  final int of;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      child: Text(
        '$held/$of',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: PosText.mono(
          size: 12,
          weight: held == of ? FontWeight.w600 : FontWeight.w400,
          color: held == 0
              ? pos.muted
              : held == of
              ? pos.inkWarm
              : pos.body,
        ),
      ),
    );
  }
}

/// A person's initials, square, as the cloud's list shows them.
class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  String get _letters {
    final parts = name.trim().split(RegExp(r'\s+'));
    String first(String s) => s.isEmpty ? '' : s.substring(0, 1).toUpperCase();
    return parts.length == 1
        ? first(parts.first)
        : '${first(parts.first)}${first(parts[1])}';
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Container(
      width: _avatarWidth,
      height: _avatarWidth,
      alignment: Alignment.center,
      color: pos.chipBg,
      child: Text(
        _letters,
        style: PosText.ui(
          size: 12,
          weight: FontWeight.w700,
          color: pos.chipText,
        ),
      ),
    );
  }
}

/// What [StaffEditorDialog] collects.
class StaffDraft {
  const StaffDraft({
    required this.name,
    required this.username,
    required this.roleId,
    this.pin,
  });

  final String name;
  final String username;
  final int roleId;
  final String? pin;
}

class StaffEditorDialog extends StatefulWidget {
  const StaffEditorDialog({required this.roles, super.key});

  final List<PosRole> roles;

  static Future<StaffDraft?> show(
    BuildContext context, {
    required List<PosRole> roles,
  }) => showDialog<StaffDraft>(
    context: context,
    barrierColor: context.pos.scrim,
    builder: (_) => StaffEditorDialog(roles: roles),
  );

  @override
  State<StaffEditorDialog> createState() => _StaffEditorDialogState();
}

class _StaffEditorDialogState extends State<StaffEditorDialog> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _pin = TextEditingController();
  late int _roleId = widget.roles
      .firstWhere(
        // A new person defaults to the least privileged role there is, so that
        // forgetting to change the dropdown cannot be how somebody becomes a
        // manager.
        (role) => role.code == SystemRoles.cashierCode,
        orElse: () => widget.roles.last,
      )
      .id;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final username = _username.text.trim().toLowerCase();
    final pin = _pin.text.trim();

    if (name.isEmpty || username.isEmpty) {
      setState(() => _error = context.strings.nameAndUsernameRequired);
      return;
    }
    if (!PinRules.isWellFormed(pin)) {
      setState(() => _error = context.strings.pinIsExactlyDigits(PinRules.length));
      return;
    }

    Navigator.of(context).pop(
      StaffDraft(name: name, username: username, roleId: _roleId, pin: pin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Dialog(
      backgroundColor: context.pos.page,
      shape: RoundedRectangleBorder(
        side: context.pos.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.addSomebody, style: PosText.panelTitle(color: context.pos.ink)),
              const SizedBox(height: PosSpace.lg),
              MicroLabel(strings.fieldName),
              const SizedBox(height: PosSpace.xs),
              TextField(
                controller: _name,
                autofocus: true,
                style: PosText.ui(color: context.pos.inkWarm, size: 15),
              ),
              const SizedBox(height: PosSpace.lg),
              MicroLabel(strings.fieldUsername),
              const SizedBox(height: PosSpace.xs),
              TextField(controller: _username, style: PosText.mono(color: context.pos.inkWarm, size: 15)),
              const SizedBox(height: PosSpace.lg),
              MicroLabel(strings.fieldPin),
              const SizedBox(height: PosSpace.xs),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                style: PosText.mono(color: context.pos.inkWarm, size: 15),
              ),
              const SizedBox(height: PosSpace.lg),
              MicroLabel(strings.fieldRole),
              const SizedBox(height: PosSpace.xs),
              DropdownButton<int>(
                key: const Key('staff-editor-role'),
                value: _roleId,
                isExpanded: true,
                style: PosText.ui(color: context.pos.inkWarm, size: 14),
                items: [
                  for (final role in widget.roles)
                    DropdownMenuItem(
                      value: role.id,
                      child: Text(role.displayName(strings.languageCode)),
                    ),
                ],
                onChanged: (id) => setState(() => _roleId = id ?? _roleId),
              ),
              if (_error != null) ...[
                const SizedBox(height: PosSpace.md),
                Text(
                  _error!,
                  style: PosText.ui(
                    size: 12.5,
                    color: context.pos.danger,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: PosSpace.xl),
              PosButton(
                label: strings.add,
                height: 48,
                background: context.pos.accent,
                foreground: Colors.white,
                fontWeight: FontWeight.w700,
                onPressed: _submit,
              ),
              const SizedBox(height: PosSpace.sm),
              PosButton(
                label: strings.cancel,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collects a new PIN. The old one is never shown, because it is not stored —
/// only a PBKDF2 hash of it is.
class PinPromptDialog extends StatefulWidget {
  const PinPromptDialog({required this.title, super.key});

  final String title;

  static Future<String?> show(BuildContext context, {required String title}) =>
      showDialog<String>(
        context: context,
        barrierColor: context.pos.scrim,
        builder: (_) => PinPromptDialog(title: title),
      );

  @override
  State<PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<PinPromptDialog> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pos.page,
    shape: RoundedRectangleBorder(
      side: context.pos.emphasis,
      borderRadius: PosBorders.radius,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: PosText.panelTitle(color: context.pos.ink)),
            const SizedBox(height: PosSpace.lg),
            TextField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: PosText.mono(color: context.pos.inkWarm, size: 18),
            ),
            if (_error != null) ...[
              const SizedBox(height: PosSpace.sm),
              Text(
                _error!,
                style: PosText.ui(size: 12.5, color: context.pos.danger),
              ),
            ],
            const SizedBox(height: PosSpace.lg),
            PosButton(
              label: context.strings.setPin,
              height: 48,
              background: context.pos.accent,
              foreground: Colors.white,
              fontWeight: FontWeight.w700,
              onPressed: () {
                final pin = _pin.text.trim();
                if (!PinRules.isWellFormed(pin)) {
                  setState(
                    () => _error = context.strings.exactlyDigits(PinRules.length),
                  );
                  return;
                }
                Navigator.of(context).pop(pin);
              },
            ),
            const SizedBox(height: PosSpace.sm),
            PosButton(
              label: context.strings.cancel,
              border: Border.fromBorderSide(context.pos.resting),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Centred extends StatelessWidget {
  const _Centred({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.s28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: PosText.ui(size: 13, color: context.pos.muted, height: 1.6),
      ),
    ),
  );
}
