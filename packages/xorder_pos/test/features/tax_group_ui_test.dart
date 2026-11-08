import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/features/admin/presentation/tax_group_dialog.dart';

/// A named rate, on screen (§17).
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<TaxGroup?> Function() open(
    WidgetTester tester, {
    TaxGroup? group,
    String locale = 'en',
  }) {
    TaxGroup? saved;

    return () async {
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
                    saved = await TaxGroupDialog.show(context, group: group);
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
      return saved;
    };
  }

  testWidgets('the typed percent becomes basis points exactly', (tester) async {
    TaxGroup? saved;
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
                  saved = await TaxGroupDialog.show(context);
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

    await tester.enterText(find.byKey(const Key('tax-group-name')), 'Reduced');
    await tester.enterText(find.byKey(const Key('tax-group-rate')), '12.5');
    await tester.tap(find.byKey(const Key('tax-group-save')));
    await tester.pumpAndSettle();

    expect(saved?.rateBp, 1250);
    expect(saved?.nameEn, 'Reduced');
    expect(saved?.isActive, isTrue);
    expect(saved?.isDefault, isFalse);
  });

  testWidgets('zero is a rate, and the dialog says why the name matters', (
    tester,
  ) async {
    await open(tester)();
    expect(
      find.textContaining('Zero-rated and exempt are both 0%'),
      findsOneWidget,
    );
  });

  testWidgets('a nameless rate is refused beside the field', (tester) async {
    final result = open(tester);
    await result();

    await tester.enterText(find.byKey(const Key('tax-group-rate')), '14');
    await tester.tap(find.byKey(const Key('tax-group-save')));
    await tester.pumpAndSettle();

    expect(find.byType(TaxGroupDialog), findsOneWidget);
    expect(find.textContaining('needs a name'), findsOneWidget);
  });

  testWidgets('a rate that is not a number is refused', (tester) async {
    await open(tester)();

    await tester.enterText(find.byKey(const Key('tax-group-name')), 'Odd');
    await tester.enterText(find.byKey(const Key('tax-group-rate')), 'fourteen');
    await tester.tap(find.byKey(const Key('tax-group-save')));
    await tester.pumpAndSettle();

    expect(find.byType(TaxGroupDialog), findsOneWidget);
    expect(find.textContaining('between 0 and 100'), findsOneWidget);
  });

  testWidgets('over 100% is refused too', (tester) async {
    await open(tester)();

    await tester.enterText(find.byKey(const Key('tax-group-name')), 'Odd');
    await tester.enterText(find.byKey(const Key('tax-group-rate')), '140');
    await tester.tap(find.byKey(const Key('tax-group-save')));
    await tester.pumpAndSettle();

    expect(find.byType(TaxGroupDialog), findsOneWidget);
  });

  testWidgets('retiring is offered only on a rate that exists', (tester) async {
    await open(tester)();
    expect(find.byKey(const Key('tax-group-active')), findsNothing);
  });

  testWidgets('an existing rate can be retired, and shows its percent', (
    tester,
  ) async {
    await open(
      tester,
      group: const TaxGroup(id: 3, nameEn: 'Reduced', rateBp: 1250),
    )();

    expect(find.byKey(const Key('tax-group-active')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tax-group-rate')))
          .controller
          ?.text,
      '12.5',
      reason: 'basis points shown as the percent a business says out loud',
    );
  });

  testWidgets('the fallback switch explains that it moves', (tester) async {
    await open(tester)();
    expect(
      find.textContaining('making this one takes it off the other'),
      findsOneWidget,
    );
  });

  testWidgets('in Arabic', (tester) async {
    await open(tester, locale: 'ar')();
    expect(find.text('نسبة جديدة'), findsOneWidget);
    expect(find.textContaining('الإعفاء'), findsOneWidget);
  });
}
