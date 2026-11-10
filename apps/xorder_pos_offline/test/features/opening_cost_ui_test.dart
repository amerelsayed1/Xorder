import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/stock_level.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/domain/services/stock_costing.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_stock_pane.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

/// Giving an uncosted item its first cost, from the Stock pane.
///
/// The rules are `opening_cost_test.dart`'s and the ledger's are
/// `test/data/opening_cost_test.dart`'s. What is pinned here is the person's
/// side of it: the button is only where it can do something and only for
/// somebody who may press it, the dialog says what it will not do before it
/// asks for a number, a bad number is answered in words without calling the
/// repository, and a refusal is shown rather than swallowed.
void main() {
  setUpAll(loadPosFonts);

  const s = EnStrings();

  const manager = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.purchaseManage},
    ),
  );
  const viewer = PosStaff(
    id: 2,
    name: 'Rana A.',
    role: PosRole(
      id: 2,
      code: 'viewer',
      nameEn: 'Viewer',
      capabilities: {PosCapability.catalogView},
    ),
  );

  const cola = StockLevel(
    productId: 1,
    nameEn: 'Cola',
    onHand: Quantity(48000),
    unitCost: Money(500),
  );
  const ketchup = StockLevel(
    productId: 2,
    nameEn: 'Ketchup',
    onHand: Quantity(6000),
    unitCost: Money.zero,
  );
  const mayo = StockLevel(
    productId: 3,
    nameEn: 'Mayo',
    onHand: Quantity(2000),
    unitCost: Money.zero,
  );

  Future<_Receiving> pump(
    WidgetTester tester, {
    List<StockLevel> levels = const [cola, ketchup, mayo],
    PosStaff admin = manager,
    _Receiving? receiving,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = receiving ?? _Receiving();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(),
          stockLevelsProvider.overrideWith((ref) async => levels),
          receivingRepositoryProvider.overrideWithValue(repository),
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
          home: Scaffold(body: ManagementStockPane(admin: admin)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('opening-cost-field')), text);
    await tester.pump();
  }

  group('where the button is', () {
    testWidgets('on each uncosted row, and not on a costed one', (tester) async {
      await pump(tester);

      expect(find.byKey(const Key('stock-set-cost-2')), findsOneWidget);
      expect(find.byKey(const Key('stock-set-cost-3')), findsOneWidget);
      expect(find.byKey(const Key('stock-set-cost-1')), findsNothing);
    });

    testWidgets('nowhere when every item is costed', (tester) async {
      await pump(tester, levels: const [cola]);

      expect(find.text(s.stockSetCost), findsNothing);
    });

    testWidgets('not for somebody who may not give a cost', (tester) async {
      await pump(tester, admin: viewer);

      expect(find.text(s.stockSetCost), findsNothing);
      // They still see the dash and the tag: what is true is not hidden.
      expect(find.byKey(const Key('stock-no-cost-2')), findsOneWidget);
    });

    testWidgets('every row reserves the button\'s room, so columns stay put', (
      tester,
    ) async {
      await pump(tester);

      Finder slot(String row) => find.descendant(
        of: find.byKey(Key(row)),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 112,
        ),
      );

      // The costed Cola has no button and the room for one all the same.
      expect(slot('stock-row-1'), findsOneWidget);
      expect(slot('stock-row-2'), findsOneWidget);
      expect(slot('stock-row-3'), findsOneWidget);
    });

    testWidgets('and none reserve it where no row has a button', (tester) async {
      await pump(tester, levels: const [cola]);

      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 112),
        findsNothing,
      );
    });
  });

  group('the dialog', () {
    testWidgets('names the item and what it holds', (tester) async {
      await pump(tester);

      await tapKey(tester, 'stock-set-cost-2');

      expect(find.text(s.stockOpeningCostTitle('Ketchup')), findsOneWidget);
      expect(find.textContaining('6'), findsWidgets);
    });

    testWidgets('says what it will not do, before asking for a number', (
      tester,
    ) async {
      await pump(tester);

      await tapKey(tester, 'stock-set-cost-2');

      // Past sales stay uncosted and the quantity is untouched — said up front.
      expect(find.text(s.stockOpeningCostHint), findsOneWidget);
      expect(s.stockOpeningCostHint, contains('already made stay uncosted'));
      expect(s.stockOpeningCostHint, contains('quantity is not changed'));
    });

    testWidgets('cancel calls nothing', (tester) async {
      final repository = await pump(tester);

      await tapKey(tester, 'stock-set-cost-2');
      await enter(tester, '3.50');
      await tester.tap(find.text(s.cancel));
      await tester.pumpAndSettle();

      expect(repository.calls, isEmpty);
      expect(find.byKey(const Key('opening-cost-field')), findsNothing);
    });
  });

  group('saving', () {
    testWidgets('a typed cost becomes minor units, for that item', (
      tester,
    ) async {
      final repository = await pump(tester);

      await tapKey(tester, 'stock-set-cost-2');
      // Through Money.tryParse: 3.50 is 350, never 349.99….
      await enter(tester, '3.50');
      await tapKey(tester, 'opening-cost-save');

      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.productId, 2);
      expect(repository.calls.single.unitCost.minor, 350);
      expect(repository.calls.single.by, manager);
      expect(find.byKey(const Key('opening-cost-field')), findsNothing);
    });

    testWidgets('the list is read again, so the cost shows', (tester) async {
      await pump(tester);
      var reads = 0;
      // A second pump with a counting provider is the honest way to see the
      // invalidation: the first read happened above, and saving must cause one
      // more.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ManagementStockPane)),
      );
      container.listen(stockLevelsProvider, (_, _) => reads++);

      await tapKey(tester, 'stock-set-cost-2');
      await enter(tester, '3.50');
      await tapKey(tester, 'opening-cost-save');

      expect(reads, greaterThan(0));
    });

    testWidgets('a number that is not a number is answered, not sent', (
      tester,
    ) async {
      final repository = await pump(tester);

      await tapKey(tester, 'stock-set-cost-2');
      await enter(tester, 'three');
      await tapKey(tester, 'opening-cost-save');

      expect(find.byKey(const Key('opening-cost-problem')), findsOneWidget);
      expect(find.text(s.priceIsNotANumber), findsOneWidget);
      expect(repository.calls, isEmpty);
      expect(find.byKey(const Key('opening-cost-field')), findsOneWidget);
    });

    testWidgets('zero is refused in words, not sent', (tester) async {
      final repository = await pump(tester);

      await tapKey(tester, 'stock-set-cost-2');
      await enter(tester, '0');
      await tapKey(tester, 'opening-cost-save');

      expect(find.text(s.refusalOpeningCostNotPositive), findsOneWidget);
      expect(repository.calls, isEmpty);
    });

    testWidgets('typing again clears the message', (tester) async {
      await pump(tester);

      await tapKey(tester, 'stock-set-cost-2');
      await enter(tester, 'x');
      await tapKey(tester, 'opening-cost-save');
      expect(find.byKey(const Key('opening-cost-problem')), findsOneWidget);

      await enter(tester, '3');
      expect(find.byKey(const Key('opening-cost-problem')), findsNothing);
    });
  });

  group('when the repository refuses', () {
    testWidgets('the reason is shown, in words', (tester) async {
      final repository = _Receiving()
        ..refuse = const OpeningCostRefused(OpeningCostProblem.alreadyCosted);
      await pump(tester, receiving: repository);

      await tapKey(tester, 'stock-set-cost-2');
      await enter(tester, '3.50');
      await tapKey(tester, 'opening-cost-save');

      expect(find.text(s.refusalOpeningCostAlreadyCosted), findsOneWidget);
    });

    testWidgets('a permission refusal reads as one', (tester) async {
      final repository = _Receiving()
        ..refuse = const NotPermitted(PosCapability.purchaseManage);
      await pump(tester, receiving: repository);

      await tapKey(tester, 'stock-set-cost-2');
      await enter(tester, '3.50');
      await tapKey(tester, 'opening-cost-save');

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  testWidgets('in Arabic the button and the dialog are in Arabic', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(english: false),
          stockLevelsProvider.overrideWith(
            (ref) async => const [cola, ketchup],
          ),
          receivingRepositoryProvider.overrideWithValue(_Receiving()),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ManagementStockPane(admin: manager)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const ar = ArStrings();
    expect(find.text(ar.stockSetCost), findsOneWidget);
    await tester.tap(find.byKey(const Key('stock-set-cost-2')));
    await tester.pumpAndSettle();
    expect(find.text(ar.stockOpeningCostHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// A receiving repository that can be LOOKED at: what was asked of it. Only the
/// method this pane calls is answered; the rest fail loudly.
class _Receiving implements ReceivingRepository {
  final calls = <({int productId, Money unitCost, PosStaff by})>[];

  /// When set, the next call is refused with this.
  AdminRefusal? refuse;

  @override
  Future<AdminResult<StockPosition>> setOpeningCost({
    required int productId,
    required Money unitCost,
    required PosStaff by,
    String? note,
  }) async {
    final refusal = refuse;
    if (refusal != null) return AdminResult.refused(refusal);
    calls.add((productId: productId, unitCost: unitCost, by: by));
    return AdminResult.done(
      StockPosition(onHand: const Quantity(6000), unitCost: unitCost),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
