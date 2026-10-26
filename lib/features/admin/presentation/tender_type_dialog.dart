import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/content_languages.dart';
import '../../../domain/models/tender_method.dart';

/// Authoring one payment method (§40).
///
/// **The two switches are not the same question, and the dialog says so.**
/// "Counts as cash" decides what the drawer is expected to hold; "opens the
/// drawer" decides whether the till kicks it. A restaurant that keeps meal
/// vouchers in the till opens the drawer for them and does not count them —
/// putting the two on one checkbox is how a cash-up starts reporting a surplus
/// nobody can explain.
class TenderTypeDialog extends StatefulWidget {
  const TenderTypeDialog({
    super.key,
    this.method,
    this.languages = ContentLanguages.both,
  });

  /// Null creates a new one.
  final TenderMethod? method;

  /// Which name fields the restaurant writes its content in (XORD-005).
  final ContentLanguages languages;

  static Future<TenderMethod?> show(
    BuildContext context, {
    TenderMethod? method,
    ContentLanguages languages = ContentLanguages.both,
  }) => showDialog<TenderMethod>(
    context: context,
    builder: (_) => TenderTypeDialog(method: method, languages: languages),
  );

  @override
  State<TenderTypeDialog> createState() => _TenderTypeDialogState();
}

class _TenderTypeDialogState extends State<TenderTypeDialog> {
  late final _nameEn = TextEditingController(
    text: widget.method?.nameEn ?? '',
  );
  late final _nameAr = TextEditingController(
    text: widget.method?.nameAr ?? '',
  );
  late final _code = TextEditingController(text: widget.method?.code ?? '');

  late TenderKind _kind = widget.method?.kind ?? TenderKind.other;
  late bool _countsAsCash = widget.method?.countsAsCash ?? false;
  late bool _opensDrawer = widget.method?.opensDrawer ?? false;
  late bool _requiresReference = widget.method?.requiresReference ?? false;
  late bool _refundAllowed = widget.method?.refundAllowed ?? true;
  late bool _isActive = widget.method?.isActive ?? true;

  bool get _isNew => widget.method == null;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    _code.dispose();
    super.dispose();
  }

  /// A code from the English name, for a method being created.
  ///
  /// Generated rather than asked for: a code is machine identity and nobody
  /// setting up a restaurant has an opinion about it. It stays editable because
  /// the one case that matters — matching a code an integration already
  /// expects — is one only the operator knows about.
  void _suggestCode(String nameEn) {
    if (!_isNew || _code.text.trim().isNotEmpty) return;
    // An Arabic-only name has no Latin letters to make a code from.
    _code.text = codeFromName(nameEn, fallback: 'method');
  }

  void _save() {
    final names = resolveNames(
      languages: widget.languages,
      typedEn: _nameEn.text,
      typedAr: _nameAr.text,
      previousEn: widget.method?.nameEn,
      previousAr: widget.method?.nameAr,
    );
    _suggestCode(names.nameEn);
    Navigator.of(context).pop(
      TenderMethod(
        id: widget.method?.id ?? 0,
        code: _code.text.trim(),
        nameEn: names.nameEn,
        nameAr: names.nameAr.isEmpty ? null : names.nameAr,
        kind: _kind,
        countsAsCash: _countsAsCash,
        opensDrawer: _opensDrawer,
        requiresReference: _requiresReference,
        refundAllowed: _refundAllowed,
        isActive: _isActive,
        sortOrder: widget.method?.sortOrder ?? 99,
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
                _isNew ? strings.tenderNew : strings.tenderEdit,
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: PosSpace.lg),

              if (widget.languages.showsEnglish)
                _Field(
                  fieldKey: const Key('tender-name'),
                  label: strings.tenderNameEn,
                  controller: _nameEn,
                ),
              if (widget.languages.showsArabic)
                _Field(
                  fieldKey: const Key('tender-name-ar'),
                  label: strings.tenderNameAr,
                  controller: _nameAr,
                  optional: widget.languages == ContentLanguages.both,
                ),
              _Field(
                label: strings.tenderCode,
                controller: _code,
                mono: true,
                // A code is identity: changing one on a live method points
                // every integration that knows it at nothing.
                enabled: _isNew,
                optional: _isNew,
              ),

              const SizedBox(height: PosSpace.sm),
              MicroLabel(strings.tenderKind),
              const SizedBox(height: PosSpace.xs),
              Wrap(
                spacing: PosSpace.sm,
                runSpacing: PosSpace.sm,
                children: [
                  for (final kind in TenderKind.values)
                    PosButton(
                      label: strings.tenderKindName(kind.wire),
                      background: kind == _kind
                          ? palette.ink
                          : Colors.transparent,
                      foreground: kind == _kind ? Colors.white : null,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => setState(() => _kind = kind),
                    ),
                ],
              ),

              const SizedBox(height: PosSpace.lg),
              _Switch(
                label: strings.tenderCountsAsCash,
                hint: strings.tenderCountsAsCashHint,
                value: _countsAsCash,
                onChanged: (v) => setState(() => _countsAsCash = v),
              ),
              _Switch(
                label: strings.tenderOpensDrawer,
                hint: strings.tenderOpensDrawerHint,
                value: _opensDrawer,
                onChanged: (v) => setState(() => _opensDrawer = v),
              ),
              _Switch(
                label: strings.tenderRequiresReference,
                value: _requiresReference,
                onChanged: (v) => setState(() => _requiresReference = v),
              ),
              _Switch(
                label: strings.tenderRefundAllowed,
                value: _refundAllowed,
                onChanged: (v) => setState(() => _refundAllowed = v),
              ),
              if (!_isNew)
                _Switch(
                  label: strings.tenderActive,
                  hint: strings.tenderActiveHint,
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
                      key: const Key('tender-save'),
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
    this.fieldKey,
    this.optional = false,
    this.mono = false,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final bool optional;
  final bool mono;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PosSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(optional ? context.strings.optionalField(label) : label),
        const SizedBox(height: PosSpace.xs),
        TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          textDirection: mono ? TextDirection.ltr : null,
          style: mono
              ? PosText.mono(size: 15, color: context.pos.ink)
              : PosText.ui(size: 15, color: context.pos.ink),
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

  /// One line saying what the switch actually decides. Present on the two that
  /// look like the same question and are not.
  final String? hint;

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: SwitchListTile(
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
    ),
  );
}
