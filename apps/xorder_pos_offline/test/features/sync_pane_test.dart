import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/domain/models/sync_outcome.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/backup.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_sync_pane.dart';

import 'package:xorder_pos_test_support/fonts.dart';
import 'package:xorder_pos_test_support/fakes.dart';

// Held through the role, as a real owner holds it.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

const _offline = DeploymentConfig(
  mode: DeploymentMode.offline,
  databaseHost: '192.168.1.20',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
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
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  container.read(deploymentProvider.notifier).apply(_offline);

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

/// System › Sync, as the OFFLINE app shows it.
///
/// The cloud cases this file held — "a cloud till" (4), "held sync items"
/// (7) and the cloud Arabic layout (1) — left with the cloud branch of the
/// pane (pos-split-apps, stage 3): a cloud till has no back office (CB-07),
/// so there is no sync pane for it to show. What remains is the offline till
/// and the problem rule, which the home pane still reads.
void main() {
  const s = EnStrings();
  const ar = ArStrings();

  setUpAll(loadPosFonts);

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
