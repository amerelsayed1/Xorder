import 'package:flutter/material.dart';

import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';

/// The three pieces every editor pane in this directory repeats.
///
/// Extracted when the Money pane was unpicked into three. Each of them had
/// carried a private copy — which is fine at one and a lie at three, because the
/// second copy diverges the first time somebody adjusts padding in one place.

/// A percentage box. Stored as basis points; shown as a percent because that is
/// what a restaurant says out loud.
class RateBox extends StatelessWidget {
  const RateBox({
    required this.controller,
    required this.label,
    this.boxKey,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final Key? boxKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(label),
      const SizedBox(height: PosSpace.sm),
      Row(
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              key: boxKey,
              controller: controller,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: PosText.mono(size: 15, color: context.pos.ink),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Text('%', style: PosText.mono(size: 15, color: context.pos.muted)),
        ],
      ),
    ],
  );
}

/// A sentence in the middle of an empty pane.
class PaneMessage extends StatelessWidget {
  const PaneMessage({required this.text, super.key});

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

/// The strip that says a setting is not this terminal's to change.
class PlatformOwnedNotice extends StatelessWidget {
  const PlatformOwnedNotice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(PosSpace.md),
    color: context.pos.warnSoft,
    child: Text(
      text,
      style: PosText.ui(size: 12.5, color: context.pos.warn, height: 1.5),
    ),
  );
}

/// A heading and a sentence over a list.
class PaneSection extends StatelessWidget {
  const PaneSection({required this.title, required this.hint, super.key});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(title),
      const SizedBox(height: PosSpace.xs),
      Text(hint, style: PosText.ui(size: 12.5, color: context.pos.muted)),
      const SizedBox(height: PosSpace.md),
    ],
  );
}

/// One section of Settings › General under the company form: a heading, a
/// sentence, and its controls, framed (BO-8).
///
/// A border and no fill, because elevation is a border here and a tinted tile
/// is the one thing the design system rules out (`07-design-system.md` §1).
/// Capped at 420 — the form's own field width — so the cards line up under
/// the boxes above them rather than running to the edge of a wide screen.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    required this.title,
    required this.hint,
    required this.children,
    super.key,
  });

  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        // No colour, not even the surface's: a filled box between a
        // `SwitchListTile` and its Material hides the tile's own ink, and
        // Flutter asserts on it.
        decoration: BoxDecoration(
          border: Border.fromBorderSide(context.pos.resting),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [PaneSection(title: title, hint: hint), ...children],
        ),
      ),
    ),
  );
}
