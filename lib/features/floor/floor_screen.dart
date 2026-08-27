import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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
    final tables = ref.watch(tablesProvider);

    return Scaffold(
      backgroundColor: PosColors.page,
      body: tables.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: PosColors.accent),
        ),
        error: (error, _) => Center(child: Text('$error')),
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(data),
            Expanded(child: _grid(context, data)),
          ],
        ),
      ),
    );
  }

  Widget _header(List<DiningTable> tables) {
    final free = tables.where((t) => t.state == TableState.free).length;
    final open = tables.where((t) => t.state == TableState.open).length;
    final billed = tables.where((t) => t.state == TableState.billAsked).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(PosSpace.s18, PosSpace.xl, PosSpace.s18, PosSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pick a table', style: PosText.screenTitle()),
          const SizedBox(height: PosSpace.xs),
          Text(
            'Tap a table to open a new bill or add to an existing one.',
            style: PosText.ui(size: 13.5, color: PosColors.muted),
          ),
          const SizedBox(height: PosSpace.md),
          // Legend strip — three cells on 1px borders and gaps, width:max-content.
          Container(
            color: PosColors.lineStrong,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legend('FREE $free', PosColors.ok),
                const SizedBox(width: 1),
                _legend('OCCUPIED $open', PosColors.warn),
                const SizedBox(width: 1),
                _legend('BILL ASKED $billed', PosColors.danger),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(String text, Color color) => Container(
        color: PosColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.md, vertical: PosSpace.sm),
        child: Text(text, style: PosText.mono(size: 11, color: color)),
      );

  Widget _grid(BuildContext context, List<DiningTable> tables) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(PosSpace.s18, 0, PosSpace.s18, PosSpace.s18),
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
    final (fill, border, stateText, stateColor) = switch (table.state) {
      TableState.free => (
          PosColors.surface,
          const Border.fromBorderSide(PosBorders.resting),
          'FREE',
          PosColors.ok,
        ),
      TableState.open => (
          PosColors.accentSoft,
          Border.all(color: PosColors.accent, width: 2),
          '${table.openLineCount} LINES',
          PosColors.warn,
        ),
      TableState.billAsked => (
          PosColors.dangerSoft,
          Border.all(color: PosColors.danger, width: 2),
          'BILL ASKED',
          PosColors.danger,
        ),
    };

    final subtitle = switch (table.state) {
      TableState.free => '${table.seats} seats',
      TableState.open => 'Open · ${table.openTotal?.format() ?? ''}',
      TableState.billAsked => 'Bill requested · ${table.openTotal?.format() ?? ''}',
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
                style: PosText.ui(size: 20, weight: FontWeight.w800, color: PosColors.ink),
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(size: 12, color: PosColors.muted),
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
