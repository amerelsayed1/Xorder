import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/money/quantity.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// The Stock items pane: what the restaurant buys and counts.
void main() {
  // An offline owner's strip holds all ten of the map's words; measured in
  // the bundled faces, not the test font's (see `loadPosFonts`).
  setUpAll(loadPosFonts);

  Future<ProviderContainer> open(
    WidgetTester tester, {
    bool authorsItsOwnMenu = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        // An offline till writes its own menu, and only there does a list of
        // bought-only items belong: on a cloud till the platform rewrites
        // every product.
        catalogAdminRepositoryProvider.overrideWithValue(
          authorsItsOwnMenu ? _Admin() : null,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: ManagementScreen(
            onClose: () {},
            onReconfigure: () {},
            initialPane: ManagementPane.items,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterAdminMode(tester);
    return container;
  }

  testWidgets('lists what is counted, in its unit, and marks what is sold', (
    tester,
  ) async {
    await open(tester);

    expect(tabOf(ManagementPane.items), BackOfficeTab.inventory);
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('Kilogram'), findsOneWidget, reason: 'the unit by name');
    expect(
      find.descendant(
        of: find.byKey(const Key('item-row-103')),
        matching: find.text('On the menu'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('item-row-101')),
        matching: find.text('On the menu'),
      ),
      findsNothing,
    );
  });

  testWidgets('an item is added with the unit it is counted in', (
    tester,
  ) async {
    final container = await open(tester);

    await tester.tap(find.byKey(const Key('item-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('item-name')), 'Gas cylinder');
    await tester.tap(find.byKey(const Key('item-unit-box')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('item-save')));
    await tester.pumpAndSettle();

    final fake =
        container.read(stockItemsRepositoryProvider) as FakeStockItemsRepository;
    final gas = fake.items.firstWhere((i) => i.nameEn == 'Gas cylinder');
    expect(gas.unit, QuantityUnit.box);
    expect(gas.onMenu, isFalse, reason: 'bought, counted, not sold');
    expect(find.text('Gas cylinder'), findsOneWidget);
  });

  testWidgets('an item on the menu keeps its name here', (tester) async {
    // Its name and price are the Menu pane's; a second door to them would be a
    // reprice with none of that door's audit.
    await open(tester);

    await tester.tap(find.byKey(const Key('item-row-103')));
    await tester.pumpAndSettle();

    final name = tester.widget<TextField>(find.byKey(const Key('item-name')));
    expect(name.enabled, isFalse);
  });

  testWidgets('a cloud till has no list of bought-only items', (tester) async {
    await open(tester, authorsItsOwnMenu: false);
    expect(find.text('Chicken'), findsNothing);
  });
}

class _Admin extends Mock implements CatalogAdminRepository {}
