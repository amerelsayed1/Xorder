import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';

/// Lock screen — step away without closing the shift.
///
/// Four digits unlock. The comparison runs against the **cached** staff PIN
/// hash so it works offline; the shift stays open throughout, and every overlay
/// is closed on lock.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  bool _error = false;

  Future<void> _push(String digit) async {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = false;
    });

    if (_pin.length == 4) {
      final ok = await ref.read(sessionRepositoryProvider).verifyPin(_pin);
      if (!mounted) return;

      if (ok) {
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

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(sessionProvider).valueOrNull?.userName ?? '';
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
                _error ? strings.wrongPin : strings.enterPinFor(name),
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
              PinDots(length: _pin.length),
              const SizedBox(height: PosSpace.s24),
              PinPad(onDigit: _push, onBackspace: _backspace),
            ],
          ),
        ),
      ),
    );
  }
}
