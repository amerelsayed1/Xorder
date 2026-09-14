import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos/features/admin/presentation/management_staff_pane.dart';
import 'package:xorder_pos/features/admin/presentation/staff_grants_dialog.dart';

import '../support/fakes.dart';

/// One owner per restaurant, and the owner's own access is not editable.
///
/// The Staff pane's claims: it does not offer what the repository would
/// refuse. The owner's row has no role to pick and no permissions to edit;
/// nobody else is offered Owner while there is one; and a new person cannot be
/// hired onto it. The database suite (`test/data/one_owner_test.dart`) is where
/// the rule itself is proved — these are about a screen that could otherwise
/// offer a dropdown whose every Owner choice ends in a refusal.
///
/// The fake staff are Amer (Owner, id 1) and Rana (Cashier, id 2).
void main() {
  const strings = EnStrings();

  Future<ProviderContainer> open(
    WidgetTester tester, {
    String username = 'amer',
    String pin = '4321',
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
          home: ManagementScreen(
            onClose: () {},
            onReconfigure: () {},
            initialPane: ManagementPane.staff,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterAdminMode(tester, username: username, pin: pin);
    return container;
  }

  FakeStaffDirectoryRepository directoryOf(ProviderContainer container) =>
      container.read(staffDirectoryRepositoryProvider)
          as FakeStaffDirectoryRepository;

  int roleIdOf(FakeStaffDirectoryRepository directory, String code) =>
      directory.roles.roles.firstWhere((r) => r.code == code).id;

  DropdownButton<int> dropdown(WidgetTester tester, Key key) =>
      tester.widget<DropdownButton<int>>(find.byKey(key));

  List<int?> offered(WidgetTester tester, Key key) => [
    for (final item in dropdown(tester, key).items!) item.value,
  ];

  VoidCallback? tapOf(WidgetTester tester, Key key) => tester
      .widget<InkWell>(
        find.descendant(of: find.byKey(key), matching: find.byType(InkWell)).first,
      )
      .onTap;

  group('the Staff pane', () {
    testWidgets("only the owner is offered the owner's PIN", (tester) async {
      // Nour: a supervisor the owner let into Admin Mode, who manages staff.
      await open(tester, username: 'nour', pin: '2468');
      expect(
        tapOf(tester, const Key('reset-pin-1')),
        isNull,
        reason: "the owner's row",
      );
      expect(
        tapOf(tester, const Key('reset-pin-2')),
        isNotNull,
        reason: "a cashier's row is still staff.manage's",
      );
    });

    testWidgets('and the owner is, on their own row', (tester) async {
      await open(tester);
      expect(tapOf(tester, const Key('reset-pin-1')), isNotNull);
    });

    testWidgets("the owner's row has no role to pick and no permissions to edit",
        (tester) async {
      await open(tester);

      expect(
        dropdown(tester, const Key('role-1')).onChanged,
        isNull,
        reason: 'a role picker on the owner is ownership given away in a '
            'dropdown',
      );
      expect(tapOf(tester, const Key('grants-1')), isNull);

      // Disabled, but still saying what they are. A disabled DropdownButton
      // shows its hint rather than its value, so this is the assertion that
      // catches a row reading "No role".
      expect(
        find.descendant(
          of: find.byKey(const Key('role-1')),
          matching: find.text('Owner'),
        ),
        findsOneWidget,
      );

      // And the rule is about the owner, not about the pane: Rana's row works.
      expect(dropdown(tester, const Key('role-2')).onChanged, isNotNull);
      expect(tapOf(tester, const Key('grants-2')), isNotNull);
    });

    testWidgets('nobody else is offered Owner while there is one', (
      tester,
    ) async {
      final container = await open(tester);
      final directory = directoryOf(container);
      final ownerRole = roleIdOf(directory, SystemRoles.ownerCode);

      expect(offered(tester, const Key('role-2')), isNot(contains(ownerRole)));
      expect(
        offered(tester, const Key('role-2')),
        contains(roleIdOf(directory, SystemRoles.managerCode)),
        reason: 'only Owner is withheld',
      );
    });

    testWidgets('nor as an extra role in the permissions dialog', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('grants-2')));
      await tester.pumpAndSettle();

      final dialog = find.byType(StaffGrantsDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Owner')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Manager')),
        findsWidgets,
      );
    });

    testWidgets('once the owner is disabled, Owner is offered again', (
      tester,
    ) async {
      // Counted among ACTIVE staff, so ownership can be handed over. A pane
      // that withheld Owner for good would make the handover impossible from
      // the one screen that does it.
      final container = await open(tester);
      final directory = directoryOf(container);
      final ownerRole = roleIdOf(directory, SystemRoles.ownerCode);

      // A manager, so that disabling the owner does not lock everybody out.
      directory.staff.add(
        PosStaff(
          id: 3,
          name: 'Nour S.',
          username: 'nour',
          role: directory.roles.roles.firstWhere(
            (r) => r.code == SystemRoles.managerCode,
          ),
        ),
      );
      final disabled = await directory.setActive(
        by: directory.staff.first,
        staffId: 1,
        isActive: false,
      );
      expect(disabled.succeeded, isTrue, reason: '${disabled.refusal}');
      container.invalidate(staffDirectoryProvider);
      await tester.pumpAndSettle();

      expect(offered(tester, const Key('role-2')), contains(ownerRole));
      // The former owner can be moved off Owner now — otherwise they could
      // never come back as anything else — but their grants stay shut: they
      // are still on the role that holds everything.
      expect(dropdown(tester, const Key('role-1')).onChanged, isNotNull);
      expect(tapOf(tester, const Key('grants-1')), isNull);
    });

    testWidgets('a new person is not offered Owner while there is one', (
      tester,
    ) async {
      final container = await open(tester);
      final directory = directoryOf(container);

      // Hiring is an offline till's act — on a cloud till the bundle owns who
      // works here and the button is shut — and the harness starts
      // unconfigured, which reads as cloud.
      container
          .read(deploymentProvider.notifier)
          .apply(
            DeploymentConfig.unconfigured.copyWith(mode: DeploymentMode.offline),
          );
      await tester.pumpAndSettle();

      await tester.tap(find.text(strings.addSomebody));
      await tester.pumpAndSettle();
      expect(find.byType(StaffEditorDialog), findsOneWidget);

      final roles = offered(tester, const Key('staff-editor-role'));
      expect(roles, isNot(contains(roleIdOf(directory, SystemRoles.ownerCode))));
      expect(roles, contains(roleIdOf(directory, SystemRoles.cashierCode)));
    });
  });

  group('the refusals say what to do next', () {
    test('in English, naming the owner and the way ownership moves', () {
      final text = AdminText.refusal(strings, const OwnerAlreadyExists('Amer M.'));
      expect(text, contains('Amer M.'));
      expect(text, contains('disable'));

      expect(AdminText.refusal(strings, const OwnerIsFixed()), contains('disable'));
      expect(
        AdminText.refusal(strings, const OwnerIsNotAnExtraRole()),
        contains('choose Owner as their role'),
      );
    });

    test('in Arabic, translated, with the name left as written', () {
      const ar = ArStrings();
      final text = AdminText.refusal(ar, const OwnerAlreadyExists('Amer M.'));
      expect(text, contains('Amer M.'));
      expect(text, contains('عطّل'));

      for (final refusal in const <AdminRefusal>[
        OwnerAlreadyExists('Amer M.'),
        OwnerIsFixed(),
        OwnerIsNotAnExtraRole(),
        OwnerPinIsTheirs(),
      ]) {
        final arabic = AdminText.refusal(ar, refusal);
        expect(arabic, isNot(AdminText.refusal(strings, refusal)));
        expect(arabic, contains('المالك'));
        // Latin digits only, as everywhere else on the till.
        expect(RegExp('[٠-٩]').hasMatch(arabic), isFalse);
      }
    });
  });

  group('the fake refuses what the database refuses', () {
    // The widget tests above run against this fake. A fake more permissive
    // than the thing it stands in for would let a screen pass a test it could
    // not pass in a restaurant.
    late FakeStaffDirectoryRepository directory;
    late PosStaff amer;
    late int ownerRole;

    setUp(() {
      directory = FakeStaffDirectoryRepository(roles: FakeRolesRepository());
      amer = directory.staff.first;
      ownerRole = roleIdOf(directory, SystemRoles.ownerCode);
    });

    test("the owner's PIN, by anybody but the owner", () async {
      final manager = PosStaff(
        id: 3,
        name: 'Nour S.',
        username: 'nour',
        role: directory.roles.roles.firstWhere(
          (r) => r.code == SystemRoles.managerCode,
        ),
      );

      final refused = await directory.resetPin(
        by: manager,
        staffId: 1,
        pin: '9999',
      );
      expect(refused.refusal, isA<OwnerPinIsTheirs>());
      expect(directory.pins, isNot(containsPair('9999', 1)));

      final own = await directory.resetPin(by: amer, staffId: 1, pin: '9999');
      expect(own.succeeded, isTrue);

      final rana = await directory.resetPin(
        by: manager,
        staffId: 2,
        pin: '8888',
      );
      expect(rana.succeeded, isTrue, reason: "everybody else's is still theirs");
    });

    test('a second owner, by hiring, moving or extra role', () async {
      final hired = await directory.create(
        by: amer,
        name: 'Nour S.',
        username: 'nour',
        pin: '9999',
        roleId: ownerRole,
      );
      expect((hired.refusal! as OwnerAlreadyExists).ownerName, 'Amer M.');

      final moved = await directory.update(
        by: amer,
        staffId: 2,
        roleId: ownerRole,
      );
      expect((moved.refusal! as OwnerAlreadyExists).ownerName, 'Amer M.');

      final extra = await directory.setGrants(
        by: amer,
        staffId: 2,
        extraRoleIds: {ownerRole},
        overrides: const [],
        limits: const {},
      );
      expect((extra.refusal! as OwnerAlreadyExists).ownerName, 'Amer M.');
      expect(directory.staff, hasLength(2));
    });

    test("the owner's role, grants and exceptions", () async {
      final moved = await directory.update(
        by: amer,
        staffId: 1,
        roleId: roleIdOf(directory, SystemRoles.managerCode),
      );
      expect(moved.refusal, isA<OwnerIsFixed>());

      final granted = await directory.update(
        by: amer,
        staffId: 1,
        directGrants: {PosCapability.orderRefund},
      );
      expect(granted.refusal, isA<OwnerIsFixed>());

      final excepted = await directory.setGrants(
        by: amer,
        staffId: 1,
        extraRoleIds: const {},
        overrides: const [
          PermissionOverride(
            capability: PosCapability.staffManage,
            effect: OverrideEffect.deny,
          ),
        ],
        limits: const {},
      );
      expect(excepted.refusal, isA<OwnerIsFixed>());
      expect(directory.staff.first.overrides, isEmpty);

      final renamed = await directory.update(
        by: amer,
        staffId: 1,
        name: 'Amer',
      );
      expect(renamed.succeeded, isTrue);
    });

    test('and the handover: disable, appoint, and no way back', () async {
      directory.staff.add(
        PosStaff(
          id: 3,
          name: 'Nour S.',
          username: 'nour',
          role: directory.roles.roles.firstWhere(
            (r) => r.code == SystemRoles.managerCode,
          ),
        ),
      );

      expect(
        (await directory.setActive(by: amer, staffId: 1, isActive: false))
            .succeeded,
        isTrue,
      );
      final appointed = await directory.update(
        by: amer,
        staffId: 2,
        roleId: ownerRole,
      );
      expect(appointed.succeeded, isTrue, reason: '${appointed.refusal}');

      final back = await directory.setActive(
        by: amer,
        staffId: 1,
        isActive: true,
      );
      expect((back.refusal! as OwnerAlreadyExists).ownerName, 'Rana A.');
    });
  });
}
