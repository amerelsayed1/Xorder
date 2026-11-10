import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/mono_amount.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/domain/models/pos_unit.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/features/admin_mode/admin_messages.dart';
import 'admin_pane_bits.dart';
import 'unit_dialog.dart';

/// The units stock is counted and bought in.
///
/// Seven come with every business — each, kg, g, litre, ml, box, pack — and
/// the rest are the business's own: a sack of rice, a tray of thirty eggs.
/// Retired rather than deleted, because a purchase order from last month still
/// names the unit it was written in.
class ManagementUnitsPane extends ConsumerStatefulWidget {
  const ManagementUnitsPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementUnitsPane> createState() =>
      _ManagementUnitsPaneState();
}

class _ManagementUnitsPaneState extends ConsumerState<ManagementUnitsPane> {
  bool _busy = false;
  String? _note;

  Future<void> _edit(PosUnit? unit) async {
    final edited = await UnitDialog.show(
      context,
      unit: unit,
      languages: ref.read(contentLanguagesNowProvider),
    );
    if (edited == null || !mounted) return;

    setState(() => _busy = true);
    final result = await ref
        .read(unitsRepositoryProvider)
        .save(edited, by: widget.admin);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _note = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });
    if (result.succeeded) {
      ref
        ..invalidate(unitsProvider)
        ..invalidate(unitsAllProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneUnits, hint: strings.paneUnitsBlurb),
        ...ref
            .watch(unitsAllProvider)
            .when(
              loading: () => const [SizedBox(height: 40)],
              error: (error, _) => [
                Text(
                  '$error',
                  style: PosText.ui(size: 13, color: context.pos.danger),
                ),
              ],
              data: (units) => [
                for (final unit in units)
                  _UnitRow(unit: unit, onEdit: () => _edit(unit)),
              ],
            ),
        if (_note != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(_note!, style: PosText.ui(size: 12.5, color: context.pos.danger)),
        ],
        const SizedBox(height: PosSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PosButton(
            key: const Key('unit-new'),
            label: strings.unitNew,
            border: Border.fromBorderSide(context.pos.resting),
            onPressed: _busy ? null : () => _edit(null),
          ),
        ),
      ],
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit, required this.onEdit});

  final PosUnit unit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return InkWell(
      key: Key('unit-row-${unit.code}'),
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
        decoration: BoxDecoration(
          border: BorderDirectional(bottom: palette.hairline),
        ),
        child: Opacity(
          // Retired units stay listed, greyed: the way to bring one back.
          opacity: unit.isActive ? 1 : 0.5,
          child: Row(
            children: [
              SizedBox(width: 90, child: MonoCode(unit.code)),
              Expanded(
                child: Text(
                  unit.displayName(strings.languageCode),
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
              ),
              if (!unit.isActive)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  child: Text(
                    strings.unitRetired,
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ),
              if (unit.allowsFraction)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: PosSpace.sm,
                    vertical: 2,
                  ),
                  color: palette.okSoft,
                  child: Text(
                    strings.unitFractionChip,
                    style: PosText.ui(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: palette.ok,
                    ),
                  ),
                ),
              MonoCode(unit.etaUnitType),
            ],
          ),
        ),
      ),
    );
  }
}
