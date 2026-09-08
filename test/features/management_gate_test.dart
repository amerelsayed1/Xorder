import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
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
  Future<ProviderContainer> open(
    WidgetTester tester, {
    ManagementPane pane = ManagementPane.staff,
  }) async {
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
          home: ManagementScreen(onClose: () {}, initialPane: pane),
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

  testWidgets('opens on staff by default, as it always did', (tester) async {
    await open(tester);
    await enter(tester, '1234');
    expect(find.text('Add somebody'), findsOneWidget);
  });

  testWidgets('can be pointed at another pane', (tester) async {
    // The mechanism the Settings menu's "Staff & accounts" item uses. Adding a
    // cashier has always been possible, behind a menu item called "Management"
    // that does not mention accounts — and a path that exists but cannot be
    // found is, to the person looking for it, the same as one that does not.
    await open(tester, pane: ManagementPane.activity);
    await enter(tester, '1234');

    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Add somebody'), findsNothing);
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

  testWidgets('a critical permission is badged as such', (tester) async {
    // §107 on screen: somebody ticking a box can see what they are handing
    // over before they hand it over. Only medium and above are badged — a
    // badge on every row would be a badge on no row.
    await open(tester);
    await enter(tester, '1234');
    await tester.tap(find.text('Roles'));
    await tester.pumpAndSettle();

    // Above the fold: the money group's high-risk permissions.
    expect(find.text('High'), findsWidgets);
    expect(find.text('Low'), findsNothing);

    // The critical ones live in the back-office group at the bottom, so the
    // list has to build them first — `ensureVisible` cannot reach a `ListView`
    // child that was never built.
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
    expect(find.text('Critical'), findsWidgets);
  });

  testWidgets('New role offers the templates rather than an empty checklist',
      (tester) async {
    // Otherwise somebody creating an accountant ticks boxes until the screen
    // stops complaining, which is how a role ends up holding whatever made the
    // error go away.
    await open(tester);
    await enter(tester, '1234');
    await tester.tap(find.text('Roles'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('roles-new')));
    await tester.pumpAndSettle();

    expect(find.text('Accountant'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Delivery staff'), findsOneWidget);
  });

  testWidgets('picking a template creates an ordinary role', (tester) async {
    await open(tester);
    await enter(tester, '1234');
    await tester.tap(find.text('Roles'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('roles-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen'));
    await tester.pumpAndSettle();

    // It appears in the list beside the seeded ones. Nothing about it stays
    // special.
    expect(find.text('Kitchen'), findsWidgets);
  });


  testWidgets('a permission shows where it came from, in four states',
      (tester) async {
    // A checkbox would collapse "comes with the role" and "granted to this
    // person" into one tick, and "deliberately taken away" into the same blank
    // as "nobody ever gave it". Those are four different facts.
    await open(tester);
    await enter(tester, '1234');

    await tester.tap(find.byKey(const Key('grants-2')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Permissions for'), findsOneWidget);
    expect(find.text('from their role'), findsWidgets);
    expect(find.text('taken away'), findsNothing);
  });

  testWidgets('Purchasing is absent for somebody who cannot buy', (
    tester,
  ) async {
    // A supervisor who manages the rota but does not order the stock is a real
    // job. Showing them a pane whose every button refuses would make the rail
    // a list of disappointments.
    final container = await open(tester);
    await enter(tester, '1234');
    expect(find.text('Purchasing'), findsOneWidget, reason: 'the owner buys');

    container.read(signedInStaffProvider.notifier).signIn(
      const PosStaff(
        id: 9,
        name: 'Nour S.',
        username: 'nour',
        role: PosRole(
          id: 9,
          code: 'supervisor',
          nameEn: 'Supervisor',
          capabilities: {PosCapability.staffManage},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Purchasing'), findsNothing);
  });

  testWidgets('a deep link to Purchasing does not outlive the permission', (
    tester,
  ) async {
    // `initialPane` comes from a menu item somebody may have had every right to
    // use last week. The rail hiding it while the body still rendered it would
    // be the gate saying no and the screen saying yes.
    final container = await open(tester, pane: ManagementPane.purchasing);
    await enter(tester, '1234');
    expect(find.text('New order'), findsOneWidget);

    container.read(signedInStaffProvider.notifier).signIn(
      const PosStaff(
        id: 9,
        name: 'Nour S.',
        username: 'nour',
        role: PosRole(
          id: 9,
          code: 'supervisor',
          nameEn: 'Supervisor',
          capabilities: {PosCapability.staffManage},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New order'), findsNothing);
    expect(find.text('Add somebody'), findsOneWidget, reason: 'falls back');
  });

  testWidgets('tapping a role permission takes it away', (tester) async {
    await open(tester);
    await enter(tester, '1234');
    await tester.tap(find.byKey(const Key('grants-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AdminCapabilityLabels.operate));
    await tester.pumpAndSettle();

    expect(find.text('taken away'), findsOneWidget);
  });

  testWidgets('tapping it again clears the exception', (tester) async {
    // An exception has to be undoable in place, or the only way back is to
    // remember what the role said.
    await open(tester);
    await enter(tester, '1234');
    await tester.tap(find.byKey(const Key('grants-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AdminCapabilityLabels.operate));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AdminCapabilityLabels.operate));
    await tester.pumpAndSettle();

    expect(find.text('taken away'), findsNothing);
  });

}

/// The labels the roles pane renders, so a test taps the same string a manager
/// reads rather than a capability name nobody sees.
abstract final class AdminCapabilityLabels {
  static const catalogManage = 'Add and change menu items and prices';
  static const orderRefund = 'Refund a sale';
  static const operate = 'Sell at the till';

}
