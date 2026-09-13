import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/config/terminal_config.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';

import '../support/fakes.dart';

/// The till ships two themes rather than one fixed palette.
///
/// What makes that true is not the palettes existing — it is that no screen
/// holds a colour of its own. Every token used to be a `static const` on
/// `PosColors`, which a widget read directly; a compile-time constant cannot
/// ask which theme is running, so the app had exactly one look no matter what
/// the machine or the operator asked for.
///
/// So these tests watch three things: that both palettes are legible, that the
/// theme actually reaches a widget, and that nothing has quietly gone back to
/// naming a fixed colour.
void main() {
  group('both palettes', () {
    test('carry a full set of distinct values', () {
      // The two must not be the same object with a different name, and the
      // accent must be the ONE thing they share — it is the tenant's brand.
      expect(PosPalette.light.brightness, Brightness.light);
      expect(PosPalette.dark.brightness, Brightness.dark);
      expect(PosPalette.dark.accent, PosPalette.light.accent);
      expect(PosPalette.dark.page, isNot(PosPalette.light.page));
      expect(PosPalette.dark.ink, isNot(PosPalette.light.ink));
      expect(PosPalette.dark.shell, isNot(PosPalette.light.shell));
    });

    test('keep the shell darker than the body it borders', () {
      // The shell is a separate region because it contrasts with the body. A
      // theme that let them meet in the middle would erase the layout, which
      // is the failure mode a hand-picked dark palette invites.
      expect(
        _luminance(PosPalette.dark.shell),
        lessThan(_luminance(PosPalette.dark.page)),
      );
      // And light runs the other way: the shell is the DARKER band there.
      expect(
        _luminance(PosPalette.light.shell),
        lessThan(_luminance(PosPalette.light.page)),
      );
    });

    test('are readable — every caption clears 4.5:1 on its own ground', () {
      // WCAG AA for body text. The dark palette is invented rather than
      // transcribed, so without this the first evidence of an unreadable
      // pairing would be a cashier squinting at a queue.
      const pairs = [
        ('ink on page', 'ink', 'page'),
        ('ink on surface', 'ink', 'surface'),
        // The label of a primary button against its fill. `ink` is a dark
        // colour in one palette and a near-white cream in the other, so what
        // is written on top of it cannot be a literal — this pair is what
        // holds the pale-slab button honest in both.
        ('onInk on ink', 'onInk', 'ink'),
        // And the confirm button. The dark palette lifts `ok` so it can be
        // READ on a dark ground, which makes it a pale fill — white on it is
        // the Take payment button at 2.1:1.
        ('onOk on ok', 'onOk', 'ok'),
        // The avatar initial. `accent` is the one colour that does not move
        // between palettes, and white on it is 2.2:1.
        ('onAccent on accent', 'onAccent', 'accent'),
        ('inkWarm on surface', 'inkWarm', 'surface'),
        ('body on page', 'body', 'page'),
        ('shellText on shell', 'shellText', 'shell'),
        ('shellText on shellCard', 'shellText', 'shellCard'),
        ('shellMuted on shell', 'shellMuted', 'shell'),
        ('shellLineMeta on shellCard', 'shellLineMeta', 'shellCard'),
        ('ok on okSoft', 'ok', 'okSoft'),
        ('danger on dangerSoft', 'danger', 'dangerSoft'),
        ('onlinePillText on onlinePillBg', 'onlinePillText', 'onlinePillBg'),
        ('offlinePillText on offlinePillBg', 'offlinePillText', 'offlinePillBg'),
      ];

      final failures = <String>[];
      for (final palette in PosPalette.values) {
        for (final (name, fg, bg) in pairs) {
          final r = _contrast(_token(palette, fg), _token(palette, bg));
          if (r < 4.5) {
            failures.add('${palette.name}: $name = ${r.toStringAsFixed(2)}');
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('the pairs the handoff sets below AA are named, not silently passed', () {
      // These come from `design_handoff_xorder_pos/README.md`, which the token
      // file is a transcription of. They are recorded here rather than fixed
      // because changing them means changing the handoff first — and recorded
      // rather than ignored so nobody reads the test above as "everything is
      // AA". Each is secondary text or a large-format CTA.
      const known = {
        ('light', 'muted on page'): 3.74,
        ('light', 'chipText on chipBg'): 4.08,
        ('light', 'warn on warnSoft'): 3.64,
      };

      expect(
        _contrast(PosPalette.light.muted, PosPalette.light.page),
        closeTo(known[('light', 'muted on page')]!, 0.05),
      );
      expect(
        _contrast(PosPalette.light.chipText, PosPalette.light.chipBg),
        closeTo(known[('light', 'chipText on chipBg')]!, 0.05),
      );
      expect(
        _contrast(PosPalette.light.warn, PosPalette.light.warnSoft),
        closeTo(known[('light', 'warn on warnSoft')]!, 0.05),
      );

      // The dark theme is ours, so it is held to the standard the light one
      // predates: each of the same three clears AA.
      expect(
        _contrast(PosPalette.dark.muted, PosPalette.dark.page),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(PosPalette.dark.chipText, PosPalette.dark.chipBg),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(PosPalette.dark.warn, PosPalette.dark.warnSoft),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('the theme', () {
    testWidgets('reaches a widget as the palette it was built from', (
      tester,
    ) async {
      for (final palette in PosPalette.values) {
        late PosPalette seen;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildPosTheme(palette),
            home: Builder(
              builder: (context) {
                seen = context.pos;
                return const SizedBox();
              },
            ),
          ),
        );
        // `AnimatedTheme` crosses over mid-flight, and the palette's own lerp
        // snaps at the halfway point — so read it once the switch has landed,
        // not on the first frame of it.
        await tester.pumpAndSettle();
        expect(seen, palette);
      }
    });

    testWidgets('falls back to light with no POS theme above it', (
      tester,
    ) async {
      // Mirrors `context.strings`: a dialog pushed onto a bare harness renders
      // rather than throwing.
      late PosPalette seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              seen = context.pos;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, PosPalette.light);
    });

    testWidgets('switches the whole tree when themeMode changes', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          terminalConfigStoreProvider.overrideWithValue(
            InMemoryTerminalConfigStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      late PosPalette seen;
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
              home: Builder(
                builder: (context) {
                  seen = context.pos;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );

      container.read(brightnessProvider.notifier).apply(Brightness.dark);
      await tester.pumpAndSettle();
      expect(seen, PosPalette.dark);

      container.read(brightnessProvider.notifier).apply(Brightness.light);
      await tester.pumpAndSettle();
      expect(seen, PosPalette.light);
    });
  });

  group('the brightness the operator chooses', () {
    const configured = SavedTerminalConfig(
      deployment: DeploymentConfig(
        mode: DeploymentMode.offline,
        databaseHost: '192.168.1.20',
      ),
      terminal: TerminalProfile(
        branchId: 13,
        branchName: 'Maadi',
        terminalName: 'Counter 1',
        terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
        restaurantId: 7,
        branchCode: 'MAA',
      ),
      languageCode: 'en',
    );

    test('starts as null, meaning follow the machine', () {
      final container = ProviderContainer(
        overrides: [
          terminalConfigStoreProvider.overrideWithValue(
            InMemoryTerminalConfigStore()..saved = configured,
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(brightnessProvider), isNull);
    });

    test('outlives the process that chose it', () async {
      final store = InMemoryTerminalConfigStore()..saved = configured;
      final container = ProviderContainer(
        overrides: [terminalConfigStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(brightnessProvider.notifier).apply(Brightness.dark);
      expect(container.read(brightnessProvider), Brightness.dark);

      await pumpEventQueue();
      expect(store.saved!.brightness, Brightness.dark);
      // The language and everything else the wizard wrote are untouched.
      expect(store.saved!.languageCode, 'en');
      expect(store.saved!.terminal.terminalId, configured.terminal.terminalId);

      final relaunched = ProviderContainer(
        overrides: [
          terminalBootProvider.overrideWithValue(
            TerminalBoot(config: store.saved),
          ),
        ],
      );
      addTearDown(relaunched.dispose);
      expect(relaunched.read(brightnessProvider), Brightness.dark);
    });

    test('can be handed back to the machine', () async {
      // Null is a value here, not an absence — "follow the machine" has to be
      // reachable again after choosing, or the first tap is permanent.
      final store = InMemoryTerminalConfigStore()
        ..saved = configured.copyWith(brightness: Brightness.dark);
      final container = ProviderContainer(
        overrides: [terminalConfigStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(brightnessProvider.notifier).apply(null);
      await pumpEventQueue();

      expect(container.read(brightnessProvider), isNull);
      expect(store.saved!.brightness, isNull);
    });

    test('survives a round trip through the config file', () {
      final json = configured.copyWith(brightness: Brightness.dark).toJson();
      expect(json['brightness'], 'dark');
      expect(SavedTerminalConfig.fromJson(json).brightness, Brightness.dark);

      // A value this build has never heard of reads as "follow the machine"
      // rather than sending the terminal back to the wizard.
      expect(
        SavedTerminalConfig.fromJson({...json, 'brightness': 'sepia'}).brightness,
        isNull,
      );
    });

    test('writes nothing on a terminal still inside the wizard', () async {
      final store = InMemoryTerminalConfigStore();
      final container = ProviderContainer(
        overrides: [terminalConfigStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(brightnessProvider.notifier).apply(Brightness.dark);
      await pumpEventQueue();

      expect(container.read(brightnessProvider), Brightness.dark);
      expect(store.saved, isNull);
      expect(store.writes, 0);
    });
  });

  test('no screen names a palette or a fixed colour of its own', () {
    // The guard that keeps this true. Reading the source rather than the
    // rendered tree, for the same reason the localisation suite does: a colour
    // only reaches a screen on the branch that builds it.
    //
    // Two things are forbidden in the widget layer:
    //
    // * naming a palette directly — `PosPalette.light.ink` renders the same
    //   shade in both themes, which is the exact bug this whole change undid;
    // * a raw `Color(0x…)` literal, which is a token nobody can retheme.
    final offenders = <String>[];

    for (final file in _widgetLayerFiles()) {
      final path = file.path;
      if (path.endsWith('core/ui/tokens.dart')) continue; // IS the palettes
      if (path.endsWith('core/ui/theme.dart')) continue; // builds from them
      // The receipt renders paper, and paper is white in a dark room too. The
      // three files that draw a printed slip pin one palette on purpose and
      // say so at the top. Named individually rather than by directory, so a
      // fourth file added to `features/receipt/` still has to argue its case
      // here rather than inheriting an exemption.
      if (path.endsWith('receipt/receipt_dialog.dart')) continue;
      if (path.endsWith('receipt/receipt_paper.dart')) continue;
      if (path.endsWith('receipt/reprint_dialog.dart')) continue;
      // The preview is the reprint's paper without the printing: the same
      // slip on the same desk grey, and just as white in a dark room.
      if (path.endsWith('receipt/receipt_preview_dialog.dart')) continue;
      // And the fourth argues its case here, as required. `receipt_raster.dart`
      // is not a screen: it paints the bitmap that goes down the wire to a
      // thermal head, which has exactly two states — a dot is burned or it is
      // not. Its black and white are not a palette choice that a theme could
      // ever have an opinion about; they are the two values the packer
      // thresholds against, and taking them from `context.pos` would make a
      // receipt printed at night come out inverted.
      if (path.endsWith('receipt/receipt_raster.dart')) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;

        if (RegExp(r'\bPosPalette\.(light|dark)\b').hasMatch(line)) {
          offenders.add('$path:${i + 1}  names a palette:  ${trimmed.trim()}');
        }
        for (final m in RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)').allMatches(line)) {
          if (_allowedRawColour(trimmed)) continue;
          offenders.add('$path:${i + 1}  raw colour:  ${m.group(0)}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A colour named in a screen cannot change with the theme:\n'
          '${offenders.join('\n')}',
    );
  });
  test('nothing writes white on an ink fill', () {
    // The bug that came back three times. `ink` is a near-white cream in the
    // dark palette, so `background: ink` under `Colors.white` is white on cream
    // at 1.06:1 — the primary action of a screen rendering as a pale blank slab
    // that reads as disabled. It was right in the light palette, which is why
    // it kept passing review.
    //
    // `onInk` is the colour that follows the theme. This is the guard that a
    // fill and its label cannot drift apart again.
    final offenders = <String>[];
    final fill = RegExp(r'(background|color):\s*((context\.)?(palette|pos))\.ink,');

    for (final file in _widgetLayerFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!fill.hasMatch(lines[i])) continue;

        // The label travels with the fill: the next line in every call site
        // this product has, and the one after it where a key intervenes.
        for (final j in [i + 1, i + 2]) {
          if (j < lines.length && lines[j].contains('Colors.white')) {
            offenders.add('${file.path}:${j + 1}  white on ink');
            break;
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A fill from the palette needs a label from the palette:\n'
          '${offenders.join('\n')}',
    );
  });

  test('nothing tints a control on hover', () {
    // A till is a touch surface first. On a touch screen there is no hover, so
    // a design that leans on it is invisible on the machine it was built for;
    // on the tills that do have a mouse, a tint following the pointer across a
    // dense cart makes rows appear to change as the hand moves over them.
    //
    // `buildPosTheme` sets `hoverColor: Colors.transparent`, which turns it off
    // for every Material control at once. This is the guard against a screen
    // quietly turning it back on for itself.
    final offenders = <String>[];

    for (final file in _widgetLayerFiles()) {
      // The theme IS the setting.
      if (file.path.endsWith('core/ui/theme.dart')) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        if (!trimmed.startsWith('hoverColor:')) continue;

        // Restating the global is allowed — it is a belt-and-braces on the
        // densest lists, and it cannot reintroduce anything.
        if (trimmed.contains('Colors.transparent')) continue;

        offenders.add('${file.path}:${i + 1}  $trimmed');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Hover is off product-wide. A control that wants a state on pointer '
          'entry wants selection or focus instead:\n${offenders.join("\n")}',
    );
  });
}

/// `Colors.white` and friends are not caught here — a literal `Color(0x…)` is
/// the shape that reads as a considered token and is not one.
bool _allowedRawColour(String line) =>
    // A translucent overlay is a shade of the ground beneath it, not a token:
    // it works against either palette by construction.
    line.contains('0x00') || RegExp(r'Color\(0x[0-3]').hasMatch(line);

Iterable<File> _widgetLayerFiles() => ['lib/features', 'lib/core/ui']
    .map(Directory.new)
    .where((d) => d.existsSync())
    .expand((d) => d.listSync(recursive: true))
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

Color _token(PosPalette p, String name) => switch (name) {
  'ink' => p.ink,
  'onInk' => p.onInk,
  'onOk' => p.onOk,
  'onAccent' => p.onAccent,
  'accent' => p.accent,
  'inkWarm' => p.inkWarm,
  'body' => p.body,
  'muted' => p.muted,
  'page' => p.page,
  'surface' => p.surface,
  'shell' => p.shell,
  'shellCard' => p.shellCard,
  'shellText' => p.shellText,
  'shellMuted' => p.shellMuted,
  'shellLineMeta' => p.shellLineMeta,
  'ok' => p.ok,
  'okSoft' => p.okSoft,
  'danger' => p.danger,
  'dangerSoft' => p.dangerSoft,
  'onlinePillText' => p.onlinePillText,
  'onlinePillBg' => p.onlinePillBg,
  'offlinePillText' => p.offlinePillText,
  'offlinePillBg' => p.offlinePillBg,
  _ => throw ArgumentError('unknown token $name'),
};

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
