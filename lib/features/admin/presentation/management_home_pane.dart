import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/branch_sales.dart' show businessDayWire;
import '../../../domain/models/home_sales.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import '../application/back_office_home.dart';

/// Where Home's shortcuts go. An enum and a total switch for the words, so a
/// fourth shortcut without an Arabic label fails to compile.
///
/// **Two of the mockup's four are cut** (plan 19 §2.1): net profit, because no
/// product has a cost price, and low stock, because stock items have no
/// reorder level and sales deduct nothing — any figure behind either would be
/// invented.
enum HomeQuickAction { salesReports, products, employees }

String homeQuickActionLabel(AppStrings s, HomeQuickAction action) =>
    switch (action) {
      HomeQuickAction.salesReports => s.homeActionReports,
      HomeQuickAction.products => s.homeActionProducts,
      HomeQuickAction.employees => s.homeActionEmployees,
    };

IconData homeQuickActionIcon(HomeQuickAction action) => switch (action) {
  HomeQuickAction.salesReports => Icons.bar_chart_outlined,
  HomeQuickAction.products => Icons.restaurant_menu_outlined,
  HomeQuickAction.employees => Icons.badge_outlined,
};

/// A delta in basis points as a person reads it: `+12.50%`, `-3.07%`.
///
/// Two decimals because that is what a basis point is — printing it to one
/// would be a second rounding after [deltaBp]'s, and rounding happens once.
String formatDeltaBp(int bp) {
  final sign = bp > 0 ? '+' : (bp < 0 ? '-' : '');
  final magnitude = bp.abs();
  return '$sign${magnitude ~/ 100}.'
      '${(magnitude % 100).toString().padLeft(2, '0')}%';
}

/// The back office's landing page (BO-4, plan 19 §2.1).
///
/// **Takes callbacks, not panes.** Which shortcuts exist, and whether the
/// terminal and backup cards lead anywhere, is the shell's decision, made from
/// the same pane list the strip and the bar use (`homeQuickActionsFor`). A
/// Home that worked its own list out would be the third list meant to agree
/// with the other two, and the first to offer Menu on a cloud till.
///
/// **A desktop-only page.** The cloud's Home shows menu counts and a setup
/// guide, not sales; an offline install has no other dashboard (plan 17 §2),
/// so this one shows the day.
class ManagementHomePane extends ConsumerWidget {
  const ManagementHomePane({
    required this.admin,
    required this.actions,
    this.onOpenTerminal,
    this.onOpenBackup,
    super.key,
  });

  final PosStaff admin;
  final List<(HomeQuickAction, VoidCallback)> actions;

  /// Null when this person has no Terminal pane: the card then states the
  /// name and leads nowhere, rather than to a pane that is not there.
  final VoidCallback? onOpenTerminal;
  final VoidCallback? onOpenBackup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final strings = context.strings;
    final profile = ref.watch(terminalProfileProvider);
    final cloud = ref.watch(cloudSyncProvider) != null;
    // The administrator's, not the till operator's: Home is inside Admin
    // Mode, and the person reading it is whoever came through its door.
    final reports = Authorization.check(
      admin,
      PosCapability.reportsView,
    ).isAllowed;

    return ListView(
      key: const Key('home-pane'),
      padding: const EdgeInsets.all(PosSpace.s24),
      children: [
        Text(
          strings.homeWelcome(admin.name),
          style: PosText.panelTitle(color: pos.ink),
        ),
        const SizedBox(height: PosSpace.xs),
        Text(
          strings.paneHomeBlurb,
          style: PosText.ui(size: 13.5, color: pos.body),
        ),
        const SizedBox(height: PosSpace.s24),
        _Row(
          children: [
            _StatusCard(
              key: const Key('home-card-branch'),
              label: strings.branchCell,
              onOpen: onOpenTerminal,
              child: _Value(_named(profile.branchName) ?? strings.homeNotSet),
            ),
            _StatusCard(
              key: const Key('home-card-device'),
              label: strings.terminalCell,
              onOpen: onOpenTerminal,
              child: _Value(
                _named(profile.terminalName) ?? strings.homeNotSet,
              ),
            ),
            _StatusCard(
              key: const Key('home-card-connection'),
              label: strings.homeCardConnection,
              child: const Align(
                alignment: AlignmentDirectional.centerStart,
                child: BackOfficeConnectionPill(),
              ),
            ),
            // Offline has no platform, so "last sync" would always say never.
            // The offline answer to "is my data safe" is the last copy.
            if (cloud)
              const _LastSyncCard()
            else
              _LastBackupCard(onOpen: onOpenBackup),
          ],
        ),
        // Absent, not greyed: a tile with its figure hidden still says how
        // much there is to hide. The same capability the till's branch view
        // asks for (`branchSalesAllowedProvider`).
        if (reports) ...[
          const SizedBox(height: PosSpace.s28),
          const _Tiles(),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: PosSpace.s28),
          MicroLabel(strings.homeQuickActions),
          const SizedBox(height: PosSpace.sm),
          _Row(
            children: [
              for (final (action, open) in actions)
                _QuickAction(action: action, onOpen: open),
            ],
          ),
        ],
      ],
    );
  }
}

