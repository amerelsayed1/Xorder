import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/backup/pg_tools.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/backup.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

/// The Backup pane, and the claims it makes.
///
/// Ship blocker 11 said `backup.manage` was "grantable, risk-classified
/// critical, held only by Owner — and honoured by no screen". These tests are
/// about the screen it now has, and specifically about the three things it
/// would be worth building wrong:
///
/// * it tells the truth about what a copy on this disk protects against;
/// * a copy that failed verification is shown as **not a backup** and cannot be
///   restored from;
/// * the pane is not there at all for somebody without the capability.
void main() {
  const strings = EnStrings();

  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: SystemRoles.ownerCode,
      nameEn: 'Owner',
      capabilities: SystemRoles.owner,
    ),
  );
  const manager = PosStaff(
    id: 2,
    name: 'Nour A.',
    role: PosRole(
      id: 2,
      code: SystemRoles.managerCode,
      nameEn: 'Manager',
      capabilities: SystemRoles.manager,
    ),
  );

  BackupRecord record({
    required BackupOutcome outcome,
    BackupFailure? failure,
    String file = '/backups/xorder_pos-20260908-231407.dump',
    int size = 4404019,
    int daysAgo = 0,
  }) => BackupRecord(
    id: 1,
    takenAt: DateTime.now().subtract(Duration(days: daysAgo)),
    takenByName: 'Amer M.',
    trigger: BackupTrigger.dayClose,
    outcome: outcome,
    filePath: file,
    sizeBytes: size,
    checksum: outcome == BackupOutcome.failed ? null : 'a' * 64,
    tablesFound: outcome == BackupOutcome.failed ? 0 : 44,
    failure: failure,
    detail: failure == null ? null : 'pg_restore: error: did not find magic',
  );

  Future<void> open(
    WidgetTester tester, {
    List<BackupRecord> records = const [],
    PgToolset? tools = const PgToolset(
      pgDump: '/usr/local/bin/pg_dump',
      pgRestore: '/usr/local/bin/pg_restore',
      version: '16.11',
    ),
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        backupRepositoryProvider.overrideWithValue(
          FakeBackupRepository(records: records),
        ),
        // Overridden rather than left to look at the real machine: whether
        // PostgreSQL happens to be installed on the box running the tests is
        // not what any of these assertions are about.
        pgToolsProvider.overrideWith((ref) async => tools),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildPosTheme(),
          home: ManagementScreen(
            onClose: () {},
            initialPane: ManagementPane.backup,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final digit in '1234'.split('')) {
      await tester.tap(find.widgetWithText(InkWell, digit).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('it says what a copy on this disk does not protect against', (
    tester,
  ) async {
    // The honest sentence, and the one most likely to be quietly softened by
    // somebody who thinks it reads badly. A restaurant that believes a local
    // dump is a backup will not make a second copy, and the disk that dies is
    // the disk the dump is on.
    await open(tester);

    final warning = find.textContaining('does not survive the disk failing');
    expect(warning, findsOneWidget);
    expect(
      tester.widget<Text>(warning).data,
      allOf(
        contains('stolen'),
        contains('Copy this folder somewhere else'),
      ),
    );
  });

  testWidgets('with no pg_dump it says so, and names where it looked', (
    tester,
  ) async {
    // A backup button that silently does nothing is worse than no button.
    await open(tester, tools: null);

    expect(find.text(strings.backupToolsMissing), findsOneWidget);
    expect(find.text(strings.backupToolsMissingHelp), findsOneWidget);
    expect(find.text(strings.backupSearchedIn.toUpperCase()), findsOneWidget);

    // And the button is dead rather than hopeful.
    final button = tester.widget<InkWell>(
      find
          .descendant(
            of: find.byKey(const Key('backup-now')),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(button.onTap, isNull);
  });

  testWidgets('a copy that failed verification is not offered as a backup', (
    tester,
  ) async {
    await open(
      tester,
      records: [
        record(
          outcome: BackupOutcome.unverified,
          failure: BackupFailure.archiveUnreadable,
        ),
      ],
    );

    expect(find.text(strings.backupOutcomeUnverified), findsOneWidget);
    expect(
      find.text(strings.backupRestoreAction),
      findsNothing,
      reason: 'a Restore button beside a file nobody could restore from is an '
          'invitation to try it at the worst possible moment',
    );
    // And the headline says the restaurant has no backup at all, rather than
    // "last backup: today".
    expect(find.text(strings.backupNoVerifiedCopy), findsOneWidget);
    // PostgreSQL's own words survive, untranslated, for whoever has to fix it.
    expect(find.textContaining('did not find magic'), findsOneWidget);
  });

  testWidgets('a verified copy can be restored from, and says how big it is', (
    tester,
  ) async {
    await open(tester, records: [record(outcome: BackupOutcome.verified)]);

    expect(find.text(strings.backupOutcomeVerified), findsOneWidget);
    expect(find.text(strings.backupRestoreAction), findsOneWidget);
    // 4,404,019 bytes. Mono, and a size somebody can read.
    expect(find.text('4.1 MB'), findsOneWidget);
    expect(find.text(strings.backupTablesFound(44)), findsOneWidget);
  });

  testWidgets('an old copy is called old', (tester) async {
    await open(
      tester,
      records: [record(outcome: BackupOutcome.verified, daysAgo: 9)],
    );

    expect(find.text(strings.backupStale(9)), findsOneWidget);
  });

  testWidgets('with nothing taken it says so rather than showing an empty list',
      (tester) async {
    await open(tester);
    expect(find.text(strings.backupNoneYet), findsOneWidget);
  });

  group('a size somebody can read', () {
    test('bytes become KB and MB, in integer arithmetic', () {
      // A size is a count, and this codebase does not put counted things in
      // floating point — `bytes / 1024 / 1024` is the habit the money code
      // exists to break.
      expect(AdminText.bytes(0), '0 B');
      expect(AdminText.bytes(812), '812 B');
      expect(AdminText.bytes(1024), '1.0 KB');
      expect(AdminText.bytes(4404019), '4.1 MB');
      expect(AdminText.bytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('and it rounds down, so a folder never looks bigger than it is', () {
      // 1023 bytes is not a kilobyte, and 1.9 MB is not 2.
      expect(AdminText.bytes(1023), '1023 B');
      expect(AdminText.bytes(2 * 1024 * 1024 - 1), '1.9 MB');
    });
  });

  group('who may see it at all', () {
    test('an owner does', () {
      final panes = managementPanesFor(
        admin: owner,
        authorsItsOwnCatalogue: true,
      );
      expect(panes, contains(ManagementPane.backup));
    });

    test('a manager does not, because backup.manage is the owner\'s', () {
      // §107 classifies it critical and `SystemRoles.manager` deliberately
      // omits it. A manager still reaches Management — they hold `staff.manage`
      // — so the pane has to be absent rather than the screen.
      expect(manager.can(PosCapability.staffManage), isTrue);
      expect(manager.can(PosCapability.backupManage), isFalse);

      final panes = managementPanesFor(
        admin: manager,
        authorsItsOwnCatalogue: true,
      );
      expect(panes, isNot(contains(ManagementPane.backup)));
      expect(panes, contains(ManagementPane.staff));
    });

    test('and it lives in System, beside Activity', () {
      expect(areaOf(ManagementPane.backup), ManagementArea.system);
      expect(
        areaOf(ManagementPane.activity),
        areaOf(ManagementPane.backup),
      );
    });
  });
}
