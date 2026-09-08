import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/supplier.dart';
import '../../domain/models/supplier_invoice.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';

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
            'There is ${Money(allocated).format()} paid against this invoice. '
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

  @override
  Future<AdminResult<SupplierPayment>> pay(
    SupplierPayment payment, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

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

      if (payment.invoiceId != null) {
        // Locked, so two bookkeepers paying the same invoice queue rather than
        // both reading the same room and both being allowed. The trigger does
        // this as well; doing it here is what lets the refusal say the numbers.
        final bill = await tx.execute(
          Sql.named(
            'SELECT supplier_id, total_minor, voided_at, '
            '  (SELECT COALESCE(SUM(amount_minor), 0)::bigint '
            '     FROM pos_supplier_payments '
            '    WHERE invoice_id = @i AND voided_at IS NULL) '
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
                  ? 'Only ${room.format()} is left on that invoice. Anything '
                        'more goes on account.'
                  : 'That invoice is already paid in full.',
            ),
          );
        }
      }

      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_supplier_payments (restaurant_id, branch_id, '
          '  supplier_id, supplier_name, invoice_id, method, amount_minor, '
          '  reference, paid_at, note, created_by) '
          'VALUES (@r, @b, @s, @name, @i, @method, @amount, @ref, @at, @note, '
          '        @by) RETURNING id',
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
          'SELECT voided_at, amount_minor FROM pos_supplier_payments '
          'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
        ),
        parameters: {'id': id, 'r': restaurantId},
      );
      if (held.isEmpty) {
        return const AdminResult<int>.refused(EditedElsewhere(0));
      }
      if (held.first[0] != null) return AdminResult<int>.done(id);

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
            '{"amount_minor": ${held.first[1]}, "reason_id": $reasonId}',
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
      (restaurant_id, branch_id, actor_staff_id, actor_name, action,
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
}

/// What a terminal binds before it has an administrator credential.
class UnconfiguredSupplierInvoicesRepository
    implements SupplierInvoicesRepository {
  const UnconfiguredSupplierInvoicesRepository();

  @override
  Future<List<SupplierInvoice>> unpaid({int? supplierId}) async => const [];

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
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<SupplierPayment>> voidPayment(
    int id, {
    required int reasonId,
    required PosStaff by,
    String? note,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}
