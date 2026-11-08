import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/backup.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/features/start/start_screen.dart';

import '../support/fakes.dart';

const _cloud = DeploymentConfig(
  mode: DeploymentMode.cloud,
  baseUrl: 'https://xorder.io',
  tenantSlug: 'mahsoub',
);

/// Boot a terminal that already has [licenceKey] installed, then show the start
/// screen — the screen that decides whether a shift may open.
Future<({ProviderContainer container, List<String> events})> _boot(
  WidgetTester tester, {
  String? licenceKey,
  List<BackupRecord>? backups,
}) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      if (backups != null)
        backupRepositoryProvider.overrideWithValue(
          FakeBackupRepository(records: backups),
        ),
    ],
  );
  addTearDown(container.dispose);
  container.read(deploymentProvider.notifier).apply(_cloud);

  if (licenceKey != null) {
    // runAsync, because the fake service sleeps and `testWidgets` runs on a
    // fake clock: awaiting a Future.delayed here without pumping hangs the
    // test forever rather than failing.
    await tester.runAsync(() async {
      await container.read(licenceServiceProvider).activate(
            deployment: _cloud,
            key: licenceKey,
          );
    });
    container.invalidate(licenceEntitlementProvider);
  }

  final events = <String>[];
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildPosTheme(),
        home: StartScreen(
          onStart: () => events.add('start'),
          onManageLicence: () => events.add('licence'),
          onManage: (_) => events.add('manage'),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();

  return (container: container, events: events);
}

