import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';
import 'package:xorder_pos/features/setup/presentation/setup_wizard.dart';

import '../support/fakes.dart';

/// Typing into the wizard must keep every character.
///
/// The bug: the fields rewrote their controller from the parent's value on any
/// rebuild where the two differed. The setters transform what they are given —
/// a PIN keeps only digits — and also churn other state, so a rebuild could
/// land carrying the value from BEFORE the last keystroke and write it back
/// over the field. The operator saw four dots for five digits and found out
/// only when the credential they typed correctly was refused.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    // The wizard is a desktop screen; the default test surface overflows it.
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
          home: SetupWizard(onFinished: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a PIN keeps every digit that was typed', (tester) async {
    final container = await pump(tester);
    container.read(setupProvider.notifier).state = container
        .read(setupProvider)
        .copyWith(
          step: SetupStep.account,
          deployment: const DeploymentConfig(mode: DeploymentMode.offline),
        );
    await tester.pumpAndSettle();

    final pin = find.byKey(const ValueKey('owner-pin:password'));
    expect(pin, findsOneWidget);

    // One at a time, pumping between — exactly the interleaving that used to
    // drop the first character.
    for (final digit in ['1', '2', '3', '4']) {
      await tester.enterText(
        pin,
        container.read(setupProvider).ownerPin + digit,
      );
      await tester.pumpAndSettle();
    }

    expect(container.read(setupProvider).ownerPin, '1234');
  });

  testWidgets('a database name keeps every character', (tester) async {
    final container = await pump(tester);
    container.read(setupProvider.notifier).state = container
        .read(setupProvider)
        .copyWith(
          step: SetupStep.deployment,
          deployment: const DeploymentConfig(mode: DeploymentMode.offline),
        );
    await tester.pumpAndSettle();

    // DATABASE NAME is the first field on this pane.
    final name = find.byType(TextFormField).first;

    await tester.enterText(name, 'pos_desktop_db');
    await tester.pumpAndSettle();

    expect(
      container.read(setupProvider).deployment.databaseName,
      'pos_desktop_db',
    );
  });
}
