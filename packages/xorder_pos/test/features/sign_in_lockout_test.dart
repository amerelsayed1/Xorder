import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin_mode/supervisor_override.dart';
import 'package:xorder_pos/features/lock/lock_screen.dart';
import 'package:xorder_pos/features/shift/presentation/shift_dialogs.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The till's PIN doors shut after five wrong tries (ADR-006, Phase 1).
///
/// The lock screen and the open-shift sign-in took guesses as fast as somebody
/// could type them, and the supervisor keypad said "cannot approve" after five
/// and went on checking every PIN it was given. Each claim here is about a
/// door refusing — the right PIN included — while it is shut.
void main() {
  late DateTime now;

  setUp(() => now = DateTime.utc(2026, 10, 25, 20));

  const shut30 = 'Too many wrong attempts. Try again in 30 seconds.';
  const wrong = 'Wrong username or PIN — try again';

  Future<ProviderContainer> pumpLock(
    WidgetTester tester, {
    VoidCallback? onUnlocked,
    ProviderContainer? container,
    bool afterInactivity = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final scope =
        container ??
        ProviderContainer(
          overrides: [
            ...fakeRepositoryOverrides(),
            tillClockProvider.overrideWithValue(() => now),
          ],
        );
    if (container == null) addTearDown(scope.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: LockScreen(
            key: UniqueKey(),
            afterInactivity: afterInactivity,
            onUnlocked: onUnlocked ?? () {},
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scope;
  }

  Future<void> typeUsername(WidgetTester tester, String username) async {
    await tester.enterText(find.byType(TextField), username);
    await tester.pump();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  String message(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('lock-message'))).data!;

  group('the lock screen', () {
    testWidgets('five wrong PINs shut it, and the right one does not open it', (
      tester,
    ) async {
      var unlocked = false;
      final container = await pumpLock(
        tester,
        onUnlocked: () => unlocked = true,
      );

      await typeUsername(tester, 'rana');
      for (var i = 0; i < 4; i++) {
        await typePin(tester, '9999');
        expect(message(tester), wrong);
      }
      await typePin(tester, '9999');
      expect(message(tester), shut30);

      // Rana's own PIN, typed while the door is shut, is not even checked.
      now = now.add(const Duration(seconds: 29));
      await typePin(tester, '1234');
      expect(unlocked, isFalse);
      expect(container.read(signedInStaffProvider), isNull);
      expect(
        message(tester),
        'Too many wrong attempts. Try again in 1 second.',
      );

      // Once the wait is over it is a PIN like any other.
      now = now.add(const Duration(seconds: 1));
      await typePin(tester, '1234');
      expect(unlocked, isTrue);
      expect(container.read(signedInStaffProvider)?.name, 'Rana A.');
    });

    testWidgets('a name nobody has reads exactly as a wrong PIN does', (
      tester,
    ) async {
      // Five tries under a real name and five under an invented one, on two
      // fresh tills: the same words at every step, and the same lock.
      Future<List<String>> fiveTries(String username) async {
        final container = await pumpLock(tester);
        await typeUsername(tester, username);
        final seen = <String>[];
        for (var i = 0; i < 5; i++) {
          await typePin(tester, '9999');
          seen.add(message(tester));
        }
        // And still shut for the right PIN under that name.
        expect(container.read(signInLimiterProvider).lockedFor(username),
            isNotNull);
        return seen;
      }

      final real = await fiveTries('rana');
      final ghost = await fiveTries('nobody');
      expect(ghost, real);
      expect(real.last, shut30);
    });

    testWidgets('the same door is shut in the open-shift sign-in', (
      tester,
    ) async {
      // One count for both: they take the same names and PINs, and a count
      // per door would be five more guesses for every lockout.
      final container = await pumpLock(tester);
      await typeUsername(tester, 'rana');
      for (var i = 0; i < 5; i++) {
        await typePin(tester, '9999');
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildPosTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => OpenShiftDialog.show(context),
                  child: const Text('open shift'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open shift'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'rana');
      await tester.pump();
      await typePin(tester, '1234');

      expect(find.text(shut30), findsOneWidget);
      // Still asking who: nobody got as far as the float.
      expect(find.text('Open the drawer'), findsNothing);
      expect(container.read(signedInStaffProvider), isNull);
    });

    testWidgets('says when it was the till that locked, not somebody', (
      tester,
    ) async {
      await pumpLock(tester, afterInactivity: true);
      expect(
        find.text(
          'Locked after inactivity. The ticket is kept — sign in to carry on.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('and says nothing of the kind after Lock', (tester) async {
      await pumpLock(tester);
      expect(find.byKey(const Key('lock-after-inactivity')), findsNothing);
    });
  });

  group('the supervisor keypad', () {
    const supervisor = PosStaff(
      id: 9,
      name: 'Hana Mostafa',
      capabilities: {PosCapability.discountApply},
    );

    Future<_Directory> open(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1440, 1200)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final directory = _Directory({'9999': supervisor});
      await tester.pumpWidget(
        ProviderScope(
          // Not `fakeRepositoryOverrides()`: it binds a staff directory of its
          // own, and this needs one that counts lookups.
          overrides: [
            staffDirectoryRepositoryProvider.overrideWithValue(directory),
            tillClockProvider.overrideWithValue(() => now),
          ],
          child: MaterialApp(
            theme: buildPosTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => SupervisorOverrideDialog.show(
                    context,
                    capability: PosCapability.discountApply,
                    action: 'Discount this line by 30%',
                    approveLabel: 'Approve discount',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return directory;
    }

    Future<void> tryPin(WidgetTester tester, String pin) async {
      for (final digit in pin.split('')) {
        await tester.tap(find.widgetWithText(InkWell, digit).first);
        await tester.pump();
      }
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();
    }

    Future<void> reopen(WidgetTester tester) async {
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the fifth wrong PIN shuts it — it does not only say so', (
      tester,
    ) async {
      final directory = await open(tester);

      for (var i = 0; i < 4; i++) {
        await tryPin(tester, '0000');
      }
      expect(find.text('Wrong PIN. One attempt left.'), findsOneWidget);
      await tryPin(tester, '0000');
      expect(find.text(shut30), findsOneWidget);

      // The supervisor's real PIN, while shut: not looked up, not approved.
      final looked = directory.lookups;
      await tryPin(tester, '9999');
      expect(directory.lookups, looked, reason: 'the PIN was not checked');
      expect(find.textContaining('approved this'), findsNothing);
      expect(find.textContaining('Too many wrong attempts'), findsOneWidget);
    });

    testWidgets('and Cancel then asking again is not five fresh tries', (
      tester,
    ) async {
      // The count lived in the dialog, so closing it and opening another was a
      // way round the five. It belongs to the terminal now.
      await open(tester);
      for (var i = 0; i < 5; i++) {
        await tryPin(tester, '0000');
      }

      await reopen(tester);
      await tryPin(tester, '9999');
      expect(find.textContaining('approved this'), findsNothing);
      expect(find.textContaining('Too many wrong attempts'), findsOneWidget);

      // Until the wait is over.
      now = now.add(const Duration(seconds: 30));
      await tryPin(tester, '9999');
      expect(find.textContaining('Hana Mostafa approved this'), findsOneWidget);
    });
  });

  test('both languages say it, in Latin digits', () {
    for (final s in const <AppStrings>[EnStrings(), ArStrings()]) {
      for (final text in [
        s.signInLockedOut(1),
        s.signInLockedOut(30),
        s.signInLockedOut(900),
        s.lockedAfterInactivity,
      ]) {
        expect(text, isNotEmpty);
        expect(RegExp('[٠-٩]').hasMatch(text), isFalse, reason: text);
      }
    }
    expect(const EnStrings().signInLockedOut(900), contains('15 minutes'));
    expect(const EnStrings().signInLockedOut(61), contains('2 minutes'));
    expect(const ArStrings().signInLockedOut(900), contains('15 دقيقة'));
    expect(const ArStrings().signInLockedOut(240), contains('4 دقائق'));
    expect(const ArStrings().signInLockedOut(30), contains('30 ثانية'));
    expect(
      const ArStrings().lockedAfterInactivity,
      isNot(const EnStrings().lockedAfterInactivity),
    );
  });
}

/// A staff directory with a known PIN map, counting lookups so a test can say
/// a PIN was never checked.
class _Directory implements StaffDirectoryRepository {
  _Directory(this._pins);

  final Map<String, PosStaff> _pins;
  var lookups = 0;

  @override
  Future<PosStaff?> byPin(String pin) async {
    lookups++;
    return _pins[pin];
  }

  @override
  Future<List<PosStaff>> all({bool includeInactive = true}) async =>
      _pins.values.toList();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
