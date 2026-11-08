import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/labels.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/services/floor_overlay.dart';

/// Floor — the dine-in landing screen. Pick a table before selling.
///
/// Non-dine-in modes skip this screen entirely.
///
/// Three things on top of the plain grid, all of them things a waiter asks
/// the room with their eyes and should not have to:
/// - **sections** — one tab per area the manager named, so the terrace is
///   not scrolled past to reach the bar;
/// - **time** — how long each party has sat, and which tables need somebody
///   (a round rung up but never fired, a table the kitchen has not heard
///   from, a bill asked and still unpaid), judged by [attentionFor];
/// - **type-to-jump** — the cashier types `12` and presses Enter. The screen
///   is keyboard-driven everywhere else; the floor was the one place that
///   made them reach for the mouse.
class FloorScreen extends ConsumerStatefulWidget {
  const FloorScreen({
    super.key,
    required this.onTablePicked,
    required this.onSellWithoutTable,
    required this.onClose,
    this.now,
  });

  final void Function(DiningTable table) onTablePicked;

  /// Go to the sale screen with nobody seated. The floor is a dine-in
  /// convenience, not a gate: a branch with no tables yet, or a walk-in
  /// buying a coffee, must still be able to sell.
  final VoidCallback onSellWithoutTable;

  /// Back to the start screen. Without it a floor with no tiles on it is a
  /// screen with no way out — the shift is open and the only exit is killing
  /// the app.
  final VoidCallback onClose;

  /// The clock the tiles read against. Null reads the system clock and ticks
  /// it every half minute; a test passes a fixed instant and nothing ticks.
  final DateTime? now;

