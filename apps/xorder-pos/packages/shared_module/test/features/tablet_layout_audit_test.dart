import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/password_sign_in.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/cash/presentation/cash_dialogs.dart';
import 'package:shared_module/features/cash/presentation/day_close_dialog.dart';
import 'package:shared_module/features/floor/floor_screen.dart';
import 'package:shared_module/features/history/presentation/order_history_screen.dart';
import 'package:shared_module/features/home/home_screen.dart';
import 'package:shared_module/features/payment/payment_screen.dart';
import 'package:shared_module/features/settings/about_dialog.dart';
import 'package:shared_module/features/settings/printer_settings_dialog.dart';
import 'package:shared_module/features/shift/presentation/shift_dialogs.dart';
import 'package:shared_module/features/lock/lock_screen.dart';
import 'package:shared_module/features/sale/sale_screen.dart';
import 'package:shared_module/features/setup/presentation/setup_wizard.dart';
import 'package:shared_module/features/start/start_screen.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

/// tablet-cloud-onboarding, Stage 6 (AC-10, AC-11): the screens a person meets
/// first on a tablet, at the sizes tablets come in, in both orientations and
/// both languages, with the bundled faces (the test font draws every glyph a
/// full em wide, so "nothing overflows" would be a claim about a font no till
/// ships). What this cannot see — a finger, the real keyboard, how it feels —
/// is a person's job on the tablet.
class _Platform implements PlatformPasswordCheck {
  @override
  Future<PasswordVerdict> verify({
    required String username,
    required String password,
  }) async => PasswordVerdict.rejected;
}

/// Fails with the whole report (which widget, how far) rather than the one
/// line `takeException` gives.
void _clean(WidgetTester tester) {
  final error = tester.takeException();
  if (error == null) return;
  final text = '${error ?? ''}\n${_reports.join('\n---\n')}';
  fail(text.length > 2500 ? text.substring(0, 2500) : text);
}

/// The framework's own reports, which say WHICH widget overflowed.
final _reports = <String>[];

