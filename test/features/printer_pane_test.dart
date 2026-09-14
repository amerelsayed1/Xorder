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
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/presentation/management_printer_pane.dart';
import 'package:xorder_pos/features/settings/printer_settings_dialog.dart';

import '../support/fonts.dart';
import '../support/fakes.dart';

// The machine and nothing of the business — through a role, as a real one.
const _keeper = PosStaff(
  id: 5,
  name: 'Salma T.',
  username: 'salma',
  role: PosRole(
    id: 5,
    code: 'keeper',
    nameEn: 'Keeper',
    capabilities: {PosCapability.adminEnter, PosCapability.terminalManage},
  ),
);
// Through Admin Mode's door, and not trusted with the machine.
const _doorOnly = PosStaff(
  id: 9,
  name: 'Nour S.',
  username: 'nour',
  role: PosRole(
    id: 9,
    code: 'door',
    nameEn: 'Door',
    capabilities: {PosCapability.adminEnter},
  ),
);

const _saved = SavedTerminalConfig(
  languageCode: 'en',
  deployment: DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseHost: '192.168.1.20',
  ),
  terminal: TerminalProfile(
    branchName: 'Maadi',
    terminalName: 'Counter 1',
    restaurantId: 7,
  ),
);

Future<InMemoryTerminalConfigStore> _pump(
  WidgetTester tester, {
  required Widget body,
  String language = 'en',
}) async {
  tester.view
    ..physicalSize = const Size(1100, 800)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = InMemoryTerminalConfigStore()..saved = _saved;
  final container = ProviderContainer(
    overrides: [
      hardwarePortsProvider.overrideWithValue(FakeHardwarePorts()),
      terminalConfigStoreProvider.overrideWithValue(store),
      printerConfigProvider.overrideWith(() => _Fixed(PrinterConfig.none)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        theme: buildPosTheme(),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// Settings › Printer & cash drawer: the till's dialog, hosted as a pane.
void main() {
  const s = EnStrings();

  setUpAll(loadPosFonts);

  testWidgets('a printer chosen in the pane is the printer after a restart', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      body: const ManagementPrinterPane(admin: _keeper),
    );

    // A pane has nothing to cancel out of.
    expect(find.text(s.cancel), findsNothing);

    await tester.tap(find.byKey(const Key('printer-find')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('printer-EPSON TM-T20III')));
    await tester.tap(find.byKey(const Key('printer-paper-384')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('printer-save')));
    await tester.pump();

    expect(store.saved!.printer.name, 'EPSON TM-T20III');
    expect(store.saved!.printer.paperWidthDots, PrinterConfig.width58mm);
    // Said, and still open — the pane is where it was.
    expect(find.text(s.printerSaved), findsOneWidget);
    expect(find.byKey(const Key('printer-pane')), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('without terminal.manage it says whose it is, and offers '
      'nothing', (tester) async {
    await _pump(tester, body: const ManagementPrinterPane(admin: _doorOnly));

    expect(find.text(s.printerNotYours), findsOneWidget);
    expect(find.byKey(const Key('printer-find')), findsNothing);
    expect(find.byKey(const Key('printer-save')), findsNothing);
  });

  testWidgets('in Arabic at 1100 px, nothing overflows', (tester) async {
    await _pump(
      tester,
      body: const ManagementPrinterPane(admin: _keeper),
      language: 'ar',
    );
    expect(find.text(const ArStrings().printerSettingsTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the till's menu still opens the dialog, with Cancel, and "
      'Save still closes it', (tester) async {
    final store = await _pump(
      tester,
      body: Builder(
        builder: (context) => PosButton(
          key: const Key('open'),
          label: 'open',
          onPressed: () => PrinterSettingsDialog.show(context),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text(s.cancel), findsOneWidget);

    await tester.tap(find.byKey(const Key('printer-paper-384')));
    await tester.tap(find.byKey(const Key('printer-save')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(store.saved!.printer.paperWidthDots, PrinterConfig.width58mm);
  });
}

class _Fixed extends PrinterConfigController {
  _Fixed(this._initial);

  final PrinterConfig _initial;

  @override
  PrinterConfig build() => _initial;
}
