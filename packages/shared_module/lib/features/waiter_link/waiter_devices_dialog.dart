import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../data/postgres/postgres_waiter_devices.dart';
import 'waiter_link_host.dart';

/// Settings › Waiter devices (waiter-app, WA1; sign-in WA3): turn the link
/// on, show the address a handheld signs in to, see and revoke the devices
/// that have signed in.
///
/// Reached from the till's Settings menu by someone holding `terminal.manage`.
/// A handheld registers itself on its first sign-in with a waiter's name and
/// PIN; this list is where a phone nobody recognises gets removed.
class WaiterDevicesDialog extends ConsumerStatefulWidget {
  const WaiterDevicesDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const WaiterDevicesDialog(),
  );

  @override
  ConsumerState<WaiterDevicesDialog> createState() => _WaiterDevicesDialogState();
}

class _WaiterDevicesDialogState extends ConsumerState<WaiterDevicesDialog> {
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // While the dialog is open, a device that signs in for the first time
    // shows up in the list without anybody pressing refresh.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(ref.read(waiterLinkHostProvider.notifier).refreshDevices());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    final staff = ref.read(signedInStaffProvider);
    if (staff == null) return;
    setState(() => _busy = true);
    try {
      final host = ref.read(waiterLinkHostProvider.notifier);
      on ? await host.enable(staff) : await host.disable(staff);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final status = ref.watch(waiterLinkHostProvider);
    final host = ref.read(waiterLinkHostProvider.notifier);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.waiterDevicesTitle, style: PosText.panelTitle(color: pos.ink)),
              const SizedBox(height: PosSpace.sm),
              Text(strings.waiterDevicesIntro, style: PosText.ui(size: 13, color: pos.body)),
              const SizedBox(height: PosSpace.lg),
              if (!status.available)
                Text(strings.waiterDevicesUnavailable, style: PosText.ui(size: 13, color: pos.warn))
              else ...[
                _StatusRow(
                  running: status.running,
                  busy: _busy,
                  onToggle: _toggle,
                ),
                if (status.error != null) ...[
                  const SizedBox(height: PosSpace.sm),
                  Text(
                    strings.waiterLinkFailed(status.error!),
                    style: PosText.ui(size: 12.5, color: pos.danger),
                  ),
                ],
                if (status.running) ...[
                  const SizedBox(height: PosSpace.lg),
                  MicroLabel(strings.waiterLinkAddress),
                  const SizedBox(height: PosSpace.xs),
                  for (final address in status.addresses)
                    SelectableText(
                      '$address:${status.port}',
                      style: PosText.mono(size: 16, color: pos.ink, weight: FontWeight.w600),
                    ),
                  const SizedBox(height: PosSpace.sm),
                  Text(strings.waiterSignInHelp, style: PosText.ui(size: 12.5, color: pos.body)),
                ],
                const SizedBox(height: PosSpace.lg),
                Flexible(
                  child: _DeviceList(
                    devices: status.devices,
                    onRevoke: (id) => unawaited(host.revoke(id)),
                  ),
                ),
              ],
              const SizedBox(height: PosSpace.lg),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: PosButton(
                  label: strings.close,
                  border: Border.fromBorderSide(pos.resting),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.running, required this.busy, required this.onToggle});

  final bool running;
  final bool busy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    return Row(
      children: [
        Container(width: 10, height: 10, color: running ? pos.ok : pos.muted),
        const SizedBox(width: PosSpace.sm),
        Expanded(
          child: Text(
            running ? strings.waiterLinkOn : strings.waiterLinkOff,
            style: PosText.ui(size: 14, color: pos.ink, weight: FontWeight.w600),
          ),
        ),
        PosButton(
          label: running ? strings.waiterLinkTurnOff : strings.waiterLinkTurnOn,
          border: Border.fromBorderSide(pos.resting),
          onPressed: busy ? null : () => onToggle(!running),
        ),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices, required this.onRevoke});

  final List<WaiterDevice> devices;
  final ValueChanged<int> onRevoke;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    if (devices.isEmpty) {
      return Text(strings.waiterDevicesNone, style: PosText.ui(size: 13, color: pos.muted));
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: devices.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: pos.line),
      itemBuilder: (context, i) {
        final d = devices[i];
        final seen = d.lastSeenAt;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: PosText.ui(
                        size: 14,
                        color: d.isRevoked ? pos.muted : pos.ink,
                        weight: FontWeight.w600,
                      ),
                    ),
                    if (seen != null)
                      Text(
                        strings.waiterDeviceLastSeen(
                          MaterialLocalizations.of(context).formatTimeOfDay(
                            TimeOfDay.fromDateTime(seen.toLocal()),
                          ),
                        ),
                        style: PosText.ui(size: 12, color: pos.muted),
                      ),
                  ],
                ),
              ),
              if (d.isRevoked)
                Text(strings.waiterDeviceRevoked, style: PosText.ui(size: 12.5, color: pos.muted))
              else
                PosButton(
                  label: strings.waiterDeviceRevoke,
                  foreground: pos.danger,
                  border: Border.fromBorderSide(pos.resting),
                  onPressed: () => onRevoke(d.id),
                ),
            ],
          ),
        );
      },
    );
  }
}
