import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/security/attempt_limiter.dart';

/// The rule every PIN door at the till asks: five wrong against a name, ten
/// across names, then thirty seconds doubling to fifteen minutes.
///
/// On a clock the test moves, so nothing here waits.
void main() {
  late DateTime now;
  late AttemptLimiter limiter;

  setUp(() {
    now = DateTime.utc(2026, 10, 25, 20);
    limiter = AttemptLimiter(clock: () => now);
  });

  void wrong(int times, [String key = 'rana']) {
    for (var i = 0; i < times; i++) {
      limiter.fail(key);
    }
  }

  group('one name', () {
    test('each refusal says how many tries are left', () {
      expect((limiter.fail('rana') as AttemptRefused).attemptsLeft, 4);
      expect((limiter.fail('rana') as AttemptRefused).attemptsLeft, 3);
      expect(limiter.lockedFor('rana'), isNull);
    });

    test('the fifth shuts the door for thirty seconds', () {
      wrong(4);
      expect(
        (limiter.fail('rana') as AttemptLockedOut).wait,
        const Duration(seconds: 30),
      );

      now = now.add(const Duration(seconds: 29));
      expect(limiter.lockedFor('rana'), const Duration(seconds: 1));

      now = now.add(const Duration(seconds: 1));
      expect(limiter.lockedFor('rana'), isNull, reason: 'open again');
    });

    test('each lockout in a row waits twice as long, up to fifteen minutes', () {
      final waits = <Duration>[];
      for (var i = 0; i < 7; i++) {
        wrong(4);
        final shut = limiter.fail('rana') as AttemptLockedOut;
        waits.add(shut.wait);
        now = now.add(shut.wait);
      }
      expect(waits, const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 4),
        Duration(minutes: 8),
        Duration(minutes: 15),
        Duration(minutes: 15),
      ]);
    });

    test('a PIN that gets somebody in clears the count and the backoff', () {
      wrong(5);
      now = now.add(const Duration(seconds: 30));
      wrong(3);
      limiter.succeed('rana');

      expect(
        (limiter.fail('rana') as AttemptRefused).attemptsLeft,
        4,
        reason: 'the count starts again',
      );
      wrong(3);
      expect(
        (limiter.fail('rana') as AttemptLockedOut).wait,
        const Duration(seconds: 30),
        reason: 'and so does the backoff',
      );
    });

    test('names are counted as the doors match them: trimmed, any case', () {
      limiter.fail('Rana');
      limiter.fail(' rana ');
      wrong(2, 'RANA');
      expect(limiter.fail('rana'), isA<AttemptLockedOut>());
    });

    test('a shut name does not shut a colleague', () {
      wrong(5);
      expect(limiter.lockedFor('rana'), isNotNull);
      expect(limiter.lockedFor('amer'), isNull);
    });
  });

  group('the terminal', () {
    test('failures spread across names still shut the till', () {
      // Four under each name never trips a name's own count. Without the
      // ceiling that is the PIN space walked one username at a time.
      wrong(4, 'rana');
      wrong(4, 'amer');
      // Nour has four of their own left and the terminal one: the nearer.
      expect((limiter.fail('nour') as AttemptRefused).attemptsLeft, 1);
      expect(limiter.fail('omar'), isA<AttemptLockedOut>());

      // Shut for everybody — a name never tried before included.
      expect(limiter.lockedFor('somebody-new'), const Duration(seconds: 30));
    });

    test('a success anywhere clears the ceiling, not the other names', () {
      wrong(4, 'rana');
      wrong(4, 'amer');
      limiter.succeed('nour');

      // The terminal count started again…
      wrong(1, 'omar');
      expect(limiter.lockedFor('omar'), isNull);
      // …but Rana's four are still Rana's, so somebody signing in as
      // themselves between guesses at a colleague gains nothing.
      expect(limiter.fail('rana'), isA<AttemptLockedOut>());
    });
  });

  group('no enumeration', () {
    test('a name nobody has is counted exactly as a real one', () {
      // The limiter is never told who exists; this pins that the answers
      // depend only on the tries.
      final real = AttemptLimiter(clock: () => now);
      final ghost = AttemptLimiter(clock: () => now);
      String describe(AttemptFailure f) => switch (f) {
        AttemptRefused(:final attemptsLeft) => 'refused $attemptsLeft',
        AttemptLockedOut(:final wait) => 'shut ${wait.inSeconds}',
      };
      final a = [for (var i = 0; i < 5; i++) describe(real.fail('rana'))];
      final b = [for (var i = 0; i < 5; i++) describe(ghost.fail('nobody'))];
      expect(a, b);
      expect(real.lockedFor('rana'), ghost.lockedFor('nobody'));
    });
  });

  test('waits are said in whole seconds, rounded up', () {
    expect(AttemptLimiter.secondsToWait(const Duration(seconds: 30)), 30);
    expect(
      AttemptLimiter.secondsToWait(const Duration(milliseconds: 29001)),
      30,
    );
    expect(AttemptLimiter.secondsToWait(const Duration(milliseconds: 1)), 1);
  });
}
