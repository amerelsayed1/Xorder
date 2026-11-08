import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/presentation/management_purchasing_pane.dart';
import 'package:xorder_pos/features/admin/presentation/supplier_dialog.dart';

import '../support/fakes.dart';

/// Buying, reached from the window's bar.
///
/// Under المشتريات the bar lists what buying actually is — orders, invoices,
/// payments, suppliers — with the "new" that starts each, rather than one word
/// that opens a screen and makes you find them again. That only works if the
/// pane does what the menu said: open on the half that was named, and — for a
/// "new" — open the form, not the list with the button on it.
void main() {
  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    username: 'amer',
    role: PosRole(
      id: 1,
      code: 'owner',
      nameEn: 'Owner',
      capabilities: SystemRoles.owner,
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    required PurchasingTab tab,
    bool create = false,
    Object? request,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeRepositoryOverrides(),
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Scaffold(
            body: ManagementPurchasingPane(
              admin: owner,
              initialTab: tab,
              create: create,
              request: request,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The "new" button names the half it creates in, so it says which half is
  /// open without leaning on the tab's colour.
  String newButton(WidgetTester tester) =>
      tester.widget<PosButton>(find.byKey(const Key('purchasing-new'))).label;

  testWidgets('opens on the half it was asked for', (tester) async {
    await pump(tester, tab: PurchasingTab.suppliers);

    expect(newButton(tester), 'New supplier');
    expect(
      find.byType(SupplierDialog),
      findsNothing,
      reason: 'the list, not the form, unless a new one was asked for',
    );
  });

  testWidgets('"New supplier" opens the form, not the list', (tester) async {
    await pump(
      tester,
      tab: PurchasingTab.suppliers,
      create: true,
      request: Object(),
    );

    expect(find.byType(SupplierDialog), findsOneWidget);
  });

  testWidgets('each request is answered exactly once', (tester) async {
    final request = Object();
    await pump(
      tester,
      tab: PurchasingTab.suppliers,
      create: true,
      request: request,
    );
    expect(find.byType(SupplierDialog), findsOneWidget);

    Navigator.of(tester.element(find.byType(SupplierDialog))).pop();
    await tester.pumpAndSettle();

    // A rebuild with the same request — the pane is still there and has seen
    // it, so `didUpdateWidget` has nothing new to follow.
    await pump(
      tester,
      tab: PurchasingTab.suppliers,
      create: true,
      request: request,
    );
    expect(find.byType(SupplierDialog), findsNothing);

    // Switching to another area and back DISPOSES the pane, and the one that
    // comes back has never seen this request — nothing on the pane itself can
    // say it was already answered. This is the path the per-request memory
    // exists for: without it, "New supplier" reopens every time somebody looks
    // at Staff and comes back.
    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      tab: PurchasingTab.suppliers,
      create: true,
      request: request,
    );
    expect(find.byType(SupplierDialog), findsNothing);

    // A new request is a new question, even for the same thing.
    await pump(
      tester,
      tab: PurchasingTab.suppliers,
      create: true,
      request: Object(),
    );
    expect(find.byType(SupplierDialog), findsOneWidget);
  });

  testWidgets('and a new request moves a pane that is already open', (
    tester,
  ) async {
    // The same bug the management screen had: a field initialised once keeps
    // showing whatever was already open. "Invoices" from the bar while looking
    // at orders has to move.
    await pump(tester, tab: PurchasingTab.orders, request: Object());
    expect(newButton(tester), 'New order');

    await pump(tester, tab: PurchasingTab.invoices, request: Object());
    expect(newButton(tester), 'Enter an invoice');
  });
}
