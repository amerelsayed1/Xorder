import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/password_sign_in.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/features/lock/lock_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// tablet-cloud-onboarding, Stage 4 (Q1): the cloud till's lock screen takes a
/// username and password, verified by the platform, with the PIN kept for when
/// the platform cannot be reached. AC-5, AC-6, AC-13, BR-2.
class _Platform implements PlatformPasswordCheck {
  _Platform(this.verdict);

  PasswordVerdict verdict;
  final asked = <(String, String)>[];

  @override
  Future<PasswordVerdict> verify({
    required String username,
    required String password,
  }) async {
    asked.add((username, password));
    return verdict;
  }
}

void main() {
  late DateTime now;
  setUp(() => now = DateTime.utc(2026, 11, 19, 9));

  Future<ProviderContainer> pumpLock(
    WidgetTester tester, {
    PlatformPasswordCheck? platform,
    VoidCallback? onUnlocked,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        tillClockProvider.overrideWithValue(() => now),
        if (platform != null)
          platformPasswordCheckProvider.overrideWithValue(platform),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: LockScreen(
            key: UniqueKey(),
            onUnlocked: onUnlocked ?? () {},
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> usePassword(
    WidgetTester tester, {
    required String username,
    required String password,
  }) async {
    // Password is the default where the platform can check one.
    await tester.enterText(find.byType(TextField).first, username);
    await tester.enterText(find.byKey(const Key('lock-password')), password);
    await tester.tap(find.byKey(const Key('lock-password-submit')));
    await tester.pumpAndSettle();
  }

  String message(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('lock-message'))).data!;

  group('the service', () {
    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    tearDownAll(container.dispose);

    PasswordSignIn service(PasswordVerdict verdict) => PasswordSignIn(
      check: _Platform(verdict),
      roster: () => container
          .read(staffDirectoryRepositoryProvider)
          .all(includeInactive: false),
    );

    test(
      'a verified password signs in the person the till already has',
      () async {
        final result = await service(PasswordVerdict.verified)
            .signIn(username: ' Rana ', password: 'pw');
        expect(result, isA<PasswordSignedIn>());
        expect((result as PasswordSignedIn).staff.name, 'Rana A.');
      },
    );

    test('a rejected password is refused', () async {
      expect(
        await service(PasswordVerdict.rejected)
            .signIn(username: 'rana', password: 'bad'),
        isA<PasswordRefused>(),
      );
    });

    test('a verified name the till does not have is not signed in', () async {
      expect(
        await service(PasswordVerdict.verified)
            .signIn(username: 'ghost', password: 'pw'),
        isA<PasswordAccountNotOnTill>(),
      );
    });

    test('no connection and a throttled login are their own answers', () async {
      expect(
        await service(PasswordVerdict.unreachable)
            .signIn(username: 'rana', password: 'pw'),
        isA<PasswordUnreachable>(),
      );
      expect(
        await service(PasswordVerdict.throttled)
            .signIn(username: 'rana', password: 'pw'),
        isA<PasswordThrottled>(),
      );
    });

    test('an empty name or password never reaches the platform', () async {
      final platform = _Platform(PasswordVerdict.verified);
      final s = PasswordSignIn(check: platform, roster: () async => []);
      expect(
        await s.signIn(username: '', password: 'x'),
        isA<PasswordRefused>(),
      );
      expect(
        await s.signIn(username: 'rana', password: ''),
        isA<PasswordRefused>(),
      );
      expect(platform.asked, isEmpty);
    });
  });

  group('the lock screen', () {
    testWidgets('offers the password only where there is a platform to ask', (
      tester,
    ) async {
      await pumpLock(tester);
      expect(find.byKey(const Key('lock-mode-toggle')), findsNothing);
    });

    testWidgets(
      'a verified password unlocks the till, and the field is empty',
      (tester) async {
        final platform = _Platform(PasswordVerdict.verified);
        var unlocked = false;
        final container = await pumpLock(
          tester,
          platform: platform,
          onUnlocked: () => unlocked = true,
        );

        await usePassword(tester, username: 'rana', password: 'pw-123');

        expect(platform.asked, [('rana', 'pw-123')]);
        expect(unlocked, isTrue);
        expect(container.read(signedInStaffProvider)?.name, 'Rana A.');
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('lock-password')))
              .controller!
              .text,
          isEmpty,
        );
      },
    );

    testWidgets('a wrong password says one thing and clears the field', (
      tester,
    ) async {
      final container = await pumpLock(
        tester,
        platform: _Platform(PasswordVerdict.rejected),
      );

      await usePassword(tester, username: 'rana', password: 'bad');

      expect(message(tester), 'Wrong username or password — try again');
      expect(container.read(signedInStaffProvider), isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('lock-password')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('five wrong passwords shut the door, even for a right one', (
      tester,
    ) async {
      final platform = _Platform(PasswordVerdict.rejected);
      final container = await pumpLock(tester, platform: platform);

      await usePassword(tester, username: 'rana', password: 'bad');
      for (var i = 0; i < 4; i++) {
        await tester.enterText(find.byKey(const Key('lock-password')), 'bad');
        await tester.tap(find.byKey(const Key('lock-password-submit')));
        await tester.pumpAndSettle();
      }
      expect(message(tester), startsWith('Too many wrong attempts'));
      final before = platform.asked.length;

      platform.verdict = PasswordVerdict.verified;
      await tester.enterText(find.byKey(const Key('lock-password')), 'good');
      await tester.tap(find.byKey(const Key('lock-password-submit')));
      await tester.pumpAndSettle();

      expect(platform.asked.length, before, reason: 'a shut door asks nobody');
      expect(container.read(signedInStaffProvider), isNull);
    });

    testWidgets('no connection says so and the PIN still works', (
      tester,
    ) async {
      var unlocked = false;
      final container = await pumpLock(
        tester,
        platform: _Platform(PasswordVerdict.unreachable),
        onUnlocked: () => unlocked = true,
      );

      await usePassword(tester, username: 'rana', password: 'pw');
      expect(message(tester), contains('Cannot reach XOrder'));
      expect(unlocked, isFalse);

      // Back to the PIN, which is checked on the till itself.
      await tester.tap(find.byKey(const Key('lock-mode-toggle')));
      await tester.pumpAndSettle();
      for (final digit in '1234'.split('')) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(unlocked, isTrue);
      expect(container.read(signedInStaffProvider)?.name, 'Rana A.');
    });

    testWidgets('a throttled login is not called a wrong password', (
      tester,
    ) async {
      await pumpLock(tester, platform: _Platform(PasswordVerdict.throttled));

      await usePassword(tester, username: 'rana', password: 'pw');

      expect(message(tester), contains('Too many sign-in attempts'));
    });

    testWidgets('a person the platform knows and the till does not', (
      tester,
    ) async {
      final container = await pumpLock(
        tester,
        platform: _Platform(PasswordVerdict.verified),
      );

      await usePassword(tester, username: 'ghost', password: 'pw');

      expect(message(tester), contains('not on this till yet'));
      expect(container.read(signedInStaffProvider), isNull);
    });
  });
}
