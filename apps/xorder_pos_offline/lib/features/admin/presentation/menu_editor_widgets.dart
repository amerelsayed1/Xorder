import 'package:flutter/material.dart';

import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/fold_digits_formatter.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/domain/models/content_languages.dart';
import 'package:xorder_pos/domain/models/option_group.dart';
import 'content_language_ui.dart';

/// The pieces the menu's editors share: the dialog frame, the labelled input,
/// and everything a size or extra group is edited with.
///
/// **One file because there are two editors of the same thing.** A group is
/// edited in the Extras library and typed on an item, and the cloud dashboard
/// draws both with the same rows — the same switches, the same Sale column
/// only on sizes. Two copies would be two places for "only a size has a sale
/// price" to be forgotten.

/// A menu editor's dialog: a title, a body that scrolls, a refusal line, and
/// Cancel beside Save.
///
/// The body scrolls because an item with three groups of five options is
/// taller than a till's screen, and a Save button pushed off the bottom is a
/// form that cannot be finished. Cancel and Save stay outside the scroll for
/// the same reason.
class MenuDialog extends StatelessWidget {
  const MenuDialog({
    required this.title,
    required this.onSave,
    required this.children,
    this.error,
    this.saving = false,
    this.maxWidth = 460,
    super.key,
  });

  final String title;
  final VoidCallback? onSave;
  final List<Widget> children;
  final String? error;

  /// A write is in flight. Save is disabled rather than hidden, so a second
  /// click during a slow write is not a second item.
  final bool saving;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pos.surface,
    shape: RoundedRectangleBorder(side: context.pos.emphasis),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: PosText.panelTitle(color: context.pos.ink)),
            const SizedBox(height: PosSpace.lg),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: PosSpace.md),
              Text(
                error!,
                key: const Key('menu-dialog-error'),
                style: PosText.ui(size: 12.5, color: context.pos.danger),
              ),
            ],
            const SizedBox(height: PosSpace.xl),
            Row(
              children: [
                Expanded(
                  child: PosButton(
                    label: context.strings.cancel,
                    border: Border.fromBorderSide(context.pos.resting),
                    onPressed: saving ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: PosSpace.md),
                Expanded(
                  child: PosButton(
                    key: const Key('menu-dialog-save'),
                    label: saving
                        ? context.strings.savingLabel
                        : context.strings.save,
                    background: context.pos.ink,
                    foreground: context.pos.onInk,
                    onPressed: saving ? null : onSave,
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

/// A labelled text field.
///
/// [readOnly] is for a figure the form derives rather than asks for — an
/// item's price while its sizes set it. Read-only rather than hidden, the way
/// the cloud does it, so the figure stays where a manager expects to find it.
class MenuInput extends StatelessWidget {
  const MenuInput({
    required this.controller,
    required this.label,
    this.mono = false,
    this.optional = false,
    this.readOnly = false,
    this.hint,
    this.fieldKey,
    this.arabic = false,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool mono;
  final bool optional;
  final bool readOnly;
  final String? hint;
  final Key? fieldKey;

  /// The field holds Arabic, so it runs right to left whatever the screen's
  /// language — the label stays in the screen's direction.
  final bool arabic;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(optional ? context.strings.optionalField(label) : label),
      const SizedBox(height: PosSpace.sm),
      TextField(
        key: fieldKey,
        controller: controller,
        readOnly: readOnly,
        onChanged: onChanged,
        // Numbers are Latin (see [_direction]): a manager typing on an Arabic
        // keyboard gets 150, not ١٥٠, in the price they are about to save.
        inputFormatters: mono ? const [FoldDigitsFormatter()] : null,
        textDirection: _direction(mono: mono, arabic: arabic),
        style: mono
            ? PosText.mono(
                size: 14,
                color: readOnly ? context.pos.muted : context.pos.ink,
              )
            : PosText.ui(size: 14, color: context.pos.ink),
        decoration: InputDecoration(
          hintText: hint,
          filled: readOnly,
          fillColor: readOnly ? context.pos.page : null,
        ),
      ),
    ],
  );
}

/// Numbers are Latin and left to right in both languages; an Arabic name is
/// right to left in both; anything else follows the screen.
TextDirection? _direction({required bool mono, required bool arabic}) {
  if (mono) return TextDirection.ltr;
  if (arabic) return TextDirection.rtl;
  return null;
}

/// A switch with its label beside it — the cloud's `.switch` rows.
class MenuSwitch extends StatelessWidget {
  const MenuSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;

  /// Null draws it disabled — see the item editor's second-sizes rule.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: value, onChanged: onChanged),
      const SizedBox(width: PosSpace.xs),
      Text(
        label,
        style: PosText.ui(
          size: 13,
          color: onChanged == null ? context.pos.muted : context.pos.body,
        ),
      ),
    ],
  );
}

/// A small bordered label: "Size / variant" on a group, "Default" on a size.
/// A border and not a fill, because a border is the only elevation here.
class MenuPill extends StatelessWidget {
  const MenuPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.sm,
      vertical: 2,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: context.pos.accent),
    ),
    child: Text(
      text,
      style: PosText.ui(
        size: 11.5,
        weight: FontWeight.w600,
        color: context.pos.accent,
      ),
    ),
  );
}

