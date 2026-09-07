import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../tokens.dart';
import '../theme.dart';
import '../../security/pin_hash.dart';

/// A bordered surface. Elevation in this design is a border, never a shadow,
/// so this replaces `Card` almost everywhere.
class PosSurface extends StatelessWidget {
  const PosSurface({
    super.key,
    required this.child,
    this.color,
    this.border,
    this.padding,
    this.width,
    this.height,
  });

  final Widget child;

  /// Null means "the palette's surface". Resolved in [build], where there is a
  /// context to resolve it against — a const constructor has none.
  final Color? color;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.pos.surface,
      border: border ?? Border.fromBorderSide(context.pos.resting),
    ),
    child: child,
  );
}

/// The uppercase mono micro-label used above every section.
class MicroLabel extends StatelessWidget {
  const MicroLabel(this.text, {super.key, this.color});

  final String text;

  /// Null means "the palette's muted". See [PosSurface.color].
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: PosText.microLabel(color: color ?? context.pos.muted),
  );
}

/// A keyboard-hint chip — the `F2` next to the search field, `ENTER` on a CTA.
class KeyChip extends StatelessWidget {
  const KeyChip(this.label, {super.key, this.onShell = false});

  final String label;

  /// On the dark shell the chip sits on a translucent black rather than a border.
  final bool onShell;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: onShell ? const Color(0x38000000) : null,
      border: onShell ? null : Border.fromBorderSide(context.pos.resting),
    ),
    child: Text(
      label,
      style: PosText.mono(
        size: 11,
        color: onShell ? Colors.white : context.pos.muted,
      ),
    ),
  );
}

/// A flat, radius-free, shadow-free button. Used instead of the Material
/// buttons wherever the design specifies an exact height and a flush-left label.
class PosButton extends StatelessWidget {
  const PosButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height = PosSize.minTouchTarget,
    this.background = Colors.transparent,
    this.foreground,
    this.border,
    this.trailing,
    this.fontSize = 13.5,
    this.fontWeight = FontWeight.w600,
    this.alignLeft = false,
    this.padding = const EdgeInsets.symmetric(horizontal: PosSpace.s14),
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final Color background;

  /// Null means "the palette's inkWarm". See [PosSurface.color].
  final Color? foreground;
  final BoxBorder? border;
  final Widget? trailing;
  final double fontSize;
  final FontWeight fontWeight;
  final bool alignLeft;
  final EdgeInsetsGeometry padding;

  /// Take focus when this button first appears.
  ///
  /// Off by default, because a screen that grabs focus moves the keyboard out
  /// from under whoever was typing. It exists for the one case that needs it:
  /// a dialog about an irreversible act puts focus on the **safe** button, so
  /// the choice already under the person's hands is the one that changes
  /// nothing. See `DestructiveConfirmDialog`.
  final bool autofocus;

