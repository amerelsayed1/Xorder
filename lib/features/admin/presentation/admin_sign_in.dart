import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/security/attempt_limiter.dart';
import '../../../core/security/pin_hash.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../application/admin_session.dart';
import 'admin_messages.dart';

/// The door to Admin Mode: a username and a password.
///
/// **The only thing Admin Mode renders before somebody is in.** The shortcut
/// that leads here is a hidden way in and nothing more — anybody who has seen
/// it pressed knows it — so this is the lock, and the check behind it is in
/// [AdminSessionController.signIn], not here.
///
/// **One secret field, for a password or — once — a PIN.** Somebody who has
/// not chosen a password yet types their PIN in the same field, and is then
/// shown the second step, where they choose one; they cannot get past it any
/// other way. One field rather than a "PIN instead" switch, because a switch
/// would ask the person to know which they have, and the door to say so to
/// whoever is looking.
///
/// On a till installed before Admin Mode it asks, once, for the back office's
/// database password as well, after the username and secret have got
/// somebody in.
class AdminSignInView extends ConsumerStatefulWidget {
  const AdminSignInView({
    required this.onClose,
    this.lockedAfterMinutes,
    super.key,
  });

  final VoidCallback onClose;

  /// Set when the inactivity timer is why the door is showing, so it can say
  /// so rather than look like a sign-out nobody asked for.
  final int? lockedAfterMinutes;

  @override
  ConsumerState<AdminSignInView> createState() => _AdminSignInViewState();
}

class _AdminSignInViewState extends ConsumerState<AdminSignInView> {
  final _username = TextEditingController();
  final _secret = TextEditingController();
  final _password = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  final _secretFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _busy = false;
  bool _needsPassword = false;

  /// On the second step: the PIN was right and a password must be chosen.
  bool _choosing = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _secret.dispose();
    _password.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    _secretFocus.dispose();
    _passwordFocus.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final secret = _secret.text;
    if (_busy || username.isEmpty || secret.isEmpty) return;
    if (_needsPassword && _password.text.isEmpty) return;

    final strings = context.strings;
    // Before the await: success rebuilds Management past this door, and this
    // widget is gone by the time the next line runs.
    final admin = ref.read(adminSessionProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await admin.signIn(
      username: username,
      secret: secret,
      databasePassword: _needsPassword ? _password.text : null,
    );
    if (!mounted) return;
    _show(result, strings);
  }

