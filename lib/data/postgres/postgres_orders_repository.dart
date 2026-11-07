import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import '../../domain/services/stock_costing.dart';
import 'open_shift.dart';
import 'pos_database.dart';

/// Identifies which terminal and tenant a write belongs to.
///
/// Passed in rather than read from a session, because branch and terminal are
/// properties of the *machine* and must survive a different cashier signing in.
class PosWriteContext {
  const PosWriteContext({
    required this.businessId,
    required this.branchId,
    required this.terminalId,
    required this.branchCode,
  });

  final int businessId;
  final int branchId;
  final String terminalId;

  /// Invoice prefix. `branches.code` on the server (POS-BE-005).
  final String branchCode;
}

/// Writes settled tickets straight to the branch server's PostgreSQL.
///
/// Every rule that matters here is enforced by the **database**, not by hope:
///
/// * **Idempotency** is `UNIQUE (business_id, client_transaction_id)`. A till
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
    this.onQueued,
    DateTime Function()? clock,
  }) : _db = database,
       _now = clock ?? DateTime.now;

  /// Told after a sale is queued for the platform, so the drain can be
  /// nudged rather than waited for. Called inside the transaction; the nudge
  /// it feeds is debounced past the commit, and a nudge with nothing to
  /// drain costs one heartbeat.
  final void Function()? onQueued;

  final PosDatabase _db;
  final DeploymentConfig _config;
  final PosWriteContext _context;
  final DateTime Function() _now;

  @override
  Future<SubmitOrderResult> submit(
    Ticket ticket, {
    PosStaff? servedBy,
    int? parkedVersion,
  }) async {
    final totals = ticket.totals;
    final occurredAt = _now().toUtc();

    final outcome = await _db.runTx(_config, (tx) async {
      // A replay must not consume an invoice number, so look first. The unique
      // constraint below is still the authority — this is the fast path, not the
      // guarantee.
      final existing = await tx.execute(
        Sql.named(
          'SELECT id, invoice_number FROM pos_orders '
          'WHERE business_id = @business AND client_transaction_id = @txn',
        ),
        parameters: {'business': _context.businessId, 'txn': ticket.id},
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

      // Before anything is written or numbered: a refusal must leave no order
      // behind, and returning from here commits nothing.
      if (!await _takeParkedCheck(tx, ticket, parkedVersion)) return null;

      final invoiceNumber = await _nextInvoiceNumber(tx, occurredAt);

      // The shift open at this moment, so a Z report can total the sale. Read
      // here, not remembered: see [openShiftIdFor]. Null when no drawer is
      // open — the order is still recorded, as an unattributed sale.
      final shiftId = await openShiftIdFor(tx, _context.terminalId);

      final inserted = await tx.execute(
        Sql.named('''
          INSERT INTO pos_orders (
            client_transaction_id, business_id, branch_id, terminal_id,
            invoice_number, order_type, table_id, table_label, guest_count,
            currency, exponent, subtotal_minor, discount_minor, service_minor,
            vat_minor, total_minor, occurred_at, shift_id, served_by,
            customer_id
          ) VALUES (
            @txn, @business, @branch, @terminal,
            @invoice, @orderType, @tableId, @tableLabel, @guests,
            @currency, @exponent, @subtotal, @discount, @service,
            @vat, @total, @occurredAt, @shift, @servedBy,
            @customer
          )
          ON CONFLICT (business_id, client_transaction_id) DO NOTHING
          RETURNING id, invoice_number
        '''),
        parameters: {
          'txn': ticket.id,
          // Who the food is for (POS-BE-014), when anybody said. Null on most
          // sales and that is the normal case — somebody buys a coffee and
          // nobody asks their name.
          'customer': ticket.customer?.id,
          'business': _context.businessId,
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
          // Written with the rest of the totals, not derived afterwards. An
          // order whose total is discounted while `discount_minor` says zero
          // does not foot: subtotal + service + vat would not equal total, and
          // anyone auditing it finds a sale that charged less than it can
          // account for.
          'discount': totals.discount.minor,
          'service': totals.service.minor,
          'vat': totals.vat.minor,
          'total': totals.total.minor,
          'occurredAt': occurredAt,
          'shift': shiftId,
          // Who closed the sale, passed in at settlement. Null is a real
          // answer — a till selling before anybody signed in still records
          // the order, unattributed, rather than refusing it.
          'servedBy': servedBy?.id,
        },
      );

      // Lost a race with another connection carrying the same key. The number we
      // just allocated is spent — a gap, which POS-BE-008 explicitly tolerates.
      // Issuing the sale twice would not be tolerable.
      if (inserted.isEmpty) {
        final winner = await tx.execute(
          Sql.named(
            'SELECT id, invoice_number FROM pos_orders '
            'WHERE business_id = @business AND client_transaction_id = @txn',
          ),
          parameters: {'business': _context.businessId, 'txn': ticket.id},
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
      final lineIds = await _insertLines(tx, orderId, ticket);
      await _insertLineEvents(tx, orderId, ticket, lineIds);
      await _insertDiscounts(tx, orderId, ticket, lineIds);
      await _insertTaxLines(tx, orderId, totals);
      await _insertPayments(tx, orderId, ticket, occurredAt);
      await _issueStock(tx, orderId, ticket, occurredAt, servedBy: servedBy);
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
    // Refused inside the transaction, thrown out here: `runTx` translates
    // anything thrown inside it into a database failure, and this is not one.
    return outcome ?? (throw CheckChangedElsewhere(ticket.tableId));
  }

  /// Let go of [ticket]'s parked check as part of the sale, and confirm it is
  /// the check being paid (XORD-045, XORD-046 for a held ticket). False
  /// refuses the sale.
  ///
  /// **Why inside the order's transaction.** The parked row used to be deleted
  /// after the sale committed, by the payment screen. In that gap another till
  /// could park a new round over the check — its version still matched — and
  /// the delete then took the round with it: food served and never charged.
  /// Deleting here, under the row's lock, means a park that arrives later finds
  /// no row and is refused, and one that arrived earlier has moved the version,
  /// so this sale is refused instead.
  ///
  /// Refused when the table holds this ticket at a version other than
  /// [parkedVersion] (another till changed it), or holds nothing of this ticket
  /// although this till paid from a parked copy (another till voided or moved
  /// it). A ticket that was never parked — rung up and paid in one go — has no
  /// row and no version, and is not refused. Neither is a sale on a table that
  /// holds a different ticket: that check is not touched, and this money is
  /// still owed. A held ticket is found by its own transaction id and judged
  /// the same way.
  Future<bool> _takeParkedCheck(
    TxSession tx,
    Ticket ticket,
    int? parkedVersion,
  ) async {
    final tableId = ticket.tableId;
    final rows = await tx.execute(
      Sql.named(
        'SELECT client_transaction_id::text, version FROM pos_parked_tickets '
        'WHERE business_id = @business AND '
        '${tableId != null ? 'table_id = @table' : 'client_transaction_id = @txn AND table_id IS NULL'} '
        'FOR UPDATE',
      ),
      parameters: {
        'business': _context.businessId,
        if (tableId != null) 'table': tableId else 'txn': ticket.id,
      },
    );
    final ours = rows.isNotEmpty && rows.first[0] == ticket.id;
    if (ours && rows.first[1] != parkedVersion) return false;
    if (!ours && parkedVersion != null) return false;
    await tx.execute(
      Sql.named(
        'DELETE FROM pos_parked_tickets '
        'WHERE business_id = @business AND client_transaction_id = @txn',
      ),
      parameters: {'business': _context.businessId, 'txn': ticket.id},
    );
    return true;
  }

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
    // Before the transaction, for the reason the refund's is: `runTx` would
    // turn "you may not" into a database failure. The approver is not written
    // on the order — `pos_orders` has no column for one — and is on the audit
    // row the approval prompt wrote.
    Authorization.require(
      by,
      PosCapability.orderVoid,
      approval: approval,
      subject: ticket.id,
    );
    final totals = ticket.totals;
    final occurredAt = _now().toUtc();

    final outcome = await _db.runTx(_config, (tx) async {
      // Same replay guard as a settlement, and for the same reason: a till that
      // retried after a timeout must not record the waste twice.
      final replay = await tx.execute(
        Sql.named(
          'SELECT id, invoice_number FROM pos_orders '
          'WHERE business_id = @business AND client_transaction_id = @txn',
        ),
        parameters: {'business': _context.businessId, 'txn': ticket.id},
      );
      if (replay.isNotEmpty) {
        return SubmitOrderResult(
          clientTransactionId: ticket.id,
          queued: false,
          serverId: replay.first[0] as int,
          invoiceNumber: replay.first[1] as String?,
        );
      }

      // As in [submit], and before anything is numbered: a void of an outdated
      // copy records nothing (XORD-046 follow-up).
      if (!await _takeParkedCheck(tx, ticket, parkedVersion)) return null;

      final invoiceNumber = await _nextInvoiceNumber(tx, occurredAt);

      // As in [submit]: the shift open now, not the one open when this
      // repository was built.
      final shiftId = await openShiftIdFor(tx, _context.terminalId);

      final inserted = await tx.execute(
        Sql.named('''
          INSERT INTO pos_orders (
            client_transaction_id, business_id, branch_id, terminal_id,
            invoice_number, order_type, table_id, table_label, guest_count,
            currency, exponent, subtotal_minor, discount_minor, service_minor,
            vat_minor, total_minor, occurred_at, shift_id,
            status, status_changed_at, voided_at, voided_by, void_reason_id,
            void_note, served_by
          ) VALUES (
            @txn, @business, @branch, @terminal,
            @invoice, @orderType, @tableId, @tableLabel, @guests,
            @currency, @exponent, @subtotal, @discount, @service,
            @vat, @total, @occurredAt, @shift,
            'VOIDED', @occurredAt, @occurredAt, @voidedBy, @reason,
            @note, @servedBy
          )
          ON CONFLICT (business_id, client_transaction_id) DO NOTHING
          RETURNING id, invoice_number
        '''),
        parameters: {
          'txn': ticket.id,
          'business': _context.businessId,
          'branch': _context.branchId,
          'terminal': _context.terminalId,
          'invoice': invoiceNumber,
          'orderType': ticket.orderType.wire,
          'tableId': ticket.tableId,
          'tableLabel': ticket.tableLabel,
          'guests': ticket.guestCount,
          'currency': ticket.currency,
          'exponent': ticket.exponent,
          // The **real** totals, not zeroes. What was thrown away is the number
          // a waste report exists to show, and an order recording nothing would
          // erase it. Every report filters on `status`; that is what it is for.
          'subtotal': totals.subtotal.minor,
          'discount': totals.discount.minor,
          'service': totals.service.minor,
          'vat': totals.vat.minor,
          'total': totals.total.minor,
          'occurredAt': occurredAt,
          'shift': shiftId,
          'voidedBy': by.id,
          // Falls back to the person voiding. On the live cart they are the
          // one who rang it up; a manager voiding somebody else's ticket is
          // named in `approved_by` on the audit row, not here. Passing the
          // seller explicitly is always better and the sale screen does.
          'servedBy': (servedBy ?? by).id,
          'reason': reasonId,
          'note': note,
        },
      );

      if (inserted.isEmpty) {
        final winner = await tx.execute(
          Sql.named(
            'SELECT id, invoice_number FROM pos_orders '
            'WHERE business_id = @business AND client_transaction_id = @txn',
          ),
          parameters: {'business': _context.businessId, 'txn': ticket.id},
        );
        return SubmitOrderResult(
          clientTransactionId: ticket.id,
          queued: false,
          serverId: winner.first[0] as int,
          invoiceNumber: winner.first[1] as String?,
        );
      }

      final orderId = inserted.first[0] as int;
      final lineIds = await _insertLines(tx, orderId, ticket);
      await _insertLineEvents(tx, orderId, ticket, lineIds);
      await _insertDiscounts(tx, orderId, ticket, lineIds);
      // A voided order too: what tax *would* have been charged is part of the
      // record of what was thrown away, and a waste report reads it.
      await _insertTaxLines(tx, orderId, totals);
      // **No payments.** A voided order took no money, and a zero-amount tender
      // row would be refused by `pos_order_payments_amount_positive` anyway.

      // Not queued for the platform. `POS-BE-006` is the contract for a settled
      // sale; what a voided one looks like on the wire is not decided, and
      // sending a shape we invented would have to be unsent later.
      return SubmitOrderResult(
        clientTransactionId: ticket.id,
        queued: false,
        serverId: orderId,
        invoiceNumber: inserted.first[1] as String?,
      );
    });
    return outcome ?? (throw CheckChangedElsewhere(ticket.tableId));
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
          order_id, client_transaction_id, business_id, branch_id
        ) VALUES (@order, @txn, @business, @branch)
        ON CONFLICT (business_id, client_transaction_id) DO NOTHING
      '''),
      parameters: {
        'order': orderId,
        'txn': ticket.id,
        'business': _context.businessId,
        'branch': _context.branchId,
      },
    );

    onQueued?.call();
    return true;
  }

  @override
  Future<int> pendingSyncCount() async {
    if (!_config.mode.syncsSalesToPlatform) return 0;

    // Held rows are left out, on purpose: the drain will not touch them until
    // a person releases one, so counting them here put a number on the sync
    // pill that no pass could ever bring down (D8). They are counted apart, by
    // `SyncQueueRepository.heldSyncCount`. The predicate is the drain's own —
    // the one `pos_sync_outbox_pending_idx` is built on — so "pending" means
    // "the next pass will try it".
    final rows = await _db.query(
      _config,
      '''
      SELECT (
        (SELECT count(*) FROM pos_outbox
          WHERE business_id = @business AND branch_id = @branch
            AND delivered_at IS NULL AND quarantined_at IS NULL)
        +
        (SELECT count(*) FROM pos_sync_outbox
          WHERE business_id = @business AND branch_id = @branch
            AND delivered_at IS NULL AND quarantined_at IS NULL)
      )::bigint
      ''',
      parameters: {
        'business': _context.businessId,
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
        INSERT INTO pos_invoice_sequences (business_id, branch_id, period, prefix)
        VALUES (@business, @branch, @period, @prefix)
        ON CONFLICT (business_id, branch_id, period) DO NOTHING
      '''),
      parameters: {
        'business': _context.businessId,
        'branch': _context.branchId,
        'period': period,
        'prefix': _context.branchCode,
      },
    );

    final locked = await tx.execute(
      Sql.named('''
        SELECT prefix, next_value FROM pos_invoice_sequences
        WHERE business_id = @business AND branch_id = @branch AND period = @period
        FOR UPDATE
      '''),
      parameters: {
        'business': _context.businessId,
        'branch': _context.branchId,
        'period': period,
      },
    );

    final prefix = locked.first[0] as String;
    final value = locked.first[1] as int;

    await tx.execute(
      Sql.named('''
        UPDATE pos_invoice_sequences SET next_value = next_value + 1
        WHERE business_id = @business AND branch_id = @branch AND period = @period
      '''),
      parameters: {
        'business': _context.businessId,
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

  /// @return line key → the row id it was written as, so a line discount can
  /// point at the line it came off.
  Future<Map<String, int>> _insertLines(
    TxSession tx,
    int orderId,
    Ticket ticket,
  ) async {
    final ids = <String, int>{};

    for (final line in ticket.lines) {
      final inserted = await tx.execute(
        Sql.named('''
          INSERT INTO pos_order_lines (
            order_id, line_key, menu_item_id, name_snapshot, modifier_ids,
            modifier_summary, quantity, unit_price_minor, line_total_minor,
            stage, note, voided_at, voided_by, void_reason_id, combo_id
          ) VALUES (
            @order, @key, @itemId, @name, @modifierIds,
            @summary, @quantity, @unitPrice, @lineTotal,
            @stage, @note, @voidedAt, @voidedBy, @voidReason, @comboId
          )
          RETURNING id
        '''),
        parameters: {
          'order': orderId,
          'key': line.key,
          // NULL for a one-off charge and for a combo alike: neither names a
          // menu item, and the synthetic id that keeps two of them apart on the
          // ticket must not reach the database as though it were one. A combo
          // says which combo it is in `combo_id`, and what it was made of in
          // `pos_order_line_items`.
          'itemId': line.product.isOpenPrice ? null : line.product.id,
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
          // A voided line is still written, with its price, and simply does not
          // count toward the totals above it. The row is the evidence: deleting
          // it would leave the kitchen's ticket and the bill describing
          // different meals, with nothing to say why.
          'voidedAt': line.voided?.at,
          'voidedBy': line.voided?.byStaffId,
          'voidReason': line.voided?.reasonId,
          'comboId': line.combo?.comboId,
        },
      );
      final lineId = inserted.first[0]! as int;
      ids[line.key] = lineId;

      // What the meal was made of. The line carries the combo's name and the
      // combo's price; these carry the items, so the kitchen knows what to make
      // and a receipt can list them underneath.
      final selection = line.combo;
      if (selection != null) {
        for (var i = 0; i < selection.items.length; i++) {
          final item = selection.items[i];
          await tx.execute(
            Sql.named(
              'INSERT INTO pos_order_line_items (order_line_id, menu_item_id, '
              '  name_snapshot, quantity, sort_order) '
              'VALUES (@line, @item, @name, @quantity, @sort)',
            ),
            parameters: {
              'line': lineId,
              'item': item.menuItemId,
              'name': item.nameEn,
              'quantity': item.quantity,
              'sort': i,
            },
          );
        }
      }
    }

    return ids;
  }

  /// What happened to the lines, in order.
  ///
  /// `order_line_id` is filled in where the line still exists and left null
  /// where it does not — a line cancelled before the first round was sent never
  /// became a row, which is exactly why the table keys on `line_key` as well.
  Future<void> _insertLineEvents(
    TxSession tx,
    int orderId,
    Ticket ticket,
    Map<String, int> lineIds,
  ) async {
    for (final event in ticket.lineEvents) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_order_line_events (
            order_id, order_line_id, line_key, event, quantity_before,
            quantity_after, unit_price_before_minor, unit_price_after_minor,
            reason_id, note, user_id, approved_by_id, occurred_at
          ) VALUES (
            @order, @line, @key, @event, @before,
            @after, @priceBefore, @priceAfter,
            @reason, @note, @staff, @approvedBy, @occurredAt
          )
        '''),
        parameters: {
          'order': orderId,
          'line': lineIds[event.lineKey],
          'key': event.lineKey,
          'event': event.event,
          'before': event.quantityBefore,
          'after': event.quantityAfter,
          // Only ever set on a `price_overridden` event. Migration 9
          // provisioned both columns; this is what fills them.
          'priceBefore': event.unitPriceBefore,
          'priceAfter': event.unitPriceAfter,
          'reason': event.reasonId,
          'note': event.note,
          'staff': event.staffId,
          'approvedBy': event.approvedByStaffId,
          'occurredAt': event.at.toUtc(),
        },
      );
    }
  }

  /// The tax breakdown, one row per rate.
  ///
  /// Written for every order, including a voided one: what tax *would* have
  /// been charged is part of the record of what was thrown away, and an ETA
  /// filing is built from these rows rather than from `vat_minor`. The scalar
  /// stays because every report and every receipt already reads it, and because
  /// `sum(amount_minor)` here equals it by construction.
  Future<void> _insertTaxLines(
    TxSession tx,
    int orderId,
    TicketTotals totals,
  ) async {
    for (final line in totals.taxLines) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_order_taxes (
            order_id, tax_group_id, name_snapshot, rate_bp, base_minor,
            amount_minor
          ) VALUES (@order, @group, @name, @rate, @base, @amount)
          ON CONFLICT (order_id, rate_bp, name_snapshot) DO NOTHING
        '''),
        parameters: {
          'order': orderId,
          // Null when the group is this build's fallback rather than a row the
          // business configured — there is nothing to point at.
          'group': (line.taxGroupId ?? 0) == 0 ? null : line.taxGroupId,
          // Snapshotted, like a line's name: a rate renamed or moved next year
          // must not rewrite what a receipt said today.
          'name': line.name,
          'rate': line.rateBp,
          'base': line.base.minor,
          'amount': line.amount.minor,
        },
      );
    }
  }

  /// What was taken off, and who took it off.
  ///
  /// In the same transaction as the order and its lines, for the reason the
  /// outbox is: a total that says a discount was given, with no row saying
  /// which discount or on whose authority, is a sale nobody can answer for.
  Future<void> _insertDiscounts(
    TxSession tx,
    int orderId,
    Ticket ticket,
    Map<String, int> lineIds,
  ) async {
    for (final discount in ticket.discounts) {
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_order_discounts (
            order_id, order_line_id, discount_id, name_snapshot, kind,
            value_bp, value_minor, amount_minor, reason_id, note, applied_by,
            approved_by_id
          ) VALUES (
            @order, @line, @discount, @name, @kind,
            @valueBp, @valueMinor, @amount, @reason, @note, @appliedBy,
            @approvedBy
          )
        '''),
        parameters: {
          'order': orderId,
          // Null for an order-level discount, which is what the totals block
          // renders rather than a line.
          'line': discount.lineKey == null
              ? null
              : lineIds[discount.lineKey!],
          'discount': discount.discountId,
          'name': discount.nameSnapshot,
          'kind': discount.kind.wire,
          'valueBp': discount.valueBp,
          'valueMinor': discount.valueMinor?.minor,
          'amount': discount.amount.minor,
          'reason': discount.reasonId,
          'note': discount.note,
          'appliedBy': discount.appliedByStaffId,
          'approvedBy': discount.approvedByStaffId,
        },
      );
    }
  }

  /// **The ledger records what was APPLIED, never what was tendered.**
  ///
  /// `payment_status.dart` states the rule and the reason: change is a till
  /// concern and never reaches the ledger, so "paid more than the total" is
  /// not a state a correct ledger can be in — and it warned this would break
  /// "the day somebody wrote tendered by mistake". That day was 27 Sep 2026.
  /// `BR8-2026-000007`: a 360.00 bill with 380.00 of cash on it, uploaded to
  /// the platform as a 380.00 payment against a 360.00 sale.
  ///
  /// The ticket is right to hold the tendered figure — `TicketTotals.change`
  /// is derived from it and the slip prints it. It is only the row that must
  /// be capped, which is what keeps both true at once: the customer's receipt
  /// says what they handed over and what came back, and the ledger says what
  /// the sale took.
  ///
  /// Capped in order and against what is still owed, so a split tender applies
  /// each one in turn and only the last can be short. A tender that lands with
  /// nothing left owing writes no row at all — it applied nothing.
  Future<void> _insertPayments(
    TxSession tx,
    int orderId,
    Ticket ticket,
    DateTime occurredAt,
  ) async {
    var remaining = ticket.totals.total;

    for (final tender in ticket.tenders) {
      if (remaining.isZero || remaining.isNegative) break;

      final applied = tender.amount.minor > remaining.minor
          ? remaining
          : tender.amount;
      remaining = remaining - applied;
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_order_payments (
            order_id, tender_type_id, label, amount_minor, reference,
            counts_as_cash, occurred_at
          ) VALUES (@order, @typeId, @label, @amount, @reference, @cash,
                    @occurredAt)
        '''),
        parameters: {
          'order': orderId,
          'typeId': tender.typeId,
          'label': tender.label,
          'amount': applied.minor,
          'reference': tender.reference,
          // Snapshotted with the money. See [Tender.countsAsCash].
          'cash': tender.countsAsCash,
          'occurredAt': occurredAt,
        },
      );
    }
  }

  /// Records a stock issue in the exact transaction that records the sale.
  ///
  /// A stocked menu item is counted in whole sellable units.  Menu dishes and
  /// combos deliberately do not become inventory movements unless the product
  /// itself is marked stocked: there is no recipe model here, so inferring that
  /// a burger consumes one of every component would manufacture stock facts.
  /// Negative stock remains valid — declining a paid sale because receiving is
  /// late makes the financial ledger less truthful, not the stock ledger more
  /// truthful.
  Future<void> _issueStock(
    TxSession tx,
    int orderId,
    Ticket ticket,
    DateTime occurredAt, {
    PosStaff? servedBy,
  }) async {
    final quantities = <int, int>{};
    for (final line in ticket.lines) {
      if (!line.product.isStocked || line.isVoided || line.product.isOpenPrice) {
        continue;
      }
      quantities.update(
        line.product.id,
        (quantity) => quantity + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }

    for (final entry in quantities.entries) {
      final product = await tx.execute(
        Sql.named(
          'SELECT stock_unit FROM pos_products '
          'WHERE id = @product AND business_id = @business FOR SHARE',
        ),
        parameters: {
          'product': entry.key,
          'business': _context.businessId,
        },
      );
      // The item was archived or replaced after the cashier added it.  The
      // sale's own snapshot remains valid, but a foreign-key movement against
      // a missing stock item would roll back a legitimate sale.
      if (product.isEmpty) continue;

      final unit = QuantityUnit.fromWire(product.first[0] as String?);
      final held = await tx.execute(
        Sql.named(
          'SELECT quantity_milli, average_cost_minor, unit '
          'FROM pos_stock_levels WHERE branch_id = @branch '
          'AND product_id = @product FOR UPDATE',
        ),
        parameters: {'branch': _context.branchId, 'product': entry.key},
      );
      final before = held.isEmpty
          ? StockPosition(onHand: Quantity(0, unit: unit), unitCost: Money.zero)
          : StockPosition(
              onHand: Quantity(
                held.first[0] as int,
                unit: QuantityUnit.fromWire(held.first[2] as String?),
              ),
              unitCost: Money(held.first[1] as int),
            );

      // A product's unit cannot change while it is held (migration 44), but
      // an older row can predate that guard.  Preserve its recorded unit; the
      // sale is still one whole unit of the thing the position says it is.
      final issued = Quantity.of(entry.value, unit: before.onHand.unit);
      final after = StockCosting.issue(before, issued: issued);

      await tx.execute(
        Sql.named('''
          INSERT INTO pos_stock_movements
            (business_id, branch_id, product_id, kind, quantity_milli, unit,
             unit_cost_minor, balance_milli, average_cost_minor, order_id,
             occurred_at, created_by)
          VALUES (@business, @branch, @product, 'sale', @quantity, @unit,
                  @cost, @balance, @average, @order, @occurredAt, @by)
        '''),
        parameters: {
          'business': _context.businessId,
          'branch': _context.branchId,
          'product': entry.key,
          'quantity': -issued.milli,
          'unit': before.onHand.unit.wire,
          'cost': before.unitCost.minor,
          'balance': after.onHand.milli,
          'average': after.unitCost.minor,
          'order': orderId,
          'occurredAt': occurredAt,
          'by': servedBy?.id,
        },
      );
      await tx.execute(
        Sql.named('''
          INSERT INTO pos_stock_levels
            (business_id, branch_id, product_id, quantity_milli, unit,
             average_cost_minor, updated_at)
          VALUES (@business, @branch, @product, @quantity, @unit, @average, now())
          ON CONFLICT (branch_id, product_id) DO UPDATE SET
            quantity_milli = excluded.quantity_milli,
            average_cost_minor = excluded.average_cost_minor,
            updated_at = now()
        '''),
        parameters: {
          'business': _context.businessId,
          'branch': _context.branchId,
          'product': entry.key,
          'quantity': after.onHand.milli,
          'unit': before.onHand.unit.wire,
          'average': after.unitCost.minor,
        },
      );
    }
  }
}
