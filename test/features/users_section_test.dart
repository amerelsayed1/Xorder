import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/application/users_overview.dart';
import 'package:xorder_pos/features/admin/presentation/management_roles_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// Settings › Users (BO-7): the tiles, the filters, the last-shift column and
/// the role matrix, each held to what it claims.
///
/// The screen's claims are counts and labels, so these read the counts and the
/// labels back off it. "Current shifts equals the open rows" against a real
/// server is `test/data/postgres_shift_test.dart`; what is asserted here is
/// that the screen prints what the repository said.
///
/// The fake staff are Amer (Owner, id 1) and Rana (Cashier, id 2); some tests
/// add Nour (id 3).
void main() {
  const en = EnStrings();
  const ar = ArStrings();

  PosRole seeded(String code, {required int id}) => PosRole(
    id: id,
    code: code,
    nameEn: SystemRoles.seeded[code]!.nameEn,
    capabilities: SystemRoles.seeded[code]!.capabilities,
  );

  group('the filters', () {
    final manager = seeded(SystemRoles.managerCode, id: 2);
    final cashier = seeded(SystemRoles.cashierCode, id: 4);
    final people = [
      PosStaff(id: 1, name: 'Hana M.', username: 'hana', role: manager),
      PosStaff(id: 2, name: 'Rana A.', username: 'rana', role: cashier),
      PosStaff(
        id: 3,
        name: 'Omar T.',
        username: 'omar',
        role: cashier,
        isActive: false,
      ),
      // A cashier who covers the odd shift as a manager: Manager is an EXTRA
      // role, and the table's role column says Cashier.
      PosStaff(
        id: 4,
        name: 'Sara K.',
        username: 'sara',
        role: cashier,
        extraRoles: [manager],
      ),
    ];
    List<int> ids(StaffFilter filter) => [
      for (final person in filter.apply(people)) person.id,
    ];

    test('by status', () {
      expect(ids(const StaffFilter()), [1, 2, 3, 4]);
      expect(
        ids(const StaffFilter(status: StaffStatusFilter.active)),
        [1, 2, 4],
      );
      expect(ids(const StaffFilter(status: StaffStatusFilter.disabled)), [3]);
    });

    test("by the person's own role, not an extra one", () {
      expect(
        ids(StaffFilter(roleId: manager.id)),
        [1],
        reason: 'Sara covers as a manager; her row says Cashier',
      );
      expect(ids(StaffFilter(roleId: cashier.id)), [2, 3, 4]);
    });

    test('by name or username, whatever the case, and with the "@" the table '
        'prints', () {
      expect(ids(const StaffFilter(search: 'rana')), [2]);
      expect(ids(const StaffFilter(search: '@OMAR')), [3]);
      expect(ids(const StaffFilter(search: 'a m')), [1]);
      expect(ids(const StaffFilter(search: '   ')), [1, 2, 3, 4]);
    });

    test('and all three at once', () {
      expect(
        ids(
          StaffFilter(
            status: StaffStatusFilter.active,
            roleId: cashier.id,
            search: 'a',
          ),
        ),
        [2, 4],
      );
    });
  });

  test('the active share rounds down, so one disabled account is never 100%',
      () {
    UsersKpis of(int active, int total) =>
        UsersKpis(total: total, active: active, openShifts: 0, roles: 0);

    expect(of(199, 200).activePercent, 99);
    expect(of(2, 3).activePercent, 66);
    expect(of(3, 3).activePercent, 100);
    expect(of(0, 0).activePercent, isNull, reason: 'no share of nobody');
  });

  group('the role matrix', () {
    test("counts every cell from the role's own capabilities", () {
      final owner = seeded(SystemRoles.ownerCode, id: 1);
      final cashier = seeded(SystemRoles.cashierCode, id: 4);
      final matrix = RoleMatrix([owner, cashier]);

      for (final group in RoleMatrix.groups) {
        expect(
          matrix.held(group, owner),
          RoleMatrix.size(group),
          reason: 'the owner holds everything — ${group.name}',
        );
        expect(
          matrix.held(group, cashier),
          group.capabilities.where(SystemRoles.cashier.contains).length,
          reason: group.name,
        );
      }
    });

    test('and changes when the role does', () {
      final cashier = seeded(SystemRoles.cashierCode, id: 4);
      final extra = CapabilityGroup.money.capabilities.firstWhere(
        (c) => !cashier.holds(c),
      );
      final before = RoleMatrix([cashier]).held(CapabilityGroup.money, cashier);

      final widened = cashier.copyWith(
        capabilities: {...cashier.capabilities, extra},
      );
      expect(
        RoleMatrix([widened]).held(CapabilityGroup.money, widened),
        before + 1,
      );

      final emptied = cashier.copyWith(capabilities: const {});
      for (final group in RoleMatrix.groups) {
        expect(RoleMatrix([emptied]).held(group, emptied), 0);
      }
    });
  });

  group('the Users section', () {
    // The bundled faces, not the test font: the test font draws every glyph a
    // full em wide, so an overflow at 1100 px in it is one no business
    // would see. It first bit on the back office's tab strip, which the owner
    // has since taken away (15 Sep 2026).
    setUpAll(loadPosFonts);

    Future<ProviderContainer> open(
      WidgetTester tester, {
      Size size = const Size(1440, 900),
      Locale locale = const Locale('en'),
      void Function(ProviderContainer container)? before,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      before?.call(container);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
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
      await enterAdminMode(tester);
      return container;
    }

    FakeStaffDirectoryRepository directoryOf(ProviderContainer container) =>
        container.read(staffDirectoryRepositoryProvider)
            as FakeStaffDirectoryRepository;

    /// Rana's two closed shifts, Amer's drawer open on another till, and
    /// Nour — disabled, a manager, who has never opened one.
    void branchWithHistory(ProviderContainer container) {
      final directory = directoryOf(container);
      directory.staff.add(
        PosStaff(
          id: 3,
          name: 'Nour S.',
          username: 'nour',
          isActive: false,
          role: directory.roles.roles.firstWhere(
            (r) => r.code == SystemRoles.managerCode,
          ),
        ),
      );
      (container.read(shiftRepositoryProvider) as FakeShiftRepository).earlier
          .addAll([
            PosShift(
              id: 7,
              openedAt: DateTime(2026, 9, 12, 9, 30),
              closedAt: DateTime(2026, 9, 12, 17),
              openingFloat: Money.zero,
              openedByName: 'Rana A.',
              openedById: 2,
            ),
            PosShift(
              id: 8,
              openedAt: DateTime(2026, 9, 13, 18, 5),
              closedAt: DateTime(2026, 9, 13, 23),
              openingFloat: Money.zero,
              openedByName: 'Rana A.',
              openedById: 2,
            ),
            PosShift(
              id: 9,
              openedAt: DateTime(2026, 9, 14, 8),
              openingFloat: Money(50000),
              openedByName: 'Amer M.',
              openedById: 1,
            ),
          ]);
    }

    String textOf(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data!;

    /// A matrix cell is a widget of its own; its figure is the Text inside.
    String cellOf(WidgetTester tester, String key) => tester
        .widget<Text>(
          find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
        )
        .data!;

    testWidgets('the tiles count staff, active, open drawers and roles', (
      tester,
    ) async {
      final container = await open(tester, before: branchWithHistory);

      expect(textOf(tester, 'users-kpi-staff'), '3', reason: 'Nour included');
      expect(textOf(tester, 'users-kpi-active'), '2');
      expect(find.text(en.usersActiveShare(66)), findsOneWidget);
      expect(
        textOf(tester, 'users-kpi-shifts'),
        '1',
        reason: "Amer's drawer is the only one out",
      );
      expect(
        textOf(tester, 'users-kpi-roles'),
        '${directoryOf(container).roles.roles.length}',
      );
    });

    testWidgets('the column is headed "last shift", and says what was '
        'recorded', (tester) async {
      await open(tester, before: branchWithHistory);

      // MicroLabel sets English in capitals.
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('users-column-last-shift')),
                matching: find.byType(Text),
              ),
            )
            .data,
        en.usersColumnLastShift.toUpperCase(),
      );
      expect(en.usersColumnLastShift, 'Last shift');
      final words = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase());
      expect(
        words.where((w) => w.contains('login') || w.contains('log in')),
        isEmpty,
        reason: 'no sign-in is recorded, so nothing may claim to show one',
      );

      expect(textOf(tester, 'last-shift-1'), en.usersOnShiftNow);
      expect(
        textOf(tester, 'last-shift-2'),
        '2026-09-13 18:05',
        reason: 'the newer of her two shifts',
      );
      expect(textOf(tester, 'last-shift-3'), en.usersNeverOnShift);
    });

    testWidgets('the filters narrow the table, and say so when nobody is '
        'left', (tester) async {
      await open(tester, before: branchWithHistory);
      final roleOf = find.byKey;

      await tester.tap(find.byKey(const Key('users-status-disabled')));
      await tester.pumpAndSettle();
      expect(roleOf(const Key('role-3')), findsOneWidget);
      expect(roleOf(const Key('role-1')), findsNothing);
      expect(roleOf(const Key('role-2')), findsNothing);

      await tester.tap(find.byKey(const Key('users-status-all')));
      await tester.enterText(find.byKey(const Key('users-search')), '@ran');
      await tester.pumpAndSettle();
      expect(roleOf(const Key('role-2')), findsOneWidget);
      expect(roleOf(const Key('role-1')), findsNothing);
      expect(roleOf(const Key('role-3')), findsNothing);

      await tester.enterText(find.byKey(const Key('users-search')), '');
      await tester.tap(find.byKey(const Key('users-role-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manager').last);
      await tester.pumpAndSettle();
      expect(roleOf(const Key('role-3')), findsOneWidget);
      expect(roleOf(const Key('role-2')), findsNothing);

      await tester.enterText(find.byKey(const Key('users-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text(en.usersNoneMatch), findsOneWidget);
    });

    testWidgets("the matrix follows a role's capabilities, not a table "
        'somebody drew', (tester) async {
      final container = await open(tester);
      final directory = directoryOf(container);
      final cashier = directory.roles.roles.firstWhere(
        (r) => r.code == SystemRoles.cashierCode,
      );
      const group = CapabilityGroup.money;
      final size = RoleMatrix.size(group);
      final held = group.capabilities.where(cashier.holds).length;
      final cell = 'matrix-${group.name}-${cashier.id}';

      expect(cellOf(tester, cell), '$held/$size');

      // What the Roles pane does when the owner ticks a box.
      final extra = group.capabilities.firstWhere((c) => !cashier.holds(c));
      final saved = await container
          .read(rolesRepositoryProvider)
          .save(
            cashier.copyWith(capabilities: {...cashier.capabilities, extra}),
            by: directory.staff.first,
          );
      expect(saved.succeeded, isTrue, reason: '${saved.refusal}');
      container.invalidate(rolesProvider);
      await tester.pumpAndSettle();

      expect(cellOf(tester, cell), '${held + 1}/$size');
    });

    testWidgets('"Manage roles" opens Settings › Roles', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('users-manage-roles')));
      await tester.pumpAndSettle();

      expect(find.byType(ManagementRolesPane), findsOneWidget);
    });

    // Two tests rather than one opening the screen twice: the second pump
    // would orphan the first screen's Admin Mode idle timer.
    testWidgets('the matrix sits beside the table on a wide screen', (
      tester,
    ) async {
      await open(tester, size: const Size(1920, 1080));
      expect(
        tester.getTopLeft(find.byKey(const Key('role-matrix'))).dx,
        greaterThan(tester.getTopRight(find.byKey(const Key('role-1'))).dx),
      );
    });

    testWidgets('and under it on a laptop', (tester) async {
      await open(tester);
      expect(
        tester.getTopLeft(find.byKey(const Key('role-matrix'))).dy,
        greaterThan(tester.getBottomLeft(find.byKey(const Key('role-2'))).dy),
      );
    });

    testWidgets('at the narrowest back office nothing breaks, and every '
        'action is still there', (tester) async {
      await open(tester, size: const Size(PosSize.wideShellMin, 800));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('reset-pin-2')), findsOneWidget);
      expect(find.byKey(const Key('grants-2')), findsOneWidget);
    });

    testWidgets('in Arabic: right to left, translated, numbers in Latin '
        'digits and set left to right', (tester) async {
      await open(tester, locale: const Locale('ar'), before: branchWithHistory);
      expect(tester.takeException(), isNull);

      final tile = find.byKey(const Key('users-kpi-staff'));
      expect(Directionality.of(tester.element(tile)), TextDirection.rtl);
      expect(tester.widget<Text>(tile).textDirection, TextDirection.ltr);
      expect(
        tester.widget<Text>(find.text('@amer')).textDirection,
        TextDirection.ltr,
      );

      for (final word in [
        ar.usersColumnLastShift,
        ar.usersKpiShifts,
        ar.roleMatrixTitle,
        ar.manageRoles,
        ar.usersOnShiftNow,
        ar.usersNeverOnShift,
      ]) {
        expect(find.text(word), findsWidgets, reason: word);
      }
      expect(textOf(tester, 'last-shift-2'), '2026-09-13 18:05');

      final eastern = RegExp('[٠-٩]');
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where(eastern.hasMatch),
        isEmpty,
      );
    });
  });
}