void main() {
  setUpAll(loadPosFonts);

  /// Logical sizes. 1200×750 is a 10.5" tablet's logical area; 1280×800 and
  /// 1024×600 are the common 10" and 8" Android tablets. Each both ways round.
  const sizes = <(String, Size)>[
    ('1280x800', Size(1280, 800)),
    ('800x1280', Size(800, 1280)),
    ('1200x750', Size(1200, 750)),
    ('750x1200', Size(750, 1200)),
    ('1024x600', Size(1024, 600)),
    ('600x1024', Size(600, 1024)),
  ];

  const cashier = PosStaff(
    id: 2,
    name: 'Rana A.',
    username: 'rana',
    role: FakeSessionRepository.cashier,
  );

  final shift = PosShift(
    id: 3,
    openedAt: DateTime(2026, 11, 19, 9),
    openingFloat: const Money(0),
    openedByName: 'Rana A.',
  );

  Future<void> show(
    WidgetTester tester,
    Size size,
    String locale,
    Widget home, {
    bool signedIn = true,
    bool platform = false,
    DeploymentMode mode = DeploymentMode.cloud,
    double keyboard = 0,
  }) async {
    _reports.clear();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      final nodes = details.informationCollector?.call() ?? const [];
      _reports.add(
        '${details.exceptionAsString()}\n'
        '${nodes.map((n) => n.toString()).join('\n')}',
      );
    };
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0
      ..viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(appMode: mode, english: false),
        shiftProvider.overrideWith((ref) async => shift),
        if (platform)
          platformPasswordCheckProvider.overrideWithValue(_Platform()),
      ],
    );
    addTearDown(container.dispose);
    if (signedIn) container.read(signedInStaffProvider.notifier).signIn(cashier);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(locale),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final screens = <String, Widget Function()>{
    'setup wizard': () => SetupWizard(onFinished: () {}),
    'start': () => StartScreen(
      onStart: () {},
      onManageLicence: () {},
      onManage: (_) {},
    ),
    'home': () => HomeScreen(onPick: (_) {}, onBack: () {}),
    'sale': () => SaleScreen(
      onLock: () {},
      onTables: () {},
      onOrders: () {},
    ),
  };

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final (label, size) in sizes) {
      for (final locale in const ['en', 'ar']) {
        testWidgets('$name at $label, $locale', (tester) async {
          await show(tester, size, locale, build());
          _clean(tester);
        });
      }
    }
  }

  // The lock screen has two faces on a cloud tablet; the password one takes the
  // keyboard, which must never hide Sign in.
  for (final (label, size) in sizes) {
    for (final locale in const ['en', 'ar']) {
      testWidgets('lock screen (PIN) at $label, $locale', (tester) async {
        await show(
          tester,
          size,
          locale,
          LockScreen(onUnlocked: () {}, onBack: () {}),
        );
        _clean(tester);
      });

      testWidgets('lock screen (password, keyboard up) at $label, $locale', (
        tester,
      ) async {
        await show(
          tester,
          size,
          locale,
          LockScreen(onUnlocked: () {}, onBack: () {}),
          platform: true,
          keyboard: size.height > size.width ? 420 : 320,
        );
        _clean(tester);

        final submit = find.byKey(const Key('lock-password-submit'));
        expect(submit, findsOneWidget);
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        final rect = tester.getRect(submit);
        final visibleBottom = size.height - (size.height > size.width ? 420 : 320);
        expect(
          rect.bottom,
          lessThanOrEqualTo(visibleBottom + 0.5),
          reason: 'Sign in must be reachable above the keyboard',
        );
        expect(rect.height, greaterThanOrEqualTo(PosSize.secondaryAction - 0.5));
      });
    }
  }

  // The first thing a new tablet asks for: the slug, the owner's name and
  // password. The keyboard is up for all of it, and Sign in must stay reachable.
  for (final (label, size) in sizes) {
    for (final locale in const ['en', 'ar']) {
      testWidgets('setup sign-in, keyboard up, at $label, $locale', (
        tester,
      ) async {
        final keyboard = size.height > size.width ? 420.0 : 320.0;
        await show(
          tester,
          size,
          locale,
          SetupWizard(onFinished: () {}),
          keyboard: keyboard,
        );
        _clean(tester);

        final strings = locale == 'ar' ? const ArStrings() : const EnStrings();
        final submit = find.text(strings.signIn);
        expect(submit, findsWidgets);
        await tester.ensureVisible(submit.first);
        await tester.pumpAndSettle();
        _clean(tester);
        expect(
          tester.getRect(submit.first).bottom,
          lessThanOrEqualTo(size.height - keyboard + 0.5),
          reason: 'Sign in must be reachable above the keyboard',
        );
      });
    }
  }

  // ── The rest of a day's screens (second pass) ─────────────────────────────
  //
  // Dialogs are opened over an empty page, the way the till opens them; the
  // ones with a text field are shown with the keyboard up as well.
  final dialogs = <String, (Future<Object?> Function(BuildContext), bool)>{
    'open shift': ((c) => OpenShiftDialog.show(c, by: cashier), true),
    'close shift': ((c) => CloseShiftDialog.show(c, shift: shift), true),
    'cash pay-in': (
      (c) => CashMovementDialog.show(c, kind: CashMovementKind.payIn),
      true,
    ),
    'day close': ((c) => DayCloseDialog.show(c), false),
    'printer settings': ((c) => PrinterSettingsDialog.show(c), false),
    'about': ((c) => PosAboutDialog.show(c), false),
  };

  for (final MapEntry(key: name, value: (open, typed)) in dialogs.entries) {
    for (final (label, size) in sizes) {
      for (final locale in const ['en', 'ar']) {
        for (final keyboard in [
          0.0,
          if (typed) size.height > size.width ? 420.0 : 320.0,
        ]) {
          testWidgets(
            '$name dialog at $label, $locale'
            '${keyboard > 0 ? ', keyboard up' : ''}',
            (tester) async {
              await show(
                tester,
                size,
                locale,
                const Scaffold(body: SizedBox.expand()),
                keyboard: keyboard,
              );
              unawaited(open(tester.element(find.byType(Scaffold))));
              await tester.pumpAndSettle();
              _clean(tester);
            },
          );
        }
      }
    }
  }

  final pages = <String, Widget Function()>{
    'floor': () => FloorScreen(
      onTablePicked: (_) {},
      onSellWithoutTable: () {},
      onClose: () {},
      now: DateTime(2026, 11, 19, 12),
    ),
    'order history': () => OrderHistoryScreen(onClose: () {}),
  };

  for (final MapEntry(key: name, value: build) in pages.entries) {
    for (final (label, size) in sizes) {
      for (final locale in const ['en', 'ar']) {
        testWidgets('$name at $label, $locale', (tester) async {
          await show(tester, size, locale, build());
          _clean(tester);
        });
      }
    }
  }

  // The payment screen, reached the way a cashier reaches it: a line on the
  // ticket, then Charge.
  for (final (label, size) in sizes) {
    for (final locale in const ['en', 'ar']) {
      testWidgets('payment at $label, $locale', (tester) async {
        late WidgetRef ref;
        await show(
          tester,
          size,
          locale,
          Consumer(
            builder: (context, r, _) {
              ref = r;
              return SaleScreen(
                onLock: () {},
                onTables: () {},
                onOrders: () {},
              );
            },
          ),
        );
        ref.read(ticketProvider.notifier).setOrderType(OrderType.takeaway);
        // The fake menu's own wording, which does not change with the locale.
        final drink = find.text('Soft Drink', skipOffstage: false);
        expect(drink, findsWidgets, reason: 'the fake menu has a drink');
        // Scrolled to, as a cashier would on a short screen.
        await tester.ensureVisible(drink.first);
        await tester.pumpAndSettle();
        await tester.tap(drink.first);
        await tester.pumpAndSettle();
        unawaited(PaymentScreen.show(tester.element(find.byType(SaleScreen))));
        await tester.pumpAndSettle();
        _clean(tester);
        expect(find.byType(PaymentScreen), findsOneWidget);
      });
    }
  }
}
