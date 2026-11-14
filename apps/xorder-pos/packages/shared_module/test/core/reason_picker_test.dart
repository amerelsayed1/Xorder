import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/reason_picker.dart';
import 'package:shared_module/domain/models/reason_code.dart';

/// The reason picker is shared by void, refund, pay-out, price override,
/// force-close and inventory adjustment. Everything asserted here is a rule the
/// business relies on being the same in all six.
void main() {
  /// The seeded list, as it comes back from `pos_reason_codes`.
  List<ReasonCode> reasons({ReasonScope scope = ReasonScope.voidAct}) => [
    for (var i = 0; i < SystemReasons.seeded.length; i++)
      ReasonCode(
        id: i + 1,
        scope: scope,
        code: SystemReasons.seeded[i].code,
        nameEn: SystemReasons.seeded[i].nameEn,
        nameAr: SystemReasons.seeded[i].nameAr,
        requiresNote: SystemReasons.seeded[i].requiresNote,
        sortOrder: i + 1,
      ),
  ];

  ReasonCode other() => reasons().firstWhere((r) => r.code == 'other');
  ReasonCode wrongItem() => reasons().firstWhere((r) => r.code == 'wrong_item');

  // A desktop till, not a phone. The default 800x600 test surface is smaller
  // than any machine this product runs on, and a ten-row list plus a note field
  // does not fit on it — which is a fact about the test harness, not about the
  // widget.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget host(Widget child, {String locale = 'en'}) => MaterialApp(
    locale: Locale(locale),
    theme: buildPosTheme(PosPalette.light),
    localizationsDelegates: const [
      AppLocalizations(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: SizedBox(width: 520, child: child))),
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(host(child, locale: locale));
    await tester.pumpAndSettle();
  }

  group('isSatisfied', () {
    test('required needs a reason', () {
      expect(
        ReasonPicker.isSatisfied(
          requirement: ReasonRequirement.required,
          reason: null,
          note: '',
        ),
        isFalse,
      );
      expect(
        ReasonPicker.isSatisfied(
          requirement: ReasonRequirement.required,
          reason: wrongItem(),
          note: '',
        ),
        isTrue,
      );
    });

    test('optional does not', () {
      expect(
        ReasonPicker.isSatisfied(
          requirement: ReasonRequirement.optional,
          reason: null,
          note: '',
        ),
        isTrue,
      );
    });

    test('disabled is always satisfied', () {
      expect(
        ReasonPicker.isSatisfied(
          requirement: ReasonRequirement.disabled,
          reason: null,
          note: '',
        ),
        isTrue,
      );
    });

    test('Other carries no information without a note', () {
      // The rule that is easy to miss: picking "Other" and typing nothing is
      // the same as not answering, whatever the list-level requirement says.
      expect(
        ReasonPicker.isSatisfied(
          requirement: ReasonRequirement.required,
          reason: other(),
          note: '   ',
        ),
        isFalse,
      );
      expect(
        ReasonPicker.isSatisfied(
          requirement: ReasonRequirement.required,
          reason: other(),
          note: 'Regular customer, comped by Hana',
        ),
        isTrue,
      );
    });

    test('Other still needs a note even when the list is optional', () {
      expect(
        ReasonPicker.isSatisfied(
          requirement: ReasonRequirement.optional,
          reason: other(),
          note: '',
        ),
        isFalse,
      );
    });
  });

  group('keyFor', () {
    test('one to nine, then zero', () {
      expect(ReasonPicker.keyFor(0), '1');
      expect(ReasonPicker.keyFor(8), '9');
      // Ten is where a hand runs out of a keypad row, and Other is the tenth.
      expect(ReasonPicker.keyFor(9), '0');
    });
  });

  group('the list', () {
    testWidgets('shows every reason with the key that picks it', (
      tester,
    ) async {
      await pump(
        tester,
        ReasonPicker(
          reasons: reasons(),
          requirement: ReasonRequirement.required,
          onChanged: (_, _) {},
        ),
      );

      expect(find.text('Customer complaint'), findsOneWidget);
      expect(find.text('Other — note required'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('a number key picks its row', (tester) async {
      ReasonCode? picked;
      await pump(
        tester,
        ReasonPicker(
          reasons: reasons(),
          requirement: ReasonRequirement.required,
          onChanged: (reason, _) => picked = reason,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();

      // Second in the business's own sort order, not second alphabetically.
      expect(picked?.code, 'wrong_item');
    });

    testWidgets('zero picks the tenth', (tester) async {
      ReasonCode? picked;
      await pump(
        tester,
        ReasonPicker(
          reasons: reasons(),
          requirement: ReasonRequirement.required,
          onChanged: (reason, _) => picked = reason,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();
      expect(picked?.code, 'other');
    });

    testWidgets('a tap picks too', (tester) async {
      ReasonCode? picked;
      await pump(
        tester,
        ReasonPicker(
          reasons: reasons(),
          requirement: ReasonRequirement.required,
          onChanged: (reason, _) => picked = reason,
        ),
      );

      await tester.tap(find.text('Staff meal'));
      await tester.pump();
      expect(picked?.code, 'staff_meal');
    });

    testWidgets('picking a row does not move the rows', (tester) async {
      await pump(
        tester,
        ReasonPicker(
          reasons: reasons(),
          requirement: ReasonRequirement.required,
          onChanged: (_, _) {},
        ),
      );
      final before = tester.getTopLeft(find.text('Other — note required'));

      await pump(
        tester,
        ReasonPicker(
          reasons: reasons(),
          requirement: ReasonRequirement.required,
          selected: wrongItem(),
          onChanged: (_, _) {},
        ),
      );
      final after = tester.getTopLeft(find.text('Other — note required'));

      // The tick is kept in the layout when unselected. Without that, choosing
      // a reason shifts every row below it — under a finger already moving.
      expect(after, before);
    });

    testWidgets('a disabled list renders nothing at all', (tester) async {
      await pump(
        tester,
        ReasonPicker(
          reasons: reasons(),
          requirement: ReasonRequirement.disabled,
          onChanged: (_, _) {},
        ),
      );

      // Not an empty list: an empty list would tell the person their business
      // has no reasons configured, which is a different and untrue thing.
      expect(find.text('Customer complaint'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('says what is stopping you when Other has no note', (
      tester,
    ) async {
      await pump(
        tester,
        ReasonPicker(
          reasons: reasons(),
          requirement: ReasonRequirement.required,
          selected: other(),
          onChanged: (_, _) {},
        ),
      );

      expect(find.text('This reason needs a note.'), findsOneWidget);
    });
  });

  group('the sheet', () {
    Future<ReasonSelection?> open(
      WidgetTester tester, {
      ReasonRequirement requirement = ReasonRequirement.required,
      String locale = 'en',
    }) async {
      ReasonSelection? result;
      var opened = false;

      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              opened = true;
              result = await ReasonSheet.show(
                context,
                reasons: reasons(),
                requirement: requirement,
                title: 'Void this item',
                confirmLabel: 'Void item',
              );
            },
            child: const Text('open'),
          ),
        ),
        locale: locale,
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      return result;
    }

    testWidgets('names the act, not the permission', (tester) async {
      await open(tester);

      // "Void this item" tells a person what they are agreeing to.
      // "order.void" tells them nothing.
      expect(find.text('Void this item'), findsOneWidget);
      expect(find.text('Void item'), findsOneWidget);
    });

    testWidgets('states the configuration in the header', (tester) async {
      await open(tester);
      expect(find.text('REASON REQUIRED'), findsOneWidget);
    });

    testWidgets('confirm is muted until a reason is picked, never hidden', (
      tester,
    ) async {
      await open(tester);

      // Visible from the start: the person has to be able to see that
      // confirming exists and that a reason is what unlocks it.
      expect(find.text('Void item'), findsOneWidget);

      await tester.tap(find.text('Void item'));
      await tester.pumpAndSettle();
      expect(find.text('Void this item'), findsOneWidget, reason: 'still open');

      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void item'));
      await tester.pumpAndSettle();

      expect(find.text('Void this item'), findsNothing, reason: 'confirmed');
    });

    testWidgets('Other holds the sheet open until a note is typed', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Other — note required'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void item'));
      await tester.pumpAndSettle();
      expect(find.text('Void this item'), findsOneWidget, reason: 'held open');

      await tester.enterText(find.byType(TextField), 'Dropped by the runner');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void item'));
      await tester.pumpAndSettle();
      expect(find.text('Void this item'), findsNothing);
    });

    testWidgets('an optional list confirms with no reason at all', (
      tester,
    ) async {
      await open(tester, requirement: ReasonRequirement.optional);

      expect(find.text('REASON OPTIONAL'), findsOneWidget);
      await tester.tap(find.text('Void item'));
      await tester.pumpAndSettle();
      expect(find.text('Void this item'), findsNothing);
    });

    testWidgets('a disabled list never renders and returns immediately', (
      tester,
    ) async {
      final result = await open(
        tester,
        requirement: ReasonRequirement.disabled,
      );

      // No dialog flashes on screen, and the caller's code path is the same
      // either way — which is the whole reason `show` handles this rather than
      // every caller checking first.
      expect(find.text('Void this item'), findsNothing);
      expect(result, isNotNull);
      expect(result!.reason, isNull);
    });

    testWidgets('Esc closes without a reason', (tester) async {
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Void this item'), findsNothing);
    });

    testWidgets('Enter does nothing until the reason is satisfied', (
      tester,
    ) async {
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Void this item'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Void this item'), findsNothing);
    });

    testWidgets('reads the business\'s own Arabic, in RTL', (tester) async {
      await open(tester, locale: 'ar');

      // The reasons are the business's rows, not translated strings — and
      // the chrome around them follows the locale too.
      expect(find.text('صنف خطأ في التحضير'), findsOneWidget);
      expect(find.text('السبب مطلوب'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('صنف خطأ في التحضير'))),
        TextDirection.rtl,
      );
    });

    testWidgets('the number chips stay LTR in Arabic', (tester) async {
      await open(tester, locale: 'ar');

      // A digit is a number, and numbers do not mirror.
      expect(Directionality.of(tester.element(find.text('1'))), TextDirection.ltr);
    });
  });
}
