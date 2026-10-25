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
/// **In memory, and lost on restart — on purpose for now.** Restarting the till
/// is neither quiet nor quick, and it is the one way round this; ADR-006 asks
/// for the count to be persisted in the database, which needs the per-till
/// roles of Phase 1 to be worth anything (a till credential that can write its
/// own lockout row can also delete it). Until then a file beside the config
/// would be a second store to keep in step for no real gain.
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
  }) : assert(maxFailures > 0 && terminalCeiling > 0),
       _clock = clock ?? DateTime.now;

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
  /// day on a Friday night is a restaurant that cannot close its shift.
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
  final _keys = <String, _Count>{};
  final _terminal = _Count();

  /// How long [key] must still wait, or null when it may be tried now.
  ///
  /// Asked **before** the PIN is looked at, so a guess made while the door is
  /// shut is not a guess at all — not even a right one.
  Duration? lockedFor(String key) {
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
  AttemptFailure fail(String key) {
    final now = _clock();
    final count = _keys.putIfAbsent(_normalise(key), _Count.new);
    count.miss(now, maxFailures, _lockoutFor);
    _terminal.miss(now, terminalCeiling, _lockoutFor);

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
    _keys.remove(_normalise(key));
    _terminal.clear();
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

  void clear() {
    failures = 0;
    lockouts = 0;
    lockedUntil = null;
  }
}
