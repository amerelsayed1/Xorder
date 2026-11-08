import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_module/features/admin_mode/admin_session.dart';

/// Locks Admin Mode when nobody has touched it for the configured time.
///
/// **A widget, not a timer inside the session.** Activity is something that
/// happens to what is on screen — a tap, a scroll, a key — and a timer owned by
/// the session would outlive the screen it was measuring. The session answers
/// the question ([AdminSessionController.isIdle]); this only asks it at the
/// moment the answer could have changed.
class AdminActivityWatch extends ConsumerStatefulWidget {
  const AdminActivityWatch({
    required this.onIdle,
    required this.child,
    super.key,
  });

  /// Called once the session has gone the whole timeout untouched.
  final VoidCallback onIdle;

  final Widget child;

  @override
  ConsumerState<AdminActivityWatch> createState() => _AdminActivityWatchState();
}

class _AdminActivityWatchState extends ConsumerState<AdminActivityWatch> {
  late final AdminSessionController _admin;
  late final DateTime Function() _now;
  Timer? _timer;
  DateTime? _lastSeen;

  @override
  void initState() {
    super.initState();
    _admin = ref.read(adminSessionProvider.notifier);
    _now = ref.read(adminClockProvider);
    // Keys anywhere, not only in a focused field of this subtree: typing into a
    // dialog over the back office is somebody still being there.
    HardwareKeyboard.instance.addHandler(_onKey);
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _seen();
    return false;
  }

  /// Throttled: a mouse crossing a list reports many times a second, and a
  /// timeout counted in minutes needs one mark a second at most.
  void _seen() {
    final now = _now();
    final last = _lastSeen;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastSeen = now;
    _admin.touch();
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    final at = _admin.locksAt;
    if (at == null) return;
    final wait = at.difference(_now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _check);
  }

  void _check() {
    if (!mounted) return;
    if (_admin.isIdle) {
      widget.onIdle();
    } else {
      _arm();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _seen(),
    onPointerMove: (_) => _seen(),
    onPointerHover: (_) => _seen(),
    onPointerSignal: (_) => _seen(),
    child: widget.child,
  );
}
