import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import 'admin_pane_bits.dart';

/// Settings › This terminal › Language & appearance.
///
/// **The card General shows, on its own.** Two ways to one control rather
/// than the control moved: plan 19 puts appearance on General (the mockup's
/// card) and in a side-nav row of its own (the cloud's grouping). Somebody who
/// looks for the language under a heading that names it should find it there,
/// not be sent to General to scroll past the restaurant's address.
class ManagementAppearancePane extends StatelessWidget {
  const ManagementAppearancePane({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(PosSpace.xl),
    children: const [TerminalAppearanceCard()],
  );
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
  const TerminalAppearanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final language = ref.watch(localeProvider).languageCode;
    final brightness = ref.watch(brightnessProvider);

    return SettingsCard(
      key: const Key('general-appearance'),
      title: strings.settingsAppearance,
      hint: strings.appearanceThisTerminal,
      children: [
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
        const SizedBox(height: PosSpace.lg),
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
                onTap: () => ref.read(brightnessProvider.notifier).apply(choice),
              ),
          ],
        ),
        const SizedBox(height: PosSpace.sm),
        Text(
          strings.themeSystemHint,
          style: PosText.ui(size: 12, color: context.pos.muted, height: 1.5),
        ),
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
