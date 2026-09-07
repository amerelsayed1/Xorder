import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/services/authorization.dart';
import 'admin_messages.dart';

/// Ask whether the person at the till may do something, offering a supervisor
/// the chance to lend the permission when one is possible.
///
/// This is the single entry point every gated action goes through, so that the
/// three outcomes are handled the same way everywhere:
///
/// * **Allowed** — proceed, and if it was lent, the returned [Allowed] carries
///   the approver so the caller can put them on the audit row.
/// * **Needs override** — a PIN prompt, right here, because the supervisor is
///   standing at the till and walking away to a settings screen is not the
///   workflow anybody has.
/// * **Denied** — an explanation and nothing else. Offering an override for
///   something no override exists for would be a prompt that can only fail.
///
/// [action] is what the supervisor READS — the till's language. [auditAction]
/// is what is WRITTEN to the ledger, and stays in one language so a year of
/// override rows can be read as one list.
///
/// The override itself is recorded before this returns. A lent permission that
/// was used but not logged is worse than one that was refused: the restaurant
/// finds out about the discount and has no way to learn who approved it.
Future<PermissionDecision> requestPermission(
  BuildContext context,
  WidgetRef ref,
  String capability, {
  required String action,
  required String auditAction,
  String? entityType,
  String? entityId,
}) async {
  final decision = Authorization.check(
    ref.read(signedInStaffProvider),
    capability,
  );
  if (decision is Allowed) return decision;

  if (decision is Denied) {
    if (context.mounted) {
      await _RefusalDialog.show(context, capability: capability);
    }
    return decision;
  }

  if (!context.mounted) return decision;
  final approver = await SupervisorOverrideDialog.show(
    context,
    capability: capability,
    action: action,
  );
  if (approver == null) return decision;

  final approved = Authorization.approve(
    approver: approver,
    capability: capability,
  );
  if (approved is! Allowed) return approved;

  await ref
      .read(auditRepositoryProvider)
      .record(
        // The person who asked, not the person who approved. Both are on the
        // row; which is which is the entire point of recording it.
        by: ref.read(signedInStaffProvider) ?? approver,
        approvedBy: approver,
        action: AuditAction.permissionOverridden,
        entityType: entityType ?? AuditAction.entityOrder,
        entityId: entityId,
        // [auditAction], not [action]: the row is read back months later,
        // often by somebody who does not run the till in the language it was
        // written on. What was approved should not depend on that.
        after: {'capability': capability, 'for': auditAction},
      );

  return approved;
}

/// The PIN prompt a supervisor answers at the till.
class SupervisorOverrideDialog extends ConsumerStatefulWidget {
  const SupervisorOverrideDialog({
    required this.capability,
    required this.action,
    super.key,
  });

  final String capability;

  /// What is about to happen, in the words the cashier would use — *"Discount
  /// this line"*. A supervisor approving "discount.apply" is approving a string;
  /// a supervisor approving "Discount this line" is approving an act.
  final String action;

  /// The member of staff who approved, or null if nobody did.
  static Future<PosStaff?> show(
    BuildContext context, {
    required String capability,
    required String action,
  }) => showDialog<PosStaff>(
    context: context,
    barrierColor: context.pos.scrimHeavy,
    barrierDismissible: false,
    builder: (_) =>
        SupervisorOverrideDialog(capability: capability, action: action),
  );

  @override
  ConsumerState<SupervisorOverrideDialog> createState() =>
      _SupervisorOverrideDialogState();
}

class _SupervisorOverrideDialogState
    extends ConsumerState<SupervisorOverrideDialog> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _digit(String digit) async {
    if (_pin.length >= 4 || _busy) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length < 4) return;

    setState(() => _busy = true);
    final staff = await ref.read(staffDirectoryRepositoryProvider).byPin(_pin);
    if (!mounted) return;

    final decision = Authorization.approve(
      approver: staff,
      capability: widget.capability,
    );
    if (decision is Allowed) {
      Navigator.of(context).pop(decision.approvedBy);
      return;
    }

    setState(() {
      _busy = false;
      _pin = '';
      // Deliberately one message for both "no such PIN" and "that person may
      // not approve this". Distinguishing them would turn the keypad into a
      // way of discovering who holds which permission.
      _error = context.strings.pinCannotApprove;
    });
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Dialog(
      backgroundColor: context.pos.page,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: RoundedRectangleBorder(
        side: context.pos.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.supervisorApproval, style: PosText.panelTitle(color: context.pos.ink)),
              const SizedBox(height: PosSpace.sm),
              Text(
                strings.supervisorApprovalHelp(widget.action),
                style: PosText.ui(
                  size: 13,
                  color: context.pos.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: PosSpace.lg),
              PinDots(length: _pin.length),
              const SizedBox(height: PosSpace.lg),
              PinPad(onDigit: _digit, onBackspace: _backspace),
              if (_error != null) ...[
                const SizedBox(height: PosSpace.md),
                Container(
                  padding: const EdgeInsets.all(PosSpace.md),
                  decoration: BoxDecoration(
                    color: context.pos.dangerSoft,
                    border: Border.all(color: context.pos.danger),
                  ),
                  child: Text(
                    _error!,
                    style: PosText.ui(
                      size: 12.5,
                      color: context.pos.ink,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: PosSpace.lg),
              PosButton(
                label: strings.cancel,
                height: 44,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when nobody at this till can authorise the action, with or without a
/// supervisor.
class _RefusalDialog extends StatelessWidget {
  const _RefusalDialog({required this.capability});

  final String capability;

  static Future<void> show(
    BuildContext context, {
    required String capability,
  }) => showDialog<void>(
    context: context,
    barrierColor: context.pos.scrim,
    builder: (_) => _RefusalDialog(capability: capability),
  );

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
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.notPermittedTitle, style: PosText.panelTitle(color: context.pos.ink)),
              const SizedBox(height: PosSpace.sm),
              Text(
                // Named in words, not as `receipt.reprint`: the person
                // reading this is being told what to go and ask for.
                strings.notPermittedBody(
                  AdminText.capability(strings, capability),
                ),
                style: PosText.ui(
                  size: 13,
                  color: context.pos.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: PosSpace.lg),
              PosButton(
                label: strings.close,
                height: 44,
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
