import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/cloud/cloud_sync.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/backup.dart';
import 'package:xorder_pos/domain/models/branch_sales.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/home_sales.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/application/back_office_home.dart';
import 'package:xorder_pos/features/admin/presentation/management_home_pane.dart';

import '../support/fakes.dart';

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

class _Sync extends Mock implements CloudSync {}

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
  bool cloud = false,
  String language = 'en',
  List<(HomeQuickAction, VoidCallback)> actions = const [],
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
      if (cloud) ...[
        cloudSyncProvider.overrideWithValue(_Sync()),
        lastPlatformSyncProvider.overrideWith(
          (ref) async => DateTime(2026, 9, 10, 7, 30),
        ),
        pendingSyncCountProvider.overrideWith((ref) async => 3),
      ],
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
          body: ManagementHomePane(admin: admin, actions: actions),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _in(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f);

/// Home (BO-4): what it claims about the day, about this till, and to whom.
void main() {
  const s = EnStrings();

  group('the tiles', () {
    testWidgets("are BranchSales' figures, each against the cut day", (
      tester,
    ) async {
      await _pump(tester);

      // Net, orders and average — the day's own figures, not re-added.
      expect(
        _in('home-tile-net', find.text(_todaySales.net.format())),
        findsOneWidget,
      );
      expect(_in('home-tile-orders', find.text('3')), findsOneWidget);
      expect(
        _in('home-tile-average', find.text(_egp(18000).format())),
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
        _in('home-tile-net', find.text(_todaySales.net.format())),
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
      expect(find.text(_todaySales.net.format()), findsNothing);
      // The rest of Home is still theirs.
      expect(find.byKey(const Key('home-card-branch')), findsOneWidget);
      expect(find.byKey(const Key('home-card-connection')), findsOneWidget);
    });
  });

  group('the cards', () {
    testWidgets('name this branch and this device', (tester) async {
      await _pump(tester);
      expect(_in('home-card-branch', find.text('Maadi')), findsOneWidget);
      expect(_in('home-card-device', find.text('POS-02')), findsOneWidget);
    });

    testWidgets('offline: the last verified backup, and no last sync', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: [
          backupsProvider.overrideWith(
            (ref) async => [
              // Newest first. The newest failed, so the verified one before
              // it is the copy anybody could restore.
              BackupRecord(
                takenAt: DateTime(2026, 9, 10, 1),
                takenByName: 'Amer M.',
                trigger: BackupTrigger.dayClose,
                outcome: BackupOutcome.failed,
                filePath: '/backups/b.dump',
              ),
              BackupRecord(
                takenAt: DateTime(2026, 9, 9, 23, 45),
                takenByName: 'Amer M.',
                trigger: BackupTrigger.dayClose,
                outcome: BackupOutcome.verified,
                filePath: '/backups/a.dump',
              ),
            ],
          ),
        ],
      );

      expect(
        _in('home-card-last-backup', find.text('2026-09-09 23:45')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-card-last-sync')), findsNothing);
    });

    testWidgets('offline, with no copy ever taken: never', (tester) async {
      await _pump(
        tester,
        overrides: [backupsProvider.overrideWith((ref) async => const [])],
      );
      expect(_in('home-card-last-backup', find.text(s.homeNever)), findsOneWidget);
    });

    testWidgets('cloud: the last sync and what is still to send, no backup', (
      tester,
    ) async {
      await _pump(tester, cloud: true);

      expect(
        _in('home-card-last-sync', find.text('2026-09-10 07:30')),
        findsOneWidget,
      );
      expect(
        _in('home-card-last-sync', find.text(s.homeSalesWaiting(3))),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-card-last-backup')), findsNothing);
    });
  });

  testWidgets('shortcuts are the ones it is given, and open what they say', (
    tester,
  ) async {
    var opened = <HomeQuickAction>[];
    await _pump(
      tester,
      actions: [
        (HomeQuickAction.employees, () => opened.add(HomeQuickAction.employees)),
      ],
    );

    expect(find.byKey(const Key('home-action-products')), findsNothing);
    expect(find.byKey(const Key('home-action-salesReports')), findsNothing);
    await tester.tap(find.byKey(const Key('home-action-employees')));
    expect(opened, [HomeQuickAction.employees]);
    opened = [];
  });

  testWidgets('in Arabic: Arabic words, Latin digits left to right, and the '
      'cards start on the right', (tester) async {
    await _pump(
      tester,
      language: 'ar',
      actions: [(HomeQuickAction.employees, () {})],
    );
    const ar = ArStrings();

    expect(find.text(ar.homeWelcome('Amer M.')), findsOneWidget);
    expect(find.text(ar.homeKpiNetSales), findsOneWidget);
    expect(find.text(ar.homeActionEmployees), findsOneWidget);
    expect(find.text(s.homeKpiNetSales), findsNothing);

    // The delta is data: Western digits, and laid out left to right so the
    // sign stays in front of the number.
    final delta = tester.widget<Text>(
      _in('home-tile-net', find.text('+20.00%')),
    );
    expect(delta.textDirection, TextDirection.ltr);

    final branch = tester.getRect(find.byKey(const Key('home-card-branch')));
    final device = tester.getRect(find.byKey(const Key('home-card-device')));
    expect(branch.left, greaterThan(device.left), reason: 'start is right');
    expect(tester.takeException(), isNull);
  });
}
