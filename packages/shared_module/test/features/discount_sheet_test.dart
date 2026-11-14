import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/discount.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/reason_code.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/features/sale/widgets/discount_sheet.dart';

/// The discount sheet — the first screen in this product where a cashier can
/// change what a customer pays.
///
/// The engine's arithmetic is pinned elsewhere. What is asserted here is the
/// wiring: that the ceiling is actually consulted, that exceeding it summons a
/// manager rather than dead-ending, and that the approver's name and id end up
/// on the record rather than being lost between the dialog and the ticket.
void main() {
  const cashier = PosStaff(
    id: 4,
    name: 'Nour Adel',
    capabilities: {PosCapability.operate, PosCapability.discountApply},
  );
  const supervisor = PosStaff(
    id: 9,
    name: 'Hana Mostafa',
    capabilities: {PosCapability.discountApply},
  );

  const burger = Product(
    id: 101,
    categoryId: 11,
    nameEn: 'Classic Burger',
    price: Money(10000),
  );

  Ticket ticket() => Ticket(
    id: 'txn-1',
    orderType: OrderType.takeaway,
    // No service charge, so the arithmetic in these assertions is the discount
    // and the VAT and nothing else.
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
    lines: [TicketLine(product: burger, quantity: 1)],
  );

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

  /// Opens the sheet and hands back a getter for the ticket it returned.
  Future<Ticket? Function()> open(
    WidgetTester tester, {
    List<Discount> offered = const [],
    DiscountLimit limit = DiscountLimit.unlimited,
    DiscountLimit approverLimit = DiscountLimit.unlimited,
    PosStaff? preApprovedBy,
    Ticket? on,
    String locale = 'en',
  }) async {
    Ticket? result;
    var returned = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discountsRepositoryProvider.overrideWithValue(
            _Discounts(
              offered,
              limit,
              approverId: supervisor.id,
              approverLimit: approverLimit,
            ),
          ),
          reasonsRepositoryProvider.overrideWithValue(const _Reasons()),
          staffDirectoryRepositoryProvider.overrideWithValue(
            _Directory({'9999': supervisor}),
          ),
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
                  result = await DiscountSheet.show(
                    context,
                    ticket: on ?? ticket(),
                    preApprovedBy: preApprovedBy,
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
      expect(returned, isTrue, reason: 'the sheet has not closed yet');
      return result;
    };
  }

  Discount percentage(int bp, {String name = 'Ten off', int id = 1}) =>
      Discount(
        id: id,
        code: 'pct$id',
        nameEn: name,
        kind: DiscountKind.percentage,
        scope: DiscountScope.order,
        valueBp: bp,
      );

  bool isOpen() => find.byType(DiscountSheet).evaluate().isNotEmpty;

  Future<void> typeAmount(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField), value);
    await tester.pumpAndSettle();
  }

  group('what is offered', () {
    testWidgets('lists the live discounts with what each comes to', (
      tester,
    ) async {
      await open(tester, offered: [percentage(1000)]);

      expect(find.text('Ten off'), findsOneWidget);
      // Priced against this ticket, not shown as an abstract rate — the number
      // a cashier is deciding about is the one that comes off.
      expect(find.text('10.00 EGP'), findsWidgets);
    });

    testWidgets('says so plainly when nothing is configured', (tester) async {
      await open(tester);

      // Not an empty box. A business with no promotions is a normal
      // business, and a cashier can still type one.
      expect(
        find.textContaining('No discounts are configured'),
        findsOneWidget,
      );
    });

    testWidgets('hides a discount that is not on offer today', (tester) async {
      await open(
        tester,
        offered: [
          Discount(
            id: 2,
            code: 'expired',
            nameEn: 'Last summer',
            kind: DiscountKind.percentage,
            scope: DiscountScope.order,
            valueBp: 1000,
            endsAt: DateTime(2020),
          ),
        ],
      );

      // A list showing expired promotions would make the cashier the one who
      // has to know which are live.
      expect(find.text('Last summer'), findsNothing);
    });

    testWidgets('hides one that does not cover this order type', (
      tester,
    ) async {
      await open(
        tester,
        offered: [
          Discount(
            id: 3,
            code: 'dinein',
            nameEn: 'Dine-in only',
            kind: DiscountKind.percentage,
            scope: DiscountScope.order,
            valueBp: 1000,
            targets: const DiscountTargets(orderTypes: {OrderType.dineIn}),
          ),
        ],
      );

      // The ticket is takeaway.
      expect(find.text('Dine-in only'), findsNothing);
    });
  });

  group('applying', () {
    testWidgets('a preset comes off the bill', (tester) async {
      final result = await open(tester, offered: [percentage(1000)]);

      await tester.tap(find.text('Ten off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      final updated = result()!;
      expect(updated.totals.discount.minor, 1000);
      expect(updated.totals.total.minor, 9000);
      expect(updated.discounts.single.nameSnapshot, 'Ten off');
      expect(updated.discounts.single.discountId, 1);
    });

    testWidgets('a typed percentage comes off too', (tester) async {
      final result = await open(tester);

      await typeAmount(tester, '25');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      final updated = result()!;
      expect(updated.totals.discount.minor, 2500);
      // No configuration behind it, so nothing to point at.
      expect(updated.discounts.single.discountId, isNull);
    });

    testWidgets('a typed cash amount comes off', (tester) async {
      final result = await open(tester);

      await tester.tap(find.text('Amount'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '15');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      expect(result()!.totals.discount.minor, 1500);
    });

    testWidgets('records who applied it', (tester) async {
      final result = await open(tester);

      await typeAmount(tester, '10');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      // Not looked up at settlement, which would name whoever is standing there
      // when the bill is paid.
      expect(result()!.discounts.single.appliedByStaffId, cashier.id);
    });

    testWidgets('the apply button is muted until something is chosen', (
      tester,
    ) async {
      await open(tester, offered: [percentage(1000)]);

      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();
      expect(isOpen(), isTrue);

      await tester.tap(find.text('Ten off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();
      expect(isOpen(), isFalse);
    });

    testWidgets('typing clears a chosen preset, and vice versa', (
      tester,
    ) async {
      final result = await open(tester, offered: [percentage(1000)]);

      await tester.tap(find.text('Ten off'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '30');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      // One or the other, never both quietly combined.
      final updated = result()!;
      expect(updated.discounts, hasLength(1));
      expect(updated.totals.discount.minor, 3000);
    });

    testWidgets('Esc leaves the ticket alone', (tester) async {
      final result = await open(tester, offered: [percentage(1000)]);

      await tester.tap(find.text('Ten off'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(result(), isNull);
    });
  });

  group('the live total', () {
    testWidgets('shows what the bill becomes before anything is committed', (
      tester,
    ) async {
      await open(tester, offered: [percentage(2500)]);

      // Undiscounted to begin with.
      expect(find.text('100.00 EGP'), findsWidgets);

      await tester.tap(find.text('Ten off'));
      await tester.pumpAndSettle();

      // The number the customer will be told, before the cashier commits.
      expect(find.text('75.00 EGP'), findsOneWidget);
      expect(find.text('-25.00 EGP'), findsOneWidget);
    });
  });

  group('the ceiling', () {
    testWidgets('a discount within the limit needs nobody', (tester) async {
      final result = await open(
        tester,
        limit: const DiscountLimit(maxBp: 1000),
      );

      await typeAmount(tester, '10');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      expect(result()!.discounts.single.wasApproved, isFalse);
    });

    testWidgets('above the limit summons a manager rather than refusing', (
      tester,
    ) async {
      await open(tester, limit: const DiscountLimit(maxBp: 1000));

      await typeAmount(tester, '30');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      // Not a dead end: the sheet stays open behind a prompt naming both
      // figures, so the supervisor can decide without asking two questions.
      expect(find.text('APPROVAL REQUIRED'), findsOneWidget);
      expect(
        find.textContaining('The manual discount limit here is 10%'),
        findsOneWidget,
      );
      expect(find.textContaining('This discount is 30%'), findsOneWidget);
    });

    testWidgets('an approved discount carries both the name and the id', (
      tester,
    ) async {
      final result = await open(
        tester,
        limit: const DiscountLimit(maxBp: 1000),
      );

      await typeAmount(tester, '30');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      for (final digit in '9999'.split('')) {
        await tester.tap(find.widgetWithText(InkWell, digit).first);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply discount').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final applied = result()!.discounts.single;
      expect(applied.amount.minor, 3000, reason: 'the full 30% went through');
      // The name survives that person being renamed; the id is what a report
      // joins on. Neither is redundant.
      expect(applied.approvedByName, 'Hana Mostafa');
      expect(applied.approvedByStaffId, supervisor.id);
      expect(applied.reasonId, isNotNull);
    });

    testWidgets('declining the approval leaves the ticket untouched', (
      tester,
    ) async {
      await open(tester, limit: const DiscountLimit(maxBp: 1000));

      await typeAmount(tester, '30');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Back in the sheet, nothing applied — and still open, so the cashier can
      // try a smaller figure without starting again.
      expect(isOpen(), isTrue);
    });

    testWidgets('a pre-approved person is not asked twice', (tester) async {
      final result = await open(
        tester,
        limit: const DiscountLimit(maxBp: 1000),
        preApprovedBy: supervisor,
      );

      await typeAmount(tester, '30');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      // A manager who just approved the act must not be called back to approve
      // the amount as well, with a customer standing there.
      expect(find.text('APPROVAL REQUIRED'), findsNothing);
      final applied = result()!.discounts.single;
      expect(applied.amount.minor, 3000);
      expect(applied.approvedByStaffId, supervisor.id);
    });

    testWidgets('an approval goes no further than the approver\'s own ceiling', (
      tester,
    ) async {
      // It used to retry with no ceiling at all. A supervisor capped at 20%
      // then approved 30% by standing beside a cashier capped at 10% — the
      // approval was wider than the authority of the person who gave it.
      await open(
        tester,
        limit: const DiscountLimit(maxBp: 1000),
        approverLimit: const DiscountLimit(maxBp: 2000),
      );

      await typeAmount(tester, '30');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      for (final digit in '9999'.split('')) {
        await tester.tap(find.widgetWithText(InkWell, digit).first);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrong item made'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply discount').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Still open, nothing applied: the cashier can try a smaller figure, or
      // find somebody who may give more.
      expect(isOpen(), isTrue);
    });
  });

  group('refusals a cashier can act on', () {
    testWidgets('a discount already here says so', (tester) async {
      var seeded = ticket();
      seeded = seeded.copyWith(
        discounts: [
          const AppliedDiscount(
            nameSnapshot: 'Earlier',
            kind: DiscountKind.fixed,
            amount: Money(500),
            appliedByStaffId: 4,
          ),
        ],
      );

      await open(tester, on: seeded);
      await typeAmount(tester, '10');
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('There is already a discount here'),
        findsOneWidget,
      );
    });

    testWidgets('removing an existing one is offered instead of Cancel', (
      tester,
    ) async {
      var seeded = ticket();
      seeded = seeded.copyWith(
        discounts: [
          const AppliedDiscount(
            nameSnapshot: 'Earlier',
            kind: DiscountKind.fixed,
            amount: Money(500),
            appliedByStaffId: 4,
          ),
        ],
      );

      final result = await open(tester, on: seeded);
      expect(find.text('Remove discount'), findsOneWidget);

      await tester.tap(find.text('Remove discount'));
      await tester.pumpAndSettle();

      expect(result()!.discounts, isEmpty);
      expect(result()!.totals.total.minor, 10000);
    });
  });

  group('Arabic', () {
    testWidgets('the sheet follows the locale', (tester) async {
      await open(tester, locale: 'ar');

      expect(find.text('خصم'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('خصم'))),
        TextDirection.rtl,
      );
    });
  });
}

/// Each person's own ceiling, as the real repository answers it.
///
/// This used to hand everybody the same limit, which was harmless while an
/// approval retried with no ceiling at all. It retries under the APPROVER'S
/// ceiling now, and a fake that gave the supervisor the cashier's 10% would
/// test a business where nobody can approve anything.
class _Discounts implements DiscountsRepository {
  const _Discounts(
    this._offered,
    this._limit, {
    required this.approverId,
    this.approverLimit = DiscountLimit.unlimited,
  });

  final List<Discount> _offered;
  final DiscountLimit _limit;
  final int approverId;
  final DiscountLimit approverLimit;

  @override
  Future<List<Discount>> all() async => _offered;

  @override
  Future<DiscountLimit> limitFor(PosStaff? staff) async =>
      staff?.id == approverId ? approverLimit : _limit;
}

class _Reasons implements ReasonsRepository {
  const _Reasons();

  @override
  Future<List<ReasonCode>> forScope(ReasonScope scope) async => [
    for (var i = 0; i < 4; i++)
      ReasonCode(
        id: i + 1,
        scope: scope,
        code: SystemReasons.seeded[i].code,
        nameEn: SystemReasons.seeded[i].nameEn,
        nameAr: SystemReasons.seeded[i].nameAr,
        sortOrder: i + 1,
      ),
  ];
}

class _SignedIn extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 4,
    name: 'Nour Adel',
    capabilities: {PosCapability.operate, PosCapability.discountApply},
  );
}

class _Directory implements StaffDirectoryRepository {
  const _Directory(this._pins);

  final Map<String, PosStaff> _pins;

  @override
  Future<PosStaff?> byPin(String pin) async => _pins[pin];

  @override
  Future<List<PosStaff>> all({bool includeInactive = true}) async =>
      _pins.values.toList();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