String? _named(String? name) =>
    name == null || name.trim().isEmpty ? null : name;

/// The connection, as the till's top bar shows it: the sync state on a cloud
/// till, the branch server on an offline one.
///
/// **One widget for the status bar and Home's card**, so the back office
/// cannot call a till healthy in one place and broken in the other. Which pill
/// and why is the till's top bar's decision; see it.
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

/// Equal-width cards of equal height, with the design's gutter between.
class _Row extends StatelessWidget {
  const _Row({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(width: PosSpace.md),
          Expanded(child: child),
        ],
      ],
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.label,
    required this.child,
    this.onOpen,
    super.key,
  });

  final String label;
  final Widget child;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final card = PosSurface(
      padding: const EdgeInsets.all(PosSpace.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MicroLabel(label),
                const SizedBox(height: PosSpace.sm),
                child,
              ],
            ),
          ),
          // `chevron_right` follows the text direction: it points left in
          // Arabic, which is where "onward" is.
          if (onOpen != null)
            Icon(Icons.chevron_right, size: 20, color: context.pos.muted),
        ],
      ),
    );
    if (onOpen == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: card,
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: PosText.ui(
      size: 15,
      weight: FontWeight.w600,
      color: color ?? context.pos.ink,
    ),
  );
}

/// A time, as data: mono and left to right in both languages.
class _Stamp extends StatelessWidget {
  const _Stamp(this.at);

  final DateTime at;

  @override
  Widget build(BuildContext context) => Text(
    _stamp(at),
    textDirection: TextDirection.ltr,
    style: PosText.mono(
      size: 14,
      weight: FontWeight.w600,
      color: context.pos.ink,
    ),
  );
}

