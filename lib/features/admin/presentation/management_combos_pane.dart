import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/catalog.dart';
import '../../../domain/models/combo_draft.dart';
import '../../../domain/models/content_languages.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import 'admin_messages.dart';

/// Combos: a meal at one price, built from real menu items.
///
/// **Offline only**, like the Menu pane it sits beside: on a cloud till the
/// platform authors the catalogue and the bootstrap seeder rewrites this
/// database's copy, so a combo made here would last until the next sync. The
/// till already sells combos (`ComboSheet`); until this pane existed nothing
/// in the app could create one.
///
/// There is no delete. A combo is retired by switching it off, because an
/// order line names it and a reprint next year still has to say what was sold.
class ManagementCombosPane extends ConsumerStatefulWidget {
  const ManagementCombosPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementCombosPane> createState() =>
      _ManagementCombosPaneState();
}

class _ManagementCombosPaneState extends ConsumerState<ManagementCombosPane> {
  /// Held rather than a provider, as the Extras pane holds its library:
  /// nothing else lists combos for editing, and the till's own read is
  /// `catalogProvider`, which is invalidated after every write here.
  Future<List<ComboDraft>>? _combos;

  void _reload(CatalogAdminRepository repository) {
    // A block, not an arrow: `=>` would hand setState the Future it is
    // assigning, which it refuses.
    setState(() {
      _combos = repository.combos();
    });
    ref.invalidate(catalogProvider);
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(catalogAdminRepositoryProvider);
    // Loaded before a dialog opens, so its first frame already has the right
    // boxes (the menu pane does the same).
    ref.watch(contentLanguagesProvider);
    final strings = context.strings;
    final pos = context.pos;
    if (repository == null) {
      return _Centred(text: strings.menuComesFromPlatform);
    }
    _combos ??= repository.combos();

    // Watched at pane level so the dialog's pickers have them when it opens.
    final catalog = ref.watch(catalogProvider).valueOrNull ?? Catalog.empty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(PosSpace.xl),
          decoration: BoxDecoration(border: Border(bottom: pos.hairline)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.combosTitle,
                      style: PosText.panelTitle(color: pos.ink),
                    ),
                    const SizedBox(height: PosSpace.xs),
                    Text(
                      strings.combosSubtitle,
                      style: PosText.ui(size: 13, color: pos.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PosSpace.lg),
              PosButton(
                key: const Key('combos-new'),
                label: '+ ${strings.combosNew}',
                background: pos.ink,
                foreground: pos.onInk,
                onPressed: () => _edit(repository, null, catalog),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ComboDraft>>(
            future: _combos,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _Centred(text: '${snapshot.error}');
              }
              final rows = snapshot.data;
              if (rows == null) {
                return Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: pos.accent,
                  ),
                );
              }
              if (rows.isEmpty) return _Centred(text: strings.combosNone);
              return ListView(
                children: [
                  for (final combo in rows)
                    _Row(
                      combo: combo,
                      categories: catalog.categories,
                      onEdit: () => _edit(repository, combo, catalog),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    CatalogAdminRepository repository,
    ComboDraft? existing,
    Catalog catalog,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ComboDialog(
        combo: existing,
        categories: catalog.categories,
        products: catalog.products,
        languages: ref.read(contentLanguagesNowProvider),
        onSave: (combo) async =>
            (await repository.saveCombo(combo, by: widget.admin)).refusal,
      ),
    );
    if (saved == true && mounted) _reload(repository);
  }
}

String _name(String en, String? ar, String locale) =>
    locale.startsWith('ar') && (ar?.isNotEmpty ?? false) ? ar! : en;

class _Row extends StatelessWidget {
  const _Row({
    required this.combo,
    required this.categories,
    required this.onEdit,
  });

  final ComboDraft combo;
  final List<Category> categories;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    final options = combo.groups.fold<int>(0, (n, g) => n + g.options.length);
    final category = categories.where((c) => c.id == combo.categoryId);

    return InkWell(
      key: Key('combo-row-${combo.id}'),
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.xl,
          vertical: PosSpace.md,
        ),
        decoration: BoxDecoration(border: Border(bottom: pos.hairline)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name(combo.nameEn, combo.nameAr, s.languageCode),
                    style: PosText.ui(
                      size: 14,
                      weight: FontWeight.w600,
                      color: combo.isAvailable ? pos.ink : pos.muted,
                    ),
                  ),
                  Text(
                    [
                      if (category.isNotEmpty)
                        _name(
                          category.first.nameEn,
                          category.first.nameAr,
                          s.languageCode,
                        ),
                      s.comboGroupsSummary(combo.groups.length, options),
                      if (!combo.isAvailable) s.comboRetired,
                    ].join(' · '),
                    style: PosText.ui(size: 12, color: pos.muted),
                  ),
                ],
              ),
            ),
            MonoAmount(combo.price, size: 14),
          ],
        ),
      ),
    );
  }
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
        style: PosText.ui(size: 13.5, color: context.pos.muted),
      ),
    ),
  );
}

