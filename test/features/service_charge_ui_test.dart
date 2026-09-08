import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/service_charge.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/admin/presentation/service_charge_dialog.dart';

/// Authoring a service charge, on screen (§38).
///
/// The dialog's job is to make one state unreachable: a charge that is both a
/// percentage and a fixed amount. The model refuses it, the repository refuses
/// it and a CHECK constraint refuses it — this is where it becomes something
/// nobody can type in the first place.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<ServiceCharge?> Function() open(
    WidgetTester tester, {
    ServiceCharge? charge,
    String locale = 'en',
  }) {
    ServiceCharge? result;
    late Future<void> Function() run;

    run = () async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: Locale(locale),
            theme: buildPosTheme(PosPalette.light),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await ServiceChargeDialog.show(
                      context,
                      charge: charge,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    };

    return () async {
      await run();
      return result;
    };
  }

  Future<ServiceCharge?> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('charge-save')));
    await tester.pumpAndSettle();
    return null;
  }

  testWidgets('a percentage and an amount are a choice, not two boxes',
      (tester) async {
    // Two boxes side by side would invite somebody to fill in both, and
    // "12% or 20 EGP, whichever" is a question nobody has answered.
    await open(tester)();

    expect(find.text('A percentage'), findsOneWidget);
    expect(find.text('A fixed amount'), findsOneWidget);
    expect(
      find.byKey(const Key('charge-amount')),
      findsOneWidget,
      reason: 'one box, whichever is chosen',
    );
  });

  testWidgets('a percentage charge comes back as a rate and nothing else',
      (tester) async {
    ServiceCharge? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await ServiceChargeDialog.show(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Service');
    await tester.enterText(find.byKey(const Key('charge-amount')), '12.5');
    await tester.pumpAndSettle();
    await save(tester);

    expect(result?.rateBp, 1250, reason: 'basis points, never a double');
    expect(result?.fixedMinor, isNull);
    expect(result?.isFixed, isFalse);
  });

  testWidgets('a fixed charge comes back as minor units and nothing else',
      (tester) async {
    ServiceCharge? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await ServiceChargeDialog.show(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Delivery');
    await tester.tap(find.text('A fixed amount'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('charge-amount')), '20.00');
    await tester.pumpAndSettle();
    await save(tester);

    expect(result?.fixedMinor, 2000);
    expect(result?.rateBp, isNull);
    expect(result?.isFixed, isTrue);
  });

  testWidgets('"applies to nothing" is spelled out as "applies to everything"',
      (tester) async {
    // An empty selection reads as "none" to everybody and means the opposite.
    await open(tester)();
    expect(
      find.text('Choose none and it applies to every order.'),
      findsOneWidget,
    );
  });

  testWidgets('an existing charge opens on what it is', (tester) async {
    await open(
      tester,
      charge: const ServiceCharge(
        id: 3,
        nameEn: 'Delivery',
        fixedMinor: 2000,
        orderTypes: {OrderType.delivery},
        isTaxable: false,
      ),
    )();

    expect(find.text('Delivery'), findsWidgets);
    expect(find.text('20.00'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget, reason: 'and can be retired');
  });

  testWidgets('a new charge is not offered a retire switch', (tester) async {
    await open(tester)();
    expect(find.text('In use'), findsNothing);
  });

  testWidgets('the tax switch says what turning it off is for', (tester) async {
    await open(tester)();
    expect(find.textContaining("somebody else's behalf"), findsOneWidget);
  });

  testWidgets('Arabic renders without overflowing', (tester) async {
    await open(tester, locale: 'ar')();
    expect(tester.takeException(), isNull);
    expect(find.text('نسبة مئوية'), findsOneWidget);
  });
}
