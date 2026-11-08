import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/table_batch.dart';
import 'package:xorder_pos/features/admin_mode/admin_messages.dart';

/// The tables a waiter can seat somebody at.
///
/// **Offline only**, like the Menu and Money panes: on a cloud till the
/// platform authors the floor and the bootstrap seeder replaces it wholesale.
///
/// Until now the only way to add a table was `bin/pos_migrate.dart
/// --seed-catalogue`, which lays out eight demo tables, or hand-written SQL.
/// A business that put two more tables on the terrace had no way to say so.
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

  /// "Add several" (XORD-006). The dialog does the saving itself and stays
  /// open on a refusal, so the numbers just typed are not lost to a clash.
  Future<void> _addSeveral(
    CatalogAdminRepository repository,
    List<DiningTable> floor,
  ) async {
    final strings = context.strings;
    final created = await showDialog<int>(
      context: context,
      builder: (context) => _BulkTablesDialog(
        existing: {for (final table in floor) table.label},
        onCreate: (tables) async {
          final result = await repository.createTables(
            tables,
            by: widget.admin,
          );
          if (result.succeeded) ref.invalidate(tablesProvider);
          return result.refusal;
        },
      ),
    );
    if (created == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.bulkTablesCreated(created))));
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
                  key: const Key('add-several-tables'),
                  label: strings.addSeveralTables,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: () => _addSeveral(repository, floor),
                ),
                const SizedBox(width: PosSpace.sm),
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
                              if (table.seats case final seats?)
                                Text(
                                  strings.tableSeats(seats),
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
  // Blank for a new table: seats are optional, and a prefilled 2 would state
  // a size nobody chose.
  late final _seats = TextEditingController(
    text: widget.table?.seats?.toString() ?? '',
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
                          // Blank is "not stated" (null). A non-number reads
                          // as zero, which the repository refuses with "a table
                          // seats at least one person" — one rule, stated in
                          // one place.
                          seats: _seatsFrom(_seats.text),
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

/// Add `Table 1` … `Table 10` in one go: a name, a first number, how many,
/// seats and an area, with the result shown before anything is saved.
///
/// **All or nothing, and said before it is tried.** The preview names the
/// first and last table and lists any name the branch already has, and Add is
/// off until there is none; the repository checks the same again inside its
/// transaction. **One press only**: the button is off from the first tap until
/// the answer, so a double click cannot send the batch twice.
class _BulkTablesDialog extends StatefulWidget {
  const _BulkTablesDialog({required this.existing, required this.onCreate});

  final Set<String> existing;
  final Future<AdminRefusal?> Function(List<DiningTable> tables) onCreate;

  @override
  State<_BulkTablesDialog> createState() => _BulkTablesDialogState();
}

class _BulkTablesDialogState extends State<_BulkTablesDialog> {
  TextEditingController? _prefix;
  final _start = TextEditingController(text: '1');
  final _quantity = TextEditingController(text: '10');
  final _seats = TextEditingController();
  final _area = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The default name is in the till's language, and is only chosen once.
    _prefix ??= TextEditingController(
      text: context.strings.bulkTableDefaultPrefix,
    );
  }

  @override
  void dispose() {
    _prefix?.dispose();
    _start.dispose();
    _quantity.dispose();
    _seats.dispose();
    _area.dispose();
    super.dispose();
  }

  TableBatchPlan get _plan => TableBatch.plan(
    prefix: _prefix!.text,
    start: int.tryParse(_start.text.trim()),
    quantity: int.tryParse(_quantity.text.trim()),
    seats: _seatsFrom(_seats.text),
    existing: widget.existing,
  );

  Future<void> _create(TableBatchPlan plan) async {
    if (_busy || !plan.canCreate) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final seats = _seatsFrom(_seats.text);
    final area = _area.text.trim().isEmpty ? null : _area.text.trim();
    final refusal = await widget.onCreate([
      for (final label in plan.labels)
        DiningTable(id: 0, label: label, seats: seats, areaName: area),
    ]);
    if (!mounted) return;
    if (refusal == null) {
      Navigator.of(context).pop(plan.labels.length);
      return;
    }
    setState(() {
      _busy = false;
      _error = AdminText.refusal(context.strings, refusal);
    });
  }

  String? _problem(AppStrings strings, TableBatchPlan plan) =>
      switch (plan.problem) {
        TableBatchProblem.quantity => strings.bulkTableQuantityInvalid(
          TableBatch.maxQuantity,
        ),
        TableBatchProblem.start => strings.bulkTableStartInvalid,
        TableBatchProblem.seats => strings.bulkTableSeatsInvalid,
        TableBatchProblem.prefix => strings.bulkTablePrefixInvalid,
        null when plan.clashes.isNotEmpty => strings.bulkTableClashes(
          plan.clashes.take(5).map((n) => '"$n"').join(', ') +
              (plan.clashes.length > 5 ? ' …' : ''),
        ),
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final plan = _plan;
    final problem = _problem(strings, plan);

    return Dialog(
      backgroundColor: context.pos.surface,
      shape: RoundedRectangleBorder(side: context.pos.emphasis),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.bulkTablesTitle,
                style: PosText.panelTitle(color: context.pos.ink),
              ),
              const SizedBox(height: PosSpace.lg),
              _Box(
                key: const Key('bulk-prefix'),
                controller: _prefix!,
                label: strings.bulkTablePrefix,
                onChanged: () => setState(() => _error = null),
              ),
              const SizedBox(height: PosSpace.md),
              Row(
                children: [
                  Expanded(
                    child: _Box(
                      key: const Key('bulk-start'),
                      controller: _start,
                      label: strings.bulkTableStart,
                      mono: true,
                      onChanged: () => setState(() => _error = null),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: _Box(
                      key: const Key('bulk-quantity'),
                      controller: _quantity,
                      label: strings.bulkTableQuantity,
                      mono: true,
                      onChanged: () => setState(() => _error = null),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: _Box(
                      key: const Key('bulk-seats'),
                      controller: _seats,
                      label: strings.tableSeatsLabel,
                      mono: true,
                      onChanged: () => setState(() => _error = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PosSpace.md),
              _Box(
                key: const Key('bulk-area'),
                controller: _area,
                label: strings.tableArea,
              ),
              const SizedBox(height: PosSpace.lg),
              if (plan.labels.isNotEmpty)
                Text(
                  strings.bulkTablePreview(
                    plan.labels.first,
                    plan.labels.last,
                    plan.labels.length,
                  ),
                  key: const Key('bulk-preview'),
                  style: PosText.ui(size: 13, color: context.pos.ink),
                ),
              if (problem != null || _error != null) ...[
                const SizedBox(height: PosSpace.sm),
                Text(
                  _error ?? problem!,
                  key: const Key('bulk-problem'),
                  style: PosText.ui(size: 12.5, color: context.pos.danger),
                ),
              ],
              const SizedBox(height: PosSpace.xl),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(context.pos.resting),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: PosButton(
                      key: const Key('bulk-create'),
                      label: plan.labels.isEmpty
                          ? strings.save
                          : strings.bulkTablesCreate(plan.labels.length),
                      background: context.pos.ink,
                      foreground: context.pos.onInk,
                      onPressed: plan.canCreate && !_busy
                          ? () => _create(plan)
                          : null,
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
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool mono;

  /// Told after every edit, for a form that shows a preview of what was typed.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(label),
      const SizedBox(height: PosSpace.sm),
      TextField(
        controller: controller,
        onChanged: onChanged == null ? null : (_) => onChanged!(),
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

/// What the Seats box says: blank is "not stated" (null), a number is that
/// number, and anything else is 0, which the planner and the repository both
/// refuse as "a table seats at least one person".
int? _seatsFrom(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed) ?? 0;
}
