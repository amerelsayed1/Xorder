import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  static final _arabic = RegExp(r'[\u0600-\u06FF]');

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.pos.muted;
    // Arabic has no capitals, and must not be letter-spaced: tracking pulls a
    // joined word apart into letters. It is set in the Arabic face, too — the
    // mono has no Arabic at all, so it fell back to whatever the system had.
    if (_arabic.hasMatch(text)) {
      return Text(
        text,
        style: PosText.ui(size: 11.5, weight: FontWeight.w600, color: color),
      );
    }
    return Text(text.toUpperCase(), style: PosText.microLabel(color: color));
  }
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
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.autofocus = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Whether the pad takes the keyboard as soon as it appears.
  ///
  /// True everywhere except where something else on the screen is asked for
  /// first — the lock screen's username field, which would otherwise never see
  /// a keystroke.
  final bool autofocus;

  /// Both rows of digits a keyboard has.
  ///
  /// A till has a number pad on the right of its keyboard; a laptop has only
  /// the row above the letters. They are the same key to the person pressing
  /// them. Not `const`, because a const map cannot be keyed on a class that
  /// overrides `==`, and `LogicalKeyboardKey` does.
  static final Map<LogicalKeyboardKey, String> _digits = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];

    // **Typed as well as tapped.** The keys on screen are for the touch screen
    // this ships on; the keyboard is what an installer, a manager at a desk and
    // anybody testing actually reach for, and a keypad that ignored them read
    // as a dialog that had frozen.
    //
    // `KeyDownEvent` only. Handling every event would enter a digit on press
    // and again on release, and a held key would fill the PIN with one number.
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (_digits[event.logicalKey] case final digit?) {
          onDigit(digit);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete) {
          onBackspace();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: context.pos.shellLine,
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          // Keys are [PosSize.pinKey] tall when the pad is [PosSize.pinPad]
          // wide, and scale with whatever width they are actually given — so
          // a caller that wants the design size gives the pad that width.
          childAspectRatio: PosSize.pinPad / 3 / PosSize.pinKey,
          physics: const NeverScrollableScrollPhysics(),
          children: keys.map((key) => _key(context, key)).toList(),
        ),
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

/// A text box on the shell: one frame, and only one.
///
/// **All three borders, stated.** `border: InputBorder.none` alone switches off
/// the default and nothing else — the theme's `enabledBorder` and
/// `focusedBorder` still apply, and a box wrapped in its own frame then drew a
/// heavy ink outline inside the thin one, orange when focused.
InputDecoration shellInputDecoration(
  PosPalette pos, {
  String? hintText,
  TextStyle? hintStyle,
}) {
  final resting = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: pos.shellBorder,
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: pos.shellCard,
    hintText: hintText,
    hintStyle: hintStyle,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: PosSpace.md,
      vertical: PosSpace.md,
    ),
    border: resting,
    enabledBorder: resting,
    disabledBorder: resting,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: pos.accent, width: 2),
    ),
  );
}

/// The name of the person taking the till, above a PIN pad.
///
/// Mono, like every other identifier in this product, and autofocused because
/// it is the first thing asked for — a keypad that took digits while the name
/// was still empty would refuse every PIN and say nothing about why.
class UsernameField extends StatelessWidget {
  const UsernameField({
    required this.controller,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;

  /// Enter, which on a keyboard means "done with this field". Without it the
  /// only way from the name to the keypad is the mouse.
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MicroLabel(context.strings.username),
      const SizedBox(height: PosSpace.sm),
      TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => onSubmitted?.call(),
        textAlign: TextAlign.center,
        style: PosText.mono(size: 16, color: context.pos.shellText),
        cursorColor: context.pos.accent,
        decoration: shellInputDecoration(
          context.pos,
          hintStyle: PosText.mono(size: 16, color: context.pos.shellMuted),
        ),
      ),
    ],
  );
}
