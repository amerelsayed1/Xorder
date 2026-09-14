import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../application/admin_session.dart';

/// The door to Admin Mode: a username and a PIN.
///
/// **The only thing Admin Mode renders before somebody is in.** The shortcut
/// that leads here is a hidden way in and nothing more — anybody who has seen
/// it pressed knows it — so this is the lock, and the check behind it is in
/// [AdminSessionController.signIn], not here.
///
/// On a till installed before Admin Mode it asks, once, for the back office's
/// database password as well, after the username and PIN have got somebody in.
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
  final _pin = TextEditingController();
  final _password = TextEditingController();
  final _pinFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _needsPassword = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _pin.dispose();
    _password.dispose();
    _pinFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final pin = _pin.text;
    if (_busy || username.isEmpty || pin.isEmpty) return;
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
      pin: pin,
      databasePassword: _needsPassword ? _password.text : null,
    );
    if (!mounted) return;

    switch (result) {
      case AdminSignedIn():
        return;
      case AdminNeedsDatabasePassword():
        setState(() {
          _busy = false;
          _needsPassword = true;
        });
        _passwordFocus.requestFocus();
      case AdminSignInRefused(:final attemptsLeft):
        _pin.clear();
        setState(() {
          _busy = false;
          _error = strings.adminSignInAttemptsLeft(attemptsLeft);
        });
      case AdminSignInLockedOut(:final wait):
        _pin.clear();
        setState(() {
          _busy = false;
          // Rounded up: "0 seconds" on a door that is still shut is a lie.
          _error = strings.adminSignInLockedOut(
            (wait.inMilliseconds + 999) ~/ 1000,
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
                Text(
                  strings.adminSignInTitle,
                  style: PosText.screenTitle(color: pos.shellText),
                ),
                const SizedBox(height: PosSpace.sm),
                Text(
                  strings.adminSignInHelp(minutes),
                  style: PosText.ui(
                    size: 13,
                    color: pos.shellMuted,
                    height: 1.5,
                  ),
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
                  onSubmitted: _pinFocus.requestFocus,
                ),
                const SizedBox(height: PosSpace.lg),
                MicroLabel(strings.yourPin),
                const SizedBox(height: PosSpace.sm),
                TextField(
                  key: const Key('admin-pin'),
                  controller: _pin,
                  focusNode: _pinFocus,
                  obscureText: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _needsPassword
                      ? _passwordFocus.requestFocus()
                      : _submit(),
                  textAlign: TextAlign.center,
                  style: PosText.mono(size: 16, color: pos.shellText),
                  cursorColor: pos.accent,
                  decoration: shellInputDecoration(pos),
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
                  TextField(
                    key: const Key('admin-db-password'),
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
                ],
                // Reserved, not conditional, so the button does not jump
                // under a finger already on its way to it.
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
                PosButton(
                  key: const Key('admin-open'),
                  label: _busy ? strings.checking : strings.openAdminMode,
                  background: pos.accent,
                  foreground: pos.onAccent,
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: PosSpace.md),
                PosButton(
                  label: strings.backToTill,
                  foreground: pos.shellText,
                  border: Border.fromBorderSide(pos.shellBorder),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
