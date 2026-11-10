import '../../core/config/deployment.dart';
import '../sql/row_reads.dart';
import '../sql/sql.dart';
import '../../domain/models/waiter_shift.dart';
import '../../domain/repositories/repositories.dart' show WaiterShiftReader;

// The record moved to the domain so the back office can read it without
// reaching into this file; exported so the waiter link's imports stand.
export '../../domain/models/waiter_shift.dart' show WaiterShiftRecord;

/// `pos_waiter_shifts`, on either engine: the waiter shift clock.
///
/// One open shift per person, held by the partial unique index
/// `pos_waiter_shifts_one_open`; [start] returns the open one instead of
/// opening a second, so two handhelds tapping at once agree. The times are the
/// database's clock, the same for every handheld on the branch.
class PostgresWaiterShifts implements WaiterShiftReader {
  PostgresWaiterShifts({
    required SqlDatabase database,
    required this.config,
    required this.businessId,
    required this.branchId,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final int businessId;
  final int branchId;

  static const _columns = 'id, user_id, started_at, ended_at';

  /// [staffId]'s open shift, or null.
  Future<WaiterShiftRecord?> open(int staffId) async {
    final rows = await _db.query(
      config,
      'SELECT $_columns FROM pos_waiter_shifts '
      'WHERE business_id = @business AND user_id = @staff AND ended_at IS NULL',
      parameters: {'business': businessId, 'staff': staffId},
    );
    return rows.isEmpty ? null : _shift(rows.single);
  }

  /// Open a shift for [staffId] on [deviceId]; an open one comes back as it is.
  Future<WaiterShiftRecord> start(int staffId, {int? deviceId}) async {
    final existing = await open(staffId);
    if (existing != null) return existing;
    try {
      final rows = await _db.query(
        config,
        'INSERT INTO pos_waiter_shifts (business_id, branch_id, user_id, started_device_id) '
        'VALUES (@business, @branch, @staff, @device) '
        'RETURNING $_columns',
        parameters: {'business': businessId, 'branch': branchId, 'staff': staffId, 'device': deviceId},
      );
      return _shift(rows.single);
    } on Object {
      // Another handheld opened it between the read and the insert: the
      // unique index refused ours, and theirs is the shift.
      final raced = await open(staffId);
      if (raced != null) return raced;
      rethrow;
    }
  }

  /// Close [staffId]'s open shift on [deviceId] and return it; null if none.
  Future<WaiterShiftRecord?> finish(int staffId, {int? deviceId}) async {
    final rows = await _db.query(
      config,
      'UPDATE pos_waiter_shifts SET ended_at = now(), ended_device_id = @device '
      'WHERE business_id = @business AND user_id = @staff AND ended_at IS NULL '
      'RETURNING $_columns',
      parameters: {'business': businessId, 'staff': staffId, 'device': deviceId},
    );
    return rows.isEmpty ? null : _shift(rows.single);
  }

  /// This branch's shifts that overlap [from]–[to] (still-open ones included),
  /// newest first, with the waiter's and handhelds' names: the back office's
  /// time record.
  @override
  Future<List<WaiterShiftRecord>> between(DateTime from, DateTime to) async {
    final rows = await _db.query(
      config,
      'SELECT s.id, s.user_id, s.started_at, s.ended_at, st.name, ds.name, de.name '
      'FROM pos_waiter_shifts s '
      'JOIN pos_users st ON st.id = s.user_id '
      'LEFT JOIN pos_waiter_devices ds ON ds.id = s.started_device_id '
      'LEFT JOIN pos_waiter_devices de ON de.id = s.ended_device_id '
      'WHERE s.business_id = @business AND (s.branch_id = @branch OR s.branch_id IS NULL) '
      'AND s.started_at < @to AND (s.ended_at IS NULL OR s.ended_at >= @from) '
      'ORDER BY s.started_at DESC, s.id DESC',
      parameters: {
        'business': businessId,
        'branch': branchId,
        'from': from.toUtc(),
        'to': to.toUtc(),
      },
    );
    return [
      for (final row in rows)
        WaiterShiftRecord(
          id: row[0]! as int,
          staffId: row[1]! as int,
          startedAt: row.dateTime(2),
          endedAt: row.dateTimeOrNull(3),
          staffName: row[4] as String?,
          startedDevice: row[5] as String?,
          endedDevice: row[6] as String?,
        ),
    ];
  }

  static WaiterShiftRecord _shift(List<Object?> row) => WaiterShiftRecord(
    id: row[0]! as int,
    staffId: row[1]! as int,
    startedAt: row.dateTime(2),
    endedAt: row.dateTimeOrNull(3),
  );
}
