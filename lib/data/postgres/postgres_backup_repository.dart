import '../../core/config/deployment.dart';
import '../../domain/models/backup.dart';
import '../../domain/models/shift.dart';
import '../../domain/repositories/admin_repositories.dart';
import 'pos_database.dart';

/// `pos_backups` — every copy taken of this database, and how it went.
///
/// **On the till's credential, like the audit ledger.** The automatic copy is
/// taken at day close by a machine on which nobody has opened the back office,
/// so binding this to the administrator connection would mean the only nights
/// with a record are the nights somebody happened to be in Management. INSERT
/// and SELECT and nothing else, on both this interface and the grant — see
/// migration 37 for why the database refuses the rest as well.
class PostgresBackupRepository implements BackupRepository {
  const PostgresBackupRepository({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    this.branchId,
    this.terminalId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;
  final int? branchId;
  final String? terminalId;

  static const _columns =
      'id, taken_at, taken_by, taken_by_name, trigger_kind, outcome, '
      'file_path, size_bytes, checksum, tables_found, failure, detail';

  @override
  Future<List<BackupRecord>> recent({int limit = 50}) async {
    final rows = await _db.query(
      config,
      'SELECT $_columns FROM pos_backups WHERE restaurant_id = @restaurant '
      // Newest first, and id as the tie-break: a manual backup taken in the
      // same second as the day-close one is not hypothetical on a fast disk.
      'ORDER BY taken_at DESC, id DESC LIMIT @limit',
      parameters: {'restaurant': restaurantId, 'limit': limit},
    );

    return [for (final row in rows) _record(row.toList())];
  }

  @override
  Future<BackupRecord> record(
    BackupRecord entry, {
    required PosStaff by,
  }) async {
    final rows = await _db.query(
      config,
      'INSERT INTO pos_backups (restaurant_id, branch_id, terminal_id, '
      '  taken_at, taken_by, taken_by_name, trigger_kind, outcome, file_path, '
      '  size_bytes, checksum, tables_found, failure, detail) '
      'VALUES (@restaurant, @branch, @terminal, @takenAt, @by, @byName, '
      '  @trigger, @outcome, @file, @size, @checksum, @tables, @failure, '
      '  @detail) '
      'RETURNING $_columns',
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'terminal': terminalId,
        'takenAt': entry.takenAt.toUtc(),
        // Zero is the id a `PosStaff` carries before it has been read from the
        // database, and there is no staff row 0 to point at.
        'by': by.id == 0 ? null : by.id,
        'byName': by.name,
        'trigger': entry.trigger.wire,
        'outcome': entry.outcome.wire,
        'file': entry.filePath,
        'size': entry.sizeBytes,
        'checksum': entry.checksum,
        'tables': entry.tablesFound,
        'failure': entry.failure?.wire,
        'detail': entry.detail,
      },
    );

    return _record(rows.first.toList());
  }

  static BackupRecord _record(List<Object?> row) => BackupRecord(
    id: row[0] as int?,
    takenAt: (row[1]! as DateTime).toLocal(),
    takenById: row[2] as int?,
    takenByName: row[3]! as String,
    trigger: BackupTrigger.fromWire(row[4]! as String),
    outcome: BackupOutcome.fromWire(row[5]! as String),
    filePath: row[6]! as String,
    sizeBytes: row[7] as int? ?? 0,
    checksum: row[8] as String?,
    tablesFound: row[9] as int? ?? 0,
    failure: BackupFailure.fromWire(row[10] as String?),
    detail: row[11] as String?,
  );
}

/// What a terminal with no branch database answers with.
///
/// Empty, and [record] refuses out loud. Reporting a backup as recorded while
/// writing nowhere is the exact shape of the bug this feature exists to close.
class UnconfiguredBackupRepository implements BackupRepository {
  const UnconfiguredBackupRepository();

  @override
  Future<List<BackupRecord>> recent({int limit = 50}) async => const [];

  @override
  Future<BackupRecord> record(
    BackupRecord entry, {
    required PosStaff by,
  }) async => throw StateError(
    'This terminal has nowhere to record a backup. It is not connected to a '
    'database — and with no database there is nothing to back up.',
  );
}
