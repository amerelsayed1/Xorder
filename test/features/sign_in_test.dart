import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/app/router.dart';
import 'package:xorder_pos/features/lock/lock_screen.dart';

import '../support/fakes.dart';

/// Who is at the till, and how the till finds out (POS-BE-024).
///
/// It did not. The name in the top bar came from `PosSession.userName`, which
/// the branch server answers with the FIRST active staff row for the branch —
/// `ORDER BY st.id LIMIT 1` — rather than with whoever is standing there. On a
/// shared terminal that put one cashier's name on the bar all day and on the
/// receipts every other cashier printed. And the lock screen could not correct
/// it: `verifyPin` only ever answered "does somebody who works here know a
/// PIN", never *who*, so unlocking left the previous person signed in.
void main() {
  Future<ProviderContainer> pumpLock(
    WidgetTester tester, {
    VoidCallback? onUnlocked,
    VoidCallback? onBack,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: LockScreen(
            onUnlocked: onUnlocked ?? () {},
            onBack: onBack ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
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

  testWidgets('nobody is signed in until a PIN is entered', (tester) async {
    final container = await pumpLock(tester);

    expect(container.read(signedInStaffProvider), isNull);
    // Blank, not the branch's first cashier. A blank is visibly missing; a
    // plausible wrong name is not.
    expect(container.read(operatorNameProvider), isEmpty);
    expect(container.read(operatorInitialsProvider), isEmpty);
  });

  testWidgets('the PIN says who, not merely that somebody works here', (
    tester,
  ) async {
    var unlocked = false;
    final container = await pumpLock(tester, onUnlocked: () => unlocked = true);

    await typeUsername(tester, 'rana');
    await typePin(tester, '1234');

    expect(unlocked, isTrue);
    final staff = container.read(signedInStaffProvider);
    expect(staff, isNotNull);
    expect(staff!.name, 'Rana A.');
    // And that is what the bars and the receipts read.
    expect(container.read(operatorNameProvider), 'Rana A.');
    expect(container.read(operatorInitialsProvider), 'RA');
  });

  testWidgets('Back signs out on the way, so the shift is not handed over', (
    tester,
  ) async {
    var back = 0;
    final container = await pumpLock(tester, onBack: () => back++);

    // Locking leaves whoever was at the till signed in. A way off this screen
    // that kept them would let the next person resume their shift with Enter.
    await typeUsername(tester, 'rana');
    await typePin(tester, '1234');
    expect(container.read(signedInStaffProvider), isNotNull);

    await tester.tap(find.byKey(const Key('lock-back')));
    await tester.pumpAndSettle();
    expect(back, 1);
    expect(container.read(signedInStaffProvider), isNull);
  });

  testWidgets('and Esc does the same, even from the username field', (
    tester,
  ) async {
    var back = 0;
    final container = await pumpLock(tester, onBack: () => back++);

    await typeUsername(tester, 'ran');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(back, 1);
    expect(container.read(signedInStaffProvider), isNull);
  });

  testWidgets('a wrong PIN signs nobody in and lets nobody through', (
    tester,
  ) async {
    var unlocked = false;
    final container = await pumpLock(tester, onUnlocked: () => unlocked = true);

    await typeUsername(tester, 'rana');
    await typePin(tester, '9999');

    expect(unlocked, isFalse);
    expect(container.read(signedInStaffProvider), isNull);
    expect(container.read(operatorNameProvider), isEmpty);
  });

  testWidgets('the right PIN under the wrong name gets nowhere', (
    tester,
  ) async {
    var unlocked = false;
    final container = await pumpLock(tester, onUnlocked: () => unlocked = true);

    // Four digits get shared, watched over a shoulder and reused. Taking over a
    // drawer is a claim the till checks, not an identity it guesses.
    await typeUsername(tester, 'omar');
    await typePin(tester, '1234');

    expect(unlocked, isFalse);
    expect(container.read(signedInStaffProvider), isNull);
    // And it does not say WHICH half was wrong, or this screen becomes a way of
    // finding out which usernames exist.
    expect(find.text('Wrong username or PIN — try again'), findsOneWidget);
  });

  testWidgets('a PIN with no name at all is refused', (tester) async {
    var unlocked = false;
    final container = await pumpLock(tester, onUnlocked: () => unlocked = true);

    await typePin(tester, '1234');

    expect(unlocked, isFalse);
    expect(container.read(signedInStaffProvider), isNull);
  });

  testWidgets('the screen names nobody before a PIN is typed', (tester) async {
    await pumpLock(tester);

    // It cannot know who is coming back to a shared till, and naming the last
    // person to stand at it invited the next one to type their own PIN under
    // somebody else's name.
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  group('an unattended till is sent to sign in', () {
    // The state a restart leaves: the shift is a row in PostgreSQL and the
    // drawer never closed, but the PIN was never remembered. Resuming went
    // straight to the till, so sales carried no cashier and the cash-up refused
    // with a message whose door did not exist.
    test('selling with a shift open and nobody signed in', () {
      for (final at in [PosRoutes.sale, PosRoutes.floor]) {
        expect(
          needsSignIn(at: at, signedIn: false, shiftOpen: true),
          isTrue,
          reason: at,
        );
      }
    });

    test('somebody signed in is left alone', () {
      expect(
        needsSignIn(at: PosRoutes.sale, signedIn: true, shiftOpen: true),
        isFalse,
      );
    });

    test('and so is the ordinary morning', () {
      // Nobody is signed in before trading either. Opening the shift is what
      // asks who is there — being sent to a PIN pad to reach a start screen
      // that will ask for one anyway is a door for the sake of a door.
      expect(
        needsSignIn(at: PosRoutes.start, signedIn: false, shiftOpen: false),
        isFalse,
      );
      expect(
        needsSignIn(at: PosRoutes.sale, signedIn: false, shiftOpen: false),
        isFalse,
      );
    });
  });

  testWidgets('the PIN can be typed, not only tapped', (tester) async {
    var unlocked = false;
    final container = await pumpLock(tester, onUnlocked: () => unlocked = true);

    await typeUsername(tester, 'rana');
    // Enter leaves the name and hands the keyboard to the pad — the keys on
    // screen are for the touch screen this ships on, and a manager at a desk
    // reaches for the keyboard.
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    for (final digit in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyEvent(digit);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(unlocked, isTrue);
    expect(container.read(operatorNameProvider), 'Rana A.');
  });

  testWidgets('and backspace takes a typed digit back', (tester) async {
    var unlocked = false;
    await pumpLock(tester, onUnlocked: () => unlocked = true);

    await typeUsername(tester, 'rana');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // 1-9-⌫-2-3 is three digits, not five: nothing has been submitted yet.
    expect(unlocked, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pumpAndSettle();
    expect(unlocked, isTrue, reason: '1234 once the 9 is taken back');
  });
}
