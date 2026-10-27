import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/business_day_service.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/features/lock/lock_screen.dart';
import 'package:xorder_pos/features/home/home_screen.dart';
import 'package:xorder_pos/features/start/start_screen.dart';

import '../support/fakes.dart';

/// Where the trading day opens, and what the start screen says about it.
///
/// Approved rules (report 2026-10-24, Part 4): a day opens with the first shift
/// opened or resumed; the till never stops selling because of it; a day left
/// open, or already closed, is said in a sentence rather than thrown.
void main() {
  const en = EnStrings();

  /// Records the order things happened in.
  late List<String> events;

  BusinessDayResult opened() => BusinessDayResult(
    BusinessDayOutcome.opened,
    day: BusinessDay(
      id: 1,
      date: DateTime(2026, 10, 24),
      openedAt: DateTime(2026, 10, 24, 9),
    ),
  );

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    required Widget home,
    BusinessDayResult? result,
    DayNotice? notice,
    bool arabic = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    events = [];

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        shiftRepositoryProvider.overrideWithValue(_RecordingShifts(events)),
        ensureBusinessDayProvider.overrideWithValue((by) async {
          events.add('day:${by.username}');
          return result ?? opened();
        }),
        dayNoticeProvider.overrideWith((ref) async => notice),
      ],
    );
    addTearDown(container.dispose);
    const deployment = DeploymentConfig(
      mode: DeploymentMode.cloud,
      baseUrl: 'https://xorder.io',
      tenantSlug: 'mahsoub',
    );
    container.read(deploymentProvider.notifier).apply(deployment);
    // A valid licence, as the start-screen gate tests install one: without it
    // the start screen refuses to open a shift at all.
    await tester.runAsync(
      () => container
          .read(licenceServiceProvider)
          .activate(deployment: deployment, key: 'XORD-GOOD-1'),
    );
    container.invalidate(licenceEntitlementProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          // As the real app wires it: the strings are looked up through
          // Localizations, so an Arabic test names the locale.
          locale: arabic ? const Locale('ar') : null,
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
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    return container;
  }

  Widget startScreen() => StartScreen(
    onStart: () => events.add('start'),
    onManageLicence: () {},
    onManage: (_) {},
  );

  /// Home is where a shift is started now (pos-signin-first-home): somebody has
  /// already signed in at Start, so what is asked here is the float.
  Widget homeScreen() => HomeScreen(
    onPick: (_) {},
    onBack: () {},
    onShiftOpened: () => events.add('start'),
  );

  Future<void> openShift(WidgetTester tester, ProviderContainer container) async {
    container
        .read(signedInStaffProvider.notifier)
        .signIn(
          const PosStaff(
            id: 1,
            name: 'Rana A.',
            username: 'rana',
            role: _cashier,
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-start-shift')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open shift'));
    await tester.pumpAndSettle();
  }

  group('opening a shift', () {
    testWidgets('opens the day first, so the shift row is stamped by it', (
      tester,
    ) async {
      // The trigger stamps a shift from the open day at INSERT time; a day
      // opened after the shift would leave the shift unstamped.
      final container = await boot(tester, home: homeScreen());
      await openShift(tester, container);

      expect(events, ['day:rana', 'shift', 'start']);
    });

    testWidgets('a day that cannot be opened does not stop the shift', (
      tester,
    ) async {
      // The till never stops selling because of the day (AC-4).
      final container = await boot(
        tester,
        home: homeScreen(),
        result: const BusinessDayResult(
          BusinessDayOutcome.failed,
          error: 'database down',
        ),
      );
      await openShift(tester, container);

      expect(events, containsAllInOrder(['day:rana', 'shift', 'start']));
    });

    testWidgets('a date that was already closed does not stop it either', (
      tester,
    ) async {
      final container = await boot(
        tester,
        home: homeScreen(),
        result: const BusinessDayResult(BusinessDayOutcome.dateAlreadyClosed),
      );
      await openShift(tester, container);

      expect(events, containsAllInOrder(['day:rana', 'shift', 'start']));
    });
  });

  group('resuming a shift at the lock screen', () {
    testWidgets('signing in on an open shift makes sure the day is open', (
      tester,
    ) async {
      final container = await boot(
        tester,
        home: LockScreen(
          onUnlocked: () => events.add('unlocked'),
          onBack: () {},
        ),
      );
      await tester.runAsync(
        () => container
            .read(shiftRepositoryProvider)
            .open(
              by: const PosStaff(
                id: 1,
                name: 'Rana A.',
                username: 'rana',
                role: _cashier,
              ),
              openingFloat: const Money(0),
            ),
      );
      events.clear();
      container.invalidate(shiftProvider);
      await container.read(shiftProvider.future);

      await tester.enterText(find.byType(TextField), 'rana');
      await tester.pump();
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(events, contains('day:rana'));
      expect(events, contains('unlocked'));
    });

    testWidgets('with no shift open the lock screen opens no day', (
      tester,
    ) async {
      await boot(
        tester,
        home: LockScreen(
          onUnlocked: () => events.add('unlocked'),
          onBack: () {},
        ),
      );

      await tester.enterText(find.byType(TextField), 'rana');
      await tester.pump();
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(events, ['unlocked']);
    });
  });

  group('what is wrong with the day is said in the status bar, not here', () {
    testWidgets('the start screen carries no banner for it', (tester) async {
      await boot(
        tester,
        home: startScreen(),
        notice: DayNotice(DayNoticeKind.staleOpenDay, DateTime(2026, 10, 22)),
      );

      expect(find.byKey(const Key('start-day-notice')), findsNothing);
      expect(find.text(en.dayStillOpenFrom('2026-10-22')), findsNothing);
    });
  });

  test('both sentences are worded, with the date, in both languages', () {
    const ar = ArStrings();
    for (final s in [en, ar]) {
      expect(s.dayStillOpenFrom('2026-10-22'), contains('2026-10-22'));
      expect(s.dayClosedTodayNotice('2026-10-24'), contains('2026-10-24'));
      expect(s.dayStillOpenShort('2026-10-22'), contains('2026-10-22'));
      expect(s.dayClosedTodayShort('2026-10-24'), contains('2026-10-24'));
    }
    expect(ar.dayStillOpenShort('x'), isNot(en.dayStillOpenShort('x')));
    expect(ar.dayClosedTodayShort('x'), isNot(en.dayClosedTodayShort('x')));
    expect(ar.dayStillOpenFrom('x'), isNot(en.dayStillOpenFrom('x')));
    expect(ar.dayClosedTodayNotice('x'), isNot(en.dayClosedTodayNotice('x')));
  });
}

const _cashier = PosRole(
  id: 2,
  code: 'cashier',
  nameEn: 'Cashier',
  capabilities: {PosCapability.shiftOpen},
);

/// The real fake, plus a note of when it was asked to open a shift.
class _RecordingShifts extends FakeShiftRepository {
  _RecordingShifts(this.events);

  final List<String> events;

  @override
  Future<PosShift> open({required PosStaff by, required Money openingFloat}) {
    events.add('shift');
    return super.open(by: by, openingFloat: openingFloat);
  }
}
