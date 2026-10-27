import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/features/setup/presentation/setup_wizard.dart';
import 'package:xorder_pos/features/start/start_screen.dart';

import '../support/fakes.dart';

/// The two screens that were still English on an Arabic till.
///
/// `test/core/localisation_test.dart` reads the catalogue and scans the source.
/// Neither can tell whether a widget actually CALLS what it was given — the
/// catalogue was complete and correctly translated the whole time these screens
/// rendered English. So these tests build the real screens under the real
/// delegate and read the words off them, which is the check that would have
/// failed while the start screen spelled its captions out inline.
const _cloud = DeploymentConfig(
  mode: DeploymentMode.cloud,
  baseUrl: 'https://xorder.io',
  tenantSlug: 'mahsoub',
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget Function() home, {
  String? licenceKey,
}) async {
  tester.view
    ..physicalSize = const Size(1440, 1000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: fakeRepositoryOverrides());
  addTearDown(container.dispose);
  container.read(deploymentProvider.notifier).apply(_cloud);

  if (licenceKey != null) {
    // runAsync, because the fake service sleeps and `testWidgets` runs on a
    // fake clock — awaiting it without pumping hangs rather than fails.
    await tester.runAsync(() async {
      await container
          .read(licenceServiceProvider)
          .activate(deployment: _cloud, key: licenceKey);
    });
    container.invalidate(licenceEntitlementProvider);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // Exactly what `XorderPosApp` installs, so the tree under test resolves
        // its words the way the shipped app does.
        locale: const Locale('ar'),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: home(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return container;
}

Widget _startScreen() => StartScreen(
  onStart: () {},
  onManageLicence: () {},
  onManage: (_) {},
);

/// Every caption the screen is currently showing.
Set<String> _onScreen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .toSet();

void main() {
  testWidgets('the start screen identity grid is Arabic', (tester) async {
    await _pump(tester, _startScreen, licenceKey: 'XORD-GOOD-1');

    // The strap under the tenant name, and the two identity cells. The VALUES
    // stay as the operator's own data — a branch is not translated.
    for (final arabic in [
      'نقطة بيع', // pointOfSale
      'الفرع', // branchCell
      'الجهاز', // terminalCell
    ]) {
      expect(find.text(arabic), findsOneWidget, reason: 'missing: $arabic');
    }
    // Not the menu: how many items are cached is nothing to act on here.
    expect(find.text('المنيو'), findsNothing);
    // XOrder's mark sits above the restaurant's name.
    expect(find.byKey(const Key('start-xorder-logo')), findsOneWidget);

    // Not the restaurant: it is the heading above the grid, and a cell saying
    // it again was the same name twice.
    expect(find.text('المطعم'), findsNothing);

    // The exact literals that used to be hardcoded in their place.
    for (final english in [
      'POINT OF SALE',
      'BRANCH',
      'TERMINAL',
      'CATALOG',
    ]) {
      expect(
        find.text(english),
        findsNothing,
        reason: 'still English: $english',
      );
    }

    expect(
      Directionality.of(tester.element(find.byType(StartScreen))),
      TextDirection.rtl,
    );
  });

  testWidgets('the start screen call to action is Arabic: signing in', (
    tester,
  ) async {
    await _pump(tester, _startScreen, licenceKey: 'XORD-GOOD-1');

    expect(find.text('تسجيل الدخول'), findsOneWidget); // signIn
    expect(find.text('Sign in'), findsNothing);
    // The help line under it.
    expect(
      find.textContaining('اسمك ورقمك السري'), // signInOnlyHelp
      findsOneWidget,
    );
  });

  testWidgets('the start screen is Arabic when the licence blocks the shift', (
    tester,
  ) async {
    // The licence banner is the other branch on this screen. It was reachable
    // with the English hardcoded just as it is now, so it has to be read too.
    // Signing in itself is never blocked (pos-signin-first-home): the shift
    // button, and its "Licence required", are on Home.
    await _pump(tester, _startScreen);

    expect(find.text('تسجيل الدخول'), findsOneWidget); // signIn, still there
    expect(find.text('تجديد الترخيص'), findsOneWidget); // renewLicence

    for (final english in [
      'Licence required',
      'Renew licence',
      'Manage licence',
    ]) {
      expect(
        find.text(english),
        findsNothing,
        reason: 'still English: $english',
      );
    }
  });


  testWidgets('nothing on the start screen is left in Latin script', (
    tester,
  ) async {
    await _pump(tester, _startScreen, licenceKey: 'XORD-GOOD-1');

    // A backstop for captions nobody thought to name above. Two things are
    // exempt, both by design rather than by oversight:
    //
    // * the operator's own data — a tenant, a branch, a terminal code and the
    //   NAME OF THE PERSON SIGNED IN are what they are in any language, and
    //   the last of those is on this screen now that it carries the same bar
    //   the till does;
    // * the ENTER keycap, which names a key the cashier is looking at. Taken
    //   from the catalogue rather than written out here, so translating it
    //   would relax this test instead of breaking it.
    const operatorData = {
      'MAHSOUB GRILL',
      'Mahsoub Grill',
      'DOWNTOWN',
      'T-02',
      'Rana A.',
      'R',
    };
    final exempt = {...operatorData, const ArStrings().enterKeyCap};

    final latin = _onScreen(tester)
        .where((t) => !exempt.contains(t))
        .where((t) => RegExp(r'[A-Za-z]{3,}').hasMatch(t))
        .toList();

    expect(latin, isEmpty, reason: 'English left on an Arabic start screen');
  });

  testWidgets('the setup wizard header is Arabic', (tester) async {
    await _pump(tester, () => SetupWizard(onFinished: () {}));

    expect(find.text('إعداد الجهاز'), findsOneWidget); // terminalSetup
    expect(find.text('TERMINAL SETUP'), findsNothing);
    // The product's own name is a brand, and stays.
    expect(find.text('XORDER POS'), findsOneWidget);

    expect(
      Directionality.of(tester.element(find.byType(SetupWizard))),
      TextDirection.rtl,
    );
  });
}
