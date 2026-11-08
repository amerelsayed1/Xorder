import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/setup/presentation/force_reset_dialog.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The forced reset — Ctrl/Cmd+Shift+R, and the menu item that prints it — and
/// who it asks for.
///
/// It used to ask for nobody: knowing the chord was the whole lock. These tests
/// are about what replaced that. A working till is wiped only by somebody
/// holding `terminal.manage`; a till that cannot reach its database at all is
/// still let through, because that is the till this reset exists to rescue.
void main() {
  const strings = EnStrings();

  Future<({ProviderContainer container, List<bool> results})> open(
    WidgetTester tester, {
    bool configured = true,
    bool reachable = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        if (!reachable)
          // The check asks the database who this is — and nothing is
          // listening where it asks.
          sessionRepositoryProvider.overrideWithValue(const _Unreachable()),
      ],
    );
    addTearDown(container.dispose);
    final setup = container.read(setupCompleteProvider.notifier);
    configured ? setup.markComplete() : setup.reset();

    final results = <bool>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('go'),
                  onPressed: () async =>
                      results.add(await showForceResetDialog(context, ref)),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('go')));
    await tester.pumpAndSettle();

    return (container: container, results: results);
  }

  Future<void> signIn(
    WidgetTester tester,
    String username,
    String pin,
  ) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('force-reset-username')),
        matching: find.byType(TextField),
      ),
      username,
    );
    await tester.enterText(find.byKey(const Key('force-reset-pin')), pin);
    await tester.tap(find.byKey(const Key('force-reset-continue')));
    await tester.pumpAndSettle();
  }

  testWidgets('a till that is set up asks who, before it shows anything it '
      'could wipe', (tester) async {
    await open(tester);

    expect(find.text(strings.forceResetSignInTitle), findsOneWidget);
    expect(find.text(strings.forceResetTitle), findsNothing);
  });

  testWidgets('an owner gets through to the cost, and confirming wipes the '
      'setup', (tester) async {
    final app = await open(tester);

    await signIn(tester, 'amer', '4321');
    expect(find.text(strings.forceResetTitle), findsOneWidget);

    await tester.tap(find.text(strings.forceResetConfirm));
    await tester.pumpAndSettle();

    expect(app.container.read(setupCompleteProvider), isFalse);
    expect(app.results, [true]);
  });

  testWidgets('a wrong PIN is refused, and nothing is wiped', (
    tester,
  ) async {
    final app = await open(tester);

    await signIn(tester, 'amer', '0000');

    expect(find.text(strings.forceResetSignInRefused), findsOneWidget);
    expect(find.text(strings.forceResetTitle), findsNothing);
    expect(app.container.read(setupCompleteProvider), isTrue);
  });

  testWidgets('five wrong tries shut the door, even to the right PIN', (
    tester,
  ) async {
    // It took guesses as fast as somebody could type them: four digits and
    // the chord were a way to walk the PIN space of an owner's account.
    final app = await open(tester);

    // A name nobody has is refused in the same words as a wrong PIN, and
    // counted the same — the door must not say which names are real.
    await signIn(tester, 'nobody', '1111');
    expect(find.text(strings.forceResetSignInRefused), findsOneWidget);
    // Five against one name shut that name.
    for (var i = 0; i < 4; i++) {
      await signIn(tester, 'amer', '0000');
      expect(find.text(strings.forceResetSignInRefused), findsOneWidget);
    }
    await signIn(tester, 'amer', '0000');
    expect(find.text(strings.signInLockedOut(30)), findsOneWidget);

    // Shut means shut: the owner's own PIN is not looked at until it opens.
    await signIn(tester, 'amer', '4321');
    expect(find.text(strings.signInLockedOut(30)), findsOneWidget);
    expect(find.text(strings.forceResetTitle), findsNothing);
    expect(app.container.read(setupCompleteProvider), isTrue);
  });

  testWidgets('a cashier with their right PIN is refused all the same', (
    tester,
  ) async {
    // Being somebody who works here is not being somebody who may wipe the
    // till. The name has to hold the right.
    final app = await open(tester);

    await signIn(tester, 'rana', '1234');

    expect(find.text(strings.forceResetSignInRefused), findsOneWidget);
    expect(find.text(strings.forceResetTitle), findsNothing);
    expect(app.container.read(setupCompleteProvider), isTrue);
  });

  testWidgets('cancelling wipes nothing', (tester) async {
    final app = await open(tester);

    await tester.tap(find.text(strings.cancel));
    await tester.pumpAndSettle();

    expect(app.results, [false]);
    expect(app.container.read(setupCompleteProvider), isTrue);
  });

  testWidgets('a till that cannot reach its database is let through to the '
      'cost', (tester) async {
    // It cannot sell and cannot check anybody's password, and pointing it at
    // a database it can reach is what this reset is for.
    await open(tester, reachable: false);

    await signIn(tester, 'anyone', '9999');

    expect(find.text(strings.forceResetTitle), findsOneWidget);
  });

  testWidgets('a till that is not set up is not asked who', (tester) async {
    // Nothing working to wipe, and no database to ask.
    await open(tester, configured: false);

    expect(find.text(strings.forceResetSignInTitle), findsNothing);
    expect(find.text(strings.forceResetTitle), findsOneWidget);
  });
}

/// A branch server nothing is listening for.
class _Unreachable implements SessionRepository {
  const _Unreachable();

  static final _refused = PosDbException(PosDbFailure.tcp, 'connection refused');

  @override
  Future<PosSession> current() => throw _refused;

  @override
  Future<bool> verifyPin(String pin) => throw _refused;

  @override
  Future<PosStaff?> signIn(String pin) => throw _refused;

  @override
  Future<PosStaff?> signInAs({required String username, required String pin}) =>
      throw _refused;

  @override
  Future<PosStaff?> signInWithPassword({
    required String username,
    required String password,
  }) => throw _refused;
}
