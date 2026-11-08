import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'admin_pane_bits.dart';

// `SyncProblem`, `syncProblemOf` and `syncProblemLabel` are gone
// (pos-split-apps, stage 4). They ranked what had gone wrong with a CLOUD
// till's sync — a rejected credential, a silent platform, held records — and
// stage 3 kept them "for the home pane", which by then no longer called them.
// The offline app has no platform to be rejected by or held against, so
// nothing here could ever have produced one.

/// System › Sync: where this till's sales go, and whether they got there.
///
/// **The offline app's pane, so one answer** (pos-split-apps). An offline till
/// owes its sales to nobody: it shows the branch server and the last copy, and
/// says plainly that there is no cloud, because a Sync pane that sat empty
/// would read as a sync that had broken. The cloud till's half — what it owes
/// the platform, "sync now", held records and their Retry — left with the
/// cloud code in stage 3; a cloud till has no back office to show it in
/// (CB-07).
///
/// **No capability of its own.** The database address below is what the About
/// dialog shows to anybody too; gating the pane harder than the till would
/// only hide from a manager what the cashier beside them can see.
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
