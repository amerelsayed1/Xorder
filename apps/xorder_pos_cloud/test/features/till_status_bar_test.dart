import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_module/app/app.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/app/router.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/core/config/app_version.dart';
import 'package:xorder_pos_cloud/data/cloud/cloud_sync.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/domain/repositories/repositories.dart';
import 'package:shared_module/domain/services/business_day_service.dart';

import 'package:xorder_pos_test_support/fakes.dart';
import 'package:xorder_pos_test_support/fonts.dart';

const _cashier = PosStaff(
  id: 2,
  name: 'Omar K.',
  username: 'omar',
  role: PosRole(
    id: 2,
    code: 'cashier',
    nameEn: 'Cashier',
    nameAr: 'كاشير',
    capabilities: SystemRoles.cashier,
  ),
);

class _Sync extends Mock implements CloudSync {}

/// The status bar under every screen (global-status-bar).
///
/// Run through the real app and the real router: what is being proved is where
/// the bar is mounted, and that is a fact about `app.dart`, not about the
/// widget.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPosFonts);

  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  final bar = find.byKey(const Key('till-status-bar'));
  final person = find.byKey(const Key('till-status-user'));

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    PosStaff? staff = _cashier,
    bool setUp = true,
    String language = 'en',
    double width = 1440,
    double height = 900,
    TerminalProfile profile = const TerminalProfile(
      branchName: 'Maadi',
      terminalName: 'Counter 1',
    ),
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [...fakeRepositoryOverrides(), ...overrides],
    );
    addTearDown(container.dispose);
    container.read(localeProvider.notifier).apply(language);
    container.read(terminalProfileProvider.notifier).apply(profile);
    if (setUp) container.read(setupCompleteProvider.notifier).markComplete();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const XorderPosApp(),
      ),
    );
    if (staff != null) {
      container.read(signedInStaffProvider.notifier).signIn(staff);
    }
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> goTo(
    WidgetTester tester,
    ProviderContainer container,
    String path,
  ) async {
    container.read(routerProvider).go(path);
    await tester.pumpAndSettle();
  }

  testWidgets('every screen of a set-up till has it: connection, branch, '
      'till, version', (tester) async {
    final container = await pumpApp(tester);

    for (final path in [
      PosRoutes.start,
      PosRoutes.lock,
      PosRoutes.orders,
      PosRoutes.licence,
      PosRoutes.sale,
    ]) {
      await goTo(tester, container, path);
      expect(bar, findsOneWidget, reason: path);
      Finder inBar(Finder f) => find.descendant(of: bar, matching: f);
      expect(
        inBar(find.byType(BranchServerPill)),
        findsOneWidget,
        reason: path,
      );
      expect(inBar(find.text('Maadi')), findsOneWidget, reason: path);
      expect(inBar(find.text('Counter 1')), findsOneWidget, reason: path);
      expect(inBar(find.text('v$posAppVersion')), findsOneWidget, reason: path);
      expect(tester.takeException(), isNull, reason: path);
    }
  }, variant: desktop);

  testWidgets('the welcome screen and the wizard do not', (tester) async {
    final container = await pumpApp(tester, staff: null, setUp: false);
    expect(
      container
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      PosRoutes.welcome,
    );
    expect(bar, findsNothing);

    await goTo(tester, container, PosRoutes.setup);
    expect(bar, findsNothing);
  }, variant: desktop);

  testWidgets('the person: shown where somebody is in, hidden on Start and '
      'Lock even with a cashier still signed in behind them', (tester) async {
    final container = await pumpApp(tester);

    for (final path in [PosRoutes.start, PosRoutes.lock]) {
      await goTo(tester, container, path);
      expect(bar, findsOneWidget, reason: path);
      expect(person, findsNothing, reason: path);
    }
    for (final path in [PosRoutes.orders, PosRoutes.licence, PosRoutes.sale]) {
      await goTo(tester, container, path);
      expect(
        tester.widget<Text>(person).data,
        'Omar K. · Cashier',
        reason: path,
      );
    }

    // And nobody signed in anywhere: the rest of the bar, no person.
    container.read(signedInStaffProvider.notifier).signOut();
    await tester.pumpAndSettle();
    await goTo(tester, container, PosRoutes.licence);
    expect(bar, findsOneWidget);
    expect(person, findsNothing);
  }, variant: desktop);

  group('a day left open, or sales after it closed, is said in the bar', () {
    final notice = find.byKey(const Key('till-status-day-notice'));
    Override staleDay() => dayNoticeProvider.overrideWith(
      (ref) async =>
          DayNotice(DayNoticeKind.staleOpenDay, DateTime(2026, 10, 24)),
    );

    testWidgets('on every screen, in a few words, beside the till facts', (
      tester,
    ) async {
      final container = await pumpApp(tester, overrides: [staleDay()]);

      for (final path in [PosRoutes.start, PosRoutes.lock, PosRoutes.sale]) {
        await goTo(tester, container, path);
        expect(
          find.descendant(
            of: bar,
            matching: find.text(
              const EnStrings().dayStillOpenShort('2026-10-24'),
            ),
          ),
          findsOneWidget,
          reason: path,
        );
        expect(find.descendant(of: bar, matching: notice), findsOneWidget);
        expect(tester.takeException(), isNull, reason: path);
      }
    }, variant: desktop);

    testWidgets('the sales-after-close warning too, and in Arabic', (
      tester,
    ) async {
      await pumpApp(
        tester,
        language: 'ar',
        overrides: [
          dayNoticeProvider.overrideWith(
            (ref) async => DayNotice(
              DayNoticeKind.todayAlreadyClosed,
              DateTime(2026, 10, 24),
            ),
          ),
        ],
      );

      expect(
        find.descendant(
          of: bar,
          matching: find.text(
            const ArStrings().dayClosedTodayShort('2026-10-24'),
          ),
        ),
        findsOneWidget,
      );
    }, variant: desktop);

    testWidgets('the full sentence, with what to do, is its tooltip', (
      tester,
    ) async {
      await pumpApp(tester, overrides: [staleDay()]);

      expect(
        find.byTooltip(const EnStrings().dayStillOpenFrom('2026-10-24')),
        findsOneWidget,
      );
    }, variant: desktop);

    testWidgets('nothing to say, nothing shown', (tester) async {
      await pumpApp(tester);
      expect(notice, findsNothing);
    }, variant: desktop);

    testWidgets('and fits a narrow window without overflow', (tester) async {
      await pumpApp(tester, width: 900, overrides: [staleDay()]);

      expect(notice, findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: desktop);
  });

  testWidgets('inside the back office it names the administrator, once', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await signInToAdminMode(container);
    await goTo(tester, container, PosRoutes.management);

    expect(bar, findsOneWidget, reason: 'Management draws none of its own');
    expect(tester.widget<Text>(person).data, 'Amer M. · Owner');
  }, variant: desktop);

  testWidgets('the sale screen says the connection and the branch once', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await goTo(tester, container, PosRoutes.sale);

    expect(find.byType(BranchServerPill), findsOneWidget);
    expect(find.text('Maadi'), findsOneWidget);
    expect(find.text('Counter 1'), findsOneWidget);
    // And the person once: the top bar no longer carries an avatar and a name
    // of its own (owner, 26 Oct 2026).
    expect(find.textContaining('Omar K.'), findsOneWidget);
    expect(find.text('Omar K.'), findsNothing);
    expect(
      find.descendant(of: bar, matching: find.byType(BranchServerPill)),
      findsOneWidget,
    );

    // The sale screen keeps a timer of its own; let it run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }, variant: desktop);

  testWidgets('a cloud till shows the sync state, not the branch server', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      overrides: [cloudSyncProvider.overrideWithValue(_Sync())],
    );
    await goTo(tester, container, PosRoutes.orders);

    expect(
      find.descendant(of: bar, matching: find.byType(SyncPill)),
      findsOneWidget,
    );
    expect(find.byType(BranchServerPill), findsNothing);
  }, variant: desktop);

  testWidgets('in Arabic the role is Arabic and the version stays a code', (
    tester,
  ) async {
    final container = await pumpApp(tester, language: 'ar');
    await goTo(tester, container, PosRoutes.orders);

    expect(tester.widget<Text>(person).data, 'Omar K. · كاشير');
    final version = tester.widget<Text>(
      find.byKey(const Key('till-status-version')),
    );
    expect(version.textDirection, TextDirection.ltr);
    expect(version.data, 'v$posAppVersion');
    // Starts at the right edge: the bar mirrors with the language.
    final pill = tester.getTopRight(
      find.descendant(of: bar, matching: find.byType(BranchServerPill)),
    );
    expect(pill.dx, greaterThan(1440 / 2));
  }, variant: desktop);

  for (final language in ['ar', 'en']) {
    testWidgets('the person sits at the far edge of the bar, in $language', (
      tester,
    ) async {
      final container = await pumpApp(tester, language: language);
      await goTo(tester, container, PosRoutes.orders);

      final barRect = tester.getRect(bar);
      final personRect = tester.getRect(person);
      // The end of the bar: the left of an Arabic one, the right of an
      // English one — not floating between the version and it.
      final gap = language == 'ar'
          ? personRect.left - barRect.left
          : barRect.right - personRect.right;
      expect(gap, lessThan(60), reason: 'gap to the edge, in $language');
    }, variant: desktop);
  }

  testWidgets('long names ellipsize at the smallest window instead of '
      'overflowing', (tester) async {
    final container = await pumpApp(
      tester,
      width: 1024,
      profile: TerminalProfile(
        branchName: 'The very long branch name ' * 4,
        terminalName: 'A counter with a very long name ' * 4,
      ),
    );
    await goTo(tester, container, PosRoutes.orders);

    expect(bar, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: desktop);

  // Close shift moved here from the sale screen's top bar (owner, 26 Oct 2026).
  group('close shift', () {
    final button = find.byKey(const Key('till-status-close-shift'));

    testWidgets('is in the bar on the sale screen and nowhere else, and the '
        'top bar no longer has it', (tester) async {
      final container = await pumpApp(tester);

      await goTo(tester, container, PosRoutes.sale);
      expect(
        find.descendant(of: bar, matching: find.text('Close shift')),
        findsOneWidget,
      );
      expect(find.text('Close shift'), findsOneWidget, reason: 'only once');

      for (final path in [
        PosRoutes.orders,
        PosRoutes.licence,
        PosRoutes.lock,
      ]) {
        await goTo(tester, container, path);
        expect(button, findsNothing, reason: path);
      }
    }, variant: desktop);

    testWidgets('a ticket still on screen is kept: the cashier is told and '
        'stays on the sale screen', (tester) async {
      final container = await pumpApp(tester);
      container
          .read(ticketProvider.notifier)
          .addProduct(
            const Product(
              id: 101,
              categoryId: 1,
              nameEn: 'Burger',
              price: Money(9500),
            ),
          );
      await goTo(tester, container, PosRoutes.sale);

      await tester.tap(button);
      await tester.pump();

      expect(find.text(EnStrings().ticketStillOpen), findsOneWidget);
      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        PosRoutes.sale,
      );
      expect(container.read(ticketProvider).isEmpty, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    }, variant: desktop);

    testWidgets('with no shift open there is nothing to count: back to Start', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await goTo(tester, container, PosRoutes.sale);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        PosRoutes.start,
      );
    }, variant: desktop);
  });

  // The bar costs 44 px of a 700 px window on every screen; the sale screen is
  // the one that is full.
  for (final language in ['en', 'ar']) {
    testWidgets('the sale screen still fits the smallest window with the bar, '
        'in $language', (tester) async {
      final container = await pumpApp(
        tester,
        width: 1024,
        height: 700,
        language: language,
      );
      await goTo(tester, container, PosRoutes.sale);

      expect(bar, findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    }, variant: desktop);
  }
}
