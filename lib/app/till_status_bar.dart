import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import '../core/ui/theme.dart';
import '../core/ui/tokens.dart';
import '../core/ui/widgets/pos_widgets.dart';
import '../data/cloud/cloud_provisioning_repository.dart' show posAppVersion;
import '../domain/models/branch_sales.dart' show businessDayWire;
import '../domain/services/business_day_service.dart'
    show DayNotice, DayNoticeKind;
import '../features/shift/presentation/shift_dialogs.dart'
    show CloseShiftDialog;
import 'providers.dart';
import 'router.dart' show PosRoutes, rootNavigatorKey, routerProvider;

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
  const TillStatusBar({
    super.key,
    this.showPerson = true,
    this.showCloseShift = false,
  });

  final bool showPerson;

  /// Close shift, on the cashier's screen only. It was the sale screen's top
  /// bar's button until the owner moved it here, beside the day notice (26 Oct
  /// 2026): the notice says the day is still open, and this is where the
  /// cashier acts on it.
  final bool showCloseShift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final strings = context.strings;
    final profile = ref.watch(terminalProfileProvider);
    final branch = profile.branchName;
    final terminal = profile.terminalName;
    final who = showPerson ? ref.watch(actingStaffProvider) : null;
    final notice = ref.watch(dayNoticeProvider).valueOrNull;
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
            // A warning, not a refusal: nothing here stops the till selling.
            if (notice != null) _DayNotice(notice),
            if (showCloseShift) const _CloseShiftButton(),
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

/// A day left open from an earlier date, or sales after the date was closed,
/// said in a few words in the bar (it was a banner on the start screen). The
/// full sentence, with what to do about it, is the tooltip.
class _DayNotice extends StatelessWidget {
  const _DayNotice(this.notice);

  final DayNotice notice;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final date = businessDayWire(notice.date);
    final (short, full) = switch (notice.kind) {
      DayNoticeKind.staleOpenDay => (
        strings.dayStillOpenShort(date),
        strings.dayStillOpenFrom(date),
      ),
      DayNoticeKind.todayAlreadyClosed => (
        strings.dayClosedTodayShort(date),
        strings.dayClosedTodayNotice(date),
      ),
    };
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
        child: Tooltip(
          message: full,
          child: Container(
            key: const Key('till-status-day-notice'),
            padding: const EdgeInsets.symmetric(
              horizontal: PosSpace.sm,
              vertical: PosSpace.xs,
            ),
            decoration: BoxDecoration(
              color: pos.offlinePillBg,
              border: Border.all(color: pos.warn),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: pos.offlinePillText,
                ),
                const SizedBox(width: PosSpace.xs),
                Flexible(
                  child: Text(
                    short,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PosText.ui(size: 12.5, color: pos.offlinePillText),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cash up and hand the till back.
///
/// What the sale screen's top-bar button did, unchanged: a ticket still on the
/// screen is not discarded (the cashier is told instead), a till with no shift
/// open has nothing to count and just goes back to Start, and otherwise the
/// count dialog runs and Start follows once the shift is closed.
///
/// The dialog is opened on the root navigator's context, as About is: this bar
/// sits above the router, so its own context has no Navigator above it.
class _CloseShiftButton extends ConsumerWidget {
  const _CloseShiftButton();

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final router = ref.read(routerProvider);
    if (!ref.read(ticketProvider).isEmpty) {
      posToast(context, context.strings.ticketStillOpen);
      return;
    }
    final shift = ref.read(shiftProvider).valueOrNull;
    if (shift == null) {
      router.go(PosRoutes.start);
      return;
    }
    final dialogContext = rootNavigatorKey.currentContext;
    if (dialogContext == null) return;
    final closed = await CloseShiftDialog.show(dialogContext, shift: shift);
    if (closed) router.go(PosRoutes.start);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: PosSpace.lg),
      child: PosButton(
        key: const Key('till-status-close-shift'),
        label: context.strings.closeShift,
        height: 32,
        fontSize: 12.5,
        foreground: pos.offlinePillText,
        border: Border.all(color: pos.warn),
        onPressed: () => _close(context, ref),
      ),
    );
  }
}
