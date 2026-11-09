import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'widgets.dart';

/// Pair this handheld with the till: its address and the one-time code it
/// shows under Settings › Waiter devices.
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
      appBar: AppBar(title: Text(s.appTitle), actions: const [LanguageButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WaiterSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.connectTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: WaiterColors.ink)),
                  const SizedBox(height: WaiterSpace.sm),
                  Text(s.connectIntro, style: const TextStyle(color: WaiterColors.body, height: 1.4)),
                  const SizedBox(height: WaiterSpace.xl),
                  TextField(
                    key: const Key('address'),
                    controller: _address,
                    keyboardType: TextInputType.url,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: s.tillAddress, hintText: s.tillAddressHint),
                  ),
                  const SizedBox(height: WaiterSpace.md),
                  TextField(
                    key: const Key('code'),
                    controller: _code,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: waiterMono(size: 22),
                    decoration: InputDecoration(labelText: s.pairingCode, hintText: s.pairingCodeHint, counterText: ''),
                  ),
                  const SizedBox(height: WaiterSpace.md),
                  TextField(
                    key: const Key('name'),
                    controller: _name,
                    decoration: InputDecoration(labelText: s.deviceName, hintText: s.deviceNameHint),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: WaiterSpace.md),
                    ErrorNote(_error!),
                  ],
                  const SizedBox(height: WaiterSpace.lg),
                  FilledButton(
                    key: const Key('pair'),
                    onPressed: _busy ? null : _pair,
                    child: _busy ? const SmallSpinner() : Text(s.pairAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
