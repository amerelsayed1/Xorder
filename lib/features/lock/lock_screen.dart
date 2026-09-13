import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../core/security/pin_hash.dart';

/// Lock screen — step away without closing the shift.
///
/// [PinRules.length] digits unlock. The comparison runs against the **cached**
/// hash so it works offline; the shift stays open throughout, and every overlay
/// is closed on lock.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onBack,
  });

  final VoidCallback onUnlocked;

  /// Leave for the start screen. Called after the screen has signed out.
  final VoidCallback onBack;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _username = TextEditingController();
  String _pin = '';
  bool _error = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _push(String digit) async {
    if (_pin.length >= PinRules.length) return;
    setState(() {
      _pin += digit;
      _error = false;
    });

    if (_pin.length == PinRules.length) {
      // Name AND PIN. A PIN alone is four digits that get shared, watched over
      // a shoulder and reused, and `signIn` hands the till to whichever active
      // member of staff happens to hold them — fine for approving a discount
      // somebody is standing over, not for taking over the drawer. Saying the
      // name first makes this check a claim instead of guessing an identity.
      //
      // `signIn`, not `verifyPin`: this screen is the handover. A till is
      // shared, and the person coming back to it is often not the one who
      // locked it — `verifyPin` only ever answered "does somebody who works
      // here know a PIN", so whoever unlocked went on selling under the name
      // and the capabilities of whoever had been standing there before.
      final staff = await ref
          .read(sessionRepositoryProvider)
          .signInAs(username: _username.text, pin: _pin);
      if (!mounted) return;

      if (staff != null) {
        ref.read(signedInStaffProvider.notifier).signIn(staff);
        widget.onUnlocked();
      } else {
        setState(() {
          _pin = '';
          _error = true;
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  /// Back to the start screen, signed out.
  ///
  /// Locking keeps whoever was at the till signed in — only closing the shift
  /// signs anybody out — so a way off this screen that kept them would hand
  /// the next person at the start screen their shift for one press of Enter.
  /// Signed out, resuming comes straight back here for a name and a PIN.
  void _back() {
    ref.read(signedInStaffProvider.notifier).signOut();
    widget.onBack();
  }

  // Esc from anywhere on the screen, the username field included: a half-typed
  // name and PIN are nothing to lose.
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
    child: _screen(context),
  );

  Widget _screen(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      backgroundColor: context.pos.shell,
      body: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.terminalLocked,
                textAlign: TextAlign.center,
                style: PosText.mono(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: context.pos.shellMuted,
                  letterSpacing: 2.5,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: PosSpace.xl),
                child: ColoredBox(
                  color: context.pos.accent,
                  child: SizedBox(height: 2),
                ),
              ),
              Text(
                _error ? strings.wrongUsernameOrPin : strings.enterYourPin,
                textAlign: TextAlign.center,
                style: PosText.ui(
                  size: 20,
                  weight: FontWeight.w800,
                  color: _error
                      ? context.pos.offlinePillText
                      : context.pos.shellText,
                ),
              ),
              const SizedBox(height: PosSpace.s24),
              // Above the keypad, and focused first: the name is the claim and
              // the PIN is what backs it up, so they are asked in that order.
              UsernameField(
                controller: _username,
                onSubmitted: () => FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: PosSpace.s24),
              PinDots(length: _pin.length),
              const SizedBox(height: PosSpace.s24),
              // Not autofocused: the username field above is asked for first,
              // and a pad that grabbed the keyboard would swallow every letter
              // typed into it. Enter moves along, and so does a tap on a key.
              PinPad(
                onDigit: _push,
                onBackspace: _backspace,
                autofocus: false,
              ),
              const SizedBox(height: PosSpace.lg),
              PosButton(
                key: const Key('lock-back'),
                label: strings.back,
                foreground: context.pos.shellText,
                border: Border.fromBorderSide(context.pos.shellBorder),
                onPressed: _back,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
