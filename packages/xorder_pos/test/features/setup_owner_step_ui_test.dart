import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';
import 'package:xorder_pos/features/setup/presentation/setup_wizard.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// Setup step 4 for an offline first install, as two screens
/// (pos-setup-owner-step): what each shows, what its one button does, and that
/// nothing on either asks an owner a technician's question.
void main() {
  late ProviderContainer container;

  final claims = LicenseClaims(
    licenseId: 'lic',
    tenantSlug: 'mahsoub',
    tenantName: 'Mahsoub Grill',
    issuedAt: DateTime.utc(2026, 1, 1),
    expiresAt: DateTime.utc(2027, 1, 1),
    modes: const {DeploymentMode.offline},
  );

  Future<void> pump(
    WidgetTester tester, {
    String language = 'en',
    Size size = const Size(1440, 900),
    OwnerPage page = OwnerPage.databaseAccess,
    bool bootstrapped = false,
    String admin = '',
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    container = ProviderContainer(
      overrides: fakeRepositoryOverrides(english: language == 'en'),
    );
    addTearDown(container.dispose);
    container.read(localeProvider.notifier).apply(language);
    container.read(setupProvider.notifier).state = container
        .read(setupProvider)
        .copyWith(
          step: SetupStep.account,
          deployment: const DeploymentConfig(
            mode: DeploymentMode.offline,
            databaseHost: '127.0.0.1',
            databasePort: 1,
          ),
          claims: claims,
          ownerPage: page,
          adminDatabasePassword: admin,
          bootstrapped: bootstrapped,
          bootstrapReport: bootstrapped ? 'Created the database.' : null,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          theme: buildPosTheme(),
          // As the real app wires it: the screens look their strings up through
          // Localizations, so an Arabic test names the locale.
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SetupWizard(onFinished: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SetupDraft draft() => container.read(setupProvider);

  final primary = find.byKey(const Key('setup-primary'));
  final pageA = find.byKey(const Key('first-install-database-access'));
  final pageB = find.byKey(const Key('first-install-owner-account'));

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pumpAndSettle();
  }

  /// Everything the person can read on the screen.
  String screenText(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      if (t.data != null) t.data!,
  ].join('\n');

  bool primaryEnabled(WidgetTester tester) =>
      tester
          .widget<InkWell>(
            find.descendant(of: primary, matching: find.byType(InkWell)).first,
          )
          .onTap !=
      null;

  group('the first screen: database access', () {
    testWidgets('asks for one password, and says in plain words why', (
      tester,
    ) async {
      await pump(tester);

      expect(pageA, findsOneWidget);
      expect(pageB, findsNothing);
      expect(find.text('Database access'), findsOneWidget);
      expect(find.textContaining('used once'), findsOneWidget);
      expect(find.textContaining('not saved'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin:password')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin:toggle')), findsOneWidget);
      expect(find.text('Account: pos_admin'), findsOneWidget);
      // Nothing about the owner yet.
      expect(find.byKey(const ValueKey('owner-pin:password')), findsNothing);
    });

    testWidgets('one primary button, and no "Build the database" beside it', (
      tester,
    ) async {
      await pump(tester);

      expect(primary, findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Build the database'), findsNothing);
      // Even empty: a local PostgreSQL that trusts this machine has no password.
      expect(primaryEnabled(tester), isTrue);
      expect(find.textContaining('leave it empty'), findsOneWidget);
    });

    testWidgets('Continue goes to the owner\'s screen, in the same step', (
      tester,
    ) async {
      await pump(tester, admin: 'secret');

      await tester.tap(primary);
      await tester.pumpAndSettle();

      expect(pageB, findsOneWidget);
      expect(pageA, findsNothing);
      expect(draft().step, SetupStep.account);
      expect(find.text('Create the owner account'), findsOneWidget);
      expect(find.text('Create database and continue'), findsOneWidget);
    });

    testWidgets('the password can be shown and hidden again', (tester) async {
      await pump(tester);
      await type(tester, 'admin:password', 'secret');

      bool obscured() => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('admin:password')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText;

      expect(obscured(), isTrue);
      await tester.tap(find.byKey(const ValueKey('admin:toggle')));
      await tester.pumpAndSettle();
      expect(obscured(), isFalse);
      await tester.tap(find.byKey(const ValueKey('admin:toggle')));
      await tester.pumpAndSettle();
      expect(obscured(), isTrue);
    });
  });

  group('the second screen: the owner', () {
    testWidgets('names, username, PIN and the PIN again', (tester) async {
      await pump(tester, page: OwnerPage.ownerAccount, admin: 'secret');

      expect(find.text('OWNER NAME'), findsOneWidget);
      expect(find.text('USERNAME'), findsOneWidget);
      expect(find.text('SIGN-IN PIN'), findsOneWidget);
      expect(find.text('CONFIRM PIN'), findsOneWidget);
      expect(find.byKey(const ValueKey('owner-pin:toggle')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('owner-pin-confirm:toggle')),
        findsOneWidget,
      );
      expect(find.textContaining('Exactly 4 digits'), findsOneWidget);
      expect(find.text('0 / 4'), findsOneWidget);
    });

    testWidgets('the count follows the typing, and never goes past four', (
      tester,
    ) async {
      await pump(tester, page: OwnerPage.ownerAccount);

      await type(tester, 'owner-pin:password', '12');
      expect(find.text('2 / 4'), findsOneWidget);
      await type(tester, 'owner-pin:password', '123456');
      expect(find.text('4 / 4'), findsOneWidget);
      expect(draft().ownerPin, '1234');
    });

    testWidgets('a PIN typed differently the second time is said at once, and '
        'pressing the button builds nothing', (tester) async {
      await pump(tester, page: OwnerPage.ownerAccount, admin: 'secret');
      await type(tester, 'Owner name:false', 'Rana');
      await type(tester, 'Username:false', 'owner');
      await type(tester, 'owner-pin:password', '1234');
      await type(tester, 'owner-pin-confirm:password', '1235');

      expect(
        find.byKey(const ValueKey('owner-pin-confirm:error')),
        findsOneWidget,
      );
      expect(find.text('The two PINs are not the same.'), findsWidgets);

      await tester.tap(primary);
      await tester.pumpAndSettle();

      expect(draft().bootstrapped, isFalse);
      expect(pageB, findsOneWidget);
    });

    testWidgets('the same PIN twice raises no complaint', (tester) async {
      await pump(tester, page: OwnerPage.ownerAccount);
      await type(tester, 'owner-pin:password', '1234');
      await type(tester, 'owner-pin-confirm:password', '1234');

      expect(
        find.byKey(const ValueKey('owner-pin-confirm:error')),
        findsNothing,
      );
    });

    testWidgets('Back goes to the first screen with everything still typed', (
      tester,
    ) async {
      await pump(tester, page: OwnerPage.ownerAccount, admin: 'secret');
      await type(tester, 'Owner name:false', 'Rana');

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(pageA, findsOneWidget);
      expect(draft().ownerName, 'Rana');
      expect(draft().adminDatabasePassword, 'secret');
    });
  });

  group('the PIN fields can be shown too', () {
    for (final field in ['owner-pin', 'owner-pin-confirm']) {
      testWidgets('$field: Show, then Hide', (tester) async {
        await pump(tester, page: OwnerPage.ownerAccount);
        await type(tester, '$field:password', '1234');

        bool obscured() => tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(ValueKey('$field:password')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText;

        expect(obscured(), isTrue);
        await tester.tap(find.byKey(ValueKey('$field:toggle')));
        await tester.pumpAndSettle();
        expect(obscured(), isFalse);
        await tester.tap(find.byKey(ValueKey('$field:toggle')));
        await tester.pumpAndSettle();
        expect(obscured(), isTrue);
      });
    }
  });

  group('when the administrator account cannot be reached', () {
    testWidgets('the first screen comes back with the error, and the password '
        'is still typed', (tester) async {
      await pump(tester, page: OwnerPage.ownerAccount, admin: 'wrong');
      await type(tester, 'Owner name:false', 'Rana');
      await type(tester, 'Username:false', 'owner');
      await type(tester, 'owner-pin:password', '1234');
      await type(tester, 'owner-pin-confirm:password', '1234');

      // A real, refused connection (the port is closed), so the clock has to be
      // the real one.
      await tester.runAsync(() async {
        await tester.tap(primary);
        for (var i = 0; i < 100 && draft().busy == false; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        for (var i = 0; i < 300 && draft().busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();

      expect(pageA, findsOneWidget);
      expect(draft().error, isNotNull);
      expect(draft().bootstrapped, isFalse);
      expect(draft().adminDatabasePassword, 'wrong');
      expect(draft().ownerName, 'Rana');
    });
  });

  group('once the database exists', () {
    testWidgets('it says so, and the same button is Continue again', (
      tester,
    ) async {
      await pump(
        tester,
        page: OwnerPage.ownerAccount,
        bootstrapped: true,
        admin: 'secret',
      );

      expect(find.byKey(const Key('first-install-done')), findsOneWidget);
      expect(find.text('Database created.'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Create database and continue'), findsNothing);
      expect(primaryEnabled(tester), isTrue);
    });
  });

  group('words', () {
    for (final language in ['en', 'ar']) {
      testWidgets('neither screen mentions a hash, a role or "four to twelve" '
          '($language)', (tester) async {
        await pump(tester, language: language, admin: 'secret');
        final first = screenText(tester);
        await tester.tap(primary);
        await tester.pumpAndSettle();
        final second = screenText(tester);

        for (final text in [first, second]) {
          expect(text, isNot(contains('PBKDF2')));
          expect(text, isNot(contains('four to twelve')));
          expect(text, isNot(contains('أربعة إلى اثني عشر')));
          expect(text, isNot(contains('First person')));
          expect(text, isNot(contains('Their PIN')));
          expect(text, isNot(contains('أول شخص')));
        }
      });
    }

    testWidgets('the PIN sentence says exactly four, in Arabic too', (
      tester,
    ) async {
      await pump(tester, language: 'ar', page: OwnerPage.ownerAccount);

      expect(find.textContaining('بالضبط 4 أرقام'), findsOneWidget);
      expect(find.text('0 / 4'), findsOneWidget);
    });

    testWidgets('both screens read in Arabic', (tester) async {
      await pump(tester, language: 'ar', admin: 'secret');
      expect(find.text('الوصول إلى قاعدة البيانات'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsNothing);

      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(find.text('إنشاء حساب المالك'), findsOneWidget);
      expect(find.text('أنشئ قاعدة البيانات وتابع'), findsOneWidget);
      expect(find.text('تأكيد الرقم السري'), findsOneWidget);
    });
  });

  group('the smallest window, in Arabic', () {
    for (final page in OwnerPage.values) {
      testWidgets('${page.name} fits with nothing overflowing', (tester) async {
        await pump(
          tester,
          language: 'ar',
          size: const Size(1024, 700),
          page: page,
          admin: 'secret',
        );

        expect(tester.takeException(), isNull);
        // Technical values read left to right inside Arabic text.
        if (page == OwnerPage.databaseAccess) {
          final account = tester.widget<Text>(find.text('الحساب: pos_admin'));
          expect(account.textDirection, TextDirection.ltr);
        } else {
          final field = tester.widget<TextField>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('اسم المستخدم:false')),
                  matching: find.byType(TextField),
                )
                .first,
          );
          expect(field.textDirection, TextDirection.ltr);
        }
      });
    }
  });
}
