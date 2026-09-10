import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/presentation/manage_menu.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

/// One tap to any back-office pane.
///
/// **Nine panes had one door**, on the start screen, opening on Staff. The claim
/// this menu makes is that everything the signed-in person may use is one tap
/// away — and the claim worth testing is the other half: that it offers exactly
/// what the rail would, never more.
void main() {
  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'owner',
      nameEn: 'Owner',
      capabilities: SystemRoles.owner,
    ),
  );

  /// Manages the rota, does not buy the stock. A real job, and the one the
  /// menu must not lie to.
  const supervisor = PosStaff(
    id: 2,
    name: 'Nour S.',
    role: PosRole(
      id: 2,
      code: 'supervisor',
      nameEn: 'Supervisor',
      capabilities: {PosCapability.staffManage},
    ),
  );

  const cashier = PosStaff(
    id: 3,
    name: 'Rana A.',
    role: PosRole(
      id: 3,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.operate},
    ),
  );

  Future<List<ManagementPane>> open(
    WidgetTester tester, {
    PosStaff? signedIn,
    bool tap = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final picked = <ManagementPane>[];
    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
    if (signedIn != null) {
      container.read(signedInStaffProvider.notifier).signIn(signedIn);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ManageMenu(onPick: picked.add),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (tap) {
      await tester.tap(find.byKey(const Key('manage-menu')));
      await tester.pumpAndSettle();
    }
    return picked;
  }

  testWidgets('a cashier is shown nothing at all, not a disabled button', (
    tester,
  ) async {
    // A greyed-out Manage button on a cashier's till is a permanent
    // advertisement for a door they will never be given.
    await open(tester, signedIn: cashier, tap: false);
    expect(find.byKey(const Key('manage-menu')), findsNothing);
  });

  testWidgets('nobody signed in gets the door, not a guess at the panes', (
    tester,
  ) async {
    // This used to assert the opposite, and it was right at the time: the start
    // screen carried its own always-visible Manage word, so hiding the menu
    // when nobody was signed in cost nothing. That word is gone — the bars
    // carry this menu instead — and hiding it left the back office unreachable
    // on a till before its shift or after a restart, because the management
    // screen's own PIN pad is what signs somebody in. A lock with its key
    // inside.
    //
    // So: one plain button rather than the pane list. Which panes an unknown
    // person may have is not a question this menu can answer; the pane it opens
    // is locked, and asks.
    final picked = await open(tester);

    expect(find.byKey(const Key('manage-menu')), findsOneWidget);
    expect(picked, [ManagementPane.staff]);
  });

  testWidgets('an owner reaches every pane in one tap', (tester) async {
    await open(tester, signedIn: owner);

    // Every pane this terminal has. Menu and Floor are absent because the
    // fake harness has no catalogue-authoring repository, which is what an
    // offline install would provide — the same rule the rail uses.
    for (final pane in [
      ManagementPane.staff,
      ManagementPane.taxes,
      ManagementPane.charges,
      ManagementPane.tenders,
      ManagementPane.purchasing,
      ManagementPane.receipt,
      ManagementPane.eta,
      ManagementPane.roles,
      ManagementPane.activity,
    ]) {
      expect(
        find.byKey(Key('manage-menu-${pane.name}')),
        findsOneWidget,
        reason: pane.name,
      );
    }
  });

  testWidgets('it offers exactly what the rail would, never more', (
    tester,
  ) async {
    // The reason `managementPanesFor` is a function rather than two lists: a
    // menu offering Purchasing to somebody the rail hides it from would take
    // them to a screen that refuses everything.
    await open(tester, signedIn: supervisor);

    expect(find.byKey(const Key('manage-menu-staff')), findsOneWidget);
    expect(
      find.byKey(const Key('manage-menu-purchasing')),
      findsNothing,
      reason: 'a supervisor who does not buy',
    );

    final allowed = managementPanesFor(
      admin: supervisor,
      authorsItsOwnCatalogue: false,
    );
    for (final pane in ManagementPane.values) {
      expect(
        find.byKey(Key('manage-menu-${pane.name}')),
        allowed.contains(pane) ? findsOneWidget : findsNothing,
        reason: pane.name,
      );
    }
  });

  testWidgets('the panes are grouped by area, not one long list', (
    tester,
  ) async {
    // Nine flat items already reached the bottom of a 900px rail, and Wave D
    // owes four more. Areas are how somebody thinks about the job anyway:
    // "where do I change the VAT rate" is answered by *Money* long before it is
    // answered by reading eleven pane names.
    await open(tester, signedIn: owner);

    // MicroLabel uppercases.
    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('MONEY'), findsOneWidget);
    expect(find.text('BUYING'), findsOneWidget);
    expect(find.text('COMPLIANCE'), findsOneWidget);
    expect(find.text('SYSTEM'), findsOneWidget);

    // And no heading over nothing: this harness has no catalogue-authoring
    // repository, so the Menu area has no panes and must not appear.
    expect(find.text('MENU'), findsNothing);
  });

  testWidgets('every pane has an area, and every area shown has a pane', (
    tester,
  ) async {
    // `areaOf` is total over the enum so the first half cannot fail to compile;
    // this checks the second — a heading over a gap reads as a pane that failed
    // to load.
    final areas = managementAreasFor(
      admin: owner,
      authorsItsOwnCatalogue: true,
    );
    for (final (area, panes) in areas) {
      expect(panes, isNotEmpty, reason: area.name);
      for (final pane in panes) {
        expect(areaOf(pane), area, reason: pane.name);
      }
    }
    expect(
      areas.expand((a) => a.$2).toSet().length,
      ManagementPane.values.length,
      reason: 'an owner on an offline till has every pane, exactly once',
    );
  });

  testWidgets('picking one names the pane, and nothing else', (tester) async {
    final picked = await open(tester, signedIn: owner);

    await tester.tap(find.byKey(const Key('manage-menu-purchasing')));
    await tester.pumpAndSettle();

    expect(picked, [ManagementPane.purchasing]);
  });

  testWidgets('each row says what the pane is for', (tester) async {
    // "Purchasing" and "Receipt" are guesses until somebody reads what they do,
    // and the whole point is not having to open three panes to find one.
    await open(tester, signedIn: owner);
    expect(
      find.textContaining('Who you buy from'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the button again closes it', (tester) async {
    await open(tester, signedIn: owner);
    expect(find.byKey(const Key('manage-menu-staff')), findsOneWidget);

    await tester.tap(find.byKey(const Key('manage-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manage-menu-staff')), findsNothing);
  });
}
