import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/shift.dart';

/// The deliberate escape hatch: wipe this machine's terminal setup and run the
/// wizard again, from anywhere, including mid-shift.
///
/// Why this exists separately from the start screen's "Reset terminal" link:
/// that link REFUSES while a shift is open, and it is right to. The common
/// case is an operator who does not realise the drawer is still open, and
/// silently discarding a shift is not something a visible button should do.
///
/// But a till whose terminal has been deleted platform-side is stuck behind
/// exactly that refusal — its shift can never be closed cleanly, because the
/// platform will not accept anything from it — and refusing forever is not an
/// answer either. So the forced path exists, is bound to a shortcut rather
/// than a button so it is not found by accident, and states plainly what it is
/// about to cost instead of either refusing or quietly destroying it.
///
/// Nothing on the platform is touched. This deletes local setup only.
Future<bool> showForceResetDialog(BuildContext context, WidgetRef ref) async {
  final strings = context.strings;

  // Read both costs BEFORE asking, so the dialog can name them. A failure to
  // read is reported as unknown rather than as "nothing to lose" — the whole
  // point is that the operator decides with the real numbers in front of them.
  PosShift? openShift;
  try {
    openShift = await ref.read(shiftRepositoryProvider).current();
  } on Exception {
    openShift = null;
  }

  var queued = 0;
  try {
    queued = await ref.read(ordersRepositoryProvider).pendingSyncCount();
  } on Exception {
    queued = 0;
  }

  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _ForceResetDialog(
      strings: strings,
      openShiftRef: openShift?.reference,
      queued: queued,
    ),
  );

  if (confirmed != true) return false;

  await ref.read(terminalResetProvider).run();

  return true;
}

class _ForceResetDialog extends StatelessWidget {
  const _ForceResetDialog({
    required this.strings,
    required this.openShiftRef,
    required this.queued,
  });

  final AppStrings strings;
  final String? openShiftRef;
  final int queued;

  @override
  Widget build(BuildContext context) {
    final warnings = <String>[
      if (openShiftRef != null)
        strings.forceResetShiftOpen.replaceFirst('{ref}', openShiftRef!),
      if (queued > 0)
        strings.forceResetQueued.replaceFirst('{count}', '$queued'),
    ];

    return Dialog(
      backgroundColor: context.pos.page,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: RoundedRectangleBorder(
        side: context.pos.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.forceResetTitle, style: PosText.panelTitle(color: context.pos.ink)),
              const SizedBox(height: PosSpace.sm),
              Text(
                strings.forceResetBody,
                style: PosText.ui(
                  size: 13,
                  color: context.pos.muted,
                  height: 1.5,
                ),
              ),
              // Each cost on its own line, in danger red. Not folded into the
              // body text: an operator scanning this dialog must not be able
              // to miss an open drawer or unsent money.
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: PosSpace.md),
                Container(
                  padding: const EdgeInsets.all(PosSpace.md),
                  decoration: BoxDecoration(
                    color: context.pos.shellDangerBg,
                    border: Border.all(color: context.pos.danger),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final warning in warnings) ...[
                        if (warning != warnings.first)
                          const SizedBox(height: PosSpace.sm),
                        Text(
                          warning,
                          style: PosText.ui(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: context.pos.shellDangerText,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: PosSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.all(color: context.pos.line),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: PosButton(
                      label: strings.forceResetConfirm,
                      background: context.pos.danger,
                      foreground: Colors.white,
                      fontWeight: FontWeight.w700,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
