import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/mono_amount.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart' show businessDayWire;
import 'package:xorder_pos/domain/models/home_sales.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import '../application/back_office_home.dart';

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

/// The back office's landing page (BO-4, plan 19 §2.1): a greeting, and the
/// day's figures for whoever may read them.
///
/// **No status cards and no shortcuts** (owner, 15 Sep 2026: "there is
/// duplication here, I don't need that"). Branch, device, connection and last
/// backup each had a card here, and every one of them was already said on the
/// same screen — the status bar under every page names the branch, the till
/// and the connection, and the backup notice over every page says when the
/// last good copy was taken. The three shortcuts were three lines of the
/// window's bar drawn a second time. Two places saying one thing are two to
/// keep in step, and the day's figures are the one thing only Home says.
///
/// **A desktop-only page.** The cloud's Home shows menu counts and a setup
/// guide, not sales; an offline install has no other dashboard (plan 17 §2),
/// so this one shows the day.
class ManagementHomePane extends ConsumerWidget {
  const ManagementHomePane({required this.admin, super.key});

  final PosStaff admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final strings = context.strings;
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
        // Absent, not greyed: a tile with its figure hidden still says how
        // much there is to hide. The same capability the till's branch view
        // asks for (`branchSalesAllowedProvider`).
        if (reports) ...[
          const SizedBox(height: PosSpace.s28),
          const _Tiles(),
        ],
      ],
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

String _time(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
