import 'dart:async';
import 'dart:convert';

import 'attempt_store.dart';

/// How many wrong PINs a door takes before it shuts, and for how long.
///
/// **One rule, lifted out of Admin Mode.** Admin Mode's door had it — five
/// wrong tries, then thirty seconds doubling to fifteen minutes — and nothing
/// else did: the lock screen and the open-shift sign-in took guesses as fast
/// as somebody could type them, and the supervisor keypad changed its message
/// after five and went on checking. A copy of the counting in each of those
/// would have been four rules that drift; this is the one they all ask.
///
/// Counted twice over:
///
/// * **Per key** — the username being tried, normalised, or a fixed key for a
///   door that asks for no name. Five wrong in a row against one name shuts
///   that name.
/// * **Per terminal** — every failure on this limiter, whichever key it was
///   against, up to [terminalCeiling]. Without it, counting per name lets
///   somebody walk the PIN space by trying a different name each time — four
///   guesses under each of fifty usernames is two hundred guesses and no
///   lockout. The ceiling is what makes spreading them pointless.
///
/// **A key is counted whether or not it names anybody.** The limiter is never
/// told which usernames exist, so a name nobody has and a name with the wrong
/// PIN are refused with the same count and the same wait — a door that locked
/// only real names would be a way of finding out which ones are real.
///
/// **Kept across restarts** (security audit F1). Given an [AttemptStore] the
/// limiter saves its count after every change and [load]s it at start, so
/// closing and reopening the till is no longer five fresh guesses. Until the
/// load has finished, [lockedFor] answers with a short wait rather than "not
/// locked": a door must not open for the few milliseconds it takes to read.
/// Without a store it is in memory only, which is what tests use.
///
/// **Counted before the PIN is looked at.** [reserve] records a try and waits
/// for it to be saved *before* the PIN is compared, so ending the app between
/// a guess and its answer does not make the guess free. [succeed] and
/// [release] give it back.
///
/// What this does not defend: moving the clock **forward** shortens a wait (a
/// clock that goes back is caught on load), and somebody who can delete the
/// store's contents can reset the count — they already own the machine.
///
/// Pure Dart with an injectable clock, so the whole rule is unit-tested without
/// waiting thirty seconds or building a widget.
class AttemptLimiter {
  AttemptLimiter({
    DateTime Function()? clock,
    this.maxFailures = defaultMaxFailures,
    this.terminalCeiling = defaultTerminalCeiling,
    this.firstLockout = defaultFirstLockout,
    this.longestLockout = defaultLongestLockout,
    AttemptStore? store,
  }) : assert(maxFailures > 0 && terminalCeiling > 0),
       _clock = clock ?? DateTime.now,
       _store = store,
       _loaded = store == null;

  /// Five wrong tries, then the door shuts. Enough that a manager mistyping
  /// under pressure is not shut out, few enough that a door is not a way to
  /// walk a four-digit space.
  static const defaultMaxFailures = 5;

  /// Twice the per-name number: two people fumbling their own PINs in a rush
  /// do not shut the till on each other, and somebody spreading guesses across
  /// names gets ten for the whole terminal rather than five per name.
  static const defaultTerminalCeiling = 10;

  /// The first wait, doubled for every lockout since the last PIN that got
  /// somebody in. Thirty seconds is nothing to a cashier who fat-fingered it;
  /// doubling makes the ten thousand PINs a matter of weeks, not an afternoon.
  static const defaultFirstLockout = Duration(seconds: 30);

  /// Capped, because this also shuts out the owner, and a door locked for a
  /// day on a Friday night is a business that cannot close its shift.
  static const defaultLongestLockout = Duration(minutes: 15);

  /// The key for a door that asks for no name — Admin Mode's single count, the
  /// supervisor keypad's PIN alone. Every failure there is the same key, so
  /// the per-key and the per-terminal counts move together.
  static const anyone = '';

  final int maxFailures;
  final int terminalCeiling;
  final Duration firstLockout;
  final Duration longestLockout;

  final DateTime Function() _clock;
  final AttemptStore? _store;
  final _keys = <String, _Count>{};
  final _terminal = _Count();

  /// Keys with a [reserve]d try that has no answer yet.
  final _pending = <String>{};

