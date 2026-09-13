import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

/// Stock on hand: how much of each counted item is here, and its worth.
void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
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
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('back-office-username')),
        matching: find.byType(TextField),
      ),
      'amer',
    );
    await tester.enterText(
      find.byKey(const Key('back-office-password')),
      'test-credential',
    );
    await tester.tap(find.byKey(const Key('back-office-open')));
    await tester.pumpAndSettle();
  }

  test('it lives in Inventory, beside the units', () {
    expect(areaOf(ManagementPane.stock), ManagementArea.inventory);
    expect(areaOf(ManagementPane.units), ManagementArea.inventory);
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
      find.text('Stock value: ${const Money(130750).format()}'),
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
}
