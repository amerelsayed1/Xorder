import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/content_languages.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin_mode/admin_messages.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_appearance_pane.dart';

import 'package:xorder_pos_test_support/staff.dart';

/// XORD-005 — Settings › Language › Menu languages.
void main() {
  Future<_Recorder> pump(
    WidgetTester tester, {
    required PosStaff admin,
    bool platformOwned = false,
    ContentLanguages current = ContentLanguages.both,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final recorder = _Recorder();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogAdminRepositoryProvider.overrideWithValue(platformOwned ? null : recorder),
          contentLanguagesProvider.overrideWith((ref) async => current),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          home: Scaffold(body: ContentLanguagesCard(admin: admin)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return recorder;
  }

  testWidgets('somebody with settings.manage chooses, and it is saved', (tester) async {
    final recorder = await pump(tester, admin: staffWith({PosCapability.settingsManage}));

    await tester.tap(find.byKey(const Key('content-language-ar')));
    await tester.pumpAndSettle();

    expect(recorder.saved, [ContentLanguages.arabic]);
  });

  testWidgets('somebody without it can look and not change', (tester) async {
    final recorder = await pump(tester, admin: staffWith({PosCapability.operate}));

    await tester.tap(find.byKey(const Key('content-language-en')));
    await tester.pumpAndSettle();

    expect(recorder.saved, isEmpty);
  });

  testWidgets('a cloud till shows it and cannot change it', (tester) async {
    await pump(
      tester,
      admin: staffWith({PosCapability.settingsManage}),
      platformOwned: true,
      current: ContentLanguages.english,
    );

    await tester.tap(find.byKey(const Key('content-language-ar')));
    await tester.pumpAndSettle();

    // Nothing to record against: no repository is bound. It says why, and it
    // still shows the platform's choice.
    expect(find.text(const EnStrings().contentLanguagesFromPlatform), findsOneWidget);
  });

  testWidgets('a refusal is said where the choice was made', (tester) async {
    final recorder = await pump(tester, admin: staffWith({PosCapability.settingsManage}));
    recorder.refuse = true;

    await tester.tap(find.byKey(const Key('content-language-en')));
    await tester.pumpAndSettle();

    expect(recorder.saved, isEmpty);
    expect(
      find.text(AdminText.refusal(
        const EnStrings(),
        const NotPermitted(PosCapability.settingsManage),
      )),
      findsOneWidget,
    );
  });
}

class _Recorder implements CatalogAdminRepository {
  final saved = <ContentLanguages>[];
  bool refuse = false;

  @override
  Future<AdminResult<ContentLanguages>> saveContentLanguages(
    ContentLanguages languages, {
    required PosStaff by,
  }) async {
    if (refuse) {
      return const AdminResult.refused(NotPermitted(PosCapability.settingsManage));
    }
    saved.add(languages);
    return AdminResult.done(languages);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
