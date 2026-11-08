import '../sql/sql.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../../domain/services/authorization.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/purchase_order.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';

/// Reads and writes purchase orders.
///
/// Administrative only, like the suppliers they name.
class PostgresPurchaseOrdersRepository implements PurchaseOrdersRepository {
  const PostgresPurchaseOrdersRepository({
    required SqlDatabase database,
    required this.config,
    required this.adminAvailable,
    required this.businessId,
    required this.branchId,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final bool adminAvailable;
  final int businessId;
  final int branchId;

  static const _orderColumns =
      'id, supplier_id, supplier_name, reference, status, currency, exponent, '
      'ordered_at, expected_at, notes';

  @override
  Future<List<PurchaseOrder>> open() => _search(
    "AND o.status IN ('sent', 'partially_received')",
  );

  @override
  Future<List<PurchaseOrder>> all({int limit = 100}) =>
      _search('', limit: limit);

  @override
  Future<PurchaseOrder?> byId(int id) async {
    final found = await _search('AND o.id = @id', parameters: {'id': id});
    return found.isEmpty ? null : found.first;
  }

  Future<List<PurchaseOrder>> _search(
    String where, {
    Map<String, Object?> parameters = const {},
    int limit = 100,
  }) async {
    if (!adminAvailable) return const [];

    final orders = await _db.query(
      config,
      'SELECT ${_orderColumns.split(', ').map((c) => 'o.$c').join(', ')} '
      'FROM pos_purchase_orders o '
      'WHERE o.business_id = @r AND o.branch_id = @b $where '
      'ORDER BY o.id DESC LIMIT @limit',
      parameters: {
        'r': businessId,
        'b': branchId,
        'limit': limit,
        ...parameters,
      },
    );
    if (orders.isEmpty) return const [];

    final ids = [for (final row in orders) row[0]! as int];
    final lines = await _db.query(
      config,
      'SELECT $_lineColumns FROM pos_purchase_order_lines '
      'WHERE purchase_order_id = ANY(@ids) ORDER BY sort_order, id',
      parameters: {'ids': ids},
    );

    final byOrder = <int, List<PurchaseOrderLine>>{};
    for (final row in lines) {
      byOrder.putIfAbsent(row[0]! as int, () => []).add(_line(row));
    }

    return [
      for (final row in orders)
        _order(row, byOrder[row[0]! as int] ?? const []),
    ];
  }

  static const _lineColumns =
      'purchase_order_id, id, product_id, description, sku, ordered_milli, '
      'received_milli, unit, unit_cost_minor, tax_rate_bp';

  static PurchaseOrderLine _line(List<Object?> row) {
    final unit = QuantityUnit.fromWire(row[7] as String?);
    return PurchaseOrderLine(
      id: row[1]! as int,
      productId: row[2] as int?,
      description: row[3]! as String,
      sku: row[4] as String?,
      ordered: Quantity(row[5]! as int, unit: unit),
      received: Quantity(row[6]! as int, unit: unit),
      unitCost: Money(row[8]! as int),
      taxRateBp: row[9]! as int,
    );
  }

  /// [row] is [_orderColumns], in that order.
  static PurchaseOrder _order(
    List<Object?> row,
    List<PurchaseOrderLine> lines,
  ) => PurchaseOrder(
    id: row[0]! as int,
    supplierId: row[1]! as int,
    supplierName: row[2] as String?,
    reference: row[3]! as String,
    status: PurchaseStatus.fromWire(row[4]! as String),
    currency: row[5]! as String,
    exponent: row[6]! as int,
    orderedAt: (row[7] as DateTime?)?.toUtc(),
    expectedAt: (row[8] as DateTime?)?.toUtc(),
    notes: row[9] as String?,
    lines: lines,
  );

  /// The order as it is now, with its lines, locked for the rest of [tx].
  ///
  /// Read on the transaction rather than through [byId], which opens its own
  /// connection: that would read a snapshot the lock does not cover, and the
  /// point of locking is that nothing moves between the read and the write.
  Future<PurchaseOrder?> _locked(TxSession tx, int id) async {
    final held = await tx.execute(
      Sql.named(
        'SELECT $_orderColumns FROM pos_purchase_orders '
        'WHERE id = @id AND business_id = @r FOR UPDATE',
      ),
      parameters: {'id': id, 'r': businessId},
    );
    if (held.isEmpty) return null;

    final lines = await tx.execute(
      Sql.named(
        'SELECT $_lineColumns FROM pos_purchase_order_lines '
        'WHERE purchase_order_id = @id ORDER BY sort_order, id',
      ),
      parameters: {'id': id},
    );
    return _order(held.first, [for (final row in lines) _line(row)]);
  }

  AdminRefusal? _blocked(PosStaff by) {
    if (!adminAvailable) return const AdministratorCredentialRequired();
    // `Authorization.check` and not `by.capabilities`: that field holds the
    // direct grants alone, so a manager whose permission comes from their
    // role would have been refused. It also asks whether they are still
    // employed, which membership of a set does not.
    if (!Authorization.check(by, PosCapability.purchaseManage).isAllowed) {
      return const NotPermitted(PosCapability.purchaseManage);
    }
    return null;
  }

  @override
  Future<AdminResult<PurchaseOrder>> saveDraft(
    PurchaseOrder order, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    // The write runs in one transaction and the read-back after it commits.
    // `byId` opens its own connection, so calling it inside the transaction
    // would query a snapshot that cannot see the rows just written — which
    // fails as a null, some distance from the cause.
    final written = await _db.runTx(config, (tx) async {
      // Re-read under a lock rather than trusting the status the screen holds:
      // two buyers on two machines is the case this exists for, and the second
      // one must not edit an order the first has already sent.
      if (order.id != 0) {
        final held = await tx.execute(
          Sql.named(
            'SELECT status FROM pos_purchase_orders '
            'WHERE id = @id AND business_id = @r FOR UPDATE',
          ),
          parameters: {'id': order.id, 'r': businessId},
        );
        if (held.isEmpty) {
          return const AdminResult<int>.refused(EditedElsewhere(0));
        }
        final status = PurchaseStatus.fromWire(held.first[0]! as String);
        if (!status.isEditable) {
          return AdminResult<int>.refused(CatalogInvalid(_notEditable(status)));
        }
      }

      final totals = order.totals;
      final id = order.id != 0
          ? order.id
          : await _insert(tx, order, totals, by);

      if (order.id != 0) {
        await tx.execute(
          Sql.named(
            'UPDATE pos_purchase_orders SET supplier_id = @supplier, '
            '  supplier_name = @name, expected_at = @expected, notes = @notes, '
            '  subtotal_minor = @subtotal, tax_minor = @tax, '
            '  total_minor = @total, updated_at = now(), updated_by = @by '
            'WHERE id = @id',
          ),
          parameters: {
            'id': id,
            'supplier': order.supplierId,
            'name': order.supplierName ?? '',
            'expected': order.expectedAt,
            'notes': order.notes,
            'subtotal': totals.subtotal.minor,
            'tax': totals.tax.minor,
            'total': totals.total.minor,
            'by': by.id == 0 ? null : by.id,
          },
        );
      }

      // Replace the lines wholesale. A draft's lines are the current shape of
      // a document nobody has sent, not a record of anything — and diffing
      // them would need a reconciliation to express what the screen already
      // knows in full.
      await tx.execute(
        Sql.named(
          'DELETE FROM pos_purchase_order_lines WHERE purchase_order_id = @id',
        ),
        parameters: {'id': id},
      );
      var sort = 0;
      for (final line in order.lines) {
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_purchase_order_lines (purchase_order_id, '
            '  product_id, description, sku, ordered_milli, received_milli, '
            '  unit, unit_cost_minor, tax_rate_bp, sort_order) '
            'VALUES (@order, @product, @description, @sku, @ordered, '
            '        @received, @unit, @cost, @tax, @sort)',
          ),
          parameters: {
            'order': id,
            'product': line.productId,
            'description': line.description,
            'sku': line.sku,
            'ordered': line.ordered.milli,
            'received': line.received.milli,
            'unit': line.ordered.unit.wire,
            'cost': line.unitCost.minor,
            'tax': line.taxRateBp,
            'sort': sort++,
          },
        );
      }

      return AdminResult.done(id);
    });

    if (!written.succeeded) {
      return AdminResult.refused(written.refusal!);
    }
    return AdminResult.done((await byId(written.value!))!);
  }

  Future<int> _insert(
    TxSession tx,
    PurchaseOrder order,
    PurchaseTotals totals,
    PosStaff by,
  ) async {
    final reference = order.reference.trim().isEmpty
        ? await _nextReference(tx)
        : order.reference.trim();

    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO pos_purchase_orders (business_id, branch_id, '
        '  supplier_id, supplier_name, reference, status, currency, exponent, '
        '  subtotal_minor, tax_minor, total_minor, expected_at, notes, '
        '  created_by, updated_by) '
        "VALUES (@r, @b, @supplier, @name, @reference, 'draft', @currency, "
        '        @exponent, @subtotal, @tax, @total, @expected, @notes, @by, '
        '        @by) RETURNING id',
      ),
      parameters: {
        'r': businessId,
        'b': branchId,
        'supplier': order.supplierId,
        'name': order.supplierName ?? '',
        'reference': reference,
        'currency': order.currency,
        'exponent': order.exponent,
        'subtotal': totals.subtotal.minor,
        'tax': totals.tax.minor,
        'total': totals.total.minor,
        'expected': order.expectedAt,
        'notes': order.notes,
        'by': by.id == 0 ? null : by.id,
      },
    );
    return rows.first[0]! as int;
  }

