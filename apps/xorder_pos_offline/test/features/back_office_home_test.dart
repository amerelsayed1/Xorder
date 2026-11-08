import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/branch_sales.dart';
import 'package:shared_module/domain/models/business_day.dart';
import 'package:shared_module/domain/models/home_sales.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:xorder_pos_offline/features/admin/application/back_office_home.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_home_pane.dart';

import 'package:xorder_pos_test_support/fakes.dart';

// The owner holds `reports.view` through the role, as a real one does;
// `PosStaff.capabilities` is direct grants only.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);
// Let through Admin Mode's door, and nothing about the money.
const _doorOnly = PosStaff(
  id: 9,
  name: 'Salma T.',
  username: 'salma',
  role: PosRole(
    id: 9,
    code: 'door',
    nameEn: 'Door',
    capabilities: {PosCapability.adminEnter},
  ),
);

Money _egp(int minor) => Money(minor, currency: 'EGP', exponent: 2);

BranchSales _sales({
  required int gross,
  required int discounts,
  required int refunds,
  required int orders,
}) => BranchSales(
  branchId: 1,
  businessDay: DateTime(2026, 9, 10),
  terminals: [
    TerminalSales(
      terminalId: 't1',
      name: 'POS-01',
      orders: orders,
      gross: _egp(gross),
      discounts: _egp(discounts),
      refunds: _egp(refunds),
      refundCount: refunds == 0 ? 0 : 1,
    ),
  ],
);

final _today = BusinessDay(
  id: 2,
  date: DateTime.utc(2026, 9, 10),
  openedAt: DateTime(2026, 9, 10, 8, 5),
);

// 60,000 gross − 5,000 off − 1,000 refunded = 54,000 net over 3 orders.
final _todaySales = _sales(
  gross: 60000,
  discounts: 5000,
  refunds: 1000,
  orders: 3,
);
// Yesterday, cut at the same time since opening: 45,000 over 2.
final _cutYesterday = _sales(
  gross: 45000,
  discounts: 0,
  refunds: 0,
  orders: 2,
);

