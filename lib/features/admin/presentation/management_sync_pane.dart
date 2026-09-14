import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../data/cloud/cloud_sync.dart';
import '../../../data/postgres/pos_database.dart';
import '../../../domain/models/shift.dart';
import '../application/back_office_home.dart';
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

  /// Sales the platform refused, held for a person.
  held,

  /// The outbox itself could not be read, so the count is not a count.
  outboxUnreadable,
}

/// The one problem worth a line, or null for none.
///
/// **Built from what the till already knows**, not a new query. The outbox's
/// own `last_error` column is per sale and written by the drain; reading it
/// here would be a second path into the sync, which is the one thing this
/// pane must not grow. What it has instead is the signals the top bar and the
/// rejected-terminal banner already act on, plus the outcome of any pass it
/// ran itself.
SyncProblem? syncProblemOf({
  required bool terminalRejected,
  required bool online,
  required bool countUnreadable,
  SyncOutcome? lastPass,
  bool lastPassFailed = false,
}) {
  if (terminalRejected || (lastPass?.deviceTokenRejected ?? false)) {
    return SyncProblem.terminalRejected;
  }
  if (lastPassFailed) return SyncProblem.passFailed;
  if (!online || (lastPass?.drain.wentOffline ?? false)) {
    return SyncProblem.platformSilent;
  }
  if ((lastPass?.drain.quarantined ?? 0) > 0) return SyncProblem.held;
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
/// pill and the Settings menu already run — [CloudSync.run], the same pass,
/// joined rather than raced if a timer tick is mid-flight. An offline till
/// owes them to nobody: it shows the branch server and the last copy, and
/// says plainly that there is no cloud, because a Sync pane that sat empty
/// would read as a sync that had broken.
///
/// **No capability of its own.** The till gives "sync now" to anybody signed
/// in (the pill, the Settings menu), and the database address below is what
/// the About dialog shows to anybody too. Gating the pane harder than the till
/// would only hide from a manager what the cashier beside them can see.
class ManagementSyncPane extends ConsumerStatefulWidget {
  const ManagementSyncPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementSyncPane> createState() => _ManagementSyncPaneState();
}

class _ManagementSyncPaneState extends ConsumerState<ManagementSyncPane> {
  bool _running = false;
  SyncOutcome? _lastPass;
  bool _lastPassFailed = false;

  Future<void> _syncNow(CloudSync cloud) async {
    setState(() => _running = true);
    SyncOutcome? outcome;
    var failed = false;
    try {
      outcome = await cloud.run();
    } on Object {
      failed = true;
    }
    if (!mounted) return;
    // `onChanged` only fires when the pass changed something; a pass that
    // sent nothing still answers "is the count right", so ask again anyway.
    ref
      ..invalidate(pendingSyncCountProvider)
      ..invalidate(lastPlatformSyncProvider);
    setState(() {
      _running = false;
      _lastPass = outcome;
      _lastPassFailed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final cloud = ref.watch(cloudSyncProvider);
    return ListView(
      key: const Key('sync-pane'),
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneSync, hint: strings.paneSyncBlurb),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: cloud == null ? const _OfflineTill() : _cloud(cloud),
        ),
      ],
    );
  }

  Widget _cloud(CloudSync cloud) {
    final strings = context.strings;
    final pos = context.pos;
    final at = ref.watch(lastPlatformSyncProvider).valueOrNull;
    final count = ref.watch(pendingSyncCountProvider);
    final problem = syncProblemOf(
      terminalRejected: ref.watch(terminalRejectedProvider),
      online: ref.watch(posUiProvider).online,
      countUnreadable: count.hasError,
      lastPass: _lastPass,
      lastPassFailed: _lastPassFailed,
    );

    return Column(
      key: const Key('sync-cloud'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneFact(
          label: strings.syncLastConfig,
          child: at == null
              ? Text(strings.homeNever, style: _words(pos))
              : _Mono(_stamp(at), key: const Key('sync-last-config')),
        ),
        PaneFact(
          label: strings.syncUnsent,
          child: switch (count.valueOrNull) {
            final queued? => _Mono(
              '$queued',
              key: const Key('sync-unsent'),
              color: queued > 0 ? pos.warn : pos.ink,
            ),
            null => Text('—', style: _words(pos)),
          },
        ),
        PaneFact(
          label: strings.syncLastProblem,
          child: Text(
            problem == null
                ? strings.syncNoProblem
                : syncProblemLabel(
                    strings,
                    problem,
                    held: _lastPass?.drain.quarantined ?? 0,
                  ),
            key: const Key('sync-problem'),
            style: PosText.ui(
              size: 13,
              color: problem == null ? pos.body : pos.danger,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: PosSpace.lg),
        Row(
          children: [
            PosButton(
              key: const Key('sync-now'),
              label: _running ? strings.syncingWithPlatform : strings.syncNow,
              background: pos.ink,
              foreground: pos.onInk,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
              onPressed: _running ? null : () => _syncNow(cloud),
            ),
            if (_lastPass case final pass? when !_running) ...[
              const SizedBox(width: PosSpace.md),
              Flexible(
                child: Text(
                  strings.syncPassSent(pass.drain.delivered),
                  key: const Key('sync-pass-sent'),
                  style: PosText.ui(size: 12.5, color: pos.muted),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The offline answer: no cloud, the branch server, the database, the copy.
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
  const _Mono(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textDirection: TextDirection.ltr,
    style: PosText.mono(size: 13, color: color ?? context.pos.ink),
  );
}

/// Western digits in both languages, as Home and the backup pane print times.
String _stamp(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
