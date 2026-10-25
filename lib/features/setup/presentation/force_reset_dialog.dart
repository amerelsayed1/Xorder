import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/security/attempt_limiter.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../admin/application/admin_session.dart'
    show StaffRefused, StaffUnreachable, StaffVerified, checkStaffPin;

/// The deliberate escape hatch: wipe this machine's terminal setup and run the
/// wizard again, from anywhere, including mid-shift.
///
/// Why this exists separately from the back office's "Reset terminal"
/// (System › Terminal): that one REFUSES while a shift is open, and it is right
/// to. The common case is an operator who does not realise the drawer is still
/// open, and silently discarding a shift is not something a visible button
/// should do.
///
/// But a till whose terminal has been deleted platform-side is stuck behind
/// exactly that refusal — its shift can never be closed cleanly, because the
/// platform will not accept anything from it — and refusing forever is not an
/// answer either. So the forced path exists, is bound to a shortcut rather
/// than a button so it is not found by accident, and states plainly what it is
/// about to cost instead of either refusing or quietly destroying it.
///
/// **On a till that is set up, it asks who first.** The shortcut used to be the
/// only lock, and a cashier who had once watched an installer use it held the
/// key to a till nobody could sell on until somebody who may manage terminals
/// arrived. See [_ForceResetSignIn] for the one case it still lets through
/// without a name.
///
/// Ctrl/Cmd+Shift+R. It was Ctrl+Shift+S until Admin Mode took that chord.
///
/// Nothing on the platform is touched. This deletes local setup only.
Future<bool> showForceResetDialog(BuildContext context, WidgetRef ref) async {
  // Nothing to protect on a till that was never set up, or is halfway through
  // the wizard: there is no working setup to wipe and no database to ask.
  if (ref.read(setupCompleteProvider)) {
    final allowed = await showDialog<bool>(
      context: context,
      // Not dismissed by a stray tap while the database is being asked: the
      // check reads providers through this dialog, which must still be there
      // when the answer comes back.
      barrierDismissible: false,
      builder: (_) => const _ForceResetSignIn(),
    );
    if (allowed != true || !context.mounted) return false;
  }

  final strings = context.strings;

  // Read both costs BEFORE asking, so the dialog can name them. A failure to
  // read is reported as unknown rather than as "nothing to lose" — the whole
  // point is that the operator decides with the real numbers in front of them.
  PosShift? openShift;
  try {
    openShift = await ref.read(shiftRepositoryProvider).current();
  } on Exception {
    openShift = null;
  }

  var queued = 0;
  try {
    // Pending AND held. The pending count leaves out what the drain has held
    // for a person, because no pass will send it — but this question is what
    // a reset leaves behind unsent, and a held sale is exactly that.
    queued =
        await ref.read(ordersRepositoryProvider).pendingSyncCount() +
        await ref.read(syncQueueRepositoryProvider).heldSyncCount();
  } on Exception {
    queued = 0;
  }

  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _ForceResetDialog(
      strings: strings,
      openShiftRef: openShift?.reference,
      queued: queued,
    ),
  );

  if (confirmed != true) return false;

  await ref.read(terminalResetProvider).run();

  return true;
}

/// Who is wiping this till: a username and PIN, from somebody who holds
/// `terminal.manage` — the same question Admin Mode asks, through the same
/// [checkStaffPin].
///
/// **The one refusal that lets somebody through** is the database being
/// unreachable altogether. A till in that state cannot sell, cannot open the
/// back office, and cannot check anybody's PIN — and pointing it at a database
/// it CAN reach is exactly what this reset is for. So it goes on to the dialog
/// that names the cost, as it always did. A wrong PIN, or the right one from
/// somebody who may not do this, stays refused.
class _ForceResetSignIn extends ConsumerStatefulWidget {
  const _ForceResetSignIn();

  @override
  ConsumerState<_ForceResetSignIn> createState() => _ForceResetSignInState();
}

class _ForceResetSignInState extends ConsumerState<_ForceResetSignIn> {
  final _username = TextEditingController();
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final pin = _pin.text;
    if (username.isEmpty || pin.isEmpty || _busy) return;