/// Walk the sign-in dialog that Start's button opens.
///
/// Signing in asks who is at the till and nothing else: opening a shift is
/// Home's button now (pos-signin-first-home), so "tapped Sign in" is not the
/// same event as "went selling". These tests are about what the licence does
/// and does not gate on this screen, so they push through the dialog rather
/// than asserting on it.
Future<void> _signIn(WidgetTester tester) async {
  // A name as well as a PIN: four digits get shared, so the till checks a claim
  // rather than handing the till to whoever holds them.
  await tester.enterText(find.byType(TextField), 'rana');
  await tester.pump();
  for (final digit in ['1', '2', '3', '4']) {
    await tester.tap(find.text(digit));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('a valid licence lets somebody sign in', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-GOOD-1');

    expect(find.byKey(const Key('start-sign-in')), findsOneWidget);
    expect(find.text('Licence required'), findsNothing);
    // Starting a shift is Home's, not Start's.
    expect(find.textContaining('Start shift'), findsNothing);

    await tester.tap(find.byKey(const Key('start-sign-in')));
    await tester.pumpAndSettle();
    await _signIn(tester);
    expect(app.events, contains('start'));
    expect(app.container.read(signedInStaffProvider)?.name, 'Rana A.');
    // And no drawer was opened by it.
    expect(await app.container.read(shiftRepositoryProvider).current(), isNull);
  });

  testWidgets('an expired licence blocks the next shift, not signing in, and '
      'offers renewal', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-EXPIRED-1');

    expect(find.textContaining('new shift cannot be started'), findsOneWidget);
    // The gate is on opening the shift (Home). A manager must still get in to
    // cash up, reprint and close the day.
    expect(find.byKey(const Key('start-sign-in')), findsOneWidget);
    expect(find.text('Licence required'), findsNothing);

    // The way out has to be right there — a blocked till with no route to
    // renewal is a support call.
    expect(find.text('Renew licence'), findsOneWidget);
    await tester.tap(find.text('Renew licence'));
    await tester.pumpAndSettle();
    expect(app.events, contains('licence'));

    await tester.tap(find.byKey(const Key('start-sign-in')));
    await tester.pumpAndSettle();
    await _signIn(tester);
    expect(app.events, contains('start'));
  });

  testWidgets('a licence in grace keeps trading, with a warning', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-GRACE-1');

    expect(find.byKey(const Key('start-sign-in')), findsOneWidget);
    expect(find.textContaining('Trading continues'), findsOneWidget);
    // Grace is a warning, not a block.
    expect(find.text('Manage licence'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-sign-in')));
    await tester.pumpAndSettle();
    await _signIn(tester);
    expect(app.events, contains('start'));
  });

  testWidgets('renewing clears the warning without a restart', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-EXPIRED-1');
    expect(find.text('Renew licence'), findsOneWidget);

    // Renew, exactly as the licence screen does.
    await tester.runAsync(() async {
      await app.container.read(licenceServiceProvider).activate(
            deployment: _cloud,
            key: 'XORD-RENEWED-1',
          );
    });
    app.container.invalidate(licenceEntitlementProvider);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Renew licence'), findsNothing);
    expect(find.textContaining('new shift cannot be started'), findsNothing);
    expect(find.byKey(const Key('start-sign-in')), findsOneWidget);
  });

  testWidgets('Enter signs in, whatever the licence', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-EXPIRED-1');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(app.events, contains('start'));
  });

  testWidgets('Enter signs in on a good licence', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-GOOD-1');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(app.events, contains('start'));
  });

  testWidgets('signing in with a shift already open asks for no float', (
    tester,
  ) async {
    final app = await _boot(tester, licenceKey: 'XORD-GOOD-1');
    // A till restarted mid-service: the drawer never closed.
    await app.container
        .read(shiftRepositoryProvider)
        .open(
          by: const PosStaff(id: 1, name: 'Rana A.', username: 'rana'),
          openingFloat: const Money(0),
        );
    app.container.invalidate(shiftProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start-sign-in')));
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(app.events.where((e) => e == 'start').length, 1);
    expect(find.text('Open shift'), findsNothing, reason: 'no second float');
    expect(find.text('Open the drawer'), findsNothing);
  });

  testWidgets('Start no longer offers to close the day', (tester) async {
    await _boot(tester, licenceKey: 'XORD-GOOD-1');
    expect(find.text('Close the day'), findsNothing);
  });

  testWidgets('a filing problem is said on the start screen, with the way '
      'to it', (tester) async {
    // Raised at settlement into a provider nobody watched, a half-typed profile
    // meant a business filed nothing for a month and heard it from the
    // authority. It is said where the business is opened from.
    final app = await _boot(tester, licenceKey: 'XORD-GOOD-1', backups: [
      BackupRecord(
        id: 1,
        takenAt: DateTime.now(),
        takenByName: 'Amer M.',
        trigger: BackupTrigger.dayClose,
        outcome: BackupOutcome.verified,
        filePath: '/backups/x.dump',
        sizeBytes: 1,
        checksum: 'a' * 64,
        tablesFound: 44,
      ),
    ]);
    expect(find.byKey(const Key('start-eta-problem')), findsNothing);

    app.container.read(etaFilingProblemProvider.notifier).report(
      const ProfileIncomplete([
        ProfileProblem(ProfileField.registrationNumber, 'nine digits'),
        ProfileProblem(ProfileField.activityCode, 'four digits'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'E-receipts are not being filed: the receipt profile has 2 things to '
        'fix.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('start-eta-open')));
    await tester.pumpAndSettle();
    expect(app.events, contains('manage'));
  });

  testWidgets('backups are the back office\'s business, not the start '
      'screen\'s', (tester) async {
    // A cashier opens the till from here and can do nothing about a backup;
    // the warning is in Management, for somebody who can.
    await _boot(tester, licenceKey: 'XORD-GOOD-1', backups: []);

    expect(find.byKey(const Key('start-backup-warning')), findsNothing);
    expect(
      find.text('No copy of this database has ever been taken.'),
      findsNothing,
    );
  });

  testWidgets('resetting the terminal is the back office\'s business, not the '
      'start screen\'s', (tester) async {
    // A cashier opens the till from here, and must not be one tap from wiping
    // its setup. The reset is in Management › System › Terminal.
    await _boot(tester, licenceKey: 'XORD-GOOD-1');

    expect(find.text('Reset terminal'), findsNothing);
  });
}
