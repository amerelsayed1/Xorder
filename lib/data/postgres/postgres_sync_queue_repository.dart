import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/held_sync.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';

/// Held sync records, read from both outbox tables and released into them.
///
/// **On the till's credential, not the administrator's.** A cloud terminal's
/// back office has no admin connection to speak of, and the till role already
/// holds UPDATE on both outboxes — the drain writes `quarantined_at` on them
/// through it. Asking for the administrator password to undo what the till's
/// own credential did would gate a Retry button behind a secret the person in
/// front of it rarely has, and protect nothing the grant does not already
/// allow. What does gate it is `terminal.manage`, asked below.
///
/// Scoped to this restaurant and branch, as `pendingSyncCount` is, so the held
/// count and the unsent count are two halves of the same queue.
class PostgresSyncQueueRepository implements SyncQueueRepository {
  const PostgresSyncQueueRepository({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    required this.branchId,
    this.terminalId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;
  final int branchId;
  final String? terminalId;

  /// A screenful, oldest problems not hidden behind newer ones for long: a
  /// till with more than this held has a fault support should be on the phone
  /// about, not one somebody clears with Retry two hundred times.
  static const listLimit = 200;

  /// Both queues' held rows in one shape. `is_sale` rather than a sentinel in
  /// `event_type`, so the lifecycle CHECK can grow without colliding with it.
  static const _heldSql = '''
    SELECT * FROM (
      SELECT true AS is_sale, ob.id, NULL::text AS event_type,
             ob.quarantine_code, ob.last_error, o.invoice_number,
             NULL::bigint AS source_id, ob.quarantined_at, ob.attempts
        FROM pos_outbox ob
        JOIN pos_orders o ON o.id = ob.order_id
       WHERE ob.restaurant_id = @restaurant AND ob.branch_id = @branch
         AND ob.delivered_at IS NULL AND ob.quarantined_at IS NOT NULL
      UNION ALL
      SELECT false, q.id, q.event_type, q.quarantine_code, q.last_error,
             NULL::text, q.source_id, q.quarantined_at, q.attempts
        FROM pos_sync_outbox q
       WHERE q.restaurant_id = @restaurant AND q.branch_id = @branch
         AND q.delivered_at IS NULL AND q.quarantined_at IS NOT NULL
    ) held
    ORDER BY quarantined_at DESC, id DESC
  ''';

  @override
  Future<List<HeldSyncItem>> listHeldSync() async {
    // The same gate `pendingSyncCount` uses. An offline till that was once a
    // cloud one can carry held rows from that life; nothing will ever drain
    // them here, so a Retry button beside them would be a button that does
    // nothing.
    if (!config.mode.syncsSalesToPlatform) return const [];

    final rows = await _db.query(
      config,
      '$_heldSql LIMIT $listLimit',
      parameters: {'restaurant': restaurantId, 'branch': branchId},
    );
    return [for (final row in rows) _read(row)];
  }

  @override
  Future<int> heldSyncCount() async {
    if (!config.mode.syncsSalesToPlatform) return 0;

    final rows = await _db.query(
      config,
      '''
      SELECT (
        (SELECT count(*) FROM pos_outbox
          WHERE restaurant_id = @restaurant AND branch_id = @branch
            AND delivered_at IS NULL AND quarantined_at IS NOT NULL)
        +
        (SELECT count(*) FROM pos_sync_outbox
          WHERE restaurant_id = @restaurant AND branch_id = @branch
            AND delivered_at IS NULL AND quarantined_at IS NOT NULL)
      )::bigint
      ''',
      parameters: {'restaurant': restaurantId, 'branch': branchId},
    );
    return rows.first[0] as int;
  }

  @override
  Future<AdminResult<HeldSyncItem>> releaseHeldSync(
    HeldSyncItem item, {
    required PosStaff by,
  }) async {
    // `Authorization.check`, never `by.capabilities`: that is the direct
    // grants alone, and an owner holds `terminal.manage` through the role.
    if (!Authorization.check(by, PosCapability.terminalManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.terminalManage),
      );
    }

    // A constant chosen by the enum, never a string from the caller.
    final table = item.kind.isSale ? 'pos_outbox' : 'pos_sync_outbox';

    return _db.runTx(config, (tx) async {
      // Locked and re-read rather than trusting the screen's copy: two
      // managers on two tills can both be looking at the same held sale, and
      // the audit row must carry what the row actually said when it was
      // released — not what one of them saw a minute ago.
      final held = await tx.execute(
        Sql.named('''
          SELECT quarantine_code, last_error, attempts
            FROM $table
           WHERE id = @id AND restaurant_id = @restaurant
             AND delivered_at IS NULL AND quarantined_at IS NOT NULL
           FOR UPDATE
        '''),
        parameters: {'id': item.id, 'restaurant': restaurantId},
      );
      if (held.isEmpty) {
        return const AdminResult<HeldSyncItem>.refused(EditedElsewhere(0));
      }

      // `attempts` is left alone: it counts conversations with the platform,
      // and support reading "attempts 3" after a release needs to know two of
      // them happened before it.
      await tx.execute(
        Sql.named('''
          UPDATE $table
             SET quarantined_at = NULL, quarantine_code = NULL,
                 last_error = NULL
           WHERE id = @id AND restaurant_id = @restaurant
        '''),
        parameters: {'id': item.id, 'restaurant': restaurantId},
      );

      await tx.execute(
        Sql.named(
          'INSERT INTO pos_audit_events (restaurant_id, branch_id, '
          '  terminal_id, actor_staff_id, actor_name, action, entity_type, '
          '  entity_id, before_value) '
          'VALUES (@restaurant, @branch, @terminal, @actor, @actorName, '
          '        @action, @entityType, @entityId, @before::jsonb)',
        ),
        parameters: {
          'restaurant': restaurantId,
          'branch': branchId,
          'terminal': terminalId,
          'actor': by.id == 0 ? null : by.id,
          'actorName': by.name,
          'action': AuditAction.syncRecordReleased,
          'entityType': AuditAction.entitySyncRecord,
          'entityId': '$table:${item.id}',
          // What was cleared. After the release the row no longer says why it
          // was held, so this is the only place that does.
          'before': jsonEncode({
            'kind': item.kind.name,
            'reference': item.reference,
            'source_id': item.sourceId,
            'quarantine_code': held.first[0],
            'last_error': held.first[1],
            'attempts': held.first[2],
          }),
        },
      );

      return AdminResult.done(item);
    });
  }

  HeldSyncItem _read(List<Object?> row) {
    final isSale = row[0]! as bool;
    final rawCode = row[3] as String?;
    return HeldSyncItem(
      id: row[1]! as int,
      kind: isSale
          ? HeldSyncKind.sale
          : HeldSyncKind.fromEventType(row[2]! as String),
      code: QuarantineCode.fromWire(rawCode),
      rawCode: rawCode,
      lastError: row[4] as String?,
      reference: row[5] as String?,
      sourceId: row[6] as int?,
      quarantinedAt: (row[7]! as DateTime).toLocal(),
      attempts: row[8]! as int,
    );
  }
}
