import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import 'pos_widgets.dart';

/// How loudly a failure or queue state speaks.
///
/// **The colour law: an offline till is a healthy till.** `danger` is reserved
/// for a till that has stopped, or an act that was refused. Being offline,
/// holding a queue, or approaching a licence expiry are all `warn` — they are
/// conditions a business trades through every day, and colouring them like an
/// outage teaches cashiers to ignore red. Red has to keep meaning *stop*.
enum FailureTone {
  /// Working, with a condition worth knowing about.
  warn,

  /// Stopped, or refused.
  danger,
}

/// One failure or queue state, stated plainly with something to do about it.
///
/// Distinct from [SyncPill], which is not superseded: the pill is *status* and
/// lives permanently in the top bar, whereas a card is an *event* that appears
/// because something happened and leaves when it is resolved. Collapsing the
/// two would either put a permanent card on screen or hide an outage in a pill.
///
/// The card carries no copy of its own. Its strings come from `AppStrings` at
/// the call site, in the cashier's language — a core widget with English baked
/// into it is a widget that cannot ship to an Arabic till.
class FailureCard extends StatelessWidget {
  const FailureCard({
    super.key,
    required this.tone,
    required this.kicker,
    required this.title,
    required this.detail,
    this.actions = const [],
    this.shortcutKey,
    this.onDismiss,
  });

  final FailureTone tone;

  /// The state, in one word — `QUEUED`, `BLOCKED`, `OFFLINE`, `NOTICE`,
  /// `REJECTED`. Rendered as a mono micro-label on a soft ground.
  final String kicker;

  /// What happened, in the words the person would use. Not an error code.
  final String title;

  /// What it means and what is safe. This is where the card earns its space:
  /// *"nothing entered is lost"* is the sentence that stops a cashier
  /// re-entering an order they already have.
  final String detail;

  /// What can be done about it. Empty for a card that is purely informational.
  final List<FailureAction> actions;

  /// Shown right-aligned in the header — `F5` on a retryable failure.
  final String? shortcutKey;

  /// Non-null makes the card dismissible.
  ///
  /// **Only notice-level cards may be dismissible.** A failed kitchen print
  /// that can be waved away is a failed kitchen print nobody resolves, and the
  /// whole reason the record exists is that a silent dismiss is how a round
  /// stops being cooked without anybody noticing. `Mark handled` is an action
  /// with a name against it, not a dismiss.
  final VoidCallback? onDismiss;

  Color _tone(PosPalette palette) =>
      tone == FailureTone.danger ? palette.danger : palette.warn;

  Color _toneSoft(PosPalette palette) =>
      tone == FailureTone.danger ? palette.dangerSoft : palette.warnSoft;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final tint = _tone(palette);

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: PosSpace.s14,
        horizontal: PosSpace.lg,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: tint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(palette, tint),
          const SizedBox(height: PosSpace.s10),
          Text(
            detail,
            style: PosText.ui(size: 13.5, color: palette.body, height: 1.6),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: PosSpace.s10),
            Wrap(
              spacing: PosSpace.sm,
              runSpacing: PosSpace.sm,
              children: [
                for (final action in actions)
                  PosButton(
                    label: action.label,
                    onPressed: action.onPressed,
                    height: PosSize.minTouchTarget,
                    foreground: palette.inkWarm,
                    border: Border.fromBorderSide(palette.resting),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(PosPalette palette, Color tint) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(width: 10, height: 10, color: tint),
      const SizedBox(width: PosSpace.s10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: _toneSoft(palette),
        child: MicroLabel(kicker, color: tint),
      ),
      const SizedBox(width: PosSpace.s10),
      Expanded(
        child: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: PosText.ui(
            size: 15,
            weight: FontWeight.w800,
            color: palette.inkWarm,
          ),
        ),
      ),
      if (shortcutKey != null) ...[
        const SizedBox(width: PosSpace.sm),
        KeyChip(shortcutKey!),
      ],
      if (onDismiss != null) ...[
        const SizedBox(width: PosSpace.sm),
        IconButton(
          onPressed: onDismiss,
          iconSize: 18,
          splashRadius: 18,
          color: palette.muted,
          icon: const Icon(Icons.close),
        ),
      ],
    ],
  );
}

/// One thing that can be done about a failure.
class FailureAction {
  const FailureAction({required this.label, required this.onPressed});

  final String label;

  /// Never null. An action nobody can take is not an action, and rendering a
  /// dead button beside an outage is how a person stops trusting the buttons.
  final VoidCallback onPressed;
}
