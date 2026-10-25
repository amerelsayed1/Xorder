import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/stock_level.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// Stock on hand: how much of each counted item is here, and its worth.
void main() {
  // The bundled faces, not the test font's, so what fits here is what a till
  // shows (see `loadPosFonts`).
  setUpAll(loadPosFonts);

  Future<void> open(
    WidgetTester tester, {
    List<StockLevel>? levels,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Offline: on a cloud till the platform authors stock (CB-09).
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        offlineTerminal(),
        if (levels != null) stockLevelsProvider.overrideWith((ref) async => levels),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          home: ManagementScreen(
            onClose: () {},
            onReconfigure: () {},
            initialPane: ManagementPane.stock,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterAdminMode(tester);
  }

  test('it lives in Inventory, beside the units', () {
    expect(tabOf(ManagementPane.stock), BackOfficeTab.inventory);
    expect(tabOf(ManagementPane.units), BackOfficeTab.inventory);
  });

  testWidgets('each item on hand in its unit, and the whole worth', (
    tester,
  ) async {
    await open(tester);

    // By the name the restaurant gave the unit, not its code.
    expect(find.text('12.5 Kilogram'), findsOneWidget);
    expect(find.text('48 Each'), findsOneWidget);
    // 12.5 × 95.00 + (−2 × 60.00) + 48 × 5.00 = 1307.50
    expect(
      find.text('Stock value: ${const Money(130750).format(withCurrency: true)}'),
      findsOneWidget,
    );
  });

  testWidgets('below zero is shown as a problem, not hidden', (tester) async {
    // Sold what never arrived, as far as the system knows. Clamping at zero
    // would hide the one line somebody needs to look at.
    await open(tester);
    final short = tester.widget<Text>(find.text('-2 Litre'));
    expect(short.style?.color, PosPalette.light.danger);
  });

  group('an item nothing has set a cost for', () {
    // Cola was bought; Ketchup was set up and never received. A cost of zero
    // is how that looks on the ledger, and the profit report already reads it
    // as "not costed" — the page must not call it 0.00.
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

    test('hasCost is whether the average is above zero', () {
      expect(cola.hasCost, isTrue);
      expect(ketchup.hasCost, isFalse);
    });

    testWidgets('is a dash and a tag, not a price of nothing', (tester) async {
      await open(tester, levels: [cola, ketchup]);

      expect(find.byKey(const Key('stock-no-cost-2')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('stock-no-cost-2')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('stock-no-cost-2')),
          matching: find.text(const EnStrings().profitNoCostTag),
        ),
        findsOneWidget,
      );
    });

    testWidgets('and a costed item beside it is unchanged', (tester) async {
      await open(tester, levels: [cola, ketchup]);

      expect(find.byKey(const Key('stock-no-cost-1')), findsNothing);
      // Its average cost, as before.
      expect(
        find.descendant(
          of: find.byKey(const Key('stock-row-1')),
          matching: find.text(const Money(500).format(withCurrency: true)),
        ),
        findsWidgets,
      );
    });

    testWidgets('the page says once what the tag means', (tester) async {
      await open(tester, levels: [cola, ketchup]);

      expect(find.byKey(const Key('stock-no-cost-note')), findsOneWidget);
      expect(find.text(const EnStrings().stockNoCostNote), findsOneWidget);
    });

    testWidgets('the total is of what is costed, and says what it leaves out', (
      tester,
    ) async {
      await open(tester, levels: [cola, ketchup]);

      // 48 × 5.00 for the Cola. The Ketchup is not added as nothing: its worth
      // is unknown, and the line under the total says so.
      expect(
        find.text('Stock value: ${const Money(24000).format(withCurrency: true)}'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stock-unvalued')), findsOneWidget);
      expect(
        find.text(const EnStrings().stockExcludesUncosted(1)),
        findsOneWidget,
      );
    });

    testWidgets('an uncosted row\'s value is a dash, a costed row\'s is its '
        'worth', (tester) async {
      await open(tester, levels: [cola, ketchup]);

      // Unknown, not 0.00 — which would say it had been counted.
      expect(
        find.descendant(
          of: find.byKey(const Key('stock-row-2')),
          matching: find.text(Money.zero.format()),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('stock-row-1')),
          matching: find.text(const Money(24000).format(withCurrency: true)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('with nothing on hand there is nothing to leave out', (
      tester,
    ) async {
      await open(
        tester,
        levels: [
          cola,
          const StockLevel(
            productId: 3,
            nameEn: 'Mayo',
            onHand: Quantity(0),
            unitCost: Money.zero,
          ),
        ],
      );

      expect(find.byKey(const Key('stock-unvalued')), findsNothing);
    });

    testWidgets('with every item costed there is no note and no tag', (
      tester,
    ) async {
      await open(tester);

      expect(find.byKey(const Key('stock-no-cost-note')), findsNothing);
      expect(find.byKey(const Key('stock-unvalued')), findsNothing);
      expect(find.text(const EnStrings().profitNoCostTag), findsNothing);
    });
  });
}