class _LastSyncCard extends ConsumerWidget {
  const _LastSyncCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final at = ref.watch(lastPlatformSyncProvider).valueOrNull;
    final queued = ref.watch(pendingSyncCountProvider).valueOrNull;
    return _StatusCard(
      key: const Key('home-card-last-sync'),
      label: strings.homeCardLastSync,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (at != null) _Stamp(at) else _Value(strings.homeNever),
          // The part of "synced" that is about money. The bundle's time says
          // the menu is current; this says whether the sales have gone up.
          if (queued != null) ...[
            const SizedBox(height: PosSpace.xs),
            Text(
              strings.homeSalesWaiting(queued),
              style: PosText.ui(
                size: 12.5,
                color: queued > 0 ? context.pos.warn : context.pos.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LastBackupCard extends ConsumerWidget {
  const _LastBackupCard({this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final records = ref.watch(backupsProvider).valueOrNull;
    // Only a VERIFIED copy counts, as in the back office's backup notice: a
    // copy that failed to prove itself is not one anybody can restore.
    final verified = records?.where((r) => r.isRestorable).firstOrNull;
    return _StatusCard(
      key: const Key('home-card-last-backup'),
      label: strings.homeCardLastBackup,
      onOpen: onOpen,
      child: switch ((records, verified)) {
        (_, final copy?) => _Stamp(copy.takenAt),
        (null, _) => const SizedBox.shrink(),
        (final all?, null) when all.isEmpty => _Value(strings.homeNever),
        (_, null) => _Value(
          strings.backupNoVerifiedCopy,
          color: context.pos.warn,
        ),
      },
    );
  }
}

/// The three figures, and the day they belong to.
class _Tiles extends ConsumerWidget {
  const _Tiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final strings = context.strings;
    return Column(
      key: const Key('home-tiles'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(strings.homeToday),
        const SizedBox(height: PosSpace.sm),
        ...switch (ref.watch(homeSalesProvider)) {
          AsyncData(value: final home?) => [
            _DayCaption(home: home),
            const SizedBox(height: PosSpace.md),
            _Row(
              children: [
                _KpiTile(
                  key: const Key('home-tile-net'),
                  label: strings.homeKpiNetSales,
                  value: MonoAmount(
                    home.sales.net,
                    size: 26,
                    weight: FontWeight.w600,
                  ),
                  delta: home.netDeltaBp,
                  comparable: home.previous != null,
                ),
                _KpiTile(
                  key: const Key('home-tile-orders'),
                  label: strings.homeKpiOrders,
                  value: Text(
                    '${home.sales.orders}',
                    textDirection: TextDirection.ltr,
                    style: PosText.mono(
                      size: 26,
                      weight: FontWeight.w600,
                      color: pos.ink,
                    ),
                  ),
                  delta: home.ordersDeltaBp,
                  comparable: home.previous != null,
                ),
                _KpiTile(
                  key: const Key('home-tile-average'),
                  label: strings.homeKpiAverage,
                  value: switch (home.average) {
                    final average? => MonoAmount(
                      average,
                      size: 26,
                      weight: FontWeight.w600,
                    ),
                    null => Text(
                      '—',
                      style: PosText.mono(size: 26, color: pos.muted),
                    ),
                  },
                  delta: home.averageDeltaBp,
                  comparable: home.previous != null,
                ),
              ],
            ),
          ],
          AsyncData(value: null) => [_Note(strings.homeNoDayYet)],
          AsyncError() => [_Note(strings.homeSalesUnavailable, danger: true)],
          _ => [const SizedBox(height: 120)],
        },
      ],
    );
  }
}

/// Which day the figures are, said every time — and said loudly when it is
/// not today's.
class _DayCaption extends StatelessWidget {
  const _DayCaption({required this.home});

  final HomeSales home;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final date = businessDayWire(home.day.date);
    final open = home.isOpen;
    return Row(
      key: const Key('home-day-caption'),
      children: [
        Icon(
          open ? Icons.today_outlined : Icons.history,
          size: 16,
          color: open ? pos.muted : pos.warn,
        ),
        const SizedBox(width: PosSpace.xs),
        Expanded(
          child: Text(
            open
                ? strings.homeDayOpen(date, _time(home.day.openedAt))
                : strings.homeDayClosed(date),
            style: PosText.ui(
              size: 13,
              weight: open ? FontWeight.w400 : FontWeight.w600,
              color: open ? pos.body : pos.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.delta,
    required this.comparable,
    super.key,
  });

  final String label;
  final Widget value;
  final int? delta;

  /// Whether there was an earlier day at all. A null [delta] with one means
  /// that day's figure was zero, which has no percentage.
  final bool comparable;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final muted = PosText.ui(size: 12, color: pos.muted);
    return PosSurface(
      padding: const EdgeInsets.all(PosSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(label),
          const SizedBox(height: PosSpace.sm),
          value,
          const SizedBox(height: PosSpace.sm),
          switch (delta) {
            final bp? => Row(
              key: const Key('home-delta'),
              children: [
                Icon(
                  bp > 0
                      ? Icons.arrow_upward
                      : (bp < 0 ? Icons.arrow_downward : Icons.remove),
                  size: 14,
                  color: _tone(pos, bp),
                ),
                const SizedBox(width: PosSpace.xs),
                Text(
                  formatDeltaBp(bp),
                  textDirection: TextDirection.ltr,
                  style: PosText.mono(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: _tone(pos, bp),
                  ),
                ),
                const SizedBox(width: PosSpace.sm),
                Flexible(
                  child: Text(
                    strings.homeVsPreviousDay,
                    maxLines: 2,
                    style: muted,
                  ),
                ),
              ],
            ),
            null => Text(
              comparable ? '— ${strings.homeVsPreviousDay}' : strings.homeNoComparison,
              style: muted,
            ),
          },
        ],
      ),
    );
  }

  /// Colour on the words and the arrow only, never the tile: no tinted tiles
  /// (`07-design-system.md`), and a green card on a good morning reads as a
  /// button.
  static Color _tone(PosPalette pos, int bp) =>
      bp > 0 ? pos.ok : (bp < 0 ? pos.danger : pos.muted);
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.action, required this.onOpen});

  final HomeQuickAction action;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return GestureDetector(
      key: Key('home-action-${action.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: PosSurface(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: PosSpace.md,
        ),
        child: Row(
          children: [
            Icon(homeQuickActionIcon(action), size: 20, color: pos.ink),
            const SizedBox(width: PosSpace.md),
            Expanded(
              child: Text(
                homeQuickActionLabel(context.strings, action),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(
                  size: 14,
                  weight: FontWeight.w600,
                  color: pos.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: pos.muted),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Text(
    text,
    key: const Key('home-note'),
    style: PosText.ui(
      size: 13,
      color: danger ? context.pos.danger : context.pos.body,
      height: 1.4,
    ),
  );
}

/// Western digits in both languages, as the backup pane prints its copies.
String _stamp(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${_time(local)}';
}

String _time(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
