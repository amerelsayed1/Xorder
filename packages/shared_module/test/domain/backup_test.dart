import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/backup.dart';
import 'package:shared_module/domain/models/pos_settings.dart';

/// The rules about backups that hold without a database or a screen.
///
/// The one worth writing down is the default: automatic copies are **on** until
/// somebody turns them off. Everywhere else in this codebase the safe default is
/// the one that surprises nobody — blind close off, drawer-open reason on. Here
/// the surprising outcome is the silent one, so the default fails the other way.
void main() {
  group('what a business gets before anybody configures anything', () {
    test('a copy at day close, and the default folder', () {
      expect(BackupPolicy.defaults.onDayClose, isTrue);
      expect(BackupPolicy.defaults.directory, isNull);
    });

    test('an unconfigured settings table resolves to the same', () {
      final policy = BackupPolicy.from(PosSettings.empty);
      expect(policy.onDayClose, isTrue);
      expect(policy.directory, isNull);
    });

    test('and turning it off is a decision somebody made', () {
      final policy = BackupPolicy.from(
        PosSettings.resolve(
          const [
            PosSettingRow(
              scope: SettingScope.business,
              scopeId: '',
              key: SettingKey.backupOnDayClose,
              value: 'false',
            ),
            PosSettingRow(
              scope: SettingScope.business,
              scopeId: '',
              key: SettingKey.backupDirectory,
              value: r'D:\xorder-backups',
            ),
          ],
          branchId: '1',
          terminalId: 't',
        ),
      );

      expect(policy.onDayClose, isFalse);
      expect(policy.directory, r'D:\xorder-backups');
    });

    test('a folder somebody blanked reads as unset, not as the empty folder',
        () {
      final policy = BackupPolicy.from(
        PosSettings.resolve(
          const [
            PosSettingRow(
              scope: SettingScope.business,
              scopeId: '',
              key: SettingKey.backupDirectory,
              value: '   ',
            ),
          ],
          branchId: '1',
          terminalId: 't',
        ),
      );
      expect(policy.directory, isNull);
    });
  });

  group('how much of a backup a row is', () {
    BackupRecord row(BackupOutcome outcome) => BackupRecord(
      takenAt: DateTime(2026, 9, 8, 23, 14),
      takenByName: 'Amer M.',
      trigger: BackupTrigger.dayClose,
      outcome: outcome,
      filePath: '/backups/x.dump',
    );

    test('only a verified one can be restored from', () {
      expect(row(BackupOutcome.verified).isRestorable, isTrue);
      // The middle state is the point of the whole enum: a file exists, and
      // nothing could read it back. That is not a backup.
      expect(row(BackupOutcome.unverified).isRestorable, isFalse);
      expect(row(BackupOutcome.failed).isRestorable, isFalse);
    });

    test('an outcome from a newer build is treated as unproven', () {
      // Never as proven. A backup wrongly believed good is the failure this
      // whole feature exists to prevent, so the unknown case fails toward
      // "you do not have one".
      expect(BackupOutcome.fromWire('quantum'), BackupOutcome.unverified);
      expect(BackupOutcome.fromWire('verified'), BackupOutcome.verified);
    });

    test('a trigger from a newer build does not promise it will happen again',
        () {
      expect(BackupTrigger.fromWire('cron'), BackupTrigger.manual);
      expect(BackupTrigger.fromWire('day_close'), BackupTrigger.dayClose);
    });

    test('an unknown failure code is no failure this build can name', () {
      expect(BackupFailure.fromWire('meteor'), isNull);
      expect(BackupFailure.fromWire(null), isNull);
      expect(
        BackupFailure.fromWire('archive_incomplete'),
        BackupFailure.archiveIncomplete,
      );
    });

    test('age is measured from when it was taken', () {
      final record = row(BackupOutcome.verified);
      expect(
        record.ageAt(DateTime(2026, 9, 11, 23, 14)).inDays,
        3,
      );
    });
  });

  group('what a restore would cost', () {
    RestoreCheck check(List<RestoreBlocker> blockers) => RestoreCheck(
      from: BackupRecord(
        takenAt: DateTime(2026, 9, 8),
        takenByName: 'Amer M.',
        trigger: BackupTrigger.manual,
        outcome: BackupOutcome.verified,
        filePath: '/backups/x.dump',
      ),
      blockers: blockers,
      ordersSince: 0,
      valueSince: const Money(0),
    );

    test('no blockers means it may proceed', () {
      expect(check(const []).isPermitted, isTrue);
    });

    test('either blocker on its own stops it', () {
      for (final kind in RestoreBlockerKind.values) {
        expect(
          check([RestoreBlocker(kind: kind, count: 1)]).isPermitted,
          isFalse,
          reason: kind.name,
        );
      }
    });
  });
}
