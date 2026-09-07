import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/order_record.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// Reads settled orders back out of the branch database.
///
/// Read-only by construction: every statement here is a `SELECT`, and the till
/// role holds no more than that on these tables. Voiding an order from history
/// still goes through [OrdersRepository], which is the only thing that writes.
///
/// Scoped to one restaurant and one branch. A till shows the orders taken at the
/// counter it is standing on — the branch filter is not a convenience, it is
/// what stops a terminal in one shop listing another shop's takings.
class PostgresOrderHistoryRepository implements OrderHistoryRepository {
  const PostgresOrderHistoryRepository({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    required this.branchId,
    this.currency = 'EGP',
    this.exponent = 2,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;
  final int branchId;
  final String currency;
  final int exponent;

  /// Order rows carry their own currency, and a branch that changed currency
  /// mid-life would otherwise have its history re-denominated on screen.
  Money _rowMoney(Object? minor, Object? rowCurrency, Object? rowExponent) =>
      Money(
        minor is int ? minor : 0,
        currency: rowCurrency is String ? rowCurrency : currency,
        exponent: rowExponent is int ? rowExponent : exponent,
      );

  static const _orderColumns = '''
        o.id, o.client_transaction_id, o.invoice_number, o.status, o.order_type,
        o.occurred_at, o.subtotal_minor, o.discount_minor, o.service_minor,
        o.vat_minor, o.total_minor, o.currency, o.exponent,
        o.table_label, o.guest_count, o.voided_at, o.void_note,
        served.name, voider.name, reason.name_en, reason.name_ar,
        o.served_by''';

  /// The joins [_orderColumns] needs.
  ///
  /// All `LEFT`: an order whose seller has been deleted, or whose void reason
  /// predates the reason table, must still appear. An `INNER` join here would
  /// make orders disappear from history as staff leave, which is the failure
  /// mode nobody notices until an audit.
  static const _orderJoins = '''
        LEFT JOIN pos_staff       AS served ON served.id = o.served_by
        LEFT JOIN pos_staff       AS voider ON voider.id = o.voided_by
        LEFT JOIN pos_reason_codes AS reason ON reason.id = o.void_reason_id''';

  OrderRecord _record(List<Object?> row) {
    final currencyCode = row[11];
    final rowExponent = row[12];
    Money money(Object? minor) => _rowMoney(minor, currencyCode, rowExponent);

    return OrderRecord(
      id: row[0] as int,
      clientTransactionId: '${row[1]}',
      invoiceNumber: row[2] as String,
      // An unreadable status is shown as what the row already proves: money was
      // written against it. Refusing to build the record would hide the order
      // entirely, and an order missing from history is worse than one whose
      // state a newer build understands better.
      status: OrderStatus.fromWire(row[3] as String) ?? OrderStatus.paid,
      // A wire value this build does not know is shown as the type that needs
      // no table — the alternative is dropping the order out of history over a
      // label.
      orderType: OrderType.fromWire(row[4] as String) ?? OrderType.takeaway,
      occurredAt: (row[5] as DateTime).toLocal(),
      subtotal: money(row[6]),
      discount: money(row[7]),
      service: money(row[8]),
      vat: money(row[9]),
      total: money(row[10]),
      tableLabel: row[13] as String?,
      guestCount: row[14] as int?,
      voidedAt: (row[15] as DateTime?)?.toLocal(),
      voidNote: row[16] as String?,
      servedByName: row[17] as String?,
      voidedByName: row[18] as String?,
      voidReason: row[19] as String?,
      voidReasonAr: row[20] as String?,
      servedByStaffId: row[21] as int?,
    );
  }

  @override
  Future<List<OrderRecord>> search(OrderHistoryQuery query) async {
    final where = <String>[
      'o.restaurant_id = @restaurant',
      'o.branch_id = @branch',
    ];
    final parameters = <String, Object?>{
      'restaurant': restaurantId,
      'branch': branchId,
      'limit': query.limit,
    };

    if (query.from != null) {
      where.add('o.occurred_at >= @from');
      parameters['from'] = query.from!.toUtc();
    }
    if (query.to != null) {
      where.add('o.occurred_at < @to');
      parameters['to'] = query.to!.toUtc();
    }
    if (query.statuses.isNotEmpty) {
      where.add('o.status = ANY(@statuses)');
      parameters['statuses'] = query.statuses.map((s) => s.wire).toList();
    }
    if (query.orderTypes.isNotEmpty) {
      where.add('o.order_type = ANY(@types)');
      parameters['types'] = query.orderTypes.map((t) => t.wire).toList();
    }
    if (query.servedByStaffId != null) {
      where.add('o.served_by = @served');
      parameters['served'] = query.servedByStaffId;
    }

    final search = query.search?.trim();
    if (search != null && search.isNotEmpty) {
      // Anywhere in the string, not a prefix: what somebody reads off a receipt
      // is the tail of the number, and a prefix match would fail on exactly the
      // input they have. It costs the index — accepted, because the rows this
      // scans are one branch's orders inside a date window, and the alternative
      // is a search box that does not find what the customer is holding.
      where.add(
        '(o.invoice_number ILIKE @search OR o.table_label ILIKE @search)',
      );
      parameters['search'] = '%$search%';
    }

    final rows = await _db.query(
      config,
      'SELECT $_orderColumns FROM pos_orders AS o $_orderJoins '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY o.occurred_at DESC, o.id DESC LIMIT @limit',
      parameters: parameters,
    );

    return rows.map((row) => _record(row.toList())).toList(growable: false);
  }

  @override
  Future<OrderRecord?> byInvoiceNumber(String invoiceNumber) async {
    final rows = await _db.query(
      config,
      'SELECT $_orderColumns FROM pos_orders AS o $_orderJoins '
      'WHERE o.restaurant_id = @restaurant AND o.branch_id = @branch '
      '  AND o.invoice_number = @invoice',
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'invoice': invoiceNumber.trim(),
      },
    );
    if (rows.isEmpty) return null;
    return _record(rows.first.toList());
  }

  @override
  Future<OrderRecordDetail?> detail(int orderId) async {
    final orderRows = await _db.query(
      config,
      'SELECT $_orderColumns FROM pos_orders AS o $_orderJoins '
      'WHERE o.id = @id AND o.restaurant_id = @restaurant '
      '  AND o.branch_id = @branch',
      parameters: {
        'id': orderId,
        'restaurant': restaurantId,
        'branch': branchId,
      },
    );
    if (orderRows.isEmpty) return null;
    final order = _record(orderRows.first.toList());
    // Everything hanging off the order is denominated in the order's currency,
    // not the terminal's. They are the same today; they would not be for a
    // branch that changed currency, and a receipt must reprint as it was
    // issued.
    Money money(Object? minor) => Money(
      minor is int ? minor : 0,
      currency: order.total.currency,
      exponent: order.total.exponent,
    );

    final lineRows = await _db.query(
      config,
      'SELECT l.id, l.line_key, l.name_snapshot, l.quantity, '
      '       l.unit_price_minor, l.line_total_minor, l.modifier_summary, '
      '       l.note, l.menu_item_id, l.refunded_quantity, l.voided_at, '
      '       voider.name '
      'FROM pos_order_lines AS l '
      'LEFT JOIN pos_staff AS voider ON voider.id = l.voided_by '
      'WHERE l.order_id = @order ORDER BY l.id',
      parameters: {'order': orderId},
    );

    final paymentRows = await _db.query(
      config,
      'SELECT label, amount_minor, tender_type_id, reference, occurred_at '
      'FROM pos_order_payments WHERE order_id = @order ORDER BY id',
      parameters: {'order': orderId},
    );

    final discountRows = await _db.query(
      config,
      'SELECT d.name_snapshot, d.amount_minor, l.line_key, '
      '       applier.name, approver.name, d.applied_at '
      'FROM pos_order_discounts AS d '
      'LEFT JOIN pos_order_lines AS l ON l.id = d.order_line_id '
      'LEFT JOIN pos_staff AS applier ON applier.id = d.applied_by '
      'LEFT JOIN pos_staff AS approver ON approver.id = d.approved_by_id '
      'WHERE d.order_id = @order ORDER BY d.id',
      parameters: {'order': orderId},
    );

    return OrderRecordDetail(
      order: order,
      lines: lineRows.map((raw) {
        final row = raw.toList();
        return OrderRecordLine(
          id: row[0] as int,
          lineKey: row[1] as String,
          name: row[2] as String,
          quantity: row[3] as int,
          unitPrice: money(row[4]),
          lineTotal: money(row[5]),
          modifierSummary: row[6] as String?,
          note: row[7] as String?,
          menuItemId: row[8] as int?,
          refundedQuantity: row[9] as int? ?? 0,
          voidedAt: (row[10] as DateTime?)?.toLocal(),
          voidedByName: row[11] as String?,
        );
      }).toList(growable: false),
      payments: paymentRows.map((raw) {
        final row = raw.toList();
        return OrderRecordPayment(
          label: row[0] as String,
          amount: money(row[1]),
          tenderTypeId: row[2] as int?,
          reference: row[3] as String?,
          occurredAt: (row[4] as DateTime?)?.toLocal(),
        );
      }).toList(growable: false),
      discounts: discountRows.map((raw) {
        final row = raw.toList();
        return OrderRecordDiscount(
          name: row[0] as String,
          amount: money(row[1]),
          lineKey: row[2] as String?,
          appliedByName: row[3] as String?,
          approvedByName: row[4] as String?,
          appliedAt: (row[5] as DateTime?)?.toLocal(),
        );
      }).toList(growable: false),
    );
  }
}

/// What a terminal with no branch database answers with.
///
/// Empty, not an error. A till mid-setup has no history because it has made no
/// sales, and that is a true statement rather than a failure to report.
class UnconfiguredOrderHistoryRepository implements OrderHistoryRepository {
  const UnconfiguredOrderHistoryRepository();

  @override
  Future<List<OrderRecord>> search(OrderHistoryQuery query) async => const [];

  @override
  Future<OrderRecordDetail?> detail(int orderId) async => null;

  @override
  Future<OrderRecord?> byInvoiceNumber(String invoiceNumber) async => null;
}
