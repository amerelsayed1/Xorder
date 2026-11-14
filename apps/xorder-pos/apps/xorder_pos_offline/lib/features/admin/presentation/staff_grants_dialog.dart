import 'package:flutter/material.dart';

import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/features/admin_mode/admin_messages.dart';
import 'package:shared_module/core/text/digits.dart';

/// What [StaffGrantsDialog] hands back.
class StaffGrants {
  const StaffGrants({
    required this.extraRoleIds,
    required this.overrides,
    required this.limits,
  });

  final Set<int> extraRoleIds;
  final List<PermissionOverride> overrides;
  final Map<String, PermissionLimit> limits;
}

/// One person's exceptions to their role, and their ceilings (§105, §16).
///
/// **Three states per permission, not two.** A checkbox would collapse *"comes
/// with the role"* and *"granted to this person"* into one tick, and *"the role
/// grants it and somebody deliberately took it away"* into the same blank as
/// *"nobody ever gave it"*. Those are four different facts about somebody's
/// access, and a manager reviewing a person needs to tell them apart — so each
/// row shows where the permission came from and offers only the two exceptions.
class StaffGrantsDialog extends StatefulWidget {
  const StaffGrantsDialog({
    super.key,
    required this.person,
    required this.roles,
    required this.admin,
  });

  final PosStaff person;
  final List<PosRole> roles;

  /// Who is editing. §48 again: an ALLOW for something the editor lacks is
  /// granting a permission they do not hold through a different door, so those
  /// rows are locked rather than merely refused on save.
  final PosStaff admin;

  static Future<StaffGrants?> show(
    BuildContext context, {
    required PosStaff person,
    required List<PosRole> roles,
    required PosStaff admin,
  }) => showDialog<StaffGrants>(
    context: context,
    builder: (_) =>
        StaffGrantsDialog(person: person, roles: roles, admin: admin),
  );

  @override
  State<StaffGrantsDialog> createState() => _StaffGrantsDialogState();
}

/// Where a permission comes from, for one person.
enum _Source { role, allowed, denied, none }