  /// `PO-2026-000042`, counted per business per year.
  ///
  /// Claimed inside the caller's transaction, so a draft that fails to save
  /// does not burn a number — the same discipline `_nextInvoiceNumber` uses.
  Future<String> _nextReference(TxSession tx) async {
    final period = '${DateTime.now().toUtc().year}';
    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO pos_purchase_sequences (business_id, period, next_number) '
        'VALUES (@r, @p, 2) '
        'ON CONFLICT (business_id, period) DO UPDATE '
        '  SET next_number = pos_purchase_sequences.next_number + 1 '
        'RETURNING next_number - 1',
      ),
      parameters: {'r': businessId, 'p': period},
    );
    final number = rows.first[0]! as int;
    return 'PO-$period-${number.toString().padLeft(6, '0')}';
  }

  @override
  Future<AdminResult<PurchaseOrder>> setStatus(
    int orderId, {
    required PurchaseStatus status,
    required PosStaff by,
    DateTime? orderedAt,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    final written = await _db.runTx(config, (tx) async {
      // Locked, then asked — and asked of the row, not of the screen. The
      // pane's copy is whatever the order was when it last drew: Cancel shows
      // on a sent order, and a receipt booked from another till since then
      // does not redraw it. An UPDATE with no look at the current status let
      // that tap cancel an order whose goods were already in the kitchen.
      //
      // The rules are `PurchaseEngine`'s, not restated here: a repository that
      // enforced them itself would enforce them slightly differently from the
      // engine its tests describe. Migration 44 holds the same line in the
      // database, for writers that never come through this method.
      final order = await _locked(tx, orderId);
      if (order == null) {
        return const AdminResult<int>.refused(EditedElsewhere(0));
      }

      final decided = switch (status) {
        PurchaseStatus.sent => PurchaseEngine.send(
          order,
          at: (orderedAt ?? DateTime.now()).toUtc(),
        ),
        PurchaseStatus.cancelled => PurchaseEngine.cancel(order),
        // Only receiving writes these, from the lines; and nothing goes back
        // to draft.
        PurchaseStatus.draft ||
        PurchaseStatus.partiallyReceived ||
        PurchaseStatus.received => PurchaseResult.refused(
          StatusFollowsTheGoods(status),
        ),
      };
      if (!decided.succeeded) {
        return AdminResult<int>.refused(PurchaseRefused(decided.refusal!));
      }

      await tx.execute(
        Sql.named(
          'UPDATE pos_purchase_orders SET status = @status, '
          '  ordered_at = @orderedAt, updated_at = now(), updated_by = @by '
          'WHERE id = @id',
        ),
        parameters: {
          'id': orderId,
          'status': decided.order!.status.wire,
          'orderedAt': decided.order!.orderedAt,
          'by': by.id == 0 ? null : by.id,
        },
      );

      await tx.execute(
        Sql.named('''
        INSERT INTO pos_audit_events
          (business_id, branch_id, actor_user_id, actor_name, action,
           entity_type, entity_id, after_value)
        VALUES (@business, @branch, @by, @actor, @action, @type, @entity,
                @after::jsonb)
        '''),
        parameters: {
          'business': businessId,
          'branch': branchId,
          'by': by.id == 0 ? null : by.id,
          'actor': by.name,
          'action': AuditAction.purchaseOrderStatusChanged,
          'type': AuditAction.entityPurchaseOrder,
          'entity': '$orderId',
          'after': '{"status": "${status.wire}"}',
        },
      );

      return AdminResult.done(orderId);
    });

    if (!written.succeeded) {
      return AdminResult.refused(written.refusal!);
    }
    return AdminResult.done((await byId(orderId))!);
  }

  static String _notEditable(PurchaseStatus status) => switch (status) {
    PurchaseStatus.sent =>
      'That order has already gone to the supplier. Cancel it and write a new '
          'one, or record what arrives against it.',
    PurchaseStatus.partiallyReceived || PurchaseStatus.received =>
      'Goods have already arrived against that order, so it cannot be '
          'changed.',
    PurchaseStatus.cancelled => 'That order was cancelled.',
    PurchaseStatus.draft => '',
  };
}

/// What a terminal binds before it has an administrator credential.
class UnconfiguredPurchaseOrdersRepository implements PurchaseOrdersRepository {
  const UnconfiguredPurchaseOrdersRepository();

  @override
  Future<List<PurchaseOrder>> open() async => const [];

  @override
  Future<List<PurchaseOrder>> all({int limit = 100}) async => const [];

  @override
  Future<PurchaseOrder?> byId(int id) async => null;

  @override
  Future<AdminResult<PurchaseOrder>> saveDraft(
    PurchaseOrder order, {
    required PosStaff by,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<AdminResult<PurchaseOrder>> setStatus(
    int orderId, {
    required PurchaseStatus status,
    required PosStaff by,
    DateTime? orderedAt,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}
