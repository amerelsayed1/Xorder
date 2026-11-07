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

  /// The quarantine code for a refund given as a flat amount off the bill.
  ///
  /// `RefundEngine.quoteForAmount` attaches **no lines** on purpose: nobody
  /// said which food the money was for, so inventing an attribution would move
  /// `refunded_quantity` on a line the operator never chose. §010 requires
  /// `lines[]` and requires the tender to equal the line total, so there is no
  /// honest shape for this refund on that endpoint — the only two options are
  /// holding it here or making the attribution up on the wire, where it would
  /// corrupt the platform's own per-line counters instead of ours. Held, with
  /// the reason on the row, and raised as an amendment in
  /// `docs/coordination/POS_TO_BACKEND.md`.
  static const refundHasNoLines = 'REFUND_HAS_NO_LINES';

  /// The `last_error` on a row whose 2xx did not prove the platform wrote it.
  ///
  /// A captive portal, a proxy, a half-deployed backend: each can answer 200
  /// with a page, or with nothing, and before this the drain wrote
  /// `delivered_at` on the strength of the status alone — a sale the platform
  /// never saw, marked sent, never retried (D4). Deferred, never quarantined:
  /// the record is fine and the network is not, so the next pass on a real
  /// connection gets the real answer — and §007 idempotency makes the resend
  /// safe even if the platform did write it behind the page.
  static const malformedAck = 'MALFORMED_ACK';

  /// Whether a reply to `POST /api/pos/orders` proves the order exists there.
  ///
  /// The platform's own id is the proof, because it is the one field §006
  /// promises on both the 201 and the idempotent replay. The invoice number is
  /// deliberately not required: the contract makes it nullable, and refusing a
  /// genuine acceptance for lacking it would be a sale resent forever behind a
  /// server that had already said yes.
  static bool acknowledgesOrder(CloudReply reply) =>
      reply.ok && reply.parsed && reply.data['id'] is int;

  /// Whether a 2xx to a lifecycle endpoint proves anything at all: a JSON
  /// object. Most of these replies tell the till nothing it keeps, so there is
  /// no field to insist on — the customer's id is the exception, and it asks
  /// for it through its event's own `acknowledges`.
  static bool acknowledgesRecord(CloudReply reply) => reply.ok && reply.parsed;

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
    'CUSTOMER_NOT_FOUND' ||
    // §010: the platform's counters say this refund would give back more than
    // the sale took, in quantity or in money. Time cannot cure that — the
    // ceiling only ever comes down — so retrying it forever would be a queue
    // that never empties behind a record that will never be accepted.
    'REFUND_EXCEEDS_SOLD' => DrainAction.quarantine,
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

  /// One line of the §006 request.
  ///
  /// [clientLineId] is the till's own name for the line, and it is the LOCAL
  /// `pos_order_lines.id` as a string — required rather than optional because
  /// a line sent without one is a line no offline refund can ever address
  /// (§010: a refund line names itself by `client_line_id` when it has never
  /// seen `order_items.id`, which is every refund built during an outage).
  ///
  /// Not `line_key`. `TicketLine.keyFor` is `productId:sortedModifierIds` and
  /// `TicketEngine` merges only draft lines with the same key AND the same
  /// note, so one order legitimately holds two rows with the same key — a sent
  /// line plus a new draft of the same dish. The platform indexes
  /// `unique(order_id, client_line_id)`, so a key would make the second row a
  /// constraint failure on an order that is perfectly valid here.
  static Map<String, Object?> lineJson({
    required int? menuItemId,
    required String clientLineId,
    required String nameSnapshot,
    required List<int> optionIds,
    required int quantity,
    required int unitPriceMinor,
    String? note,
    Map<String, Object?>? discount,
    Map<String, Object?>? priceOverride,
  }) => {
    'client_line_id': clientLineId,
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

  /// The §010 request, a pure function of local rows for the same reason
  /// [buildOrderRequest] is one.
  ///
  /// [orderClientId] is the ORDER'S OWN `client_transaction_id`, never a
  /// platform id. §010 accepts either and detects a UUID by format, and the
  /// till's own key is the one it is certain of: the platform id arrives on the
  /// order's reply, which a refund written during the same outage has not seen.
  ///
  /// `kind` is always `refund`. The platform's `refund | void` axis asks
  /// whether a sale is being erased, and nothing reaches here to erase one — a
  /// local void takes no money, so §010 has nothing to record for it (the
  /// platform's order simply has no payments). `pos_refunds.kind`
  /// (`full | partial`) is a different question entirely, and the platform
  /// derives that one itself from its own counters.
  static Map<String, Object?> buildRefundRequest({
    required String clientTransactionId,
    required String orderClientId,
    required DateTime occurredAt,
    required List<Map<String, Object?>> lines,
    required List<Map<String, Object?>> tenders,
    String? reason,
    int? actingUserId,
    int? authorizedByUserId,
    String? shiftClientId,
  }) => {
    'client_transaction_id': clientTransactionId,
    'order_id': orderClientId,
    'kind': 'refund',
    'reason': reason,
    'acting_user_id': actingUserId,
    'authorized_by_user_id': authorizedByUserId,
    'shift_client_id': shiftClientId,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'lines': lines,
    'tenders': tenders,
  };

  /// One line of the §010 request, addressed the way [lineJson] promised it
  /// would be — so the two together are the whole of the mapping that used to
  /// be missing.
  static Map<String, Object?> refundLineJson({
    required int orderLineId,
    required int quantity,
    required int amountMinor,
  }) => {
    'client_line_id': '$orderLineId',
    'quantity': quantity,
    'amount_minor': amountMinor,
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
      // Customers first, and before orders on purpose: a sale can name one,
      // and the platform has to know who they are before it is told what they
      // bought. Same reasoning as the shift, which must exist before an order
      // can name it.
      ['customer'],
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
             o.business_id
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
        businessId: row[16] as int,
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

      // A 2xx that does not carry the order back is not a delivery (D4). Not
      // treated as offline either: something did answer, and stopping the
      // pass would let one portal page hold the whole backlog — while every
      // row it touches still counts the attempt, so a network that only ever
      // answers like this shows up as a climbing `attempts`, not as silence.
      if (reply.ok && !acknowledgesOrder(reply)) {
        await _db.query(
          config,
          '''
          UPDATE pos_outbox
             SET attempts = attempts + 1, last_attempt_at = now(),
                 last_error = @error
           WHERE id = @id
          ''',
          parameters: {'id': outboxId, 'error': malformedAck},
        );
        deferred++;
        continue;
      }

      if (reply.ok) {
        final data = reply.data;
        final invoice = data['invoice_number'] as String?;
        await _db.runTx(config, (tx) async {
          // One parameter map per statement, not one shared between the two.
          // The driver refuses a map carrying a variable its statement does
          // not name, and the shared map meant EVERY delivered sale threw here
          // — after the platform had accepted it. The sale was safe (§007
          // idempotency) and the queue never emptied: `delivered_at` was never
          // written, so the same sale was resent on every pass forever and the
          // "owed to the platform" count never came down.
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
            parameters: {
              'id': outboxId,
              'serverId': data['id'] is int ? data['id'] : null,
              'invoice': invoice,
              // The server re-priced and disagreed. The order still exists on
              // both sides — this marks it for the reconciliation view, it
              // does not fail anything (POS-R081).
              'mismatch': data['totals_mismatch'] == true,
            },
          );
          // The platform invoice is authoritative for later history and
          // reprints.  Keep the terminal's provisional sequence separately:
          // two offline tills can legitimately issue the same local reference,
          // so overwriting the locally unique `invoice_number` would turn a
          // successful sync into a constraint failure.
          //
          // The "only if there is one" guard is in Dart rather than in a
          // `WHERE @invoice IS NOT NULL`: in that position PostgreSQL has no
          // column to infer the parameter's type from and refuses the
          // statement outright (42P08), which is the second half of the same
          // defect as the shared parameter map above.
          if (invoice != null) {
            await tx.execute(
              Sql.named(
                'UPDATE pos_orders SET server_invoice_number = @invoice '
                'WHERE id = @order',
              ),
              parameters: {'order': orderId, 'invoice': invoice},
            );
          }
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
      final prepared = await _lifecycleEvent(
        eventType: eventType,
        sourceId: sourceId,
        clientTransactionId: clientId,
      );

      switch (prepared) {
        case _Held(:final code, :final message):
          await _quarantineLifecycle(eventId, code: code, message: message);
          quarantined++;

        case _Waiting(:final why):
          // `attempts` is left alone on purpose, exactly as [_hold] leaves it:
          // it counts conversations with the platform, and this record never
          // opened one. The cure is the next pass, once whatever it waits
          // behind has landed — so nothing here needs a person.
          await _db.query(
            config,
            'UPDATE pos_sync_outbox SET last_error = @error WHERE id = @id',
            parameters: {'id': eventId, 'error': why},
          );
          deferred++;

        case _Sendable(:final event):
          final reply = await event.send();
          if (reply.offline) {
            return DrainReport(
              delivered: delivered,
              quarantined: quarantined,
              deferred: deferred,
              wentOffline: true,
            );
          }
          // Same rule as the order path, same reason: a 2xx is only a
          // delivery when the body proves the platform wrote the record.
          if (reply.ok && !event.acknowledges(reply)) {
            await _db.query(
              config,
              '''
              UPDATE pos_sync_outbox
                 SET attempts = attempts + 1, last_attempt_at = now(),
                     last_error = @error
               WHERE id = @id
              ''',
              parameters: {'id': eventId, 'error': malformedAck},
            );
            deferred++;
            continue;
          }
          if (reply.ok) {
            // One transaction, so "this was delivered" and whatever the reply
            // carried back about the record cannot end up disagreeing — the
            // same discipline the order path applies to its invoice number.
            final data = reply.data;
            await _db.runTx(config, (tx) async {
              await tx.execute(
                Sql.named('''
                  UPDATE pos_sync_outbox
                     SET delivered_at = now(), attempts = attempts + 1,
                         last_attempt_at = now(), last_error = NULL
                   WHERE id = @id
                '''),
                parameters: {'id': eventId},
              );
              await event.record?.call(tx, data);
            });
            delivered++;
            continue;
          }

          final action = classify(reply.code);
          if (action == DrainAction.quarantine) {
            await _quarantineLifecycle(
              eventId,
              code: reply.code ?? 'REJECTED',
              message:
                  '${reply.status} ${reply.code ?? ''} ${reply.message ?? ''}'
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
                'error':
                    '${reply.status} ${reply.code ?? ''} ${reply.message ?? ''}'
                        .trim(),
              },
            );
            deferred++;
          }
      }
    }
    return DrainReport(
      delivered: delivered,
      quarantined: quarantined,
      deferred: deferred,
    );
  }

  /// What one queued lifecycle row turned into, before a word was said to the
  /// platform.
  ///
  /// An event type this build does not know quarantines rather than defers,
  /// which is the opposite of the rule for an unknown *error* code — and
  /// deliberately so. An unknown code comes from a newer server and the record
  /// is fine; an unknown `event_type` in our own queue means something wrote a
  /// row this code cannot build a request from, and no amount of waiting will
  /// teach it how.
  Future<_Prepared> _lifecycleEvent({
    required String eventType,
    required int sourceId,
    required String clientTransactionId,
  }) async => switch (eventType) {
    'shift_open' => _sendableOrHeld(
      eventType,
      await _shiftOpenEvent(sourceId, clientTransactionId),
    ),
    'shift_close' => _sendableOrHeld(
      eventType,
      await _shiftCloseEvent(sourceId, clientTransactionId),
    ),
    'cash_movement' => _sendableOrHeld(
      eventType,
      await _cashMovementEvent(sourceId, clientTransactionId),
    ),
    'customer' => _sendableOrHeld(
      eventType,
      await _customerEvent(sourceId, clientTransactionId),
    ),
    'refund' => await _refundEvent(sourceId, clientTransactionId),
    _ => _sendableOrHeld(eventType, null),
  };

  /// The shared answer for the three record types whose only local failure is
  /// "the source row no longer carries a complete payload".
  static _Prepared _sendableOrHeld(String eventType, _LifecycleEvent? event) =>
      event == null
      ? _Held(
          code: 'LOCAL_SOURCE_MISSING',
          message:
              'The local ${eventType.replaceAll('_', ' ')} source row no '
              'longer has a complete platform payload. It was not sent.',
        )
      : _Sendable(event);

  /// A customer created at the counter (POS-BE-014).
  ///
  /// **The reply is worth keeping**, unlike a shift's: it carries the
  /// platform's own customer id, and writing it back is what lets a sale
  /// uploaded afterwards name the person the dashboard already knows rather
  /// than a local row number that means nothing there.
  ///
  /// Only rows that have never been delivered are queued, so a customer who
  /// came DOWN in a bundle is never sent back up — they already have a
  /// `platform_id`, and re-posting them would be a write the platform has to
  /// resolve for no reason.
  Future<_LifecycleEvent?> _customerEvent(
    int sourceId,
    String clientTransactionId,
  ) async {
    final rows = await _db.query(
      config,
      'SELECT name, phone, email, address, client_transaction_id '
      'FROM pos_customers WHERE id = @id',
      parameters: {'id': sourceId},
    );
    if (rows.isEmpty || rows.first[4]?.toString() != clientTransactionId) {
      return null;
    }

    final row = rows.first;
    final request = <String, Object?>{
      'client_transaction_id': clientTransactionId,
      'name': row[0] as String,
      'phone': row[1] as String,
      'email': row[2] as String?,
      'address': row[3] as String?,
    };

    return _LifecycleEvent(
      request: request,
      send: () => api.createCustomer(request),
      // The id is the point of sending a customer at all. Marked delivered
      // without one, the row is never resent and `platform_id` is never
      // written — permanently, since a delivered row is never looked at
      // again — so the customer stays a local row number to the platform.
      // Requiring only a JSON object would have let `{}` do exactly that.
      acknowledges: (reply) =>
          acknowledgesRecord(reply) && reply.data['id'] is int,
      record: (tx, data) async {
        if (data['id'] case final int platformId) {
          await tx.execute(
            Sql.named(
              'UPDATE pos_customers SET platform_id = @platform '
              'WHERE id = @id',
            ),
            parameters: {'platform': platformId, 'id': sourceId},
          );
        }
      },
    );
  }

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

  /// The platform's cap on `variance_reason` (`CloseShiftRequest`).
  static const _varianceReasonMax = 255;

  /// What goes out as a shift close's `variance_reason`.
  ///
  /// The cashier's own note when there is one. The till has no field for a note
  /// today, so most closes have none, and then the reason is the till's own
  /// figures: that is a fact the platform can set against its own, which is
  /// what a reason is for. It is sent even when the till saw no variance — the
  /// platform's expected cash comes from the sales it attributed to the shift,
  /// and the two can disagree while the till's count balances.
  ///
  /// Never empty and never longer than the platform accepts.
  static String shiftCloseReason({
    required String? note,
    required int countedMinor,
    required int expectedMinor,
    required int varianceMinor,
  }) {
    final trimmed = note?.trim() ?? '';
    final reason = trimmed.isNotEmpty
        ? trimmed
        : 'No cashier note. Till closed with counted $countedMinor against '
              'expected $expectedMinor (variance $varianceMinor, minor units).';
    // Characters, as the platform counts them, not UTF-16 units: an Arabic or
    // emoji note cut by `substring` could end in half a character.
    final characters = reason.runes;
    return characters.length <= _varianceReasonMax
        ? reason
        : String.fromCharCodes(characters.take(_varianceReasonMax));
  }

  Future<_LifecycleEvent?> _shiftCloseEvent(
    int sourceId,
    String clientTransactionId,
  ) async {
    final rows = await _db.query(
      config,
      '''
      SELECT client_transaction_id, close_client_transaction_id, closed_by,
             closed_at, counted_cash_minor, expected_cash_minor,
             variance_minor, closing_note
        FROM pos_shifts WHERE id = @id
      ''',
      parameters: {'id': sourceId},
    );
    if (rows.isEmpty ||
        rows.first[0] == null ||
        rows.first[1]?.toString() != clientTransactionId ||
        rows.first[2] == null ||
        rows.first[3] == null ||
        rows.first[4] == null ||
        rows.first[5] == null ||
        rows.first[6] == null) {
      return null;
    }
    final row = rows.first;
    final shiftClientId = row[0].toString();
    final request = <String, Object?>{
      'client_transaction_id': clientTransactionId,
      'acting_user_id': row[2] as int,
      'closed_at': (row[3] as DateTime).toUtc().toIso8601String(),
      'counted_cash_minor': row[4] as int,
      // Always sent. The platform works out its own expected cash and answers
      // 422 to a count that differs from it unless a reason comes with it;
      // this drain quarantines a 422, so a close sent without one that the
      // platform disagreed with would stay open on the dashboard for good.
      'variance_reason': shiftCloseReason(
        note: row[7] as String?,
        countedMinor: row[4] as int,
        expectedMinor: row[5] as int,
        varianceMinor: row[6] as int,
      ),
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
             m.amount_minor, reason.code, m.note, m.user_id, m.occurred_at
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

  /// One queued refund as §010's request — or the local reason it is not going
  /// on this pass.
  ///
  /// **A refund can never precede its sale.** §010 resolves `order_id` against
  /// the platform's own orders, so a refund sent while its sale is still in
  /// `pos_outbox` earns a 422 for a fact that is about to stop being true.
  /// It waits instead: the phase order in [run] already sends orders first, so
  /// the usual case is that the sale went out moments ago in the same pass, and
  /// the wait only bites when the sale is held or the pass ran out of room.
  Future<_Prepared> _refundEvent(
    int sourceId,
    String clientTransactionId,
  ) async {
    final rows = await _db.query(
      config,
      '''
      SELECT r.client_refund_id, o.client_transaction_id, reason.code, r.note,
             r.refunded_by, r.approved_by_id, shift.client_transaction_id,
             r.occurred_at, r.business_id,
             sale.id, sale.delivered_at, sale.quarantined_at
        FROM pos_refunds r
        JOIN pos_orders o ON o.id = r.order_id
        LEFT JOIN pos_shifts shift ON shift.id = r.shift_id
        LEFT JOIN pos_reason_codes reason ON reason.id = r.reason_id
        LEFT JOIN LATERAL (
          SELECT ob.id, ob.delivered_at, ob.quarantined_at
            FROM pos_outbox ob
           WHERE ob.order_id = o.id
           ORDER BY ob.id
           LIMIT 1
        ) sale ON true
       WHERE r.id = @id
      ''',
      parameters: {'id': sourceId},
    );
    if (rows.isEmpty || rows.first[0]?.toString() != clientTransactionId) {
      return _sendableOrHeld('refund', null);
    }
    final row = rows.first;

    if (row[9] == null) {
      return const _Held(
        code: 'SALE_NEVER_QUEUED',
        message:
            'The sale this refund reverses was never queued for the platform, '
            'so the platform has no order for it to name. Held for a person: '
            'the refund is recorded in this database and the money did leave '
            'the drawer.',
      );
    }
    if (row[10] == null) {
      return _Waiting(
        row[11] == null
            ? 'Waiting for the sale this refund reverses to reach the '
                  'platform. Nothing was sent.'
            // Self-healing on purpose rather than quarantined alongside the
            // sale: whoever unsticks the sale should not then have to find
            // this row too.
            : 'The sale this refund reverses is held for a person. This '
                  'refund goes as soon as that sale does.',
      );
    }

    final lines = await _refundLinesFor(sourceId);
    if (lines.isEmpty) {
      return const _Held(
        code: refundHasNoLines,
        message:
            'This refund was given as an amount off the bill rather than '
            'against chosen lines, and the platform requires lines that add '
            'up to the tender. Held for a person rather than attributing it '
            'to food nobody chose.',
      );
    }

    final tenders = await _refundTendersFor(
      sourceId,
      businessId: row[8] as int,
    );
    if (tenders.stranded.isNotEmpty) {
      return _Held(
        code: tenderNotFromPlatform,
        message:
            'Not sent: handed back by ${tenders.stranded.join(', ')}, which '
            'the platform did not send this till. The platform would refuse '
            'it, or book it against a different payment method — and a card '
            'refund booked as cash is a drawer that is short. Held for a '
            'person.',
      );
    }

    final request = buildRefundRequest(
      clientTransactionId: clientTransactionId,
      orderClientId: row[1].toString(),
      // The coded reason, which is the axis the platform reports on. The free
      // note stays local: §010 has one `reason` string, and gluing the two
      // together would make every grouped refund report a list of one.
      reason: row[2] as String? ?? row[3] as String?,
      // The local staff id IS the platform's user id on a cloud till — the
      // bootstrap seeder writes `pos_users` under the platform's own ids, and
      // the order path already sends `served_by` on that basis.
      actingUserId: row[4] as int?,
      authorizedByUserId: row[5] as int?,
      shiftClientId: row[6]?.toString(),
      occurredAt: row[7] as DateTime,
      lines: lines,
      tenders: tenders.sendable,
    );

    return _Sendable(
      _LifecycleEvent(
        request: request,
        send: () => api.submitRefund(request),
        // The platform's credit note number, kept exactly as the platform's
        // invoice number is kept on a sale: it is what an auditor asks for,
        // and it is drawn from the platform's own `CN-` sequence, so the till
        // cannot derive it.
        record: (tx, data) async {
          final number = data['credit_note_number'] as String?;
          if (number == null) return;
          await tx.execute(
            Sql.named(
              'UPDATE pos_refunds SET server_credit_note_number = @number '
              'WHERE id = @refund',
            ),
            parameters: {'refund': sourceId, 'number': number},
          );
        },
      ),
    );
  }

  /// The §010 `lines[]`, addressed by the local line id.
  Future<List<Map<String, Object?>>> _refundLinesFor(int refundId) async {
    final rows = await _db.query(
      config,
      'SELECT order_line_id, quantity, line_total_minor '
      'FROM pos_refund_lines WHERE refund_id = @refund ORDER BY id',
      parameters: {'refund': refundId},
    );
    return [
      for (final row in rows)
        refundLineJson(
          orderLineId: row[0] as int,
          quantity: row[1] as int,
          amountMinor: row[2] as int,
        ),
    ];
  }

  /// The §010 `tenders[]`, plus the ones that cannot be sent.
  ///
  /// Identical reasoning to [_paymentsFor], applied to money going the other
  /// way: `pos_refund_payments.tender_type_id` is the LOCAL row id, and only
  /// its `platform_id` means anything to the platform. One stranded tender
  /// holds the whole refund, because §010 requires the tenders to balance the
  /// lines — half of them would be refused anyway, and a refund recorded short
  /// would understate what a shift handed back.
  Future<({List<Map<String, Object?>> sendable, List<String> stranded})>
  _refundTendersFor(int refundId, {required int businessId}) async {
    final rows = await _db.query(
      config,
      'SELECT t.platform_id, p.amount_minor, p.tender_type_id, p.label '
      'FROM pos_refund_payments p '
      'LEFT JOIN pos_tender_types t '
      '  ON t.id = p.tender_type_id AND t.business_id = @restaurant '
      'WHERE p.refund_id = @refund ORDER BY p.id',
      parameters: {'refund': refundId, 'restaurant': businessId},
    );
    return (
      sendable: [
        for (final row in rows)
          if (row[0] case final int platformId)
            {'tender_type_id': platformId, 'amount_minor': row[1] as int},
      ],
      stranded: [
        for (final row in rows)
          if (row[0] == null) '${row[3]} (payment method ${row[2]} on this till)',
      ],
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
             override.unit_price_minor, override.reason, l.id
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
          // What `pos_refund_lines.order_line_id` references, as a string, so
          // a refund of this line is a straight projection rather than a
          // lookup the till cannot do offline.
          clientLineId: '${row[10]}',
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
    required int businessId,
  }) async {
    final rows = await _db.query(
      config,
      'SELECT p.id, t.platform_id, p.amount_minor, p.reference, p.occurred_at, '
      '       p.tender_type_id, p.label '
      'FROM pos_order_payments p '
      'LEFT JOIN pos_tender_types t '
      '  ON t.id = p.tender_type_id AND t.business_id = @restaurant '
      'WHERE p.order_id = @order ORDER BY p.id',
      parameters: {'order': orderId, 'restaurant': businessId},
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
  const _LifecycleEvent({
    required this.request,
    required this.send,
    this.record,
    this.acknowledges = OutboxDrain.acknowledgesRecord,
  });

  final Map<String, Object?> request;
  final Future<CloudReply> Function() send;

  /// Whether a 2xx reply proves this record landed — checked before
  /// `delivered_at` is written. Per record because what counts as proof is:
  /// any JSON object for a shift, the platform's id for a customer.
  final bool Function(CloudReply reply) acknowledges;

  /// What to write back out of a successful reply, in the same transaction
  /// that marks the row delivered. Null for the three records whose reply
  /// tells the till nothing it did not already know.
  final Future<void> Function(TxSession tx, Map<String, Object?> data)? record;
}

/// What one queued lifecycle row turned into before anything was sent.
///
/// Three outcomes rather than a nullable event, because a refund brought a
/// third local answer: its sale may not have reached the platform yet, and
/// that is a wait — nobody has to do anything, and the next pass fixes it.
/// Modelled as a sealed type so the drain's `switch` is exhaustive and a
/// fourth outcome cannot be added without the compiler finding the gap.
sealed class _Prepared {
  const _Prepared();
}

class _Sendable extends _Prepared {
  const _Sendable(this.event);

  final _LifecycleEvent event;
}

/// Held for a person, before the platform was asked. Nothing is deleted:
/// money moved, and this row is what somebody resolves it from.
class _Held extends _Prepared {
  const _Held({required this.code, required this.message});

  final String code;
  final String message;
}

/// Left queued, with [why] on the row so the wait is legible.
class _Waiting extends _Prepared {
  const _Waiting(this.why);

  final String why;
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
  Future<SubmitOrderResult> submit(
    Ticket ticket, {
    PosStaff? servedBy,
    int? parkedVersion,
  }) async {
    final result = await _inner.submit(
      ticket,
      servedBy: servedBy,
      parkedVersion: parkedVersion,
    );
    _kick();
    return result;
  }

  @override
  Future<int> pendingSyncCount() => _inner.pendingSyncCount();

  /// Kicks the drain too. A voided order is a row the platform has to hear
  /// about as much as a paid one — arguably more, since it is the one a
  /// business will be asked about.
  @override
  Future<SubmitOrderResult> voidOrder(
    Ticket ticket, {
    required PosStaff by,
    int? reasonId,
    String? note,
    Approval? approval,
    PosStaff? servedBy,
    int? parkedVersion,
  }) async {
    final result = await _inner.voidOrder(
      ticket,
      by: by,
      reasonId: reasonId,
      note: note,
      approval: approval,
      servedBy: servedBy,
      parkedVersion: parkedVersion,
    );
    _kick();
    return result;
  }
}
