import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/features/setup/presentation/welcome_screen.dart';

import '../support/fakes.dart';

const _desktop = Size(1440, 900);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required VoidCallback onOpen,
    Brightness platform = Brightness.dark,
  }) async {
    tester.view
      ..physicalSize = _desktop
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The controller writes the chosen brightness to the terminal's
          // config; the real store reaches for a directory this harness does
          // not have.
          terminalConfigStoreProvider.overrideWithValue(
            InMemoryTerminalConfigStore(),
          ),
        ],
        // ABOVE the app, because `ThemeMode.system` is resolved by MaterialApp
        // itself against the platform brightness it can see.
        child: MediaQuery(
          data: MediaQueryData(platformBrightness: platform),
          child: Consumer(
            // The same wiring `XorderPosApp` uses. The screen no longer picks
            // a ground of its own, so a harness that pinned one theme would be
            // testing nothing.
            builder: (context, ref, _) => MaterialApp(
              theme: buildPosTheme(PosPalette.light),
              darkTheme: buildPosTheme(PosPalette.dark),
              themeMode: switch (ref.watch(brightnessProvider)) {
                Brightness.light => ThemeMode.light,
                Brightness.dark => ThemeMode.dark,
                null => ThemeMode.system,
              },
              home: WelcomeScreen(onOpenSetup: onOpen),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The Scaffold's ground colour — what "light" and "dark" actually mean here.
  Color background(WidgetTester tester) =>
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!;

  testWidgets('shows the official mark, not a redrawn wordmark', (tester) async {
    await pump(tester, onOpen: () {});

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/icons/xorder_logo_official.png',
    );
    expect(find.text('This terminal has not been set up.'), findsOneWidget);
  });

  testWidgets('offers nothing that reveals the way in', (tester) async {
    await pump(tester, onOpen: () {});

    // The chord is the only way into setup, so whoever walks past an
    // unconfigured till in a public room must find nothing that starts it and
    // no hint that a chord exists. The brightness toggle is exempt on purpose
    // — it changes a colour and cannot configure anything — but it must stay
    // the ONLY pressable thing, which is what this asserts.
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.textContaining('Ctrl'), findsNothing);
    expect(find.textContaining('Shift'), findsNothing);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('pressing the toggle cannot open setup', (tester) async {
    var opened = false;
    await pump(tester, onOpen: () => opened = true);

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(opened, isFalse);
  });

  testWidgets('follows the machine when nobody has chosen', (tester) async {
    await pump(tester, onOpen: () {}, platform: Brightness.light);
    expect(background(tester), PosPalette.light.surface);

    await pump(tester, onOpen: () {}, platform: Brightness.dark);
    expect(background(tester), PosPalette.dark.surface);
  });

  testWidgets('the toggle flips away from what is on screen', (tester) async {
    // Starting from the system's dark, one tap must land on light. Toggling
    // off `state` instead of what is showing would make this first tap a
    // no-op, because "follow the system" holds no direction of its own.
    await pump(tester, onOpen: () {}, platform: Brightness.dark);
    expect(background(tester), PosPalette.dark.surface);

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(background(tester), PosPalette.light.surface);

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(background(tester), PosPalette.dark.surface);
  });

  testWidgets('Ctrl+Shift+S opens the setup wizard', (tester) async {
    var opened = false;
    await pump(tester, onOpen: () => opened = true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets('twelve taps on the mark open setup, for a till with no '
      'keyboard', (tester) async {
    var opened = false;
    await pump(tester, onOpen: () => opened = true);

    // Eleven is a child at the counter, not an installer.
    for (var i = 0; i < 11; i++) {
      await tester.tap(find.byType(Image));
    }
    await tester.pump();
    expect(opened, isFalse);

    await tester.tap(find.byType(Image));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('the plain key does nothing', (tester) async {
    var opened = false;
    await pump(tester, onOpen: () => opened = true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();

    expect(opened, isFalse);
  });
}
