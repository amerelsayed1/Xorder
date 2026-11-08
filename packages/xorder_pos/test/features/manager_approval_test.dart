import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/reason_code.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin_mode/supervisor_override.dart';

/// The manager-approval dialog (patterns 5.1).
///
/// A cashier has asked for something above their permission or their limit, and
/// a manager authorises it standing at the till. Two things must hold or the
/// whole override model is theatre: the supervisor must be told what they are
/// approving in words they can act on, and **both** names must end up on the
/// record.
void main() {
  const supervisor = PosStaff(
    id: 9,
    name: 'Hana Mostafa',
    capabilities: {PosCapability.discountApply},
  );
  const cashier = PosStaff(
    id: 4,
    name: 'Nour Adel',
    capabilities: {PosCapability.operate},
  );

  /// Only `9999` belongs to somebody who may approve. `1111` is a real person
  /// without the capability; `0000` is nobody.
  final directory = _Directory({'9999': supervisor, '1111': cashier});

  List<ReasonCode> reasons() => [
    for (var i = 0; i < 4; i++)
      ReasonCode(
        id: i + 1,
        scope: ReasonScope.discount,
        code: SystemReasons.seeded[i].code,
        nameEn: SystemReasons.seeded[i].nameEn,
        nameAr: SystemReasons.seeded[i].nameAr,
        sortOrder: i + 1,
      ),
  ];

  setUp(() {
    directory.reset();
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1200);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<ApprovalOutcome? Function()> open(
    WidgetTester tester, {
    String? limitNote = 'Your manual discount limit is 10%. This discount is 30%.',
    ReasonRequirement requirement = ReasonRequirement.required,
    String locale = 'en',
  }) async {
    ApprovalOutcome? outcome;
    var returned = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffDirectoryRepositoryProvider.overrideWithValue(directory),
          signedInStaffProvider.overrideWith(_SignedIn.new),
        ],
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
                  outcome = await SupervisorOverrideDialog.show(
                    context,
                    capability: PosCapability.discountApply,
                    action: 'Discount this line by 30%',
                    requestedBy: 'Nour Adel · Cashier · Till 2',
                    subjectLabel: 'THE LINE',
                    subject: '2 x Grilled Chicken - 268.00',
                    limitNote: limitNote,
                    approveLabel: 'Approve discount',
                    reasons: reasons(),
                    reasonRequirement: requirement,
                  );
                  returned = true;
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

    return () {
      expect(returned, isTrue, reason: 'the dialog has not closed yet');
      return outcome;
    };
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.widgetWithText(InkWell, digit).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  bool isOpen() => find.text('Discount this line by 30%').evaluate().isNotEmpty;

  group('what the supervisor is told', () {
    testWidgets('the act, in words, not the permission key', (tester) async {
      await open(tester);

      // A supervisor approving "discount.apply" is approving a string. One
      // approving "Discount this line by 30%" is approving an act.
      expect(find.text('Discount this line by 30%'), findsOneWidget);
      expect(find.textContaining('discount.apply'), findsNothing);
    });

    testWidgets('who is asking, and what it is being done to', (tester) async {
      await open(tester);

      expect(find.text('Nour Adel · Cashier · Till 2'), findsOneWidget);
      expect(find.text('THE LINE'), findsOneWidget);
      expect(find.text('2 x Grilled Chicken - 268.00'), findsOneWidget);
    });

    testWidgets('the limit AND the number that exceeded it', (tester) async {
      await open(tester);

      // A supervisor told only "above the limit" has to ask two questions
      // before they can decide anything.
      expect(
        find.text('Your manual discount limit is 10%. This discount is 30%.'),
        findsOneWidget,
      );
      expect(find.text('Above the limit'), findsOneWidget);
    });

    testWidgets('no limit strip when no limit was exceeded', (tester) async {
      // The other half of the override model: a permission somebody simply does
      // not hold, with no ceiling involved.
      await open(tester, limitNote: null);

      expect(find.text('Above the limit'), findsNothing);
      expect(find.text('Discount this line by 30%'), findsOneWidget);
    });
  });

  group('approving', () {
    testWidgets('a supervisor PIN and a reason approves', (tester) async {
      final result = await open(tester);

      await typePin(tester, '9999');
      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();

      // The dialog does not close on approval — it shows both names first.
      expect(find.textContaining('Hana Mostafa approved this'), findsOneWidget);
      expect(find.textContaining('Nour Adel'), findsWidgets);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final outcome = result();
      expect(outcome, isNotNull);
      expect(outcome!.approver.name, 'Hana Mostafa');
      expect(outcome.reason?.reason?.code, 'wrong_item');
    });

    testWidgets('a four-digit PIN alone does not approve', (tester) async {
      await open(tester);

      await typePin(tester, '9999');

      // The old dialog fired the moment four digits were in. That cannot work
      // once a reason is also required — it would approve before the manager
      // had said why.
      expect(isOpen(), isTrue);
      expect(find.textContaining('approved this'), findsNothing);
    });

    testWidgets('the approve button is muted until both are in, never hidden',
        (tester) async {
      await open(tester);

      // Visible from the start: a manager has to be able to see what completing
      // the form will let them do.
      expect(find.text('Approve discount'), findsOneWidget);

      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();
      expect(isOpen(), isTrue);

      await typePin(tester, '9999');
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();
      expect(isOpen(), isTrue, reason: 'still no reason given');
    });

    testWidgets('a reason is not asked for when the business switched it off',
        (tester) async {
      final result = await open(tester, requirement: ReasonRequirement.disabled);

      expect(find.text('Wrong item made'), findsNothing);
      await typePin(tester, '9999');
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result()?.approver.name, 'Hana Mostafa');
      expect(result()?.reason, isNull);
    });
  });

  group('refusing', () {
    testWidgets('a PIN nobody has says how many tries are left', (tester) async {
      await open(tester);

      await typePin(tester, '0000');
      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong PIN. 4 attempts left.'), findsOneWidget);
      expect(isOpen(), isTrue);
    });

    testWidgets('a real person without the capability gets the same message',
        (tester) async {
      await open(tester);

      await typePin(tester, '1111');
      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();

      // Deliberately identical to "no such PIN". Distinguishing them would turn
      // the keypad into a way of discovering who holds which permission.
      expect(find.text('Wrong PIN. 4 attempts left.'), findsOneWidget);
    });

    testWidgets('the attempt counter counts down', (tester) async {
      await open(tester);
      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();

      await typePin(tester, '0000');
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN. 4 attempts left.'), findsOneWidget);

      await typePin(tester, '0000');
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN. 3 attempts left.'), findsOneWidget);
    });

    testWidgets('one attempt left is stated in the singular', (tester) async {
      await open(tester);
      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await typePin(tester, '0000');
        await tester.tap(find.text('Approve discount'));
        await tester.pumpAndSettle();
      }

      // "1 attempts left" is the kind of detail that makes a person distrust
      // everything else on the screen.
      expect(find.text('Wrong PIN. One attempt left.'), findsOneWidget);
    });
  });

  group('the keyboard', () {
    testWidgets('digits type the PIN', (tester) async {
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Hana Mostafa approved this'), findsOneWidget);
    });

    testWidgets('Enter approves only once the PIN and reason are both in',
        (tester) async {
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(isOpen(), isTrue, reason: 'nothing typed yet');

      await typePin(tester, '9999');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('approved this'), findsNothing,
          reason: 'no reason yet');

      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('Hana Mostafa approved this'), findsOneWidget);
    });

    testWidgets('Esc cancels and approves nothing', (tester) async {
      final result = await open(tester);

      await typePin(tester, '9999');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(isOpen(), isFalse);
      expect(result(), isNull);
    });

    testWidgets('a click outside does not dismiss it', (tester) async {
      await open(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(isOpen(), isTrue);
    });
  });

  group('Arabic', () {
    testWidgets('the chrome follows the locale, right to left', (tester) async {
      await open(tester, locale: 'ar');

      expect(find.text('يلزم اعتماد'), findsOneWidget);
      expect(find.text('رمز المدير'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('يلزم اعتماد'))),
        TextDirection.rtl,
      );
    });

    testWidgets('the subject stays left to right, being data', (tester) async {
      await open(tester, locale: 'ar');

      expect(
        Directionality.of(
          tester.element(find.text('2 x Grilled Chicken - 268.00')),
        ),
        TextDirection.ltr,
      );
    });
  });
}

/// The cashier who is asking, already signed in at the till.
class _SignedIn extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 4,
    name: 'Nour Adel',
    capabilities: {PosCapability.operate},
  );
}

/// A staff directory with a known PIN map. Only the two methods this flow
/// touches do anything.
class _Directory implements StaffDirectoryRepository {
  _Directory(this._pins);

  final Map<String, PosStaff> _pins;
  var lookups = 0;

  void reset() => lookups = 0;

  @override
  Future<PosStaff?> byPin(String pin) async {
    lookups++;
    return _pins[pin];
  }

  @override
  Future<List<PosStaff>> all({bool includeInactive = true}) async =>
      _pins.values.toList();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
