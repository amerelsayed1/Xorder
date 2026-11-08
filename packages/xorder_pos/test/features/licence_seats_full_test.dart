import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/presentation/licence_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// XORD-017 — what a cashier or owner reads on the till when the platform says
/// every device the licence covers is already in use.
///
/// The server side (409 `licence_seats_full`) and the mapping to
/// [LicenceSeatsFull] are tested elsewhere; this is the last step, the sentence
/// on the Licence screen, in both languages. Without it a regression in the
/// screen would leave the buyer of a one-device licence looking at a generic
/// "server refused".
class _SeatsFull extends FakeLicenceService {
  _SeatsFull(this.seats);

  final int? seats;

  /// What the platform answers a key whose devices are all in use. The real
  /// service turns a 409 `licence_seats_full` into exactly this.
  @override
  Future<LicenceFetch> fetchByKey(String key, DeploymentConfig deployment) async =>
      LicenceFetch.failed(LicenceSeatsFull(seats));
}

const _offline = DeploymentConfig(
  mode: DeploymentMode.offline,
  databaseHost: '192.168.1.20',
  tenantSlug: 'mahsoub',
);

Future<void> _pump(
  WidgetTester tester, {
  required String locale,
  int? seats = 1,
}) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      licenceServiceProvider.overrideWithValue(_SeatsFull(seats)),
    ],
  );
  addTearDown(container.dispose);
  container.read(deploymentProvider.notifier).apply(_offline);
  container.read(localeProvider.notifier).apply(locale);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: LicenceScreen(onClose: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Past the fake service's latency: `pumpAndSettle` alone stops when no frame is
/// pending, and a bare `Future.delayed` timer schedules none.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('English: says the key is right, the licence is not withdrawn, and who to ask', (tester) async {
    await _pump(tester, locale: 'en');

    await tester.tap(find.text(const EnStrings().activateKey));
    await _settle(tester);

    expect(find.text(const EnStrings().licenceSeatsFull(1)), findsOneWidget);
    expect(find.textContaining('1 device(s)'), findsOneWidget);
    expect(find.textContaining('has not been withdrawn'), findsOneWidget);
    expect(find.textContaining('revoked'), findsNothing, reason: 'not the revoked sentence');
  });

  testWidgets('Arabic: the same sentence, translated, with the number of devices', (tester) async {
    await _pump(tester, locale: 'ar', seats: 3);

    await tester.tap(find.text(const ArStrings().activateKey));
    await _settle(tester);

    expect(find.text(const ArStrings().licenceSeatsFull(3)), findsOneWidget);
    expect(find.textContaining('3 جهاز'), findsOneWidget);
  });

  testWidgets('a platform that does not say how many still gets a whole sentence', (tester) async {
    await _pump(tester, locale: 'en', seats: null);

    await tester.tap(find.text(const EnStrings().activateKey));
    await _settle(tester);

    expect(find.textContaining('a fixed number of device(s)'), findsOneWidget);
  });

  testWidgets('it is not mistaken for success: no "licence updated" note', (tester) async {
    await _pump(tester, locale: 'en');

    await tester.tap(find.text(const EnStrings().activateKey));
    await _settle(tester);

    expect(find.text(const EnStrings().licenceUpdated), findsNothing);
  });
}
