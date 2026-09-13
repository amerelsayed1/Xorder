import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
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
      backgroundColor: context.pos.page,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepRail(draft: draft),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(draft: draft),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PosSpace.s28,
                      vertical: PosSpace.s24,
                    ),
                    child: SetupPane(draft: draft),
                  ),
                ),
                if (draft.notice != null) _NoticeBar(message: draft.notice!),
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
  const _StepRail({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context) => Container(
    width: 280,
    decoration: BoxDecoration(
      color: context.pos.shell,
      border: Border(right: context.pos.emphasis),
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
                context.strings.productWordmark,
                style: PosText.ui(
                  size: 20,
                  weight: FontWeight.w800,
                  color: context.pos.shellText,
                ),
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                context.strings.terminalSetup,
                style: PosText.mono(
                  size: 10,
                  weight: FontWeight.w600,
                  color: context.pos.shellMuted,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: PosSpace.xl),
          child: ColoredBox(
            color: context.pos.accent,
            child: SizedBox(height: 2),
          ),
        ),
        const SizedBox(height: PosSpace.sm),
        Expanded(
          child: ListView(
            children: [
              // The rail shows the path being walked. Every step is on
              // that path today — `visibleSteps` used to drop the licence
              // row for cloud terminals, which it can no longer do now that
              // the licence is what decides the mode.
              for (final (position, step) in draft.visibleSteps.indexed)
                _RailRow(step: step, position: position, draft: draft),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.step,
    required this.position,
    required this.draft,
  });

  final SetupStep step;

  /// Index within the visible path, which is what the numbering shows.
  final int position;
  final SetupDraft draft;

  @override
  Widget build(BuildContext context) {
    final isCurrent = step == draft.step;
    final isDone = position < draft.visibleSteps.indexOf(draft.step);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.xl,
        vertical: PosSpace.md,
      ),
      color: isCurrent ? context.pos.shellRow : Colors.transparent,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent
                  ? context.pos.accent
                  : (isDone ? context.pos.onlinePillBg : Colors.transparent),
              border: Border.all(
                color: isDone
                    ? context.pos.onlinePillBorder
                    : context.pos.shellLine,
              ),
            ),
            child: Text(
              isDone ? '✓' : '${position + 1}',
              style: PosText.mono(
                size: 11,
                weight: FontWeight.w600,
                color: isCurrent
                    ? Colors.white
                    : (isDone
                          ? context.pos.onlinePillText
                          : context.pos.shellMuted),
              ),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: Text(
              step.title(
                context.strings,
                mode: draft.deployment.mode,
                role: draft.deployment.role,
              ),
              overflow: TextOverflow.ellipsis,
              style: PosText.ui(
                size: 14,
                weight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                color: isCurrent ? context.pos.shellText : context.pos.shellMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      PosSpace.s28,
      PosSpace.s28,
      PosSpace.s28,
      PosSpace.xl,
    ),
    decoration: BoxDecoration(
      color: context.pos.surface,
      border: Border(bottom: context.pos.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(context.strings.stepOf(draft.stepNumber, draft.stepCount)),
        const SizedBox(height: PosSpace.sm),
        Text(
          draft.step.title(
            context.strings,
            mode: draft.deployment.mode,
            role: draft.deployment.role,
          ),
          style: PosText.screenTitle(color: context.pos.ink),
        ),
        const SizedBox(height: PosSpace.xs),
        Text(
          draft.step.blurb(
            context.strings,
            mode: draft.deployment.mode,
            role: draft.deployment.role,
          ),
          style: PosText.ui(size: 13.5, color: context.pos.muted),
        ),
      ],
    ),
  );
}

/// Information, not failure — amber, no alarm icon. Kept separate from
/// [_ErrorBar] so red keeps meaning "act now" and nothing else.
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: context.pos.warnSoft,
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.s28,
      vertical: PosSpace.md,
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 18, color: context.pos.warn),
        const SizedBox(width: PosSpace.sm),
        Expanded(
          child: Text(
            message,
            style: PosText.ui(size: 13, color: context.pos.ink, height: 1.4),
          ),
        ),
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
    color: context.pos.dangerSoft,
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.s28,
      vertical: PosSpace.md,
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: context.pos.danger),
        const SizedBox(width: PosSpace.sm),
        Expanded(
          child: Text(
            message,
            style: PosText.ui(size: 13, color: context.pos.danger, height: 1.4),
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
      decoration: BoxDecoration(
        color: context.pos.surface,
        border: Border(top: context.pos.emphasis),
      ),
      child: Row(
        children: [
          if (!draft.isFirstStep)
            PosButton(
              label: context.strings.back,
              border: Border.fromBorderSide(
                BorderSide(color: context.pos.inkWarm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.s24),
              onPressed: draft.busy ? null : controller.back,
            ),
          const Spacer(),
          if (draft.busy)
            Padding(
              padding: EdgeInsets.only(right: PosSpace.lg),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.pos.accent,
                ),
              ),
            ),
          PosButton(
            label: draft.isLastStep
                ? context.strings.openTheTill
                : context.strings.continueLabel,
            height: PosSize.secondaryAction,
            background: context.pos.accent,
            foreground: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.s28),
            onPressed: draft.busy || !draft.canAdvance
                ? null
                : () async {
                    if (draft.isLastStep) {
                      // Publish what the wizard gathered and write it to disk
                      // before leaving — the rest of the app reads deployment
                      // config, not the draft, and the next launch reads the
                      // file. A save that failed keeps the operator here, with
                      // the reason on screen.
                      final failure = await controller.complete();
                      if (failure == null) onFinished();
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