  bool _loaded;
  Future<void> _saving = Future.value();

  /// Most names kept. A name nobody has still counts (so real and unknown
  /// names look alike), which would let typed names grow the saved state
  /// without end; the oldest unlocked ones are dropped past this.
  static const maxKeys = 100;

  /// Whether the saved count has been read. A limiter with no store is always
  /// loaded.
  bool get loaded => _loaded;

  /// Read the saved count. Never throws: a store that cannot be asked starts
  /// empty (the till could not sign anybody in without it anyway), and a saved
  /// count that cannot be understood starts the terminal **locked** for the
  /// first wait, because a damaged count is not a reason to open the door.
  Future<void> load() => _loading ??= _load();

  Future<void>? _loading;

  /// Completes once the saved count has been read. The doors wait on this
  /// before asking [lockedFor], so the first PIN after a start is not met with
  /// "wait a moment".
  Future<void> get ready => load();

  Future<void> _load() async {
    final store = _store;
    if (store == null || _loaded) {
      _loaded = true;
      return;
    }
    try {
      final raw = await store.read();
      if (raw != null) _restore(raw);
    } on Object {
      // Cannot be asked, or cannot be understood: see above. A store that
      // threw reading is treated as empty; a snapshot that failed to parse
      // is handled inside [_restore].
    } finally {
      _loaded = true;
    }
  }

  /// Completes when every change so far has been saved.
  Future<void> get saved => _saving;

  /// How long [key] must still wait, or null when it may be tried now.
  ///
  /// Asked **before** the PIN is looked at, so a guess made while the door is
  /// shut is not a guess at all — not even a right one.
  Duration? lockedFor(String key) {
    // Not read yet: shut for a moment rather than open without knowing.
    if (!_loaded) return const Duration(seconds: 1);
    final now = _clock();
    final waits = [
      _terminal.remaining(now),
      _keys[_normalise(key)]?.remaining(now),
    ].whereType<Duration>();
    if (waits.isEmpty) return null;
    return waits.reduce((a, b) => a > b ? a : b);
  }

  /// One more wrong try against [key].
  ///
  /// Synchronous, so two submits racing each other cannot both be the fourth.
  ///
  /// A try that was [reserve]d is already counted: this only reads off what
  /// that came to.
  AttemptFailure fail(String key) {
    final now = _clock();
    final name = _normalise(key);
    final count = _keys.putIfAbsent(name, _Count.new);
    if (!_pending.remove(name)) {
      count.miss(now, maxFailures, _lockoutFor);
      _terminal.miss(now, terminalCeiling, _lockoutFor);
      _save();
    }

    final wait = lockedFor(key);
    if (wait != null) return AttemptLockedOut(wait);
    final left = [
      maxFailures - count.failures,
      terminalCeiling - _terminal.failures,
    ].reduce((a, b) => a < b ? a : b);
    return AttemptRefused(left);
  }

  /// A PIN that got somebody in: [key]'s count and backoff start again, and
  /// so does the terminal's.
  ///
  /// The terminal's too, because the ceiling exists for somebody who knows no
  /// PIN at all — and they never get here. Somebody who does know one, their
  /// own, and signs in between guesses at colleagues is still held by each
  /// colleague's own count, which this does not touch.
  void succeed(String key) {
    _pending.remove(_normalise(key));
    _keys.remove(_normalise(key));
    _terminal.clear();
    _save();
  }

  /// Count a try against [key] **now** and wait until it is saved, before the
  /// PIN is compared. Answer it with [succeed] (right), [fail] (wrong) or
  /// [release] (nothing was checked). Ending the app in between leaves the try
  /// counted, which is the point.
  Future<void> reserve(String key) {
    final name = _normalise(key);
    // A second reserve for a name already waiting is the same try.
    if (_pending.add(name)) {
      final now = _clock();
      _keys.putIfAbsent(name, _Count.new).miss(now, maxFailures, _lockoutFor);
      _terminal.miss(now, terminalCeiling, _lockoutFor);
    }
    return _save();
  }

  /// Give a [reserve]d try back: nothing was checked, so nothing is counted
  /// (the platform was unreachable, say).
  void release(String key) {
    final name = _normalise(key);
    if (!_pending.remove(name)) return;
    _keys[name]?.unmiss();
    _terminal.unmiss();
    _save();
  }

