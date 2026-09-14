import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos/features/admin/presentation/management_terminal_pane.dart';

import '../support/fakes.dart';

/// The Terminal pane, and the one button on it.
///
/// Resetting a till used to sit on the start screen, a tap away from whoever
/// opens the shift. These tests are about what moving it bought: it is only
/// there for somebody holding `terminal.manage`, it still refuses while a
/// drawer is uncounted, and it still sends the till to setup when it runs.
void main() {
  const strings = EnStrings();

  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: SystemRoles.ownerCode,
      nameEn: 'Owner',
      capabilities: SystemRoles.owner,
    ),
  );
  const manager = PosStaff(
    id: 2,
    name: 'Nour A.',
    role: PosRole(
      id: 2,
      code: SystemRoles.managerCode,
      nameEn: 'Manager',
      capabilities: SystemRoles.manager,
    ),
  );

  Future<({ProviderContainer container, List<String> events})> open(
    WidgetTester tester, {
    bool shiftOpen = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
    container.read(setupCompleteProvider.notifier).markComplete();
    if (shiftOpen) {
      await container
          .read(shiftRepositoryProvider)
          .open(by: owner, openingFloat: Money.zero);
    }

    final events = <String>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: ManagementScreen(
            onClose: () {},
            onReconfigure: () => events.add('reconfigure'),
            initialPane: ManagementPane.terminal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Through Admin Mode's door, as the owner.
    await enterAdminMode(tester);

    return (container: container, events: events);
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(Dialog), matching: find.text(text));

  testWidgets('with no shift open, confirming resets the till and goes to '
      'setup', (tester) async {
    final app = await open(tester);
    expect(find.byType(ManagementTerminalPane), findsOneWidget);

    await tester.tap(find.byKey(const Key('terminal-reset')));
    await tester.pumpAndSettle();

    // What is and is not touched is said before anything is.
    expect(find.text(strings.resetTerminalTitle), findsOneWidget);
    expect(app.container.read(setupCompleteProvider), isTrue);

    await tester.tap(inDialog(strings.resetTerminalConfirm));
    await tester.pumpAndSettle();

    expect(app.container.read(setupCompleteProvider), isFalse);
    expect(app.events, ['reconfigure']);
  });

  testWidgets('cancelling touches nothing', (tester) async {
    final app = await open(tester);

    await tester.tap(find.byKey(const Key('terminal-reset')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(strings.cancel));
    await tester.pumpAndSettle();

    expect(app.container.read(setupCompleteProvider), isTrue);
    expect(app.events, isEmpty);
  });

  testWidgets('with a shift open it refuses, and says why', (tester) async {
    // The drawer has not been counted. A till that dropped its database
    // address now would leave that count with nowhere to go.
    final app = await open(tester, shiftOpen: true);

    await tester.tap(find.byKey(const Key('terminal-reset')));
    await tester.pumpAndSettle();

    expect(find.text(strings.resetTerminalShiftOpen), findsOneWidget);
    expect(find.text(strings.resetTerminalTitle), findsNothing);
    expect(app.container.read(setupCompleteProvider), isTrue);
    expect(app.events, isEmpty);
  });

  group('who may see it at all', () {
    test('an owner does', () {
      final panes = managementPanesFor(
        admin: owner,
        authorsItsOwnCatalogue: true,
      );
      expect(panes, contains(ManagementPane.terminal));
    });

    test('a manager does not, because terminal.manage is the owner\'s', () {
      // Critical, and deliberately left out of `SystemRoles.manager`. A
      // manager still reaches Management — they hold `staff.manage` — so the
      // pane has to be absent rather than the screen.
      expect(manager.can(PosCapability.staffManage), isTrue);
      expect(manager.can(PosCapability.terminalManage), isFalse);

      final panes = managementPanesFor(
        admin: manager,
        authorsItsOwnCatalogue: true,
      );
      expect(panes, isNot(contains(ManagementPane.terminal)));
      expect(panes, contains(ManagementPane.staff));
    });

    test('and it lives in System, beside Backup', () {
      expect(tabOf(ManagementPane.terminal), BackOfficeTab.system);
      expect(tabOf(ManagementPane.backup), BackOfficeTab.system);
    });
  });
}
