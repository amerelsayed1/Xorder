import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/pos_settings.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/shift/presentation/shift_dialogs.dart';

/// A blind count is a count.
///
/// The Z report hid the expected cash from somebody who may not see it, but the
/// panel under the count field went on saying `SHORT -50.00` the moment a
/// number was typed, `BALANCES` and the expected figure when it matched, and,
/// before any number, "Expected 323.45 — float …". Each is the expected cash one
/// subtraction away, so the policy protected nothing (audit, 17 Oct 2026).
///
/// The drawer here opened with 200.00 and took 123.45 in cash, so the expected
/// cash is 323.45, a number that appears nowhere else on the screen.
void main() {
  final shift = PosShift(
    id: 7,
    openedAt: DateTime(2026, 10, 16, 9),
    openingFloat: const Money(20000),
    openedByName: 'Amer M.',
    openedById: 1,
  );

  const expected = Money(32345); // 200.00 float + 123.45 cash

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
        ('300.00', '-23.45'), // short
        ('400.00', '76.55'), // over
        ('323.45', null), // balances
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
      expect(find.text('-23.45'), findsOneWidget);

      await count(tester, '400.00');
      expect(find.text(s.varianceOver), findsOneWidget);

      await count(tester, '323.45');
      expect(find.text(s.varianceBalances), findsOneWidget);
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

/// A drawer with 123.45 of cash taken in it.
class _Shifts extends FakeShiftRepository {
  @override
  Future<ShiftSummary> summarise(PosShift shift) async => ShiftSummary(
    shift: shift,
    saleCount: 3,
    gross: const Money(12345),
    tenders: const [
      ShiftTenderTotal(
        label: 'Cash',
        count: 3,
        amount: Money(12345),
        countsAsCash: true,
      ),
    ],
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
