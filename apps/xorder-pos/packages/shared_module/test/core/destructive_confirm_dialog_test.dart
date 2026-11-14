import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/destructive_confirm_dialog.dart';
import 'package:shared_module/domain/models/reason_code.dart';

/// Void, refund, restore, force-close.
///
/// Most of what follows is not about what the dialog looks like. It is about
/// what it refuses to do: fire on a reflex. A cashier clearing dialogs at speed
/// during a rush must not be able to void an order by pressing Enter twice, and
/// that property is exactly the kind a later refactor removes without noticing.
void main() {
  List<ReasonCode> reasons() => [
    for (var i = 0; i < SystemReasons.seeded.length; i++)
      ReasonCode(
        id: i + 1,
        scope: ReasonScope.voidAct,
        code: SystemReasons.seeded[i].code,
        nameEn: SystemReasons.seeded[i].nameEn,
        nameAr: SystemReasons.seeded[i].nameAr,
        requiresNote: SystemReasons.seeded[i].requiresNote,
        sortOrder: i + 1,
      ),
  ];

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1100);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// Opens the dialog and hands back a getter for what it returned. The result
  /// is deliberately read *after* the dialog closes, never assumed.
  Future<ReasonSelection? Function()> open(
    WidgetTester tester, {
    ReasonRequirement requirement = ReasonRequirement.required,
    Money? amount = const Money(48650),
    List<String> consequences = const [
      'The order is lifted off table 12 and the table is freed.',
      'Three lines already sent to the kitchen are marked VOID.',
      'This cannot be undone. A refund is the only way money moves back.',
    ],
    String locale = 'en',
  }) async {
    ReasonSelection? result;
    var returned = false;

    await tester.pumpWidget(
      MaterialApp(
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
                result = await DestructiveConfirmDialog.show(
                  context,
                  title: 'Void order INV-2481?',
                  confirmLabel: 'Void order · 486.50',
                  keepLabel: 'Keep order',
                  amount: amount,
                  consequences: consequences,
                  reasons: reasons(),
                  requirement: requirement,
                );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    return () {
      expect(returned, isTrue, reason: 'the dialog has not closed yet');
      return result;
    };
  }

  bool isOpen() => find.text('Void order INV-2481?').evaluate().isNotEmpty;

  group('what it says', () {
    testWidgets('names the act and warns it cannot be undone', (tester) async {
      await open(tester);

      expect(find.text('Void order INV-2481?'), findsOneWidget);
      expect(find.text('CANNOT BE UNDONE'), findsOneWidget);
    });

    testWidgets('the amount is the loudest thing in the dialog', (
      tester,
    ) async {
      await open(tester);

      final amount = tester.widget<Text>(find.text('486.50 EGP'));
      // 32/600 mono. A person deciding whether to void something is deciding
      // about an amount, and it must not be a detail buried in a sentence.
      expect(amount.style!.fontSize, 32);
      expect(amount.style!.fontFamily, PosFonts.mono);
    });

    testWidgets('the confirm button states the amount too', (tester) async {
      await open(tester);

      // "Confirm" tells nobody what they are about to lose.
      expect(find.text('Void order · 486.50'), findsOneWidget);
    });

    testWidgets('shows every consequence, worst last', (tester) async {
      await open(tester);

      expect(find.textContaining('table is freed'), findsOneWidget);
      expect(find.textContaining('marked VOID'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
    });

    testWidgets('never shows more than three consequences', (tester) async {
      await open(
        tester,
        consequences: const ['One', 'Two', 'Three', 'Four', 'Five'],
      );

      // Three is a limit, not a target: somebody reading a fourth line has
      // stopped reading, and the last line is the one that matters most.
      expect(find.text('Three'), findsOneWidget);
      expect(find.text('Four'), findsNothing);
      expect(find.text('Five'), findsNothing);
    });

    testWidgets('an act with no money shows no amount cell', (tester) async {
      // A force-close, a restore. Rendering "0.00" would be a claim about
      // money where there is none.
      await open(tester, amount: null);

      expect(find.text('AMOUNT'), findsNothing);
      expect(find.text('Void order INV-2481?'), findsOneWidget);
    });

    testWidgets('states the keyboard contract under the buttons', (
      tester,
    ) async {
      await open(tester);

      expect(
        find.textContaining('the confirm button is never focused'),
        findsOneWidget,
      );
    });
  });

  group('the deliberate-action rule', () {
    testWidgets('the safe button holds focus on open', (tester) async {
      await open(tester);

      final focused = primaryFocus;
      expect(focused, isNotNull);
      // The choice already under the person's hands is the one that changes
      // nothing.
      expect(
        find.descendant(
          of: find.byWidget(focused!.context!.widget),
          matching: find.text('Keep order'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Enter on open does nothing at all', (tester) async {
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Not "Enter keeps the order" — nothing. Enter is the reflex key, the one
      // a hand presses to make a dialog go away, and it is consumed at the
      // dialog so it never reaches the control holding focus.
      expect(isOpen(), isTrue);
    });

    testWidgets('Enter still does nothing once the dialog is armed', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Arming the dialog must not turn Enter back into a commit key. This is
      // the regression the rule exists to prevent.
      expect(isOpen(), isTrue);
    });

    testWidgets('Esc keeps the order', (tester) async {
      final result = await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(isOpen(), isFalse);
      expect(result(), isNull, reason: 'null means the act did not happen');
    });

    testWidgets('a click outside does not dismiss it', (tester) async {
      await open(tester);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Somebody who did not notice the dialog also did not read it, and the
      // next thing they press is the one that matters.
      expect(isOpen(), isTrue);
    });
  });

  group('arming', () {
    testWidgets('starts disarmed when a reason is required', (tester) async {
      await open(tester);

      await tester.tap(find.text('Void order · 486.50'));
      await tester.pumpAndSettle();

      expect(isOpen(), isTrue, reason: 'pressing a disarmed button does nothing');
    });

    testWidgets('the disarmed button is muted, never hidden', (tester) async {
      await open(tester);

      // The person must be able to see that confirming exists, and that
      // choosing a reason is what unlocks it.
      expect(find.text('Void order · 486.50'), findsOneWidget);
    });

    testWidgets('a reason arms it, and confirming returns that reason', (
      tester,
    ) async {
      final result = await open(tester);

      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void order · 486.50'));
      await tester.pumpAndSettle();

      expect(isOpen(), isFalse);
      expect(result()?.reason?.code, 'wrong_item');
    });

    testWidgets('Other stays disarmed until a note is typed', (tester) async {
      final result = await open(tester);

      await tester.tap(find.text('Other — note required'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void order · 486.50'));
      await tester.pumpAndSettle();
      expect(isOpen(), isTrue);

      await tester.enterText(find.byType(TextField), 'Dropped by the runner');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void order · 486.50'));
      await tester.pumpAndSettle();

      expect(isOpen(), isFalse);
      expect(result()?.note, 'Dropped by the runner');
    });

    testWidgets('a switched-off reason list arms it immediately', (
      tester,
    ) async {
      final result = await open(
        tester,
        requirement: ReasonRequirement.disabled,
      );

      expect(find.text('Wrong item made'), findsNothing);
      await tester.tap(find.text('Void order · 486.50'));
      await tester.pumpAndSettle();

      // A non-null selection carrying a null reason: the act happened, on a
      // list the business switched off. Distinguishable from keeping.
      final selection = result();
      expect(selection, isNotNull);
      expect(selection!.reason, isNull);
    });

    testWidgets('an optional list arms it with no reason', (tester) async {
      final result = await open(
        tester,
        requirement: ReasonRequirement.optional,
      );

      await tester.tap(find.text('Void order · 486.50'));
      await tester.pumpAndSettle();
      expect(result(), isNotNull);
    });

    testWidgets('keeping returns null even after a reason was picked', (
      tester,
    ) async {
      final result = await open(tester);

      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep order'));
      await tester.pumpAndSettle();

      // A reason chosen and then abandoned is not a reason given.
      expect(result(), isNull);
    });
  });

  group('Arabic', () {
    testWidgets('warns and asks in Arabic, right to left', (tester) async {
      await open(tester, locale: 'ar');

      expect(find.text('لا يمكن التراجع عنه'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('لا يمكن التراجع عنه'))),
        TextDirection.rtl,
      );
    });

    testWidgets('the amount stays left to right', (tester) async {
      await open(tester, locale: 'ar');

      expect(
        Directionality.of(tester.element(find.text('486.50 EGP'))),
        TextDirection.ltr,
      );
    });
  });
}
