import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/eta_submission.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/eta_serialization.dart';
import 'pos_database.dart';

/// The queue of receipts owed to Egypt's tax authority.
///
/// **The chain is why this is not the outbox.** Each receipt names the uuid of
/// the one before it from the same device, so enqueuing is not an append — it
/// is a read of the chain head, a build against it, and a write of both, and
/// all three have to be one transaction. Two tills sharing a device serial is
/// a misconfiguration; two threads on one till racing the head is a Tuesday.
class PostgresEtaQueueRepository implements EtaQueueRepository {
  const PostgresEtaQueueRepository({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    required this.branchId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;
  final int branchId;

  @override
  Future<EtaEnqueued> enqueue({
    required int orderId,
    required String deviceSerial,
    required String receiptNumber,
    required String receiptType,
    required DateTime issuedAt,
    required EtaObject Function(String previousUuid) build,
    int? refundId,
  }) => _db.runTx(config, (tx) async {
    // The head, locked. Without the lock two receipts built in the same second
    // would claim the same predecessor, and the authority would reject the
    // second — with an error naming a uuid neither till has heard of.
    final head = await tx.execute(
      Sql.named(
        'SELECT last_uuid FROM pos_eta_chains '
        'WHERE branch_id = @branch AND device_serial = @device FOR UPDATE',
      ),
      parameters: {'branch': branchId, 'device': deviceSerial},
    );
    final previousUuid = head.isEmpty ? '' : head.first[0]! as String;

    final document = build(previousUuid);
    final uuid = ((document['header']! as EtaObject)['uuid']! as EtaText).value;

    final inserted = await tx.execute(
      Sql.named('''
      INSERT INTO pos_eta_receipts
        (restaurant_id, branch_id, order_id, refund_id, device_serial, uuid,
         previous_uuid, receipt_number, receipt_type, document, canonical,
         issued_at, status)
      VALUES
        (@restaurant, @branch, @order, @refund, @device, @uuid, @previous,
         @number, @type, @document::jsonb, @canonical, @issued, 'pending')
      RETURNING id
      '''),
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'order': orderId,
        'refund': refundId,
        'device': deviceSerial,
        'uuid': uuid,
        'previous': previousUuid,
        'number': receiptNumber,
        'type': receiptType,
        'document': jsonEncode(EtaSerializer.toJson(document)),
        // Stored beside the document, not recomputed on demand. A rejection
        // two days later is investigated against what was actually hashed,
        // and rebuilding it today would serialise a menu that has changed.
        'canonical': EtaSerializer.canonical(document),
        'issued': issuedAt.toUtc(),
      },
    );

    await tx.execute(
      Sql.named('''
      INSERT INTO pos_eta_chains (branch_id, device_serial, last_uuid)
      VALUES (@branch, @device, @uuid)
      ON CONFLICT (branch_id, device_serial)
      DO UPDATE SET last_uuid = excluded.last_uuid, updated_at = now()
      '''),
      parameters: {'branch': branchId, 'device': deviceSerial, 'uuid': uuid},
    );

    return EtaEnqueued(
      id: inserted.first[0]! as int,
      uuid: uuid,
      previousUuid: previousUuid,
      document: document,
    );
  });

  static const _columns =
      'id, order_id, refund_id, uuid, receipt_number, issued_at, status, '
      'device_serial, attempts, submitted_at, error_message, long_id';

  EtaSubmission _read(List<dynamic> row) => EtaSubmission(
    id: row[0]! as int,
    orderId: row[1]! as int,
    refundId: row[2] as int?,
    uuid: row[3]! as String,
    receiptNumber: row[4]! as String,
    issuedAt: (row[5]! as DateTime).toUtc(),
    status: EtaStatus.fromWire(row[6]! as String),
    deviceSerial: row[7]! as String,
    attempts: row[8]! as int,
    submittedAt: (row[9] as DateTime?)?.toUtc(),
    errorMessage: row[10] as String?,
    longId: row[11] as String?,
  );

  @override
  Future<List<EtaSubmission>> outstanding({int limit = 200}) async {
    final rows = await _db.query(
      config,
      'SELECT $_columns FROM pos_eta_receipts '
      "WHERE branch_id = @branch AND status NOT IN ('accepted', 'cancelled') "
      // Oldest first: the deadline runs from issuance, so the one closest to
      // it is the one that matters.
      'ORDER BY issued_at ASC LIMIT @limit',
      parameters: {'branch': branchId, 'limit': limit},
    );
    return [for (final row in rows) _read(row)];
  }

  @override
  Future<EtaQueueSummary> summary({required DateTime now}) async {
    final rows = await _db.query(
      config,
      '''
      SELECT
        count(*) FILTER (WHERE status NOT IN ('accepted', 'cancelled')),
        count(*) FILTER (WHERE status = 'rejected'),
        count(*) FILTER (WHERE status NOT IN ('accepted', 'cancelled')
                           AND issued_at <= @deadline),
        min(issued_at) FILTER (WHERE status NOT IN ('accepted', 'cancelled'))
      FROM pos_eta_receipts WHERE branch_id = @branch
      ''',
      parameters: {
        'branch': branchId,
        // Computed here rather than in SQL's `now()`: the caller's clock is
        // the one the screen shows, and two clocks would disagree about which
        // receipts are late.
        'deadline': now.toUtc().subtract(EtaSubmission.window),
      },
    );

    final row = rows.first;
    return EtaQueueSummary(
      outstanding: (row[0] as int?) ?? 0,
      rejected: (row[1] as int?) ?? 0,
      late: (row[2] as int?) ?? 0,
      oldest: (row[3] as DateTime?)?.toUtc(),
    );
  }

  @override
  Future<String?> canonicalFor(int id) async {
    final rows = await _db.query(
      config,
      'SELECT canonical FROM pos_eta_receipts WHERE id = @id',
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : rows.first[0] as String?;
  }

  @override
  Future<void> markSigned(int id, String signature) => _db.query(
    config,
    "UPDATE pos_eta_receipts SET signature = @signature, status = 'signed' "
    "WHERE id = @id AND status = 'pending'",
    parameters: {'id': id, 'signature': signature},
  ).then((_) {});

  @override
  Future<void> markAccepted(
    int id, {
    required String submissionUuid,
    String? longId,
  }) => _db.query(
    config,
    '''
    UPDATE pos_eta_receipts
       SET status = 'accepted', submitted_at = now(),
           submission_uuid = @submission, long_id = @long,
           error_message = NULL, attempts = attempts + 1
     WHERE id = @id
    ''',
    parameters: {'id': id, 'submission': submissionUuid, 'long': longId},
  ).then((_) {});

  @override
  Future<void> markRejected(int id, String message) => _db.query(
    config,
    '''
    UPDATE pos_eta_receipts
       SET status = 'rejected', error_message = @message,
           last_attempt_at = now(), attempts = attempts + 1
     WHERE id = @id
    ''',
    parameters: {'id': id, 'message': message},
  ).then((_) {});

  @override
  Future<void> markAttempted(int id, String message) => _db.query(
    config,
    // Status untouched: a network failure is not a verdict, and moving a
    // signed receipt to `rejected` because the line was down would put a
    // person in front of a problem no person can fix.
    '''
    UPDATE pos_eta_receipts
       SET error_message = @message, last_attempt_at = now(),
           attempts = attempts + 1
     WHERE id = @id
    ''',
    parameters: {'id': id, 'message': message},
  ).then((_) {});
}
