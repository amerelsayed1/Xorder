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
import 'admin_messages.dart';

/// The tables a waiter can seat somebody at.
///
/// **Offline only**, like the Menu and Money panes: on a cloud till the
/// platform authors the floor and the bootstrap seeder replaces it wholesale.
///
/// Until now the only way to add a table was `bin/pos_migrate.dart
/// --seed-catalogue`, which lays out eight demo tables, or hand-written SQL.
/// A restaurant that put two more tables on the terrace had no way to say so.
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
  Future<void> _write(
    Future<AdminResult<DiningTable>> Function() action,
  ) async {
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
  ) async {
    final edited = await showDialog<DiningTable>(
      context: context,
      builder: (context) => _TableDialog(table: existing),
    );
    if (edited == null) return;
    await _write(() => repository.saveTable(edited, by: widget.admin));
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
      data: (floor) => Column(
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
                  onPressed: () => _edit(repository, null),
                ),
              ],
            ),
          ),
          Expanded(
            child: floor.isEmpty
                ? _Centred(text: strings.noTablesYet)
                : ListView(
                    children: [
                      for (final table in floor)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: PosSpace.xl,
                            vertical: PosSpace.md,
                          ),
                          decoration: BoxDecoration(
                            border: Border(bottom: context.pos.hairline),
                          ),
                          child: Row(
                            children: [
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
                                style: PosText.mono(
                                  size: 13,
                                  color: context.pos.muted,
                                ),
                              ),
                              if (table.areaName != null) ...[
                                const SizedBox(width: PosSpace.lg),
                                Text(
                                  table.areaName!,
                                  style: PosText.ui(
                                    size: 13,
                                    color: context.pos.muted,
                                  ),
                                ),
                              ],
                              const SizedBox(width: PosSpace.lg),
                              PosButton(
                                label: strings.takeOutOfService,
                                border: Border.fromBorderSide(
                                  context.pos.resting,
                                ),
                                onPressed: () => _write(
                                  () => repository.archiveTable(
                                    table,
                                    by: widget.admin,
                                  ),
                                ),
                              ),
                              const SizedBox(width: PosSpace.sm),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                onPressed: () => _edit(repository, table),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TableDialog extends StatefulWidget {
  const _TableDialog({this.table});

  final DiningTable? table;

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

    return Dialog(
      backgroundColor: context.pos.surface,
      shape: RoundedRectangleBorder(side: context.pos.emphasis),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.addTable, style: PosText.panelTitle(color: context.pos.ink)),
              const SizedBox(height: PosSpace.lg),
              _Box(controller: _label, label: strings.tableLabel, mono: true),
              const SizedBox(height: PosSpace.md),
              _Box(
                controller: _seats,
                label: strings.tableSeatsLabel,
                mono: true,
              ),
              const SizedBox(height: PosSpace.md),
              _Box(controller: _area, label: strings.tableArea),
              const SizedBox(height: PosSpace.xl),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(context.pos.resting),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: PosButton(
                      label: strings.save,
                      background: context.pos.ink,
                      foreground: context.pos.onInk,
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
                              : _area.text,
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
  });

  final TextEditingController controller;
  final String label;
  final bool mono;

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
