import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import '../core/ui/theme.dart';
import '../core/ui/tokens.dart';
import '../core/ui/widgets/pos_widgets.dart';
import '../data/cloud/cloud_provisioning_repository.dart' show posAppVersion;
import 'providers.dart';

/// The bottom line of every screen of a set-up till: connection, branch, this
/// till, version, who is in.
///
/// **One bar, mounted once** above the router (`app.dart`), so every screen
/// shows the same facts in the same place and no screen draws its own. It was
/// the back office's alone until the owner asked for it everywhere (26 Oct
/// 2026): support asks over the phone for the branch, the till, the version and
/// whether the till is connected, and a cashier on the sale screen or the lock
/// screen had nowhere to read them out from.
///
/// **The till's own sources, not new ones** (plan 19 §1.3). The connection is
/// the same pill the till's top bar draws from the same providers — a sync
/// state on a cloud till, the branch server on an offline one — so the bar can
/// never call a till healthy that the till itself calls broken. The branch and
/// the till are the names the terminal was set up under, as About prints them;
/// the version is `posAppVersion`, as About prints it.
///
/// **Who is in** is `actingStaffProvider`'s answer: the administrator inside
/// the back office, otherwise whoever is signed in. [showPerson] is false on
/// the start and lock screens, where nobody is in front of the till yet — a
/// manual Lock leaves the last cashier signed in behind it, and printing their
/// name on the lock screen would defeat it.
class TillStatusBar extends ConsumerWidget {
  const TillStatusBar({super.key, this.showPerson = true});

  final bool showPerson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final strings = context.strings;
    final profile = ref.watch(terminalProfileProvider);
    final branch = profile.branchName;
    final terminal = profile.terminalName;
    final who = showPerson ? ref.watch(actingStaffProvider) : null;
    final meta = PosText.ui(size: 13, color: pos.body);

    // Its own Material: this sits above the router, so no screen's Scaffold is
    // an ancestor, and the connection pill is an InkWell that needs one.
    return Material(
      color: pos.surface,
      child: Container(
        key: const Key('till-status-bar'),
        height: PosSize.minTouchTarget,
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
        decoration: BoxDecoration(border: Border(top: pos.resting)),
        // Two groups pushed to the two edges, not one row with a spacer: the
        // branch and till names are flexible too, and a `Spacer` or an
        // `Expanded` beside them shared the free room three ways and left the
        // person floating mid-bar (26 Oct 2026). `spaceBetween` puts what is
        // left between the groups, so the person ends at the far edge — the
        // left of an Arabic bar, the right of an English one.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BackOfficeConnectionPill(),
                  if (branch != null && branch.isNotEmpty) ...[
                    const SizedBox(width: PosSpace.lg),
                    Icon(Icons.storefront_outlined, size: 16, color: pos.muted),
                    const SizedBox(width: PosSpace.xs),
                    Flexible(
                      child: Text(
                        branch,
                        key: const Key('till-status-branch'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta,
                      ),
                    ),
                  ],
                  // A name somebody typed at setup, in either script — so the
                  // UI face, not mono: it is a word, not a code.
                  if (terminal != null && terminal.trim().isNotEmpty) ...[
                    const SizedBox(width: PosSpace.lg),
                    Icon(
                      Icons.point_of_sale_outlined,
                      size: 16,
                      color: pos.muted,
                    ),
                    const SizedBox(width: PosSpace.xs),
                    Flexible(
                      child: Text(
                        terminal,
                        key: const Key('till-status-terminal'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta,
                      ),
                    ),
                  ],
                  const SizedBox(width: PosSpace.lg),
                  // A code, not a word: mono and left to right in both
                  // languages.
                  Text(
                    'v$posAppVersion',
                    key: const Key('till-status-version'),
                    textDirection: TextDirection.ltr,
                    style: PosText.mono(size: 12, color: pos.muted),
                  ),
                ],
              ),
            ),
            if (who != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: PosSpace.lg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline, size: 16, color: pos.muted),
                      const SizedBox(width: PosSpace.xs),
                      // Flexible: a long name must not push the bar past the
                      // window.
                      Flexible(
                        child: Text(
                          '${who.name} · '
                          '${who.role?.displayName(strings.languageCode) ?? strings.noRole}',
                          key: const Key('till-status-user'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: meta,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The connection, as the till's top bar shows it: the sync state on a cloud
/// till, the branch server on an offline one.
///
/// Which pill and why is the till's top bar's decision; see it. Home's
/// connection card drew this too, until the owner took it away as the status
/// bar said twice (15 Sep 2026).
class BackOfficeConnectionPill extends ConsumerWidget {
  const BackOfficeConnectionPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(cloudSyncProvider) case final cloud?) {
      final sync = ref.watch(pendingSyncCountProvider);
      return SyncPill(
        online: ref.watch(posUiProvider).online,
        queued: sync.valueOrNull,
        hasError: sync.hasError,
        onTap: () {
          cloud.kick();
          posToast(context, context.strings.syncingWithPlatform);
        },
      );
    }
    final probe = ref.watch(branchDatabaseProvider);
    return BranchServerPill(
      checking: probe.isLoading,
      reachable: probe.hasValue && probe.value == null,
      onTap: () => ref.invalidate(branchDatabaseProvider),
    );
  }
}
