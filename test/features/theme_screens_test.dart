import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/features/start/start_screen.dart';

import '../support/fakes.dart';

/// A real screen, built twice.
///
/// `test/core/theme_test.dart` proves the palettes are sound and that the
/// theme reaches a `Builder`. This proves the thing that was actually broken:
/// that a SCREEN changes when the theme does. Every one of these colours used
/// to be a compile-time constant, so this test could not have passed at all —
/// both runs would have returned the same paint.
const _cloud = DeploymentConfig(
  mode: DeploymentMode.cloud,
  baseUrl: 'https://xorder.io',
  tenantSlug: 'mahsoub',
);

Future<Set<Color>> _paint(WidgetTester tester, Brightness brightness) async {
  tester.view
    ..physicalSize = const Size(1440, 1000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: fakeRepositoryOverrides());
  addTearDown(container.dispose);
  container.read(deploymentProvider.notifier).apply(_cloud);
  await tester.runAsync(() async {
    await container
        .read(licenceServiceProvider)
        .activate(deployment: _cloud, key: 'XORD-GOOD-1');
  });
  container.invalidate(licenceEntitlementProvider);
  container.read(brightnessProvider.notifier).apply(brightness);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          darkTheme: buildPosTheme(PosPalette.dark),
          themeMode: switch (ref.watch(brightnessProvider)) {
            Brightness.light => ThemeMode.light,
            Brightness.dark => ThemeMode.dark,
            null => ThemeMode.system,
          },
          home: StartScreen(
            onStart: () {},
            onManageLicence: () {},
            onReconfigure: () {},
            onManage: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return {
    for (final c in tester.widgetList<Container>(find.byType(Container)))
      if (c.color != null) c.color!,
    for (final b in tester.widgetList<ColoredBox>(find.byType(ColoredBox)))
      b.color,
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      if (t.style?.color != null) t.style!.color!,
  };
}

void main() {
  testWidgets('the start screen paints from the palette it is given', (
    tester,
  ) async {
    final light = await _paint(tester, Brightness.light);
    final dark = await _paint(tester, Brightness.dark);

    // Not merely different — each run must use ITS OWN palette's shell and
    // text, and none of the other's.
    expect(light, contains(PosPalette.light.shellRow));
    expect(light, contains(PosPalette.light.shellText));
    expect(light, isNot(contains(PosPalette.dark.shellRow)));

    expect(dark, contains(PosPalette.dark.shellRow));
    expect(dark, contains(PosPalette.dark.shellText));
    expect(dark, isNot(contains(PosPalette.light.shellRow)));

    // The accent is the tenant's brand and is the one thing that must NOT move.
    expect(light, contains(PosPalette.light.accent));
    expect(dark, contains(PosPalette.dark.accent));
  });
}
