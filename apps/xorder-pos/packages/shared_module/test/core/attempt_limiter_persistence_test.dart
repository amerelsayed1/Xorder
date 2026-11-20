import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/security/attempt_limiter.dart';
import 'package:shared_module/core/security/attempt_store.dart';

/// The count survives the app being closed (security audit F1).
void main() {
  late DateTime now;
  late MemoryAttemptStore store;

  AttemptLimiter open() => AttemptLimiter(clock: () => now, store: store);

  Future<AttemptLimiter> reopen() async {
    final limiter = open();
    await limiter.load();
    return limiter;
  }

  setUp(() {
    now = DateTime.utc(2026, 11, 20, 12);
    store = MemoryAttemptStore();
  });

  test('a lockout is still there after a restart', () async {
    final first = await reopen();
    for (var i = 0; i < 5; i++) {
      first.fail('rana');
    }
    await first.saved;

    final second = await reopen();
    expect(second.lockedFor('rana'), const Duration(seconds: 30));
    now = now.add(const Duration(seconds: 30));
    expect(second.lockedFor('rana'), isNull);
  });

  test('failures short of a lockout carry over too', () async {
    final first = await reopen();
    first.fail('rana');
    first.fail('rana');
    await first.saved;

    final second = await reopen();
    expect((second.fail('rana') as AttemptRefused).attemptsLeft, 2);
  });

  test('the terminal-wide count survives, across different names', () async {
    final first = await reopen();
    for (var i = 0; i < 10; i++) {
      first.fail('name$i');
    }
    await first.saved;

    final second = await reopen();
    expect(second.lockedFor('somebody-new'), isNotNull);
  });

  test('a guess that was reserved is counted even if the app ends', () async {
    final first = await reopen();
    for (var i = 0; i < 4; i++) {
      await first.reserve('rana');
      first.fail('rana');
    }
    // The fifth guess is reserved and saved, then the app is killed before
    // the PIN is compared or fail() is ever called.
    await first.reserve('rana');

    final second = await reopen();
    expect(second.lockedFor('rana'), const Duration(seconds: 30));
  });

  test('reserve then fail counts one try, not two', () async {
    final limiter = await reopen();
    await limiter.reserve('rana');
    expect((limiter.fail('rana') as AttemptRefused).attemptsLeft, 4);
  });

  test('a right PIN clears the saved count', () async {
    final first = await reopen();
    await first.reserve('rana');
    first.fail('rana');
    await first.reserve('rana');
    first.succeed('rana');
    await first.saved;

    final second = await reopen();
    expect((second.fail('rana') as AttemptRefused).attemptsLeft, 4);
  });

  test('release gives a try back when nothing was checked', () async {
    final limiter = await reopen();
    await limiter.reserve('rana');
    limiter.release('rana');
    await limiter.saved;
    expect((limiter.fail('rana') as AttemptRefused).attemptsLeft, 4);
    expect((await reopen()).lockedFor('rana'), isNull);
  });

  test(
    'the fifth, correct PIN still gets in: succeed lifts the lock',
    () async {
      final limiter = await reopen();
      for (var i = 0; i < 4; i++) {
        await limiter.reserve('rana');
        limiter.fail('rana');
      }
      await limiter.reserve('rana');
      limiter.succeed('rana');
      expect(limiter.lockedFor('rana'), isNull);
    },
  );

  test('shut until the saved count has been read', () {
    final limiter = open();
    expect(limiter.loaded, isFalse);
    expect(limiter.lockedFor('rana'), isNotNull);
  });

  test('winding the clock back does not shorten a lockout', () async {
    final first = await reopen();
    for (var i = 0; i < 5; i++) {
      first.fail('rana');
    }
    await first.saved;

    now = now.subtract(const Duration(hours: 2));
    final second = await reopen();
    expect(
      second.lockedFor('rana')!,
      greaterThanOrEqualTo(const Duration(hours: 2)),
    );
  });

  test('a damaged count starts the terminal shut, not open', () async {
    store.snapshot = 'not json at all';
    final limiter = await reopen();
    expect(limiter.lockedFor('anyone'), const Duration(seconds: 30));
  });

  test('a store that cannot be read starts empty and does not throw', () async {
    final limiter = AttemptLimiter(clock: () => now, store: _Broken());
    await limiter.load();
    expect(limiter.lockedFor('rana'), isNull);
    // And a write that fails does not break signing in.
    await limiter.reserve('rana');
    limiter.succeed('rana');
  });

  test('typed names cannot grow the saved count without end', () async {
    final limiter = await reopen();
    for (var i = 0; i < 300; i++) {
      limiter.fail('name$i');
    }
    await limiter.saved;
    expect(store.snapshot!.length, lessThan(20000));
  });
}

class _Broken implements AttemptStore {
  @override
  Future<String?> read() async => throw StateError('keychain locked');

  @override
  Future<void> write(String snapshot) async => throw StateError('no');
}
