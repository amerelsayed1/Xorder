import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/config/pos_db_secret_store.dart';
import 'package:xorder_pos/data/backup/pg_tools.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/backup.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';
import 'package:xorder_pos/features/admin/presentation/management_backup_pane.dart';
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

  // In memory: the file-backed store is `FileSecretStore`'s own test's
  // business, and real disk writes do not complete on a widget test's clock.
  late _MemoryStore reader;
  setUp(() => reader = _MemoryStore());

  Future<void> open(
    WidgetTester tester, {
    List<BackupRecord> records = const [],
    bool filesExist = true,
    ManagementPane pane = ManagementPane.backup,
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
        // Whether a file is on disk is a fact about the box running the tests.
        backupFileExistsProvider.overrideWithValue((_) => filesExist),
        backupPasswordStoreProvider.overrideWithValue(reader),
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
            onReconfigure: () {},
            initialPane: pane,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Through Admin Mode's door, as the owner.
    await enterAdminMode(tester);
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
        contains('USB drive'),
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

    // And the button is dead rather than hopeful. Scrolled to first: the
    // account section sits above it, and a list does not build what is below
    // the fold.
    await tester.scrollUntilVisible(
      find.byKey(const Key('backup-now')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ManagementBackupPane),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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

  testWidgets('the backup account: it says when no password is kept, and '
      'keeps the one entered', (tester) async {
    // The nightly copy runs at day close with nobody in the back office, so
    // the account it signs in as has to be answerable without anyone typing.
    await open(tester);
    expect(find.text(strings.backupAccountMissing), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('backup-account-password')),
      'read-only-please',
    );
    await tester.tap(find.byKey(const Key('backup-account-save')));
    await tester.pumpAndSettle();

    expect(reader.value, 'read-only-please');
    expect(find.text(strings.backupAccountStored), findsOneWidget);
    // And the field is emptied: a password left sitting in a box on a till
    // screen is a password on a till screen.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('backup-account-password')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('a verified copy can go to a USB drive', (tester) async {
    await open(tester, records: [record(outcome: BackupOutcome.verified)]);

    expect(find.byKey(const Key('backup-copy-1')), findsOneWidget);
    expect(find.text(strings.backupCopyAction), findsOneWidget);
  });

  testWidgets('a copy whose file is gone says so, and offers nothing to press',
      (tester) async {
    // Only the newest copies stay on disk, so an old verified row with no file
    // is the ordinary case. Its Restore would fail; its Copy would copy
    // nothing.
    await open(
      tester,
      records: [record(outcome: BackupOutcome.verified, daysAgo: 20)],
      filesExist: false,
    );

    expect(find.text(strings.backupOutcomeVerified), findsOneWidget);
    expect(find.text(strings.backupFileGone), findsOneWidget);
    expect(find.text(strings.backupRestoreAction), findsNothing);
    expect(find.text(strings.backupCopyAction), findsNothing);
  });

  testWidgets('a copy brought back on a drive can be restored from', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const Key('backup-restore-file')), findsOneWidget);
    expect(find.text(strings.backupRestoreFromFile), findsOneWidget);
  });

  testWidgets('the back office says when there is no copy, and goes to Backup',
      (tester) async {
    // Said here, for somebody who can act on it — not on the start screen a
    // cashier opens the till from.
    await open(tester, pane: ManagementPane.staff);

    expect(find.byKey(const Key('management-backup-notice')), findsOneWidget);
    expect(find.text(strings.backupNoneYet), findsOneWidget);

    await tester.tap(find.byKey(const Key('management-backup-open')));
    await tester.pumpAndSettle();

    expect(find.byType(ManagementBackupPane), findsOneWidget);
    expect(find.byKey(const Key('management-backup-notice')), findsNothing);
  });

  testWidgets('not on the Backup pane, which says it already', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('management-backup-notice')), findsNothing);
  });

  testWidgets('a copy verified today says nothing', (tester) async {
    await open(
      tester,
      pane: ManagementPane.staff,
      records: [record(outcome: BackupOutcome.verified)],
    );
    expect(find.byKey(const Key('management-backup-notice')), findsNothing);
  });

  testWidgets('an old one is called old, wherever the manager is', (
    tester,
  ) async {
    await open(
      tester,
      pane: ManagementPane.staff,
      records: [record(outcome: BackupOutcome.verified, daysAgo: 4)],
    );
    expect(find.text(strings.backupStale(4)), findsOneWidget);
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

class _MemoryStore implements PosDbSecretStore {
  String? value;

  @override
  Object? get lastFailure => null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}
