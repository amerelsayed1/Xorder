import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// Identifies which terminal and tenant a write belongs to.
///
/// Passed in rather than read from a session, because branch and terminal are
/// properties of the *machine* and must survive a different cashier signing in.
class PosWriteContext {
  const PosWriteContext({
    required this.restaurantId,
    required this.branchId,
    required this.terminalId,
    required this.branchCode,
  });

  final int restaurantId;
  final int branchId;
  final String terminalId;

  /// Invoice prefix. `branches.code` on the server (POS-BE-005).
  final String branchCode;
}

/// Writes settled tickets straight to the branch server's PostgreSQL.
///
/// Every rule that matters here is enforced by the **database**, not by hope:
///
/// * **Idempotency** is `UNIQUE (restaurant_id, client_transaction_id)`. A till
///   that retries after a timeout gets the original order back, with the same id
///   and the same invoice number — never a second sale and never a `409`.
/// * **Invoice numbering** is a row lock on `pos_invoice_sequences`, taken inside
///   the same transaction as the insert. `MAX(number)+1` would double-issue the
///   moment two tills settle at once, which at a lunch rush is constantly.
/// * **Atomicity** is one transaction covering the sequence bump, the order, its
///   lines and its payments. A half-written order is worse than a refused one.
///
/// It implements [OrdersRepository] and nothing else knows it exists, so the day
/// `POS-BE-006` is `READY` an `ApiOrdersRepository` replaces it in
/// `providers.dart` with no change to the domain or the UI.
class PostgresOrdersRepository implements OrdersRepository {
  PostgresOrdersRepository({
    required PosDatabase database,
    required this._config,
    required this._context,
    this.shiftId,
    DateTime Function()? clock,
  }) : _db = database,
       _now = clock ?? DateTime.now;

  /// The shift this sale belongs to, so a Z report can total it.
  ///
  /// Nullable because a till can be selling before the shift concept reaches
  /// every deployment, and an order that cannot name its shift is still an
  /// order that must be recorded. It shows up as an unattributed sale on the
  /// report rather than being silently dropped from it.
  final int? shiftId;

  final PosDatabase _db;
  final DeploymentConfig _config;
  final PosWriteContext _context;
  final DateTime Function() _now;

  @override
  Future<SubmitOrderResult> submit(Ticket ticket) async {
    final totals = ticket.totals;
    final occurredAt = _now().toUtc();

    return _db.runTx(_config, (tx) async {
      // A replay must not consume an invoice number, so look first. The unique
      // constraint below is still the authority — this is the fast path, not the
      // guarantee.
      final existing = await tx.execute(
        Sql.named(
          'SELECT id, invoice_number FROM pos_orders '
          'WHERE restaurant_id = @restaurant AND client_transaction_id = @txn',
        ),
        parameters: {'restaurant': _context.restaurantId, 'txn': ticket.id},
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        return SubmitOrderResult(
          clientTransactionId: ticket.id,
          queued: false,
          serverId: row[0] as int,
          invoiceNumber: row[1] as String?,
        );
      }

      final invoiceNumber = await _nextInvoiceNumber(tx, occurredAt);

      final inserted = await tx.execute(
        Sql.named('''
          INSERT INTO pos_orders (
            client_transaction_id, restaurant_id, branch_id, terminal_id,
            invoice_number, order_type, table_id, table_label, guest_count,
            currency, exponent, subtotal_minor, service_minor, vat_minor,
            total_minor, occurred_at, shift_id
          ) VALUES (
            @txn, @restaurant, @branch, @terminal,
            @invoice, @orderType, @tableId, @tableLabel, @guests,
            @currency, @exponent, @subtotal, @service, @vat,
            @total, @occurredAt, @shift
          )
          ON CONFLICT (restaurant_id, client_transaction_id) DO NOTHING
          RETURNING id, invoice_number
        '''),
        parameters: {
          'txn': ticket.id,
          'restaurant': _context.restaurantId,
          'branch': _context.branchId,
          'terminal': _context.terminalId,
          'invoice': invoiceNumber,
          'orderType': ticket.orderType.wire,
          'tableId': ticket.tableId,
          'tableLabel': ticket.tableLabel,
          'guests': ticket.guestCount,
          'currency': ticket.currency,
          'exponent': ticket.exponent,
          'subtotal': totals.subtotal.minor,
          'service': totals.service.minor,
          'vat': totals.vat.minor,
          'total': totals.total.minor,
          'occurredAt': occurredAt,
          'shift': shiftId,
        },
      );

      // Lost a race with another connection carrying the same key. The number we
      // just allocated is spent — a gap, which POS-BE-008 explicitly tolerates.
      // Issuing the sale twice would not be tolerable.
      if (inserted.isEmpty) {
        final winner = await tx.execute(
          Sql.named(
            'SELECT id, invoice_number FROM pos_orders '
            'WHERE restaurant_id = @restaurant AND client_transaction_id = @txn',
          ),
          parameters: {'restaurant': _context.restaurantId, 'txn': ticket.id},
        );
        final row = winner.first;
        return SubmitOrderResult(
          clientTransactionId: ticket.id,
          queued: false,
          serverId: row[0] as int,
          invoiceNumber: row[1] as String?,
        );
      }

      final orderId = inserted.first[0] as int;
      await _insertLines(tx, orderId, ticket);
      await _insertPayments(tx, orderId, ticket, occurredAt);
      final queued = await _enqueueForSync(tx, orderId, ticket);

      return SubmitOrderResult(
        clientTransactionId: ticket.id,
        // Committed to PostgreSQL either way. `queued` says whether it is still
        // owed to the platform — true in cloud mode until the drain lands, and
        // false in offline mode, where the sale is already everywhere it will
        // ever go.
        queued: queued,
        serverId: orderId,
        invoiceNumber: inserted.first[1] as String?,
      );
    });
  }

