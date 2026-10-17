import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/config/terminal_config.dart';
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
  /// [container] carries a till across two locks: the same process, locked
  /// again, with whatever the first unlock left behind.
  Future<ProviderContainer> pumpLock(
    WidgetTester tester, {
    VoidCallback? onUnlocked,
    VoidCallback? onBack,
    ProviderContainer? container,
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final scope =
        container ??
        ProviderContainer(
          overrides: [...fakeRepositoryOverrides(), ...overrides],
        );
    if (container == null) addTearDown(scope.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: LockScreen(
            // A new key per pump: the second lock is a fresh screen, as it
            // is in the app, not the first one rebuilt.
            key: UniqueKey(),
            onUnlocked: onUnlocked ?? () {},
            onBack: onBack ?? () {},
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

    // The heading claims no identity: it cannot know who is coming back to a
    // shared till. The name field may be filled in and the tiles name the
    // roster, but both are offers the PIN still has to back up.
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    // Nobody has signed in on this till yet, so nothing to prefill.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  group('who is offered, so the cashier types only the PIN', () {
    // The audit (S3-2) watched every cashier type their username on a keypad
    // screen at every lock. The till now remembers the last person to sign in
    // and shows everybody who can, as tiles. What it must not do is relax
    // the check: the PIN still has to belong to the name.
    const terminal = TerminalProfile(
      branchId: 13,
      branchName: 'Maadi',
      terminalName: 'Counter 1',
      terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
      restaurantId: 7,
      branchCode: 'MAA',
    );
    const saved = SavedTerminalConfig(
      deployment: DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: '192.168.1.20',
      ),
      terminal: terminal,
      languageCode: 'en',
    );

    testWidgets('the last person to sign in is filled in at the next lock', (
      tester,
    ) async {
      final store = InMemoryTerminalConfigStore()..saved = saved;
      var unlocked = 0;
      final container = await pumpLock(
        tester,
        onUnlocked: () => unlocked++,
        overrides: [terminalConfigStoreProvider.overrideWithValue(store)],
      );

      await typeUsername(tester, 'rana');
      await typePin(tester, '1234');
      expect(unlocked, 1);

      // Locked again, in the same process: the name is already there, and
      // it is on disk for tomorrow's first lock too.
      await pumpLock(tester, onUnlocked: () => unlocked++, container: container);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'rana');
      expect(store.saved?.lastUsername, 'rana');

      // So the PIN alone is enough — typed, because the pad holds the
      // keyboard once the name is in.
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
      expect(unlocked, 2);
    });

    testWidgets('a remembered name comes back after a restart', (
      tester,
    ) async {
      // The config file is what the next launch reads; the controller seeds
      // from it before the first frame, like the language does.
      await pumpLock(
        tester,
        overrides: [
          terminalBootProvider.overrideWithValue(
            TerminalBoot(
              config: saved.copyWith(lastUsername: 'rana'),
              hasDatabaseCredential: true,
            ),
          ),
        ],
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'rana');
    });

    testWidgets('a tile fills the name, so switching user is one tap', (
      tester,
    ) async {
      var unlocked = false;
      final container = await pumpLock(
        tester,
        onUnlocked: () => unlocked = true,
      );

      // Everybody the directory lists who can sign in here, by name.
      expect(find.text('Amer M.'), findsOneWidget);
      expect(find.text('Rana A.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lock-tile-amer')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'amer');

      // Amer's PIN, under Amer's name. The tap handed the keyboard to the
      // pad, so the digits can be typed straight away.
      for (final digit in [
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit1,
      ]) {
        await tester.sendKeyEvent(digit);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(unlocked, isTrue);
      expect(container.read(signedInStaffProvider)?.name, 'Amer M.');
    });

    testWidgets('a tile is an offer, not an identity: the wrong PIN still fails', (
      tester,
    ) async {
      var unlocked = false;
      final container = await pumpLock(
        tester,
        onUnlocked: () => unlocked = true,
      );

      await tester.tap(find.byKey(const Key('lock-tile-rana')));
      await tester.pumpAndSettle();
      await typePin(tester, '9999');

      expect(unlocked, isFalse);
      expect(container.read(signedInStaffProvider), isNull);
      expect(find.text('Wrong username or PIN — try again'), findsOneWidget);
      // And the name stays, for the second try.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'rana');
    });

    testWidgets('the typed name is still there for somebody not on a tile', (
      tester,
    ) async {
      var unlocked = false;
      final container = await pumpLock(
        tester,
        onUnlocked: () => unlocked = true,
      );

      // Nour is not in the directory's list, and signs in by typing.
      expect(find.byKey(const Key('lock-tile-nour')), findsNothing);
      await typeUsername(tester, 'nour');
      await typePin(tester, '2468');

      expect(unlocked, isTrue);
      expect(container.read(signedInStaffProvider)?.name, 'Nour S.');
    });
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
