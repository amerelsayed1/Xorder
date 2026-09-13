import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

/// The Units pane: the list stock is counted in, and adding to it.
void main() {
  Future<ProviderContainer> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Offline: on a cloud till the platform authors units (CB-09).
    final container = ProviderContainer(
      overrides: [...fakeRepositoryOverrides(), offlineTerminal()],
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
            initialPane: ManagementPane.units,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Through the back office's door, as the owner.
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
    return container;
  }

  testWidgets('it lives in Inventory, and lists the units with their codes', (
    tester,
  ) async {
    await open(tester);

    expect(areaOf(ManagementPane.units), ManagementArea.inventory);
    expect(find.text('Kilogram'), findsOneWidget);
    expect(find.byKey(const Key('unit-row-kg')), findsOneWidget);
    // A kilo can be part of one; a box cannot.
    expect(
      find.descendant(
        of: find.byKey(const Key('unit-row-kg')),
        matching: find.text('fractions'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('unit-row-box')),
        matching: find.text('fractions'),
      ),
      findsNothing,
    );
  });

  testWidgets('a unit is added by name, and gets a code from it', (
    tester,
  ) async {
    final container = await open(tester);

    await tester.tap(find.byKey(const Key('unit-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('unit-name')), 'Tray of 30');
    await tester.enterText(find.byKey(const Key('unit-name_ar')), 'طبق');
    await tester.tap(find.byKey(const Key('unit-save')));
    await tester.pumpAndSettle();

    final fake = container.read(unitsRepositoryProvider) as FakeUnitsRepository;
    expect([for (final u in fake.units) u.code], contains('tray_of_30'));
    expect(find.byKey(const Key('unit-row-tray_of_30')), findsOneWidget);
  });
}
