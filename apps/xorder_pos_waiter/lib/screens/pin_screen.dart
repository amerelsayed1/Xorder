import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'widgets.dart';

/// Who is holding the handheld. The same PIN as on the till's lock screen;
/// the till checks it and decides what this person may do.
class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  static const _maxLength = 8;
  String _pin = '';
  String? _error;
  bool _busy = false;

  void _tap(String digit) {
    if (_busy || _pin.length >= _maxLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_pin.length < 4 || _busy) return;
    final s = WaiterStrings.of(context);
    setState(() => _busy = true);
    final app = ref.read(waiterAppProvider.notifier);
    try {
      await app.signIn(_pin);
    } on WaiterLinkFailure catch (e) {
      if (await app.absorb(e)) return;
      if (mounted) setState(() => _error = s.failure(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pin = '';
        });
      }
    }
  }

  Future<void> _unpair() async {
    final s = WaiterStrings.of(context);
    final till = ref.read(waiterAppProvider).pairing?.tillName ?? '';
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.unpairConfirm(till)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.unpairAction, style: const TextStyle(color: WaiterColors.danger)),
          ),
        ],
      ),
    );
    if (sure ?? false) await ref.read(waiterAppProvider.notifier).unpair();
  }

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final till = ref.watch(waiterAppProvider.select((a) => a.pairing?.tillName)) ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(s.appTitle),
        actions: [
          const LanguageButton(),
          PopupMenuButton<void>(
            itemBuilder: (_) => [PopupMenuItem(onTap: _unpair, child: Text(s.unpairAction))],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WaiterSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                children: [
                  Text(s.pinTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: WaiterColors.ink)),
                  const SizedBox(height: WaiterSpace.xs),
                  Text(s.pairedWith(till), style: const TextStyle(color: WaiterColors.muted)),
                  const SizedBox(height: WaiterSpace.xl),
                  _Dots(length: _pin.length),
                  const SizedBox(height: WaiterSpace.md),
                  SizedBox(height: 48, child: _error == null ? null : Center(child: ErrorNote(_error!))),
                  const SizedBox(height: WaiterSpace.md),
                  _Keypad(onDigit: _tap, onBack: _back, onEnter: _submit, busy: _busy),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.length});
  final int length;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 4 || i < length; i++)
        Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: i < length ? WaiterColors.ink : WaiterColors.surface,
            border: const Border.fromBorderSide(BorderSide(color: WaiterColors.ink, width: 2)),
          ),
        ),
    ],
  );
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBack, required this.onEnter, required this.busy});

  final ValueChanged<String> onDigit;
  final VoidCallback onBack;
  final VoidCallback onEnter;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    Widget key(String label, VoidCallback onTap, {Key? k, bool accent = false}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 64,
          child: accent
              ? FilledButton(key: k, onPressed: busy ? null : onTap, child: busy ? const SmallSpinner() : Text(label))
              : OutlinedButton(
                  key: k,
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(backgroundColor: WaiterColors.surface),
                  child: Text(label, style: waiterMono(size: 24)),
                ),
        ),
      ),
    );
    // Digits always left to right, as on every keypad, in either language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
            Row(children: [for (final d in row) key(d, () => onDigit(d), k: Key('pin-$d'))]),
          Row(
            children: [
              key('⌫', onBack, k: const Key('pin-back')),
              key('0', () => onDigit('0'), k: const Key('pin-0')),
              key(s.signInAction, onEnter, k: const Key('pin-enter'), accent: true),
            ],
          ),
        ],
      ),
    );
  }
}
