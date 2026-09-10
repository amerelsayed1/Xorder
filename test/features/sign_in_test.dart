import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
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
          home: LockScreen(onUnlocked: onUnlocked ?? () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
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

    await typePin(tester, '1234');

    expect(unlocked, isTrue);
    final staff = container.read(signedInStaffProvider);
    expect(staff, isNotNull);
    expect(staff!.name, 'Rana A.');
    // And that is what the bars and the receipts read.
    expect(container.read(operatorNameProvider), 'Rana A.');
    expect(container.read(operatorInitialsProvider), 'RA');
  });

  testWidgets('a wrong PIN signs nobody in and lets nobody through', (
    tester,
  ) async {
    var unlocked = false;
    final container = await pumpLock(tester, onUnlocked: () => unlocked = true);

    await typePin(tester, '9999');

    expect(unlocked, isFalse);
    expect(container.read(signedInStaffProvider), isNull);
    expect(container.read(operatorNameProvider), isEmpty);
  });

  testWidgets('the screen names nobody before a PIN is typed', (tester) async {
    await pumpLock(tester);

    // It cannot know who is coming back to a shared till, and naming the last
    // person to stand at it invited the next one to type their own PIN under
    // somebody else's name.
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });
}
