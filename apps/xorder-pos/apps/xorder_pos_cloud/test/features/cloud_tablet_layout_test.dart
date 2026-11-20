import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/password_sign_in.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:xorder_pos_cloud/features/cloud_back_office_screen.dart';
import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

/// tablet-cloud-onboarding, Stage 6 (AC-10, AC-11): the cloud till's
/// Management screen, with Change business open and the keyboard up, at tablet
/// sizes in both orientations and both languages. The confirm button must stay
/// reachable and nothing may overflow.
class _Platform implements PlatformPasswordCheck {
  @override
  Future<PasswordVerdict> verify({
    required String username,
    required String password,
  }) async => PasswordVerdict.rejected;
}

void main() {
  setUpAll(loadPosFonts);

  const sizes = <(String, Size)>[
    ('1280x800', Size(1280, 800)),
    ('800x1280', Size(800, 1280)),
    ('1200x750', Size(1200, 750)),
    ('750x1200', Size(750, 1200)),
    ('1024x600', Size(1024, 600)),
    ('600x1024', Size(600, 1024)),
  ];

  const owner = PosStaff(
    id: 1,
    name: 'Amer',
    username: 'amer',
    role: FakeSessionRepository.owner,
  );

  for (final (label, size) in sizes) {
    for (final locale in const ['en', 'ar']) {
      testWidgets('Management, Change business open, keyboard up, at $label, '
          '$locale', (tester) async {
        final keyboard = size.height > size.width ? 420.0 : 320.0;
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1.0
          ..viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.reset);

        final container = ProviderContainer(
          overrides: [
            ...fakeRepositoryOverrides(english: false),
            platformPasswordCheckProvider.overrideWithValue(_Platform()),
          ],
        );
        addTearDown(container.dispose);
        container.read(signedInStaffProvider.notifier).signIn(owner);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: Locale(locale),
              theme: buildPosTheme(),
              localizationsDelegates: const [
                AppLocalizations(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: CloudBackOfficeScreen(onClose: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.byKey(const Key('change-business')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('change-business')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final confirm = find.byKey(const Key('change-business-confirm'));
        await tester.ensureVisible(confirm);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(confirm).bottom,
          lessThanOrEqualTo(size.height - keyboard + 0.5),
          reason: 'Confirm must be reachable above the keyboard',
        );
      });
    }
  }
}
