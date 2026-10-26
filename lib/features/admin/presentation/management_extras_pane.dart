import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/destructive_confirm_dialog.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/catalog.dart';
import '../../../domain/models/content_languages.dart';
import '../../../domain/models/option_group.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import 'admin_messages.dart';
import 'menu_editor_widgets.dart';

/// The Extras library: size and extra groups written once and used on many
/// items.
///
/// **The cloud dashboard's Extras page, field for field** (`ExtrasView.vue`),
/// because the owner's instruction is that the desktop back office is the
/// same as the cloud one. Where this differs it says so where it does.
///
/// **Offline only**, like the Menu pane: on a cloud till the platform authors
/// the catalogue and the bootstrap seeder rewrites this database's copy, so a
/// group made here would last until the next sync.
class ManagementExtrasPane extends ConsumerStatefulWidget {
  const ManagementExtrasPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementExtrasPane> createState() =>
      _ManagementExtrasPaneState();
}

class _ManagementExtrasPaneState extends ConsumerState<ManagementExtrasPane> {
  /// Held rather than a provider: nothing else on the till lists the library,
  /// and a `FutureProvider` would need invalidating from both panes that write
  /// it. Reloaded after every write here; the item editor reads its own.
  Future<List<LibraryGroup>>? _library;

  void _reload(CatalogAdminRepository repository) {
    setState(() {
      _library = repository.optionLibrary();
    });
    // The till sells from `catalogProvider`, which nothing else refreshes
    // offline — see the Menu pane's `_write`.
    ref.invalidate(catalogProvider);
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(catalogAdminRepositoryProvider);
    final strings = context.strings;
    if (repository == null) {
      return _Centred(text: strings.menuComesFromPlatform);
    }
    _library ??= repository.optionLibrary();

    // For the category picker. Watched at pane level for the reason the Menu
    // pane watches its rates: a `read` when the dialog opens finds nothing.
    final categories =
        ref.watch(catalogProvider).valueOrNull?.categories ??
        const <Category>[];

    return Column(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.extrasTitle,
                      style: PosText.panelTitle(color: context.pos.ink),
                    ),
                    const SizedBox(height: PosSpace.xs),
                    Text(
                      strings.extrasSubtitle,
                      style: PosText.ui(size: 13, color: context.pos.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PosSpace.lg),
              PosButton(
                key: const Key('extras-new'),
                label: '+ ${strings.extrasNew}',
                background: context.pos.ink,
                foreground: context.pos.onInk,
                onPressed: () => _edit(repository, null, categories),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<LibraryGroup>>(
            future: _library,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _Centred(text: '${snapshot.error}');
              }
              final rows = snapshot.data;
              if (rows == null) {
                return Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.pos.accent,
                  ),
                );
              }
              if (rows.isEmpty) return _Centred(text: strings.extrasNone);
              return ListView(
                children: [
                  for (final row in rows)
                    _Row(
                      entry: row,
                      onEdit: () => _edit(repository, row.group, categories),
                      onDelete: () => _delete(repository, row),
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
    OptionGroupDraft? existing,
    List<Category> categories,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ExtraDialog(
        group: existing,
        categories: categories,
        languages: ref.read(contentLanguagesNowProvider),
        onSave: (group) async =>
            (await repository.saveOptionGroup(group, by: widget.admin))
                .refusal,
      ),
    );
    if (saved == true && mounted) _reload(repository);
  }

  Future<void> _delete(
    CatalogAdminRepository repository,
    LibraryGroup entry,
  ) async {
    final strings = context.strings;
    // The count is the whole warning: "used by 12 items" is what stops the
    // owner who thought they were tidying up an unused group.
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: entry.itemCount > 0
          ? strings.extrasDeleteWarning(entry.itemCount)
          : strings.deleteConfirmGeneric,
      confirmLabel: strings.deleteLabel,
      keepLabel: strings.cancel,
      requirement: ReasonRequirement.disabled,
    );
    if (confirmed == null || !mounted) return;

    final result = await repository.deleteOptionGroup(
      entry.group,
      by: widget.admin,
    );
    if (!mounted) return;
    final refusal = result.refusal;
    if (refusal != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminText.refusal(context.strings, refusal))),
      );
      return;
    }
    _reload(repository);
  }
}