  Widget _label(Color foreground) => Text(
    label,
    overflow: TextOverflow.ellipsis,
    style: PosText.ui(size: fontSize, weight: fontWeight, color: foreground),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final ink = foreground ?? context.pos.inkWarm;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onPressed,
          autofocus: autofocus,
          child: Container(
            height: height,
            padding: padding,
            decoration: BoxDecoration(border: border),
            // Two layouts, because this button is used both inside the
            // horizontally-scrolling top bar (unbounded width, so no child may
            // flex) and as a full-width CTA (bounded, label flush left with the
            // key chip pushed right).
            child: alignLeft
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: _label(ink)),
                      if (trailing != null) ...[
                        const SizedBox(width: PosSpace.sm),
                        trailing!,
                      ],
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Flexible, like the flush-left branch above. Without it
                      // the label asks for its natural width inside a Row that
                      // cannot give it, and `TextOverflow.ellipsis` above never
                      // gets the chance to fire — a button whose label is a
                      // little too long overflows instead of shortening. That
                      // is not hypothetical: a confirm button states an amount,
                      // and amounts get longer.
                      Flexible(child: _label(ink)),
                      if (trailing != null) ...[
                        const SizedBox(width: PosSpace.sm),
                        trailing!,
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Status pill for the sync state in the top bar.
///
/// **Only a cloud terminal has a sync state.** An offline till owes its sales
/// to nobody, so a pill telling its operator they are "offline · 0 queued"
/// announces a permanent, intended condition as though it were a fault — and
/// the counter beside it can only ever read zero. [BranchServerPill] is what an
/// offline terminal shows instead.
class SyncPill extends StatelessWidget {
  const SyncPill({
    super.key,
    required this.online,
    required this.queued,
    this.hasError = false,
    this.onTap,
  });

  final bool online;
  final int? queued;
  final bool hasError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final label = switch ((online, queued, hasError)) {
      (_, _, true) => strings.syncStatusUnavailable,
      (false, final int? count, false) => strings.syncOfflineQueued(count),
      (true, null, false) => strings.syncChecking,
      (true, final int count, false) => strings.syncSyncedQueued(count),
    };

    return _StatusPill(
      label: label,
      healthy: online && !hasError,
      onTap: onTap,
    );
  }
}

/// Status pill for an **offline** terminal.
///
/// It reports the one thing that can actually stop this till selling: whether
/// the branch server is answering. Quiet when it is — a healthy till should not
/// be wearing a status light — and a warning when it is not.
class BranchServerPill extends StatelessWidget {
  const BranchServerPill({
    super.key,
    required this.checking,
    required this.reachable,
    this.onTap,
  });

  /// The first probe has not come back yet.
  final bool checking;

  final bool reachable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _StatusPill(
      label: checking
          ? strings.branchDatabaseChecking
          : reachable
          ? strings.branchDatabaseReady
          : strings.branchDatabaseUnreachable,
      healthy: checking || reachable,
      onTap: onTap,
    );
  }
}

/// The chrome both pills share, so a status never changes shape by which
/// deployment mode drew it.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.healthy,
    this.onTap,
  });

  final String label;
  final bool healthy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: healthy
            ? context.pos.onlinePillBg
            : context.pos.offlinePillBg,
        border: Border.all(
          color: healthy ? context.pos.onlinePillBorder : context.pos.warn,
        ),
      ),
      child: Text(
        label,
        style: PosText.mono(
          size: 11.5,
          color: healthy
              ? context.pos.onlinePillText
              : context.pos.offlinePillText,
        ),
      ),
    ),
  );
}

/// Shows a toast in the design's language — flat, dark, no radius.
void posToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        width: 420,
      ),
    );
}

/// Four PIN slots, filled as digits arrive.
///
/// Lives here rather than on the lock screen because signing in to open a shift
/// asks the same question in the same shape. Two keypads that drift apart is how
/// a cashier learns that "the one on the other screen works differently".
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.of = PinRules.length});

  final int length;
  final int of;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(of, (i) {
      final filled = i < length;
      return Container(
        width: 52,
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: PosSpace.xs),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.pos.shellCard,
          border: Border(
            bottom: BorderSide(
              color: filled ? context.pos.accent : context.pos.shellLine,
              width: 2,
            ),
          ),
        ),
        child: filled
            ? Text(
                '•',
                style: PosText.mono(size: 26, color: context.pos.shellText),
              )
            : null,
      );
    }),
  );
}

/// The numeric pad a PIN is entered on.
class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];

    return Container(
      color: context.pos.shellLine,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 320 / 3 / PosSize.pinKey,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((key) => _key(context, key)).toList(),
      ),
    );
  }

  Widget _key(BuildContext context, String label) {
    if (label.isEmpty) return ColoredBox(color: context.pos.shellRow);

    final isBackspace = label == '⌫';
    return Material(
      color: isBackspace ? context.pos.shellRow : context.pos.shellCard,
      child: InkWell(
        onTap: () => isBackspace ? onBackspace() : onDigit(label),
        child: Center(
          child: Text(
            label,
            style: PosText.mono(
              size: 21,
              color: isBackspace ? context.pos.shellMuted : context.pos.shellText,
            ),
          ),
        ),
      ),
    );
  }
}
