import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';

/// The first thing anyone sees on a new till.
///
/// The official mark, not a wordmark rebuilt from Text and a Border. A drawn
/// approximation drifts from the brand the moment the brand moves, and this
/// screen is the one an installer photographs and a customer sees over the
/// counter before anything else exists.
///
/// It is also the only screen that honours light and dark. That is not an
/// oversight elsewhere: the rest of the app runs a FIXED palette — a light
/// body with a dark shell for the top bar, cart, start and lock screens —
/// chosen for a counter under bright light. Here there is no counter and no
/// shift, just a machine sitting in a room, so it follows the room.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, required this.onOpenSetup});

  final VoidCallback onOpenSetup;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _focus = FocusNode();

  /// **The tablet's way in: tap the mark twelve times.**
  ///
  /// The chord below is the only other door, and a tablet has no keyboard —
  /// so an Android till sat on this screen forever. Twelve rather than the
  /// usual seven because this is in front of customers: a child at the
  /// counter taps a logo five or six times, and nobody taps it twelve by
  /// accident. The count starts again after a pause, so twelve stray taps
  /// spread over a morning add up to nothing.
  static const _tapsToOpenSetup = 12;
  static const _tapPause = Duration(seconds: 2);

  int _logoTaps = 0;
  DateTime? _lastLogoTap;

  void _onLogoTap() {
    _focus.requestFocus();

    final now = DateTime.now();
    final last = _lastLogoTap;
    _lastLogoTap = now;
    _logoTaps = last != null && now.difference(last) < _tapPause
        ? _logoTaps + 1
        : 1;

    if (_logoTaps < _tapsToOpenSetup) return;
    _logoTaps = 0;
    widget.onOpenSetup();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the STATE, not the notifier: watching `.notifier` only rebuilds
    // when the notifier instance is replaced, so the toggle changed the value
    // and repainted nothing.
    final override = ref.watch(brightnessProvider);
    final showing = override ?? MediaQuery.platformBrightnessOf(context);
    final dark = showing == Brightness.dark;

    // The mark is orange on transparent and carries both grounds unaided, so
    // there is one asset rather than a light and a dark cut to keep in step.
    //
    // The GROUND no longer picks a side here. It used to — this screen chose
    // `shell` when dark and `surface` when light, because it was the only
    // screen that honoured a theme and each token had exactly one value. Now
    // the palette itself differs, so asking for `surface` is already asking
    // for the right one, and the values land where they always did: white on
    // light, #1C1712 on dark.
    final background = context.pos.surface;
    final caption = context.pos.muted;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): widget.onOpenSetup,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            widget.onOpenSetup,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: GestureDetector(
          // A click anywhere re-arms the shortcut if focus wandered — a mouse
          // user poking the screen must not disarm the only way in.
          onTap: _focus.requestFocus,
          behavior: HitTestBehavior.opaque,
          child: Scaffold(
            backgroundColor: background,
            body: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Fixed WIDTH, not height: the asset is 1348x376, and
                      // sizing by width keeps the mark the same size on screen
                      // regardless of what the aspect ratio does later.
                      GestureDetector(
                        onTap: _onLogoTap,
                        child: Image.asset(
                          'assets/icons/xorder_logo_official.png',
                          // Declared once, by the shared package (see its pubspec).
                          package: 'shared_module',
                          width: 280,
                          fit: BoxFit.contain,
                          // A missing asset must not paint a broken-image
                          // glyph across the first screen of a new install.
                          errorBuilder: (context, error, stack) => Text(
                            context.strings.productWordmark,
                            style: PosText.ui(
                              size: 40,
                              weight: FontWeight.w800,
                              color: context.pos.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: PosSpace.s28),
                      Text(
                        context.strings.terminalNotSetUp,
                        style: PosText.ui(size: 13.5, color: caption),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: PosSpace.xl,
                  right: PosSpace.xl,
                  child: _BrightnessToggle(
                    dark: dark,
                    onPressed: () =>
                        ref.read(brightnessProvider.notifier).toggle(showing),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one round thing in a zero-radius system, and deliberately so: it is a
/// chrome control rather than part of the till's own vocabulary, and reading
/// as chrome is what stops it looking like a button that sets something up.
class _BrightnessToggle extends StatelessWidget {
  const _BrightnessToggle({required this.dark, required this.onPressed});

  final bool dark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: dark
        ? context.strings.switchToLight
        : context.strings.switchToDark,
    child: Material(
      color: context.pos.page,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 20,
            color: context.pos.body,
          ),
        ),
      ),
    ),
  );
}
