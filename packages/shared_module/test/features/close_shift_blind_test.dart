import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/pos_settings.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/features/shift/presentation/shift_dialogs.dart';

/// A blind count is a count.
///
/// The Z report hid the expected cash from somebody who may not see it, but the
/// panel under the count field went on saying `SHORT -50.00` the moment a
/// number was typed, `BALANCES` and the expected figure when it matched, and,
/// before any number, "Expected 323.45 — float …". Each is the expected cash one
/// subtraction away, so the policy protected nothing (audit, 17 Oct 2026).
///
/// The drawer here opened with 200.00, took 123.45 in cash and 126.55 on a card,
/// had 50.00 paid in and 20.00 paid out: the expected cash is 353.45, a number
/// that appears nowhere else on the screen.
///
/// The Z report is held to the same rule. The expected cash is the float plus
/// the cash tenders plus pay-ins less pay-outs, so a blind cashier shown the
/// tender rows and the pay-in and pay-out rows beside the float is shown the
/// sum with the answer masked (audit, 17 Oct 2026). What blind withholds there
/// is those components; the sales totals stay, because the cashier rang the
/// sales and a Z report without them is no report.
void main() {
  final shift = PosShift(
    id: 7,
    openedAt: DateTime(2026, 10, 16, 9),
    openingFloat: const Money(20000),
    openedByName: 'Amer M.',
    openedById: 1,
  );

  const expected = Money(35345); // 200.00 float + 123.45 cash + 50.00 in - 20.00 out

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> open(
    WidgetTester tester, {
    required bool blindPolicy,
    required bool mayViewExpected,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shiftRepositoryProvider.overrideWithValue(_Shifts()),
          auditRepositoryProvider.overrideWithValue(FakeAuditRepository()),
          cashPolicyProvider.overrideWithValue(
            CashPolicy(blindClose: blindPolicy),
          ),
          signedInStaffProvider.overrideWith(
            () => _Staff(mayViewExpected: mayViewExpected),
          ),
          openTicketsProvider.overrideWith(_NothingParked.new),
        ],
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
                onPressed: () => CloseShiftDialog.show(context, shift: shift),
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
  }

  Future<void> count(WidgetTester tester, String typed) async {
    await tester.enterText(find.byType(TextField).first, typed);
    await tester.pump();
  }

  /// Text the screen SHOWS containing [needle]. Not the count field's own
  /// content: what the cashier typed is theirs, and typing the expected figure
  /// is how a balancing count is tested.
  Finder shows(String needle) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').contains(needle),
  );

  AppStrings strings(WidgetTester tester) =>
      tester.element(find.byType(CloseShiftDialog)).strings;

  group('a blind cashier', () {
    testWidgets('is told no expected figure before counting', (tester) async {
      await open(tester, blindPolicy: true, mayViewExpected: false);

      expect(shows('Expected'), findsNothing);
      expect(shows(expected.format()), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is not told short, over or balances after typing a count', (
      tester,
    ) async {
      await open(tester, blindPolicy: true, mayViewExpected: false);
      final s = strings(tester);

      for (final (typed, difference) in [
        ('300.00', '-53.45'), // short
        ('400.00', '46.55'), // over
        ('353.45', null), // balances
      ]) {
        await count(tester, typed);

        expect(find.text(s.varianceShort), findsNothing, reason: typed);
        expect(find.text(s.varianceOver), findsNothing, reason: typed);
        expect(find.text(s.varianceBalances), findsNothing, reason: typed);
        if (difference != null) {
          expect(find.text(difference), findsNothing, reason: typed);
        }
        expect(shows(expected.format()), findsNothing, reason: typed);
      }
    });

    testWidgets('can still close the drawer', (tester) async {
      await open(tester, blindPolicy: true, mayViewExpected: false);

      await count(tester, '300.00');
      // The dialog scrolls; on a busy drawer the button is below the fold.
      await tester.ensureVisible(find.text('Close shift'));
      await tester.tap(find.text('Close shift'));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('somebody who may see the expected cash', () {
    testWidgets('is told it before counting, under a blind policy too', (
      tester,
    ) async {
      await open(tester, blindPolicy: true, mayViewExpected: true);

      expect(shows('Expected ${expected.format()}'), findsOneWidget);
    });

    testWidgets('sees the live difference while counting', (tester) async {
      await open(tester, blindPolicy: true, mayViewExpected: true);
      final s = strings(tester);

      await count(tester, '300.00');
      expect(find.text(s.varianceShort), findsOneWidget);
      expect(find.text('-53.45 EGP'), findsOneWidget);

      await count(tester, '400.00');
      expect(find.text(s.varianceOver), findsOneWidget);

      await count(tester, '353.45');
      expect(find.text(s.varianceBalances), findsOneWidget);
    });
  });

  group('the Z report on the same screen', () {
    testWidgets('does not lay out the cash components for a blind cashier', (
      tester,
    ) async {
      await open(tester, blindPolicy: true, mayViewExpected: false);
      final s = strings(tester);

      // The tenders, each one: cash and card.
      expect(shows('Cash ×'), findsNothing);
      expect(shows('Card ×'), findsNothing);
      expect(shows('123.45'), findsNothing);
      expect(shows('126.55'), findsNothing);
      // Money paid in and out of the drawer.
      expect(find.text(s.zCashIn), findsNothing);
      expect(find.text(s.zCashOut), findsNothing);
      // Exact: `50.00` is inside the gross `250.00` and `20.00` inside the float.
      expect(find.text('50.00'), findsNothing);
      expect(find.text('-20.00'), findsNothing);
      // And still masked where the answer would be.
      expect(find.text(s.zHiddenUntilCounted), findsOneWidget);
    });

    testWidgets('still reports what was sold', (tester) async {
      await open(tester, blindPolicy: true, mayViewExpected: false);
      final s = strings(tester);

      expect(find.text(s.zSales), findsOneWidget);
      expect(find.text(s.zGrossTaken), findsOneWidget);
      expect(shows('250.00'), findsOneWidget); // gross
      expect(find.text(s.zOpeningFloat), findsOneWidget);
    });

    testWidgets('shows everything to somebody who may see the expected cash', (
      tester,
    ) async {
      await open(tester, blindPolicy: true, mayViewExpected: true);
      final s = strings(tester);

      // Exact row values: `123.45` is also inside the "Expected … plus 123.45
      // taken in cash" help line, which is not what this is about.
      expect(shows('Cash ×'), findsOneWidget);
      expect(shows('Card ×'), findsOneWidget);
      expect(find.text('123.45 EGP'), findsOneWidget);
      expect(find.text('126.55 EGP'), findsOneWidget);
      expect(find.text(s.zCashIn), findsOneWidget);
      expect(find.text(s.zCashOut), findsOneWidget);
      expect(find.text('50.00 EGP'), findsOneWidget);
      expect(find.text('-20.00 EGP'), findsOneWidget);
      expect(find.text(s.zExpectedInDrawer), findsOneWidget);
    });

    testWidgets('shows everything with blind counting off', (tester) async {
      await open(tester, blindPolicy: false, mayViewExpected: false);
      final s = strings(tester);

      expect(shows('Cash ×'), findsOneWidget);
      expect(find.text(s.zCashIn), findsOneWidget);
      expect(find.text(s.zCashOut), findsOneWidget);
    });
  });

  testWidgets('with blind counting off, a cashier sees the difference as before',
      (tester) async {
    await open(tester, blindPolicy: false, mayViewExpected: false);
    final s = strings(tester);

    expect(shows('Expected ${expected.format()}'), findsOneWidget);
    await count(tester, '300.00');
    expect(find.text(s.varianceShort), findsOneWidget);
  });
}

/// A drawer with 123.45 cash and 126.55 card taken, 50.00 paid in, 20.00 out.
class _Shifts extends FakeShiftRepository {
  @override
  Future<ShiftSummary> summarise(PosShift shift) async => ShiftSummary(
    shift: shift,
    saleCount: 5,
    gross: const Money(25000),
    tenders: const [
      ShiftTenderTotal(
        label: 'Cash',
        count: 3,
        amount: Money(12345),
        countsAsCash: true,
      ),
      ShiftTenderTotal(
        label: 'Card',
        count: 2,
        amount: Money(12655),
        countsAsCash: false,
      ),
    ],
    movements: const CashMovementTotals(
      paidIn: Money(5000),
      paidOut: Money(2000),
      drawerOpens: 0,
      movements: [],
    ),
  );
}

/// Opened this drawer, so may close it. Whether they may see the expected cash
/// is the point of the tests.
class _Staff extends SignedInStaffController {
  _Staff({required this.mayViewExpected});

  final bool mayViewExpected;

  @override
  PosStaff? build() => PosStaff(
    id: 1,
    name: 'Amer M.',
    capabilities: {
      PosCapability.operate,
      PosCapability.shiftClose,
      if (mayViewExpected) PosCapability.shiftViewExpectedCash,
    },
  );
}

class _NothingParked extends OpenTicketsController {
  @override
  OpenTickets build() => const OpenTickets();
}
