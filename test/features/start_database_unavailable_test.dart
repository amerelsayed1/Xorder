import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/features/start/start_screen.dart';

import '../support/fakes.dart';

/// When the till cannot open its database, the person at the counter sees a
/// sentence, not an exception.
///
/// Found on the real till: after its database was deleted the start screen
/// printed `PosDbException(missingDatabase): Severity.fatal 3D000: database
/// "demo_cashier_db" does not exist` in the middle of a black screen, with no
/// way to try again. A restaurant hits the same thing after a disk fault or a
/// reset database server, and cannot be expected to read that.
void main() {
  const en = EnStrings();
  const ar = ArStrings();

  const deployment = DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseName: 'demo_cashier_db',
    databaseUser: 'pos_till',
    databasePort: 5432,
  );

  late int attempts;

  Future<void> pump(
    WidgetTester tester, {
    required Object error,
    bool arabic = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    attempts = 0;

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        sessionProvider.overrideWith((ref) async {
          attempts++;
          throw error;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(deploymentProvider.notifier).apply(deployment);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          locale: arabic ? const Locale('ar') : null,
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: StartScreen(
            onStart: () {},
            onManageLicence: () {},
            onManage: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PosDbException db(PosDbFailure failure) => PosDbException(
    failure,
    'Severity.fatal 3D000: database "demo_cashier_db" does not exist',
  );

  group('a database that is not there', () {
    testWidgets('says so in a sentence, naming the database', (tester) async {
      await pump(tester, error: db(PosDbFailure.missingDatabase));

      expect(find.text(en.dbUnavailableTitle), findsOneWidget);
      expect(
        find.text(en.dbUnavailableMissing('demo_cashier_db')),
        findsOneWidget,
      );
    });

    testWidgets('shows no exception text outside the support line', (
      tester,
    ) async {
      await pump(tester, error: db(PosDbFailure.missingDatabase));

      // The raw text is kept, small, for whoever the person calls; nothing
      // else on screen may carry it.
      final raw = find.textContaining('PosDbException');
      expect(raw, findsNothing);
      expect(find.byKey(const Key('start-error-details')), findsOneWidget);
      expect(find.textContaining('3D000'), findsOneWidget);
    });

    testWidgets('in Arabic on an Arabic till', (tester) async {
      await pump(
        tester,
        error: db(PosDbFailure.missingDatabase),
        arabic: true,
      );

      expect(find.text(ar.dbUnavailableTitle), findsOneWidget);
      expect(
        find.text(ar.dbUnavailableMissing('demo_cashier_db')),
        findsOneWidget,
      );
    });

    testWidgets('offers Try again, which asks the database again', (
      tester,
    ) async {
      await pump(tester, error: db(PosDbFailure.missingDatabase));
      expect(attempts, 1);

      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();

      expect(attempts, 2);
    });
  });

  group('the other ways a database fails get their own plain sentence', () {
    for (final (failure, sentence) in [
      (PosDbFailure.tcp, en.dbUnavailableUnreachable),
      (PosDbFailure.dns, en.dbUnavailableUnreachable),
      (PosDbFailure.tls, en.dbUnavailableUnreachable),
      (PosDbFailure.auth, en.dbUnavailableSignIn),
      (PosDbFailure.missingRole, en.dbUnavailableSignIn),
      (PosDbFailure.permissionDenied, en.dbUnavailableSignIn),
      (PosDbFailure.query, en.dbUnavailableGeneric),
    ]) {
      testWidgets('$failure', (tester) async {
        await pump(tester, error: db(failure));

        expect(find.text(sentence), findsOneWidget);
        expect(find.textContaining('PosDbException'), findsNothing);
      });
    }

    testWidgets('an error that is not a database error', (tester) async {
      await pump(tester, error: StateError('boom'));

      expect(find.text(en.dbUnavailableGeneric), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.byKey(const Key('start-error-details')), findsOneWidget);
    });
  });

  test('every sentence is worded in both languages, and they differ', () {
    for (final pair in [
      (en.dbUnavailableTitle, ar.dbUnavailableTitle),
      (en.dbUnavailableMissing('x'), ar.dbUnavailableMissing('x')),
      (en.dbUnavailableUnreachable, ar.dbUnavailableUnreachable),
      (en.dbUnavailableSignIn, ar.dbUnavailableSignIn),
      (en.dbUnavailableGeneric, ar.dbUnavailableGeneric),
      (en.dbUnavailableDetails, ar.dbUnavailableDetails),
    ]) {
      expect(pair.$1, isNotEmpty);
      expect(pair.$2, isNotEmpty);
      expect(pair.$2, isNot(pair.$1));
    }
    expect(en.dbUnavailableMissing('demo_cashier_db'), contains('demo_cashier_db'));
    expect(ar.dbUnavailableMissing('demo_cashier_db'), contains('demo_cashier_db'));
  });
}
