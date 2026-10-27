import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/content_languages.dart';
import 'content_language_ui.dart';
import '../../../domain/models/pos_unit.dart';
import '../../../domain/services/eta_filing.dart' show etaFilingEnabled;

/// Adding or editing one unit.
///
/// The code is asked for once and then fixed: purchase lines and stock rows
/// store it, so a new name is fine and a new code is not.
class UnitDialog extends StatefulWidget {
  const UnitDialog({
    super.key,
    this.unit,
    this.languages = ContentLanguages.both,
  });

  /// Null adds a new one.
  final PosUnit? unit;

  /// Which name fields the restaurant writes its content in (XORD-005).
  final ContentLanguages languages;

  static Future<PosUnit?> show(
    BuildContext context, {
    PosUnit? unit,
    ContentLanguages languages = ContentLanguages.both,
  }) => showDialog<PosUnit>(
    context: context,
    builder: (_) => UnitDialog(unit: unit, languages: languages),
  );

  @override
  State<UnitDialog> createState() => _UnitDialogState();
}

class _UnitDialogState extends State<UnitDialog> {
  late final _nameEn = TextEditingController(text: widget.unit?.nameEn ?? '');
  late final _nameAr = TextEditingController(
    text: initialArabicName(
      languages: widget.languages,
      nameAr: widget.unit?.nameAr,
      nameEn: widget.unit?.nameEn,
    ),
  );
  late final _code = TextEditingController(text: widget.unit?.code ?? '');
  late final _eta = TextEditingController(
    text: widget.unit?.etaUnitType ?? PosUnit.defaultEtaUnitType,
  );
  late bool _allowsFraction = widget.unit?.allowsFraction ?? false;
  late bool _isActive = widget.unit?.isActive ?? true;

  bool get _isNew => widget.unit == null;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    _code.dispose();
    _eta.dispose();
    super.dispose();
  }

  void _save() {
    final names = resolveNames(
      languages: widget.languages,
      typedEn: _nameEn.text,
      typedAr: _nameAr.text,
      previousEn: widget.unit?.nameEn,
      previousAr: widget.unit?.nameAr,
    );
    // A code from the English name when nobody typed one: "Tray of 30" is
    // tray_of_30. It stays editable for the case only the operator knows; an
    // Arabic-only name has no Latin letters to make one from.
    if (_isNew && _code.text.trim().isEmpty) {
      _code.text = codeFromName(names.nameEn, fallback: 'unit');
    }
    Navigator.of(context).pop(
      PosUnit(
        id: widget.unit?.id ?? 0,
        code: _code.text.trim(),
        nameEn: names.nameEn,
        nameAr: names.nameAr.isEmpty ? null : names.nameAr,
        etaUnitType: _eta.text.trim().toUpperCase(),
        allowsFraction: _allowsFraction,
        isActive: _isActive,
        sortOrder: widget.unit?.sortOrder ?? 100,
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
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isNew ? strings.unitNew : strings.unitEdit,
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: PosSpace.lg),
              if (widget.languages.showsEnglish)
                NameDirection(
                  languages: widget.languages,
                  child: _Field(
                    name: 'name',
                    label: widget.languages.nameStrings(strings).unitNameEn,
                    controller: _nameEn,
                  ),
                ),
              if (widget.languages.showsArabic)
                NameDirection(
                  languages: widget.languages,
                  child: _Field(
                    name: 'name_ar',
                    label: widget.languages == ContentLanguages.arabic
                        ? widget.languages.nameStrings(strings).unitNameEn
                        : strings.unitNameAr,
                    controller: _nameAr,
                    optional: widget.languages == ContentLanguages.both,
                  ),
                ),
              _Field(
                name: 'code',
                label: strings.unitCode,
                controller: _code,
                mono: true,
                enabled: _isNew,
                optional: _isNew,
                hint: strings.unitCodeHelp,
              ),
              // Kept, and saved as it was, while e-receipts are off: nothing
              // else reads it.
              if (etaFilingEnabled)
                _Field(
                  name: 'eta',
                  label: strings.unitEtaCode,
                  controller: _eta,
                  mono: true,
                  hint: strings.unitEtaCodeHelp,
                ),
              SwitchListTile(
                key: const Key('unit-fraction'),
                value: _allowsFraction,
                onChanged: (v) => setState(() => _allowsFraction = v),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  strings.unitAllowsFraction,
                  style: PosText.ui(size: 13.5, color: palette.body),
                ),
                subtitle: Text(
                  strings.unitAllowsFractionHelp,
                  style: PosText.ui(size: 11.5, color: palette.muted),
                ),
              ),
              if (!_isNew)
                SwitchListTile(
                  key: const Key('unit-active'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.unitActive,
                    style: PosText.ui(size: 13.5, color: palette.body),
                  ),
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
                      key: const Key('unit-save'),
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
    required this.name,
    required this.label,
    required this.controller,
    this.optional = false,
    this.mono = false,
    this.enabled = true,
    this.hint,
  });

  final String name;
  final String label;
  final TextEditingController controller;
  final bool optional;
  final bool mono;
  final bool enabled;
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
          key: Key('unit-$name'),
          controller: controller,
          enabled: enabled,
          textDirection: mono ? TextDirection.ltr : null,
          decoration: const InputDecoration(),
          style: mono
              ? PosText.mono(size: 15, color: context.pos.ink)
              : PosText.ui(size: 15, color: context.pos.ink),
        ),
        if (hint case final text?) ...[
          const SizedBox(height: PosSpace.xs),
          Text(
            text,
            style: PosText.ui(size: 12, color: context.pos.muted, height: 1.4),
          ),
        ],
      ],
    ),
  );
}
