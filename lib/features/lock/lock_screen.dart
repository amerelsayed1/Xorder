import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../core/security/pin_hash.dart';
import '../../domain/models/shift.dart';

/// Lock screen — step away without closing the shift.
///
/// [PinRules.length] digits unlock. The comparison runs against the **cached**
/// hash so it works offline; the shift stays open throughout, and every overlay
/// is closed on lock.
///
/// **The name is offered, never assumed.** The audit (S3-2) watched every
/// cashier type their username on a keypad screen at every lock. Now the last
/// person to sign in at this till finds their name already in the field, and
/// everybody who can sign in here is a tile — one tap to switch user. The PIN
/// still has to belong to the name: what is remembered is a convenience, and
/// what is checked is a claim.
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
  /// Six tiles: three rows, which with the name field, the dots and the pad is
  /// what a 900px screen holds without scrolling. A roster longer than that
  /// types the name, which is what everybody did before and still works.
  static const _maxTiles = 6;

  final _username = TextEditingController();

  /// The pad's keyboard focus, so a tile — or Enter in the name field — can
  /// hand the keyboard straight to the digits.
  final _pad = FocusNode();

  String _pin = '';
  bool _error = false;

  /// Whether the name arrived filled in. Then the pad takes the keyboard
  /// first: the only thing left to type is the PIN.
  late final bool _prefilled;

  @override
  void initState() {
    super.initState();
    final remembered = ref.read(lastUsernameProvider);
    _prefilled = remembered != null;
    if (remembered != null) _username.text = remembered;

    // Somebody is about to sign in with a PIN this till verifies from its
    // own staff table. A cashier added on the dashboard a minute ago, or a
    // PIN reset there, is exactly what that table lacks — so ask the
    // platform now rather than on the four-hourly pass.
    Future.microtask(() => ref.read(cloudSyncProvider)?.nudge());
  }

  @override
  void dispose() {
    _username.dispose();
    _pad.dispose();
    super.dispose();
  }

  /// A tile was tapped: the name is this person's, and the keyboard is the
  /// pad's. A half-typed PIN under the previous name is dropped — it was for
  /// somebody else.
  void _pick(PosStaff person) {
    setState(() {
      _username.text = person.username ?? '';
      _pin = '';
      _error = false;
    });
    _pad.requestFocus();
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
        // Resuming a shift: make sure the branch is trading in a day. Covers a
        // till upgraded mid-shift and a day that failed to open earlier. Not
        // awaited and never throws: unlocking must not wait on it.
        if (ref.read(shiftProvider).valueOrNull != null) {
          unawaited(ref.read(ensureBusinessDayProvider)(staff));
        }
        widget.onUnlocked();
      } else {
        setState(() {
          _pin = '';
          _error = true;
        });
        // A wrong PIN is the moment a just-changed one would be wrong: ask
        // the platform again, so the second try can be against the new one.
        ref.read(cloudSyncProvider)?.nudge();
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
    // Whoever the directory lists, or nobody while it is still being read —
    // the field below works either way, so the tiles are only ever a shortcut.
    final people =
        ref.watch(signInCandidatesProvider).valueOrNull ?? const <PosStaff>[];
    final typed = _username.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: context.pos.shell,
      body: Center(
        child: SizedBox(
          width: PosSize.pinPad,
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
              if (people.isNotEmpty) ...[
                MicroLabel(
                  strings.lockPickYourName,
                  color: context.pos.shellMuted,
                ),
                const SizedBox(height: PosSpace.sm),
                Wrap(
                  spacing: PosSpace.sm,
                  runSpacing: PosSpace.sm,
                  children: [
                    for (final person in people.take(_maxTiles))
                      _NameTile(
                        key: Key('lock-tile-${person.username}'),
                        person: person,
                        selected:
                            typed.isNotEmpty &&
                            person.username?.trim().toLowerCase() == typed,
                        onTap: () => _pick(person),
                      ),
                  ],
                ),
                const SizedBox(height: PosSpace.s24),
              ],
              // Still here, under the tiles: the fallback for a name that is
              // not on them, and the place the remembered name shows so the
              // next person can see whose it is and change it. Focused first
              // only when it is empty; otherwise the pad is.
              UsernameField(
                controller: _username,
                autofocus: !_prefilled,
                onChanged: (_) => setState(() => _error = false),
                onSubmitted: _pad.requestFocus,
              ),
              const SizedBox(height: PosSpace.s24),
              PinDots(length: _pin.length),
              const SizedBox(height: PosSpace.s24),
              // Takes the keyboard first only when the name is already in —
              // a pad that grabbed it while the name field was empty would
              // swallow every letter typed into it. Enter moves along, and so
              // does a tap on a tile or a key.
              PinPad(
                focusNode: _pad,
                onDigit: _push,
                onBackspace: _backspace,
                autofocus: _prefilled,
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

/// One person who can take this till. Name large, username small — the name
/// is what a colleague recognises, the username is what the PIN is checked
/// against, and the tile shows both so there is no doubt which it filled in.
class _NameTile extends StatelessWidget {
  const _NameTile({
    super.key,
    required this.person,
    required this.selected,
    required this.onTap,
  });

  final PosStaff person;
  final bool selected;
  final VoidCallback onTap;

  /// Two across the pad's width, with the gap between.
  static const _width = (PosSize.pinPad - PosSpace.sm) / 2;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return SizedBox(
      width: _width,
      child: Material(
        color: pos.shellCard,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: PosSize.searchRow),
            padding: const EdgeInsets.symmetric(
              horizontal: PosSpace.md,
              vertical: PosSpace.sm,
            ),
            // Selected is the 2px emphasis border in the accent; resting is
            // the shell's 1px. No fill change: on the dark shell a filled
            // tile reads as pressed, not chosen.
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? pos.accent : pos.shellLine,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.ui(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: pos.shellText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  person.username ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PosText.mono(size: 11, color: pos.shellMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
