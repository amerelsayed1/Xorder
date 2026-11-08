import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/dining_table.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/services/floor_overlay.dart';
import 'admin_messages.dart';

/// The tables a waiter can seat somebody at.
///
/// **Offline only**, like the Menu and Money panes: on a cloud till the
/// platform authors the floor and the bootstrap seeder replaces it wholesale.
///
/// Laid out the way the floor screen shows it: grouped by section, in
/// `sort_order`. Move up / move down change that order and it is the order
/// the cashier sees — the pane *is* the floor plan, not a list about it.
///
/// Nothing deletes. A table goes out of service, because parked tickets and
/// past orders name its row.
class ManagementFloorPane extends ConsumerStatefulWidget {
  const ManagementFloorPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementFloorPane> createState() =>
      _ManagementFloorPaneState();
}

class _ManagementFloorPaneState extends ConsumerState<ManagementFloorPane> {
  Future<void> _write<T>(Future<AdminResult<T>> Function() action) async {
    final result = await action();
    if (!mounted) return;

    final refusal = result.refusal;
    if (refusal != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminText.refusal(context.strings, refusal))),
      );
      return;
    }
    // The floor screen reads this. Without the invalidation a table added
    // here would not appear until the app restarted.
    ref.invalidate(tablesProvider);
  }

  Future<void> _edit(
    CatalogAdminRepository repository,
    DiningTable? existing,
    List<String> sections,
  ) async {
    final edited = await showDialog<DiningTable>(
      context: context,
      builder: (context) => _TableDialog(table: existing, sections: sections),
    );
    if (edited == null) return;
    await _write(() => repository.saveTable(edited, by: widget.admin));
  }

  /// Swap [table] with its neighbour inside its section, then write the whole
  /// floor's order back in one call.
  ///
  /// The whole floor rather than the two that swapped: the repository numbers
  /// what it is given 1..n, so handing it one section would collapse that
  /// section onto the same numbers as the others and interleave them.
  Future<void> _nudge(
    CatalogAdminRepository repository,
    List<FloorSection> sections,
    DiningTable table, {
    required int by,
  }) async {
    final order = <int>[];
    for (final section in sections) {
      final ids = [for (final t in section.tables) t.id];
      final at = ids.indexOf(table.id);
      final to = at + by;
      if (at >= 0 && to >= 0 && to < ids.length) {
        ids[at] = ids[to];
        ids[to] = table.id;
      }
      order.addAll(ids);
    }
    await _write(() => repository.reorderTables(order, by: widget.admin));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final repository = ref.watch(catalogAdminRepositoryProvider);
    if (repository == null) {
      return _Centred(text: strings.floorComesFromPlatform);
    }

    final tables = ref.watch(tablesProvider);

    return tables.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => _Centred(text: '$error'),
      data: (floor) {
        final sections = floorSections(floor);
        final sectionNames = [
          for (final s in sections)
            if (s.name != null) s.name!,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(PosSpace.xl),
              decoration: BoxDecoration(
                border: Border(bottom: context.pos.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.tableSummary(floor.length),
                      style: PosText.ui(size: 13, color: context.pos.muted),
                    ),
                  ),
                  PosButton(
                    label: strings.addTable,
                    background: context.pos.ink,
                    foreground: context.pos.onInk,
                    onPressed: () => _edit(repository, null, sectionNames),
                  ),
                ],
              ),
            ),
            Expanded(
              child: floor.isEmpty
                  ? _Centred(text: strings.noTablesYet)
                  : ListView(
                      children: [
                        for (final section in sections) ...[
                          Container(
                            padding: const EdgeInsets.fromLTRB(
                              PosSpace.xl,
                              PosSpace.lg,
                              PosSpace.xl,
                              PosSpace.sm,
                            ),
                            child: Row(
                              children: [
                                MicroLabel(
                                  section.name ?? strings.floorMainRoom,
                                ),
                                const SizedBox(width: PosSpace.sm),
                                Text(
                                  '${section.tables.length}',
                                  style: PosText.mono(
                                    size: 11,
                                    color: context.pos.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (var i = 0; i < section.tables.length; i++)
                            _row(
                              context,
                              strings,
                              repository,
                              sections,
                              sectionNames,
                              section.tables[i],
                              first: i == 0,
                              last: i == section.tables.length - 1,
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    AppStrings strings,
    CatalogAdminRepository repository,
    List<FloorSection> sections,
    List<String> sectionNames,
    DiningTable table, {
    required bool first,
    required bool last,
  }) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.xl,
      vertical: PosSpace.sm,
    ),
    decoration: BoxDecoration(border: Border(bottom: context.pos.hairline)),
    child: Row(
      children: [
        // Up/down rather than drag: a mouse drag on a 44px row is fiddly on
        // the touch screens these tills run on, and the manager moves a
        // table one place at a time anyway.
        IconButton(
          tooltip: strings.moveUp,
          icon: const Icon(Icons.keyboard_arrow_up, size: 18),
          onPressed: first
              ? null
              : () => _nudge(repository, sections, table, by: -1),
        ),
        IconButton(
          tooltip: strings.moveDown,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          onPressed: last
              ? null
              : () => _nudge(repository, sections, table, by: 1),
        ),
        const SizedBox(width: PosSpace.sm),
        Expanded(
          child: Text(
            table.label,
            style: PosText.ui(
              size: 14,
              weight: FontWeight.w600,
              color: context.pos.ink,
            ),
          ),
        ),
        Text(
          strings.tableSeats(table.seats),
          style: PosText.mono(size: 13, color: context.pos.muted),
        ),
        const SizedBox(width: PosSpace.lg),
        PosButton(
          label: strings.takeOutOfService,
          border: Border.fromBorderSide(context.pos.resting),
          onPressed: () => _write(
            () => repository.archiveTable(table, by: widget.admin),
          ),
        ),
        const SizedBox(width: PosSpace.sm),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 16),
          onPressed: () => _edit(repository, table, sectionNames),
        ),
      ],
    ),
  );
}

class _TableDialog extends StatefulWidget {
  const _TableDialog({this.table, required this.sections});

  final DiningTable? table;

  /// Sections that already exist, offered as one-tap chips so "Terrace" and
  /// "terrace " do not become two tabs on the floor.
  final List<String> sections;

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  late final _label = TextEditingController(text: widget.table?.label ?? '');
  late final _seats = TextEditingController(
    text: '${widget.table?.seats ?? 2}',
  );
  late final _area = TextEditingController(text: widget.table?.areaName ?? '');

  @override
  void dispose() {
    _label.dispose();
    _seats.dispose();
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;

    return Dialog(
      backgroundColor: pos.surface,
      shape: RoundedRectangleBorder(side: pos.emphasis),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.addTable, style: PosText.panelTitle(color: pos.ink)),
              const SizedBox(height: PosSpace.lg),
              _Box(controller: _label, label: strings.tableLabel, mono: true),
              const SizedBox(height: PosSpace.md),
              _Box(
                controller: _seats,
                label: strings.tableSeatsLabel,
                mono: true,
              ),
              const SizedBox(height: PosSpace.md),
              _Box(
                controller: _area,
                label: strings.tableSection,
                help: strings.tableSectionHelp,
              ),
              if (widget.sections.isNotEmpty) ...[
                const SizedBox(height: PosSpace.sm),
                Wrap(
                  spacing: PosSpace.sm,
                  runSpacing: PosSpace.sm,
                  children: [
                    for (final name in widget.sections)
                      PosButton(
                        label: name,
                        height: 32,
                        fontSize: 12,
                        border: Border.fromBorderSide(pos.resting),
                        onPressed: () => setState(() => _area.text = name),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: PosSpace.xl),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(pos.resting),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: PosButton(
                      label: strings.save,
                      background: pos.ink,
                      foreground: pos.onInk,
                      onPressed: () => Navigator.of(context).pop(
                        DiningTable(
                          id: widget.table?.id ?? 0,
                          label: _label.text,
                          // A non-number reads as zero, which the repository
                          // refuses with "a table seats at least one person" —
                          // one rule, stated in one place.
                          seats: int.tryParse(_seats.text.trim()) ?? 0,
                          areaName: _area.text.trim().isEmpty
                              ? null
                              : _area.text.trim(),
                          sortOrder: widget.table?.sortOrder ?? 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.controller,
    required this.label,
    this.mono = false,
    this.help,
  });

  final TextEditingController controller;
  final String label;
  final bool mono;
  final String? help;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(label),
      const SizedBox(height: PosSpace.sm),
      TextField(
        controller: controller,
        style: mono
            ? PosText.mono(size: 14, color: context.pos.ink)
            : PosText.ui(size: 14, color: context.pos.ink),
      ),
      if (help case final text?) ...[
        const SizedBox(height: PosSpace.xs),
        Text(text, style: PosText.ui(size: 11.5, color: context.pos.muted)),
      ],
    ],
  );
}

class _Centred extends StatelessWidget {
  const _Centred({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: PosText.ui(size: 13, color: context.pos.muted),
      ),
    ),
  );
}
