import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/content_languages.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';

/// Which half of this terminal's appearance a pane shows.
enum AppearancePart { language, theme }

/// Settings › Language, and Settings › Appearance.
///
/// **The card General shows, one half at a time.** Two ways to one control
/// rather than the control moved: plan 19 puts appearance on General (the
/// mockup's card), and the owner's map (14 Sep 2026) gives language and
/// appearance an item each. Somebody who looks for the language under the
/// word that names it should find it there — not be sent to General to scroll
/// past the business's address, nor meet the theme first and wonder whether
/// they chose the wrong line.
class ManagementAppearancePane extends StatelessWidget {
  const ManagementAppearancePane({required this.part, this.admin, super.key});

  final AppearancePart part;

  /// Who is in the back office, for the menu-languages card (XORD-005). Null
  /// for a host that shows the terminal's own appearance only.
  final PosStaff? admin;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(PosSpace.xl),
    children: [
      TerminalAppearanceCard(only: part),
      if (part == AppearancePart.language && admin != null) ...[
        const SizedBox(height: PosSpace.lg),
        ContentLanguagesCard(admin: admin!),
      ],
    ],
  );
}

/// Which languages the MENU is written in (XORD-005) — categories, items and
/// the forms that ask for their names. Not the language this till is shown in:
/// that is the card above it.
///
/// An offline install authors it here, under `settings.manage`; a cloud till's
/// comes from the platform and is read-only, as its order types are.
class ContentLanguagesCard extends ConsumerStatefulWidget {
  const ContentLanguagesCard({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ContentLanguagesCard> createState() =>
      _ContentLanguagesCardState();
}

class _ContentLanguagesCardState extends ConsumerState<ContentLanguagesCard> {
  bool _busy = false;
  String? _problem;

  Future<void> _choose(ContentLanguages languages) async {
    final repository = ref.read(catalogAdminRepositoryProvider);
    if (repository == null || _busy) return;

    setState(() {
      _busy = true;
      _problem = null;
    });
    final result = await repository.saveContentLanguages(
      languages,
      by: widget.admin,
    );
    if (!mounted) return;

    setState(() {
      _busy = false;
      _problem = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });
    if (result.succeeded) ref.invalidate(contentLanguagesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final current = ref.watch(contentLanguagesNowProvider);
    final platformOwned = ref.watch(catalogAdminRepositoryProvider) == null;
    final mayChoose = widget.admin.can(PosCapability.settingsManage);
    final editable = !platformOwned && mayChoose && !_busy;

    return SettingsCard(
      key: const Key('content-languages'),
      title: strings.contentLanguagesTitle,
      hint: strings.contentLanguagesHint,
      children: [
        if (platformOwned)
          PlatformOwnedNotice(text: strings.contentLanguagesFromPlatform)
        else if (!mayChoose)
          PlatformOwnedNotice(text: strings.contentLanguagesNeedPermission),
        if (platformOwned || !mayChoose) const SizedBox(height: PosSpace.sm),
        _Choices(
          children: [
            for (final (value, label) in <(ContentLanguages, String)>[
              (ContentLanguages.arabic, strings.contentLanguagesArabic),
              (ContentLanguages.english, strings.contentLanguagesEnglish),
            ])
              _Choice(
                key: Key('content-language-${value.wire}'),
                label: label,
                selected: current == value,
                onTap: editable ? () => _choose(value) : () {},
              ),
          ],
        ),
        if (_problem != null) ...[
          const SizedBox(height: PosSpace.sm),
          Text(
            _problem!,
            style: PosText.ui(size: 12.5, color: context.pos.danger),
          ),
        ],
      ],
    );
  }
}

/// Which language and which theme this terminal shows.
///
/// **The Settings menu's own providers, so the two cannot disagree.**
/// `localeProvider` and `brightnessProvider` are what the bar flips, and both
/// write this terminal's config file — so a choice made here is the one the
/// menu then offers to reverse, and the one the till opens in tomorrow. A
/// second store for "the back office's preference" would be a till that
/// answers the same question two ways.
///
/// **Three themes where the menu has a toggle** (plan 19 §2.6). The menu flips
/// away from what is on screen, which is all a menu line can say. A toggle
/// here would lose "follow the machine" — the state every till is in until
/// somebody chooses — with no way back to it short of editing a file.
///
/// No gate: the menu lets anybody at the till switch language, and asking for
/// a capability to do the same thing one screen deeper would be a lock on an
/// open door.
class TerminalAppearanceCard extends ConsumerWidget {
  const TerminalAppearanceCard({this.only, super.key});

  /// One half, as Settings › Language and › Appearance each show it. Null for
  /// both, as General shows them.
  final AppearancePart? only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final language = ref.watch(localeProvider).languageCode;
    final brightness = ref.watch(brightnessProvider);

    return SettingsCard(
      key: const Key('general-appearance'),
      title: switch (only) {
        null => strings.settingsAppearance,
        AppearancePart.language => strings.settingsLanguage,
        AppearancePart.theme => strings.settingsLook,
      },
      hint: strings.appearanceThisTerminal,
      children: [
        if (only != AppearancePart.theme) ...[
          MicroLabel(strings.appearanceLanguage),
          const SizedBox(height: PosSpace.xs),
          _Choices(
            children: [
              // Each language named in itself, as the bar names them: somebody
              // who cannot read the one on screen still finds their own.
              for (final (code, name) in [
                ('en', const EnStrings().languageName),
                ('ar', const ArStrings().languageName),
              ])
                _Choice(
                  key: Key('appearance-language-$code'),
                  label: name,
                  selected: language == code,
                  onTap: () => ref.read(localeProvider.notifier).apply(code),
                ),
            ],
          ),
        ],
        if (only == null) const SizedBox(height: PosSpace.lg),
        if (only != AppearancePart.language) ...[
          MicroLabel(strings.appearanceTheme),
          const SizedBox(height: PosSpace.xs),
          _Choices(
            children: [
              for (final (name, choice, label) in <(String, Brightness?, String)>[
                ('system', null, strings.themeSystem),
                ('light', Brightness.light, strings.themeLight),
                ('dark', Brightness.dark, strings.themeDark),
              ])
                _Choice(
                  key: Key('appearance-theme-$name'),
                  label: label,
                  selected: brightness == choice,
                  onTap: () =>
                      ref.read(brightnessProvider.notifier).apply(choice),
                ),
            ],
          ),
          const SizedBox(height: PosSpace.sm),
          Text(
            strings.themeSystemHint,
            style: PosText.ui(size: 12, color: context.pos.muted, height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// A row of equal choices.
class _Choices extends StatelessWidget {
  const _Choices({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) const SizedBox(width: PosSpace.sm),
        Expanded(child: child),
      ],
    ],
  );
}

/// One of them. Chosen is an accent border and nothing else — no fill, no
/// hover, no radius (`07-design-system.md` §1): elevation is a border here,
/// so selection is one too.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: PosSize.formControl,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm),
          decoration: BoxDecoration(
            color: pos.surface,
            border: Border.fromBorderSide(
              selected ? pos.accentBorder : pos.resting,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: selected ? pos.accent : pos.muted,
              ),
              const SizedBox(width: PosSpace.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(
                    size: 13.5,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? pos.ink : pos.body,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