  @override
  ConsumerState<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends ConsumerState<FloorScreen> {
  /// Null is the "All" tab; otherwise a section name, or `''` for the main
  /// room (a section with no name).
  String? _section;

  /// What the cashier has typed to jump to a table.
  String _typed = '';

  /// One timer for the whole floor, so the "seated 42m" on every tile moves
  /// together and no tile owns a clock of its own. Owned by the widget, not a
  /// provider, so it dies with the screen.
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.now == null) {
      _tick = Timer.periodic(
        const Duration(seconds: 30),
        (_) => setState(() => _now = DateTime.now()),
      );
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  List<DiningTable> _visible(List<FloorSection> sections) {
    final section = _section;
    final tables = section == null
        ? [for (final s in sections) ...s.tables]
        : sections
              .where((s) => (s.name ?? '') == section)
              .expand((s) => s.tables)
              .toList();
    if (_typed.isEmpty) return tables;
    final needle = _typed.toLowerCase();
    return [
      for (final t in tables)
        if (t.label.toLowerCase().contains(needle)) t,
    ];
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, List<DiningTable> all) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_typed.isEmpty) return KeyEventResult.ignored;
      setState(() => _typed = '');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_typed.isEmpty) return KeyEventResult.ignored;
      setState(() => _typed = _typed.substring(0, _typed.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_typed.isEmpty) return KeyEventResult.ignored;
      // An exact label wins over a prefix — typing `1` with T1 and T12 both
      // on the floor opens T1, not whichever the grid listed first.
      final needle = _typed.toLowerCase();
      final matches = [
        for (final t in all)
          if (t.label.toLowerCase().contains(needle)) t,
      ];
      final exact = matches.where(
        (t) =>
            t.label.toLowerCase() == needle ||
            _digits(t.label) == _digits(_typed),
      );
      final pick = exact.isNotEmpty
          ? exact.first
          : (matches.length == 1 ? matches.first : null);
      if (pick != null) {
        setState(() => _typed = '');
        widget.onTablePicked(pick);
      }
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (char != null && char.length == 1 && char.trim().isNotEmpty) {
      setState(() => _typed += char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  @override
  Widget build(BuildContext context) {
    final tables = ref.watch(floorTablesProvider);
    final now = widget.now ?? _now;
    final strings = context.strings;

    return Scaffold(
      backgroundColor: context.pos.page,
      body: tables.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.pos.accent),
        ),
        error: (error, _) => Center(child: Text('$error')),
        data: (data) {
          final sections = floorSections(data);
          // A section the manager renamed under us falls back to "All"
          // rather than an empty grid.
          if (_section != null &&
              !sections.any((s) => (s.name ?? '') == _section)) {
            _section = null;
          }
          final visible = _visible(sections);
          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) => _onKey(node, event, data),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, strings, data, now),
                if (sections.length > 1)
                  _sectionTabs(context, strings, sections),
                Expanded(
                  child: data.isEmpty
                      ? _empty(context, strings)
                      : _grid(context, visible, now),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppStrings strings,
    List<DiningTable> tables,
    DateTime now,
  ) {
    final pos = context.pos;
    final free = tables.where((t) => t.state == TableState.free).length;
    final open = tables.where((t) => t.state == TableState.open).length;
    final billed = tables.where((t) => t.state == TableState.billAsked).length;
    final attention = tables
        .where((t) => attentionFor(t, now) != TableAttention.none)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PosSpace.s18,
        PosSpace.xl,
        PosSpace.s18,
        PosSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.pickATable,
                      style: PosText.screenTitle(color: pos.ink),
                    ),
                    const SizedBox(height: PosSpace.xs),
                    Text(
                      _typed.isEmpty
                          ? strings.pickATableHelp
                          : strings.floorJumpHelp,
                      style: PosText.ui(size: 13.5, color: pos.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PosSpace.md),
              if (_typed.isNotEmpty) ...[
                _JumpChip(text: strings.floorJumpHint(_typed)),
                const SizedBox(width: PosSpace.sm),
              ],
              PosButton(
                label: strings.sellWithoutTable,
                border: Border.fromBorderSide(pos.resting),
                onPressed: widget.onSellWithoutTable,
              ),
              const SizedBox(width: PosSpace.sm),
              PosButton(
                label: strings.backToTill,
                border: Border.fromBorderSide(pos.resting),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: PosSpace.md),
          // Legend strip — cells on 1px borders and gaps, width:max-content.
          Container(
            color: pos.lineStrong,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legend(strings.legendFree(free), pos.ok, pos: pos),
                const SizedBox(width: 1),
                _legend(strings.legendOccupied(open), pos.warn, pos: pos),
                const SizedBox(width: 1),
                _legend(strings.legendBillAsked(billed), pos.danger, pos: pos),
                if (attention > 0) ...[
                  const SizedBox(width: 1),
                  _legend(
                    strings.legendNeedsAttention(attention),
                    pos.danger,
                    pos: pos,
                    fill: pos.dangerSoft,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One tab per section, "All" first. Each carries busy/total so the
  /// head waiter sees where the room is full without opening the tab.
  Widget _sectionTabs(
    BuildContext context,
    AppStrings strings,
    List<FloorSection> sections,
  ) {
    final pos = context.pos;
    Widget tab({
      required String label,
      required String count,
      required bool selected,
      required VoidCallback onTap,
    }) => Material(
      color: selected ? pos.ink : pos.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: PosSize.minTouchTarget,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              selected ? BorderSide(color: pos.ink) : pos.resting,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: PosText.ui(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: selected ? pos.onInk : pos.inkWarm,
                ),
              ),
              const SizedBox(width: PosSpace.sm),
              Text(
                count,
                style: PosText.mono(
                  size: 11,
                  color: selected ? pos.onInk : pos.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final total = sections.fold(0, (n, s) => n + s.tables.length);
    final busy = sections.fold(0, (n, s) => n + s.busy);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PosSpace.s18,
        0,
        PosSpace.s18,
        PosSpace.lg,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tab(
              label: strings.floorAllSections,
              count: strings.floorSectionCount(busy, total),
              selected: _section == null,
              onTap: () => setState(() => _section = null),
            ),
            for (final section in sections) ...[
              const SizedBox(width: PosSpace.sm),
              tab(
                label: section.name ?? strings.floorMainRoom,
                count: strings.floorSectionCount(
                  section.busy,
                  section.tables.length,
                ),
                selected: _section == (section.name ?? ''),
                onTap: () => setState(() => _section = section.name ?? ''),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A branch with no tables. Says who makes them, and does not trap the
  /// cashier on a screen with nothing to tap.
  Widget _empty(BuildContext context, AppStrings strings) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.s18),
      child: Text(
        strings.floorHasNoTables,
        textAlign: TextAlign.center,
        style: PosText.ui(size: 14, color: context.pos.muted),
      ),
    ),
  );

  Widget _legend(
    String text,
    Color color, {
    required PosPalette pos,
    Color? fill,
  }) => Container(
    color: fill ?? pos.surface,
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.md,
      vertical: PosSpace.sm,
    ),
    child: Text(text, style: PosText.mono(size: 11, color: color)),
  );

  Widget _grid(BuildContext context, List<DiningTable> tables, DateTime now) =>
      GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          PosSpace.s18,
          0,
          PosSpace.s18,
          PosSpace.s18,
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          mainAxisExtent: PosSize.tableTile,
          crossAxisSpacing: PosSize.tableGridGutter,
          mainAxisSpacing: PosSize.tableGridGutter,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) => TableCard(
          table: tables[index],
          now: now,
          onTap: () => widget.onTablePicked(tables[index]),
        ),
      );
}

class _JumpChip extends StatelessWidget {
  const _JumpChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: PosSize.minTouchTarget,
    padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.pos.accentSoft,
      border: Border.all(color: context.pos.accent, width: 2),
    ),
    child: Text(
      text,
      style: PosText.mono(size: 13, color: context.pos.ink),
    ),
  );
}

/// One table tile. Fill, border and state text are all keyed off [TableState];
/// the attention stripe and the clock line off [attentionFor] and [now].
class TableCard extends StatelessWidget {
  const TableCard({
    super.key,
    required this.table,
    this.now,
    this.onTap,
    this.rules = FloorAttentionRules.defaults,
  });

  final DiningTable table;

  /// The clock the timers are read against. Null reads the system clock —
  /// fine for a one-off tile, but the floor passes its ticking one so every
  /// tile agrees to the second.
  final DateTime? now;
  final VoidCallback? onTap;
  final FloorAttentionRules rules;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final now = this.now ?? DateTime.now();

    // Only the paint is decided here. The badge's words come from the same
    // `TableStateLabel` extension the rest of the app reads, so a new
    // [TableState] cannot reach a tile in one language only.
    final (fill, border, stateColor) = switch (table.state) {
      TableState.free => (
        pos.surface,
        Border.fromBorderSide(pos.resting),
        pos.ok,
      ),
      TableState.open => (
        pos.accentSoft,
        Border.all(color: pos.accent, width: 2),
        pos.warn,
      ),
      TableState.billAsked => (
        pos.dangerSoft,
        Border.all(color: pos.danger, width: 2),
        pos.danger,
      ),
    };

    final attention = attentionFor(table, now, rules: rules);
    final seated = table.seatedFor(now);
    final quiet = table.quietFor(now);

    // The bottom line: what needs doing, else the plain state badge.
    final (footer, footerColor) = switch (attention) {
      TableAttention.unsentRound => (strings.tableUnsentRound, pos.danger),
      TableAttention.quiet => (
        strings.tableQuietFor(_elapsed(strings, quiet!)),
        pos.warn,
      ),
      TableAttention.billWaiting => (
        strings.tableBillWaitingFor(_elapsed(strings, quiet!)),
        pos.danger,
      ),
      TableAttention.none => (
        table.state.badge(strings, openLines: table.openLineCount),
        stateColor,
      ),
    };

    final subtitle = switch (table.state) {
      TableState.free => strings.tableSeats(table.seats),
      TableState.open => strings.tableOpenWith(
        table.openTotal?.format(withCurrency: true) ?? '',
      ),
      TableState.billAsked => strings.tableBillRequested(
        table.openTotal?.format(withCurrency: true) ?? '',
      ),
    };

    return Material(
      color: fill,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: border),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The attention stripe: a 4px bar down the start edge. Visible
              // from across the room, which is the point — a waiter reads the
              // floor from the pass, not with their nose on the screen.
              if (attention != TableAttention.none)
                Container(width: 4, color: footerColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(PosSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              table.label,
                              overflow: TextOverflow.ellipsis,
                              style: PosText.ui(
                                size: 20,
                                weight: FontWeight.w800,
                                color: pos.ink,
                              ),
                            ),
                          ),
                          if (seated != null)
                            Text(
                              _elapsed(strings, seated),
                              style: PosText.mono(size: 12, color: pos.muted),
                            ),
                        ],
                      ),
                      const SizedBox(height: PosSpace.xs),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: PosText.ui(size: 12, color: pos.muted),
                      ),
                      if (table.guestCount case final guests?
                          when !table.isFree)
                        Text(
                          strings.tableGuests(guests),
                          overflow: TextOverflow.ellipsis,
                          style: PosText.ui(size: 11, color: pos.muted),
                        ),
                      const Spacer(),
                      Text(
                        footer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PosText.mono(size: 11, color: footerColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `4m`, `1h 12m`. Never seconds — a floor that counts seconds looks
  /// nervous, and nobody acts on them.
  static String _elapsed(AppStrings strings, Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 60) return strings.elapsedMinutes(minutes);
    return strings.elapsedHours(minutes ~/ 60, minutes % 60);
  }
}
