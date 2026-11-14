import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/features/licensing/data/licence_service.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/presentation/licence_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

const _cloud = DeploymentConfig(
  mode: DeploymentMode.cloud,
  baseUrl: 'https://xorder.io',
  tenantSlug: 'mahsoub',
);

const _offline = DeploymentConfig(
  mode: DeploymentMode.offline,
  databaseHost: '192.168.1.20',
  tenantSlug: 'mahsoub',
);

/// A build with no licence transport at all — the only case that now falls back
/// to file-only renewal. It is a property of the build, not of the mode.
class _NoRemoteLicenceService extends FakeLicenceService {
  @override
  bool get canActivateOnline => false;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  DeploymentConfig deployment = _cloud,
  List<Override> extraOverrides = const [],
}) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [...fakeRepositoryOverrides(), ...extraOverrides],
  );
  addTearDown(container.dispose);
  container.read(deploymentProvider.notifier).apply(deployment);
  // English, asked for rather than assumed: the product's default is Arabic —
  // its businesses are in Egypt — and these tests read English copy.
  container.read(localeProvider.notifier).apply('en');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildPosTheme(),
        home: LicenceScreen(onClose: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Advance past the fake service's latency.
///
/// `pumpAndSettle` alone stops as soon as no frames are pending, and a bare
/// `Future.delayed` timer schedules no frame — so an async tap can silently be
/// checked before it has resolved.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  group('shared activation path', () {
    test('an unrecognised key fails without persisting anything', () async {
      final service = FakeLicenceService();

      final result = await service.activate(deployment: _cloud, key: '');

      expect(result.succeeded, isFalse);
      expect(result.notice, isA<LicenceKeyNotRecognised>());
      expect((await service.current(_cloud)).state, LicenseState.missing);
    });

    test('a valid key installs a licence that permits trade', () async {
      final service = FakeLicenceService();

      final result = await service.activate(deployment: _cloud, key: 'XORD-0001');

      expect(result.succeeded, isTrue);
      expect((await service.current(_cloud)).state, LicenseState.valid);
    });

    test('renewing replaces an expired licence with a valid one', () async {
      final service = FakeLicenceService();

      await service.activate(deployment: _cloud, key: 'XORD-EXPIRED-1');
      expect((await service.current(_cloud)).canOpenShift, isFalse);

      // The renewal — the whole point of the screen.
      await service.activate(deployment: _cloud, key: 'XORD-RENEWED-1');
      final after = await service.current(_cloud);

      expect(after.state, LicenseState.valid);
      expect(after.canOpenShift, isTrue);
    });

    test('an expired licence is still persisted, so the screen can show it', () async {
      final service = FakeLicenceService();

      final result = await service.activate(deployment: _cloud, key: 'XORD-EXPIRED-1');

      // Installed, but not a successful renewal: it does not restore
      // shift-opening, which is the thing renewal exists to fix.
      expect(result.installed, isTrue);
      expect(result.succeeded, isFalse);
      expect(result.notice, isA<LicenceExpired>());
      expect((await service.current(_cloud)).state, LicenseState.expired);
    });

    test('garbage passed as a file is rejected with a file-shaped message', () async {
      final service = FakeLicenceService();

      final result = await service.activate(
        deployment: _cloud,
        fileContents: 'this is not a licence',
      );

      expect(result.notice, isA<NotALicenceFile>());
    });
  });

  group('licence screen', () {
    testWidgets('shows what still works when nothing is installed', (tester) async {
      await _pump(tester);

      expect(find.text('NOT LICENSED'), findsOneWidget);
      // The carve-out has to be legible at a glance: an operator staring at a
      // red panel needs to know whether they can cash up tonight.
      expect(find.text('Cash up, X/Z report'), findsOneWidget);
      expect(find.text('Open a new shift'), findsOneWidget);
    });

    testWidgets('renews from a key and updates the panel in place', (tester) async {
      final container = await _pump(tester);

      await tester.enterText(find.byType(TextField).first, 'XORD-RENEWAL-1');
      await tester.tap(find.text('Activate key'));
      await _settle(tester);

      expect(find.text('Licence updated.'), findsOneWidget);
      expect(find.text('LICENSED'), findsOneWidget);
      expect(
        container.read(licenceEntitlementProvider).valueOrNull?.state,
        LicenseState.valid,
      );
    });

    testWidgets('surfaces a bad key rather than silently doing nothing', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Activate key'));
      await _settle(tester);

      expect(find.textContaining('not recognised'), findsOneWidget);
    });

    testWidgets('an offline terminal can still renew against the platform', (tester) async {
      // The mode decides where *sales* go, not where the licence comes from.
      // An offline till renews online — that check-in is the whole mechanism
      // behind its offline window.
      await _pump(tester, deployment: _offline);

      await tester.tap(find.text('Check for renewal'));
      await _settle(tester);

      expect(find.textContaining('cannot check for a renewal'), findsNothing);
      expect(find.textContaining('Renewals bought on the platform'), findsOneWidget);
    });

    testWidgets('a build with no licence transport says so and offers no file', (tester) async {
      await _pump(
        tester,
        deployment: _offline,
        extraOverrides: [
          licenceServiceProvider.overrideWithValue(_NoRemoteLicenceService()),
        ],
      );

      expect(find.textContaining('no route to the platform'), findsOneWidget);
      expect(find.text('Import licence file'), findsNothing);

      await tester.tap(find.text('Check for renewal'));
      await _settle(tester);
      expect(find.textContaining('cannot check for a renewal'), findsOneWidget);
    });
  });
}
