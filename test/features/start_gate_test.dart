import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/ui/theme.dart';
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
}) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: fakeRepositoryOverrides());
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
          onReconfigure: () => events.add('reconfigure'),
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

/// Walk the dialog that now stands between the CTA and the floor.
///
/// Opening a shift asks who is on the till and what is in the drawer, so
/// "tapped Start shift" is no longer the same event as "went selling". These
/// tests are about the licence gate, so they push through the dialog rather
/// than asserting on it.
Future<void> _openShift(WidgetTester tester) async {
  // A name as well as a PIN. Opening a shift makes somebody answerable for the
  // drawer, and four digits get shared — so the till checks a claim rather than
  // handing the drawer to whoever holds them.
  await tester.enterText(find.byType(TextField), 'rana');
  await tester.pump();
  for (final digit in ['1', '2', '3', '4']) {
    await tester.tap(find.text(digit));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Open shift'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a valid licence opens a shift normally', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-GOOD-1');

    expect(find.textContaining('Start shift'), findsOneWidget);
    expect(find.text('Licence required'), findsNothing);

    await tester.tap(find.textContaining('Start shift'));
    await tester.pumpAndSettle();
    await _openShift(tester);
    expect(app.events, contains('start'));
  });

  testWidgets('an expired licence blocks the next shift and offers renewal',
      (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-EXPIRED-1');

    expect(find.text('Licence required'), findsOneWidget);
    expect(find.textContaining('new shift cannot be started'), findsOneWidget);

    // Tapping the disabled CTA must do nothing at all.
    await tester.tap(find.text('Licence required'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(app.events, isNot(contains('start')));

    // But the way out has to be right there — a blocked till with no route to
    // renewal is a support call.
    expect(find.text('Renew licence'), findsOneWidget);
    await tester.tap(find.text('Renew licence'));
    await tester.pumpAndSettle();
    expect(app.events, contains('licence'));
  });

  testWidgets('an expired licence still promises cash-up', (tester) async {
    await _boot(tester, licenceKey: 'XORD-EXPIRED-1');

    expect(find.textContaining('Cash-up and reprint'), findsOneWidget);
  });

  testWidgets('a licence in grace keeps trading, with a warning', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-GRACE-1');

    expect(find.textContaining('Start shift'), findsOneWidget);
    expect(find.textContaining('Trading continues'), findsOneWidget);
    // Grace is a warning, not a block.
    expect(find.text('Manage licence'), findsOneWidget);

    await tester.tap(find.textContaining('Start shift'));
    await tester.pumpAndSettle();
    await _openShift(tester);
    expect(app.events, contains('start'));
  });

  testWidgets('renewing unblocks the till without a restart', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-EXPIRED-1');
    expect(find.text('Licence required'), findsOneWidget);

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

    expect(find.text('Licence required'), findsNothing);
    expect(find.textContaining('Start shift'), findsOneWidget);
  });

  testWidgets('Enter cannot bypass the licence gate', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-EXPIRED-1');

    // The CTA is disabled; the keyboard shortcut for the same action must be
    // too, or the gate is decorative.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(app.events, isNot(contains('start')));
  });

  testWidgets('Enter still opens a shift on a good licence', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-GOOD-1');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await _openShift(tester);

    expect(app.events, contains('start'));
  });

  testWidgets('a shift already open is resumed, not opened again', (tester) async {
    final app = await _boot(tester, licenceKey: 'XORD-GOOD-1');

    await tester.tap(find.textContaining('Start shift'));
    await tester.pumpAndSettle();
    await _openShift(tester);
    expect(app.events, contains('start'));

    // Back at the start screen with the drawer still open — a till restarted
    // mid-service must come back to the same shift rather than asking for a
    // second opening float against the same cash.
    app.container.invalidate(shiftProvider);
    await tester.pumpAndSettle();

    expect(find.textContaining('Resume SHIFT'), findsOneWidget);
    await tester.tap(find.textContaining('Resume SHIFT'));
    await tester.pumpAndSettle();

    expect(find.text('Open shift'), findsNothing, reason: 'no second float is asked for');
    expect(app.events.where((e) => e == 'start').length, 2);
  });
}