class _StaffGrantsDialogState extends State<StaffGrantsDialog> {
  late final Set<int> _extraRoles = {
    for (final role in widget.person.extraRoles) role.id,
  };
  late final Map<String, OverrideEffect> _overrides = {
    for (final override in widget.person.overrides)
      PosCapability.canonical(override.capability): override.effect,
  };
  late final _discount = TextEditingController(
    text: _percent(widget.person.limitFor(LimitKey.discount).maxBp),
  );

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  /// Basis points as a percentage, blank when there is no ceiling.
  static String _percent(int? bp) {
    if (bp == null) return '';
    final value = bp / 100;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// What the roles alone would grant, with the current selection.
  Set<String> get _fromRoles => {
    for (final role in [
      ?widget.person.role,
      ...widget.roles.where((r) => _extraRoles.contains(r.id)),
    ])
      for (final capability in role.capabilities)
        PosCapability.canonical(capability),
  };

  _Source _sourceOf(String capability, Set<String> fromRoles) {
    final override = _overrides[capability];
    if (override == OverrideEffect.deny) return _Source.denied;
    if (override == OverrideEffect.allow) return _Source.allowed;
    return fromRoles.contains(capability) ? _Source.role : _Source.none;
  }

  void _cycle(String capability, Set<String> fromRoles) {
    setState(() {
      final current = _sourceOf(capability, fromRoles);
      // From the role, the only meaningful exception is to take it away. From
      // nothing, the only one is to add it. The third press clears back to
      // whatever the role says, so an exception is always undoable in place.
      _overrides.remove(capability);
      switch (current) {
        case _Source.role:
          _overrides[capability] = OverrideEffect.deny;
        case _Source.none:
          if (widget.admin.can(capability)) {
            _overrides[capability] = OverrideEffect.allow;
          }
        case _Source.allowed || _Source.denied:
          break;
      }
    });
  }

  void _save() {
    final bp = _discount.text.trim().isEmpty
        ? null
        : (double.tryParse(foldDigits(_discount.text.trim())) ?? 0) * 100;

    Navigator.of(context).pop(
      StaffGrants(
        extraRoleIds: _extraRoles,
        overrides: [
          for (final entry in _overrides.entries)
            PermissionOverride(capability: entry.key, effect: entry.value),
        ],
        limits: {
          LimitKey.discount: PermissionLimit(maxBp: bp?.round()),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final fromRoles = _fromRoles;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.grantsFor(widget.person.name),
                    style: PosText.ui(
                      size: 18,
                      weight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    strings.grantsExplain,
                    style: PosText.ui(
                      size: 12.5,
                      color: palette.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  MicroLabel(strings.grantsExtraRoles),
                  const SizedBox(height: PosSpace.sm),
                  for (final role in widget.roles)
                    if (role.id != widget.person.role?.id)
                      _RoleToggle(
                        role: role,
                        on: _extraRoles.contains(role.id),
                        onChanged: (on) => setState(() {
                          on
                              ? _extraRoles.add(role.id)
                              : _extraRoles.remove(role.id);
                        }),
                      ),
                  const SizedBox(height: PosSpace.xl),
                  MicroLabel(strings.grantsCeilings),
                  const SizedBox(height: PosSpace.sm),
                  _Ceiling(
                    label: strings.grantsDiscountCeiling,
                    controller: _discount,
                    hint: strings.grantsNoCeiling,
                  ),
                  const SizedBox(height: PosSpace.xl),
                  MicroLabel(strings.grantsExceptions),
                  const SizedBox(height: PosSpace.sm),
                  for (final group in CapabilityGroup.values)
                    for (final capability in group.capabilities)
                      _CapabilityLine(
                        label: AdminText.capability(strings, capability),
                        source: _sourceOf(capability, fromRoles),
                        // §48 — an ALLOW for something the editor lacks would
                        // be granting a permission they do not hold. Shown and
                        // locked rather than hidden, so the row still tells the
                        // truth about what this person has.
                        locked:
                            !widget.admin.can(capability) &&
                            !fromRoles.contains(capability),
                        onTap: () => _cycle(capability, fromRoles),
                      ),
                  const SizedBox(height: PosSpace.lg),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                border: BorderDirectional(top: palette.resting),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      key: const Key('grants-save'),
                      label: strings.save,
                      background: palette.ink,
                      foreground: palette.onInk,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleToggle extends StatelessWidget {
  const _RoleToggle({
    required this.role,
    required this.on,
    required this.onChanged,
  });

  final PosRole role;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!on),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: on ? context.pos.accent : context.pos.surface,
              border: Border.all(
                color: on ? context.pos.accent : context.pos.lineStrong,
              ),
            ),
            child: on
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: PosSpace.md),
          Text(
            role.displayName(context.strings.languageCode),
            style: PosText.ui(size: 13.5, color: context.pos.inkWarm),
          ),
        ],
      ),
    ),
  );
}

class _Ceiling extends StatelessWidget {
  const _Ceiling({
    required this.label,
    required this.controller,
    required this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: PosText.ui(size: 13.5, color: context.pos.inkWarm),
        ),
      ),
      SizedBox(
        width: 96,
        child: TextField(
          controller: controller,
          textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: hint),
          style: PosText.mono(size: 15, color: context.pos.ink),
        ),
      ),
      const SizedBox(width: PosSpace.sm),
      Text('%', style: PosText.mono(size: 15, color: context.pos.muted)),
    ],
  );
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine({
    required this.label,
    required this.source,
    required this.onTap,
    required this.locked,
  });

  final String label;
  final _Source source;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final (text, ink) = switch (source) {
      _Source.role => (strings.grantsFromRole, palette.muted),
      _Source.allowed => (strings.grantsAllowed, palette.ok),
      _Source.denied => (strings.grantsDenied, palette.danger),
      _Source.none => ('', palette.muted),
    };

    return InkWell(
      onTap: locked ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
        decoration: BoxDecoration(
          border: BorderDirectional(bottom: palette.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: PosText.ui(
                  size: 13,
                  color: locked ? palette.muted : palette.inkWarm,
                ),
              ),
            ),
            if (text.isNotEmpty)
              Text(
                text,
                style: PosText.ui(
                  size: 11.5,
                  weight: source == _Source.role
                      ? FontWeight.w400
                      : FontWeight.w700,
                  color: ink,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