  Future<void> _savePassword() async {
    if (_busy || _newPassword.text.isEmpty) return;
    final strings = context.strings;
    final admin = ref.read(adminSessionProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await admin.setPassword(
      password: _newPassword.text,
      confirm: _confirm.text,
    );
    if (!mounted) return;
    _show(result, strings);
  }

  /// Back from the second step to the first. The PIN is spent: the next try
  /// asks for it again.
  void _backToSignIn({String? error}) {
    ref.read(adminSessionProvider.notifier).cancelPasswordStep();
    _secret.clear();
    _newPassword.clear();
    _confirm.clear();
    setState(() {
      _busy = false;
      _choosing = false;
      _error = error;
    });
    _secretFocus.requestFocus();
  }

  void _show(AdminSignIn result, AppStrings strings) {
    switch (result) {
      case AdminSignedIn():
        return;
      case AdminNeedsDatabasePassword():
        setState(() {
          _busy = false;
          _needsPassword = true;
        });
        _passwordFocus.requestFocus();
      case AdminMustSetPassword():
        // The PIN is not left in its field behind the step that replaces it.
        _secret.clear();
        setState(() {
          _busy = false;
          _choosing = true;
        });
        _newFocus.requestFocus();
      case AdminPasswordMismatch():
        _confirm.clear();
        setState(() {
          _busy = false;
          _error = strings.passwordsDoNotMatch;
        });
        _confirmFocus.requestFocus();
      case AdminPasswordRejected(:final problem):
        setState(() {
          _busy = false;
          _error = AdminText.passwordProblem(strings, problem);
        });
        _newFocus.requestFocus();
      case AdminPasswordNotSaved(:final refusal):
        setState(() {
          _busy = false;
          _error = AdminText.refusal(strings, refusal);
        });
      case AdminPasswordStepExpired():
        _backToSignIn(error: strings.adminPasswordStepExpired);
      case AdminSignInRefused(:final attemptsLeft):
        _secret.clear();
        setState(() {
          _busy = false;
          _error = strings.adminSignInAttemptsLeft(attemptsLeft);
        });
      case AdminSignInLockedOut(:final wait):
        _secret.clear();
        setState(() {
          _busy = false;
          _error = strings.adminSignInLockedOut(
            AttemptLimiter.secondsToWait(wait),
          );
        });
      case AdminDatabasePasswordRefused():
        _password.clear();
        setState(() {
          _busy = false;
          _error = strings.adminDatabasePasswordRefused;
        });
      case AdminSignInUnreachable():
        setState(() {
          _busy = false;
          _error = strings.backOfficeUnreachable;
        });
      case AdminDatabaseRefused():
        setState(() {
          _busy = false;
          _error = strings.backOfficeRefused;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final minutes = ref.watch(adminModeSettingsProvider).timeoutMinutes;

    TextField secretField({
      required Key key,
      required TextEditingController controller,
      required FocusNode focusNode,
      required VoidCallback onSubmitted,
    }) => TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      obscureText: true,
      enabled: !_busy,
      onSubmitted: (_) => onSubmitted(),
      textAlign: TextAlign.center,
      style: PosText.mono(size: 16, color: pos.shellText),
      cursorColor: pos.accent,
      decoration: shellInputDecoration(pos),
    );

    final children = _choosing
        ? <Widget>[
            Text(
              strings.adminSetPasswordTitle,
              key: const Key('admin-set-password-title'),
              style: PosText.screenTitle(color: pos.shellText),
            ),
            const SizedBox(height: PosSpace.sm),
            Text(
              strings.adminSetPasswordHelp(PasswordPolicy.minLength),
              style: PosText.ui(size: 13, color: pos.shellMuted, height: 1.5),
            ),
            const SizedBox(height: PosSpace.xl),
            MicroLabel(strings.adminNewPassword),
            const SizedBox(height: PosSpace.sm),
            secretField(
              key: const Key('admin-new-password'),
              controller: _newPassword,
              focusNode: _newFocus,
              onSubmitted: _confirmFocus.requestFocus,
            ),
            const SizedBox(height: PosSpace.lg),
            MicroLabel(strings.adminConfirmPassword),
            const SizedBox(height: PosSpace.sm),
            secretField(
              key: const Key('admin-confirm-password'),
              controller: _confirm,
              focusNode: _confirmFocus,
              onSubmitted: _savePassword,
            ),
          ]
        : <Widget>[
            Text(
              strings.adminSignInTitle,
              style: PosText.screenTitle(color: pos.shellText),
            ),
            const SizedBox(height: PosSpace.sm),
            Text(
              strings.adminSignInHelp(minutes),
              style: PosText.ui(size: 13, color: pos.shellMuted, height: 1.5),
            ),
            if (widget.lockedAfterMinutes case final after?) ...[
              const SizedBox(height: PosSpace.md),
              Text(
                strings.adminLockedAfter(after),
                key: const Key('admin-locked'),
                style: PosText.ui(size: 12.5, color: pos.warn, height: 1.5),
              ),
            ],
            const SizedBox(height: PosSpace.xl),
            UsernameField(
              key: const Key('admin-username'),
              controller: _username,
              onSubmitted: _secretFocus.requestFocus,
            ),
            const SizedBox(height: PosSpace.lg),
            MicroLabel(strings.adminPasswordLabel),
            const SizedBox(height: PosSpace.sm),
            // Not digits-only any more, as the PIN field was: a password is
            // any characters, Arabic included, and the PIN that still fits
            // here the first time is four of them.
            secretField(
              key: const Key('admin-password'),
              controller: _secret,
              focusNode: _secretFocus,
              onSubmitted: () =>
                  _needsPassword ? _passwordFocus.requestFocus() : _submit(),
            ),
            const SizedBox(height: PosSpace.sm),
            Text(
              strings.adminPasswordFirstTime,
              style: PosText.ui(size: 12, color: pos.shellMuted, height: 1.5),
            ),
            if (_needsPassword) ...[
              const SizedBox(height: PosSpace.lg),
              Text(
                strings.adminDatabasePasswordNeeded,
                style: PosText.ui(
                  size: 12.5,
                  color: pos.shellMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: PosSpace.sm),
              MicroLabel(strings.backOfficePassword),
              const SizedBox(height: PosSpace.sm),
              secretField(
                key: const Key('admin-db-password'),
                controller: _password,
                focusNode: _passwordFocus,
                onSubmitted: _submit,
              ),
            ],
          ];

    return Scaffold(
      backgroundColor: pos.shell,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PosSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...children,
                // Reserved, not conditional, so the button does not jump
                // under a finger already on its way to it.
                const SizedBox(height: PosSpace.md),
                SizedBox(
                  height: 36,
                  child: _error == null
                      ? null
                      : Text(
                          _error!,
                          key: const Key('admin-error'),
                          textAlign: TextAlign.center,
                          style: PosText.ui(size: 12.5, color: pos.danger),
                        ),
                ),
                const SizedBox(height: PosSpace.sm),
                if (_choosing)
                  PosButton(
                    key: const Key('admin-set-password'),
                    label: _busy ? strings.checking : strings.adminSavePassword,
                    background: pos.accent,
                    foreground: pos.onAccent,
                    onPressed: _busy ? null : _savePassword,
                  )
                else
                  PosButton(
                    key: const Key('admin-open'),
                    label: _busy ? strings.checking : strings.openAdminMode,
                    background: pos.accent,
                    foreground: pos.onAccent,
                    onPressed: _busy ? null : _submit,
                  ),
                const SizedBox(height: PosSpace.md),
                PosButton(
                  key: const Key('admin-back'),
                  label: _choosing ? strings.back : strings.backToTill,
                  foreground: pos.shellText,
                  border: Border.fromBorderSide(pos.shellBorder),
                  // Back to the till is never shut, as it never was; back
                  // from the password step waits for a save in flight.
                  onPressed: !_choosing
                      ? widget.onClose
                      : _busy
                      ? null
                      : _backToSignIn,
                ),
                if (!_choosing) ...[
                  const SizedBox(height: PosSpace.lg),
                  // A link, quiet, at the bottom: it is for the day the owner
                  // has forgotten, and a technician on the phone can say
                  // where it is.
                  TextButton(
                    key: const Key('admin-technician-reset'),
                    onPressed: _busy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const _TechnicianResetDialog(),
                          ),
                    child: Text(
                      strings.technicianResetLink,
                      style: PosText.ui(size: 12.5, color: pos.shellMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The technician's reset: a username and the back-office database password,
/// typed. See [AdminSessionController.technicianClearPassword] for why the
/// typed one and not the kept one.
class _TechnicianResetDialog extends ConsumerStatefulWidget {
  const _TechnicianResetDialog();

  @override
  ConsumerState<_TechnicianResetDialog> createState() =>
      _TechnicianResetDialogState();
}

class _TechnicianResetDialogState
    extends ConsumerState<_TechnicianResetDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  String? _message;
  bool _done = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    if (_busy || username.isEmpty || _password.text.isEmpty) return;
    final strings = context.strings;
    final admin = ref.read(adminSessionProvider.notifier);
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await admin.technicianClearPassword(
      username: username,
      databasePassword: _password.text,
    );
    if (!mounted) return;
    // Never left in the field, whatever the answer: it is the one secret
    // that unlocks everything.
    _password.clear();
    setState(() {
      _busy = false;
      _done = result is TechnicianResetDone;
      _message = switch (result) {
        TechnicianResetDone(:final name) => strings.technicianResetDone(name),
        TechnicianResetNobody() => strings.technicianResetNobody,
        TechnicianResetDatabasePasswordRefused() =>
          strings.adminDatabasePasswordRefused,
        TechnicianResetLockedOut(:final wait) => strings.adminSignInLockedOut(
          AttemptLimiter.secondsToWait(wait),
        ),
        TechnicianResetFailed() => strings.backOfficeUnreachable,
      };
    });
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
                strings.technicianResetTitle,
                style: PosText.panelTitle(color: pos.shellText),
              ),
              const SizedBox(height: PosSpace.sm),
              Text(
                strings.technicianResetHelp,
                style: PosText.ui(size: 13, color: pos.shellMuted, height: 1.5),
              ),
              const SizedBox(height: PosSpace.lg),
              UsernameField(
                key: const Key('technician-username'),
                controller: _username,
                onSubmitted: _passwordFocus.requestFocus,
              ),
              const SizedBox(height: PosSpace.lg),
              MicroLabel(strings.backOfficePassword),
              const SizedBox(height: PosSpace.sm),
              TextField(
                key: const Key('technician-db-password'),
                controller: _password,
                focusNode: _passwordFocus,
                obscureText: true,
                enabled: !_busy,
                onSubmitted: (_) => _submit(),
                textAlign: TextAlign.center,
                style: PosText.mono(size: 16, color: pos.shellText),
                cursorColor: pos.accent,
                decoration: shellInputDecoration(pos),
              ),
              const SizedBox(height: PosSpace.md),
              SizedBox(
                height: 54,
                child: _message == null
                    ? null
                    : Text(
                        _message!,
                        key: const Key('technician-message'),
                        textAlign: TextAlign.center,
                        style: PosText.ui(
                          size: 12.5,
                          color: _done ? pos.ok : pos.danger,
                          height: 1.4,
                        ),
                      ),
              ),
              const SizedBox(height: PosSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: PosButton(
                      key: const Key('technician-close'),
                      label: _done ? strings.close : strings.cancel,
                      foreground: pos.shellText,
                      border: Border.fromBorderSide(pos.shellBorder),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.md),
                  Expanded(
                    child: PosButton(
                      key: const Key('technician-clear'),
                      label: _busy
                          ? strings.checking
                          : strings.technicianResetAction,
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
