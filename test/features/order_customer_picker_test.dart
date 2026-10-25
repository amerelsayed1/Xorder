import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/customer.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/payment/customer_dialog.dart';
import 'package:xorder_pos/features/sale/sale_screen.dart';

import '../support/fakes.dart';
import '../support/in_memory_customers.dart';

/// XORD-001 — choosing, or adding, who an order is for without leaving the sale.
///
/// Two permissions, kept apart on purpose. **Choosing** somebody already on file
/// needs `pos.operate` — it is part of ringing the order up. **Adding** somebody
/// new needs `customers.create`, because that writes a name and a phone number
/// into the directory every till of the restaurant shares.
const _mona = PosCustomer(id: 1, name: 'Mona Fathy', phone: '01012345678');

PosStaff _staff(String name, Set<String> capabilities) => PosStaff(
  id: 7,
  name: name,
  username: name.toLowerCase(),
  role: PosRole(
    id: 70,
    code: 'test-${name.toLowerCase()}',
    nameEn: name,
    capabilities: capabilities,
  ),
);

/// Sells and may add customers — a seeded cashier.
final _cashier = _staff('Rana', SystemRoles.cashier);

/// Sells, may choose a customer, may not add one.
final _chooserOnly = _staff('Omar', {
  ...SystemRoles.cashier.where((c) => c != PosCapability.customersCreate),
});

void main() {
  late InMemoryCustomers directory;

  Future<WidgetRef> sale(WidgetTester tester, PosStaff atTheTill) async {
    late WidgetRef captured;
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    directory = InMemoryCustomers([_mona]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeRepositoryOverrides(),
          customersRepositoryProvider.overrideWithValue(directory),
        ],
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return SaleScreen(
                onLock: () {},
                onTables: () {},
                onOrders: () {},
                onCloseShift: () {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    captured.read(signedInStaffProvider.notifier).signIn(atTheTill);
    captured.read(ticketProvider.notifier).setOrderType(OrderType.takeaway);
    await tester.tap(find.text('Soft Drink'));
    await tester.pumpAndSettle();
    return captured;
  }

  /// The dialog's own boxes — the sale screen's product search sits behind it.
  Finder dialogField(int index) => find
      .descendant(
        of: find.byType(CustomerDialog),
        matching: find.byType(TextField),
      )
      .at(index);

  Finder cartButton() => find.byKey(const Key('cart-customer'));

  testWidgets('the sale screen offers the picker, and the cart survives it', (
    tester,
  ) async {
    final ref = await sale(tester, _cashier);
    final before = ref.read(ticketProvider);
    expect(before.lines, isNotEmpty);
    expect(before.customer, isNull, reason: 'a walk-in is a valid order');

    await tester.tap(cartButton());
    await tester.pumpAndSettle();
    expect(find.text('Mona Fathy'), findsOneWidget);

    await tester.tap(find.text('Mona Fathy'));
    await tester.pumpAndSettle();

    final after = ref.read(ticketProvider);
    expect(after.customer?.name, 'Mona Fathy');
    expect(after.lines.map((l) => l.key), before.lines.map((l) => l.key));
    expect(after.orderType, before.orderType);
    expect(after.totals.total, before.totals.total);
    // The cart's own button now names who it is for.
    expect(
      find.descendant(of: cartButton(), matching: find.text('Mona Fathy')),
      findsOneWidget,
    );
  });

  testWidgets('cancelling leaves the cart and the customer as they were', (
    tester,
  ) async {
    final ref = await sale(tester, _cashier);
    final before = ref.read(ticketProvider);

    await tester.tap(cartButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(ref.read(ticketProvider), before);
  });

  testWidgets('an authorised user adds a customer and is attached to it', (
    tester,
  ) async {
    final ref = await sale(tester, _cashier);

    await tester.tap(cartButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a customer'));
    await tester.pumpAndSettle();

    await tester.enterText(dialogField(0), 'Nour Hassan');
    // Arabic digits are accepted and stored as ASCII (XORD-004).
    await tester.enterText(dialogField(1), '٠١٢١٢٣٤٥٦٧٨');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(directory.upsertedBy.single?.id, _cashier.id);
    expect(ref.read(ticketProvider).customer?.name, 'Nour Hassan');
    expect(ref.read(ticketProvider).customer?.phone, '01212345678');
    expect(ref.read(ticketProvider).lines, isNotEmpty);
  });

  testWidgets('without customers.create the add control is not drawn', (
    tester,
  ) async {
    final ref = await sale(tester, _chooserOnly);

    await tester.tap(cartButton());
    await tester.pumpAndSettle();

    expect(find.text('Add a customer'), findsNothing);
    // …but choosing somebody on file still works.
    await tester.tap(find.text('Mona Fathy'));
    await tester.pumpAndSettle();
    expect(ref.read(ticketProvider).customer?.name, 'Mona Fathy');
    expect(directory.upsertedBy, isEmpty);
  });

  testWidgets('and says why when the search finds nobody', (tester) async {
    await sale(tester, _chooserOnly);

    await tester.tap(cartButton());
    await tester.pumpAndSettle();
    await tester.enterText(dialogField(0), 'zzz');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer-create-denied')), findsOneWidget);
  });

  testWidgets('a number already on file selects that person, not a copy', (
    tester,
  ) async {
    final ref = await sale(tester, _cashier);

    await tester.tap(cartButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a customer'));
    await tester.pumpAndSettle();
    await tester.enterText(dialogField(0), 'Somebody Else');
    await tester.enterText(dialogField(1), '٠١٠١٢٣٤٥٦٧٨');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(ref.read(ticketProvider).customer?.name, 'Mona Fathy');
    expect(directory.customers, hasLength(1), reason: 'no second row');
    expect(directory.upsertedBy, isEmpty, reason: 'nothing was written');
  });
}
