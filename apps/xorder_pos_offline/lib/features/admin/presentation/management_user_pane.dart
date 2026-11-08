import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin_mode/admin_session.dart';
import 'admin_pane_bits.dart';

/// Settings › User: who is in Admin Mode, what they hold, and the way out.
///
/// **No "Change my PIN".** Nothing in this app lets a person change their own
/// PIN — the staff pane's reset is one person setting another's, behind
/// `staff.manage`, and audited as such. A self-service button here would be a
/// second, ungated way to the same write, and inventing it is a decision about
/// who may change a credential, not a layout choice.
///
/// **The count is what they hold, not what the role lists**: role, extra roles
/// and direct grants, less any deny — [PosStaff.effectiveCapabilities], the set
/// every check in the app reads. The role's own list is on People › Roles,
/// which [onOpenRoles] leads to when the shell has one to open.
class ManagementUserPane extends ConsumerWidget {
  const ManagementUserPane({
    required this.admin,
    required this.onExit,
    this.onOpenRoles,
    super.key,
  });

  final PosStaff admin;

  /// After the session has ended: the shell's cue to leave the back office.
  /// Ending it is done here as well as by the shell's own Exit, and the second
  /// call is a no-op — so whichever the shell wires, the audit row says
  /// "exited", not "left".
  final VoidCallback onExit;

  /// Null when this person has no Roles pane: the count then leads nowhere,
  /// rather than to a pane they cannot open.
  final VoidCallback? onOpenRoles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final pos = context.pos;
    final language = strings.languageCode;
    final roles = [?admin.role, ...admin.extraRoles];
    final words = PosText.ui(size: 13, color: pos.ink);

    return ListView(
      key: const Key('user-pane'),
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneUser, hint: strings.paneUserBlurb),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaneFact(
                label: strings.userNameLabel,
                child: Text(admin.name, key: const Key('user-name'), style: words),
              ),
              if (admin.username case final username?
                  when username.trim().isNotEmpty)
                PaneFact(
                  label: strings.username,
                  // Typed at the door, letter for letter: a code, not a word.
                  child: Text(
                    username,
                    key: const Key('user-username'),
                    textDirection: TextDirection.ltr,
                    style: PosText.mono(size: 13, color: pos.ink),
                  ),
                ),
              PaneFact(
                label: strings.userRole,
                child: Text(
                  roles.isEmpty
                      ? strings.userNoRole
                      : roles.map((r) => r.displayName(language)).join(' · '),
                  key: const Key('user-role'),
                  style: roles.isEmpty
                      ? PosText.ui(size: 13, color: pos.muted)
                      : words,
                ),
              ),
              PaneFact(
                label: strings.userPermissions,
                child: Row(
                  children: [
                    Text(
                      '${admin.effectiveCapabilities.length}',
                      key: const Key('user-permissions'),
                      textDirection: TextDirection.ltr,
                      style: PosText.mono(size: 13, color: pos.ink),
                    ),
                    if (onOpenRoles case final open?) ...[
                      const SizedBox(width: PosSpace.md),
                      PosButton(
                        key: const Key('user-see-roles'),
                        label: strings.userSeeRoles,
                        height: 32,
                        border: Border.fromBorderSide(pos.resting),
                        padding: const EdgeInsets.symmetric(
                          horizontal: PosSpace.md,
                        ),
                        onPressed: open,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: PosSpace.xl),
              Text(
                strings.userExitHint,
                style: PosText.ui(size: 12.5, color: pos.muted, height: 1.5),
              ),
              const SizedBox(height: PosSpace.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: PosButton(
                  key: const Key('user-exit'),
                  label: strings.exitAdminMode,
                  background: pos.ink,
                  foreground: pos.onInk,
                  padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                  onPressed: () async {
                    await ref
                        .read(adminSessionProvider.notifier)
                        .end(AdminSessionEnd.exited);
                    onExit();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
