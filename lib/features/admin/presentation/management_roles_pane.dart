import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import 'admin_messages.dart';

/// What each job title may do.
///
/// The capabilities are shown as sentences, grouped by the part of the business
/// they belong to, because the decision a manager is making is *"should a
/// supervisor be able to refund?"* — not *"should a supervisor hold
/// order.refund?"*. The grouping is the argument: everything under **Back
/// office** is what a cashier must never have, and a restaurant ticking those
/// boxes for a cashier role should be able to see that is what it is doing.
class ManagementRolesPane extends ConsumerStatefulWidget {
  const ManagementRolesPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementRolesPane> createState() =>
      _ManagementRolesPaneState();
}

class _ManagementRolesPaneState extends ConsumerState<ManagementRolesPane> {
  int? _selectedId;
  Set<String>? _draft;
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(rolesProvider);
    final strings = context.strings;

    return roles.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => _Message(text: '$error'),
      data: (all) {
        if (all.isEmpty) return _Message(text: strings.noRolesYet);

        final selected = all.firstWhere(
          (role) => role.id == _selectedId,
          orElse: () => all.first,
        );
        final draft = _draft ?? selected.capabilities;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 240,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: context.pos.hairline),
                ),
                child: ListView(
                  children: [
                    for (final role in all)
                      _RoleRow(
                        role: role,
                        selected: role.id == selected.id,
                        onTap: () => setState(() {
                          _selectedId = role.id;
                          _draft = null;
                          _message = null;
                        }),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(child: _editor(strings, selected, draft)),
          ],
        );
      },
    );
  }

  Widget _editor(AppStrings strings, PosRole role, Set<String> draft) {
    final dirty = !_sameSet(draft, role.capabilities);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(PosSpace.xl),
          decoration: BoxDecoration(
            border: Border(bottom: context.pos.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.displayName(strings.languageCode),
                      style: PosText.panelTitle(color: context.pos.ink),
                    ),
                    const SizedBox(height: PosSpace.xs),
                    Text(
                      strings.permissionCount(
                            draft.length,
                            PosCapability.all.length,
                          ) +
                          (role.isSystem ? strings.createdByInstaller : ''),
                      style: PosText.ui(size: 12, color: context.pos.muted),
                    ),
                  ],
                ),
              ),
              if (dirty)
                PosButton(
                  label: strings.discard,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: _busy ? null : () => setState(() => _draft = null),
                ),
              const SizedBox(width: PosSpace.sm),
              PosButton(
                label: strings.save,
                background: dirty ? context.pos.accent : context.pos.chipBg,
                foreground: dirty ? Colors.white : context.pos.muted,
                fontWeight: FontWeight.w700,
                onPressed: _busy || !dirty ? null : () => _save(role, draft),
              ),
            ],
          ),
        ),
        if (_message != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(PosSpace.lg),
            color: context.pos.dangerSoft,
            child: Text(
              _message!,
              style: PosText.ui(size: 12.5, color: context.pos.ink, height: 1.5),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PosSpace.xl),
            children: [
              for (final group in CapabilityGroup.values) ...[
                MicroLabel(AdminText.group(strings, group).toUpperCase()),
                const SizedBox(height: PosSpace.sm),
                for (final capability in group.capabilities)
                  _CapabilityRow(
                    label: AdminText.capability(strings, capability),
                    checked: draft.contains(capability),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            final next = {...draft};
                            value
                                ? next.add(capability)
                                : next.remove(capability);
                            _draft = next;
                            _message = null;
                          }),
                  ),
                const SizedBox(height: PosSpace.xl),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save(PosRole role, Set<String> draft) async {
    setState(() {
      _busy = true;
      _message = null;
    });

    final result = await ref
        .read(rolesRepositoryProvider)
        .save(role.copyWith(capabilities: draft), by: widget.admin);

    if (!mounted) return;
    final strings = context.strings;
    setState(() {
      _busy = false;
      _message = result.succeeded
          ? null
          : AdminText.refusal(strings, result.refusal!);
      if (result.succeeded) _draft = null;
    });

    if (result.succeeded) {
      ref.invalidate(rolesProvider);
      // The people on this role now have different permissions. Anything
      // showing what they may do has to be told, including the person doing
      // the editing — who may have just edited their own role.
      ref.invalidate(staffDirectoryProvider);
    }
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final PosRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? context.pos.accentSoft : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: BoxDecoration(
          border: Border(bottom: context.pos.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                role.displayName(context.strings.languageCode),
                style: PosText.ui(color: context.pos.inkWarm, 
                  size: 13.5,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${role.capabilities.length}',
              style: PosText.mono(size: 12, color: context.pos.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onChanged == null ? null : () => onChanged!(!checked),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: PosSpace.md),
      child: Row(
        children: [
          // A square, because the radius in this design is zero everywhere.
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: checked ? context.pos.accent : context.pos.surface,
              border: Border.all(
                color: checked ? context.pos.accent : context.pos.lineStrong,
              ),
            ),
            child: checked
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(child: Text(label, style: PosText.ui(color: context.pos.inkWarm, size: 13.5))),
        ],
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

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
