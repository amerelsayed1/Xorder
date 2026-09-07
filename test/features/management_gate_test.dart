import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

/// The door to the back office.
///
/// The screen is one PIN away from a cashier on a shared machine, so what it
/// refuses matters more than what it shows. These tests drive the real widgets
/// against fakes that apply the real permission rules — the point is to catch a
/// screen that offers an action the data layer would reject, or worse, one that
/// opens for somebody it should not.
void main() {
  Future<ProviderContainer> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: ManagementScreen(onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> enter(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.widgetWithText(InkWell, digit).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('asks for the back-office password before it opens', (
    tester,
  ) async {
    // The till credential holds SELECT and nothing more, on purpose. Without
    // an administrator password nothing on this screen could save, so it asks
    // BEFORE showing panes rather than letting a manager type a whole staff
    // record and then refusing it.
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        // Back to the real, unsupplied credential — the shared harness starts
        // past this gate so every other test need not type through it.
        adminDbCredentialProvider,
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: ManagementScreen(onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enter(tester, '1234'); // Amer, the owner.

    expect(find.text('Back office password'), findsOneWidget);
    // And none of the panes are reachable behind it.
    expect(find.text('Staff'), findsNothing);
    expect(find.text('Roles'), findsNothing);
  });

  testWidgets('opens for somebody who may manage staff', (tester) async {
    final container = await open(tester);
    expect(find.text('Staff'), findsNothing, reason: 'locked until a PIN is entered');

    await enter(tester, '1234'); // Amer, the owner.

    expect(find.text('Management'), findsWidgets);
    expect(find.text('Amer M.'), findsWidgets);
    expect(find.text('Rana A.'), findsOneWidget);
    expect(container.read(signedInStaffProvider)!.name, 'Amer M.');
  });

  testWidgets('a cashier PIN gets no further than the keypad', (tester) async {
    final container = await open(tester);

    await enter(tester, '5678'); // Rana, a cashier.

    expect(find.text('That PIN cannot open Management.'), findsOneWidget);
    expect(find.text('Rana A.'), findsNothing, reason: 'the staff list must not render');
    expect(
      container.read(signedInStaffProvider),
      isNull,
      reason: 'a refused PIN must not sign anybody in',
    );
  });

  testWidgets('an unknown PIN is refused in the same words as a cashier', (tester) async {
    // Identical messages on purpose. Telling them apart would turn the keypad
    // into a way of finding out who the managers are.
    await open(tester);
    await enter(tester, '0000');
    expect(find.text('That PIN cannot open Management.'), findsOneWidget);
  });

  testWidgets('the roles pane refuses to make a cashier an administrator',
      (tester) async {
    await open(tester);
    await enter(tester, '1234');

    await tester.tap(find.text('Roles'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cashier').first);
    await tester.pumpAndSettle();

    // Scrolled to first, with `scrollUntilVisible` rather than
    // `ensureVisible`. It is the last row of the last group, so a capability
    // added to any earlier group pushes it down — and past the fold a
    // `ListView` has not built it at all, which `ensureVisible` cannot fix
    // because there is no element to scroll to. Twice now, adding capabilities
    // has made this test tap nothing and then assert a refusal that was never
    // requested.
    await tester.scrollUntilVisible(
      find.text(AdminCapabilityLabels.catalogManage),
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(AdminCapabilityLabels.catalogManage),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('A cashier role cannot include'),
      findsOneWidget,
      reason: 'the requirement is that cashiers never receive catalogue '
          'administration, and a checkbox nobody re-reads is not a control',
    );
  });

  // The ledger entry for this is asserted in `postgres_admin_test.dart`, where
  // the write and its audit row share a transaction. The fake does not write
  // one, so proving it here would prove only that the fake was written to
  // agree with the test.
  testWidgets('a permission taken off a role is saved', (tester) async {
    final container = await open(tester);
    await enter(tester, '1234');

    await tester.tap(find.text('Roles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supervisor').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AdminCapabilityLabels.orderRefund));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final roles = container.read(rolesRepositoryProvider) as FakeRolesRepository;
    final supervisor =
        roles.roles.firstWhere((r) => r.code == SystemRoles.supervisorCode);
    expect(supervisor.holds(PosCapability.orderRefund), isFalse);
  });
}

/// The labels the roles pane renders, so a test taps the same string a manager
/// reads rather than a capability name nobody sees.
abstract final class AdminCapabilityLabels {
  static const catalogManage = 'Add and change menu items and prices';
  static const orderRefund = 'Refund a sale';
}
