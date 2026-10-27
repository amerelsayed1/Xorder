import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/business_day.dart' show CashMovementKind;
import '../../domain/models/permissions.dart';
import '../../domain/models/finance_report.dart';
import '../../domain/models/reason_code.dart' show ReasonScope;
import '../../domain/models/sales_report.dart';
import '../../domain/models/supplier.dart';
import '../../domain/models/supplier_invoice.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';
import 'postgres_cash_movements_repository.dart' show CashMovementWrite;
import 'postgres_order_history_repository.dart';

/// Reads and writes `pos_supplier_invoices` and `pos_supplier_payments`.
///
/// **One repository for both**, unlike the rest of purchasing, because every
/// interesting question spans them. "What is outstanding" is invoices minus
/// payments; "may this payment be made" needs the invoice's total and what is
/// already against it. Splitting them would mean either two round trips per
/// answer or a join written twice.
///
/// Entirely on the administrator connection. A till does not pay anybody.
class PostgresSupplierInvoicesRepository implements SupplierInvoicesRepository {
  const PostgresSupplierInvoicesRepository({
    required PosDatabase database,
    required this.config,
    required this.adminAvailable,
    required this.restaurantId,
    required this.branchId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final bool adminAvailable;
  final int restaurantId;
  final int branchId;

  /// The invoice columns, plus the payments against it.
  ///
  /// **The `paid` figure is a correlated subquery rather than a stored
  /// column.** It is the sum of the live payments allocated here, so it cannot
  /// disagree with them — which a column would, the first time a payment was
  /// voided inside a transaction that failed halfway.
  static const _invoiceColumns =
      'i.id, i.supplier_id, i.supplier_name, i.purchase_order_id, '
      'i.purchase_order_reference, i.number, i.total_minor, i.tax_minor, '
      'i.issued_at, i.due_at, i.note, i.voided_at, i.void_reason_id, '
      'i.currency, i.exponent, '
      '(SELECT COALESCE(SUM(p.amount_minor), 0)::bigint FROM pos_supplier_payments p '
      '  WHERE p.invoice_id = i.id AND p.voided_at IS NULL) AS paid_minor, '
      'i.void_note';

  static const _paymentColumns =
      'y.id, y.supplier_id, y.supplier_name, y.invoice_id, y.method, '
      'y.amount_minor, y.reference, y.paid_at, y.note, y.cash_movement_id, '
      'y.voided_at, y.void_reason_id, y.currency, y.exponent, '
      '(SELECT n.number FROM pos_supplier_invoices n WHERE n.id = y.invoice_id), '
      'y.void_note';

  static String? _text(Object? value) {
    final trimmed = (value as String?)?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  SupplierInvoice _readInvoice(List<dynamic> row) {
    final currency = row[13]! as String;
    final exponent = row[14]! as int;
    Money money(int minor) =>
        Money(minor, currency: currency, exponent: exponent);

    return SupplierInvoice(
      id: row[0]! as int,
      supplierId: row[1]! as int,
      supplierName: _text(row[2]),
      purchaseOrderId: row[3] as int?,
      purchaseOrderReference: _text(row[4]),
      number: row[5]! as String,
      total: money(row[6]! as int),
      tax: money(row[7]! as int),
      issuedAt: row[8]! as DateTime,
      dueAt: row[9]! as DateTime,
      note: _text(row[10]),
      voidedAt: row[11] as DateTime?,
      voidReasonId: row[12] as int?,
      paid: money(_bigint(row[15])),
      voidNote: _text(row[16]),
    );
  }

  SupplierPayment _readPayment(List<dynamic> row) {
    final currency = row[12]! as String;
    final exponent = row[13]! as int;

    return SupplierPayment(
      id: row[0]! as int,
      supplierId: row[1]! as int,
      supplierName: _text(row[2]),
      invoiceId: row[3] as int?,
      method: SupplierPaymentMethod.fromWire(row[4]! as String),
      amount: Money(row[5]! as int, currency: currency, exponent: exponent),
      reference: _text(row[6]),
      paidAt: row[7]! as DateTime,
      note: _text(row[8]),
      cashMovementId: row[9] as int?,
      voidedAt: row[10] as DateTime?,
      voidReasonId: row[11] as int?,
      invoiceNumber: _text(row[14]),
      voidNote: _text(row[15]),
    );
  }

  AdminRefusal? _blocked(PosStaff by) {
    if (!adminAvailable) return const AdministratorCredentialRequired();
    if (!Authorization.check(by, PosCapability.purchaseManage).isAllowed) {
      return const NotPermitted(PosCapability.purchaseManage);
    }
    return null;
  }

  @override
  Future<List<SupplierInvoice>> unpaid({int? supplierId}) async {
    if (!adminAvailable) return const [];

    final rows = await _db.query(
      config,
      'SELECT $_invoiceColumns FROM pos_supplier_invoices i '
      'WHERE i.restaurant_id = @r AND i.voided_at IS NULL '
      '${supplierId == null ? '' : 'AND i.supplier_id = @s '}'
      // Filtered in SQL rather than in Dart: an old restaurant has thousands of
      // settled invoices and the screen wants the dozen that are not.
      'AND i.total_minor > (SELECT COALESCE(SUM(p.amount_minor), 0)::bigint '
      '                       FROM pos_supplier_payments p '
      '                      WHERE p.invoice_id = i.id '
      '                        AND p.voided_at IS NULL) '
      // Oldest due first, which is the order somebody pays in.
      'ORDER BY i.due_at, i.id',
      parameters: {'r': restaurantId, 's': ?supplierId},
    );
    return [for (final row in rows) _readInvoice(row)];
  }

  @override
  Future<SupplierSpending> spending(ReportFilter filter) async {
    if (!adminAvailable) return SupplierSpending.none;

    // Local midnights, as the sales list compares a row no business day
    // covers. Neither table has a business day: an invoice is dated off the
    // paper, and a payment on the day the bookkeeper says it was made.
    final window = <String, Object?>{
      'r': restaurantId,
      'from': filter.from.toUtc(),
      'to': filter.to.toUtc(),
    };
    return _db.runTx(config, (tx) async {
      final invoices = await tx.execute(
        Sql.named(
          'SELECT $_invoiceColumns FROM pos_supplier_invoices i '
          'WHERE i.restaurant_id = @r '
          '  AND i.issued_at >= @from AND i.issued_at < @to '
          'ORDER BY i.issued_at DESC, i.id DESC',
        ),
        parameters: window,
      );
      final payments = await tx.execute(
        Sql.named(
          'SELECT $_paymentColumns FROM pos_supplier_payments y '
          'WHERE y.restaurant_id = @r '
          '  AND y.paid_at >= @from AND y.paid_at < @to '
          'ORDER BY y.paid_at DESC, y.id DESC',
        ),
        parameters: window,
      );
      return SupplierSpending(
        invoices: [for (final row in invoices) _readInvoice(row)],
        payments: [for (final row in payments) _readPayment(row)],
        drawerMovementIds: await _linkedPayOuts(tx, filter),
      );
    });
  }

  @override
  Future<Set<int>> supplierPayOutIds(ReportFilter filter) async {
    if (!adminAvailable) return const {};
    return _db.runTx(config, (tx) => _linkedPayOuts(tx, filter));
  }

  /// Which drawer pay-outs in the range are a supplier payment's own. The
  /// movement is filed by the drawer's rule — the business day, as the till's
  /// range read files it — so this set and that list are cut from the same
  /// dates and meet exactly.
  Future<Set<int>> _linkedPayOuts(TxSession tx, ReportFilter filter) async {
    final drawers = PostgresOrderHistoryRepository.businessDateRange(
      from: filter.from,
      to: filter.to,
      alias: 'm',
    );
    final linked = await tx.execute(
      Sql.named(
        'SELECT y.cash_movement_id FROM pos_supplier_payments y '
        'JOIN pos_cash_movements AS m ON m.id = y.cash_movement_id '
        '${PostgresOrderHistoryRepository.tradingDayJoin('m')} '
        'WHERE y.restaurant_id = @r AND m.branch_id = @b '
        '  AND ${drawers.where.join(' AND ')}',
      ),
      parameters: {'r': restaurantId, 'b': branchId, ...drawers.parameters},
    );
    return {for (final row in linked) row[0]! as int};
  }

  @override
  Future<List<SupplierInvoice>> all({int? supplierId, int limit = 200}) async {
    if (!adminAvailable) return const [];

    final rows = await _db.query(
      config,
      'SELECT $_invoiceColumns FROM pos_supplier_invoices i '
      'WHERE i.restaurant_id = @r '
      '${supplierId == null ? '' : 'AND i.supplier_id = @s '}'
      'ORDER BY i.issued_at DESC, i.id DESC LIMIT @limit',
      parameters: {'r': restaurantId, 'limit': limit, 's': ?supplierId},
    );
    return [for (final row in rows) _readInvoice(row)];
  }

  @override
  Future<SupplierInvoice?> byId(int id) async {
    if (!adminAvailable) return null;

    final rows = await _db.query(
      config,
      'SELECT $_invoiceColumns FROM pos_supplier_invoices i '
      'WHERE i.id = @id AND i.restaurant_id = @r',
      parameters: {'id': id, 'r': restaurantId},
    );
    return rows.isEmpty ? null : _readInvoice(rows.first);
  }

  @override
  Future<List<SupplierPayment>> payments({
    int? supplierId,
    int limit = 200,
  }) async {
    if (!adminAvailable) return const [];

    final rows = await _db.query(
      config,
      'SELECT $_paymentColumns FROM pos_supplier_payments y '
      'WHERE y.restaurant_id = @r '
      '${supplierId == null ? '' : 'AND y.supplier_id = @s '}'
      'ORDER BY y.paid_at DESC, y.id DESC LIMIT @limit',
      parameters: {'r': restaurantId, 'limit': limit, 's': ?supplierId},
    );
    return [for (final row in rows) _readPayment(row)];
  }

  @override
  Future<SupplierAccount> accountFor(int supplierId, {DateTime? asOf}) async {
    final when = asOf ?? DateTime.now();
    if (!adminAvailable) {
      return SupplierAccount(
        supplierId: supplierId,
        invoices: const [],
        payments: const [],
        asOf: when,
      );
    }

    // Two queries rather than one join. A join between invoices and payments
    // multiplies the rows, and every total computed off it would count an
    // invoice once per payment against it — which is the classic way a
    // statement comes out wrong and still looks plausible.
    final invoices = await all(supplierId: supplierId, limit: 10000);
    final paid = await payments(supplierId: supplierId, limit: 10000);

    return SupplierAccount(
      supplierId: supplierId,
      invoices: [
        for (final i in invoices)
          if (!i.isVoided) i,
      ],
      payments: [
        for (final p in paid)
          if (!p.isVoided) p,
      ],
      asOf: when,
    );
  }

  @override
  Future<List<SupplierBalance>> balances({DateTime? asOf}) async {
    if (!adminAvailable) return const [];
    final when = asOf ?? DateTime.now();

    // Aggregated in SQL, and **each aggregate over its own table**. Summing
    // invoices and payments in one query needs a join that multiplies rows, so
    // each side is its own subquery and the supplier list is what joins them.
    final rows = await _db.query(
      config,
      '''
      SELECT s.id,
             COALESCE(bill.invoiced, 0),
             COALESCE(cash.paid, 0),
             COALESCE(late.overdue, 0)
        FROM pos_suppliers s
        LEFT JOIN (SELECT supplier_id, SUM(total_minor)::bigint AS invoiced
                     FROM pos_supplier_invoices
                    WHERE restaurant_id = @r AND voided_at IS NULL
                    GROUP BY supplier_id) bill ON bill.supplier_id = s.id
        LEFT JOIN (SELECT supplier_id, SUM(amount_minor) AS paid
                     FROM pos_supplier_payments
                    WHERE restaurant_id = @r AND voided_at IS NULL
                    GROUP BY supplier_id) cash ON cash.supplier_id = s.id
        LEFT JOIN (SELECT i.supplier_id,
                          SUM(GREATEST(i.total_minor - COALESCE((
                            SELECT SUM(p.amount_minor)::bigint
                              FROM pos_supplier_payments p
                             WHERE p.invoice_id = i.id
                               AND p.voided_at IS NULL), 0), 0))::bigint AS overdue
                     FROM pos_supplier_invoices i
                    WHERE i.restaurant_id = @r
                      AND i.voided_at IS NULL
                      AND i.due_at < @asOf
                    GROUP BY i.supplier_id) late ON late.supplier_id = s.id
       WHERE s.restaurant_id = @r
       ORDER BY s.name_en, s.id
      ''',
      parameters: {'r': restaurantId, 'asOf': when},
    );

    return [
      for (final row in rows)
        SupplierBalance(
          supplierId: row[0]! as int,
          invoiced: Money(_bigint(row[1])),
          paid: Money(_bigint(row[2])),
          overdue: Money(_bigint(row[3])),
        ),
    ];
  }

  /// `SUM()` comes back as a `BigInt` on some drivers and an `int` on others.
  /// `SUM()` over a `bigint` column is `numeric` in Postgres, and the driver
  /// hands numeric back as a **String** rather than risk losing precision.
  /// Every aggregate here is cast to `bigint` in SQL for that reason; this
  /// copes with the ones that are not, because the alternative is a type error
  /// a long way from its cause.
  static int _bigint(Object? value) => switch (value) {
    final int i => i,
    final BigInt b => b.toInt(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  @override
  Future<AdminResult<SupplierInvoice>> save(
    SupplierInvoice invoice, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    final problems = invoice.problems;
    if (problems.isNotEmpty) {
      return AdminResult.refused(CatalogInvalid(problems.first.message));
    }

    // The write commits, then the row is read back. `byId` opens its own
    // connection and would query a snapshot that cannot see uncommitted rows —
    // which surfaces as a null some distance from the cause.
    final written = await _db.runTx(config, (tx) async {
      final supplier = await tx.execute(
        Sql.named(
          'SELECT name_en, payment_term_days FROM pos_suppliers '
          'WHERE id = @s AND restaurant_id = @r',
        ),
        parameters: {'s': invoice.supplierId, 'r': restaurantId},
      );
      if (supplier.isEmpty) {
        return const AdminResult<int>.refused(
          CatalogInvalid('That supplier is not on this restaurant.'),
        );
      }

      // Checked here as well as by the unique index, so the refusal can name
      // the invoice that is already on file rather than surfacing a constraint
      // name to somebody holding a piece of paper.
      final clash = await tx.execute(
        Sql.named(
          'SELECT id FROM pos_supplier_invoices '
          'WHERE restaurant_id = @r AND supplier_id = @s '
          '  AND lower(btrim(number)) = lower(btrim(@number)) '
          '  AND voided_at IS NULL AND id <> @id',
        ),
        parameters: {
          'r': restaurantId,
          's': invoice.supplierId,
          'number': invoice.number,
          'id': invoice.id,
        },
      );
      if (clash.isNotEmpty) {
        return AdminResult<int>.refused(
          CatalogInvalid(
            'Invoice ${invoice.number.trim()} from this supplier is already '
            'entered.',
          ),
        );
      }

      if (invoice.id != 0) {
        // Re-read under a lock: a voided invoice is a record, and correcting
        // one means entering a new invoice, not editing the cancelled one.
        final held = await tx.execute(
          Sql.named(
            'SELECT voided_at FROM pos_supplier_invoices '
            'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
          ),
          parameters: {'id': invoice.id, 'r': restaurantId},
        );
        if (held.isEmpty) {
          return const AdminResult<int>.refused(EditedElsewhere(0));
        }
        if (held.first[0] != null) {
          return const AdminResult<int>.refused(
            CatalogInvalid(
              'That invoice was cancelled. Enter a new one rather than '
              'changing it.',
            ),
          );
        }
      }

      final parameters = <String, Object?>{
        'r': restaurantId,
        'b': branchId,
        's': invoice.supplierId,
        'name': supplier.first[0]! as String,
        'order': invoice.purchaseOrderId,
        'orderRef': invoice.purchaseOrderReference,
        'number': invoice.number.trim(),
        'total': invoice.total.minor,
        'tax': invoice.tax.minor,
        'issued': invoice.issuedAt,
        'due': invoice.dueAt,
        'note': invoice.note?.trim(),
        'by': by.id == 0 ? null : by.id,
      };

      final rows = invoice.id == 0
          ? await tx.execute(
              Sql.named(
                'INSERT INTO pos_supplier_invoices (restaurant_id, branch_id, '
                '  supplier_id, supplier_name, purchase_order_id, '
                '  purchase_order_reference, number, total_minor, tax_minor, '
                '  issued_at, due_at, note, created_by, updated_by) '
                'VALUES (@r, @b, @s, @name, @order, @orderRef, @number, '
                '        @total, @tax, @issued, @due, @note, @by, @by) '
                'RETURNING id',
              ),
              parameters: parameters,
            )
          : await tx.execute(
              Sql.named(
                'UPDATE pos_supplier_invoices SET number = @number, '
                '  total_minor = @total, tax_minor = @tax, '
                '  issued_at = @issued, due_at = @due, note = @note, '
                '  purchase_order_id = @order, '
                '  purchase_order_reference = @orderRef, '
                '  updated_at = now(), updated_by = @by '
                'WHERE id = @id AND restaurant_id = @r RETURNING id',
              ),
              // Only what the UPDATE names. `Sql.named` refuses superfluous
              // parameters, and the insert's map carries three the update does
              // not use — the branch, the supplier and its name, none of which
              // an existing invoice may be moved to anyway.
              parameters: {
                'r': restaurantId,
                'id': invoice.id,
                'number': invoice.number.trim(),
                'total': invoice.total.minor,
                'tax': invoice.tax.minor,
                'issued': invoice.issuedAt,
                'due': invoice.dueAt,
                'note': invoice.note?.trim(),
                'order': invoice.purchaseOrderId,
                'orderRef': invoice.purchaseOrderReference,
                'by': by.id == 0 ? null : by.id,
              },
            );

      if (rows.isEmpty) {
        return const AdminResult<int>.refused(EditedElsewhere(0));
      }

      final id = rows.first[0]! as int;
      await _audit(
        tx,
        by: by,
        action: AuditAction.supplierInvoiceSaved,
        entityType: AuditAction.entitySupplierInvoice,
        entityId: id,
        after:
            '{"number": ${_json(invoice.number.trim())}, '
            '"total_minor": ${invoice.total.minor}, '
            '"supplier": ${_json(supplier.first[0]! as String)}}',
      );
      return AdminResult<int>.done(id);
    });

    if (written.refusal != null) {
      return AdminResult.refused(written.refusal!);
    }
    return AdminResult.done((await byId(written.value!))!);
  }

  @override
  Future<AdminResult<SupplierInvoice>> voidInvoice(
    int id, {
    required int reasonId,
    required PosStaff by,
    String? note,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    final outcome = await _db.runTx(config, (tx) async {
      final held = await tx.execute(
        Sql.named(
          'SELECT voided_at, number, '
          '  (SELECT COALESCE(SUM(amount_minor), 0)::bigint '
          '     FROM pos_supplier_payments '
          '    WHERE invoice_id = @id AND voided_at IS NULL) '
          'FROM pos_supplier_invoices '
          'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
        ),
        parameters: {'id': id, 'r': restaurantId},
      );
      if (held.isEmpty) {
        return const AdminResult<int>.refused(EditedElsewhere(0));
      }
      if (held.first[0] != null) {
        // Already cancelled. Not an error worth a scary message — somebody
        // clicked twice, or two people did.
        return AdminResult<int>.done(id);
      }

      final allocated = _bigint(held.first[2]);
      if (allocated > 0) {
        // The database refuses this too, in a trigger. Refused here as well so
        // the message can say how much, and say what to do about it.
        return AdminResult<int>.refused(
          CatalogInvalid(
            'There is ${Money(allocated).format(withCurrency: true)} paid against this invoice. '
            'Void the payments first.',
          ),
        );
      }

      await tx.execute(
        Sql.named(
          'UPDATE pos_supplier_invoices SET voided_at = now(), '
          '  voided_by = @by, void_reason_id = @reason, void_note = @note, '
          '  updated_at = now(), updated_by = @by '
          'WHERE id = @id AND restaurant_id = @r',
        ),
        parameters: {
          'id': id,
          'r': restaurantId,
          'by': by.id == 0 ? null : by.id,
          'reason': reasonId,
          'note': note?.trim(),
        },
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.supplierInvoiceVoided,
        entityType: AuditAction.entitySupplierInvoice,
        entityId: id,
        after:
            '{"number": ${_json((held.first[1] as String?) ?? '')}, '
            '"reason_id": $reasonId}',
      );
      return AdminResult<int>.done(id);
    });

    if (outcome.refusal != null) return AdminResult.refused(outcome.refusal!);
    return AdminResult.done((await byId(id))!);
  }

  /// The reason a supplier pay-out is recorded under.
  ///
  /// One of the restaurant's own `ReasonScope.payOut` codes — `SystemReasons`
  /// has seeded `supplier` since migration 14 — rather than a new code or a free
  /// sentence. The pay-out list already had the right answer on it, and asking
  /// the manager to pick "Supplier payment" from a list on a screen that says
  /// *Pay Nile Dairy* at the top is a tap that cannot go any other way.
  static const _payOutReasonCode = 'supplier';

  /// And the code a compensating pay-in goes back in under, when a till payment
  /// is voided. `correction` is what `SystemReasons.cashIn` calls it.
  static const _payInReasonCode = 'correction';

  /// The id of one of this restaurant's active reason codes, or null.
  Future<int?> _reasonId(TxSession tx, String scope, String code) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id FROM pos_reason_codes '
        'WHERE restaurant_id = @r AND scope = @scope AND code = @code '
        '  AND is_active ORDER BY id LIMIT 1',
      ),
      parameters: {'r': restaurantId, 'scope': scope, 'code': code},
    );
    return rows.isEmpty ? null : rows.first[0]! as int;
  }

  /// What a drawer movement says beside the amount, on the Z report.
  ///
  /// Built from the supplier and the invoice number and nothing else, because
  /// this is one of the few notes in the product that no person typed — and a
  /// sentence written in English by the app would be the only English on an
  /// Arabic Z report. A name and a number read the same in both.
  static String _movementNote(String supplier, String? invoiceNumber) =>
      invoiceNumber == null ? supplier : '$supplier — $invoiceNumber';

  @override
  Future<AdminResult<SupplierPayment>> pay(
    SupplierPayment payment, {
    required PosStaff by,
    int? fromShiftId,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    // **Two authorities, not one.** `purchase.manage` is permission to say what
    // the restaurant owes and has paid; reaching into a till drawer is
    // `cash.movement`, which is what the till itself checks before a pay-out.
    // A bookkeeper entering invoices is not automatically somebody who may take
    // 500 out of a drawer, and the manager role holds both anyway — so
    // requiring both costs a real restaurant nothing and stops the back office
    // becoming a way around the counter's own gate.
    //
    // Refused outright rather than quietly recorded without the movement: a
    // payment that silently does not reduce the drawer is precisely the bug
    // this exists to fix, and doing it under a permission refusal would hide
    // it behind something that looks like a security message.
    if (fromShiftId != null &&
        !Authorization.check(by, PosCapability.cashMovement).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.cashMovement),
      );
    }

    if (fromShiftId != null && payment.method != SupplierPaymentMethod.cash) {
      return const AdminResult.refused(
        CatalogInvalid(
          'Only a cash payment comes out of the till drawer. A transfer, a '
          'cheque or a card never passes through it.',
        ),
      );
    }

    // `pos_cash_movements.user_id` is NOT NULL, and it is the one column on
    // that row that matters afterwards: a pay-out nobody is named on is a
    // shortage nobody can be asked about. Every other write here tolerates
    // `id == 0` by storing null; this one must not.
    if (fromShiftId != null && by.id == 0) {
      return const AdminResult.refused(
        CatalogInvalid(
          'A drawer pay-out has to name who took the money out, and this '
          'session has no staff record. Sign in again before paying out of the '
          'till.',
        ),
      );
    }

    final problems = payment.problems;
    if (problems.isNotEmpty) {
      return AdminResult.refused(CatalogInvalid(problems.first.message));
    }

    final written = await _db.runTx(config, (tx) async {
      final supplier = await tx.execute(
        Sql.named(
          'SELECT name_en FROM pos_suppliers '
          'WHERE id = @s AND restaurant_id = @r',
        ),
        parameters: {'s': payment.supplierId, 'r': restaurantId},
      );
      if (supplier.isEmpty) {
        return const AdminResult<int>.refused(
          CatalogInvalid('That supplier is not on this restaurant.'),
        );
      }

      // The number as the invoice row has it, for the drawer movement's note —
      // not `payment.invoiceNumber`, which is whatever the screen was showing.
      // A note on a Z report is read a month later against the invoice itself.
      String? invoiceNumber;

      if (payment.invoiceId != null) {
        // Locked, so two bookkeepers paying the same invoice queue rather than
        // both reading the same room and both being allowed. The trigger does
        // this as well; doing it here is what lets the refusal say the numbers.
        final bill = await tx.execute(
          Sql.named(
            'SELECT supplier_id, total_minor, voided_at, '
            '  (SELECT COALESCE(SUM(amount_minor), 0)::bigint '
            '     FROM pos_supplier_payments '
            '    WHERE invoice_id = @i AND voided_at IS NULL), '
            '  number '
            'FROM pos_supplier_invoices '
            'WHERE id = @i AND restaurant_id = @r FOR UPDATE',
          ),
          parameters: {'i': payment.invoiceId, 'r': restaurantId},
        );
        if (bill.isEmpty) {
          return const AdminResult<int>.refused(
            CatalogInvalid('That invoice is not on this restaurant.'),
          );
        }
        if (bill.first[0]! as int != payment.supplierId) {
          return const AdminResult<int>.refused(
            CatalogInvalid('That invoice is from a different supplier.'),
          );
        }
        if (bill.first[2] != null) {
          return const AdminResult<int>.refused(
            CatalogInvalid('That invoice was cancelled.'),
          );
        }

        invoiceNumber = _text(bill.first[4]);
        final total = bill.first[1]! as int;
        final already = _bigint(bill.first[3]);
        if (already + payment.amount.minor > total) {
          final room = Money(
            total - already,
            currency: payment.amount.currency,
            exponent: payment.amount.exponent,
          );
          return AdminResult<int>.refused(
            CatalogInvalid(
              room.isPositive
                  ? 'Only ${room.format(withCurrency: true)} is left on that invoice. Anything '
                        'more goes on account.'
                  : 'That invoice is already paid in full.',
            ),
          );
        }
      }

      // ── Out of the drawer, in the same transaction ──────────────────────
      //
      // Written *before* the payment, so the payment can carry the movement's
      // id in its own INSERT. The office holds no UPDATE grant on
      // `cash_movement_id` — deliberately, it is a fact about how the money
      // left and not a working field — so writing the payment first and
      // pointing it at the movement afterwards is not available, and would not
      // be better if it were: it is one more statement that can fail with a row
      // already on file.
      //
      // Everything below is inside `runTx`. A throw from any of it takes the
      // movement and the payment down together, which is the whole point: a
      // drawer 500 down with no payment behind it is a worse thing to leave
      // behind than the shortage this feature removes.
      int? movementId;
      if (fromShiftId != null) {
        // The **shift's** terminal, not the machine the bookkeeper is sitting
        // at. Management may well be running on the back-office PC, and the
        // drawer that goes short is the one on the till the shift is open on.
        final drawer = await tx.execute(
          Sql.named(
            'SELECT terminal_id::text, business_day_id, closed_at '
            'FROM pos_shifts '
            'WHERE id = @s AND restaurant_id = @r AND branch_id = @b '
            'FOR UPDATE',
          ),
          parameters: {'s': fromShiftId, 'r': restaurantId, 'b': branchId},
        );
        if (drawer.isEmpty) {
          return const AdminResult<int>.refused(
            CatalogInvalid('That shift is not on this branch.'),
          );
        }
        if (drawer.first[2] != null) {
          // Locked above, so a cash-up running at the same moment either counted
          // this pay-out or refused it — never counted a drawer and then had a
          // pay-out appear on the shift it just closed.
          return const AdminResult<int>.refused(
            CatalogInvalid(
              'That shift has been closed and counted. A pay-out added now '
              'would change a Z report somebody has already signed — record it '
              'on the shift that is open.',
            ),
          );
        }

        final reasonId = await _reasonId(
          tx,
          ReasonScope.payOut.wire,
          _payOutReasonCode,
        );
        if (reasonId == null) {
          return const AdminResult<int>.refused(
            CatalogInvalid(
              'This restaurant has no active pay-out reason coded "supplier", '
              'so the drawer movement would have nothing to be reported under. '
              'Add it to the pay-out reasons first.',
            ),
          );
        }

        final amount = CashMovementWrite.normalise(
          CashMovementKind.payOut,
          payment.amount,
        );
        CashMovementWrite.refuseNothing(CashMovementKind.payOut, amount);
        final movementClientId = config.mode.syncsSalesToPlatform
            ? const Uuid().v4()
            : null;

        final movement = await tx.execute(
          Sql.named(CashMovementWrite.sql),
          parameters: CashMovementWrite.parameters(
            restaurantId: restaurantId,
            branchId: branchId,
            terminalId: drawer.first[0]! as String,
            shiftId: fromShiftId,
            businessDayId: drawer.first[1] as int?,
            kind: CashMovementKind.payOut,
            amount: amount,
            reasonId: reasonId,
            note: _movementNote(supplier.first[0]! as String, invoiceNumber),
            staffId: by.id,
            clientTransactionId: movementClientId,
          ),
        );
        movementId = movement.first[0]! as int;
        if (movementClientId != null) {
          await _enqueueCashMovement(
            tx,
            sourceId: movementId,
            clientTransactionId: movementClientId,
          );
        }
      }

      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_supplier_payments (restaurant_id, branch_id, '
          '  supplier_id, supplier_name, invoice_id, method, amount_minor, '
          '  reference, paid_at, note, cash_movement_id, created_by) '
          'VALUES (@r, @b, @s, @name, @i, @method, @amount, @ref, @at, @note, '
          '        @movement, @by) RETURNING id',
        ),
        parameters: {
          'r': restaurantId,
          'b': branchId,
          's': payment.supplierId,
          'name': supplier.first[0]! as String,
          'i': payment.invoiceId,
          'method': payment.method.wire,
          'amount': payment.amount.minor,
          'ref': payment.reference?.trim(),
          'at': payment.paidAt,
          'note': payment.note?.trim(),
          'movement': movementId,
          'by': by.id == 0 ? null : by.id,
        },
      );

      final id = rows.first[0]! as int;
      await _audit(
        tx,
        by: by,
        action: AuditAction.supplierPaid,
        entityType: AuditAction.entitySupplierPayment,
        entityId: id,
        after:
            '{"amount_minor": ${payment.amount.minor}, '
            '"method": ${_json(payment.method.wire)}, '
            '"invoice_id": ${payment.invoiceId ?? 'null'}, '
            // On the audit row because "who took money out of which drawer" is
            // the question a variance turns into, and the payment row alone
            // does not say which shift.
            '"shift_id": ${fromShiftId ?? 'null'}, '
            '"cash_movement_id": ${movementId ?? 'null'}, '
            '"supplier": ${_json(supplier.first[0]! as String)}}',
      );
      return AdminResult<int>.done(id);
    });

    if (written.refusal != null) {
      return AdminResult.refused(written.refusal!);
    }
    return AdminResult.done((await _paymentById(written.value!))!);
  }

  @override
  Future<AdminResult<SupplierPayment>> voidPayment(
    int id, {
    required int reasonId,
    required PosStaff by,
    String? note,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    final outcome = await _db.runTx(config, (tx) async {
      final held = await tx.execute(
        Sql.named(
          'SELECT voided_at, amount_minor, cash_movement_id, supplier_name '
          'FROM pos_supplier_payments '
          'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
        ),
        parameters: {'id': id, 'r': restaurantId},
      );
      if (held.isEmpty) {
        return const AdminResult<int>.refused(EditedElsewhere(0));
      }
      if (held.first[0] != null) return AdminResult<int>.done(id);

      // ── The drawer, when the money came out of one ──────────────────────
      //
      // **A cash movement is never edited or deleted; a correction is a second
      // movement.** That is this product's rule everywhere else and it is not
      // relaxed here, so the pay-out stands and a `pay_in` puts the cash back —
      // in this same transaction, on the same shift, while that shift is open.
      //
      // Defaulting to "the cash came back" is a judgement, and this is the
      // argument for it: a void in the back office almost always means *entered
      // twice* or *wrong amount*, where no second bundle of money left the
      // building — the drawer is short by a pay-out that should never have
      // existed and the notes are still in it. The case it gets wrong, paying a
      // supplier who keeps the money, is not honestly a void at all: that
      // payment happened, and what is owed comes back as a credit note.
      //
      // Two alternatives were rejected. **Leaving the pay-out standing
      // silently** is the original bug wearing the other hat — the manager would
      // find a drawer that is right and a ledger that says nothing was paid.
      // **Refusing the void outright** reads well and is unusable: there is then
      // no way to correct a mistyped payment from the office at all, and the
      // person who wants one would edit the database.
      final movementId = held.first[2] as int?;
      if (movementId != null) {
        // Putting cash back is a drawer act like taking it out, so it wants the
        // same key. A bookkeeper who may not open a drawer may not do this
        // either, even though what they are undoing is their own row.
        if (!Authorization.check(by, PosCapability.cashMovement).isAllowed) {
          return const AdminResult<int>.refused(
            NotPermitted(PosCapability.cashMovement),
          );
        }

        final drawer = await tx.execute(
          Sql.named(
            'SELECT m.shift_id, m.terminal_id::text, m.amount_minor, m.note, '
            '       s.business_day_id, s.closed_at '
            'FROM pos_cash_movements m JOIN pos_shifts s ON s.id = m.shift_id '
            'WHERE m.id = @m FOR UPDATE OF s',
          ),
          parameters: {'m': movementId},
        );
        if (drawer.isEmpty) {
          return const AdminResult<int>.refused(
            CatalogInvalid(
              'This payment names a drawer movement that is no longer on file. '
              'It cannot be reversed here.',
            ),
          );
        }

        if (drawer.first[5] == null) {
          final reasonForPayIn = await _reasonId(
            tx,
            ReasonScope.payIn.wire,
            _payInReasonCode,
          );
          if (reasonForPayIn == null) {
            return const AdminResult<int>.refused(
              CatalogInvalid(
                'This restaurant has no active pay-in reason coded '
                '"correction", so the cash has nowhere to go back in under. '
                'Add it to the pay-in reasons first.',
              ),
            );
          }
          if (by.id == 0) {
            return const AdminResult<int>.refused(
              CatalogInvalid(
                'Putting cash back in a drawer has to name who put it there, '
                'and this session has no staff record.',
              ),
            );
          }

          // The same note as the pay-out it answers, so the two read as a pair
          // on the drawer's history — "− Nile Dairy — INV-900" above
          // "+ Nile Dairy — INV-900" — rather than as two unrelated events a
          // manager has to work out for themselves.
          final movementClientId = config.mode.syncsSalesToPlatform
              ? const Uuid().v4()
              : null;
          final movement = await tx.execute(
            Sql.named(CashMovementWrite.sql),
            parameters: CashMovementWrite.parameters(
              restaurantId: restaurantId,
              branchId: branchId,
              terminalId: drawer.first[1]! as String,
              shiftId: drawer.first[0]! as int,
              businessDayId: drawer.first[4] as int?,
              kind: CashMovementKind.payIn,
              amount: Money(drawer.first[2]! as int),
              reasonId: reasonForPayIn,
              note: drawer.first[3] as String?,
              staffId: by.id,
              clientTransactionId: movementClientId,
            ),
          );
          if (movementClientId != null) {
            await _enqueueCashMovement(
              tx,
              sourceId: movement.first[0]! as int,
              clientTransactionId: movementClientId,
            );
          }
        } else if ((note ?? '').trim().isEmpty) {
          // The drawer has been counted. A `pay_in` on a closed shift would
          // rewrite an expected total a manager already argued about, and one on
          // *today's* shift would claim cash appeared in a drawer nobody put
          // cash into — so neither is written, and the only thing left worth
          // recording is where the money actually went. That is a sentence,
          // and it is required.
          return const AdminResult<int>.refused(
            CatalogInvalid(
              'This payment took cash out of a till whose shift has since been '
              'counted, so the drawer cannot be put back. Say in a note where '
              'the money went, and record any cash returning to the till as a '
              'pay-in there.',
            ),
          );
        }
      }

      await tx.execute(
        Sql.named(
          'UPDATE pos_supplier_payments SET voided_at = now(), '
          '  voided_by = @by, void_reason_id = @reason, void_note = @note '
          'WHERE id = @id AND restaurant_id = @r',
        ),
        parameters: {
          'id': id,
          'r': restaurantId,
          'by': by.id == 0 ? null : by.id,
          'reason': reasonId,
          'note': note?.trim(),
        },
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.supplierPaymentVoided,
        entityType: AuditAction.entitySupplierPayment,
        entityId: id,
        after:
            '{"amount_minor": ${held.first[1]}, "reason_id": $reasonId, '
            '"cash_movement_id": ${held.first[2] ?? 'null'}}',
      );
      return AdminResult<int>.done(id);
    });

    if (outcome.refusal != null) return AdminResult.refused(outcome.refusal!);
    return AdminResult.done((await _paymentById(id))!);
  }

  Future<SupplierPayment?> _paymentById(int id) async {
    final rows = await _db.query(
      config,
      'SELECT $_paymentColumns FROM pos_supplier_payments y '
      'WHERE y.id = @id AND y.restaurant_id = @r',
      parameters: {'id': id, 'r': restaurantId},
    );
    return rows.isEmpty ? null : _readPayment(rows.first);
  }

  Future<void> _audit(
    TxSession tx, {
    required PosStaff by,
    required String action,
    required String entityType,
    required int entityId,
    required String after,
  }) => tx.execute(
    Sql.named('''
    INSERT INTO pos_audit_events
      (restaurant_id, branch_id, actor_user_id, actor_name, action,
       entity_type, entity_id, after_value)
    VALUES (@restaurant, @branch, @by, @actor, @action, @type, @entity,
            @after::jsonb)
    '''),
    parameters: {
      'restaurant': restaurantId,
      'branch': branchId,
      'by': by.id == 0 ? null : by.id,
      'actor': by.name,
      'action': action,
      'type': entityType,
      'entity': '$entityId',
      'after': after,
    },
  );

  static String _json(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  Future<void> _enqueueCashMovement(
    TxSession tx, {
    required int sourceId,
    required String clientTransactionId,
  }) => tx.execute(
    Sql.named('''
      INSERT INTO pos_sync_outbox
        (restaurant_id, branch_id, event_type, source_id, client_transaction_id)
      VALUES (@restaurant, @branch, 'cash_movement', @source, @client)
      ON CONFLICT (restaurant_id, client_transaction_id) DO NOTHING
    '''),
    parameters: {
      'restaurant': restaurantId,
      'branch': branchId,
      'source': sourceId,
      'client': clientTransactionId,
    },
  );
}

/// What a terminal binds before it has an administrator credential.
class UnconfiguredSupplierInvoicesRepository
    implements SupplierInvoicesRepository {
  const UnconfiguredSupplierInvoicesRepository();

  @override
  Future<List<SupplierInvoice>> unpaid({int? supplierId}) async => const [];

  @override
  Future<SupplierSpending> spending(ReportFilter filter) async =>
      SupplierSpending.none;

  @override
  Future<Set<int>> supplierPayOutIds(ReportFilter filter) async => const {};

  @override
  Future<List<SupplierInvoice>> all({int? supplierId, int limit = 200}) async =>
      const [];

  @override
  Future<SupplierInvoice?> byId(int id) async => null;

  @override
  Future<List<SupplierPayment>> payments({
    int? supplierId,
    int limit = 200,
  }) async => const [];

  @override
  Future<SupplierAccount> accountFor(int supplierId, {DateTime? asOf}) async =>
      SupplierAccount(
        supplierId: supplierId,
        invoices: const [],
        payments: const [],
        asOf: asOf ?? DateTime.now(),
      );

  @override
  Future<List<SupplierBalance>> balances({DateTime? asOf}) async => const [];

  @override
  Future<AdminResult<SupplierInvoice>> save(
    SupplierInvoice invoice, {
    required PosStaff by,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<SupplierInvoice>> voidInvoice(
    int id, {
    required int reasonId,
    required PosStaff by,
    String? note,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<SupplierPayment>> pay(
    SupplierPayment payment, {
    required PosStaff by,
    int? fromShiftId,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<SupplierPayment>> voidPayment(
    int id, {
    required int reasonId,
    required PosStaff by,
    String? note,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}
