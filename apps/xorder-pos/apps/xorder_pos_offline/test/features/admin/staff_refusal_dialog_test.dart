import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_staff_pane.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// XORD-010 — the "not saved" dialog on the Staff pane.
///
/// The dialog is a route of its own. Its Close button used to ask the *pane's*
/// context for the Navigator, so the moment the pane left the tree while a
/// refusal was still on screen — the cashier navigated away, the screen was
/// swapped for the lock screen — the tap threw "Null check operator used on a
/// null value" out of `StatefulElement.state`.
void main() {
  const strings = EnStrings();

  testWidgets('Close works after the pane that raised the dialog is gone', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
    final directory =
        container.read(staffDirectoryRepositoryProvider)
            as FakeStaffDirectoryRepository;
    final amer = directory.staff.firstWhere((p) => p.id == 1);

    final paneShown = ValueNotifier(true);
    addTearDown(paneShown.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: paneShown,
              builder: (_, shown, _) => shown
                  ? ManagementStaffPane(admin: amer)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Rana is deleted behind the pane's back, so disabling her is refused
    // ("edited elsewhere") and the refusal dialog opens.
    directory.staff.removeWhere((p) => p.id == 2);
    await tester.tap(
      // Rana is the second row; the first is the owner's own.
      find.text(strings.disable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text(strings.notSaved), findsOneWidget);

    // The pane goes while the dialog is still up.
    paneShown.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(ManagementStaffPane), findsNothing);
    expect(find.text(strings.notSaved), findsOneWidget);

    await tester.tap(find.text(strings.close));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(strings.notSaved), findsNothing);
  });

  testWidgets('Close dismisses the dialog and leaves the pane in place', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
    final directory =
        container.read(staffDirectoryRepositoryProvider)
            as FakeStaffDirectoryRepository;
    final amer = directory.staff.firstWhere((p) => p.id == 1);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Scaffold(body: ManagementStaffPane(admin: amer)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    directory.staff.removeWhere((p) => p.id == 2);
    await tester.tap(
      // Rana is the second row; the first is the owner's own.
      find.text(strings.disable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text(strings.notSaved), findsOneWidget);

    // Twice in a row: a double tap must not pop the pane's own route.
    await tester.tap(find.text(strings.close));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(strings.notSaved), findsNothing);
    expect(find.byType(ManagementStaffPane), findsOneWidget);
  });

  testWidgets('rapid repeated taps on Close are harmless', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
    final directory =
        container.read(staffDirectoryRepositoryProvider)
            as FakeStaffDirectoryRepository;
    final amer = directory.staff.firstWhere((p) => p.id == 1);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: Scaffold(body: ManagementStaffPane(admin: amer)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    directory.staff.removeWhere((p) => p.id == 2);
    await tester.tap(find.text(strings.disable).last);
    await tester.pumpAndSettle();
    expect(find.text(strings.notSaved), findsOneWidget);

    // Three taps with no frame between them: the second and third land on a
    // dialog that is already closing. None may throw, and none may pop the
    // pane's own route (there is none here, so a stray pop would be an error).
    final close = find.text(strings.close);
    await tester.tap(close, warnIfMissed: false);
    await tester.tap(close, warnIfMissed: false);
    await tester.tap(close, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(strings.notSaved), findsNothing);
    expect(find.byType(ManagementStaffPane), findsOneWidget);
  });
}
