import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../application/setup_controller.dart';
import '../domain/setup_state.dart';
import 'setup_panes.dart';

/// First-run setup.
///
/// Runs once per terminal, before anything else. The step rail is always
/// visible so the installer can see how much is left — a wizard that hides its
/// own length feels endless on a shop floor.
class SetupWizard extends ConsumerWidget {
  const SetupWizard({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(setupProvider);

    return Scaffold(
      backgroundColor: PosColors.page,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepRail(current: draft.step),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(step: draft.step),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PosSpace.s28,
                      vertical: PosSpace.s24,
                    ),
                    child: SetupPane(draft: draft),
                  ),
                ),
                if (draft.error != null) _ErrorBar(message: draft.error!),
                _Footer(draft: draft, onFinished: onFinished),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.current});

  final SetupStep current;

  @override
  Widget build(BuildContext context) => Container(
        width: 280,
        decoration: const BoxDecoration(
          color: PosColors.shell,
          border: Border(right: PosBorders.emphasis),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PosSpace.xl,
                PosSpace.s28,
                PosSpace.xl,
                PosSpace.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'XORDER POS',
                    style: PosText.ui(
                      size: 20,
                      weight: FontWeight.w800,
                      color: PosColors.shellText,
                    ),
                  ),
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    'TERMINAL SETUP',
                    style: PosText.mono(
                      size: 10,
                      weight: FontWeight.w600,
                      color: PosColors.shellMuted,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: PosSpace.xl),
              child: ColoredBox(color: PosColors.accent, child: SizedBox(height: 2)),
            ),
            const SizedBox(height: PosSpace.sm),
            Expanded(
              child: ListView(
                children: [
                  for (final step in SetupStep.values)
                    _RailRow(
                      step: step,
                      current: current,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RailRow extends StatelessWidget {
  const _RailRow({required this.step, required this.current});

  final SetupStep step;
  final SetupStep current;

  @override
  Widget build(BuildContext context) {
    final isCurrent = step == current;
    final isDone = step.index < current.index;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.xl,
        vertical: PosSpace.md,
      ),
      color: isCurrent ? PosColors.shellRow : Colors.transparent,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent
                  ? PosColors.accent
                  : (isDone ? PosColors.onlinePillBg : Colors.transparent),
              border: Border.all(
                color: isDone ? PosColors.onlinePillBorder : PosColors.shellLine,
              ),
            ),
            child: Text(
              isDone ? '✓' : '${step.index + 1}',
              style: PosText.mono(
                size: 11,
                weight: FontWeight.w600,
                color: isCurrent
                    ? Colors.white
                    : (isDone ? PosColors.onlinePillText : PosColors.shellMuted),
              ),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: Text(
              step.title,
              overflow: TextOverflow.ellipsis,
              style: PosText.ui(
                size: 14,
                weight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                color: isCurrent ? PosColors.shellText : PosColors.shellMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.step});

  final SetupStep step;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(
          PosSpace.s28,
          PosSpace.s28,
          PosSpace.s28,
          PosSpace.xl,
        ),
        decoration: const BoxDecoration(
          color: PosColors.surface,
          border: Border(bottom: PosBorders.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MicroLabel('Step ${step.index + 1} of ${SetupStep.values.length}'),
            const SizedBox(height: PosSpace.sm),
            Text(step.title, style: PosText.screenTitle()),
            const SizedBox(height: PosSpace.xs),
            Text(step.blurb, style: PosText.ui(size: 13.5, color: PosColors.muted)),
          ],
        ),
      );
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: PosColors.dangerSoft,
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.s28,
          vertical: PosSpace.md,
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: PosColors.danger),
            const SizedBox(width: PosSpace.sm),
            Expanded(
              child: Text(
                message,
                style: PosText.ui(size: 13, color: PosColors.danger, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.draft, required this.onFinished});

  final SetupDraft draft;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setupProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: const BoxDecoration(
        color: PosColors.surface,
        border: Border(top: PosBorders.emphasis),
      ),
      child: Row(
        children: [
          if (!draft.step.isFirst)
            PosButton(
              label: 'Back',
              border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.s24),
              onPressed: draft.busy ? null : controller.back,
            ),
          const Spacer(),
          if (draft.busy)
            const Padding(
              padding: EdgeInsets.only(right: PosSpace.lg),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: PosColors.accent),
              ),
            ),
          PosButton(
            label: draft.step.isLast ? 'Open the till' : 'Continue',
            height: PosSize.secondaryAction,
            background: PosColors.accent,
            foreground: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.s28),
            onPressed: draft.busy || !draft.canAdvance
                ? null
                : () {
                    if (draft.step.isLast) {
                      // Publish what the wizard gathered before leaving it —
                      // the rest of the app reads deployment config, not the draft.
                      ref.read(localeProvider.notifier).apply(draft.locale);
                      ref.read(deploymentProvider.notifier).apply(draft.deployment);
                      ref.read(terminalProfileProvider.notifier).apply(TerminalProfile(
                            branchId: draft.branchId,
                            branchName: draft.branchLabel,
                            terminalName: draft.terminalName,
                            terminalId: draft.terminalId,
                            provisioned: draft.claimed,
                            restaurantId: draft.restaurantId,
                            branchCode: draft.branchCode,
                          ));
                      // Move the database password out of the wizard draft and
                      // into the credential store the pool reads from.
                      controller.publishCredentials();
                      ref.read(setupCompleteProvider.notifier).markComplete();
                      onFinished();
                      return;
                    }
                    controller.next();
                  },
          ),
        ],
      ),
    );
  }
}
