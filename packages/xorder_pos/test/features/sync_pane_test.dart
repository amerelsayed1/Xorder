import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/cloud/cloud_sync.dart';
import 'package:xorder_pos/data/cloud/outbox_drain.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/backup.dart';
import 'package:xorder_pos/domain/models/held_sync.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/application/back_office_home.dart';
import 'package:xorder_pos/features/admin/presentation/management_sync_pane.dart';

import '../support/fonts.dart';
import '../support/fakes.dart';

// Held through the role, as a real owner holds it.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

class _Sync extends Mock implements CloudSync {}

const _offline = DeploymentConfig(
  mode: DeploymentMode.offline,
  databaseHost: '192.168.1.20',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CloudSync? cloud,
  String language = 'en',
  List<Override> overrides = const [],
  PosStaff admin = _owner,
}) async {
  // The back office's narrowest: 1100 px across, pane and all.
  tester.view
    ..physicalSize = const Size(1100, 800)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      if (cloud != null) ...[
        cloudSyncProvider.overrideWithValue(cloud),
        lastPlatformSyncProvider.overrideWith(
          (ref) async => DateTime(2026, 9, 10, 7, 30),
        ),
        pendingSyncCountProvider.overrideWith((ref) async => 3),
      ],
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  if (cloud == null) {
    container.read(deploymentProvider.notifier).apply(_offline);
  }

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
        home: Scaffold(body: ManagementSyncPane(admin: admin)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

// `matchRoot`: some keys sit on the Text itself, not on a box around it.
Finder _in(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f, matchRoot: true);

/// System › Sync: what it claims on each kind of till.
void main() {
  const s = EnStrings();
  const ar = ArStrings();

  setUpAll(loadPosFonts);

  group('a cloud till', () {
    testWidgets('says when the bundle came, what is unsent, and no problem', (
      tester,
    ) async {
      await _pump(tester, cloud: _Sync());

      expect(find.byKey(const Key('sync-cloud')), findsOneWidget);
      expect(find.text('2026-09-10 07:30'), findsOneWidget);
      expect(_in('sync-unsent', find.text('3')), findsOneWidget);
      expect(_in('sync-problem', find.text(s.syncNoProblem)), findsOneWidget);
      // None of the offline answer.
      expect(find.text(s.syncOfflineTill), findsNothing);
      expect(find.byKey(const Key('sync-database')), findsNothing);
    });

    testWidgets('"sync now" runs the same pass the pill runs, and says what '
        'it sent', (tester) async {
      final cloud = _Sync();
      when(cloud.run).thenAnswer(
        (_) async => const SyncOutcome(drain: DrainReport(delivered: 3)),
      );
      await _pump(tester, cloud: cloud);

      await tester.tap(find.byKey(const Key('sync-now')));
      await tester.pumpAndSettle();

      verify(cloud.run).called(1);
      expect(find.text(s.syncPassSent(3)), findsOneWidget);
    });

    testWidgets('a pass the platform went silent on is the last problem', (
      tester,
    ) async {
      final cloud = _Sync();
      when(cloud.run).thenAnswer(
        (_) async =>
            const SyncOutcome(drain: DrainReport(delivered: 1, wentOffline: true)),
      );
      await _pump(tester, cloud: cloud);

      await tester.tap(find.byKey(const Key('sync-now')));
      await tester.pumpAndSettle();

      expect(
        _in('sync-problem', find.text(s.syncPlatformSilent)),
        findsOneWidget,
      );
    });

    testWidgets('a rejected terminal outranks everything', (tester) async {
      await _pump(
        tester,
        cloud: _Sync(),
        overrides: [terminalRejectedProvider.overrideWith((ref) => true)],
      );
      expect(
        _in('sync-problem', find.text(s.terminalRejectedTitle)),
        findsOneWidget,
      );
    });
  });

  group('held sync items (D1/D2/D13)', () {
    // A sale the platform refused because the item was deleted there, and a
    // refund the till would not send. One from each queue, with the same id,
    // because the two tables number their rows independently.
    final sale = HeldSyncItem(
      id: 7,
      kind: HeldSyncKind.sale,
      code: QuarantineCode.menuItemNotFound,
      rawCode: 'MENU_ITEM_NOT_FOUND',
      lastError: '422 MENU_ITEM_NOT_FOUND Menu item 88 does not exist.',
      reference: 'MAADI-000042',
      quarantinedAt: DateTime(2026, 9, 9, 13, 5),
      attempts: 1,
    );
    final refund = HeldSyncItem(
      id: 7,
      kind: HeldSyncKind.refund,
      code: QuarantineCode.refundHasNoLines,
      rawCode: 'REFUND_HAS_NO_LINES',
      sourceId: 31,
      quarantinedAt: DateTime(2026, 9, 9, 14),
      attempts: 0,
    );

    const cashier = PosStaff(
      id: 4,
      name: 'Rana A.',
      role: PosRole(
        id: 9,
        code: 'cashier',
        nameEn: 'Cashier',
        capabilities: {PosCapability.operate},
      ),
    );

    testWidgets('are counted apart from the unsent, and named as the problem '
        'without a pass having run', (tester) async {
      final queue = FakeSyncQueueRepository([sale, refund]);
      await _pump(
        tester,
        cloud: _Sync(),
        overrides: [syncQueueRepositoryProvider.overrideWithValue(queue)],
      );

      // Three unsent, two held — never five unsent.
      expect(_in('sync-unsent', find.text('3')), findsOneWidget);
      expect(_in('sync-held', find.text('2')), findsOneWidget);
      // Read from the queue, so a restart does not forget them (D8).
      expect(_in('sync-problem', find.text(s.syncHeld(2))), findsOneWidget);
    });

    testWidgets('each says what it is, why in words, and what the platform '
        'said', (tester) async {
      final queue = FakeSyncQueueRepository([sale, refund]);
      await _pump(
        tester,
        cloud: _Sync(),
        overrides: [syncQueueRepositoryProvider.overrideWithValue(queue)],
      );

      final saleRow = find.byKey(const Key('held-sale-7'));
      expect(
        find.descendant(of: saleRow, matching: find.text(s.heldKindSale)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: saleRow, matching: find.text('MAADI-000042')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: saleRow,
          matching: find.text(s.quarantineMenuItemNotFound),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: saleRow,
          matching: find.text(
            '422 MENU_ITEM_NOT_FOUND Menu item 88 does not exist.',
          ),
        ),
        findsOneWidget,
      );

      final refundRow = find.byKey(const Key('held-event-7'));
      expect(
        find.descendant(
          of: refundRow,
          matching: find.text(s.quarantineRefundHasNoLines),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Retry puts that one record back and runs the drain', (
      tester,
    ) async {
      final cloud = _Sync();
      when(cloud.kick).thenReturn(null);
      final queue = FakeSyncQueueRepository([sale, refund]);
      await _pump(
        tester,
        cloud: cloud,
        overrides: [syncQueueRepositoryProvider.overrideWithValue(queue)],
      );

      await tester.tap(find.byKey(const Key('held-retry-sale-7')));
      await tester.pumpAndSettle();

      // The sale, not the refund that shares its id.
      expect(queue.released.single.kind, HeldSyncKind.sale);
      expect(queue.held.single.kind, HeldSyncKind.refund);
      verify(cloud.kick).called(1);
      expect(find.byKey(const Key('held-sale-7')), findsNothing);
      expect(find.byKey(const Key('held-event-7')), findsOneWidget);
    });

    testWidgets('somebody who may not manage the terminal sees them and '
        'cannot retry', (tester) async {
      final cloud = _Sync();
      final queue = FakeSyncQueueRepository([sale]);
      await _pump(
        tester,
        cloud: cloud,
        admin: cashier,
        overrides: [syncQueueRepositoryProvider.overrideWithValue(queue)],
      );

      expect(find.byKey(const Key('held-sale-7')), findsOneWidget);
      expect(find.text(s.heldSyncNotYours), findsOneWidget);

      await tester.tap(find.byKey(const Key('held-retry-sale-7')));
      await tester.pumpAndSettle();

      expect(queue.released, isEmpty);
      verifyNever(cloud.kick);
    });

    testWidgets('nothing held says so', (tester) async {
      await _pump(tester, cloud: _Sync());
      expect(find.byKey(const Key('held-sync-none')), findsOneWidget);
      expect(_in('sync-held', find.text('0')), findsOneWidget);
    });

    testWidgets('in Arabic: the reason in Arabic, the codes left to right', (
      tester,
    ) async {
      final queue = FakeSyncQueueRepository([sale]);
      await _pump(
        tester,
        cloud: _Sync(),
        language: 'ar',
        overrides: [syncQueueRepositoryProvider.overrideWithValue(queue)],
      );

      expect(find.text(ar.quarantineMenuItemNotFound), findsOneWidget);
      expect(find.text(ar.heldSyncRetry), findsOneWidget);
      final reference = tester.widget<Text>(find.text('MAADI-000042'));
      expect(reference.textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });
  });

  group('an offline till', () {
    final backups = backupsProvider.overrideWith(
      (ref) async => [
        // Newest first; the newest failed, so the verified one is the copy.
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
    );

    testWidgets('says plainly it does not sync, and offers no sync', (
      tester,
    ) async {
      await _pump(tester, overrides: [backups]);

      expect(find.text(s.syncOfflineTill), findsOneWidget);
      expect(find.byKey(const Key('sync-now')), findsNothing);
      expect(find.byKey(const Key('sync-cloud')), findsNothing);
    });

    testWidgets('names the branch server, the database — never its '
        'credential — and the last verified copy', (tester) async {
      final container = await _pump(tester, overrides: [backups]);
      final config = container.read(deploymentProvider);

      expect(find.text(s.branchDatabaseReady), findsOneWidget);
      expect(
        find.text('${config.databaseName} · 192.168.1.20:${config.databasePort}'),
        findsOneWidget,
      );
      expect(find.textContaining(config.databaseUser), findsNothing);
      expect(
        _in('sync-last-backup', find.text('2026-09-09 23:45')),
        findsOneWidget,
      );
    });
  });

  group('in Arabic at 1100 px', () {
    testWidgets('cloud: Arabic words, the count left to right, nothing '
        'overflows', (tester) async {
      await _pump(tester, cloud: _Sync(), language: 'ar');

      expect(find.text(ar.syncNoProblem), findsOneWidget);
      expect(find.text(ar.syncNow), findsOneWidget);
      final count = tester.widget<Text>(_in('sync-unsent', find.text('3')));
      expect(count.textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offline: the sentence in Arabic, the address left to right', (
      tester,
    ) async {
      await _pump(tester, language: 'ar');

      expect(find.text(ar.syncOfflineTill), findsOneWidget);
      final address = tester.widget<Text>(
        _in('sync-database', find.byType(Text)),
      );
      expect(address.textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });
  });

  group('syncProblemOf', () {
    test('nothing wrong is null', () {
      expect(
        syncProblemOf(
          terminalRejected: false,
          online: true,
          countUnreadable: false,
        ),
        isNull,
      );
    });

    test('worst first: a rejected credential over a silent platform', () {
      expect(
        syncProblemOf(
          terminalRejected: true,
          online: false,
          countUnreadable: true,
        ),
        SyncProblem.terminalRejected,
      );
    });

    test('held records are named from the queue, not only by a pass', () {
      expect(
        syncProblemOf(
          terminalRejected: false,
          online: true,
          countUnreadable: false,
          heldCount: 1,
        ),
        SyncProblem.held,
      );
    });

    test('held sales are named by the pass that held them', () {
      expect(
        syncProblemOf(
          terminalRejected: false,
          online: true,
          countUnreadable: false,
          lastPass: const SyncOutcome(drain: DrainReport(quarantined: 2)),
        ),
        SyncProblem.held,
      );
    });

    test('every problem has words in both languages', () {
      for (final problem in SyncProblem.values) {
        expect(syncProblemLabel(s, problem, held: 2), isNotEmpty);
        expect(syncProblemLabel(ar, problem, held: 2), isNotEmpty);
      }
    });
  });
}
