import 'package:uuid/uuid.dart';

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
    required int serviceMinor,
    required int vatMinor,
    required int totalMinor,
    required List<Map<String, Object?>> lines,
    required List<Map<String, Object?>> payments,
    int? tableId,
    int? actingUserId,
    DateTime? catalogSyncedAt,
  }) => {
    'client_transaction_id': clientTransactionId,
    'branch_id': branchId,
    'order_type': orderType,
    'table_id': tableId,
    'acting_user_id': actingUserId,
    'shift_client_id': null,
    'created_at': occurredAt.toUtc().toIso8601String(),
    'priced_offline': true,
    'catalog_synced_at': catalogSyncedAt?.toUtc().toIso8601String(),
    'lines': lines,
    'asserted_totals': {
      'subtotal_minor': subtotalMinor,
      'discount_minor': 0,
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
  }) => {
    'menu_item_id': menuItemId,
    // The variant option, when there is one, travels inside option_ids[] —
    // the 2026-09-02 amendment; the server resolves is_variant itself.
    'option_ids': optionIds,
    'quantity': quantity,
    'note': note,
    'name_snapshot': nameSnapshot,
    'unit_price_minor': unitPriceMinor,
  };

  /// One pass: oldest first, stop on silence.
  Future<DrainReport> run() async {
    if (!config.mode.syncsSalesToPlatform) return const DrainReport();

    final pending = await _db.query(config, '''
      SELECT ob.id, o.id, o.client_transaction_id, o.branch_id, o.order_type,
             o.table_id, o.currency, o.exponent, o.subtotal_minor,
             o.service_minor, o.vat_minor, o.total_minor, o.occurred_at,
             s.opened_by, o.restaurant_id
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
        restaurantId: row[14] as int,
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
        serviceMinor: row[9] as int,
        vatMinor: row[10] as int,
        totalMinor: row[11] as int,
        occurredAt: (row[12] as DateTime),
        actingUserId: row[13] as int?,
        lines: await _linesFor(orderId),
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
        await _db.query(
          config,
          '''
          UPDATE pos_outbox
          SET delivered_at = now(), attempts = attempts + 1, last_attempt_at = now(),
              last_error = NULL, server_order_id = @serverId,
              server_invoice_number = @invoice, totals_mismatch = @mismatch
          WHERE id = @id
          ''',
          parameters: {
            'id': outboxId,
            'serverId': data['id'] is int ? data['id'] : null,
            'invoice': data['invoice_number'] as String?,
            // The server re-priced and disagreed. The order still exists on
            // both sides — this marks it for the reconciliation view, it does
            // not fail anything (POS-R081).
            'mismatch': data['totals_mismatch'] == true,
          },
        );
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

  Future<List<Map<String, Object?>>> _linesFor(int orderId) async {
    final rows = await _db.query(
      config,
      'SELECT menu_item_id, name_snapshot, modifier_ids, quantity, '
      '       unit_price_minor, note '
      'FROM pos_order_lines WHERE order_id = @order ORDER BY id',
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
        ),
    ];
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