/// One option while it is being typed. Controllers rather than values, so a
/// row keeps what was typed in it when a row above it is removed.
class EditableOption {
  EditableOption.from(
    OptionDraft option, {
    ContentLanguages languages = ContentLanguages.both,
  }) : id = option.id,
       isAvailable = option.isAvailable,
       storedNameEn = option.nameEn,
       storedNameAr = option.nameAr,
       nameEn = TextEditingController(text: option.nameEn),
       nameAr = TextEditingController(
         text: initialArabicName(
           languages: languages,
           nameAr: option.nameAr,
           nameEn: option.nameEn,
         ),
       ),
       price = TextEditingController(text: option.price.format()),
       sale = TextEditingController(text: option.salePrice?.format() ?? '');

  /// A new row, with its price blank — which is what lets switching a group to
  /// sizes carry the item's price into it (see the item editor).
  EditableOption.blank()
    : id = 0,
      isAvailable = true,
      storedNameEn = null,
      storedNameAr = null,
      nameEn = TextEditingController(),
      nameAr = TextEditingController(),
      price = TextEditingController(),
      sale = TextEditingController();

  /// Carried back unchanged: an option keeps its id across every save, because
  /// parked tickets and past order lines name it by that id.
  final int id;

  /// Not editable here — the cloud's editors do not offer it either — but
  /// carried, because the first *available* size is the default.
  final bool isAvailable;

  /// The names as stored when the row was opened. A language the editor does
  /// not show is saved as it was, never blanked (XORD-005).
  final String? storedNameEn;
  final String? storedNameAr;

  final TextEditingController nameEn;
  final TextEditingController nameAr;
  final TextEditingController price;
  final TextEditingController sale;

  void dispose() {
    nameEn.dispose();
    nameAr.dispose();
    price.dispose();
    sale.dispose();
  }
}

/// One group while it is being typed — a library group, or one on an item.
class EditableGroup {
  EditableGroup.from(
    OptionGroupDraft group, {
    ContentLanguages languages = ContentLanguages.both,
  }) : id = group.id,
       revision = group.revision,
       minSelect = group.minSelect,
       freeOptions = group.freeOptions,
       isVariant = group.isVariant,
       isRequired = group.isRequired,
       scope = group.scope,
       categoryIds = {...group.categoryIds},
       storedNameEn = group.nameEn,
       storedNameAr = group.nameAr,
       storedDisplayEn = group.displayNameEn,
       storedDisplayAr = group.displayNameAr,
       nameEn = TextEditingController(text: group.nameEn),
       nameAr = TextEditingController(
         text: initialArabicName(
           languages: languages,
           nameAr: group.nameAr,
           nameEn: group.nameEn,
         ),
       ),
       displayEn = TextEditingController(text: group.displayNameEn ?? ''),
       displayAr = TextEditingController(text: group.displayNameAr ?? ''),
       maxSelect = TextEditingController(text: '${group.maxSelect}'),
       options = [
         for (final o in group.options)
           EditableOption.from(o, languages: languages),
       ];

  /// The cloud's new group: not required, not sizes, one choice, no options.
  EditableGroup.blank() : this.from(const OptionGroupDraft(nameEn: ''));

  final int id;
  final int revision;

  /// The till's own "needs N" and "N included", which neither editor shows —
  /// the cloud has no such fields — but which a group authored before this
  /// screen may carry, and a save must not quietly drop.
  final int minSelect;
  final int freeOptions;

  bool isVariant;
  bool isRequired;
  OptionGroupScope scope;
  final Set<int> categoryIds;

  /// The names as stored when the group was opened; see
  /// [EditableOption.storedNameEn].
  final String? storedNameEn;
  final String? storedNameAr;
  final String? storedDisplayEn;
  final String? storedDisplayAr;

  final TextEditingController nameEn;
  final TextEditingController nameAr;
  final TextEditingController displayEn;
  final TextEditingController displayAr;
  final TextEditingController maxSelect;
  final List<EditableOption> options;

  /// The size the till opens on, and so the one the item's price mirrors: the
  /// first available option. Null when this is not a size group.
  EditableOption? get defaultSize {
    if (!isVariant) return null;
    for (final option in options) {
      if (option.isAvailable) return option;
    }
    return null;
  }

