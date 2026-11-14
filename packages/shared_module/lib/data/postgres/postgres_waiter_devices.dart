import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../core/config/deployment.dart';
import '../sql/row_reads.dart';
import '../sql/sql.dart';

/// A waiter handheld paired with this till (waiter-app, migration 65).
class WaiterDevice {
  const WaiterDevice({
    required this.id,
    required this.name,
    required this.pairedAt,
    this.lastSeenAt,
    this.revokedAt,
  });

  final int id;
  final String name;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
}

/// `pos_waiter_devices`, on either engine.
///
/// **The token never touches the disk.** [register] makes 32 random bytes,
/// stores their SHA-256 and hands the token back once, for the handheld to
/// keep; [byToken] hashes what a request carries and looks the hash up. A copy
/// of this table, or of a backup, opens nothing.
class PostgresWaiterDevices {
  PostgresWaiterDevices({
    required SqlDatabase database,
    required this.config,
    required this.businessId,
    required this.branchId,
    Random? random,
  }) : _db = database,
       _random = random ?? Random.secure();

  final SqlDatabase _db;
  final DeploymentConfig config;
  final int businessId;
  final int branchId;
  final Random _random;

  static String hashOf(String token) => sha256.convert(utf8.encode(token)).toString();

  /// Store a new device and return it with its token.
  Future<(WaiterDevice, String)> register(String name) async {
    final token = base64Url
        .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
        .replaceAll('=', '');
    final rows = await _db.query(
      config,
      'INSERT INTO pos_waiter_devices (business_id, branch_id, name, token_hash) '
      'VALUES (@business, @branch, @name, @hash) '
      'RETURNING id, name, paired_at, last_seen_at, revoked_at',
      parameters: {
        'business': businessId,
        'branch': branchId,
        'name': name.trim(),
        'hash': hashOf(token),
      },
    );
    return (_device(rows.single), token);
  }

  /// The device [token] was issued to — revoked ones included, so the caller
  /// can say "revoked" rather than "unknown" — or null.
  Future<WaiterDevice?> byToken(String token) async {
    if (token.isEmpty) return null;
    final rows = await _db.query(
      config,
      'SELECT id, name, paired_at, last_seen_at, revoked_at FROM pos_waiter_devices '
      'WHERE token_hash = @hash AND business_id = @business',
      parameters: {'hash': hashOf(token), 'business': businessId},
    );
    return rows.isEmpty ? null : _device(rows.single);
  }

  /// Every device this branch has paired, newest first.
  Future<List<WaiterDevice>> all() async {
    final rows = await _db.query(
      config,
      'SELECT id, name, paired_at, last_seen_at, revoked_at FROM pos_waiter_devices '
      'WHERE business_id = @business AND (branch_id = @branch OR branch_id IS NULL) '
      'ORDER BY paired_at DESC, id DESC',
      parameters: {'business': businessId, 'branch': branchId},
    );
    return [for (final row in rows) _device(row)];
  }

  Future<void> touch(int id) => _db.query(
    config,
    'UPDATE pos_waiter_devices SET last_seen_at = now() '
    'WHERE id = @id AND business_id = @business',
    parameters: {'id': id, 'business': businessId},
  );

  /// Revoke [id]. Idempotent: an already-revoked device keeps its first date.
  Future<void> revoke(int id) => _db.query(
    config,
    'UPDATE pos_waiter_devices SET revoked_at = now() '
    'WHERE id = @id AND business_id = @business AND revoked_at IS NULL',
    parameters: {'id': id, 'business': businessId},
  );

  static WaiterDevice _device(List<Object?> row) => WaiterDevice(
    id: row[0]! as int,
    name: row[1]! as String,
    pairedAt: row.dateTime(2),
    lastSeenAt: row.dateTimeOrNull(3),
    revokedAt: row.dateTimeOrNull(4),
  );
}
