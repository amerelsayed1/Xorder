import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_activity_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_roles_pane.dart';
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

  /// The door: the administrator's username and the back-office password.
  /// The shared harness holds 'test-credential' as that password.
  Future<void> enter(
    WidgetTester tester,
    String username, {
    String password = 'test-credential',
  }) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('back-office-username')),
        matching: find.byType(TextField),
      ),
      username,
    );
    await tester.enterText(find.byKey(const Key('back-office-password')), password);
    await tester.tap(find.byKey(const Key('back-office-open')));
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

    expect(find.byKey(const Key('back-office-username')), findsOneWidget);
    expect(find.text('BACK OFFICE PASSWORD'), findsOneWidget);
    expect(find.byType(PinPad), findsNothing, reason: 'PINs are for the till');
    // And none of the panes are reachable behind it.
    expect(find.text('Staff'), findsNothing);
    expect(find.text('Roles'), findsNothing);
  });

  testWidgets('opens for somebody who may manage staff', (tester) async {
    final container = await open(tester);
    expect(find.text('Staff'), findsNothing, reason: 'locked until a PIN is entered');

    await enter(tester, 'amer'); // Amer, the owner.

    // The header names the area, now that the rail that said so is gone.
    expect(find.text('Management › People'), findsOneWidget);
    expect(find.text('Amer M.'), findsWidgets);
    expect(find.text('Rana A.'), findsOneWidget);
    expect(container.read(signedInStaffProvider)!.name, 'Amer M.');
  });

  testWidgets('a cashier gets no further than the door', (tester) async {
    final container = await open(tester);

    await enter(tester, 'rana'); // Rana, a cashier.

    expect(find.text('That username and password cannot open Management.'), findsOneWidget);
    expect(find.text('Rana A.'), findsNothing, reason: 'the staff list must not render');
    expect(
      container.read(signedInStaffProvider),
      isNull,
      reason: 'a refused PIN must not sign anybody in',
    );
  });

  testWidgets('a wrong password is refused in the same words, and opens nothing',
      (tester) async {
    final container = await open(tester);
    await enter(tester, 'amer', password: 'not-it');

    expect(
      find.text('That username and password cannot open Management.'),
      findsOneWidget,
    );
    expect(container.read(signedInStaffProvider), isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('back-office-password')))
          .controller!
          .text,
      isEmpty,
      reason: 'a refused password is not left sitting in the box',
    );
  });

  testWidgets('an unknown username is refused in the same words as a cashier', (tester) async {
    // Identical messages on purpose. Telling them apart would turn the keypad
    // into a way of finding out who the managers are.
    await open(tester);
    await enter(tester, 'nobody');
    expect(find.text('That username and password cannot open Management.'), findsOneWidget);
  });

  testWidgets('opens on staff by default, as it always did', (tester) async {
    await open(tester);
    await enter(tester, 'amer');
    expect(find.text('Add somebody'), findsOneWidget);
  });

  testWidgets('can be pointed at another pane', (tester) async {
    // The mechanism the Settings menu's "Staff & accounts" item uses. Adding a
    // cashier has always been possible, behind a menu item called "Management"
    // that does not mention accounts — and a path that exists but cannot be
    // found is, to the person looking for it, the same as one that does not.
    await open(tester, pane: ManagementPane.activity);
    await enter(tester, 'amer');

    // The pane itself. Activity is the only pane in its area, so no tab names
    // it — and the header says "System", which is where it lives.
    expect(find.byType(ManagementActivityPane), findsOneWidget);
    expect(find.text('Add somebody'), findsNothing);
  });

  testWidgets('and pointed at another pane again, from inside', (tester) async {
    // **The bug the bar found.** `go('/management', extra: pane)` rebuilds this
    // screen with a new `initialPane`, and the pane it shows was a `late` field
    // initialised once — so asking for a pane while already in the back office
    // did nothing at all. From the start screen it worked, because that built a
    // fresh screen, which is why the menu appeared to work until it was used
    // twice.
    final container = await open(tester, pane: ManagementPane.activity);
    await enter(tester, 'amer');
    // The pane itself, never its name: every pane's name is in the rail all the
    // time, so `find.text('Roles')` passes on a screen that never moved.
    expect(find.byType(ManagementActivityPane), findsOneWidget);

    // The same screen, asked for a different pane — what the menu bar does.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: ManagementScreen(
            onClose: () {},
            initialPane: ManagementPane.roles,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ManagementRolesPane), findsOneWidget);
    expect(find.byType(ManagementActivityPane), findsNothing);
  });

  testWidgets('the panes of one area are tabs, and only those', (
    tester,
  ) async {
    // The rail listed all thirteen; the window's bar does that now. What is
    // left here is only the neighbours of where you are.
    await open(tester, pane: ManagementPane.taxes);
    await enter(tester, 'amer');

    // Money's panes on this terminal. Order types is absent because the fake
    // harness authors no catalogue — the same rule the bar applies.
    for (final pane in [
      ManagementPane.taxes,
      ManagementPane.charges,
      ManagementPane.tenders,
    ]) {
      expect(
        find.byKey(Key('management-tab-${pane.name}')),
        findsOneWidget,
        reason: pane.name,
      );
    }
    expect(find.byKey(const Key('management-tab-staff')), findsNothing);
    expect(find.text('Management › Money'), findsOneWidget);
  });

  testWidgets('and a pane alone in its area gets no tab at all', (
    tester,
  ) async {
    // A single tab over a single pane is a heading dressed as a control.
    // Buying, because Purchasing is the one pane in it — System stopped being
    // the example the day Backup joined Activity there.
    await open(tester, pane: ManagementPane.purchasing);
    await enter(tester, 'amer');

    expect(find.byKey(const Key('management-tab-purchasing')), findsNothing);
    expect(find.text('Management › Buying'), findsOneWidget);
  });

  testWidgets('a tab switches the pane', (tester) async {
    await open(tester);
    await enter(tester, 'amer');

    await tester.tap(find.byKey(const Key('management-tab-roles')));
    await tester.pumpAndSettle();

    expect(find.byType(ManagementRolesPane), findsOneWidget);
  });

  testWidgets('the roles pane refuses to make a cashier an administrator',
      (tester) async {
    await open(tester);
    await enter(tester, 'amer');

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

  testWidgets('the Activity pane reads as sentences, not as wire values', (
    tester,
  ) async {
    // **It rendered `entry.action` raw.** Every row said
    // `supplier_invoice.saved`, in mono, in both languages — on the one screen
    // whose whole purpose is telling a restaurant who changed something.
    final container = await open(tester, pane: ManagementPane.activity);
    final audit =
        container.read(auditRepositoryProvider) as FakeAuditRepository;
    await audit.record(
      by: const PosStaff(id: 1, name: 'Amer M.'),
      action: AuditAction.supplierPaid,
      entityType: AuditAction.entitySupplierPayment,
      entityId: '4',
    );
    await audit.record(
      by: const PosStaff(id: 1, name: 'Amer M.'),
      // A row from a build this one has never heard of. Shown as stored rather
      // than hidden: an audit log that omits what it cannot name is an audit
      // log nobody can rely on.
      action: 'warehouse.transferred',
      entityType: 'warehouse',
    );

    await enter(tester, 'amer');
    await tester.pumpAndSettle();

    expect(find.text('Paid a supplier'), findsOneWidget);
    expect(find.text('supplier.paid'), findsNothing);
    expect(find.text('warehouse.transferred'), findsOneWidget);
  });

  testWidgets('the Activity pane prints money as money, not as piastres', (
    tester,
  ) async {
    // **`total_minor: 100000` was the bug.** A hundred thousand piastres is a
    // thousand pounds, and the column printed the integer — on an audit trail,
    // beside a supplier's name, where the whole question is how much money
    // moved. The suffix is the rule: `_minor` is money, `_milli` is a quantity
    // in thousandths, `_bp` is a rate in basis points.
    final container = await open(tester, pane: ManagementPane.activity);
    final audit =
        container.read(auditRepositoryProvider) as FakeAuditRepository;
    await audit.record(
      by: const PosStaff(id: 1, name: 'Amer M.'),
      action: AuditAction.supplierInvoiceSaved,
      entityType: AuditAction.entitySupplierInvoice,
      after: const {
        'total_minor': 100000,
        'tax_minor': 12281,
        'received_milli': 12500,
        'tax_rate_bp': 1400,
        'service_bp': 1250,
        'is_active': true,
        'number': 'INV-900',
      },
    );

    await enter(tester, 'amer');
    await tester.pumpAndSettle();

    final column = find.textContaining('total:');
    expect(column, findsOneWidget);
    final text = tester.widget<Text>(column).data!;

    expect(text, contains('total: 1,000.00'));
    expect(text, contains('tax: 122.81'));
    expect(
      text,
      contains('received: 12.5'),
      reason: 'thousandths, and the unit is not repeated in the name',
    );
    expect(text, contains('tax rate: 14%'));
    expect(
      text,
      contains('service: 12.5%'),
      reason: 'not 12.50% — a trailing zero reads as precision nobody claimed',
    );
    expect(
      text,
      contains('active: yes'),
      reason: '"is active: yes" is not a sentence',
    );
    expect(text, contains('number: INV-900'), reason: 'left alone');

    expect(text, isNot(contains('100000')));
    expect(text, isNot(contains('_minor')));
    expect(text, isNot(contains('1400')));
  });

  testWidgets('a change shows both sides, in the same units', (tester) async {
    final container = await open(tester, pane: ManagementPane.activity);
    final audit =
        container.read(auditRepositoryProvider) as FakeAuditRepository;
    await audit.record(
      by: const PosStaff(id: 1, name: 'Amer M.'),
      action: AuditAction.productRepriced,
      entityType: AuditAction.entityProduct,
      before: const {'price_minor': 4500},
      after: const {'price_minor': 5000},
    );

    await enter(tester, 'amer');
    await tester.pumpAndSettle();

    expect(find.textContaining('price: 45.00 → 50.00'), findsOneWidget);
  });

  testWidgets('purchasing is a permission an owner can grant by name', (
    tester,
  ) async {
    // **It rendered as `purchase.manage`.** `AdminText.capability` ends in a
    // fall-through so a capability from a newer build is shown rather than
    // hidden, and the effect on one from *this* build was the raw key on the
    // screen where a restaurant owner decides who may spend money.
    final container = await open(tester);
    await enter(tester, 'amer');

    await tester.tap(find.text('Roles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manager').first);
    await tester.pumpAndSettle();

    // Back-office permissions are the last group, so it has to be scrolled to
    // — which is itself worth asserting, because a raw key would be just as
    // far down and just as invisible to a test that did not look.
    final label = find.text(AdminCapabilityLabels.purchaseManage);
    await tester.scrollUntilVisible(
      label,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('purchase.manage'), findsNothing);
    expect(label, findsOneWidget);

    // And it is a real checkbox, not a label: taking it off a role is what
    // makes the Manage menu hide Purchasing from that person.
    await tester.tap(find.text(AdminCapabilityLabels.purchaseManage));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final roles = container.read(rolesRepositoryProvider) as FakeRolesRepository;
    final manager =
        roles.roles.firstWhere((r) => r.code == SystemRoles.managerCode);
    expect(manager.holds(PosCapability.purchaseManage), isFalse);
  });

  // The ledger entry for this is asserted in `postgres_admin_test.dart`, where
  // the write and its audit row share a transaction. The fake does not write
  // one, so proving it here would prove only that the fake was written to
  // agree with the test.
  testWidgets('a permission taken off a role is saved', (tester) async {
    final container = await open(tester);
    await enter(tester, 'amer');

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
    await enter(tester, 'amer');
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
    await enter(tester, 'amer');
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
    await enter(tester, 'amer');
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
    await enter(tester, 'amer');

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
    await enter(tester, 'amer');

    // Asked of the rule rather than of a rail that no longer exists. What
    // decides whether Purchasing is offered — in the window's bar, in the
    // tabs, and to a deep link — is `managementAreasFor`, so that is asked.
    bool offersPurchasing() =>
        managementAreasFor(
          admin: container.read(signedInStaffProvider)!,
          authorsItsOwnCatalogue:
              container.read(catalogAdminRepositoryProvider) != null,
        ).expand((area) => area.$2).contains(ManagementPane.purchasing);

    expect(offersPurchasing(), isTrue, reason: 'the owner buys');

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

    expect(offersPurchasing(), isFalse);
  });

  testWidgets('a deep link to Purchasing does not outlive the permission', (
    tester,
  ) async {
    // `initialPane` comes from a menu item somebody may have had every right to
    // use last week. The rail hiding it while the body still rendered it would
    // be the gate saying no and the screen saying yes.
    final container = await open(tester, pane: ManagementPane.purchasing);
    await enter(tester, 'amer');
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
    await enter(tester, 'amer');
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
    await enter(tester, 'amer');
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
  static const purchaseManage =
      'Order stock, book in deliveries and pay suppliers';

}