  /// What was typed, as the repository takes it — or why it cannot be.
  ///
  /// The cloud's save rules, applied here as it applies them: a size is
  /// required and single-choice whatever the hidden boxes said, a blank price
  /// is zero, and only a size keeps a sale price. The repository normalises
  /// the same way; doing it here as well is what makes a blank price a zero
  /// rather than a "not a number".
  ///
  /// [languages] is which names the editor showed (XORD-005): a language it did
  /// not show keeps its stored value, and the English column of an Arabic-only
  /// business mirrors the Arabic name (see `resolveNames`).
  ({OptionGroupDraft? draft, String? error}) toDraft(
    AppStrings s, {
    ContentLanguages languages = ContentLanguages.both,
  }) {
    final drafts = <OptionDraft>[];
    for (final option in options) {
      final priceText = option.price.text.trim();
      final price = priceText.isEmpty ? Money.zero : Money.tryParse(priceText);
      if (price == null) return (draft: null, error: s.priceIsNotANumber);

      final saleText = option.sale.text.trim();
      Money? sale;
      if (isVariant && saleText.isNotEmpty) {
        sale = Money.tryParse(saleText);
        if (sale == null) return (draft: null, error: s.offerPriceIsNotANumber);
      }
      final optionNames = resolveNames(
        languages: languages,
        typedEn: option.nameEn.text,
        typedAr: option.nameAr.text,
        previousEn: option.storedNameEn,
        previousAr: option.storedNameAr,
      );
      drafts.add(
        OptionDraft(
          id: option.id,
          nameEn: languages == ContentLanguages.both
              ? option.nameEn.text
              : optionNames.nameEn,
          nameAr: languages == ContentLanguages.both
              ? option.nameAr.text
              : optionNames.nameAr,
          price: price,
          salePrice: sale,
          isAvailable: option.isAvailable,
        ),
      );
    }

    final required = isVariant || isRequired;
    final groupNames = resolveNames(
      languages: languages,
      typedEn: nameEn.text,
      typedAr: nameAr.text,
      previousEn: storedNameEn,
      previousAr: storedNameAr,
    );
    final both = languages == ContentLanguages.both;
    return (
      draft: OptionGroupDraft(
        id: id,
        revision: revision,
        nameEn: both ? nameEn.text : groupNames.nameEn,
        nameAr: both ? nameAr.text : groupNames.nameAr,
        displayNameEn: languages.showsEnglish
            ? displayEn.text
            : (storedDisplayEn ?? ''),
        displayNameAr: languages.showsArabic
            ? displayAr.text
            : (storedDisplayAr ?? ''),
        isVariant: isVariant,
        isRequired: required,
        maxSelect: isVariant ? 1 : (int.tryParse(maxSelect.text.trim()) ?? 1),
        // **Zero when the switch says not required.** The normaliser lifts a
        // required group's minimum to one and leaves an optional group's
        // alone, so a size group switched to extras would otherwise keep the
        // minimum of one it had as a size — "optional" on screen, and a
        // choice the cashier cannot skip at the till.
        minSelect: required ? minSelect : 0,
        freeOptions: freeOptions,
        scope: scope,
        categoryIds: categoryIds,
        options: drafts,
      ),
      error: null,
    );
  }

  void dispose() {
    nameEn.dispose();
    nameAr.dispose();
    displayEn.dispose();
    displayAr.dispose();
    maxSelect.dispose();
    for (final option in options) {
      option.dispose();
    }
  }
}

/// "Size / variant", then — unless it is sizes — "Required" and "Max select".
///
/// Hidden rather than disabled for a size, as the cloud does: a size is always
/// required and always one choice, so the boxes would only offer a question
/// the save then overrules.
class GroupRulesRow extends StatelessWidget {
  const GroupRulesRow({
    required this.group,
    required this.keyPrefix,
    required this.onVariant,
    required this.onChanged,
    this.trailing,
    super.key,
  });

