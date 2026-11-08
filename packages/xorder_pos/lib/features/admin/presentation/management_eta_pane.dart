import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/eta_submission.dart';
import '../../../domain/services/eta_filing.dart';

/// What Egypt's tax authority has not accepted yet.
///
/// **A queue growing where nobody looks is a failure mode this codebase has
/// already been bitten by once** — and here the cost of not looking is a legal
/// one, because the obligation runs out twenty-four hours after each receipt
/// is issued rather than whenever somebody next checks.
///
/// So the pane leads with the sentence that matters — "everything has been
/// filed", or a count of what has not — and only then shows the list. A screen
/// that opened on a table of rows would make the good state and the bad state
/// look identical at a glance.
class ManagementEtaPane extends ConsumerWidget {
  const ManagementEtaPane({super.key, this.now});

  /// The clock the deadline is measured against. Injected so the summary and
  /// the rows cannot disagree, and so a test can stand at a chosen minute.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final palette = context.pos;
    final clock = now ?? DateTime.now();

    final summary = ref.watch(etaQueueSummaryProvider);
    final rows = ref.watch(etaOutstandingProvider);
    final problem = etaProblemText(strings, ref.watch(etaFilingProblemProvider));
    final reconciler = ref.watch(etaReconcilerProvider);

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        // Above the queue: a queue that stopped growing because nothing is
        // being filed looks exactly like one that is keeping up.
        if (problem != null) ...[
          Container(
            key: const Key('eta-filing-problem'),
            padding: const EdgeInsets.all(PosSpace.md),
            color: palette.dangerSoft,
            child: Text(
              problem,
              style: PosText.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: palette.danger,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        summary.when(
          loading: () => const SizedBox(height: 60),
          error: (error, _) => Text(
            '$error',
            style: PosText.ui(size: 13, color: palette.danger),
          ),
          data: (value) => _Headline(summary: value, now: clock),
        ),
        const SizedBox(height: PosSpace.md),
        Text(
          strings.etaQueueExplain,
          style: PosText.ui(size: 12.5, color: palette.muted, height: 1.6),
        ),
        if (reconciler != null) ...[
          const SizedBox(height: PosSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PosButton(
              key: const Key('eta-reconcile-now'),
              label: strings.etaReconcileNow,
              border: Border.fromBorderSide(palette.resting),
              onPressed: () async {
                final messenger = ScaffoldMessenger.maybeOf(context);
                final report = await reconciler.run();
                if (report == null) return; // A pass was already running.
                messenger?.showSnackBar(
                  SnackBar(
                    content: Text(
                      etaProblemText(strings, report.problem) ??
                          strings.etaReconcileDone(
                            report.salesFiled,
                            report.refundsFiled,
                            report.refundsWaiting,
                          ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: PosSpace.xl),
        rows.when(
          loading: () => Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.accent,
            ),
          ),
          error: (error, _) => Text(
            '$error',
            style: PosText.ui(size: 13, color: palette.danger),
          ),
          data: (outstanding) => outstanding.isEmpty
              ? const SizedBox.shrink()
              : _Table(rows: outstanding, now: clock),
        ),
      ],
    );
  }
}

/// The one sentence somebody reads before deciding whether to care.
class _Headline extends StatelessWidget {
  const _Headline({required this.summary, required this.now});

  final EtaQueueSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    if (summary.isClear) {
      return Container(
        padding: const EdgeInsets.all(PosSpace.md),
        color: palette.okSoft,
        child: Text(
          strings.etaQueueClear,
          style: PosText.ui(
            size: 15,
            weight: FontWeight.w700,
            color: palette.ok,
          ),
        ),
      );
    }

    // Urgent is late or refused, and it gets the danger ground. Work merely
    // in progress does not: a receipt rung up four minutes ago and not yet
    // sent is the normal state of a working till, and colouring that red
    // would teach everybody to ignore the colour.
    final urgent = summary.isUrgent;

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      color: urgent ? palette.dangerSoft : palette.warnSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.etaQueueOutstanding(summary.outstanding),
            style: PosText.ui(
              size: 15,
              weight: FontWeight.w700,
              color: urgent ? palette.danger : palette.warn,
            ),
          ),
          if (summary.late > 0) ...[
            const SizedBox(height: 4),
            Text(
              strings.etaQueueLate(summary.late),
              style: PosText.ui(size: 13, color: palette.danger),
            ),
          ],
          if (summary.rejected > 0) ...[
            const SizedBox(height: 4),
            Text(
              strings.etaQueueRejected(summary.rejected),
              style: PosText.ui(size: 13, color: palette.danger),
            ),
          ],
          if (summary.oldest case final oldest?) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${strings.etaQueueOldest} · ',
                  style: PosText.ui(size: 12.5, color: palette.body),
                ),
                MonoCode(
                  context.strings.etaAgeHours(
                    now.difference(oldest).inHours,
                  ),
                  color: palette.body,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows, required this.now});

  final List<EtaSubmission> rows;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: PosSpace.sm),
          child: Row(
            children: [
              Expanded(flex: 3, child: MicroLabel(strings.etaColumnReceipt)),
              Expanded(flex: 2, child: MicroLabel(strings.etaColumnAge)),
              Expanded(flex: 4, child: MicroLabel(strings.etaColumnStatus)),
            ],
          ),
        ),
        for (final row in rows) _Row(row: row, now: now),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.now});

  final EtaSubmission row;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final late = row.isLate(now);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      decoration: BoxDecoration(
        border: BorderDirectional(bottom: palette.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: MonoCode(row.receiptNumber, size: 12.5)),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                MonoCode(
                  strings.etaAgeHours(row.age(now).inHours),
                  size: 12.5,
                  color: late ? palette.danger : palette.body,
                ),
                if (late || row.isDueSoon(now)) ...[
                  const SizedBox(width: PosSpace.xs),
                  Text(
                    late ? strings.etaLate : strings.etaDueSoon,
                    style: PosText.ui(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: late ? palette.danger : palette.warn,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.etaStatusLabel(row.status.wire),
                  style: PosText.ui(
                    size: 12.5,
                    color: row.status.needsAttention
                        ? palette.danger
                        : palette.ink,
                  ),
                ),
                // The authority's own words, verbatim. A paraphrase would be
                // a paraphrase of the only sentence that says how to fix it.
                if (row.errorMessage case final message?) ...[
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sentence for a filing problem a person can fix, or null for none.
///
/// Public because the start screen says the same thing: the problem is the
/// business's, whichever screen somebody happens to open.
String? etaProblemText(AppStrings strings, EtaFilingSkipped? problem) =>
    switch (problem) {
      ProfileIncomplete(:final problems) => strings.etaProblemProfile(
        problems.length,
      ),
      FilingFailed(:final detail) => strings.etaProblemFailed(detail),
      _ => null,
    };
