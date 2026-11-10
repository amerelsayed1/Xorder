import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../mode.dart';
import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'widgets.dart';

/// The one door of each flavor (design §5.1): where to sign in, who, and the
/// PIN. The first two are remembered on this phone; the PIN never is. A shell
/// screen, like the till's lock screen.
///
/// Offline: the till's address · name · PIN. Cloud: the restaurant's slug ·
/// name · PIN. The screen is the same; the mode decides the first field's
/// words and where the client goes.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final TextEditingController _target;
  late final TextEditingController _username;
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(waiterAppProvider).connection;
    _target = TextEditingController(text: saved?.target ?? '');
    _username = TextEditingController(text: saved?.username ?? '');
  }

  @override
  void dispose() {
    _target.dispose();
    _username.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final s = WaiterStrings.of(context);
    if (_target.text.trim().isEmpty || _username.text.trim().isEmpty || _pin.text.length < 4) {
      setState(() => _error = s.fillEverything);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = ref.read(waiterAppProvider.notifier);
    final mode = ref.read(waiterModeProvider);
    try {
      // At most twice: once, and once more after the waiter confirmed the
      // till's certificate (WA4). A second refusal is an error like any other.
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await app.signIn(target: _target.text, username: _username.text, pin: _pin.text);
          return;
        } on WaiterLinkUntrustedCertificate catch (e) {
          if (e.pinned || mode != WaiterMode.offline || attempt > 0) rethrow;
          // Not busy while the waiter reads: the question is theirs to take time over.
          if (mounted) setState(() => _busy = false);
          final match = await _confirmCertificate(e.presented);
          if (!match || !mounted) return;
          setState(() => _busy = true);
          await app.trust(target: _target.text, certificate: e.presented);
        }
      }
    } on WaiterLinkFailure catch (e) {
      await app.absorb(e); // a forgotten device: the next tap registers it again
      if (mounted) setState(() => _error = s.failure(e));
    } on FormatException {
      if (mounted) setState(() => _error = s.unreachable);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pin.clear();
        });
      }
    }
  }

  /// The fingerprint, for the waiter to hold against the till's screen.
  Future<bool> _confirmCertificate(WaiterCertificate certificate) async {
    final s = WaiterStrings.of(context);
    final notAfter = certificate.notAfter;
    final until = notAfter == null ? null : '${notAfter.year}-${notAfter.month.toString().padLeft(2, '0')}-${notAfter.day.toString().padLeft(2, '0')}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.certificateTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.certificateCompare, style: WaiterText.body()),
            const SizedBox(height: WaiterSpace.md),
            Container(
              key: const Key('certificate-fingerprint'),
              padding: const EdgeInsets.all(WaiterSpace.md),
              decoration: const BoxDecoration(
                color: WaiterColors.page,
                border: Border.fromBorderSide(BorderSide(color: WaiterColors.lineStrong)),
              ),
              child: SelectableText(
                certificate.formatted,
                textDirection: TextDirection.ltr,
                style: WaiterText.mono(size: 13, weight: FontWeight.w500, height: 1.5),
              ),
            ),
            if (until != null) ...[
              const SizedBox(height: WaiterSpace.sm),
              Text(s.certificateExpires(until), style: WaiterText.meta()),
            ],
          ],
        ),
        actions: [
          TextButton(key: const Key('certificate-cancel'), onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(key: const Key('certificate-match'), onPressed: () => Navigator.pop(context, true), child: Text(s.certificateMatch)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _forget() async {
    final s = WaiterStrings.of(context);
    final saved = ref.read(waiterAppProvider).connection;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.forgetConfirm(saved?.serverName.isNotEmpty == true ? saved!.serverName : (saved?.target ?? ''))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.forgetAction, style: WaiterText.ui(weight: FontWeight.w600, color: WaiterColors.danger)),
          ),
        ],
      ),
    );
    if (sure ?? false) {
      await ref.read(waiterAppProvider.notifier).forget();
      if (mounted) {
        _target.clear();
        _username.clear();
        _pin.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final mode = ref.watch(waiterModeProvider);
    final saved = ref.watch(waiterAppProvider.select((a) => a.connection));
    return Scaffold(
      backgroundColor: WaiterColors.shell,
      appBar: AppBar(
        backgroundColor: WaiterColors.shell,
        foregroundColor: WaiterColors.shellText,
        shape: const Border(bottom: BorderSide(color: WaiterColors.shellLine)),
        title: Text(s.appTitle),
        actions: [
          if (saved != null)
            PopupMenuButton<void>(
              key: const Key('sign-in-menu'),
              itemBuilder: (_) => [PopupMenuItem(key: const Key('forget'), onTap: _forget, child: Text(s.forgetAction))],
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WaiterSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(WaiterSpace.xl),
                decoration: const BoxDecoration(
                  color: WaiterColors.shellCard,
                  border: Border.fromBorderSide(BorderSide(color: WaiterColors.shellLine)),
                ),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(alignment: AlignmentDirectional.centerStart, child: XorderMark()),
                      const SizedBox(height: WaiterSpace.lg),
                      Text(s.signInTitle, style: WaiterText.heading()),
                      const SizedBox(height: WaiterSpace.xs),
                      if (saved != null && saved.serverName.isNotEmpty)
                        Text(s.signedInTo(saved.serverName), style: WaiterText.meta(color: WaiterColors.shellMuted))
                      else
                        Text(s.signInIntro, style: WaiterText.body()),
                      const SizedBox(height: WaiterSpace.xl),
                      TextField(
                        key: const Key('target'),
                        controller: _target,
                        keyboardType: mode == WaiterMode.cloud ? TextInputType.text : TextInputType.url,
                        textDirection: TextDirection.ltr,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        style: WaiterText.mono(weight: FontWeight.w500, size: 15),
                        decoration: InputDecoration(
                          labelText: s.targetLabel,
                          hintText: s.targetHint,
                          prefixText: mode == WaiterMode.cloud ? '$cloudDomain/' : null,
                          prefixStyle: WaiterText.mono(weight: FontWeight.w500, size: 15, color: WaiterColors.muted),
                        ),
                      ),
                      const SizedBox(height: WaiterSpace.md),
                      TextField(
                        key: const Key('username'),
                        controller: _username,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: InputDecoration(labelText: s.usernameLabel, hintText: s.usernameHint),
                      ),
                      const SizedBox(height: WaiterSpace.md),
                      TextField(
                        key: const Key('pin'),
                        controller: _pin,
                        focusNode: _pinFocus,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        textDirection: TextDirection.ltr,
                        maxLength: 8,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        style: WaiterText.keypad().copyWith(letterSpacing: 6),
                        decoration: InputDecoration(labelText: s.pinLabel, hintText: s.pinHint, counterText: ''),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: WaiterSpace.md),
                        ErrorNote(_error!),
                      ],
                      const SizedBox(height: WaiterSpace.lg),
                      PrimaryCta(key: const Key('sign-in'), label: s.signInAction, busy: _busy, onPressed: _submit),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