// ── the editor ───────────────────────────────────────────────────────────────

class _OptionState {
  _OptionState(this.productId, String delta)
    : delta = TextEditingController(text: delta);

  int? productId;
  final TextEditingController delta;
}

class _GroupState {
  _GroupState(ComboGroupDraft? group, {required String Function(Money) fmt})
    : id = group?.id ?? 0,
      storedEn = group?.nameEn,
      storedAr = group?.nameAr,
      nameEn = TextEditingController(text: group?.nameEn ?? ''),
      nameAr = TextEditingController(text: group?.nameAr ?? ''),
      min = TextEditingController(text: '${group?.minSelect ?? 1}'),
      max = TextEditingController(text: '${group?.maxSelect ?? 1}'),
      options = [
        for (final option in group?.options ?? const <ComboOptionDraft>[])
          _OptionState(
            option.productId,
            option.priceDelta.minor == 0 ? '' : fmt(option.priceDelta),
          ),
      ];

  final int id;

  /// What is stored for this group's names, so a language the form hides keeps
  /// its value on save (XORD-005).
  final String? storedEn;
  final String? storedAr;
  final TextEditingController nameEn;
  final TextEditingController nameAr;
  final TextEditingController min;
  final TextEditingController max;
  final List<_OptionState> options;

  void dispose() {
    nameEn.dispose();
    nameAr.dispose();
    min.dispose();
    max.dispose();
    for (final option in options) {
      option.delta.dispose();
    }
  }
}

class _ComboDialog extends StatefulWidget {
  const _ComboDialog({
    required this.combo,
    required this.categories,
    required this.products,
    required this.onSave,
    required this.languages,
  });

  /// Which languages the menu is written in: the name boxes shown follow it.
  final ContentLanguages languages;

  final ComboDraft? combo;
  final List<Category> categories;
  final List<Product> products;
  final Future<AdminRefusal?> Function(ComboDraft) onSave;

  @override
  State<_ComboDialog> createState() => _ComboDialogState();
}

class _ComboDialogState extends State<_ComboDialog> {
  static String _plain(Money m) => m.format();

