import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/supplier.dart';

/// Recording who the restaurant buys from.
///
/// **One required field.** A delivery arrives at seven in the morning and
/// somebody has to write down who brought it; everything else can be filled in
/// later with the invoice in hand, and a form that demanded a tax number would
/// be a form that gets skipped and a delivery that goes unrecorded.
class SupplierDialog extends StatefulWidget {
  const SupplierDialog({super.key, this.supplier});

  final Supplier? supplier;

  static Future<Supplier?> show(BuildContext context, {Supplier? supplier}) =>
      showDialog<Supplier>(
        context: context,
        builder: (_) => SupplierDialog(supplier: supplier),
      );

  @override
  State<SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<SupplierDialog> {
  final _controllers = <String, TextEditingController>{};
  late bool _isActive = widget.supplier?.isActive ?? true;
  String? _problem;

  TextEditingController _box(String key, String? initial) =>
      _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: initial ?? ''),
      );

  String? _text(String key) {
    final value = _controllers[key]?.text.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final supplier = Supplier(
      id: widget.supplier?.id ?? 0,
      nameEn: _text('name') ?? '',
      nameAr: _text('name_ar'),
      code: _text('code') ?? '',
      contactName: _text('contact'),
      phone: _text('phone'),
      email: _text('email'),
      address: _text('address'),
      taxNumber: _text('tax'),
      paymentTermDays: int.tryParse(_text('terms') ?? '') ?? 0,
      notes: _text('notes'),
      isActive: _isActive,
    );

    // Validated here as well as in the repository, so the message lands beside
    // the field rather than after a round trip.
    final problems = supplier.problems;
    if (problems.isNotEmpty) {
      setState(() => _problem = problems.first.message);
      return;
    }
    Navigator.of(context).pop(supplier);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final supplier = widget.supplier;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Text(
                supplier == null ? strings.supplierNew : strings.supplierEdit,
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  _Field(
                    name: 'name',
                    label: strings.supplierName,
                    controller: _box('name', supplier?.nameEn),
                  ),
                  _Field(
                    name: 'name_ar',
                    label: strings.tenderNameAr,
                    controller: _box('name_ar', supplier?.nameAr),
                    optional: true,
                  ),
                  _Field(
                    name: 'contact',
                    label: strings.supplierContact,
                    controller: _box('contact', supplier?.contactName),
                    optional: true,
                  ),
                  _Field(
                    name: 'phone',
                    label: strings.receiptPhone,
                    controller: _box('phone', supplier?.phone),
                    optional: true,
                    mono: true,
                  ),
                  _Field(
                    name: 'email',
                    label: strings.supplierEmail,
                    controller: _box('email', supplier?.email),
                    optional: true,
                  ),
                  _Field(
                    name: 'address',
                    label: strings.receiptBranchAddress,
                    controller: _box('address', supplier?.address),
                    optional: true,
                  ),
                  _Field(
                    name: 'tax',
                    label: strings.receiptRegistrationNumber,
                    controller: _box('tax', supplier?.taxNumber),
                    optional: true,
                    mono: true,
                  ),
                  _Field(
                    name: 'terms',
                    label: strings.supplierPaymentTerms,
                    controller: _box(
                      'terms',
                      supplier == null ? '' : '${supplier.paymentTermDays}',
                    ),
                    optional: true,
                    mono: true,
                    hint: strings.supplierTermsHint,
                  ),
                  _Field(
                    name: 'code',
                    label: strings.supplierCode,
                    controller: _box('code', supplier?.code),
                    optional: true,
                    mono: true,
                  ),
                  _Field(
                    name: 'notes',
                    label: strings.supplierNotes,
                    controller: _box('notes', supplier?.notes),
                    optional: true,
                  ),
                  if (supplier != null)
                    SwitchListTile(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.supplierActive,
                        style: PosText.ui(size: 13.5, color: palette.body),
                      ),
                      subtitle: Text(
                        strings.supplierActiveHint,
                        style: PosText.ui(size: 11.5, color: palette.muted),
                      ),
                    ),
                  if (_problem != null) ...[
                    const SizedBox(height: PosSpace.sm),
                    Text(
                      _problem!,
                      style: PosText.ui(size: 12.5, color: palette.danger),
                    ),
                  ],
                  const SizedBox(height: PosSpace.lg),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                border: BorderDirectional(top: palette.resting),
              ),
              child: Row(
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
                      key: const Key('supplier-save'),
                      label: strings.save,
                      background: palette.ink,
                      foreground: palette.onInk,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.name,
    this.optional = false,
    this.mono = false,
    this.hint,
  });

  /// The box's own key, so a test names the field rather than counting boxes.
  final String name;

  final String label;
  final TextEditingController controller;
  final bool optional;
  final bool mono;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PosSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(optional ? context.strings.optionalField(label) : label),
        const SizedBox(height: PosSpace.xs),
        TextField(
          key: Key('supplier-$name'),
          controller: controller,
          textDirection: mono ? TextDirection.ltr : null,
          // Always a decoration. `null` here is not "the default" — it is NO
          // decoration: no border, no fill, none of the theme. Nine of these
          // boxes were invisible for it, and the one with a hint was the only
          // field on the form that looked like a field.
          decoration: const InputDecoration(),
          style: mono
              ? PosText.mono(size: 15, color: context.pos.ink)
              : PosText.ui(size: 15, color: context.pos.ink),
        ),
        // Under the box, not inside it. It explains the field — a sentence in
        // the box read as something already typed there.
        if (hint case final text?) ...[
          const SizedBox(height: PosSpace.xs),
          Text(
            text,
            style: PosText.ui(
              size: 12,
              color: context.pos.muted,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );
}
