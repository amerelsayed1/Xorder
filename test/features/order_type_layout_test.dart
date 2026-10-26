import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import '../support/fakes.dart';

/// XORD-002 — the sale screen adapts to how many order types are sold.
void main() {
  Future<void> pumpWith(WidgetTester tester, List<OrderType> offered) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(),
          branchOrderTypesProvider.overrideWithValue(offered),
        ],
        child: MaterialApp(
          theme: buildPosTheme(),
          home: SaleScreen(
            onLock: () {},
            onTables: () {},
            onOrders: () {},
            onCloseShift: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one type: a label, not a switch with one segment', (tester) async {
    await pumpWith(tester, [OrderType.takeaway]);

    expect(find.byKey(const Key('order-type-single')), findsOneWidget);
    expect(find.byKey(const Key('order-type-switch')), findsNothing);
  });

  testWidgets('two or more: the switch, with exactly those segments', (tester) async {
    await pumpWith(tester, [OrderType.dineIn, OrderType.delivery]);

    expect(find.byKey(const Key('order-type-switch')), findsOneWidget);
    expect(find.byKey(const Key('order-type-single')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('order-type-switch')),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('all four: all four segments', (tester) async {
    await pumpWith(tester, OrderType.values);

    expect(
      find.descendant(
        of: find.byKey(const Key('order-type-switch')),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(4),
    );
  });
}