    final strings = context.strings;
    // Before the await, for the reason [checkStaffPin] takes a repository.
    final sessions = ref.read(sessionRepositoryProvider);
    // The lock screen's limiter, not a count of this door's own: a separate
    // one would be five more guesses per lockout window for anybody who knew
    // the shortcut. Asked before the PIN is looked at, as there.
    final limiter = ref.read(signInLimiterProvider);
    if (limiter.lockedFor(username) case final wait?) {
      _pin.clear();
      setState(
        () => _error = strings.signInLockedOut(
          AttemptLimiter.secondsToWait(wait),
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final check = await checkStaffPin(
      sessions,
      username: username,
      pin: pin,
      capability: PosCapability.terminalManage,
    );
    if (!mounted) return;

    switch (check) {
      case StaffVerified():
        limiter.succeed(username);
        Navigator.of(context).pop(true);
      case StaffUnreachable():
        // Nothing was checked, so nothing is counted. See the class comment.
        Navigator.of(context).pop(true);
      case StaffRefused():
        // Every refusal counts — unknown name, wrong PIN, and the right PIN
        // from somebody without `terminal.manage` alike. Sparing the last
        // would make the count itself say which PIN was right.
        final failure = limiter.fail(username);
        _pin.clear();
        setState(() {
          _busy = false;
          _error = switch (failure) {
            AttemptRefused() => strings.forceResetSignInRefused,
            AttemptLockedOut(:final wait) => strings.signInLockedOut(
              AttemptLimiter.secondsToWait(wait),
            ),
          };
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;

    return Dialog(
      backgroundColor: pos.shell,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: RoundedRectangleBorder(
        side: pos.shellBorder,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.forceResetSignInTitle,
                style: PosText.panelTitle(color: pos.shellText),
              ),
              const SizedBox(height: PosSpace.sm),
              Text(
                strings.forceResetSignInHelp,
                style: PosText.ui(size: 13, color: pos.shellMuted, height: 1.5),
              ),
              const SizedBox(height: PosSpace.lg),
              UsernameField(
                key: const Key('force-reset-username'),
                controller: _username,
                onSubmitted: _pinFocus.requestFocus,
              ),
              const SizedBox(height: PosSpace.lg),
              MicroLabel(strings.yourPin),
              const SizedBox(height: PosSpace.sm),
              TextField(
                key: const Key('force-reset-pin'),
                controller: _pin,
                focusNode: _pinFocus,
                obscureText: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _submit(),
                textAlign: TextAlign.center,
                style: PosText.mono(size: 16, color: pos.shellText),
                cursorColor: pos.accent,
                decoration: shellInputDecoration(pos),
              ),
              // Reserved, not conditional, so the buttons do not jump under a
              // finger already on its way to them.
              const SizedBox(height: PosSpace.md),
              SizedBox(
                height: 36,
                child: _error == null
                    ? null
                    : Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: PosText.ui(size: 12.5, color: pos.danger),
                      ),
              ),
              const SizedBox(height: PosSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      foreground: pos.shellText,
                      border: Border.fromBorderSide(pos.shellBorder),
                      // Not while the database is being asked: the answer
                      // lands on this dialog, which has to still be here.
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: PosButton(
                      key: const Key('force-reset-continue'),
                      label: _busy ? strings.checking : strings.continueLabel,
                      background: pos.accent,
                      foreground: pos.onAccent,
                      onPressed: _busy ? null : _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForceResetDialog extends StatelessWidget {
  const _ForceResetDialog({
    required this.strings,
    required this.openShiftRef,
    required this.queued,
  });

  final AppStrings strings;
  final String? openShiftRef;
  final int queued;

  @override
  Widget build(BuildContext context) {
    final warnings = <String>[
      if (openShiftRef != null)
        strings.forceResetShiftOpen.replaceFirst('{ref}', openShiftRef!),
      if (queued > 0)
        strings.forceResetQueued.replaceFirst('{count}', '$queued'),
    ];

    return Dialog(
      backgroundColor: context.pos.page,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: RoundedRectangleBorder(
        side: context.pos.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.forceResetTitle, style: PosText.panelTitle(color: context.pos.ink)),
              const SizedBox(height: PosSpace.sm),
              Text(
                strings.forceResetBody,
                style: PosText.ui(
                  size: 13,
                  color: context.pos.muted,
                  height: 1.5,
                ),
              ),
              // Each cost on its own line, in danger red. Not folded into the
              // body text: an operator scanning this dialog must not be able
              // to miss an open drawer or unsent money.
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: PosSpace.md),
                Container(
                  padding: const EdgeInsets.all(PosSpace.md),
                  decoration: BoxDecoration(
                    color: context.pos.shellDangerBg,
                    border: Border.all(color: context.pos.danger),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final warning in warnings) ...[
                        if (warning != warnings.first)
                          const SizedBox(height: PosSpace.sm),
                        Text(
                          warning,
                          style: PosText.ui(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: context.pos.shellDangerText,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: PosSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.all(color: context.pos.line),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: PosButton(
                      label: strings.forceResetConfirm,
                      background: context.pos.danger,
                      foreground: Colors.white,
                      fontWeight: FontWeight.w700,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