  final EditableGroup group;
  final String keyPrefix;
  final ValueChanged<bool>? onVariant;
  final VoidCallback onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: PosSpace.lg,
                runSpacing: PosSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MenuSwitch(
                    key: Key('$keyPrefix-variant'),
                    label: s.itemVariant,
                    value: group.isVariant,
                    onChanged: onVariant,
                  ),
                  if (!group.isVariant)
                    MenuSwitch(
                      key: Key('$keyPrefix-required'),
                      label: s.itemRequired,
                      value: group.isRequired,
                      onChanged: (v) {
                        group.isRequired = v;
                        onChanged();
                      },
                    ),
                  if (!group.isVariant)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.itemMaxSelect,
                          style: PosText.ui(size: 13, color: context.pos.body),
                        ),
                        const SizedBox(width: PosSpace.sm),
                        SizedBox(
                          width: 64,
                          child: TextField(
                            key: Key('$keyPrefix-max'),
                            controller: group.maxSelect,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => onChanged(),
                            style: PosText.mono(
                              size: 13,
                              color: context.pos.ink,
                            ),
                            decoration: const InputDecoration(isDense: true),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        if (group.isVariant) ...[
          const SizedBox(height: PosSpace.xs),
          Text(
            s.itemVariantHint,
            style: PosText.ui(size: 11.5, color: context.pos.muted, height: 1.4),
          ),
        ],
      ],
    );
  }
}

/// A group's options, one row each, and "+ Add option" under them.
///
/// **Sale only on sizes.** An extra's price is added to the item, and a
/// discount on an addition is not something a customer could be told; on a
/// size the option *is* the item's price, so it can be on offer. The column
/// is absent, not disabled, for an extra — as on the cloud.
class OptionRows extends StatelessWidget {
  const OptionRows({
    required this.group,
    required this.keyPrefix,
    required this.onChanged,
    this.markDefault = false,
    this.languages = ContentLanguages.both,
    super.key,
  });

  final EditableGroup group;
  final String keyPrefix;
  final VoidCallback onChanged;

  /// Which name cells to draw (XORD-005).
  final ContentLanguages languages;

  /// Put "Default" on the size the item's price mirrors. Only the item editor
  /// asks — in the library the default depends on nothing but order, and the
  /// cloud does not mark it there either.
  final bool markDefault;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    final fallback = markDefault ? group.defaultSize : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, option) in group.options.indexed)
          Padding(
            key: ObjectKey(option),
            padding: const EdgeInsets.only(bottom: PosSpace.sm),
            child: Row(
              children: [
                if (languages.showsEnglish) ...[
                  Expanded(
                    child: NameDirection(
                      languages: languages,
                      child: _Cell(
                        key: Key('$keyPrefix-option-$i-name'),
                        controller: option.nameEn,
                        hint: languages.nameStrings(s).itemOptionEn,
                        onChanged: onChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                ],
                if (languages.showsArabic) ...[
                  Expanded(
                    child: NameDirection(
                      languages: languages,
                      child: _Cell(
                        key: Key('$keyPrefix-option-$i-name-ar'),
                        controller: option.nameAr,
                        hint: languages.nameStrings(s).itemOptionAr,
                        arabic: true,
                        onChanged: onChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                ],
                SizedBox(
                  width: 90,
                  child: _Cell(
                    key: Key('$keyPrefix-option-$i-price'),
                    controller: option.price,
                    // What the number means: a size is the price, an extra
                    // is added to it.
                    hint: group.isVariant ? '0' : '+0',
                    mono: true,
                    onChanged: onChanged,
                  ),
                ),
                if (group.isVariant) ...[
                  const SizedBox(width: PosSpace.sm),
                  SizedBox(
                    width: 90,
                    child: Tooltip(
                      message: s.itemOptionDiscountHint,
                      child: _Cell(
                        key: Key('$keyPrefix-option-$i-sale'),
                        controller: option.sale,
                        hint: s.itemOptionDiscount,
                        mono: true,
                        onChanged: onChanged,
                      ),
                    ),
                  ),
                ],
                if (identical(option, fallback)) ...[
                  const SizedBox(width: PosSpace.sm),
                  MenuPill(
                    s.itemDefaultSize,
                    key: Key('$keyPrefix-option-$i-default'),
                  ),
                ],
                IconButton(
                  key: Key('$keyPrefix-option-$i-remove'),
                  icon: Icon(Icons.close, size: 16, color: pos.danger),
                  tooltip: s.deleteLabel,
                  onPressed: () {
                    group.options.remove(option);
                    option.dispose();
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        PosButton(
          key: Key('$keyPrefix-add-option'),
          label: '+ ${s.itemAddOption}',
          height: 36,
          border: Border.fromBorderSide(pos.resting),
          onPressed: () {
            group.options.add(EditableOption.blank());
            onChanged();
          },
        ),
      ],
    );
  }
}

/// A compact field inside an option row: no label, the placeholder says it.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.mono = false,
    this.arabic = false,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool mono;
  final bool arabic;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: (_) => onChanged(),
    textDirection: _direction(mono: mono, arabic: arabic),
    style: mono
        ? PosText.mono(size: 13, color: context.pos.ink)
        : PosText.ui(size: 13, color: context.pos.ink),
    decoration: InputDecoration(hintText: hint, isDense: true),
  );
}
