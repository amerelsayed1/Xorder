import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/domain/models/sync_outcome.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'admin_pane_bits.dart';

/// What has gone wrong with a cloud till's sync, worst first.
///
/// An enum and a total switch for the words, so a sixth kind of trouble
/// without an Arabic sentence fails to compile rather than showing nothing.
enum SyncProblem {
  /// The platform refuses this till's credential. Outranks everything: no
  /// pass will send anything until somebody re-pairs it.
  terminalRejected,

  /// The pass this pane ran threw.
  passFailed,

  /// The platform stopped answering.
  platformSilent,

  /// Records the platform refused, or the till would not send, held for a
  /// person — by the pass this pane ran, or still sitting in the queue.
  held,

  /// The outbox itself could not be read, so the count is not a count.
  outboxUnreadable,
}

/// The one problem worth a line, or null for none.
///
/// **Built from what the till already knows**, not a new query: the signals
/// the top bar and the rejected-terminal banner already act on, the outcome of
/// any pass this pane ran itself, and [heldCount] — the held records the
/// pane's own list reads. The held count used to come only from the last pass,
/// so a restart forgot it and a sale held yesterday showed "no problem" (D8).
SyncProblem? syncProblemOf({
  required bool terminalRejected,
  required bool online,
  required bool countUnreadable,
  SyncOutcome? lastPass,
  bool lastPassFailed = false,
  int heldCount = 0,
}) {
  if (terminalRejected || (lastPass?.deviceTokenRejected ?? false)) {
    return SyncProblem.terminalRejected;
  }
  if (lastPassFailed) return SyncProblem.passFailed;
  if (!online || (lastPass?.drain.wentOffline ?? false)) {
    return SyncProblem.platformSilent;
  }
  if ((lastPass?.drain.quarantined ?? 0) > 0 || heldCount > 0) {
    return SyncProblem.held;
  }
  if (countUnreadable) return SyncProblem.outboxUnreadable;
  return null;
}

String syncProblemLabel(AppStrings s, SyncProblem problem, {int held = 0}) =>
    switch (problem) {
      SyncProblem.terminalRejected => s.terminalRejectedTitle,
      SyncProblem.passFailed => s.syncPassFailed,
      SyncProblem.platformSilent => s.syncPlatformSilent,
      SyncProblem.held => s.syncHeld(held),
      SyncProblem.outboxUnreadable => s.syncStatusUnavailable,
    };

/// System › Sync: where this till's sales go, and whether they got there.
///
/// **Two different questions by deployment**, as the till's top bar already
/// decides (see `PosTopBar`). A cloud till owes its sales to the platform, so
/// this shows what it owes, what it last received, and the one "sync now" the
/// pill and the Settings menu already run — the cloud app's sync pass, the same pass,
/// joined rather than raced if a timer tick is mid-flight. An offline till
/// owes them to nobody: it shows the branch server and the last copy, and
/// says plainly that there is no cloud, because a Sync pane that sat empty
/// would read as a sync that had broken.
///
/// **No capability of its own.** The till gives "sync now" to anybody signed
/// in (the pill, the Settings menu), and the database address below is what
/// the About dialog shows to anybody too. Gating the pane harder than the till
/// would only hide from a manager what the cashier beside them can see.
///
/// The one write it holds is: **Retry** on a held record, behind
/// `terminal.manage`. Seeing that a sale is stuck is everybody's business;
/// deciding to offer it to the platform again is the person's who answers for
/// this till.
class ManagementSyncPane extends ConsumerStatefulWidget {
  const ManagementSyncPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementSyncPane> createState() => _ManagementSyncPaneState();
}

class _ManagementSyncPaneState extends ConsumerState<ManagementSyncPane> {
  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return ListView(
      key: const Key('sync-pane'),
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneSync, hint: strings.paneSyncBlurb),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          // Always the offline till: this pane is the offline app's, and a
          // cloud till has no back office to show a sync pane in (CB-07).
          // The cloud branch left with the cloud code (pos-split-apps,
          // stage 3).
          child: const _OfflineTill(),
        ),
      ],
    );
  }

}

class _OfflineTill extends ConsumerWidget {
  const _OfflineTill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final pos = context.pos;
    final config = ref.watch(deploymentProvider);
    final host = PosDatabase.hostFor(config);
    final probe = ref.watch(branchDatabaseProvider);
    final records = ref.watch(backupsProvider).valueOrNull;
    // Only a VERIFIED copy counts, as on Home and in the backup notice: a copy
    // that failed to prove itself is not one anybody can restore.
    final verified = records?.where((r) => r.isRestorable).firstOrNull;

    return Column(
      key: const Key('sync-offline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.syncOfflineTill,
          key: const Key('sync-offline-sentence'),
          style: PosText.ui(size: 13, color: pos.body, height: 1.5),
        ),
        const SizedBox(height: PosSpace.md),
        PaneFact(
          label: strings.syncBranchServer,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            // The top bar's own pill, on the same probe: the back office
            // cannot call the branch server healthy while the till says not.
            child: BranchServerPill(
              checking: probe.isLoading,
              reachable: probe.hasValue && probe.value == null,
              onTap: () => ref.invalidate(branchDatabaseProvider),
            ),
          ),
        ),
        PaneFact(
          label: strings.aboutDatabase,
          // Name, host and port — never the user or the password. This is read
          // aloud to support, and a password said down a phone is a password
          // somebody else now has.
          child: host == null
              ? Text(strings.homeNotSet, style: _words(pos))
              : _Mono(
                  '${config.databaseName} · $host:${config.databasePort}',
                  key: const Key('sync-database'),
                ),
        ),
        PaneFact(
          label: strings.homeCardLastBackup,
          child: switch ((records, verified)) {
            (_, final copy?) => _Mono(
              _stamp(copy.takenAt),
              key: const Key('sync-last-backup'),
            ),
            (null, _) => const SizedBox.shrink(),
            (final all?, null) when all.isEmpty => Text(
              strings.homeNever,
              style: _words(pos),
            ),
            (_, null) => Text(
              strings.backupNoVerifiedCopy,
              style: PosText.ui(size: 13, color: pos.warn),
            ),
          },
        ),
      ],
    );
  }
}

TextStyle _words(PosPalette pos) => PosText.ui(size: 13, color: pos.body);

/// A value that is a code: mono, and left to right in Arabic too.
class _Mono extends StatelessWidget {
  const _Mono(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textDirection: TextDirection.ltr,
    style: PosText.mono(size: 13, color: context.pos.ink),
  );
}

/// Western digits in both languages, as Home and the backup pane print times.
String _stamp(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
