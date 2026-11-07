import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/config/printer_config.dart';
import 'package:xorder_pos/core/config/terminal_config.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/features/settings/printer_settings_dialog.dart';

import '../support/fakes.dart';

/// Choosing the receipt printer without re-running setup.
///
/// The wizard was the only place a printer could be picked, so a swapped
/// printer meant resetting the till. The claim worth testing is the second half
/// of "change it here": that the choice is still the choice after a restart.
void main() {
  const strings = EnStrings();

  const saved = SavedTerminalConfig(
    languageCode: 'en',
    deployment: DeploymentConfig(
      mode: DeploymentMode.offline,
      databaseHost: '192.168.1.20',
    ),
    terminal: TerminalProfile(
      branchId: 13,
      branchName: 'Maadi',
      terminalName: 'Counter 1',
      terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
      businessId: 7,
    ),
  );

  Future<(ProviderContainer, InMemoryTerminalConfigStore)> open(
    WidgetTester tester, {
    PrinterConfig current = PrinterConfig.none,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = InMemoryTerminalConfigStore()..saved = saved;
    final container = ProviderContainer(
      overrides: [
        hardwarePortsProvider.overrideWithValue(FakeHardwarePorts()),
        terminalConfigStoreProvider.overrideWithValue(store),
        printerConfigProvider.overrideWith(() => _Fixed(current)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PrinterSettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, store);
  }

  testWidgets('a printer chosen here is the printer after a restart', (
    tester,
  ) async {
    final (container, store) = await open(tester);

    await tester.tap(find.byKey(const Key('printer-find')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('printer-EPSON TM-T20III')));
    await tester.tap(find.byKey(const Key('printer-paper-384')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('printer-save')));
    await tester.pumpAndSettle();

    const chosen = PrinterConfig(
      name: 'EPSON TM-T20III',
      paperWidthDots: PrinterConfig.width58mm,
    );
    // In use now…
    expect(container.read(printerConfigProvider).name, chosen.name);
    expect(
      container.read(printerConfigProvider).paperWidthDots,
      chosen.paperWidthDots,
    );
    // …and written where the next launch reads it from.
    expect(store.saved!.printer.name, chosen.name);
    expect(store.saved!.printer.paperWidthDots, chosen.paperWidthDots);
    // Nothing else in the file was touched.
    expect(store.saved!.terminal.terminalName, 'Counter 1');
  });

  testWidgets('with no printer it says so, and there is nothing to test', (
    tester,
  ) async {
    await open(tester);

    expect(find.text(strings.printerNoneChosen), findsOneWidget);
    final test = tester.widget<InkWell>(
      find
          .descendant(
            of: find.byKey(const Key('printer-test')),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(test.onTap, isNull);
  });

  testWidgets('the saved printer is offered before any scan', (tester) async {
    // Switched off today, or on another floor: still the one this till uses,
    // and still choosable without finding it again first.
    await open(tester, current: const PrinterConfig(name: '10.20.30.40:9100'));
    expect(find.byKey(const Key('printer-10.20.30.40:9100')), findsOneWidget);
  });

  group('print logo on receipts (XORD-024)', () {
    IconData tick(WidgetTester tester) => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('printer-logo')),
            matching: find.byType(Icon),
          ),
        )
        .icon!;

    testWidgets('is on by default', (tester) async {
      await open(tester);

      expect(find.text(strings.printerPrintLogo), findsOneWidget);
      expect(tick(tester), Icons.check_box);
    });

    testWidgets('turned off, it is off in use and after a restart', (
      tester,
    ) async {
      final (container, store) = await open(tester);

      await tester.tap(find.byKey(const Key('printer-logo')));
      await tester.pump();
      expect(tick(tester), Icons.check_box_outline_blank);
      await tester.tap(find.byKey(const Key('printer-save')));
      await tester.pumpAndSettle();

      expect(container.read(printerConfigProvider).printLogo, isFalse);
      expect(store.saved!.printer.printLogo, isFalse);
    });

    testWidgets('survives choosing a printer and a paper width afterwards', (
      tester,
    ) async {
      // The form used to rebuild the whole config from the two fields it knew
      // about, so every new field went back to its default on the next tap.
      final (container, store) = await open(tester);

      await tester.tap(find.byKey(const Key('printer-logo')));
      await tester.tap(find.byKey(const Key('printer-find')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('printer-EPSON TM-T20III')));
      await tester.tap(find.byKey(const Key('printer-paper-384')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('printer-save')));
      await tester.pumpAndSettle();

      expect(container.read(printerConfigProvider).printLogo, isFalse);
      expect(store.saved!.printer.printLogo, isFalse);
      expect(store.saved!.printer.paperWidthDots, PrinterConfig.width58mm);
    });

    testWidgets('a saved off is shown as off when the pane opens', (
      tester,
    ) async {
      await open(
        tester,
        current: const PrinterConfig(name: 'X', printLogo: false),
      );

      expect(tick(tester), Icons.check_box_outline_blank);
    });

    test('the file reads and writes it, and an old file reads as on', () {
      expect(const PrinterConfig().printLogo, isTrue);
      expect(
        PrinterConfig.fromJson(const PrinterConfig(printLogo: false).toJson())
            .printLogo,
        isFalse,
      );
      // Written by a build that did not know the key, or by hand.
      expect(PrinterConfig.fromJson(const {'name': 'X'}).printLogo, isTrue);
      expect(
        PrinterConfig.fromJson(const {'print_logo': 'no'}).printLogo,
        isTrue,
      );
      expect(
        PrinterConfig.fromJson(const {'print_logo': null}).printLogo,
        isTrue,
      );
      expect(
        const PrinterConfig(printLogo: false).copyWith(name: 'Y').printLogo,
        isFalse,
      );
      expect(const PrinterConfig().toJson()['print_logo'], isTrue);
    });
  });
}

class _Fixed extends PrinterConfigController {
  _Fixed(this._initial);

  final PrinterConfig _initial;

  @override
  PrinterConfig build() => _initial;
}
