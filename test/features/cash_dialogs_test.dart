import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/pos_settings.dart';
import 'package:xorder_pos/domain/models/reason_code.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/cash/presentation/cash_dialogs.dart';
import 'package:xorder_pos/features/cash/presentation/day_close_dialog.dart';

/// Money in and out of the drawer, and the end of the night.
///
/// The claim that carries most weight here is the first group's: **money
/// arriving and money leaving must never be confusable.** Identical arithmetic,
/// opposite meaning — a cashier who reaches for the wrong one records the
/// drawer 100 up when it is 100 down, a 200 discrepancy from one mis-tap.
void main() {
  setUp(() {
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

  Widget host(
    Widget child, {
    required FakeCash cash,
    CashPolicy policy = CashPolicy.defaults,
    bool withShift = true,
    BusinessDayRepository? days,
    String locale = 'en',
    bool nobodyAtTill = false,
    PosStaff? admin,
  }) => ProviderScope(
    overrides: [
      cashMovementsRepositoryProvider.overrideWithValue(cash),
      cashPolicyProvider.overrideWithValue(policy),
      reasonsRepositoryProvider.overrideWithValue(const _Reasons()),
      signedInStaffProvider.overrideWith(
        nobodyAtTill ? _NobodyAtTill.new : _SignedIn.new,
      ),
      if (admin != null)
        adminSessionProvider.overrideWith(() => _AdminIn(admin)),
      // A flag rather than a nullable shift: `shift ?? _openShift` would have
      // made "no shift open" untestable, because passing null is exactly how a
      // caller says there is none.
      shiftProvider.overrideWith((ref) async => withShift ? _openShift : null),
      businessDayProvider.overrideWith((ref) async => null),
      if (days != null) businessDayRepositoryProvider.overrideWithValue(days),
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
      home: Scaffold(body: child),
    ),
  );

  Future<FakeCash> openMovement(
    WidgetTester tester, {
    required CashMovementKind kind,
    CashPolicy policy = CashPolicy.defaults,
    bool withShift = true,
    String locale = 'en',
  }) async {
    final cash = FakeCash();
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => CashMovementDialog.show(context, kind: kind),
            child: const Text('open'),
          ),
        ),
        cash: cash,
        policy: policy,
        withShift: withShift,
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return cash;
  }

  /// Type an amount and pick the first reason **for that direction**.
  ///
  /// The lists differ on purpose — "Supplier payment" is not a reason anybody
  /// puts money into a till — so a helper that always picked the pay-out list
  /// would tap nothing on a pay-in dialog.
  Future<void> fill(
    WidgetTester tester,
    String amount, {
    CashMovementKind kind = CashMovementKind.payOut,
  }) async {
    await tester.enterText(find.byType(TextField).first, amount);
    await tester.pumpAndSettle();

    final reasons = kind == CashMovementKind.payOut
        ? SystemReasons.cashOut
        : SystemReasons.cashIn;
    await tester.tap(find.text(reasons.first.nameEn).hitTestable());
    await tester.pumpAndSettle();
  }

  group('in and out cannot be confused', () {
    testWidgets('money in names itself and shows a plus', (tester) async {
      // Colour carries the direction too, but colour alone fails a
      // colour-blind cashier and a sun-bleached screen. The sign does not.
      await openMovement(tester, kind: CashMovementKind.payIn);
      expect(find.text('Cash in'), findsOneWidget);
      expect(find.text('Cash out'), findsNothing);
      expect(find.text('+'), findsOneWidget);
      expect(find.text('−'), findsNothing);
    });

    testWidgets('money out names itself and shows a minus', (tester) async {
      await openMovement(tester, kind: CashMovementKind.payOut);
      expect(find.text('Cash out'), findsOneWidget);
      expect(find.text('Cash in'), findsNothing);
      expect(find.text('−'), findsOneWidget);
      expect(find.text('+'), findsNothing);
    });

    testWidgets('the button says which act it performs', (tester) async {
      await openMovement(tester, kind: CashMovementKind.payOut);
      expect(find.text('Record cash out'), findsOneWidget);
    });
  });

  group('recording', () {
    testWidgets('writes a positive amount with the kind carrying direction', (
      tester,
    ) async {
      final cash = await openMovement(tester, kind: CashMovementKind.payOut);
      await fill(tester, '50.00');

      await tester.tap(find.text('Record cash out'));
      await tester.pumpAndSettle();

      expect(cash.recorded, hasLength(1));
      final movement = cash.recorded.single;
      expect(movement.kind, CashMovementKind.payOut);
      // Positive in storage; the kind is what points it.
      expect(movement.amount.minor, 5000);
      expect(movement.reasonId, isNotNull);
      expect(movement.shiftId, _openShift.id);
    });

    testWidgets('refuses nothing, and says so', (tester) async {
      final cash = await openMovement(tester, kind: CashMovementKind.payIn);
      await tester.tap(find.text('Record cash in'));
      await tester.pumpAndSettle();

      expect(cash.recorded, isEmpty);
      expect(find.text('Enter an amount above zero.'), findsOneWidget);
    });

    testWidgets('will not record without a reason', (tester) async {
      // §22 does not make a reason optional for money leaving a drawer, and
      // neither does anybody who has ever had to explain one.
      final cash = await openMovement(tester, kind: CashMovementKind.payOut);
      await tester.enterText(find.byType(TextField).first, '50.00');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Record cash out'));
      await tester.pumpAndSettle();

      expect(cash.recorded, isEmpty);
      expect(find.textContaining('reason'), findsWidgets);
    });

    testWidgets('refuses a pay-out above the configured ceiling', (
      tester,
    ) async {
      final cash = await openMovement(
        tester,
        kind: CashMovementKind.payOut,
        policy: const CashPolicy(payOutCeiling: Money(10000)),
      );
      await fill(tester, '150.00');

      await tester.tap(find.text('Record cash out'));
      await tester.pumpAndSettle();

      // A ceiling, not an approval prompt — §22 makes this configured rather
      // than something waved through at the counter.
      expect(cash.recorded, isEmpty);
      expect(find.textContaining('above the'), findsOneWidget);
    });

    testWidgets('the ceiling does not apply to money coming in', (
      tester,
    ) async {
      final cash = await openMovement(
        tester,
        kind: CashMovementKind.payIn,
        policy: const CashPolicy(payOutCeiling: Money(10000)),
      );
      await fill(tester, '150.00', kind: CashMovementKind.payIn);

      await tester.tap(find.text('Record cash in'));
      await tester.pumpAndSettle();
      expect(cash.recorded, hasLength(1));
    });

    testWidgets('says so when no shift is open', (tester) async {
      final cash = FakeCash();
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => CashMovementDialog.show(
                context,
                kind: CashMovementKind.payIn,
              ),
              child: const Text('open'),
            ),
          ),
          cash: cash,
          withShift: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await fill(tester, '50.00', kind: CashMovementKind.payIn);

      await tester.tap(find.text('Record cash in'));
      await tester.pumpAndSettle();
      expect(cash.recorded, isEmpty);
      expect(find.text('Open a shift before moving cash.'), findsOneWidget);
    });

    testWidgets('a failed write says nothing moved, and stays open', (
      tester,
    ) async {
      final cash = await openMovement(tester, kind: CashMovementKind.payOut);
      cash.failWith = StateError('the branch server went away');
      await fill(tester, '50.00');

      await tester.tap(find.text('Record cash out'));
      await tester.pumpAndSettle();

      expect(find.textContaining('nothing has moved'), findsOneWidget);
      expect(find.text('Cash out'), findsOneWidget);
    });
  });

  group('the day close', () {
    Future<void> openDay(
      WidgetTester tester, {
      required List<DayBlocker> blockers,
      String locale = 'en',
      _FakeDays? days,
      bool nobodyAtTill = false,
      PosStaff? admin,
    }) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => DayCloseDialog.show(context),
              child: const Text('open'),
            ),
          ),
          cash: FakeCash(),
          days: days ?? _FakeDays(blockers),
          locale: locale,
          nobodyAtTill: nobodyAtTill,
          admin: admin,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a clear day offers a plain close', (tester) async {
      await openDay(tester, blockers: const []);
      expect(find.textContaining('Everything is settled'), findsOneWidget);
      // The title says this too, so both are present; what matters is that the
      // forcing wording is not.
      expect(find.text('Close the day'), findsWidgets);
      expect(find.text('Close anyway'), findsNothing);
    });

    testWidgets('the closer is the person at the till', (tester) async {
      final days = _FakeDays(const []);
      await openDay(tester, blockers: const [], days: days);
      await tester.tap(find.text('Close the day').last);
      await tester.pumpAndSettle();

      expect(days.closedBy, [4]);
    });

    testWidgets(
      'closed from the back office with nobody signed in at the till, the '
      'administrator is the closer, not nobody',
      (tester) async {
        final days = _FakeDays(const []);
        await openDay(
          tester,
          blockers: const [],
          days: days,
          nobodyAtTill: true,
          admin: const PosStaff(
            id: 9,
            name: 'Admin',
            capabilities: {PosCapability.dayClose},
          ),
        );
        await tester.tap(find.text('Close the day').last);
        await tester.pumpAndSettle();

        expect(days.closedBy, [9]);
      },
    );

    testWidgets('blockers are named and counted, not summarised', (
      tester,
    ) async {
      // A close that refused without saying what was in the way would send a
      // manager hunting through four screens at midnight.
      await openDay(
        tester,
        blockers: const [
          DayBlocker(kind: DayBlockerKind.openShift, count: 2),
          DayBlocker(kind: DayBlockerKind.parkedTicket, count: 1),
          DayBlocker(kind: DayBlockerKind.unpaidOrder, count: 3),
        ],
      );

      expect(find.text('2 tills still have drawers open'), findsOneWidget);
      expect(find.text('1 ticket is still parked'), findsOneWidget);
      expect(find.text('3 orders have not been paid'), findsOneWidget);
    });

    testWidgets('with blockers the button says what it really does', (
      tester,
    ) async {
      await openDay(
        tester,
        blockers: const [DayBlocker(kind: DayBlockerKind.openShift, count: 1)],
      );
      expect(find.text('Close anyway'), findsOneWidget);
      // Only the title, not a second button offering the gentler act.
      expect(find.text('Close the day'), findsOneWidget);
    });

    testWidgets('forcing is dead until a reason is typed', (tester) async {
      await openDay(
        tester,
        blockers: const [DayBlocker(kind: DayBlockerKind.openShift, count: 1)],
      );

      // The database refuses a forced close with no reason; the screen refuses
      // it first, so the message names the missing thing.
      final before = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Close anyway'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(before.onTap, isNull);

      await tester.enterText(find.byType(TextField).first, 'Till crashed');
      await tester.pumpAndSettle();

      final after = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Close anyway'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(after.onTap, isNotNull);
    });

    testWidgets('renders in Arabic without overflowing', (tester) async {
      await openDay(
        tester,
        locale: 'ar',
        blockers: const [DayBlocker(kind: DayBlockerKind.openShift, count: 2)],
      );
      expect(find.text('إقفال رغم ذلك'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

final _openShift = PosShift(
  id: 3,
  openedAt: DateTime(2026, 9, 8, 9),
  openingFloat: const Money(20000),
  openedByName: 'Nour Adel',
);

class FakeCash implements CashMovementsRepository {
  final recorded =
      <({CashMovementKind kind, Money amount, int shiftId, int? reasonId})>[];
  Object? failWith;

  @override
  Future<List<CashMovement>> forShift(int shiftId) async => const [];

  @override
  Future<List<CashMovement>> between(
    ReportFilter filter, {
    Set<CashMovementKind> kinds = const {CashMovementKind.payOut},
  }) async => const [];

  @override
  Future<CashMovement> record({
    required CashMovementKind kind,
    required Money amount,
    required PosStaff by,
    required int shiftId,
    int? reasonId,
    String? note,
    Approval? approval,
    int? businessDayId,
  }) async {
    final failure = failWith;
    if (failure != null) throw failure;

    recorded.add((
      kind: kind,
      amount: amount,
      shiftId: shiftId,
      reasonId: reasonId,
    ));
    return CashMovement(
      id: recorded.length,
      kind: kind,
      amount: amount,
      occurredAt: DateTime.utc(2026, 9, 8),
    );
  }
}

class _FakeDays implements BusinessDayRepository {
  _FakeDays(this.blockers);

  final List<DayBlocker> blockers;

  /// The ids of whoever closed, in order.
  final closedBy = <int>[];

  static final _day = BusinessDay(
    id: 1,
    date: DateTime(2026, 9, 8),
    openedAt: DateTime(2026, 9, 8, 6),
  );

  @override
  Future<BusinessDay?> current() async => _day;

  @override
  Future<BusinessDay?> lastClosed({DateTime? before}) async => null;

  @override
  Future<DayCloseCheck> check() async =>
      DayCloseCheck(day: _day, blockers: blockers);

  @override
  Future<BusinessDay> open({
    required DateTime date,
    required PosStaff by,
  }) async => _day;

  @override
  Future<BusinessDay> close({
    required BusinessDay day,
    required PosStaff by,
    bool force = false,
    String? forceReason,
  }) async {
    closedBy.add(by.id);
    return _day;
  }
}

class _Reasons implements ReasonsRepository {
  const _Reasons();

  @override
  Future<List<ReasonCode>> forScope(ReasonScope scope) async {
    final list = SystemReasons.seededFor(scope);
    return [
      for (var i = 0; i < list.length; i++)
        ReasonCode(
          id: i + 1,
          scope: scope,
          code: list[i].code,
          nameEn: list[i].nameEn,
          nameAr: list[i].nameAr,
          sortOrder: i + 1,
        ),
    ];
  }
}

class _NobodyAtTill extends SignedInStaffController {
  @override
  PosStaff? build() => null;
}

class _AdminIn extends AdminSessionController {
  _AdminIn(this.staff);

  final PosStaff staff;

  @override
  AdminSession? build() =>
      AdminSession(staff: staff, startedAt: DateTime(2026, 9, 8));
}

class _SignedIn extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 4,
    name: 'Nour Adel',
    capabilities: {
      PosCapability.operate,
      PosCapability.cashMovement,
      PosCapability.dayClose,
      PosCapability.dayForceClose,
    },
  );
}
