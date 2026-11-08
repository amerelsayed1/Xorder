import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/branch_sales.dart' show settledStatuses;
import '../../domain/models/customer.dart';
import '../../domain/models/customer_summary.dart';
import '../../domain/repositories/repositories.dart';
import '../sql/sql.dart';

/// The directory with what each customer has bought (`pos_customers`,
/// `pos_orders.customer_id`).
///
/// Read through the till's own credential, as the reports are: it holds SELECT
/// on both tables and nothing more is needed to look.
class PostgresCustomerDirectoryRepository
    implements CustomerDirectoryRepository {
  const PostgresCustomerDirectoryRepository({
    required SqlDatabase database,
    required this.config,
    required this.businessId,
    required this.branchId,
    this.currency = 'EGP',
    this.exponent = 2,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final int businessId;
  final int branchId;
  final String currency;
  final int exponent;

  static final _settled = [for (final status in settledStatuses) status.wire];

  Money _money(Object? minor) =>
      Money(minor is int ? minor : 0, currency: currency, exponent: exponent);

  @override
  Future<List<CustomerSummary>> list({String query = '', int limit = 100}) async {
    final trimmed = query.trim();
    // The counter's own search, so a name or a number finds the same person
    // here as it does at the till: a name fragment, or the digits of a phone
    // number — normalised, so Arabic-Indic digits match.
    final digits = PosCustomer.normalisePhone(trimmed);

    final rows = await _db.query(
      config,
      '''
      SELECT c.id, c.platform_id, c.name, c.phone, c.email, c.address, c.note,
             coalesce(s.orders, 0), coalesce(s.spent, 0),
             coalesce(s.refunded, 0), s.last_at
        FROM pos_customers AS c
        LEFT JOIN LATERAL (
          SELECT count(*)::int AS orders,
                 sum(o.total_minor)::bigint AS spent,
                 max(o.occurred_at) AS last_at,
                 coalesce(sum(
                   (SELECT coalesce(sum(r.total_minor), 0)
                      FROM pos_refunds AS r WHERE r.order_id = o.id)
                 ), 0)::bigint AS refunded
            FROM pos_orders AS o
           WHERE o.customer_id = c.id
             AND o.branch_id = @branch
             AND o.status = ANY(@settled::text[])
        ) AS s ON true
       WHERE c.business_id = @r
         ${trimmed.isEmpty ? '' : 'AND (lower(c.name) LIKE @name '
              '${digits.isEmpty ? '' : 'OR c.phone LIKE @phone'})'}
       ORDER BY s.last_at DESC NULLS LAST, lower(c.name), c.id
       LIMIT @limit
      ''',
      parameters: {
        'r': businessId,
        'branch': branchId,
        'settled': _settled,
        'limit': limit,
        if (trimmed.isNotEmpty) 'name': '%${trimmed.toLowerCase()}%',
        if (trimmed.isNotEmpty && digits.isNotEmpty) 'phone': '%$digits%',
      },
    );

    return [
      for (final raw in rows)
        () {
          final row = raw.toList();
          return CustomerSummary(
            customer: PosCustomer(
              id: row[0]! as int,
              platformId: row[1] as int?,
              name: row[2]! as String,
              phone: row[3]! as String,
              email: row[4] as String?,
              address: row[5] as String?,
              note: row[6] as String?,
            ),
            orders: row[7]! as int,
            spent: _money(row[8]),
            refunded: _money(row[9]),
            lastOrderAt: (row[10] as DateTime?)?.toLocal(),
          );
        }(),
    ];
  }

  @override
  Future<List<CustomerOrder>> recentOrders(
    int customerId, {
    int limit = 20,
  }) async {
    final rows = await _db.query(
      config,
      '''
      SELECT o.id, o.invoice_number, o.occurred_at, o.total_minor,
             coalesce((SELECT sum(r.total_minor) FROM pos_refunds AS r
                        WHERE r.order_id = o.id), 0)::bigint
        FROM pos_orders AS o
        JOIN pos_customers AS c ON c.id = o.customer_id
       WHERE o.customer_id = @customer
         AND c.business_id = @r
         AND o.branch_id = @branch
         AND o.status = ANY(@settled::text[])
       ORDER BY o.occurred_at DESC, o.id DESC
       LIMIT @limit
      ''',
      parameters: {
        'customer': customerId,
        'r': businessId,
        'branch': branchId,
        'settled': _settled,
        'limit': limit,
      },
    );

    return [
      for (final raw in rows)
        () {
          final row = raw.toList();
          return CustomerOrder(
            orderId: row[0]! as int,
            invoiceNumber: row[1] as String? ?? '',
            occurredAt: (row[2]! as DateTime).toLocal(),
            total: _money(row[3]),
            refunded: _money(row[4]),
          );
        }(),
    ];
  }
}

/// No database on this terminal: nobody on file.
class UnconfiguredCustomerDirectoryRepository
    implements CustomerDirectoryRepository {
  const UnconfiguredCustomerDirectoryRepository();

  @override
  Future<List<CustomerSummary>> list({String query = '', int limit = 100}) async =>
      const [];

  @override
  Future<List<CustomerOrder>> recentOrders(
    int customerId, {
    int limit = 20,
  }) async => const [];
}