  /// Claim this sale for the platform, in the **same transaction** that wrote it.
  ///
  /// That is the whole invariant. An outbox row inserted afterwards can be lost
  /// to a crash between the two commits, and the sale is then money the platform
  /// will never hear about — invisible precisely because it committed
  /// successfully. One transaction or neither.
  ///
  /// Returns whether anything was enqueued.
  Future<bool> _enqueueForSync(TxSession tx, int orderId, Ticket ticket) async {
    // An offline terminal never sends sales, so queueing them would build a
    // backlog nothing can ever drain and report a debt that does not exist.
    if (!_config.mode.syncsSalesToPlatform) return false;

    await tx.execute(
      Sql.named('''
        INSERT INTO pos_outbox (
          order_id, client_transaction_id, restaurant_id, branch_id
        ) VALUES (@order, @txn, @restaurant, @branch)
        ON CONFLICT (restaurant_id, client_transaction_id) DO NOTHING
      '''),
      parameters: {
        'order': orderId,
        'txn': ticket.id,
        'restaurant': _context.restaurantId,
        'branch': _context.branchId,
      },
    );

    return true;
  }

  @override
  Future<int> pendingSyncCount() async {
    if (!_config.mode.syncsSalesToPlatform) return 0;

    final rows = await _db.query(
      _config,
      'SELECT count(*) FROM pos_outbox '
      'WHERE restaurant_id = @restaurant AND branch_id = @branch '
      'AND delivered_at IS NULL',
      parameters: {
        'restaurant': _context.restaurantId,
        'branch': _context.branchId,
      },
    );

    return rows.first[0] as int;
  }

  /// Allocate the next number for this branch and period.
  ///
  /// `FOR UPDATE` on the sequence row is what makes two tills settling at the
  /// same instant safe. The row is created on first use so a new branch needs no
  /// provisioning step.
  Future<String> _nextInvoiceNumber(TxSession tx, DateTime occurredAt) async {
    final period = occurredAt.year.toString();

    await tx.execute(
      Sql.named('''
        INSERT INTO pos_invoice_sequences (restaurant_id, branch_id, period, prefix)
        VALUES (@restaurant, @branch, @period, @prefix)
        ON CONFLICT (restaurant_id, branch_id, period) DO NOTHING
      '''),
      parameters: {
        'restaurant': _context.restaurantId,
        'branch': _context.branchId,
        'period': period,
        'prefix': _context.branchCode,
      },
    );

    final locked = await tx.execute(
      Sql.named('''
        SELECT prefix, next_value FROM pos_invoice_sequences
        WHERE restaurant_id = @restaurant AND branch_id = @branch AND period = @period
        FOR UPDATE
      '''),
      parameters: {
        'restaurant': _context.restaurantId,
        'branch': _context.branchId,
        'period': period,
      },
    );

    final prefix = locked.first[0] as String;
    final value = locked.first[1] as int;

    await tx.execute(
      Sql.named('''
        UPDATE pos_invoice_sequences SET next_value = next_value + 1
        WHERE restaurant_id = @restaurant AND branch_id = @branch AND period = @period
      '''),
      parameters: {
        'restaurant': _context.restaurantId,
        'branch': _context.branchId,
        'period': period,
      },
    );

    return formatInvoiceNumber(prefix: prefix, period: period, value: value);
  }

  /// `MAADI-2026-001042`.
  ///
  /// Pure and public so the format is testable without a database — it ends up
  /// printed on a receipt a tax authority may read.
  static String formatInvoiceNumber({
    required String prefix,
    required String period,
    required int value,
    int padTo = 6,
  }) => '$prefix-$period-${value.toString().padLeft(padTo, '0')}';

  Future<void> _insertLines(TxSession tx, int orderId, Ticket ticket) async {
    for (final line in ticket.lines) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_order_lines (
            order_id, line_key, menu_item_id, name_snapshot, modifier_ids,
            modifier_summary, quantity, unit_price_minor, line_total_minor,
            stage, note
          ) VALUES (
            @order, @key, @itemId, @name, @modifierIds,
            @summary, @quantity, @unitPrice, @lineTotal,
            @stage, @note
          )
        '''),
        parameters: {
          'order': orderId,
          'key': line.key,
          'itemId': line.product.id,
          // Snapshotted because an item renamed or deleted tomorrow must not
          // rewrite a receipt printed today.
          'name': line.product.nameEn,
          'modifierIds': (line.modifiers.map((m) => m.id).toList()..sort()),
          'summary': line.modifiers.isEmpty ? null : line.modifierSummary('en'),
          'quantity': line.quantity,
          'unitPrice': line.unitPrice.minor,
          'lineTotal': line.lineTotal.minor,
          'stage': line.stage.name,
          'note': line.note,
        },
      );
    }
  }

  Future<void> _insertPayments(
    TxSession tx,
    int orderId,
    Ticket ticket,
    DateTime occurredAt,
  ) async {
    for (final tender in ticket.tenders) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_order_payments (
            order_id, tender_type_id, label, amount_minor, reference, occurred_at
          ) VALUES (@order, @typeId, @label, @amount, @reference, @occurredAt)
        '''),
        parameters: {
          'order': orderId,
          'typeId': tender.typeId,
          'label': tender.label,
          'amount': tender.amount.minor,
          'reference': tender.reference,
          'occurredAt': occurredAt,
        },
      );
    }
  }
}
