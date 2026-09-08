import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/deployment.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import 'admin_messages.dart';
import 'staff_grants_dialog.dart';
import '../../../core/security/pin_hash.dart';

/// Who works here.
///
/// Nobody is ever deleted. A member of staff who left is still the person named
/// on last March's shifts and on the audit rows for everything they changed, so
/// the only thing this screen can do is disable them — which stops the PIN
/// working and leaves the history intact.
class ManagementStaffPane extends ConsumerWidget {
  const ManagementStaffPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffDirectoryProvider);
    final roles = ref.watch(rolesProvider);

    return staff.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => _Centred(text: '$error'),
      data: (people) => Column(
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
                PosButton(
                  label: context.strings.addSomebody,
                  background: context.pos.accent,
                  foreground: Colors.white,
                  fontWeight: FontWeight.w700,
                  onPressed:
                      roles.valueOrNull == null ||
                          ref.watch(deploymentProvider).mode !=
                              DeploymentMode.offline
                      ? null
                      : () => _add(context, ref, roles.value!, people),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: people.length,
              itemBuilder: (context, index) => _StaffRow(
                staff: people[index],
                isSelf: people[index].id == admin.id,
                admin: admin,
                roles: roles.valueOrNull ?? const [],
                onAction: (action) => _act(context, ref, people[index], action),
              ),
            ),
          ),
        ],
      ),
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
    // let a restaurant's history consume the seats it is paying for.
    final cap = ref.read(licenceClaimsProvider).valueOrNull?.maxUsers;
    if (cap != null && people.where((p) => p.isActive).length >= cap) {
      _report(context, ref, UserSeatsExhausted(cap));
      return;
    }

    final draft = await StaffEditorDialog.show(context, roles: roles);
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
    if (refusal == null) return;

    // A refusal is shown where the action was, not as a toast that has gone by
    // the time somebody looks up from the keypad.
    showDialog<void>(
      context: context,
      barrierColor: context.pos.scrim,
      builder: (_) => Dialog(
        backgroundColor: context.pos.page,
        shape: RoundedRectangleBorder(
          side: context.pos.emphasis,
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
                Text(context.strings.notSaved, style: PosText.panelTitle(color: context.pos.ink)),
                const SizedBox(height: PosSpace.sm),
                Text(
                  AdminText.refusal(context.strings, refusal),
                  style: PosText.ui(
                    size: 13,
                    color: context.pos.body,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: PosSpace.lg),
                PosButton(
                  label: context.strings.close,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: () => Navigator.of(context).pop(),
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

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.staff,
    required this.isSelf,
    required this.roles,
    required this.onAction,
    required this.admin,
  });

  final PosStaff staff;
  final bool isSelf;
  final List<PosRole> roles;
  final ValueChanged<_StaffAction> onAction;

  /// Who is editing. The grants dialog needs it for §48 — an ALLOW for
  /// something the editor lacks is granting a permission they do not hold.
  final PosStaff admin;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Opacity(
      opacity: staff.isActive ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: BoxDecoration(
          border: Border(bottom: context.pos.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        staff.name,
                        style: PosText.ui(color: context.pos.inkWarm, size: 14, weight: FontWeight.w600),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: PosSpace.sm),
                        Text(strings.you, style: PosText.microLabel(color: context.pos.muted)),
                      ],
                    ],
                  ),
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    staff.username ?? '—',
                    style: PosText.mono(size: 11.5, color: context.pos.muted),
                  ),
                ],
              ),
            ),
            Expanded(flex: 3, child: _rolePicker(strings, pos: context.pos)),
            Expanded(
              flex: 2,
              child: Text(
                // The extra grants a person has beyond their role. Shown as a
                // count with the detail on hover: the common case is zero, and
                // a column that is empty for everybody teaches nothing.
                staff.capabilities.isEmpty
                    ? ''
                    : strings.extraCapabilities(staff.capabilities.length),
                style: PosText.ui(size: 12, color: context.pos.warn),
              ),
            ),
            PosButton(
              key: Key('grants-${staff.id}'),
              label: strings.grantsAction,
              border: Border.fromBorderSide(context.pos.resting),
              onPressed: () async {
                final grants = await StaffGrantsDialog.show(
                  context,
                  person: staff,
                  roles: roles,
                  admin: admin,
                );
                if (grants != null) onAction(_SetGrants(grants));
              },
            ),
            const SizedBox(width: PosSpace.sm),
            PosButton(
              label: strings.resetPin,
              border: Border.fromBorderSide(context.pos.resting),
              onPressed: () async {
                final pin = await PinPromptDialog.show(
                  context,
                  title: strings.newPinFor(staff.name),
                );
                if (pin != null) onAction(_ResetPin(pin));
              },
            ),
            const SizedBox(width: PosSpace.sm),
            PosButton(
              label: staff.isActive ? strings.disable : strings.enable,
              foreground: staff.isActive ? context.pos.danger : context.pos.ok,
              border: Border.fromBorderSide(context.pos.resting),
              onPressed: () => onAction(_SetActive(!staff.isActive)),
            ),
          ],
        ),
      ),
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
        value: roles.any((r) => r.id == staff.role?.id) ? staff.role?.id : null,
        hint: Text(
          strings.noRole,
          style: PosText.ui(size: 13, color: pos.muted),
        ),
        underline: const SizedBox.shrink(),
        style: PosText.ui(color: pos.inkWarm, size: 13),
        items: [
          for (final role in roles)
            DropdownMenuItem(
              value: role.id,
              child: Text(role.displayName(strings.languageCode)),
            ),
        ],
        onChanged: (id) {
          if (id != null && id != staff.role?.id) onAction(_SetRole(id));
        },
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
