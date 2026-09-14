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
        home: const Scaffold(body: ManagementSyncPane(admin: _owner)),
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