  late final _nameEn = TextEditingController(text: widget.combo?.nameEn ?? '');
  late final _nameAr = TextEditingController(text: widget.combo?.nameAr ?? '');
  late final _price = TextEditingController(
    text: widget.combo == null ? '' : _plain(widget.combo!.price),
  );
  late final _sku = TextEditingController(text: widget.combo?.sku ?? '');
  late int? _categoryId =
      widget.combo?.categoryId ??
      (widget.categories.isEmpty ? null : widget.categories.first.id);
  late bool _available = widget.combo?.isAvailable ?? true;
  late final List<_GroupState> _groups = [
    for (final group in widget.combo?.groups ?? const <ComboGroupDraft>[])
      _GroupState(group, fmt: _plain),
  ];

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    _price.dispose();
    _sku.dispose();
    for (final group in _groups) {
      group.dispose();
    }
    super.dispose();
  }

  /// What the boxes say, or null with [_error] set.
  ComboDraft? _draft(AppStrings strings) {
    final price = Money.tryParse(_price.text);
    if (price == null) {
      setState(() => _error = strings.priceIsNotANumber);
      return null;
    }

    final groups = <ComboGroupDraft>[];
    for (final group in _groups) {
      final options = <ComboOptionDraft>[];
      for (final option in group.options) {
        final product = option.productId;
        if (product == null) continue;
        final text = option.delta.text.trim();
        final delta = text.isEmpty ? Money.zero : Money.tryParse(text);
        if (delta == null) {
          setState(() => _error = strings.priceIsNotANumber);
          return null;
        }
        options.add(ComboOptionDraft(productId: product, priceDelta: delta));
      }
      final groupNames = resolveNames(
        languages: widget.languages,
        typedEn: group.nameEn.text,
        typedAr: group.nameAr.text,
        previousEn: group.storedEn,
        previousAr: group.storedAr,
      );
      groups.add(
        ComboGroupDraft(
          id: group.id,
          nameEn: groupNames.nameEn,
          nameAr: groupNames.nameAr,
          // An unreadable count becomes one the rules refuse, never a crash.
          minSelect: int.tryParse(group.min.text.trim()) ?? -1,
          maxSelect: int.tryParse(group.max.text.trim()) ?? 0,
          options: options,
        ),
      );
    }

    final names = resolveNames(
      languages: widget.languages,
      typedEn: _nameEn.text,
      typedAr: _nameAr.text,
      previousEn: widget.combo?.nameEn,
      previousAr: widget.combo?.nameAr,
    );

    return ComboDraft(
      id: widget.combo?.id ?? 0,
      categoryId: _categoryId ?? 0,
      nameEn: names.nameEn,
      nameAr: names.nameAr,
      price: price,
      // Carried, not edited here: a combo is taxed like anything else unless
      // somebody has said otherwise, and saving must not silently change it.
      taxGroupId: widget.combo?.taxGroupId,
      sku: _sku.text,
      isAvailable: _available,
      groups: groups,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final strings = context.strings;
    final draft = _draft(strings);
    if (draft == null) return;

    // The same rules the repository applies, asked first so a blank name is
    // answered without a round trip to the database.
    final problem = ComboRules.refusal(draft);
    if (problem != null) {
      setState(() => _error = AdminText.comboProblem(strings, problem));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final refusal = await widget.onSave(draft);
    if (!mounted) return;
    if (refusal == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = AdminText.refusal(strings, refusal);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final locale = strings.languageCode;

    return Dialog(
      backgroundColor: pos.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Text(
                widget.combo == null ? strings.combosNew : strings.combosEdit,
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: pos.ink,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  if (widget.languages.showsEnglish) ...[
                    MicroLabel(strings.comboName),
                    const SizedBox(height: PosSpace.xs),
                    TextField(
                      key: const Key('combo-name'),
                      controller: _nameEn,
                      onChanged: (_) => setState(() => _error = null),
                      style: PosText.ui(size: 15, color: pos.ink),
                    ),
                    const SizedBox(height: PosSpace.md),
                  ],
                  if (widget.languages.showsArabic) ...[
                    // The one name box when Arabic is the only language;
                    // otherwise the optional second one.
                    MicroLabel(
                      widget.languages == ContentLanguages.arabic
                          ? strings.comboName
                          : strings.optionalField(strings.tenderNameAr),
                    ),
                    const SizedBox(height: PosSpace.xs),
                    TextField(
                      key: const Key('combo-name-ar'),
                      controller: _nameAr,
                      onChanged: (_) => setState(() => _error = null),
                      style: PosText.ui(size: 15, color: pos.ink),
                    ),
                    const SizedBox(height: PosSpace.md),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MicroLabel(strings.comboPrice),
                            const SizedBox(height: PosSpace.xs),
                            TextField(
                              key: const Key('combo-price'),
                              controller: _price,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() => _error = null),
                              style: PosText.mono(size: 15, color: pos.ink),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: PosSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MicroLabel(strings.optionalField(strings.comboSku)),
                            const SizedBox(height: PosSpace.xs),
                            TextField(
                              key: const Key('combo-sku'),
                              controller: _sku,
                              style: PosText.mono(size: 15, color: pos.ink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PosSpace.md),
                  MicroLabel(strings.comboCategory),
                  const SizedBox(height: PosSpace.xs),
                  DropdownButton<int>(
                    key: const Key('combo-category'),
                    isExpanded: true,
                    value: widget.categories.any((c) => c.id == _categoryId)
                        ? _categoryId
                        : null,
                    items: [
                      for (final category in widget.categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(
                            _name(category.nameEn, category.nameAr, locale),
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() {
                      _categoryId = id;
                      _error = null;
                    }),
                  ),
                  if (widget.combo != null)
                    SwitchListTile(
                      key: const Key('combo-available'),
                      value: _available,
                      onChanged: (v) => setState(() => _available = v),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.comboAvailable,
                        style: PosText.ui(size: 13.5, color: pos.body),
                      ),
                      subtitle: Text(
                        strings.comboAvailableHint,
                        style: PosText.ui(size: 11.5, color: pos.muted),
                      ),
                    ),
                  const SizedBox(height: PosSpace.lg),
                  MicroLabel(strings.comboChoices),
                  const SizedBox(height: PosSpace.sm),
                  for (var g = 0; g < _groups.length; g++) _group(g, locale),
                  PosButton(
                    key: const Key('combo-add-group'),
                    label: strings.comboAddGroup,
                    border: Border.fromBorderSide(pos.resting),
                    onPressed: () => setState(() {
                      _groups.add(_GroupState(null, fmt: _plain));
                      _error = null;
                    }),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: PosSpace.md),
                    Text(
                      _error!,
                      key: const Key('combo-error'),
                      style: PosText.ui(size: 12.5, color: pos.danger),
                    ),
                  ],
                  const SizedBox(height: PosSpace.lg),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                border: BorderDirectional(top: pos.resting),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(pos.resting),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      key: const Key('combo-save'),
                      label: strings.save,
                      background: pos.ink,
                      foreground: pos.onInk,
                      onPressed: _busy ? null : _save,
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

  /// The Arabic name box of a group: a fixed-width second box beside the
  /// English one, or the whole row when Arabic is the only language.
  Widget _groupArabic(
    int index,
    _GroupState group,
    AppStrings strings,
    PosPalette pos, {
    required bool soleName,
  }) {
    final field = TextField(
      key: Key('combo-group-name-ar-$index'),
      controller: group.nameAr,
      onChanged: (_) => setState(() => _error = null),
      decoration: InputDecoration(
        hintText: soleName ? strings.comboGroupName : strings.tenderNameAr,
      ),
      style: PosText.ui(size: 14, color: pos.ink),
    );
    return soleName
        ? Expanded(child: field)
        : SizedBox(width: 150, child: field);
  }

  Widget _group(int index, String locale) {
    final strings = context.strings;
    final pos = context.pos;
    final group = _groups[index];

    return Container(
      key: Key('combo-group-$index'),
      margin: const EdgeInsets.only(bottom: PosSpace.md),
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(border: Border.fromBorderSide(pos.resting)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.languages.showsEnglish)
                Expanded(
                  child: TextField(
                    key: Key('combo-group-name-$index'),
                    controller: group.nameEn,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: InputDecoration(
                      hintText: strings.comboGroupName,
                    ),
                    style: PosText.ui(size: 14, color: pos.ink),
                  ),
                ),
              if (widget.languages == ContentLanguages.both)
                const SizedBox(width: PosSpace.sm),
              if (widget.languages.showsArabic)
                _groupArabic(
                  index,
                  group,
                  strings,
                  pos,
                  soleName: widget.languages == ContentLanguages.arabic,
                ),
              IconButton(
                key: Key('combo-group-remove-$index'),
                tooltip: strings.comboRemove,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() {
                  _groups.removeAt(index).dispose();
                  _error = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: PosSpace.sm),
          Row(
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  key: Key('combo-group-min-$index'),
                  controller: group.min,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: strings.comboMinSelect),
                  style: PosText.mono(size: 14, color: pos.ink),
                ),
              ),
              const SizedBox(width: PosSpace.sm),
              SizedBox(
                width: 80,
                child: TextField(
                  key: Key('combo-group-max-$index'),
                  controller: group.max,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: strings.comboMaxSelect),
                  style: PosText.mono(size: 14, color: pos.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: PosSpace.sm),
          for (var o = 0; o < group.options.length; o++)
            Row(
              key: Key('combo-option-$index-$o'),
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    key: Key('combo-option-product-$index-$o'),
                    isExpanded: true,
                    hint: Text(strings.comboOptionProduct),
                    value:
                        widget.products.any(
                          (p) => p.id == group.options[o].productId,
                        )
                        ? group.options[o].productId
                        : null,
                    items: [
                      for (final product in widget.products)
                        DropdownMenuItem(
                          value: product.id,
                          child: Text(
                            _name(product.nameEn, product.nameAr, locale),
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() {
                      group.options[o].productId = id;
                      _error = null;
                    }),
                  ),
                ),
                const SizedBox(width: PosSpace.sm),
                SizedBox(
                  width: 100,
                  child: TextField(
                    key: Key('combo-option-delta-$index-$o'),
                    controller: group.options[o].delta,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: strings.comboOptionDelta,
                    ),
                    style: PosText.mono(size: 14, color: pos.ink),
                  ),
                ),
                IconButton(
                  key: Key('combo-option-remove-$index-$o'),
                  tooltip: strings.comboRemove,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    group.options.removeAt(o).delta.dispose();
                    _error = null;
                  }),
                ),
              ],
            ),
          TextButton(
            key: Key('combo-add-option-$index'),
            onPressed: () => setState(() {
              group.options.add(_OptionState(null, ''));
              _error = null;
            }),
            child: Text(strings.comboAddOption),
          ),
        ],
      ),
    );
  }
}
