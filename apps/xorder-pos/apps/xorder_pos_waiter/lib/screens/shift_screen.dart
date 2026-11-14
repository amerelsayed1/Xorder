import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'widgets.dart';

/// A shift time ("18:05"), in the handheld's own time zone and locale.
String shiftTime(BuildContext context, DateTime at) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));

/// Signed in with no shift open: the one thing to do is start it (waiter
/// shift clock). Tables are worked on the clock, so the floor waits behind
/// this screen; the server refuses them too.
class ShiftStartScreen extends ConsumerStatefulWidget {
  const ShiftStartScreen({super.key});

  @override
  ConsumerState<ShiftStartScreen> createState() => _ShiftStartScreenState();
}

class _ShiftStartScreenState extends ConsumerState<ShiftStartScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = ref.read(waiterAppProvider.notifier);
    try {
      await app.startShift();
    } on WaiterLinkFailure catch (e) {
      if (await app.absorb(e)) return;
      if (mounted) setState(() => _error = WaiterStrings.of(context).failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final staff = ref.watch(waiterAppProvider.select((a) => a.staff));
    return Scaffold(
      backgroundColor: WaiterColors.shell,
      appBar: AppBar(
        backgroundColor: WaiterColors.shell,
        foregroundColor: WaiterColors.shellText,
        shape: const Border(bottom: BorderSide(color: WaiterColors.shellLine)),
        title: Text(s.appTitle),
        actions: [
          IconButton(
            tooltip: s.signOutAction,
            onPressed: ref.read(waiterAppProvider.notifier).signOut,
            icon: const Icon(Icons.logout),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(alignment: AlignmentDirectional.centerStart, child: XorderMark()),
                    const SizedBox(height: WaiterSpace.lg),
                    Text(s.shiftStartTitle, style: WaiterText.heading()),
                    if (staff != null) ...[
                      const SizedBox(height: WaiterSpace.xs),
                      Text(staff.name, style: WaiterText.meta(color: WaiterColors.shellMuted)),
                    ],
                    const SizedBox(height: WaiterSpace.md),
                    Text(s.shiftStartIntro, style: WaiterText.body()),
                    if (_error != null) ...[
                      const SizedBox(height: WaiterSpace.md),
                      ErrorNote(_error!),
                    ],
                    const SizedBox(height: WaiterSpace.xl),
                    PrimaryCta(key: const Key('shift-start'), label: s.shiftStartAction, busy: _busy, onPressed: _start),
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

/// Under the floor's title: since when the waiter has been on shift, and for
/// how long (refreshed with the floor).
class ShiftSubtitle extends StatelessWidget {
  const ShiftSubtitle(this.shift, {super.key, required this.now});

  final WaiterShift shift;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    return Text(
      '${s.shiftSince(shiftTime(context, shift.startedAt))} · ${s.duration(shift.length(now))}',
      key: const Key('shift-since'),
      style: WaiterText.meta(),
    );
  }
}

/// Ask, then finish the waiter's shift. Says how long it ran once it has.
Future<void> confirmFinishShift(BuildContext context, WidgetRef ref, WaiterShift shift) async {
  final s = WaiterStrings.of(context);
  final since = shiftTime(context, shift.startedAt);
  final length = s.duration(shift.length(DateTime.now()));
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.shiftFinishTitle),
      content: Text(s.shiftFinishConfirm(since, length)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
        FilledButton(
          key: const Key('shift-finish-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(s.shiftFinishAction),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final app = ref.read(waiterAppProvider.notifier);
  try {
    final finished = await app.finishShift();
    messenger.showSnackBar(SnackBar(
      content: Text(finished == null ? s.noOpenShift : s.shiftFinished(s.duration(finished.length(DateTime.now())))),
      backgroundColor: WaiterColors.ink,
    ));
  } on WaiterLinkFailure catch (e) {
    if (await app.absorb(e)) return;
    messenger.showSnackBar(SnackBar(content: Text(s.failure(e)), backgroundColor: WaiterColors.danger));
  }
}
