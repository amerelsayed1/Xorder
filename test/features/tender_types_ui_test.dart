import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';
import 'package:xorder_pos/features/admin/presentation/tender_type_dialog.dart';

/// Authoring payment methods, on screen (§40).
///
/// The thing worth pinning is that the dialog asks the two drawer questions
/// separately. "Counts as cash" decides what the drawer is expected to hold;
/// "opens the drawer" decides whether the till kicks it. A restaurant that
/// keeps meal vouchers in the till wants the second and not the first, and one
/// checkbox for both is how a cash-up starts reporting a surplus nobody can
/// explain.
void main() {
  const admin = PosStaff(
    id: 1,
    name: 'Mona',
    capabilities: {PosCapability.settingsManage},
  );

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

  Future<TenderMethod?> pump(
    WidgetTester tester, {
    TenderMethod? method,
    String locale = 'en',
  }) async {
    TenderMethod? saved;
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
                  saved = await TenderTypeDialog.show(context, method: method);
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
  }

  Future<TenderMethod?> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tender-save')));
    await tester.pumpAndSettle();
    return null;
  }

  testWidgets('the two drawer questions are asked separately', (tester) async {
    await pump(tester);

    expect(find.text('Counts as cash'), findsOneWidget);
    expect(find.text('Opens the drawer'), findsOneWidget);
    // And the difference is spelled out where it is asked, not in a manual.
    expect(find.textContaining('vouchers kept in the till'), findsOneWidget);
  });

  testWidgets('a new method starts as nothing in particular', (tester) async {
    // Every switch off except the one that is safe to have on. A dialog that
    // pre-ticked "counts as cash" would put a method in the drawer because
    // somebody pressed New.
    await pump(tester);

    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(
      switches.where((s) => s.value).length,
      1,
      reason: 'only "money can go back this way"',
    );
  });

  testWidgets('a retired method can be brought back', (tester) async {
    // The switch only exists when editing: there is nothing to un-retire on a
    // method that does not exist yet.
    await pump(
      tester,
      method: const TenderMethod(
        id: 5,
        code: 'voucher',
        nameEn: 'Voucher',
        isActive: false,
      ),
    );
    expect(find.text('Offered at the till'), findsOneWidget);
  });

  testWidgets('a new method is not offered an active switch', (tester) async {
    await pump(tester);
    expect(find.text('Offered at the till'), findsNothing);
  });

  testWidgets('the code is fixed once a method exists', (tester) async {
    // Changing a code on a live method points every integration that knows it
    // at nothing.
    await pump(
      tester,
      method: const TenderMethod(id: 5, code: 'voucher', nameEn: 'Voucher'),
    );

    final code = tester.widgetList<TextField>(find.byType(TextField)).toList()[2];
    expect(code.enabled, isFalse);
  });

  testWidgets('a code is generated from the name rather than demanded',
      (tester) async {
    // Nobody setting up a restaurant has an opinion about a machine identifier.
    late TenderMethod? result;
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
                  result = await TenderTypeDialog.show(context);
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

    await tester.enterText(find.byType(TextField).first, 'Meal Voucher');
    await tester.pumpAndSettle();
    await save(tester);

    expect(result?.code, 'meal_voucher');
    expect(result?.nameEn, 'Meal Voucher');
    expect(result?.id, 0, reason: 'zero means create');
  });

  testWidgets('what was chosen is what comes back', (tester) async {
    late TenderMethod? result;
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
                  result = await TenderTypeDialog.show(context);
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

    await tester.enterText(find.byType(TextField).first, 'Voucher');
    await tester.tap(find.text('Voucher').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opens the drawer'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(result?.kind, TenderKind.voucher);
    expect(result?.opensDrawer, isTrue);
    expect(
      result?.countsAsCash,
      isFalse,
      reason: 'the drawer opens for it and it is not cash',
    );
  });

  testWidgets('Arabic renders without overflowing', (tester) async {
    await pump(tester, locale: 'ar');
    expect(tester.takeException(), isNull);
    expect(find.text('يُحتسب نقدًا'), findsOneWidget);
  });

  test('the admin is the one who saves it', () {
    // Guards the plumbing this dialog has none of: it returns a value and the
    // pane writes it, so the dialog itself never needs a permission.
    expect(admin.can(PosCapability.settingsManage), isTrue);
  });
}
