import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/content_languages.dart';
import 'content_language_ui.dart';
import '../../../domain/models/tax.dart';
import 'admin_pane_bits.dart';
import '../../../core/text/digits.dart';

/// A named rate (§17).
///
/// **The name is not decoration.** Zero-rated and exempt are both 0% and are
/// different things on a filing, and the only place that difference can live is
/// what the group is called — because that is what an accountant reconciles
/// against. So the name is required and the hint says why.
class TaxGroupDialog extends StatefulWidget {
  const TaxGroupDialog({
    super.key,
    this.group,
    this.languages = ContentLanguages.both,
  });

  final TaxGroup? group;

  /// Which name fields the restaurant writes its content in (XORD-005).
  final ContentLanguages languages;

  static Future<TaxGroup?> show(
    BuildContext context, {
    TaxGroup? group,
    ContentLanguages languages = ContentLanguages.both,
  }) => showDialog<TaxGroup>(
    context: context,
    builder: (_) => TaxGroupDialog(group: group, languages: languages),
  );

  @override
  State<TaxGroupDialog> createState() => _TaxGroupDialogState();
}

class _TaxGroupDialogState extends State<TaxGroupDialog> {
  late final _nameEn = TextEditingController(text: widget.group?.nameEn ?? '');
  late final _nameAr = TextEditingController(
    text: initialArabicName(
      languages: widget.languages,
      nameAr: widget.group?.nameAr,
      nameEn: widget.group?.nameEn,
    ),
  );
  late final _rate = TextEditingController(
    text: widget.group == null ? '' : _percent(widget.group!.rateBp),
  );

  late bool _isDefault = widget.group?.isDefault ?? false;
  late bool _isActive = widget.group?.isActive ?? true;
  String? _problem;

  /// Basis points as a percentage string, without trailing noise.
  static String _percent(int bp) {
    final value = bp / 100;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _save() {
    final strings = context.strings;
    if (!hasRequiredName(
      languages: widget.languages,
      typedEn: _nameEn.text,
      typedAr: _nameAr.text,
    )) {
      setState(() => _problem = strings.taxGroupNeedsAName);
      return;
    }

    final typed = double.tryParse(foldDigits(_rate.text.trim()));
    if (typed == null || typed < 0 || typed > 100) {
      setState(() => _problem = strings.taxGroupRateNotValid);
      return;
    }

    final names = resolveNames(
      languages: widget.languages,
      typedEn: _nameEn.text,
      typedAr: _nameAr.text,
      previousEn: widget.group?.nameEn,
      previousAr: widget.group?.nameAr,
    );

    Navigator.of(context).pop(
      TaxGroup(
        id: widget.group?.id ?? 0,
        nameEn: names.nameEn,
        nameAr: names.nameAr.isEmpty ? null : names.nameAr,
        rateBp: (typed * 100).round(),
        isDefault: _isDefault,
        isActive: _isActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final existing = widget.group;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null
                        ? strings.taxGroupNew
                        : strings.taxGroupEdit,
                    style: PosText.ui(
                      size: 18,
                      weight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    strings.taxGroupHint,
                    style: PosText.ui(
                      size: 12.5,
                      color: palette.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  if (widget.languages.showsEnglish) ...[
                    NameDirection(
                      languages: widget.languages,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MicroLabel(
                            widget.languages.nameStrings(strings).taxGroupName,
                          ),
                          const SizedBox(height: PosSpace.xs),
                          TextField(
                            key: const Key('tax-group-name'),
                            controller: _nameEn,
                            onChanged: (_) => setState(() => _problem = null),
                            style: PosText.ui(size: 15, color: palette.ink),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PosSpace.md),
                  ],
                  if (widget.languages.showsArabic) ...[
                    // Required when it is the only language; optional beside
                    // English.
                    NameDirection(
                      languages: widget.languages,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MicroLabel(
                            widget.languages == ContentLanguages.arabic
                                ? widget.languages
                                      .nameStrings(strings)
                                      .taxGroupName
                                : strings.optionalField(strings.tenderNameAr),
                          ),
                          const SizedBox(height: PosSpace.xs),
                          TextField(
                            key: const Key('tax-group-name-ar'),
                            controller: _nameAr,
                            onChanged: (_) => setState(() => _problem = null),
                            style: PosText.ui(size: 15, color: palette.ink),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: PosSpace.lg),
                  RateBox(
                    boxKey: const Key('tax-group-rate'),
                    controller: _rate,
                    label: strings.taxGroupRate,
                  ),
                  const SizedBox(height: PosSpace.lg),
                  SwitchListTile(
                    key: const Key('tax-group-default'),
                    value: _isDefault,
                    onChanged: (v) => setState(() => _isDefault = v),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      strings.taxGroupDefault,
                      style: PosText.ui(size: 13.5, color: palette.body),
                    ),
                    subtitle: Text(
                      strings.taxGroupDefaultHint,
                      style: PosText.ui(
                        size: 11.5,
                        color: palette.muted,
                        height: 1.4,
                      ),
                    ),
                  ),
                  // Nothing to retire on a rate nobody has saved yet.
                  if (existing != null)
                    SwitchListTile(
                      key: const Key('tax-group-active'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.taxGroupActive,
                        style: PosText.ui(size: 13.5, color: palette.body),
                      ),
                      subtitle: Text(
                        strings.taxGroupActiveHint,
                        style: PosText.ui(
                          size: 11.5,
                          color: palette.muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (_problem != null) ...[
                    const SizedBox(height: PosSpace.md),
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
                      key: const Key('tax-group-save'),
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
