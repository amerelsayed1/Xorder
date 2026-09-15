import 'package:uuid/uuid.dart';
import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import '../postgres/pos_database.dart';
import 'cloud_api.dart';

/// What one drain pass did. Data, not logs — the sync pill renders it.
class DrainReport {
  const DrainReport({
    this.delivered = 0,
    this.quarantined = 0,
    this.deferred = 0,
    this.wentOffline = false,
  });

  final int delivered;
  final int quarantined;

  /// Held for retry — a refusal whose cure is time, not a person.
  final int deferred;

  /// True when the platform stopped answering mid-pass. The pass stops there:
  /// hammering a dead endpoint once per queued order helps nobody.
  final bool wentOffline;

  int get attempted => delivered + quarantined + deferred;
}

/// How the drain reacts to a POS-BE-019 code.
enum DrainAction {
  /// The record itself is at fault; retrying will never change the answer.
  /// Held out of the loop for a person, never deleted (money changed hands).
  quarantine,

  /// The refusal is about the tenant, the terminal or the moment — not the
  /// record. Everything stays queued and the pass moves on. This is also the
  /// fallback for a code this build has never heard of: *retry later, never
  /// discard* is the client's standing rule.
  defer,
}

/// Drains `pos_outbox` to `POST /api/pos/orders` (POS-BE-006/007).
///
/// The queue's invariants, restated where they are enforced:
///
/// * A sale is **never** removed from the outbox — `delivered_at` is set, rows
///   are not deleted. A till that forgets what it sent is a till that sends it
///   twice.
/// * The idempotency key is the order's `client_transaction_id`, so a pass that
///   dies between the server writing and the till recording gets the same
///   answer — same id, same invoice number — on the next pass (POS-BE-007).
/// * A rejection quarantines **that record**; it never stops the queue.
/// * A payment names its tender by the **platform's** id, read off the tender
///   row the bootstrap seeder wrote. A payment whose tender row did not come
///   from the platform is held here, before anything is sent — see
///   [tenderNotFromPlatform].
class OutboxDrain {
  const OutboxDrain({
    required PosDatabase database,
    required this.config,
    required this.api,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final PosCloudApi api;

  /// How many orders one pass will attempt. A four-hour outage drains over a
  /// few passes rather than one giant one, so a single bad connection blip
  /// costs a batch, not the backlog.
  static const passLimit = 25;

  /// The standard RFC 4122 URL namespace, used to derive **stable** per-payment
  /// keys from rows that predate `Tender.clientId`. Deterministic on purpose:
  /// the same payment row must present the same `client_transaction_id` on
  /// every pass, or a retry after a timeout would double-record the money.
  static const _namespace = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';

  /// The quarantine code for a sale paid on a tender the platform never sent.
  ///
  /// Decided on the till, not by a refusal from the platform, because the
  /// platform's answer is not safe to wait for: an id it does not know gets a
  /// 422, but an id that happens to match one of ITS tenders is accepted and
  /// booked against the wrong one — and card money counted as cash in a
  /// cash-up is found a week later, if at all. Nor is null an option: the
  /// platform's shift maths counts a payment with no tender as cash.
  static const tenderNotFromPlatform = 'TENDER_NOT_FROM_PLATFORM';

  static String paymentClientId({
    required String orderClientId,
    required int paymentRowId,
  }) => const Uuid().v5(
    _namespace,
    'xorder-pos:payment:$orderClientId:$paymentRowId',
  );

  /// Which codes condemn the record rather than the moment.
  ///
  /// Everything else — feature disabled, subscription lapsed, terminal revoked
  /// (BE-A04 says queued records are still accepted; if a server rejects
  /// anyway, that is a fight to have later, not money to discard), rate limits,
  /// codes from a future backend — defers.
  static DrainAction classify(String? code) => switch (code) {
    'VALIDATION_FAILED' ||
    'IDEMPOTENCY_PAYLOAD_MISMATCH' ||
    'MENU_ITEM_NOT_FOUND' ||
    'BRANCH_NOT_IN_TENANT' ||
    'CUSTOMER_NOT_FOUND' => DrainAction.quarantine,
    _ => DrainAction.defer,
  };

  /// The §006 request, as a pure function of local rows so it is testable
  /// without a database or a socket.
  ///
  /// `actingUserId` and `shiftClientId` are nullable per the 2026-09-02 v1
  /// relaxation: local rows can predate sign-in enforcement, and local shifts
  /// are not yet synced. The platform accepts and flags rather than rejects.
  static Map<String, Object?> buildOrderRequest({
    required String clientTransactionId,
    required int branchId,
    required String orderType,
    required String currency,
    required int exponent,
    required DateTime occurredAt,
    required int subtotalMinor,
    int discountMinor = 0,
    required int serviceMinor,
    required int vatMinor,
    required int totalMinor,
    required List<Map<String, Object?>> lines,
    required List<Map<String, Object?>> payments,
    int? tableId,
    int? actingUserId,
    String? shiftClientId,
    DateTime? catalogSyncedAt,
    Map<String, Object?>? orderDiscount,
  }) => {
    'client_transaction_id': clientTransactionId,
    'branch_id': branchId,
    'order_type': orderType,
    'table_id': tableId,
    'acting_user_id': actingUserId,
    'shift_client_id': shiftClientId,
    'created_at': occurredAt.toUtc().toIso8601String(),
    'priced_offline': true,
    'catalog_synced_at': catalogSyncedAt?.toUtc().toIso8601String(),
    'lines': lines,
    'order_discount': ?orderDiscount,
    'asserted_totals': {
      'subtotal_minor': subtotalMinor,
      'discount_minor': discountMinor,
      'charges_minor': serviceMinor,
      'tax_minor': vatMinor,
      'total_minor': totalMinor,
    },
    'payments': payments,
    'currency': currency,
    'exponent': exponent,
  };

  static Map<String, Object?> lineJson({
    required int? menuItemId,
    required String nameSnapshot,
    required List<int> optionIds,
    required int quantity,
    required int unitPriceMinor,
    String? note,
    Map<String, Object?>? discount,
    Map<String, Object?>? priceOverride,
  }) => {
    'menu_item_id': menuItemId,
    // The variant option, when there is one, travels inside option_ids[] —
    // the 2026-09-02 amendment; the server resolves is_variant itself.
    'option_ids': optionIds,
    'quantity': quantity,
    'note': note,
    'name_snapshot': nameSnapshot,
    'unit_price_minor': unitPriceMinor,
    'discount': ?discount,
    'price_override': ?priceOverride,
  };

  /// Drains causal lifecycle records around the sale queue.  A shift must
  /// exist before an order can name it; cash movements and refunds need the
  /// order/shift graph; a close comes last so the server computes the same
  /// drawer the terminal just closed.  This is the serial form of POS-BE-021's
  /// documented batch ordering and keeps one rejected record from holding
  /// money that follows it hostage.
  Future<DrainReport> run() async {
    if (!config.mode.syncsSalesToPlatform) return const DrainReport();

    final reports = <DrainReport>[];
    for (final phase in const [
      ['shift_open'],
      ['order'],
      ['cash_movement', 'refund'],
      ['shift_close'],
    ]) {
      final report = phase.first == 'order'
          ? await _drainOrders()
          : await _drainLifecycle(phase);
      reports.add(report);
      if (report.wentOffline) break;
    }

    return DrainReport(
      delivered: reports.fold(0, (sum, report) => sum + report.delivered),
      quarantined: reports.fold(0, (sum, report) => sum + report.quarantined),
      deferred: reports.fold(0, (sum, report) => sum + report.deferred),
      wentOffline: reports.any((report) => report.wentOffline),
    );
  }

  /// One pass: oldest first, stop on silence.
  Future<DrainReport> _drainOrders() async {

    final pending = await _db.query(config, '''
      SELECT ob.id, o.id, o.client_transaction_id, o.branch_id, o.order_type,
             o.table_id, o.currency, o.exponent, o.subtotal_minor,
             o.discount_minor, o.service_minor, o.vat_minor, o.total_minor,
             o.occurred_at, o.served_by, s.client_transaction_id,
             o.restaurant_id
      FROM pos_outbox ob
      JOIN pos_orders o ON o.id = ob.order_id
      LEFT JOIN pos_shifts s ON s.id = o.shift_id
      WHERE ob.delivered_at IS NULL AND ob.quarantined_at IS NULL
      ORDER BY ob.enqueued_at
      LIMIT $passLimit
      ''');

    var delivered = 0, quarantined = 0, deferred = 0;

    for (final row in pending) {
      final outboxId = row[0] as int;
      final orderId = row[1] as int;
      final clientTransactionId = row[2].toString();

      final payments = await _paymentsFor(
        orderId,
        clientTransactionId,
        restaurantId: row[16] as int,
      );
      if (payments.stranded.isNotEmpty) {
        await _hold(outboxId, payments.stranded);
        quarantined++;
        continue;
      }

      final request = buildOrderRequest(
        clientTransactionId: clientTransactionId,
        branchId: row[3] as int,
        orderType: row[4] as String,
        tableId: row[5] as int?,
        currency: row[6] as String,
        exponent: row[7] as int,
        subtotalMinor: row[8] as int,
        discountMinor: row[9] as int,
        serviceMinor: row[10] as int,
        vatMinor: row[11] as int,
        totalMinor: row[12] as int,
        occurredAt: (row[13] as DateTime),
        actingUserId: row[14] as int?,
        shiftClientId: row[15]?.toString(),
        lines: await _linesFor(orderId),
        orderDiscount: await _orderDiscountFor(orderId),
        payments: payments.sendable,
      );

      final reply = await api.submitOrder(request);

      if (reply.offline) {
        return DrainReport(
          delivered: delivered,
          quarantined: quarantined,
          deferred: deferred,
          wentOffline: true,
        );
      }

      if (reply.ok) {
        final data = reply.data;
        await _db.runTx(config, (tx) async {
          final parameters = <String, Object?>{
            'id': outboxId,
            'serverId': data['id'] is int ? data['id'] : null,
            'invoice': data['invoice_number'] as String?,
            // The server re-priced and disagreed. The order still exists on
            // both sides — this marks it for the reconciliation view, it does
            // not fail anything (POS-R081).
            'mismatch': data['totals_mismatch'] == true,
            'order': orderId,
          };
          await tx.execute(
            Sql.named('''
              UPDATE pos_outbox
                 SET delivered_at = now(), attempts = attempts + 1,
                     last_attempt_at = now(), last_error = NULL,
                     server_order_id = @serverId,
                     server_invoice_number = @invoice,
                     totals_mismatch = @mismatch
               WHERE id = @id
            '''),
            parameters: parameters,
          );
          // The platform invoice is authoritative for later history and
          // reprints.  Keep the terminal's provisional sequence separately:
          // two offline tills can legitimately issue the same local reference,
          // so overwriting the locally unique `invoice_number` would turn a
          // successful sync into a constraint failure.
          await tx.execute(
            Sql.named(
              'UPDATE pos_orders SET server_invoice_number = @invoice '
              'WHERE id = @order AND @invoice IS NOT NULL',
            ),
            parameters: parameters,
          );
        });
        delivered++;
        continue;
      }

      final action = classify(reply.code);
      await _db.query(
        config,
        '''
        UPDATE pos_outbox
        SET attempts = attempts + 1, last_attempt_at = now(), last_error = @error
            ${action == DrainAction.quarantine ? ', quarantined_at = now(), quarantine_code = @code' : ''}
        WHERE id = @id
        ''',
        parameters: {
          'id': outboxId,
          'error': '${reply.status} ${reply.code ?? ''} ${reply.message ?? ''}'
              .trim(),
          if (action == DrainAction.quarantine) 'code': reply.code,
        },
      );
      if (action == DrainAction.quarantine) {
        quarantined++;
      } else {
        deferred++;
      }
    }

    return DrainReport(
      delivered: delivered,
      quarantined: quarantined,
      deferred: deferred,
    );
  }

  Future<DrainReport> _drainLifecycle(List<String> types) async {
    final pending = await _db.query(
      config,
      '''
      SELECT id, event_type, source_id, client_transaction_id
        FROM pos_sync_outbox
       WHERE delivered_at IS NULL AND quarantined_at IS NULL
         AND event_type = ANY(@types)
       ORDER BY enqueued_at
       LIMIT $passLimit
      ''',
      parameters: {'types': types},
    );
    var delivered = 0, quarantined = 0, deferred = 0;

    for (final row in pending) {
      final eventId = row[0] as int;
      final eventType = row[1] as String;
      final sourceId = row[2] as int;
      final clientId = row[3].toString();
      final event = await _lifecycleEvent(
        eventType: eventType,
        sourceId: sourceId,
        clientTransactionId: clientId,
      );
      if (event == null) {
        await _quarantineLifecycle(
          eventId,
          code: 'LOCAL_SOURCE_MISSING',
          message:
              'The local ${eventType.replaceAll('_', ' ')} source row no '
              'longer has a complete platform payload. It was not sent.',
        );
        quarantined++;
        continue;
      }

      final reply = await event.send();
      if (reply.offline) {
        return DrainReport(
          delivered: delivered,
          quarantined: quarantined,
          deferred: deferred,
          wentOffline: true,
        );
      }
      if (reply.ok) {
        await _db.query(
          config,
          '''
          UPDATE pos_sync_outbox
             SET delivered_at = now(), attempts = attempts + 1,
                 last_attempt_at = now(), last_error = NULL
           WHERE id = @id
          ''',
          parameters: {'id': eventId},
        );
        delivered++;
        continue;
      }

      final action = classify(reply.code);
      if (action == DrainAction.quarantine) {
        await _quarantineLifecycle(
          eventId,
          code: reply.code ?? 'REJECTED',
          message: '${reply.status} ${reply.code ?? ''} ${reply.message ?? ''}'
              .trim(),
          incrementAttempt: true,
        );
        quarantined++;
      } else {
        await _db.query(
          config,
          '''
          UPDATE pos_sync_outbox
             SET attempts = attempts + 1, last_attempt_at = now(),
                 last_error = @error
           WHERE id = @id
          ''',
          parameters: {
            'id': eventId,
            'error': '${reply.status} ${reply.code ?? ''} ${reply.message ?? ''}'
                .trim(),
          },
        );
        deferred++;
      }
    }
    return DrainReport(
      delivered: delivered,
      quarantined: quarantined,
      deferred: deferred,
    );
  }

  Future<_LifecycleEvent?> _lifecycleEvent({
    required String eventType,
    required int sourceId,
    required String clientTransactionId,
  }) async => switch (eventType) {
    'shift_open' => _shiftOpenEvent(sourceId, clientTransactionId),
    'shift_close' => _shiftCloseEvent(sourceId, clientTransactionId),
    'cash_movement' => _cashMovementEvent(sourceId, clientTransactionId),
    // A refund needs the platform's order-item ids, not this database's local
    // line ids.  The writer does not enqueue one until that mapping exists;
    // keeping this guard makes an accidental/manual queue row visibly held
    // instead of ever posting a local id as though it were a platform id.
    'refund' => Future.value(null),
    _ => Future.value(null),
  };

  Future<_LifecycleEvent?> _shiftOpenEvent(
    int sourceId,
    String clientTransactionId,
  ) async {
    final rows = await _db.query(
      config,
      '''
      SELECT branch_id, opened_by, opened_at, opening_float_minor,
             client_transaction_id
        FROM pos_shifts WHERE id = @id
      ''',
      parameters: {'id': sourceId},
    );
    if (rows.isEmpty || rows.first[4]?.toString() != clientTransactionId) {
      return null;
    }
    final row = rows.first;
    final request = <String, Object?>{
      'client_transaction_id': clientTransactionId,
      'branch_id': row[0] as int,
      'acting_user_id': row[1] as int,
      'opened_at': (row[2] as DateTime).toUtc().toIso8601String(),
      'opening_float_minor': row[3] as int,
    };
    return _LifecycleEvent(request: request, send: () => api.openShift(request));
  }

  Future<_LifecycleEvent?> _shiftCloseEvent(
    int sourceId,
    String clientTransactionId,
  ) async {
    final rows = await _db.query(
      config,
      '''
      SELECT client_transaction_id, close_client_transaction_id, closed_by,
             closed_at, counted_cash_minor
        FROM pos_shifts WHERE id = @id
      ''',
      parameters: {'id': sourceId},
    );
    if (rows.isEmpty ||
        rows.first[0] == null ||
        rows.first[1]?.toString() != clientTransactionId ||
        rows.first[2] == null ||
        rows.first[3] == null ||
        rows.first[4] == null) {
      return null;
    }
    final row = rows.first;
    final shiftClientId = row[0].toString();
    final request = <String, Object?>{
      'client_transaction_id': clientTransactionId,
      'acting_user_id': row[2] as int,
      'closed_at': (row[3] as DateTime).toUtc().toIso8601String(),
      'counted_cash_minor': row[4] as int,
    };
    return _LifecycleEvent(
      request: request,
      send: () => api.closeShift(shiftClientId, request),
    );
  }

  Future<_LifecycleEvent?> _cashMovementEvent(
    int sourceId,
    String clientTransactionId,
  ) async {
    final rows = await _db.query(
      config,
      '''
      SELECT m.client_transaction_id, s.client_transaction_id, m.kind,
             m.amount_minor, reason.code, m.note, m.staff_id, m.occurred_at
        FROM pos_cash_movements m
        JOIN pos_shifts s ON s.id = m.shift_id
        LEFT JOIN pos_reason_codes reason ON reason.id = m.reason_id
       WHERE m.id = @id
      ''',
      parameters: {'id': sourceId},
    );
    if (rows.isEmpty ||
        rows.first[0]?.toString() != clientTransactionId ||
        rows.first[1] == null) {
      return null;
    }
    final row = rows.first;
    final kind = row[2] as String;
    final direction = switch (kind) {
      'pay_in' || 'float_adjust' => 'in',
      'pay_out' => 'out',
      _ => null,
    };
    if (direction == null) return null;
    final request = <String, Object?>{
      'client_transaction_id': clientTransactionId,
      'shift_client_id': row[1].toString(),
      'direction': direction,
      'amount_minor': row[3] as int,
      'reason': row[4] as String?,
      'reference': row[5] as String?,
      'acting_user_id': row[6] as int,
      'occurred_at': (row[7] as DateTime).toUtc().toIso8601String(),
    };
    return _LifecycleEvent(
      request: request,
      send: () => api.recordCashMovement(request),
    );
  }

  Future<void> _quarantineLifecycle(
    int eventId, {
    required String code,
    required String message,
    bool incrementAttempt = false,
  }) => _db.query(
    config,
    '''
    UPDATE pos_sync_outbox
       SET quarantined_at = now(), quarantine_code = @code, last_error = @error
           ${incrementAttempt ? ', attempts = attempts + 1, last_attempt_at = now()' : ''}
     WHERE id = @id
    ''',
    parameters: {'id': eventId, 'code': code, 'error': message},
  );

  Future<List<Map<String, Object?>>> _linesFor(int orderId) async {
    final rows = await _db.query(
      config,
      '''
      SELECT l.menu_item_id, l.name_snapshot, l.modifier_ids, l.quantity,
             l.unit_price_minor, l.note,
             coalesce(discount.amount_minor, 0)::bigint, discount.reason,
             override.unit_price_minor, override.reason
        FROM pos_order_lines l
        LEFT JOIN LATERAL (
          SELECT sum(d.amount_minor)::bigint AS amount_minor,
                 min(reason.code) AS reason
            FROM pos_order_discounts d
            LEFT JOIN pos_reason_codes reason ON reason.id = d.reason_id
           WHERE d.order_line_id = l.id
        ) discount ON true
        LEFT JOIN LATERAL (
          SELECT e.unit_price_after_minor AS unit_price_minor,
                 reason.code AS reason
            FROM pos_order_line_events e
            LEFT JOIN pos_reason_codes reason ON reason.id = e.reason_id
           WHERE e.order_line_id = l.id AND e.event = 'price_overridden'
           ORDER BY e.occurred_at DESC, e.id DESC
           LIMIT 1
        ) override ON true
       WHERE l.order_id = @order
       ORDER BY l.id
      ''',
      parameters: {'order': orderId},
    );
    return [
      for (final row in rows)
        lineJson(
          menuItemId: row[0] as int?,
          nameSnapshot: row[1] as String,
          optionIds: [
            if (row[2] is List)
              for (final id in row[2] as List)
                if (id is int) id,
          ],
          quantity: row[3] as int,
          unitPriceMinor: row[4] as int,
          note: row[5] as String?,
          discount: (row[6] as int) == 0
              ? null
              : {
                  'amount_minor': row[6] as int,
                  'reason': row[7] as String?,
                },
          priceOverride: row[8] == null
              ? null
              : {
                  'unit_price_minor': row[8] as int,
                  'reason': row[9] as String?,
                },
        ),
    ];
  }

  /// The platform's v1 envelope has one order-level discount object.  The
  /// local ledger can retain multiple component discounts (and their separate
  /// approvals), so their total is sent as the financial assertion while the
  /// component rows remain available locally for audit.
  Future<Map<String, Object?>?> _orderDiscountFor(int orderId) async {
    final rows = await _db.query(
      config,
      '''
      SELECT coalesce(sum(d.amount_minor), 0)::bigint, min(reason.code)
        FROM pos_order_discounts d
        LEFT JOIN pos_reason_codes reason ON reason.id = d.reason_id
       WHERE d.order_id = @order AND d.order_line_id IS NULL
      ''',
      parameters: {'order': orderId},
    );
    final amount = rows.first[0] as int;
    if (amount == 0) return null;
    return {'amount_minor': amount, 'reason': rows.first[1] as String?};
  }

  /// The §006 `payments[]`, plus the ones that cannot be sent.
  ///
  /// `pos_order_payments.tender_type_id` is the LOCAL row id — it is what the
  /// payment screen had in hand — and on a cloud till it means nothing to the
  /// platform. What goes on the wire is that row's `platform_id`, which only
  /// the bootstrap seeder writes. A payment whose row has none (one of the
  /// till's own four, the compiled-in fallback, or a row that is gone) is
  /// [stranded], and the whole order is held: a sale sent with one of its
  /// payments missing is a sale the platform records as underpaid.
  Future<({List<Map<String, Object?>> sendable, List<String> stranded})>
  _paymentsFor(
    int orderId,
    String orderClientId, {
    required int restaurantId,
  }) async {
    final rows = await _db.query(
      config,
      'SELECT p.id, t.platform_id, p.amount_minor, p.reference, p.occurred_at, '
      '       p.tender_type_id, p.label '
      'FROM pos_order_payments p '
      'LEFT JOIN pos_tender_types t '
      '  ON t.id = p.tender_type_id AND t.restaurant_id = @restaurant '
      'WHERE p.order_id = @order ORDER BY p.id',
      parameters: {'order': orderId, 'restaurant': restaurantId},
    );
    return (
      sendable: [
        for (final row in rows)
          if (row[1] case final int platformId)
            {
              'client_transaction_id': paymentClientId(
                orderClientId: orderClientId,
                paymentRowId: row[0] as int,
              ),
              'tender_type_id': platformId,
              'amount_minor': row[2] as int,
              'reference': row[3] as String?,
              'received_at': (row[4] as DateTime).toUtc().toIso8601String(),
            },
      ],
      stranded: [
        for (final row in rows)
          if (row[1] == null) '${row[6]} (payment method ${row[5]} on this till)',
      ],
    );
  }

  /// Quarantine an order before it is sent, saying which payment and why.
  ///
  /// `attempts` is left alone: it counts conversations with the platform, and
  /// this was not one. Nothing is deleted — money changed hands, and the row
  /// is what a person resolves it from.
  Future<void> _hold(int outboxId, List<String> stranded) async {
    await _db.query(
      config,
      '''
      UPDATE pos_outbox
      SET quarantined_at = now(), quarantine_code = @code, last_error = @error
      WHERE id = @id
      ''',
      parameters: {
        'id': outboxId,
        'code': tenderNotFromPlatform,
        'error':
            'Not sent: paid by ${stranded.join(', ')}, which the platform did '
            'not send this till. The platform would refuse it, or book it '
            'against a different payment method. Held for a person — do not '
            'resend it under a guessed method.',
      },
    );
  }
}

class _LifecycleEvent {
  const _LifecycleEvent({required this.request, required this.send});

  final Map<String, Object?> request;
  final Future<CloudReply> Function() send;
}

/// Wraps the local repository so every settled sale immediately pokes the
/// drain. The write itself is untouched — the sale commits to PostgreSQL with
/// its outbox claim in the same transaction, exactly as before; this only
/// makes "sold" and "synced" seconds apart instead of a timer apart.
class SyncingOrdersRepository implements OrdersRepository {
  const SyncingOrdersRepository(this._inner, this._kick);

  final OrdersRepository _inner;
  final void Function() _kick;

  @override
  Future<SubmitOrderResult> submit(Ticket ticket, {PosStaff? servedBy}) async {
    final result = await _inner.submit(ticket, servedBy: servedBy);
    _kick();
    return result;
  }

  @override
  Future<int> pendingSyncCount() => _inner.pendingSyncCount();

  /// Kicks the drain too. A voided order is a row the platform has to hear
  /// about as much as a paid one — arguably more, since it is the one a
  /// restaurant will be asked about.
  @override
  Future<SubmitOrderResult> voidOrder(
    Ticket ticket, {
    required PosStaff by,
    int? reasonId,
    String? note,
    Approval? approval,
    PosStaff? servedBy,
  }) async {
    final result = await _inner.voidOrder(
      ticket,
      by: by,
      reasonId: reasonId,
      note: note,
      approval: approval,
      servedBy: servedBy,
    );
    _kick();
    return result;
  }
}
