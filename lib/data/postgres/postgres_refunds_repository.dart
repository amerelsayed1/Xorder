import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/order_record.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/refund.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import '../../domain/services/refund_engine.dart' show RefundQuote;
import 'open_shift.dart';
import 'pos_database.dart';
import 'postgres_orders_repository.dart' show PosWriteContext;

/// Writes refunds to the branch database.
///
/// Every rule that matters is enforced by the **database**, not by this class:
///
/// * **A line cannot be refunded more than it was sold.** Migration 12's
///   trigger bumps `pos_order_lines.refunded_quantity`, and migration 9's CHECK
///   refuses the row if it passes the quantity.
/// * **An order cannot give back more than it took.** Same shape, on
///   `pos_orders.refunded_minor`.
/// * **The order's status follows the money.** The trigger derives `REFUNDED`
///   or `PARTIALLY_REFUNDED` from the counter, so this class never writes a
///   status and the two cannot drift.
/// * **The tender adds up.** A deferred constraint trigger checks at commit
///   that the payments sum to the refund total.
/// * **Idempotency** is `UNIQUE (restaurant_id, client_refund_id)`.
///
/// What is left here is putting it in one transaction and reporting what
/// happened — and, on a cloud till, putting the platform's delivery claim in
/// that same transaction (POS-BE-010).
class PostgresRefundsRepository implements RefundsRepository {
  const PostgresRefundsRepository({
    required PosDatabase database,
    required this.config,
    required this.context,
    this.currency = 'EGP',
    this.exponent = 2,
    this.onQueued,
  }) : _db = database;

  /// Told after a refund is queued — see `PostgresOrdersRepository.onQueued`.
  final void Function()? onQueued;

  final PosDatabase _db;
  final DeploymentConfig config;
  final PosWriteContext context;

  final String currency;
  final int exponent;

  Money _money(Object? minor) =>
      Money(minor is int ? minor : 0, currency: currency, exponent: exponent);

