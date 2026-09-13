import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/service_charge.dart';
import '../../../domain/models/ticket.dart';
import '../../../app/labels.dart';

/// Authoring one service charge (§38).
///
/// **A percentage or an amount, chosen before either is typed.** Two boxes
/// side by side would invite somebody to fill in both, and "12% or 20 EGP,
/// whichever" is a question nobody has answered — so the choice comes first
/// and only one box exists at a time.
class ServiceChargeDialog extends StatefulWidget {
  const ServiceChargeDialog({super.key, this.charge});

  final ServiceCharge? charge;

  static Future<ServiceCharge?> show(
    BuildContext context, {
    ServiceCharge? charge,
  }) => showDialog<ServiceCharge>(
    context: context,
    builder: (_) => ServiceChargeDialog(charge: charge),
  );

  @override
  State<ServiceChargeDialog> createState() => _ServiceChargeDialogState();
}

class _ServiceChargeDialogState extends State<ServiceChargeDialog> {
  late final _nameEn = TextEditingController(text: widget.charge?.nameEn ?? '');
  late final _nameAr = TextEditingController(
    text: widget.charge?.nameAr ?? '',
  );
  late final _amount = TextEditingController(
    text: widget.charge == null
        ? ''
        : (widget.charge!.isFixed
              ? _major(widget.charge!.fixedMinor!)
              : _percent(widget.charge!.rateBp!)),
  );

  late bool _isFixed = widget.charge?.isFixed ?? false;
  late final Set<OrderType> _orderTypes = {...?widget.charge?.orderTypes};
  late bool _isTaxable = widget.charge?.isTaxable ?? true;
  late bool _isAutomatic = widget.charge?.isAutomatic ?? true;
  late bool _isOptional = widget.charge?.isOptional ?? false;
  late bool _isActive = widget.charge?.isActive ?? true;

  bool get _isNew => widget.charge == null;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    _amount.dispose();
    super.dispose();
  }

  static String _percent(int bp) {
    final value = bp / 100;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  static String _major(int minor) => (minor / 100).toStringAsFixed(2);

  void _save() {
    final typed = double.tryParse(_amount.text.trim()) ?? 0;
    Navigator.of(context).pop(
      ServiceCharge(
        id: widget.charge?.id ?? 0,
        nameEn: _nameEn.text.trim(),
        nameAr: _nameAr.text.trim().isEmpty ? null : _nameAr.text.trim(),
        // Exactly one of the two, always. Both set is the state the model,
        // the repository and a CHECK constraint all refuse, so the dialog
        // cannot produce it in the first place.
        rateBp: _isFixed ? null : (typed * 100).round(),
        fixedMinor: _isFixed ? (typed * 100).round() : null,
        orderTypes: _orderTypes,
        isTaxable: _isTaxable,
        isAutomatic: _isAutomatic,
        isOptional: _isOptional,
        isActive: _isActive,
        sortOrder: widget.charge?.sortOrder ?? 99,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isNew ? strings.chargeNew : strings.chargeEdit,
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: PosSpace.lg),

              _Field(label: strings.chargeName, controller: _nameEn),
              _Field(
                label: strings.tenderNameAr,
                controller: _nameAr,
                optional: true,
              ),

              MicroLabel(strings.chargeHow),
              const SizedBox(height: PosSpace.xs),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.chargePercentage,
                      background: _isFixed ? Colors.transparent : palette.ink,
                      foreground: _isFixed ? null : Colors.white,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => setState(() => _isFixed = false),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      label: strings.chargeFixed,
                      background: _isFixed ? palette.ink : Colors.transparent,
                      foreground: _isFixed ? Colors.white : null,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => setState(() => _isFixed = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PosSpace.md),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      key: const Key('charge-amount'),
                      controller: _amount,
                      textDirection: TextDirection.ltr,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: PosText.mono(size: 15, color: palette.ink),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Text(
                    _isFixed ? strings.currencyEgp : '%',
                    style: PosText.mono(size: 15, color: palette.muted),
                  ),
                ],
              ),

              const SizedBox(height: PosSpace.lg),
              MicroLabel(strings.chargeAppliesTo),
              const SizedBox(height: PosSpace.xs),
              Text(
                // Said out loud, because an empty selection reads as "none" to
                // everybody and means the opposite.
                strings.chargeAppliesToHint,
                style: PosText.ui(size: 11.5, color: palette.muted),
              ),
              const SizedBox(height: PosSpace.sm),
              Wrap(
                spacing: PosSpace.sm,
                runSpacing: PosSpace.sm,
                children: [
                  for (final type in OrderType.values)
                    PosButton(
                      label: type.label(strings),
                      background: _orderTypes.contains(type)
                          ? palette.ink
                          : Colors.transparent,
                      foreground: _orderTypes.contains(type)
                          ? Colors.white
                          : null,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => setState(() {
                        _orderTypes.contains(type)
                            ? _orderTypes.remove(type)
                            : _orderTypes.add(type);
                      }),
                    ),
                ],
              ),

              const SizedBox(height: PosSpace.lg),
              _Switch(
                label: strings.chargeTaxable,
                hint: strings.chargeTaxableHint,
                value: _isTaxable,
                onChanged: (v) => setState(() => _isTaxable = v),
              ),
              _Switch(
                label: strings.chargeAutomatic,
                value: _isAutomatic,
                onChanged: (v) => setState(() => _isAutomatic = v),
              ),
              _Switch(
                label: strings.chargeOptional,
                hint: strings.chargeOptionalHint,
                value: _isOptional,
                onChanged: (v) => setState(() => _isOptional = v),
              ),
              if (!_isNew)
                _Switch(
                  label: strings.chargeActive,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),

              const SizedBox(height: PosSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      key: const Key('charge-save'),
                      label: strings.save,
                      background: palette.ink,
                      foreground: palette.onInk,
                      onPressed: _save,
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.optional = false,
  });

  final String label;
  final TextEditingController controller;
  final bool optional;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PosSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(optional ? context.strings.optionalField(label) : label),
        const SizedBox(height: PosSpace.xs),
        TextField(
          controller: controller,
          style: PosText.ui(size: 15, color: context.pos.ink),
        ),
      ],
    ),
  );
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    value: value,
    onChanged: onChanged,
    contentPadding: EdgeInsets.zero,
    title: Text(
      label,
      style: PosText.ui(size: 13.5, color: context.pos.body),
    ),
    subtitle: hint == null
        ? null
        : Text(
            hint!,
            style: PosText.ui(size: 11.5, color: context.pos.muted),
          ),
  );
}
