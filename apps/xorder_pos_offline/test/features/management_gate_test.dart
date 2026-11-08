import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:shared_module/features/admin_mode/admin_session.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_activity_pane.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_home_pane.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_roles_pane.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

/// The door to the back office.
///
/// The screen is one PIN away from a cashier on a shared machine, so what it
/// refuses matters more than what it shows. These tests drive the real widgets
/// against fakes that apply the real permission rules — the point is to catch a
/// screen that offers an action the data layer would reject, or worse, one that
/// opens for somebody it should not.
void main() {
  // The bundled faces, not the test font's, so what fits here is what a till
  // shows (see `loadPosFonts`).
  setUpAll(loadPosFonts);

  /// [offline] for the tests about Purchasing: the harness is a cloud till,
  /// and since CB-09 a cloud till has no Purchasing pane to test.
  Future<ProviderContainer> open(
    WidgetTester tester, {
    ManagementPane? pane = ManagementPane.staff,
    VoidCallback? onClose,
    Future<List<int>> Function()? schemaUpgrader,
    bool offline = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(schemaUpgrader: schemaUpgrader),
        if (offline) offlineTerminal(),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: ManagementScreen(
            onClose: onClose ?? () {},
            onReconfigure: () {},
            initialPane: pane,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// The door: a username and a password — or, the first time, the PIN and
  /// then a password chosen on the step after it (see [enterAdminMode]).
  /// Amer is the owner, and his PIN in the fake session repository is 4321;
  /// the harness keeps the back-office database password as the setup wizard
  /// would.
  Future<void> enter(
    WidgetTester tester,
    String username, {
    String pin = '4321',
  }) => enterAdminMode(tester, username: username, pin: pin);

  testWidgets('asks for a username and password before it opens', (
    tester,
  ) async {
    // Nothing of the back office renders before somebody is in — not even for
    // a till whose back-office password is kept, which is every till now.
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
          home: ManagementScreen(onClose: () {}, onReconfigure: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-username')), findsOneWidget);
    expect(find.byKey(const Key('admin-password')), findsOneWidget);
    // Typed, not tapped: a PIN pad on a back-office door is a PIN anybody
    // behind the counter can read off the screen.
    expect(find.byType(PinPad), findsNothing);
    // And none of the panes are reachable behind it.
    expect(find.text('Staff'), findsNothing);
    expect(find.text('Roles'), findsNothing);
  });

  testWidgets('opens for somebody who may manage staff', (tester) async {
    final container = await open(tester);
    expect(find.text('Staff'), findsNothing, reason: 'locked until a PIN is entered');

    await enter(tester, 'amer'); // Amer, the owner.

    // The header names the page, and only the page.
    expect(
      tester.widget<Text>(find.byKey(const Key('back-office-title'))).data,
      const EnStrings().paneStaff,
    );
    expect(find.text('Amer M.'), findsWidgets);
    expect(find.text('Rana A.'), findsOneWidget);
    expect(container.read(adminSessionProvider)!.staff.name, 'Amer M.');
    expect(
      container.read(signedInStaffProvider),
      isNull,
      reason: 'Admin Mode is not the till: nobody was signed in there',
    );
  });

  testWidgets('Esc at the door goes back, even from a field', (tester) async {
    var closed = 0;
    await open(tester, onClose: () => closed++);

    // A username and a PIN are nothing to lose: one key, not two.
    await tester.tap(find.byKey(const Key('admin-password')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('Esc goes back to the till from inside the back office', (
    tester,
  ) async {
    var closed = 0;
    await open(tester, onClose: () => closed++);
    await enter(tester, 'amer');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('but inside a field the first Esc only leaves the field', (
    tester,
  ) async {
    var closed = 0;
    // Offline: on a cloud till the platform authors units (CB-09), and the
    // screen would land on Staff with no form to type into.
    await open(
      tester,
      pane: ManagementPane.units,
      onClose: () => closed++,
      offline: true,
    );
    await enter(tester, 'amer');
    // Inline on the pane, not a dialog: the field and the binding share a route.
    await tester.tap(find.byKey(const Key('unit-new')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('unit-name')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, 0, reason: 'a reflex mid-form must not throw the form away');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('and in a dialog Esc closes the dialog, not the back office', (
    tester,
  ) async {
    var closed = 0;
    final container = await open(tester, onClose: () => closed++);
    await enter(tester, 'amer');
    // Hiring is an offline till's act; the harness starts unconfigured, which
    // reads as cloud and shuts the button.
    container
        .read(deploymentProvider.notifier)
        .apply(
          DeploymentConfig.unconfigured.copyWith(mode: DeploymentMode.offline),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add somebody'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(closed, 0);
  });

  testWidgets('the door brings the database up to date before a pane loads', (
    tester,
  ) async {
    // Nothing else upgrades an installed till: a new version met a database a
    // version behind it, and the Units pane said `relation "pos_units" does
    // not exist`.
    var upgrades = 0;
    await open(
      tester,
      schemaUpgrader: () async {
        upgrades++;
        return const [39];
      },
    );
    await enter(tester, 'amer');

    expect(upgrades, 1);
    expect(find.byKey(const Key('management-schema-notice')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('back-office-title'))).data,
      const EnStrings().paneStaff,
    );
  });

  testWidgets('an upgrade that fails is said, and the door still opens', (
    tester,
  ) async {
    await open(
      tester,
      schemaUpgrader: () async =>
          throw StateError('relation "pos_units" does not exist'),
    );
    await enter(tester, 'amer');

    // Backup is in here, so a failed upgrade must not keep anybody out.
    expect(
      tester.widget<Text>(find.byKey(const Key('back-office-title'))).data,
      const EnStrings().paneStaff,
    );
    expect(find.byKey(const Key('management-schema-notice')), findsOneWidget);
    expect(find.textContaining('pos_units'), findsOneWidget);
  });

  testWidgets('a cashier gets no further than the door', (tester) async {
    final container = await open(tester);

    await enter(tester, 'rana', pin: '1234'); // Rana, a cashier.

    expect(find.text('That username and password cannot open Admin Mode. 4 attempts left.'), findsOneWidget);
    expect(find.text('Rana A.'), findsNothing, reason: 'the staff list must not render');
    expect(
      container.read(adminSessionProvider),
      isNull,
      reason: 'a refused PIN must not let anybody in',
    );
  });

  testWidgets('a wrong PIN is refused in the same words, and opens nothing',
      (tester) async {
    final container = await open(tester);
    await enter(tester, 'amer', pin: '0000');

    expect(
      find.text('That username and password cannot open Admin Mode. 4 attempts left.'),
      findsOneWidget,
    );
    expect(container.read(adminSessionProvider), isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('admin-password')))
          .controller!
          .text,
      isEmpty,
      reason: 'a refused PIN is not left sitting in the box',
    );
  });

  testWidgets('an unknown username is refused in the same words as a cashier', (tester) async {
    // Identical messages on purpose. Telling them apart would turn the door
    // into a way of finding out who may pass it.
    await open(tester);
    await enter(tester, 'nobody');
    expect(find.text('That username and password cannot open Admin Mode. 4 attempts left.'), findsOneWidget);
  });

  group('the Admin Mode password', () {
    Future<void> typeAtDoor(
      WidgetTester tester,
      String username,
      String secret,
    ) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('admin-username')),
          matching: find.byType(TextField),
        ),
        username,
      );
      await tester.enterText(find.byKey(const Key('admin-password')), secret);
      await tester.tap(find.byKey(const Key('admin-open')));
      await tester.pumpAndSettle();
    }

    Future<void> choose(
      WidgetTester tester,
      String password, [
      String? again,
    ]) async {
      await tester.enterText(
        find.byKey(const Key('admin-new-password')),
        password,
      );
      await tester.enterText(
        find.byKey(const Key('admin-confirm-password')),
        again ?? password,
      );
      await tester.tap(find.byKey(const Key('admin-set-password')));
      await tester.pumpAndSettle();
    }

    String? error(WidgetTester tester) {
      final shown = find.byKey(const Key('admin-error'));
      return shown.evaluate().isEmpty ? null : tester.widget<Text>(shown).data;
    }

    testWidgets('the first entry is by PIN, and nothing opens until a password '
        'is chosen', (tester) async {
      final container = await open(tester);
      await typeAtDoor(tester, 'amer', '4321');

      expect(find.byKey(const Key('admin-set-password-title')), findsOneWidget);
      expect(find.text('Add somebody'), findsNothing);
      expect(container.read(adminSessionProvider), isNull);
      expect(
        container.read(adminDbCredentialProvider),
        isNull,
        reason: 'the PIN step holds nothing the back office writes with',
      );

      // Back is the only other way, and it spends the PIN step.
      await tester.tap(find.byKey(const Key('admin-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-open')), findsOneWidget);
      expect(container.read(adminSessionProvider), isNull);
    });

    testWidgets('a short password is refused with the rule, in numbers',
        (tester) async {
      final container = await open(tester);
      await typeAtDoor(tester, 'amer', '4321');

      await choose(tester, 'too-short'); // Nine characters.
      expect(error(tester), 'A password needs at least 10 characters.');
      expect(container.read(adminSessionProvider), isNull);

      // Ten Arabic letters are ten characters: counted as typed, not in bytes.
      await choose(tester, 'كلمةسرطويل');
      expect(container.read(adminSessionProvider)!.staff.username, 'amer');
    });

    testWidgets('two different entries are refused, and nothing opens',
        (tester) async {
      final container = await open(tester);
      await typeAtDoor(tester, 'amer', '4321');

      await choose(tester, testAdminPassword, 'correct horse batteries');
      expect(error(tester), 'The two passwords are not the same.');
      expect(container.read(adminSessionProvider), isNull);
    });

    testWidgets('once chosen, the password opens it and the PIN no longer does',
        (tester) async {
      final container = await open(tester);
      await enter(tester, 'amer');
      expect(container.read(adminSessionProvider), isNotNull);

      // Out, and back to the door on the same till — the same book of
      // passwords, which a new harness would not have.
      await container
          .read(adminSessionProvider.notifier)
          .end(AdminSessionEnd.exited);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-open')), findsOneWidget);

      await typeAtDoor(tester, 'amer', '4321');
      final pinRefusal = error(tester);
      expect(
        pinRefusal,
        'That username and password cannot open Admin Mode. 4 attempts left.',
        reason: 'a PIN for a password account is a wrong guess, nothing more',
      );
      expect(find.byKey(const Key('admin-set-password-title')), findsNothing);
      expect(container.read(adminSessionProvider), isNull);

      await typeAtDoor(tester, 'amer', testAdminPassword);
      expect(container.read(adminSessionProvider)!.staff.username, 'amer');
    });

    testWidgets('a wrong password and an unknown username read the same',
        (tester) async {
      final container = await open(tester);
      final directory =
          container.read(staffDirectoryRepositoryProvider)
              as FakeStaffDirectoryRepository;
      directory.passwords.set(
        const PosStaff(
          id: 1,
          name: 'Amer M.',
          username: 'amer',
          role: FakeSessionRepository.owner,
        ),
        testAdminPassword,
      );

      await typeAtDoor(tester, 'amer', 'not the password at all');
      final wrong = error(tester);
      await typeAtDoor(tester, 'nobody', 'not the password at all');
      final unknown = error(tester);

      expect(wrong, startsWith(const EnStrings().adminSignInRefused));
      // Same words; only the count of tries left moves, and it moves for both.
      expect(
        wrong!.replaceAll(RegExp('[0-9]'), ''),
        unknown!.replaceAll(RegExp('[0-9]'), ''),
      );

      await typeAtDoor(tester, 'amer', testAdminPassword);
      expect(container.read(adminSessionProvider)!.staff.username, 'amer');
    });

    testWidgets("the technician's reset at the door clears the owner's, on "
        'the database password typed there', (tester) async {
      final container = await open(tester);
      final directory =
          container.read(staffDirectoryRepositoryProvider)
              as FakeStaffDirectoryRepository;
      directory.passwords.set(
        const PosStaff(
          id: 1,
          name: 'Amer M.',
          username: 'amer',
          role: FakeSessionRepository.owner,
        ),
        testAdminPassword,
      );

      await tester.tap(find.byKey(const Key('admin-technician-reset')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('technician-username')),
          matching: find.byType(TextField),
        ),
        'amer',
      );

      // A wrong one first: refused, and nothing cleared.
      await tester.enterText(
        find.byKey(const Key('technician-db-password')),
        'not-it',
      );
      await tester.tap(find.byKey(const Key('technician-clear')));
      await tester.pumpAndSettle();
      expect(
        find.text(const EnStrings().adminDatabasePasswordRefused),
        findsOneWidget,
      );
      expect(directory.passwords.passwordOf('amer'), testAdminPassword);

      await tester.enterText(
        find.byKey(const Key('technician-db-password')),
        'test-credential',
      );
      await tester.tap(find.byKey(const Key('technician-clear')));
      await tester.pumpAndSettle();
      expect(
        find.text(const EnStrings().technicianResetDone('Amer M.')),
        findsOneWidget,
      );
      expect(directory.passwords.passwordOf('amer'), isNull);
      expect(container.read(adminSessionProvider), isNull, reason: 'not in');

      // And the owner is back on the PIN, once.
      await tester.tap(find.byKey(const Key('technician-close')));
      await tester.pumpAndSettle();
      await typeAtDoor(tester, 'amer', '4321');
      expect(find.byKey(const Key('admin-set-password-title')), findsOneWidget);
    });

    testWidgets('a manager can clear somebody\'s password from Staff, never the '
        'owner\'s', (tester) async {
      final container = await open(tester);
      await enter(tester, 'amer'); // Chooses Amer's password on the way in.

      final directory =
          container.read(staffDirectoryRepositoryProvider)
              as FakeStaffDirectoryRepository;
      final rana = directory.staff.firstWhere((p) => p.username == 'rana');
      directory.passwords.set(rana, 'rana-password-1');
      container.invalidate(staffWithPasswordProvider);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('password-set-1')), findsOneWidget);
      expect(
        find.byKey(const Key('clear-password-1')),
        findsNothing,
        reason: "the owner's is a technician's to clear",
      );

      await tester.tap(find.byKey(Key('clear-password-${rana.id}')));
      await tester.pumpAndSettle();
      expect(find.text("Clear Rana A.'s Admin Mode password?"), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Clear password'),
        ),
      );
      await tester.pumpAndSettle();

      expect(directory.passwords.passwordOf('rana'), isNull);
      expect(find.byKey(Key('clear-password-${rana.id}')), findsNothing);
      expect(directory.passwords.passwordOf('amer'), testAdminPassword);
    });
  });

  testWidgets('asked for nothing, it opens on Home', (tester) async {
    // Staff was the default while the back office was a list with Staff at
    // the top. Under the owner's map it sits in People, so the door lands
    // where the bar starts: Home, which everybody past the door holds (BO-4).
    await open(tester, pane: null);
    await enter(tester, 'amer');
    expect(find.byType(ManagementHomePane), findsOneWidget);
    expect(find.text('Add somebody'), findsNothing);
  });

  testWidgets('can be pointed at another pane', (tester) async {
    // The mechanism the Settings menu's "Staff & accounts" item uses. Adding a
    // cashier has always been possible, behind a menu item called "Management"
    // that does not mention accounts — and a path that exists but cannot be
    // found is, to the person looking for it, the same as one that does not.
    await open(tester, pane: ManagementPane.activity);
    await enter(tester, 'amer');

    // The pane itself, not its name: a name can be on screen without its
    // pane — the header's, a card's link to it.
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
            onReconfigure: () {},
            initialPane: ManagementPane.roles,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ManagementRolesPane), findsOneWidget);
    expect(find.byType(ManagementActivityPane), findsNothing);
  });

  testWidgets('Tax sits in Settings beside its neighbours, and the header '
      'names it', (tester) async {
    // Money is configuration, as it is on the cloud, so it went to Settings
    // when the tabs came back (BO-1). The side nav names the neighbours; the
    // header still names the page.
    await open(tester, pane: ManagementPane.taxes);
    await enter(tester, 'amer');

    expect(
      tester.widget<Text>(find.byKey(const Key('back-office-title'))).data,
      const EnStrings().paneTaxes,
    );
    expect(find.byType(ManagementRolesPane), findsNothing);
    expect(find.byKey(const Key('back-office-settings-nav')), findsOneWidget);
    expect(
      find.byKey(const Key('back-office-settings-charges')),
      findsOneWidget,
    );
  });

  testWidgets('the roles pane refuses to make a cashier an administrator',
      (tester) async {
    await open(tester, pane: ManagementPane.roles);
    await enter(tester, 'amer');

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
    // whose whole purpose is telling a business who changed something.
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

    expect(find.textContaining('price: 45.00 EGP → 50.00 EGP'), findsOneWidget);
  });

  testWidgets('purchasing is a permission an owner can grant by name', (
    tester,
  ) async {
    // **It rendered as `purchase.manage`.** `AdminText.capability` ends in a
    // fall-through so a capability from a newer build is shown rather than
    // hidden, and the effect on one from *this* build was the raw key on the
    // screen where a business owner decides who may spend money.
    final container = await open(tester, pane: ManagementPane.roles);
    await enter(tester, 'amer');

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
    final container = await open(tester, pane: ManagementPane.roles);
    await enter(tester, 'amer');

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
    await open(tester, pane: ManagementPane.roles);
    await enter(tester, 'amer');
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
    await open(tester, pane: ManagementPane.roles);
    await enter(tester, 'amer');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('roles-new')));
    await tester.pumpAndSettle();

    expect(find.text('Accountant'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Delivery staff'), findsOneWidget);
  });

  testWidgets('picking a template creates an ordinary role', (tester) async {
    await open(tester, pane: ManagementPane.roles);
    await enter(tester, 'amer');
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
    final container = await open(tester, offline: true);
    await enter(tester, 'amer');

    // Asked of the rule rather than of the bar. What decides whether
    // Purchasing is offered — in the window's bar, to Home's shortcuts, and
    // to a deep link — is `backOfficeTabsFor`, so that is asked.
    bool offersPurchasing() =>
        backOfficeTabsFor(
          admin: container.read(adminSessionProvider)!.staff,
          authorsItsOwnCatalogue:
              container.read(catalogAdminRepositoryProvider) != null,
        ).expand((tab) => tab.$2).contains(ManagementPane.purchasing);

    expect(offersPurchasing(), isTrue, reason: 'the owner buys');

    // Nour: a supervisor the owner let into Admin Mode, who does not buy.
    // The owner leaves as Log out does — this harness has no window bar.
    await container
        .read(adminSessionProvider.notifier)
        .end(AdminSessionEnd.exited);
    await tester.pumpAndSettle();
    await enter(tester, 'nour', pin: '2468');

    expect(offersPurchasing(), isFalse);
  });

  testWidgets('a deep link to Purchasing does not outlive the permission', (
    tester,
  ) async {
    // `initialPane` comes from a menu item somebody may have had every right to
    // use last week. The rail hiding it while the body still rendered it would
    // be the gate saying no and the screen saying yes.
    final container = await open(
      tester,
      pane: ManagementPane.purchasing,
      offline: true,
    );
    await enter(tester, 'amer');
    expect(find.text('New order'), findsOneWidget);

    // The same deep link, and somebody else through the door.
    await container
        .read(adminSessionProvider.notifier)
        .end(AdminSessionEnd.exited);
    await tester.pumpAndSettle();
    await enter(tester, 'nour', pin: '2468');

    expect(find.text('New order'), findsNothing);
    // Back to the door's landing — Home — rather than to anything the link
    // named.
    expect(
      find.byKey(const ValueKey('back-office-pane-home')),
      findsOneWidget,
      reason: 'falls back',
    );
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

  group('while the database is being asked', () {
    // The case that crashed once: the door's answer arriving after the screen
    // had already moved on. Management used to hold the password first and
    // try it second, which opened the panes mid-check, disposed the form, and
    // left the check reading a `ref` that no longer existed. These hold the
    // database's answer back and look at the screen in between — with the
    // owner signed in at the till, where it went wrong.
    Future<({ProviderContainer container, Completer<PosDbFailure?> answer})>
    atTheDoor(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final answer = Completer<PosDbFailure?>();
      final container = ProviderContainer(
        overrides: [
          ...fakeRepositoryOverrides(),
          adminPasswordProbeProvider.overrideWithValue((_) => answer.future),
        ],
      );
      addTearDown(container.dispose);

      final amer = (await container
              .read(staffDirectoryRepositoryProvider)
              .all(includeInactive: false))
          .firstWhere((person) => person.username == 'amer');
      container.read(signedInStaffProvider.notifier).signIn(amer);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildPosTheme(),
            home: ManagementScreen(
              onClose: () {},
              onReconfigure: () {},
              initialPane: ManagementPane.staff,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add somebody'), findsNothing, reason: 'the door is shut');
      return (container: container, answer: answer);
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('admin-username')),
          matching: find.byType(TextField),
        ),
        'amer',
      );
      await tester.enterText(find.byKey(const Key('admin-password')), '4321');
      await tester.tap(find.byKey(const Key('admin-open')));
      // One frame, not settle: the database has not answered yet.
      await tester.pump();
    }

    testWidgets('nothing opens before the answer, and the screen survives it', (
      tester,
    ) async {
      final door = await atTheDoor(tester);
      await submit(tester);

      expect(
        find.text('Add somebody'),
        findsNothing,
        reason: 'nothing opens on a password nobody has tried yet',
      );
      expect(door.container.read(adminDbCredentialProvider), isNull);

      door.answer.complete(null);
      await tester.pumpAndSettle();
      // Amer has no password yet: the PIN got him to the step that asks for
      // one, and the back office opens only after it.
      expect(find.text('Add somebody'), findsNothing);
      await completeAdminPasswordStep(tester);

      expect(find.text('Add somebody'), findsOneWidget);
      expect(door.container.read(adminDbCredentialProvider), 'test-credential');
      expect(door.container.read(adminSessionProvider)!.staff.username, 'amer');
    });

    testWidgets('a kept password the database now refuses is asked for again, '
        'and nothing is held', (tester) async {
      final door = await atTheDoor(tester);
      await submit(tester);

      door.answer.complete(PosDbFailure.auth);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-db-password')), findsOneWidget);
      expect(find.text('Add somebody'), findsNothing);
      expect(
        door.container.read(adminDbCredentialProvider),
        isNull,
        reason: 'a password that got nobody in is not held for the session',
      );
    });
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