  @override
  Future<RefundResult> issue({
    required OrderRecord order,
    required RefundQuote quote,
    required PosStaff by,
    required List<RefundTender> tenders,
    required String clientRefundId,
    Approval? approval,
    int? reasonId,
    String? note,
  }) async {
    // Asked before the transaction rather than inside it: `runTx` turns
    // anything thrown in there into a database failure, and "you may not" is
    // not one. The sheet asked first; this is what holds when something goes
    // round the sheet.
    final approvedBy = Authorization.require(
      by,
      PosCapability.orderRefund,
      approval: approval,
      subject: '${order.id}',
      approvalRequired: quote.requiresApproval,
    ).approvedBy;
    final occurredAt = DateTime.now().toUtc();

    return _db.runTx(config, (tx) async {
      // The fast path, not the guarantee — the unique constraint below is the
      // authority. Looked at first so a retry does not consume anything.
      final existing = await tx.execute(
        Sql.named(
          'SELECT id FROM pos_refunds '
          'WHERE restaurant_id = @restaurant AND client_refund_id = @client',
        ),
        parameters: {
          'restaurant': context.restaurantId,
          'client': clientRefundId,
        },
      );
      if (existing.isNotEmpty) {
        return RefundResult(
          clientRefundId: clientRefundId,
          refundId: existing.first[0] as int,
          replayed: true,
        );
      }

      // The shift the money leaves, which is the one open now — not the one
      // open when this repository was built (see [openShiftIdFor]). Null when
      // no drawer is open: a refund that cannot name its shift is still a
      // refund that must be recorded.
      final shiftId = await openShiftIdFor(tx, context.terminalId);

      final inserted = await tx.execute(
        Sql.named('''
          INSERT INTO pos_refunds (
            client_refund_id, restaurant_id, branch_id, terminal_id, order_id,
            shift_id, kind, subtotal_minor, discount_minor, service_minor,
            vat_minor, total_minor, reason_id, note, refunded_by,
            approved_by_id, occurred_at
          ) VALUES (
            @client, @restaurant, @branch, @terminal, @order,
            @shift, @kind, @subtotal, @discount, @service,
            @vat, @total, @reason, @note, @by,
            @approvedBy, @occurredAt
          )
          ON CONFLICT (restaurant_id, client_refund_id) DO NOTHING
          RETURNING id
        '''),
        parameters: {
          'client': clientRefundId,
          'restaurant': context.restaurantId,
          'branch': context.branchId,
          'terminal': context.terminalId,
          'order': order.id,
          'shift': shiftId,
          'kind': quote.kind.wire,
          'subtotal': quote.subtotal.minor,
          'discount': quote.discount.minor,
          'service': quote.service.minor,
          'vat': quote.vat.minor,
          'total': quote.total.minor,
          'reason': reasonId,
          'note': note,
          'by': by.id,
          // Both people on the row when there were two, exactly as a discount
          // above a limit records both.
          'approvedBy': approvedBy?.id,
          'occurredAt': occurredAt,
        },
      );

      // Lost a race with another connection carrying the same key. The winner's
      // refund is the refund; issuing a second one would hand the money back
      // twice.
      if (inserted.isEmpty) {
        final winner = await tx.execute(
          Sql.named(
            'SELECT id FROM pos_refunds '
            'WHERE restaurant_id = @restaurant AND client_refund_id = @client',
          ),
          parameters: {
            'restaurant': context.restaurantId,
            'client': clientRefundId,
          },
        );
        return RefundResult(
          clientRefundId: clientRefundId,
          refundId: winner.first[0] as int,
          replayed: true,
        );
      }

      final refundId = inserted.first[0] as int;

      for (final line in quote.lines) {
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_refund_lines (
              refund_id, order_line_id, quantity, unit_price_minor,
              line_total_minor, name_snapshot
            ) VALUES (@refund, @line, @qty, @unit, @total, @name)
          '''),
          parameters: {
            'refund': refundId,
            'line': line.orderLineId,
            'qty': line.quantity,
            'unit': line.unitPrice.minor,
            'total': line.lineTotal.minor,
            'name': line.name,
          },
        );
      }

      for (final tender in tenders) {
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_refund_payments (
              refund_id, tender_type_id, label, amount_minor, reference,
              counts_as_cash, occurred_at
            ) VALUES (
              @refund, @type, @label, @amount, @reference,
              coalesce((SELECT counts_as_cash FROM pos_tender_types
                        WHERE restaurant_id = @restaurant AND id = @type), false),
              @occurredAt
            )
          '''),
          parameters: {
            'refund': refundId,
            'type': tender.tenderTypeId,
            'label': tender.label,
            'amount': tender.amount.minor,
            'reference': tender.reference,
            'restaurant': context.restaurantId,
            'occurredAt': occurredAt,
          },
        );
      }

      // The platform's claim on this refund, in the transaction that wrote it.
      // Two commits would leave a refund the platform never hears about if the
      // second one lost — invisible precisely because the first succeeded, the
      // same reasoning `_enqueueForSync` gives for a sale.
      //
      // The key is `client_refund_id` itself rather than a second UUID: a
      // refund already carries the idempotency key §007 asks for, and one key
      // for one act means a replayed refund cannot queue a second delivery.
      if (config.mode.syncsSalesToPlatform) {
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_sync_outbox
              (restaurant_id, branch_id, event_type, source_id,
               client_transaction_id)
            VALUES (@restaurant, @branch, 'refund', @source, @client)
            ON CONFLICT (restaurant_id, client_transaction_id) DO NOTHING
          '''),
          parameters: {
            'restaurant': context.restaurantId,
            'branch': context.branchId,
            'source': refundId,
            'client': clientRefundId,
          },
        );
      }

      onQueued?.call();
      return RefundResult(
        clientRefundId: clientRefundId,
        refundId: refundId,
        replayed: false,
      );
    });
  }

  @override
  Future<List<Refund>> forOrder(int orderId) async {
    final rows = await _db.query(
      config,
      'SELECT r.id, r.client_refund_id, r.order_id, r.kind, r.subtotal_minor, '
      '       r.discount_minor, r.service_minor, r.vat_minor, r.total_minor, '
      '       r.occurred_at, r.note, reason.name_en, reason.name_ar, '
      '       issuer.name, approver.name '
      'FROM pos_refunds AS r '
      'LEFT JOIN pos_reason_codes AS reason ON reason.id = r.reason_id '
      'LEFT JOIN pos_users AS issuer ON issuer.id = r.refunded_by '
      'LEFT JOIN pos_users AS approver ON approver.id = r.approved_by_id '
      'WHERE r.order_id = @order AND r.restaurant_id = @restaurant '
      'ORDER BY r.occurred_at, r.id',
      parameters: {'order': orderId, 'restaurant': context.restaurantId},
    );
    if (rows.isEmpty) return const [];

    final ids = rows.map((row) => row[0] as int).toList();

    // Two more reads rather than a join with the refunds: joining would
    // multiply the refund rows by their lines and payments, and unpicking that
    // in Dart is how a total gets counted twice.
    final lineRows = await _db.query(
      config,
      'SELECT refund_id, order_line_id, quantity, unit_price_minor, '
      '       name_snapshot '
      'FROM pos_refund_lines WHERE refund_id = ANY(@ids) ORDER BY id',
      parameters: {'ids': ids},
    );
    final paymentRows = await _db.query(
      config,
      'SELECT refund_id, tender_type_id, label, amount_minor, reference '
      'FROM pos_refund_payments WHERE refund_id = ANY(@ids) ORDER BY id',
      parameters: {'ids': ids},
    );

    final linesByRefund = <int, List<RefundLineSelection>>{};
    for (final raw in lineRows) {
      final row = raw.toList();
      linesByRefund.putIfAbsent(row[0] as int, () => []).add(
        RefundLineSelection(
          orderLineId: row[1] as int,
          name: row[4] as String,
          quantity: row[2] as int,
          unitPrice: _money(row[3]),
        ),
      );
    }

    final paymentsByRefund = <int, List<RefundTender>>{};
    for (final raw in paymentRows) {
      final row = raw.toList();
      paymentsByRefund.putIfAbsent(row[0] as int, () => []).add(
        RefundTender(
          tenderTypeId: row[1] as int,
          label: row[2] as String,
          amount: _money(row[3]),
          reference: row[4] as String?,
        ),
      );
    }

    return rows.map((raw) {
      final row = raw.toList();
      final id = row[0] as int;
      return Refund(
        id: id,
        clientRefundId: '${row[1]}',
        orderId: row[2] as int,
        kind: RefundKind.fromWire(row[3] as String) ?? RefundKind.partial,
        subtotal: _money(row[4]),
        discount: _money(row[5]),
        service: _money(row[6]),
        vat: _money(row[7]),
        total: _money(row[8]),
        occurredAt: (row[9] as DateTime).toLocal(),
        note: row[10] as String?,
        reasonName: row[11] as String?,
        reasonNameAr: row[12] as String?,
        refundedByName: row[13] as String?,
        approvedByName: row[14] as String?,
        lines: linesByRefund[id] ?? const [],
        payments: paymentsByRefund[id] ?? const [],
      );
    }).toList(growable: false);
  }
}

/// What a terminal with no branch database answers with.
///
/// [forOrder] is empty — a till that has recorded no sales has issued no
/// refunds, which is true rather than a failure. [issue] refuses out loud:
/// reporting success while writing nowhere would tell a cashier the money was
/// accounted for when it was not.
class UnconfiguredRefundsRepository implements RefundsRepository {
  const UnconfiguredRefundsRepository();

  @override
  Future<List<Refund>> forOrder(int orderId) async => const [];

  @override
  Future<RefundResult> issue({
    required OrderRecord order,
    required RefundQuote quote,
    required PosStaff by,
    required List<RefundTender> tenders,
    required String clientRefundId,
    Approval? approval,
    int? reasonId,
    String? note,
  }) async => throw StateError(
    'This terminal has nowhere to record a refund. It is not connected to a '
    'database, so the money must not leave the drawer on this till.',
  );
}
