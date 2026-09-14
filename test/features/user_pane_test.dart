import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/presentation/management_user_pane.dart';

import '../support/bundled_fonts.dart';
import '../support/fakes.dart';

const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);
// Everything by direct grant and no role: a real shape, and the count must
// still be what they hold.
const _granted = PosStaff(
  id: 4,
  name: 'Hady K.',
  username: 'hady',
  capabilities: {
    PosCapability.adminEnter,
    PosCapability.staffManage,
    PosCapability.purchaseManage,
  },
);

Future<void> _pump(
  WidgetTester tester, {
  required ManagementUserPane pane,
  String language = 'en',
}) async {
  tester.view
    ..physicalSize = const Size(1100, 800)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: fakeRepositoryOverrides(),
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
        home: Scaffold(body: pane),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// `matchRoot`: some keys sit on the Text itself, not on a box around it.
Finder _in(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f, matchRoot: true);

/// Settings › User: who is in, what they hold, and the way out.
void main() {
  const s = EnStrings();

  setUpAll(loadBundledFonts);

  testWidgets('names the person, their username and their role, and counts '
      'what they hold', (tester) async {
    await _pump(tester, pane: ManagementUserPane(admin: _owner, onExit: () {}));

    expect(_in('user-name', find.text('Amer M.')), findsOneWidget);
    expect(_in('user-username', find.text('amer')), findsOneWidget);
    expect(
      _in('user-role', find.text(FakeSessionRepository.owner.displayName('en'))),
      findsOneWidget,
    );
    expect(
      _in(
        'user-permissions',
        find.text('${_owner.effectiveCapabilities.length}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('with no role, says so — and counts the direct grants', (
    tester,
  ) async {
    await _pump(
      tester,
      pane: ManagementUserPane(admin: _granted, onExit: () {}),
    );
    expect(_in('user-role', find.text(s.userNoRole)), findsOneWidget);
    expect(_in('user-permissions', find.text('3')), findsOneWidget);
  });

  testWidgets('offers no PIN change, because the app has none to offer', (
    tester,
  ) async {
    await _pump(tester, pane: ManagementUserPane(admin: _owner, onExit: () {}));
    expect(find.textContaining('PIN'), findsNothing);
    expect(find.text(s.resetPin), findsNothing);
  });

  testWidgets('leads to Roles only when it is given somewhere to go', (
    tester,
  ) async {
    await _pump(tester, pane: ManagementUserPane(admin: _owner, onExit: () {}));
    expect(find.byKey(const Key('user-see-roles')), findsNothing);

    var opened = 0;
    await _pump(
      tester,
      pane: ManagementUserPane(
        admin: _owner,
        onExit: () {},
        onOpenRoles: () => opened++,
      ),
    );
    await tester.tap(find.byKey(const Key('user-see-roles')));
    expect(opened, 1);
  });

  testWidgets('Exit Admin Mode hands back to the shell', (tester) async {
    var exited = 0;
    await _pump(
      tester,
      pane: ManagementUserPane(admin: _owner, onExit: () => exited++),
    );
    await tester.tap(find.byKey(const Key('user-exit')));
    await tester.pumpAndSettle();
    expect(exited, 1);
  });

  testWidgets('in Arabic at 1100 px: Arabic words, the username left to '
      'right, nothing overflows', (tester) async {
    await _pump(
      tester,
      pane: ManagementUserPane(admin: _owner, onExit: () {}),
      language: 'ar',
    );
    const ar = ArStrings();
    expect(find.text(ar.userExitHint), findsOneWidget);
    expect(find.text(ar.exitAdminMode), findsOneWidget);
    final username = tester.widget<Text>(_in('user-username', find.text('amer')));
    expect(username.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });
}
