import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import 'lock_screen.dart';

/// Five minutes without a touch or a key, and the till locks: ADR-006's
/// accepted number.
const tillIdleTimeout = Duration(minutes: 5);

/// [tillIdleTimeout], as a provider only so a test can say how long it is.
///
/// **Not a setting.** There is no screen for it on purpose: the number is a
/// security rule the business accepted, and a till where somebody behind the
/// counter could make it a day is a till where somebody would.
final tillIdleTimeoutProvider = Provider<Duration>((ref) => tillIdleTimeout);

/// Signs the cashier out after [tillIdleTimeout] with nobody at the till, and
/// sends a till with a shift open to the lock screen.
///
/// **One, at the root, above the router** (`XorderPosApp`'s builder), rather
/// than a watch on each selling screen: the sale screen, the floor and the
/// order history are three screens and every dialog over them, and a watch on
/// each is a screen somebody adds later without one. Activity is any pointer
/// over the window and any key through [HardwareKeyboard] — the sale screen is
/// driven from the keyboard, so a cashier typing a search with the mouse
/// parked is somebody still there.
///
/// **What it does not do:**
///
/// * Lock with nobody signed in, or before the till is set up — the welcome
///   screen and the wizard have nobody to sign out.
/// * Lock while [IdleLockGuard] is held — a payment part-way through.
/// * Lock Admin Mode, which has its own watch and timeout; while the back
///   office is open this waits, and locks the till the moment it closes if
///   nobody has touched anything since.
/// * Touch the ticket. [ticketProvider] is left exactly as it was; see
///   [LockScreen] for what happens when somebody else signs in over it.
///
/// **Signs out, where Lock does not.** Lock keeps whoever pressed it signed in
/// until somebody signs in over them — they are standing there. A till nobody
/// has touched for five minutes has nobody standing at it, and the redirect in
/// `routerProvider` ([needsSignIn]) is what keeps a signed-out till off the
/// selling screens; this uses the same rule to decide where to go.
class TillIdleLock extends ConsumerStatefulWidget {
  const TillIdleLock({required this.child, super.key});

  /// How soon to look again when the lock was due but held off. Short, so a
  /// payment that finishes with nobody touching anything afterwards locks
  /// within seconds rather than a whole timeout later.
  static const heldRetry = Duration(seconds: 5);

  final Widget child;

  @override
  ConsumerState<TillIdleLock> createState() => _TillIdleLockState();
}

class _TillIdleLockState extends ConsumerState<TillIdleLock> {
  Timer? _timer;
  late DateTime _lastSeen;

  DateTime _now() => ref.read(tillClockProvider)();

  @override
  void initState() {
    super.initState();
    _lastSeen = _now();
    // Keys anywhere, focused field or not: the sale screen's shortcuts and a
    // dialog's keypad are all somebody at the till.
    HardwareKeyboard.instance.addHandler(_onKey);
    _arm(ref.read(tillIdleTimeoutProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _seen();
    // Seen, never handled: the key goes on to whatever it was for.
    return false;
  }

  /// A mark, not a re-armed timer: a mouse crossing a list reports many times
  /// a second, and the timer works out what is left when it fires.
  void _seen() => _lastSeen = _now();

  void _arm(Duration wait) {
    _timer?.cancel();
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _check);
  }

  void _check() {
    if (!mounted) return;
    final timeout = ref.read(tillIdleTimeoutProvider);
    final idle = _now().difference(_lastSeen);
    if (idle < timeout) {
      _arm(timeout - idle);
      return;
    }
    _arm(_lock() ? timeout : TillIdleLock.heldRetry);
  }

  /// True when there is nothing more to do — locked, or nothing to lock —
  /// and false when the lock is due but something is holding it off.
  bool _lock() {
    if (ref.read(signedInStaffProvider) == null) return true;
    if (!ref.read(setupCompleteProvider)) return true;
    if (ref.read(idleLockGuardProvider).isHeld) return false;

    final router = ref.read(routerProvider);
    final at = router.routerDelegate.currentConfiguration.uri.path;
    if (at == PosRoutes.welcome || at == PosRoutes.setup) return true;
    // Admin Mode's own watch owns that screen. Signing the till out from under
    // it would change nothing there, and its exit lands back on the till,
    // where the next look finds the till idle and locks it.
    if (at == PosRoutes.management) return false;

    ref.read(signedInStaffProvider.notifier).signOut();

    // Home belongs to whoever signed in, shift or no shift (pos-signin-first-
    // home). Signed out under it, it would be an empty screen on a counter, so
    // it goes to Start — the signed-out door — rather than to a lock screen.
    if (at == PosRoutes.home) {
      router.go(PosRoutes.start);
      return true;
    }

    final shiftOpen = ref.read(shiftProvider).valueOrNull != null;
    // The order history is a till screen too — receipts, refunds and
    // reprints — but outside the redirect's rule, which is about selling.
    // Left there signed out, it would show the day's sales to whoever walks
    // up; sent to the lock screen, it is a name and a PIN away.
    if (needsSignIn(at: at, signedIn: false, shiftOpen: shiftOpen) ||
        (at == PosRoutes.orders && shiftOpen)) {
      router.go(lockLocationFrom(at), extra: LockReason.inactivity);
    }
    return true;
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
