import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/widgets/pos_widgets.dart';
import 'package:xorder_pos/core/config/app_version.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_about_pane.dart';
import 'package:xorder_pos/features/settings/about_dialog.dart';

import 'package:xorder_pos_test_support/fonts.dart';
import 'package:xorder_pos_test_support/fakes.dart';

const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

Future<void> _pump(
  WidgetTester tester, {
  required Widget body,
  String language = 'en',
}) async {
  tester.view
    ..physicalSize = const Size(1100, 800)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: fakeRepositoryOverrides());
  addTearDown(container.dispose);
  container
      .read(terminalProfileProvider.notifier)
      .apply(
        const TerminalProfile(
          branchName: 'Maadi',
          terminalName: 'POS-02',
          terminalId: 'e6c0f0a2-0000-4000-8000-000000000001',
        ),
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: Scaffold(body: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Settings › About XOrder, and the till's About dialog it was lifted from.
void main() {
  const s = EnStrings();

  setUpAll(loadPosFonts);

  testWidgets('the pane says what support asks: version, device, its id', (
    tester,
  ) async {
    await _pump(tester, body: const ManagementAboutPane(admin: _owner));

    expect(find.text(posAppVersion), findsOneWidget);
    expect(find.text('POS-02'), findsOneWidget);
    expect(find.text('e6c0f0a2-0000-4000-8000-000000000001'), findsOneWidget);
    // A pane has nothing to close.
    expect(find.text(s.close), findsNothing);
  });

  testWidgets("the till's dialog shows the same rows, and still closes", (
    tester,
  ) async {
    await _pump(
      tester,
      body: Builder(
        builder: (context) => PosButton(
          key: const Key('open'),
          label: 'open',
          onPressed: () => PosAboutDialog.show(context),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text(posAppVersion), findsOneWidget);
    expect(find.text('POS-02'), findsOneWidget);

    await tester.tap(find.text(s.close));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('in Arabic at 1100 px: the codes stay left to right', (
    tester,
  ) async {
    await _pump(
      tester,
      body: const ManagementAboutPane(admin: _owner),
      language: 'ar',
    );
    final version = tester.widget<SelectableText>(
      find.widgetWithText(SelectableText, posAppVersion),
    );
    expect(version.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });
}
