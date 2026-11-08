import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';

/// The setup wizard's way back to a blank till.
///
/// The ordinary reset keeps the licence file and the terminal id (the licence is
/// pinned to it), so a till that had been licensed once opened the wizard on
/// "Licensed" for ever, and the way to start over was to delete files by hand
/// from a folder whose path differs between macOS and Windows. This button does
/// that wipe through the app's own stores, so it is the same on both.
///
/// It erases this machine's memory and nothing else: no database, sale or
/// backup is touched, and the dialog says so before anything goes.
Future<void> confirmAndHardReset(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const HardResetDialog(),
  );
  if (confirmed != true) return;

  try {
    await ref.read(terminalResetProvider).runHard();
  } on Object catch (error) {
    if (context.mounted) {
      posToast(context, context.strings.hardResetFailed('$error'));
    }
  }
}

class HardResetDialog extends StatelessWidget {
  const HardResetDialog({super.key});

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
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.hardResetTitle,
                style: PosText.panelTitle(color: context.pos.ink),
              ),
              const SizedBox(height: PosSpace.sm),
              Text(
                strings.hardResetBody,
                style: PosText.ui(
                  size: 13,
                  color: context.pos.muted,
                  height: 1.5,
                ),
              ),
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
                      label: strings.hardResetConfirm,
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
