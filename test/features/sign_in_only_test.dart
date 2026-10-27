import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/business_day_service.dart';
import 'package:xorder_pos/features/shift/presentation/shift_dialogs.dart';

import '../support/fakes.dart';

/// Signing in at the till is not opening a shift (pos-signin-first-home).
///
/// A manager who has come to close the night has no use for a drawer, and an
/// open shift is a blocker for closing the day. These claims are about the
/// sign-in-only dialog and the float-only form of the open-shift dialog; the
/// PIN pad, the limiter and the words of a refusal are the existing ones.
void main() {
  late DateTime now;

  setUp(() => now = DateTime.utc(2026, 10, 26, 9));

  const shut30 = 'Too many wrong attempts. Try again in 30 seconds.';
  const wrong = 'Wrong username or PIN — try again';

  Future<ProviderContainer> pumpDialog(
    WidgetTester tester,
    Future<bool> Function(BuildContext context) open, {
    required void Function(bool result) onResult,
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        tillClockProvider.overrideWithValue(() => now),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => onResult(await open(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> signIn(WidgetTester tester, String name, String pin) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('sign-in only', () {
    testWidgets('a right name and PIN signs in and opens no shift', (
      tester,
    ) async {
      bool? result;
      final container = await pumpDialog(
        tester,
        SignInDialog.show,
        onResult: (r) => result = r,
      );

      expect(find.text('Your name and your PIN.'), findsOneWidget);
      await signIn(tester, 'rana', '1234');

      expect(result, isTrue);
      expect(container.read(signedInStaffProvider)?.name, 'Rana A.');
      expect(await container.read(shiftRepositoryProvider).current(), isNull);
      expect(find.text('Open the drawer'), findsNothing);
    });

    testWidgets('someone who may not open a shift can still sign in', (
      tester,
    ) async {
      // Nour holds neither shift.open nor day.close here: signing in is only
      // the question of who is at the till.
      bool? result;
      final container = await pumpDialog(
        tester,
        SignInDialog.show,
        onResult: (r) => result = r,
      );

      await signIn(tester, 'nour', '2468');

      expect(result, isTrue);
      expect(container.read(signedInStaffProvider)?.name, 'Nour S.');
      expect(
        container.read(canProvider(PosCapability.shiftOpen)).isAllowed,
        isFalse,
      );
    });

    testWidgets('a wrong PIN signs nobody in and says so', (tester) async {
      bool? result;
      final container = await pumpDialog(
        tester,
        SignInDialog.show,
        onResult: (r) => result = r,
      );

      await signIn(tester, 'rana', '9999');

      expect(result, isNull, reason: 'still open');
      expect(find.text(wrong), findsOneWidget);
      expect(container.read(signedInStaffProvider), isNull);
    });

    testWidgets('five wrong PINs shut it, the right one included, on the same '
        'count as the other doors', (tester) async {
      bool? result;
      final container = await pumpDialog(
        tester,
        SignInDialog.show,
        onResult: (r) => result = r,
      );

      await tester.enterText(find.byType(TextField), 'rana');
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        for (final digit in '9999'.split('')) {
          await tester.tap(find.text(digit).last);
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }
      expect(find.text(shut30), findsOneWidget);

      for (final digit in '1234'.split('')) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(container.read(signedInStaffProvider), isNull);
      expect(
        container.read(signInLimiterProvider).lockedFor('rana'),
        isNotNull,
      );
    });

    testWidgets('with a shift already open, the business day is made sure of', (
      tester,
    ) async {
      final ensured = <int>[];
      final container = await pumpDialog(
        tester,
        SignInDialog.show,
        onResult: (_) {},
        overrides: [
          ensureBusinessDayProvider.overrideWithValue((by) async {
            ensured.add(by.id);
            return const BusinessDayResult(BusinessDayOutcome.reused);
          }),
        ],
      );
      // A shift left open by a restart.
      await container
          .read(shiftRepositoryProvider)
          .open(
            by: const PosStaff(id: 1, name: 'Rana A.', username: 'rana'),
            openingFloat: const Money(0),
          );
      container.invalidate(shiftProvider);
      await container.read(shiftProvider.future);

      await signIn(tester, 'rana', '1234');

      expect(ensured, [1]);
    });

    testWidgets('with no shift open, no day is opened by signing in', (
      tester,
    ) async {
      final ensured = <int>[];
      await pumpDialog(
        tester,
        SignInDialog.show,
        onResult: (_) {},
        overrides: [
          ensureBusinessDayProvider.overrideWithValue((by) async {
            ensured.add(by.id);
            return const BusinessDayResult(BusinessDayOutcome.reused);
          }),
        ],
      );

      await signIn(tester, 'rana', '1234');

      expect(ensured, isEmpty);
    });

    testWidgets('an unknown name reads exactly as a wrong PIN does', (
      tester,
    ) async {
      await pumpDialog(tester, SignInDialog.show, onResult: (_) {});
      await signIn(tester, 'rana', '9999');
      final wrongPin = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data);

      await tester.pumpWidget(const SizedBox());
      await pumpDialog(tester, SignInDialog.show, onResult: (_) {});
      await signIn(tester, 'nobody', '9999');
      final unknown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data);

      expect(wrong, isNotEmpty);
      expect(unknown, contains(wrong));
      expect(wrongPin, contains(wrong));
    });

    testWidgets('offers back whoever signed in last', (tester) async {
      final container = await pumpDialog(
        tester,
        SignInDialog.show,
        onResult: (_) {},
        overrides: [],
      );
      // Sign out and open it again: the name is already there.
      await signIn(tester, 'rana', '1234');
      expect(container.read(lastUsernameProvider), 'rana');
      container.read(signedInStaffProvider.notifier).signOut();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'rana',
      );
    });
  });

  group('open shift for somebody already signed in', () {
    testWidgets('asks for the float only, and opens the shift in their name', (
      tester,
    ) async {
      const rana = PosStaff(
        id: 1,
        name: 'Rana A.',
        username: 'rana',
        capabilities: {PosCapability.shiftOpen},
      );
      bool? result;
      final container = await pumpDialog(
        tester,
        (context) => OpenShiftDialog.show(context, by: rana),
        onResult: (r) => result = r,
        overrides: [
          ensureBusinessDayProvider.overrideWithValue(
            (by) async => const BusinessDayResult(BusinessDayOutcome.reused),
          ),
        ],
      );

      // No PIN pad: the float step is first.
      expect(find.text('Open the drawer'), findsOneWidget);
      expect(find.text('Wrong username or PIN — try again'), findsNothing);

      await tester.tap(find.text('Open shift'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      final shift = await container.read(shiftRepositoryProvider).current();
      expect(shift, isNotNull);
      expect(shift!.openedByName, 'Rana A.');
    });

    testWidgets('refuses somebody without shift.open even when the caller '
        'forgot to hide the button', (tester) async {
      const nour = PosStaff(
        id: 3,
        name: 'Nour S.',
        username: 'nour',
        capabilities: {PosCapability.operate},
      );
      bool? result;
      final container = await pumpDialog(
        tester,
        (context) => OpenShiftDialog.show(context, by: nour),
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Open shift'));
      await tester.pumpAndSettle();

      expect(result, isNull, reason: 'the dialog stays open');
      expect(find.textContaining('Nour S.'), findsWidgets);
      expect(await container.read(shiftRepositoryProvider).current(), isNull);
    });
  });
}