Future<void> _pump(
  WidgetTester tester, {
  PosStaff admin = _owner,
  HomeSales? home,
  bool noDay = false,
  String language = 'en',
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = const Size(1280, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      homeSalesProvider.overrideWith(
        (ref) async => noDay ? null : (home ?? HomeSales(
          day: _today,
          sales: _todaySales,
          previousDay: BusinessDay(
            id: 1,
            date: DateTime.utc(2026, 9, 9),
            openedAt: DateTime(2026, 9, 9, 8),
            closedAt: DateTime(2026, 9, 9, 23),
          ),
          previous: _cutYesterday,
        )),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  container
      .read(terminalProfileProvider.notifier)
      .apply(
        const TerminalProfile(branchName: 'Maadi', terminalName: 'POS-02'),
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
        home: Scaffold(
          body: ManagementHomePane(admin: admin),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _in(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f);

/// Home (BO-4): what it claims about the day, and to whom — and, since the
/// owner took its cards and shortcuts away as duplicates (15 Sep 2026), that
/// it claims nothing the status bar or the window's bar already says.
void main() {
  const s = EnStrings();

  group('the tiles', () {
    testWidgets("are BranchSales' figures, each against the cut day", (
      tester,
    ) async {
      await _pump(tester);

      // Net, orders and average — the day's own figures, not re-added.
      expect(
        _in('home-tile-net', find.text(_todaySales.net.format(withCurrency: true))),
        findsOneWidget,
      );
      expect(_in('home-tile-orders', find.text('3')), findsOneWidget);
      expect(
        _in('home-tile-average', find.text(_egp(18000).format(withCurrency: true))),
        findsOneWidget,
      );

      // 54,000 against 45,000; 3 against 2; 18,000 against 22,500.
      expect(_in('home-tile-net', find.text('+20.00%')), findsOneWidget);
      expect(_in('home-tile-orders', find.text('+50.00%')), findsOneWidget);
      expect(_in('home-tile-average', find.text('-20.00%')), findsOneWidget);
      expect(find.text(s.homeVsPreviousDay), findsNWidgets(3));

      expect(
        _in('home-day-caption', find.text(s.homeDayOpen('2026-09-10', '08:05'))),
        findsOneWidget,
      );
    });

    testWidgets('with no day open, show the last closed day and say so', (
      tester,
    ) async {
      await _pump(
        tester,
        home: HomeSales(
          day: BusinessDay(
            id: 2,
            date: DateTime.utc(2026, 9, 10),
            openedAt: DateTime(2026, 9, 10, 8),
            closedAt: DateTime(2026, 9, 10, 23, 40),
          ),
          sales: _todaySales,
        ),
      );

      expect(
        _in('home-day-caption', find.text(s.homeDayClosed('2026-09-10'))),
        findsOneWidget,
      );
      expect(find.textContaining('open since'), findsNothing);
      // Its figures, still.
      expect(
        _in('home-tile-net', find.text(_todaySales.net.format(withCurrency: true))),
        findsOneWidget,
      );
      // And no earlier day to hold it against.
      expect(find.text(s.homeNoComparison), findsNWidgets(3));
    });

    testWidgets('with no day ever, say there is nothing — not zeros', (
      tester,
    ) async {
      await _pump(tester, noDay: true);
      expect(find.text(s.homeNoDayYet), findsOneWidget);
      expect(find.byKey(const Key('home-tile-net')), findsNothing);
    });

    testWidgets('are absent without reports.view', (tester) async {
      await _pump(tester, admin: _doorOnly);

      expect(find.byKey(const Key('home-tiles')), findsNothing);
      expect(find.text(_todaySales.net.format(withCurrency: true)), findsNothing);
      // The greeting is still theirs.
      expect(find.text(s.homeWelcome('Salma T.')), findsOneWidget);
      expect(find.text(s.paneHomeBlurb), findsOneWidget);
    });
  });

  // The status bar under every page names the branch, the till and the
  // connection; the backup notice over every page says when the last good
  // copy was; the window's bar holds every page. Home said all of it again,
  // and the owner took it away. Asserted by what a person would read — the
  // names, the pills, the old headings — not only by the keys that are gone.
  //
  // Once for the offline till only: the cloud variant, which bound a sync loop
  // and three unsent sales, left in pos-split-apps stage 4 — this Home is the
  // offline app's, which never binds one.
  testWidgets('offline: no status cards and no quick actions — the greeting '
      'and the day, and nothing else', (tester) async {
    await _pump(tester);

    for (final key in [
      'home-card-branch',
      'home-card-device',
      'home-card-connection',
      'home-card-last-backup',
      'home-card-last-sync',
      'home-action-salesReports',
      'home-action-products',
      'home-action-employees',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    // The terminal profile says Maadi and POS-02; Home says neither.
    expect(find.text('Maadi'), findsNothing);
    expect(find.text('POS-02'), findsNothing);
    expect(find.byType(BranchServerPill), findsNothing);
    expect(find.byType(SyncPill), findsNothing);
    for (final heading in [
      'Connection',
      'Last backup',
      'Last sync',
      'Quick actions',
      'Product management',
    ]) {
      expect(find.text(heading), findsNothing, reason: heading);
    }
    // What is left: the greeting, and the tiles.
    expect(find.text(s.homeWelcome('Amer M.')), findsOneWidget);
    expect(find.byKey(const Key('home-tiles')), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing, reason: 'no links');
  });

  testWidgets('the subtitle promises no way onward: the links are gone', (
    tester,
  ) async {
    const ar = ArStrings();
    for (final words in [s.paneHomeBlurb, ar.paneHomeBlurb]) {
      expect(words, isNot(contains('rest')), reason: words);
      expect(words, isNot(contains('الأقسام')), reason: words);
    }
  });

  testWidgets('in Arabic: Arabic words, Latin digits left to right, and the '
      'tiles start on the right', (tester) async {
    await _pump(tester, language: 'ar');
    const ar = ArStrings();

    expect(find.text(ar.homeWelcome('Amer M.')), findsOneWidget);
    expect(find.text(ar.paneHomeBlurb), findsOneWidget);
    expect(find.text(ar.homeKpiNetSales), findsOneWidget);
    expect(find.text(s.homeKpiNetSales), findsNothing);

    // The delta is data: Western digits, and laid out left to right so the
    // sign stays in front of the number.
    final delta = tester.widget<Text>(
      _in('home-tile-net', find.text('+20.00%')),
    );
    expect(delta.textDirection, TextDirection.ltr);

    final net = tester.getRect(find.byKey(const Key('home-tile-net')));
    final orders = tester.getRect(find.byKey(const Key('home-tile-orders')));
    expect(net.left, greaterThan(orders.left), reason: 'start is right');
    expect(tester.takeException(), isNull);
  });
}
