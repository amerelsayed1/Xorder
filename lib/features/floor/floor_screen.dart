import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/labels.dart';
import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../domain/models/dining_table.dart';

/// Floor — the dine-in landing screen. Pick a table before selling.
///
/// Non-dine-in modes skip this screen entirely.
class FloorScreen extends ConsumerWidget {
  const FloorScreen({super.key, required this.onTablePicked});

  final void Function(DiningTable table) onTablePicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(floorTablesProvider);
    final strings = context.strings;

    return Scaffold(
      backgroundColor: context.pos.page,
      body: tables.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.pos.accent),
        ),
        error: (error, _) => Center(child: Text('$error')),
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(strings, data, pos: context.pos),
            Expanded(child: _grid(context, data)),
          ],
        ),
      ),
    );
  }

  Widget _header(AppStrings strings, List<DiningTable> tables, {required PosPalette pos}) {
    final free = tables.where((t) => t.state == TableState.free).length;
    final open = tables.where((t) => t.state == TableState.open).length;
    final billed = tables.where((t) => t.state == TableState.billAsked).length;

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
          Text(strings.pickATable, style: PosText.screenTitle(color: pos.ink)),
          const SizedBox(height: PosSpace.xs),
          Text(
            strings.pickATableHelp,
            style: PosText.ui(size: 13.5, color: pos.muted),
          ),
          const SizedBox(height: PosSpace.md),
          // Legend strip — three cells on 1px borders and gaps, width:max-content.
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(String text, Color color, {required PosPalette pos}) => Container(
    color: pos.surface,
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.md,
      vertical: PosSpace.sm,
    ),
    child: Text(text, style: PosText.mono(size: 11, color: color)),
  );

  Widget _grid(BuildContext context, List<DiningTable> tables) =>
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
          onTap: () => onTablePicked(tables[index]),
        ),
      );
}

/// One table tile. Fill, border and state text are all keyed off [TableState].
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.table, this.onTap});

  final DiningTable table;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    // Only the paint is decided here. The badge's words come from the same
    // `TableStateLabel` extension the rest of the app reads, so a new
    // [TableState] cannot reach a tile in one language only.
    final (fill, border, stateColor) = switch (table.state) {
      TableState.free => (
        context.pos.surface,
        Border.fromBorderSide(context.pos.resting),
        context.pos.ok,
      ),
      TableState.open => (
        context.pos.accentSoft,
        Border.all(color: context.pos.accent, width: 2),
        context.pos.warn,
      ),
      TableState.billAsked => (
        context.pos.dangerSoft,
        Border.all(color: context.pos.danger, width: 2),
        context.pos.danger,
      ),
    };

    final stateText = table.state.badge(
      strings,
      openLines: table.openLineCount,
    );

    final subtitle = switch (table.state) {
      TableState.free => strings.tableSeats(table.seats),
      TableState.open => strings.tableOpenWith(table.openTotal?.format() ?? ''),
      TableState.billAsked => strings.tableBillRequested(
        table.openTotal?.format() ?? '',
      ),
    };

    return Material(
      color: fill,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(PosSpace.md),
          decoration: BoxDecoration(border: border),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                table.label,
                style: PosText.ui(
                  size: 20,
                  weight: FontWeight.w800,
                  color: context.pos.ink,
                ),
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(size: 12, color: context.pos.muted),
              ),
              const Spacer(),
              Text(
                stateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PosText.mono(size: 11, color: stateColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