/// One library group in the list.
class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final LibraryGroup entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    final group = entry.group;
    final name = groupName(group, s.languageCode);
    final shown = _menuName(group, s.languageCode);
    // Accent when it reaches something, as the cloud colours it: "Not used
    // yet" is the one summary that should not catch the eye.
    final reaches = group.scope != OptionGroupScope.items || entry.itemCount > 0;

    return Container(
      key: Key('extra-row-${group.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.xl,
        vertical: PosSpace.md,
      ),
      decoration: BoxDecoration(border: Border(bottom: pos.hairline)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            color: pos.accentSoft,
            alignment: Alignment.center,
            child: Icon(
              group.isVariant ? Icons.restaurant : Icons.add,
              size: 18,
              color: pos.accent,
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: PosText.ui(
                    size: 14,
                    weight: FontWeight.w600,
                    color: pos.ink,
                  ),
                ),
                if (shown != null)
                  Text(
                    s.extrasShownAs(shown),
                    style: PosText.ui(size: 12, color: pos.muted),
                  ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${s.extrasOptionsSummary(group.options.length)} · ',
                      ),
                      TextSpan(
                        text: scopeSummary(s, entry),
                        style: reaches ? TextStyle(color: pos.accent) : null,
                      ),
                    ],
                  ),
                  key: Key('extra-summary-${group.id}'),
                  style: PosText.ui(size: 12, color: pos.muted),
                ),
              ],
            ),
          ),
          if (group.isVariant) MenuPill(s.itemVariant),
          IconButton(
            key: Key('extra-edit-${group.id}'),
            icon: const Icon(Icons.edit_outlined, size: 16),
            tooltip: s.edit,
            onPressed: onEdit,
          ),
          IconButton(
            key: Key('extra-delete-${group.id}'),
            icon: Icon(Icons.delete_outline, size: 16, color: pos.danger),
            tooltip: s.deleteLabel,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Where a library group applies, in the words of its list row.
///
/// Enum-keyed, so a fourth scope is a compile error here rather than a row
/// that says nothing.
String scopeSummary(AppStrings s, LibraryGroup entry) =>
    switch (entry.group.scope) {
      OptionGroupScope.all => s.extrasScopeAll,
      OptionGroupScope.categories => s.extrasAppliesCategories(
        entry.group.categoryIds.length,
      ),
      OptionGroupScope.items =>
        entry.itemCount > 0 ? s.extrasUsedBy(entry.itemCount) : s.extrasNotUsed,
    };

/// A group's library name in [languageCode], falling back to the other one.
String groupName(OptionGroupDraft group, String languageCode) {
  final arabic = group.nameAr;
  if (languageCode == 'ar' && arabic != null && arabic.isNotEmpty) {
    return arabic;
  }
  return group.nameEn.isNotEmpty ? group.nameEn : (arabic ?? '');
}

/// What a diner reads above the choices, when it differs from the library
/// name — repeating an identical string under every row would be noise.
String? _menuName(OptionGroupDraft group, String languageCode) {
  final own = languageCode == 'ar' ? group.displayNameAr : group.displayNameEn;
  final other = languageCode == 'ar' ? group.displayNameEn : group.displayNameAr;
  final shown = (own != null && own.isNotEmpty) ? own : other;
  if (shown == null || shown.isEmpty) return null;
  return shown == groupName(group, languageCode) ? null : shown;
}

/// Add or edit a library group.
///
/// **Saves itself, and stays open on a refusal.** The other menu dialogs pop
/// and let the pane write, which loses nothing when all there is to lose is a
/// name. Here it would be a group of eight options typed by hand, thrown away
/// because one sale price was above its price — so the refusal is said in the
/// dialog, the way the cloud leaves its form open with the error under it.
class _ExtraDialog extends StatefulWidget {
  const _ExtraDialog({
    required this.group,
    required this.categories,
    required this.onSave,
    required this.languages,
  });

  final OptionGroupDraft? group;
  final List<Category> categories;

  /// Which names the restaurant writes its content in (XORD-005).
  final ContentLanguages languages;
  final Future<AdminRefusal?> Function(OptionGroupDraft group) onSave;

  @override
  State<_ExtraDialog> createState() => _ExtraDialogState();
}

class _ExtraDialogState extends State<_ExtraDialog> {
  late final _group = widget.group == null
      ? EditableGroup.blank()
      : EditableGroup.from(widget.group!);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _save() async {
    final strings = context.strings;
    final (:draft, :error) = _group.toDraft(
      strings,
      languages: widget.languages,
    );
    if (draft == null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final refusal = await widget.onSave(draft);
    if (!mounted) return;
    if (refusal != null) {
      setState(() {
        _saving = false;
        _error = AdminText.refusal(strings, refusal);
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    final hint = PosText.ui(size: 11.5, color: pos.muted, height: 1.4);

    Widget scopeButton(OptionGroupScope scope, String label) => PosButton(
      key: Key('extras-scope-${scope.wire}'),
      label: label,
      height: 36,
      background: _group.scope == scope ? pos.ink : Colors.transparent,
      foreground: _group.scope == scope ? pos.onInk : null,
      border: Border.fromBorderSide(pos.resting),
      onPressed: () => setState(() => _group.scope = scope),
    );

    return MenuDialog(
      title: widget.group == null ? s.extrasNew : s.extrasEdit,
      error: _error,
      saving: _saving,
      maxWidth: 680,
      onSave: _save,
      children: [
        // Two names, because one string cannot do both jobs: the library is
        // browsed by an owner with dozens of groups, the heading is read by
        // somebody choosing.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.languages.showsEnglish)
              Expanded(
                child: MenuInput(
                  fieldKey: const Key('extras-name'),
                  controller: _group.nameEn,
                  label: s.extrasLibraryNameEn,
                  hint: s.itemGroupNameEn,
                  onChanged: (_) => _changed(),
                ),
              ),
            if (widget.languages == ContentLanguages.both)
              const SizedBox(width: PosSpace.md),
            if (widget.languages.showsArabic)
              Expanded(
                child: MenuInput(
                  fieldKey: const Key('extras-name-ar'),
                  controller: _group.nameAr,
                  label: s.extrasLibraryNameAr,
                  hint: s.itemGroupNameAr,
                  arabic: true,
                  onChanged: (_) => _changed(),
                ),
              ),
          ],
        ),
        const SizedBox(height: PosSpace.xs),
        Text(s.extrasLibraryNameHint, style: hint),
        const SizedBox(height: PosSpace.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.languages.showsEnglish)
              Expanded(
                child: MenuInput(
                  fieldKey: const Key('extras-heading'),
                  controller: _group.displayEn,
                  label: s.extrasMenuNameEn,
                  hint: _placeholder(_group.nameEn.text, s),
                ),
              ),
            if (widget.languages == ContentLanguages.both)
              const SizedBox(width: PosSpace.md),
            if (widget.languages.showsArabic)
              Expanded(
                child: MenuInput(
                  fieldKey: const Key('extras-heading-ar'),
                  controller: _group.displayAr,
                  label: s.extrasMenuNameAr,
                  hint: _placeholder(_group.nameAr.text, s),
                  arabic: true,
                ),
              ),
          ],
        ),
        const SizedBox(height: PosSpace.xs),
        Text(s.extrasMenuNameHint, style: hint),
        const SizedBox(height: PosSpace.lg),
        GroupRulesRow(
          group: _group,
          keyPrefix: 'extras',
          onVariant: (v) {
            _group.isVariant = v;
            _changed();
          },
          onChanged: _changed,
        ),
        const SizedBox(height: PosSpace.lg),
        MicroLabel(s.extrasApplyTo),
        const SizedBox(height: PosSpace.sm),
        Wrap(
          spacing: PosSpace.sm,
          runSpacing: PosSpace.sm,
          children: [
            scopeButton(OptionGroupScope.all, s.extrasScopeAll),
            scopeButton(OptionGroupScope.categories, s.extrasScopeCategories),
            scopeButton(OptionGroupScope.items, s.extrasScopeItems),
          ],
        ),
        const SizedBox(height: PosSpace.sm),
        if (_group.scope == OptionGroupScope.items)
          Text(s.extrasScopeItemsHint, style: hint)
        else if (_group.scope == OptionGroupScope.categories) ...[
          Text(s.extrasPickCategories, style: hint),
          const SizedBox(height: PosSpace.sm),
          Wrap(
            key: const Key('extras-categories'),
            spacing: PosSpace.sm,
            runSpacing: PosSpace.sm,
            children: [
              for (final category in widget.categories)
                _categoryChip(category, pos, s),
            ],
          ),
        ],
        const SizedBox(height: PosSpace.lg),
        OptionRows(
          group: _group,
          keyPrefix: 'extras',
          onChanged: _changed,
          languages: widget.languages,
        ),
      ],
    );
  }

  /// Selection is a border here, not a fill — the cloud's chip, drawn the way
  /// this design draws a chosen thing.
  Widget _categoryChip(Category category, PosPalette pos, AppStrings s) {
    final on = _group.categoryIds.contains(category.id);
    return PosButton(
      key: Key('extras-category-${category.id}'),
      label: category.displayName(s.languageCode),
      height: 36,
      background: on ? pos.accentSoft : Colors.transparent,
      foreground: on ? pos.accent : null,
      border: Border.fromBorderSide(on ? pos.accentBorder : pos.resting),
      onPressed: () => setState(() {
        if (!_group.categoryIds.remove(category.id)) {
          _group.categoryIds.add(category.id);
        }
      }),
    );
  }

  /// The heading's placeholder is the library name, so a blank heading shows
  /// what it will fall back to; before there is a name, the cloud's example.
  static String _placeholder(String libraryName, AppStrings s) =>
      libraryName.trim().isEmpty ? s.extrasMenuNamePlaceholder : libraryName;
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
