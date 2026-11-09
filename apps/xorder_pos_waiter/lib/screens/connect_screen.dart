import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'widgets.dart';

/// Pair this handheld with the till: its address and the one-time code it
/// shows under Settings › Waiter devices. A shell screen (design §5.1), like
/// the till's start screen: a device is paired once, so nothing else is here.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final s = WaiterStrings.of(context);
    if (_address.text.trim().isEmpty || _code.text.trim().length != 6) {
      setState(() => _error = s.badCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(waiterAppProvider.notifier).pair(
        address: _address.text,
        code: _code.text,
        deviceName: _name.text.trim().isEmpty ? s.deviceNameHint : _name.text.trim(),
      );
    } on WaiterLinkFailure catch (e) {
      if (mounted) setState(() => _error = s.failure(e));
    } on FormatException {
      if (mounted) setState(() => _error = s.unreachable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    return Scaffold(
      backgroundColor: WaiterColors.shell,
      appBar: AppBar(
        backgroundColor: WaiterColors.shell,
        foregroundColor: WaiterColors.shellText,
        shape: const Border(bottom: BorderSide(color: WaiterColors.shellLine)),
        title: Text(s.appTitle),
        actions: const [LanguageButton()],
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(alignment: AlignmentDirectional.centerStart, child: XorderMark()),
                    const SizedBox(height: WaiterSpace.lg),
                    Text(s.connectTitle, style: WaiterText.heading()),
                    const SizedBox(height: WaiterSpace.sm),
                    Text(s.connectIntro, style: WaiterText.body()),
                    const SizedBox(height: WaiterSpace.xl),
                    TextField(
                      key: const Key('address'),
                      controller: _address,
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      style: WaiterText.mono(weight: FontWeight.w500, size: 15),
                      decoration: InputDecoration(labelText: s.tillAddress, hintText: s.tillAddressHint),
                    ),
                    const SizedBox(height: WaiterSpace.md),
                    TextField(
                      key: const Key('code'),
                      controller: _code,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: WaiterText.keypad().copyWith(letterSpacing: 6),
                      decoration: InputDecoration(labelText: s.pairingCode, hintText: s.pairingCodeHint, counterText: ''),
                    ),
                    const SizedBox(height: WaiterSpace.md),
                    TextField(
                      key: const Key('name'),
                      controller: _name,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _pair(),
                      decoration: InputDecoration(labelText: s.deviceName, hintText: s.deviceNameHint),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: WaiterSpace.md),
                      ErrorNote(_error!),
                    ],
                    const SizedBox(height: WaiterSpace.lg),
                    PrimaryCta(key: const Key('pair'), label: s.pairAction, busy: _busy, onPressed: _pair),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
