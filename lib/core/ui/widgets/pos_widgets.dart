import 'package:flutter/material.dart';

import '../tokens.dart';
import '../theme.dart';

/// A bordered surface. Elevation in this design is a border, never a shadow,
/// so this replaces `Card` almost everywhere.
class PosSurface extends StatelessWidget {
  const PosSurface({
    super.key,
    required this.child,
    this.color = PosColors.surface,
    this.border,
    this.padding,
    this.width,
    this.height,
  });

  final Widget child;
  final Color color;
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
          color: color,
          border: border ?? const Border.fromBorderSide(PosBorders.resting),
        ),
        child: child,
      );
}

/// The uppercase mono micro-label used above every section.
class MicroLabel extends StatelessWidget {
  const MicroLabel(this.text, {super.key, this.color = PosColors.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: PosText.microLabel(color: color));
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
          border: onShell ? null : const Border.fromBorderSide(PosBorders.resting),
        ),
        child: Text(
          label,
          style: PosText.mono(
            size: 11,
            color: onShell ? Colors.white : PosColors.muted,
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
    this.foreground = PosColors.inkWarm,
    this.border,
    this.trailing,
    this.fontSize = 13.5,
    this.fontWeight = FontWeight.w600,
    this.alignLeft = false,
    this.padding = const EdgeInsets.symmetric(horizontal: PosSpace.s14),
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final Color background;
  final Color foreground;
  final BoxBorder? border;
  final Widget? trailing;
  final double fontSize;
  final FontWeight fontWeight;
  final bool alignLeft;
  final EdgeInsetsGeometry padding;

  Widget _label() => Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: PosText.ui(size: fontSize, weight: fontWeight, color: foreground),
      );

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onPressed,
          // The theme's global hover tint (accentSoft) is right on a light
          // ground and wrong on a filled button — it washes an accent or green
          // CTA out to cream. A filled button darkens instead.
          hoverColor: background == Colors.transparent
              ? PosColors.accentSoft
              : Colors.black.withValues(alpha: 0.10),
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
                      Flexible(child: _label()),
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
                      _label(),
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
class SyncPill extends StatelessWidget {
  const SyncPill({super.key, required this.online, required this.queued, this.onTap});

  final bool online;
  final int queued;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = online ? '● Synced · $queued queued' : '● Offline · $queued queued';

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: online ? PosColors.onlinePillBg : PosColors.offlinePillBg,
          border: Border.all(
            color: online ? PosColors.onlinePillBorder : PosColors.warn,
          ),
        ),
        child: Text(
          label,
          style: PosText.mono(
            size: 11.5,
            color: online ? PosColors.onlinePillText : PosColors.offlinePillText,
          ),
        ),
      ),
    );
  }
}

/// Shows a toast in the design's language — flat, dark, no radius.
void posToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      width: 420,
    ));
}

/// Four PIN slots, filled as digits arrive.
///
/// Lives here rather than on the lock screen because signing in to open a shift
/// asks the same question in the same shape. Two keypads that drift apart is how
/// a cashier learns that "the one on the other screen works differently".
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.of = 4});

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
              color: PosColors.shellCard,
              border: Border(
                bottom: BorderSide(
                  color: filled ? PosColors.accent : PosColors.shellLine,
                  width: 2,
                ),
              ),
            ),
            child: filled
                ? Text('•', style: PosText.mono(size: 26, color: PosColors.shellText))
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
      color: PosColors.shellLine,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 320 / 3 / PosSize.pinKey,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map(_key).toList(),
      ),
    );
  }

  Widget _key(String label) {
    if (label.isEmpty) return const ColoredBox(color: PosColors.shellRow);

    final isBackspace = label == '⌫';
    return Material(
      color: isBackspace ? PosColors.shellRow : PosColors.shellCard,
      child: InkWell(
        onTap: () => isBackspace ? onBackspace() : onDigit(label),
        child: Center(
          child: Text(
            label,
            style: PosText.mono(
              size: 21,
              color: isBackspace ? PosColors.shellMuted : PosColors.shellText,
            ),
          ),
        ),
      ),
    );
  }
}