  Future<void> _save() {
    final store = _store;
    if (store == null) return Future.value();
    _trim();
    final snapshot = _snapshot();
    // One write after another, in order; a failed write must not break the
    // chain or the sign-in that asked.
    return _saving = _saving
        .then((_) => store.write(snapshot))
        .catchError((Object _) {});
  }

  void _trim() {
    if (_keys.length <= maxKeys) return;
    final now = _clock();
    for (final name in _keys.keys.toList()) {
      if (_keys.length <= maxKeys) break;
      if (_pending.contains(name)) continue;
      if (_keys[name]!.remaining(now) == null) _keys.remove(name);
    }
  }

  String _snapshot() => jsonEncode({
    'v': 1,
    'savedAt': _clock().millisecondsSinceEpoch,
    'terminal': _terminal.toJson(),
    'keys': {for (final e in _keys.entries) e.key: e.value.toJson()},
  });

  void _restore(String raw) {
    final now = _clock();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      // The clock went back since this was saved: lengthen what is left by the
      // difference, so winding it back is not a way out.
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        json['savedAt'] as int,
      );
      final skew = savedAt.isAfter(now)
          ? savedAt.difference(now)
          : Duration.zero;
      _terminal.restore(json['terminal'] as Map<String, dynamic>, skew);
      for (final e in (json['keys'] as Map<String, dynamic>).entries) {
        _keys[e.key] = _Count()
          ..restore(e.value as Map<String, dynamic>, skew);
      }
    } on Object {
      _keys.clear();
      _terminal
        ..clear()
        ..lockouts = 1
        ..lockedUntil = now.add(firstLockout);
    }
  }

  /// Whole seconds, rounded up: "0 seconds" on a door that is still shut is a
  /// lie, and so is "try again now" a moment before it opens.
  static int secondsToWait(Duration wait) => (wait.inMilliseconds + 999) ~/ 1000;

  Duration _lockoutFor(int lockouts) {
    var wait = firstLockout;
    for (var i = 1; i < lockouts && wait < longestLockout; i++) {
      wait *= 2;
    }
    return wait > longestLockout ? longestLockout : wait;
  }

  /// Usernames are matched case-blind and trimmed at every door, so they are
  /// counted the same way: "Rana" and "rana " are one person's count.
  static String _normalise(String key) => key.trim().toLowerCase();
}

/// What a wrong try came to.
sealed class AttemptFailure {
  const AttemptFailure();
}

/// Refused, and this many more before the door shuts.
final class AttemptRefused extends AttemptFailure {
  const AttemptRefused(this.attemptsLeft);

  final int attemptsLeft;
}

/// That try shut the door. Nothing is checked until [wait] has passed.
final class AttemptLockedOut extends AttemptFailure {
  const AttemptLockedOut(this.wait);

  final Duration wait;
}

class _Count {
  int failures = 0;
  int lockouts = 0;
  DateTime? lockedUntil;

  Duration? remaining(DateTime now) {
    final until = lockedUntil;
    if (until == null) return null;
    final wait = until.difference(now);
    if (wait > Duration.zero) return wait;
    lockedUntil = null;
    return null;
  }

  void miss(DateTime now, int limit, Duration Function(int) lockoutFor) {
    failures++;
    if (failures < limit) return;
    failures = 0;
    lockouts++;
    lockedUntil = now.add(lockoutFor(lockouts));
  }

  /// Undo one [miss] that was never answered (a [release]). Only a count that
  /// has not rolled into a lockout is given back; a lockout it caused is lifted
  /// by the caller's next [succeed] or runs out as normal.
  void unmiss() {
    if (failures > 0) failures--;
  }

  void clear() {
    failures = 0;
    lockouts = 0;
    lockedUntil = null;
  }

  Map<String, dynamic> toJson() => {
    'f': failures,
    'l': lockouts,
    if (lockedUntil != null) 'u': lockedUntil!.millisecondsSinceEpoch,
  };

  void restore(Map<String, dynamic> json, Duration skew) {
    failures = json['f'] as int;
    lockouts = json['l'] as int;
    final until = json['u'] as int?;
    lockedUntil = until == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(until).add(skew);
  }
}
