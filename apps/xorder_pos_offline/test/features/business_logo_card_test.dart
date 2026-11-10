import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/business_logo.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/business_logo_card.dart';
import 'package:shared_module/features/start/start_screen.dart';

import 'package:xorder_pos_test_support/staff.dart';

/// XORD-021 — the logo card in Settings › General, and the start screen that
/// draws what it saves.
void main() {
  // A real 1×1 PNG, so the framework can decode it.
  final onePixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
  final picked = Uint8List.fromList([1, 2, 3, 4]);

  BusinessLogo stored(Uint8List bytes) =>
      BusinessLogo(bytes: bytes, mime: 'image/png', source: LogoSource.local);

  group('the card', () {
    Future<({_Recorder repo, List<int> reads})> pump(
      WidgetTester tester, {
      required PosStaff admin,
      bool platformOwned = false,
      BusinessLogo? current,
      Uint8List? choose,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _Recorder();
      final reads = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessLogoRepositoryProvider.overrideWithValue(
              platformOwned ? null : repo,
            ),
            businessLogoProvider.overrideWith((ref) async {
              reads.add(reads.length);
              return repo.logo ?? current;
            }),
          ],
          child: MaterialApp(
            theme: buildPosTheme(PosPalette.light),
            home: Scaffold(
              body: BusinessLogoCard(admin: admin, source: () async => choose),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (repo: repo, reads: reads);
    }

    testWidgets('with no logo it says so and offers to choose one', (
      tester,
    ) async {
      await pump(tester, admin: staffWith({PosCapability.brandingManage}));

      expect(find.byKey(const Key('business-logo-none')), findsOneWidget);
      expect(find.text(const EnStrings().businessLogoChoose), findsOneWidget);
      expect(find.byKey(const Key('business-logo-remove')), findsNothing);
    });

    testWidgets('choosing a picture saves it and re-reads what is shown', (
      tester,
    ) async {
      final r = await pump(
        tester,
        admin: staffWith({PosCapability.brandingManage}),
        choose: picked,
      );

      await tester.tap(find.byKey(const Key('business-logo-choose')));
      await tester.pumpAndSettle();

      expect(r.repo.saved, [picked]);
      expect(find.byKey(const Key('business-logo-note')), findsOneWidget);
      expect(
        r.reads.length,
        2,
        reason: 'the provider was invalidated and read again',
      );
    });

    testWidgets('cancelling the file dialog changes nothing', (tester) async {
      final r = await pump(
        tester,
        admin: staffWith({PosCapability.brandingManage}),
      );

      await tester.tap(find.byKey(const Key('business-logo-choose')));
      await tester.pumpAndSettle();

      expect(r.repo.saved, isEmpty);
      expect(find.byKey(const Key('business-logo-problem')), findsNothing);
    });

    testWidgets('a logo that is refused is explained in words, in the card', (
      tester,
    ) async {
      final r = await pump(
        tester,
        admin: staffWith({PosCapability.brandingManage}),
        choose: picked,
      );
      r.repo.refuse = const LogoRejected(LogoRefusal.tooLarge);

      await tester.tap(find.byKey(const Key('business-logo-choose')));
      await tester.pumpAndSettle();

      expect(find.text(const EnStrings().logoRefusedTooLarge), findsOneWidget);
      expect(
        r.reads.length,
        1,
        reason: 'nothing changed, so nothing is re-read',
      );
    });

    testWidgets('a file that cannot be opened is said, and does not throw', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessLogoRepositoryProvider.overrideWithValue(_Recorder()),
            businessLogoProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: buildPosTheme(PosPalette.light),
            home: Scaffold(
              body: BusinessLogoCard(
                admin: staffWith({PosCapability.brandingManage}),
                source: () async => throw const FileSystemExceptionStub(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('business-logo-choose')));
      await tester.pumpAndSettle();

      expect(
        find.text(const EnStrings().businessLogoReadFailed),
        findsOneWidget,
      );
    });

    testWidgets(
      'with a logo it offers to replace or remove, and remove works',
      (tester) async {
        final r = await pump(
          tester,
          admin: staffWith({PosCapability.brandingManage}),
          current: stored(onePixel),
        );

        expect(find.byKey(const Key('business-logo-preview')), findsOneWidget);
        expect(
          find.text(const EnStrings().businessLogoReplace),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('business-logo-remove')));
        await tester.pumpAndSettle();

        expect(r.repo.removed, 1);
        expect(find.byKey(const Key('business-logo-note')), findsOneWidget);
      },
    );

    testWidgets('without the key it can be seen and not changed', (
      tester,
    ) async {
      await pump(
        tester,
        admin: staffWith({PosCapability.settingsManage}),
        current: stored(onePixel),
      );

      expect(find.byKey(const Key('business-logo-preview')), findsOneWidget);
      expect(find.byKey(const Key('business-logo-choose')), findsNothing);
      expect(find.byKey(const Key('business-logo-remove')), findsNothing);
      expect(
        find.text(const EnStrings().businessLogoNeedPermission),
        findsOneWidget,
      );
    });

    testWidgets(
      'a cloud till shows the platform\'s logo and says where to change it',
      (tester) async {
        await pump(
          tester,
          admin: staffWith({PosCapability.brandingManage}),
          platformOwned: true,
          current: stored(onePixel),
        );

        expect(find.byKey(const Key('business-logo-preview')), findsOneWidget);
        expect(find.byKey(const Key('business-logo-choose')), findsNothing);
        expect(
          find.text(const EnStrings().businessLogoFromPlatform),
          findsOneWidget,
        );
      },
    );

    testWidgets('the Arabic card reads in Arabic', (tester) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessLogoRepositoryProvider.overrideWithValue(_Recorder()),
            businessLogoProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildPosTheme(PosPalette.light),
            home: Scaffold(
              body: BusinessLogoCard(
                admin: staffWith({PosCapability.brandingManage}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(const ArStrings().businessLogoTitle), findsOneWidget);
    });
  });

  group('the start screen logo', () {
    Future<void> pump(WidgetTester tester, BusinessLogo? logo) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [businessLogoProvider.overrideWith((ref) async => logo)],
          child: MaterialApp(
            theme: buildPosTheme(PosPalette.light),
            home: const Scaffold(body: Center(child: StartLogo())),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no logo: the XOrder mark alone, as before', (tester) async {
      await pump(tester, null);
      expect(find.byKey(const Key('start-xorder-logo')), findsOneWidget);
      expect(find.byKey(const Key('start-business-logo')), findsNothing);
    });

    testWidgets('a logo never replaces the mark: it sits under it, drawn from '
        'the stored bytes', (tester) async {
      await pump(tester, stored(onePixel));

      expect(find.byKey(const Key('start-xorder-logo')), findsOneWidget);
      expect(find.byKey(const Key('start-business-logo')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('start-business-logo'))).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(const Key('start-xorder-logo'))).dy -
              1,
        ),
        reason: 'under the XOrder mark, not over it or beside it',
      );
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('start-business-logo')),
          matching: find.byType(Image),
        ),
      );
      expect(image.image, isA<ResizeImage>());
    });

    testWidgets('bytes that will not decode leave the XOrder mark alone', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await pump(tester, stored(Uint8List.fromList([0, 1, 2, 3, 4, 5])));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('start-xorder-logo')),
        findsOneWidget,
        reason: 'a corrupt logo must never leave the start screen broken',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class FileSystemExceptionStub implements Exception {
  const FileSystemExceptionStub();
}

class _Recorder implements BusinessLogoRepository {
  final saved = <Uint8List>[];
  int removed = 0;
  AdminRefusal? refuse;
  BusinessLogo? logo;

  @override
  Future<AdminResult<BusinessLogo>> save(
    Uint8List bytes, {
    required PosStaff by,
  }) async {
    if (refuse != null) return AdminResult.refused(refuse!);
    saved.add(bytes);
    logo = BusinessLogo(
      bytes: bytes,
      mime: 'image/png',
      source: LogoSource.local,
    );
    return AdminResult.done(logo!);
  }

  @override
  Future<AdminResult<bool>> remove({required PosStaff by}) async {
    removed++;
    logo = null;
    return const AdminResult.done(true);
  }
}
