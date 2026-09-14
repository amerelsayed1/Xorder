import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/branch_sales.dart';
import '../../domain/models/branch_sales_source.dart';
import '../../domain/models/tender_method.dart';
import 'pos_database.dart';

/// The branch view (§3a) where every terminal of the branch writes to this
/// database — the shared-LAN shape, and any offline install with more than one
/// till.
///
/// **One statement.** Terminals, sales, refunds and payments are aggregated
/// per terminal in CTEs and returned as one result, and the branch figures are
/// read off those rows by [BranchSales] rather than selected a second time.
/// Two statements would each be right and could still disagree — a sale
/// committed between them lands in one and not the other — and rule 1 is that
/// they cannot disagree.
///
/// Read-only; every table here is already `SELECT`-granted to the till role.
class PostgresBranchSalesRepository implements BranchSalesSource {
  const PostgresBranchSalesRepository({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    required this.branchId,
    this.currency = 'EGP',
    this.exponent = 2,
    this.clock = DateTime.now,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;
  final int branchId;
  final String currency;
  final int exponent;
  final DateTime Function() clock;

  /// Settled sales — the set the business-day close already totals
  /// (`postgres_business_day_repository.dart`), and the two must keep agreeing.
  /// See [settledStatuses].
  static final _settled = [for (final status in settledStatuses) status.wire];

  /// Payments by terminal and method, over a `sales` CTE that has `id`,
  /// `restaurant_id` and `terminal_id`.
  ///
  /// Public so the reports (`PostgresReportsRepository`) group tenders exactly
  /// as the branch view does. The label, the snapshotted cash flag and the
  /// unknown-kind rule below are three decisions, and a report that made any
  /// of them differently would show a tender bar that does not match the
  /// branch view's list for the same day.
  ///
  /// LEFT join onto the tender types for the KIND only: a payment carries its
  /// own label and cash flag, and a retired tender must not take its takings
  /// off the report with it. An unknown kind is read as `other`.
  static const paymentTotalsCte = '''
    payment_totals AS (
      SELECT s.terminal_id, p.tender_type_id, p.label,
             coalesce(tt.kind, 'other') AS kind, p.counts_as_cash,
             count(*) AS payments, sum(p.amount_minor)::bigint AS amount
      FROM pos_order_payments p
      JOIN sales s ON s.id = p.order_id
      LEFT JOIN pos_tender_types tt
        ON tt.restaurant_id = s.restaurant_id AND tt.id = p.tender_type_id
      GROUP BY s.terminal_id, p.tender_type_id, p.label, coalesce(tt.kind, 'other'),
               p.counts_as_cash
    )''';

  /// One [paymentTotalsCte] row, read from its six method columns starting at
  /// [at]: tender type, label, kind, cash flag, count, amount.
  static MethodTotal readMethod(
    List<Object?> row,
    int at,
    Money Function(Object?) money,
  ) => MethodTotal(
    tenderTypeId: row[at] as int?,
    label: row[at + 1] as String,
    kind: TenderKind.fromWire(row[at + 2] as String?),
    countsAsCash: row[at + 3] as bool? ?? false,
    count: row[at + 4] as int,
    amount: money(row[at + 5]),
  );

  /// The business day, by the date that names it. At most one row: the day is
  /// unique per branch and date.
  static const _dayCte = '''
    day AS (
      SELECT id, opened_at, closed_at FROM pos_business_days
      WHERE restaurant_id = @restaurant AND branch_id = @branch
        AND business_date = @date::date
    )''';

  /// Which business day a row belongs to.
  ///
  /// The stamped `business_day_id` when there is one; otherwise the day's own
  /// open-to-close window. The fallback is load-bearing, not a nicety: as of
  /// 2026-09-10 nothing stamps `business_day_id` on orders or refunds — the
  /// column and its foreign key exist, but the INSERTs in
  /// `postgres_orders_repository.dart` and `postgres_refunds_repository.dart`
  /// do not name it — so a query that trusted the column alone would show
  /// every terminal at zero. The window is the same answer by another road (a
  /// sale belongs to the trading day that was open when it happened), and the
  /// stamped id wins as soon as somebody writes it. Calendar date was
  /// rejected: it splits a night that runs past midnight across two days,
  /// which is exactly what §0 rule 5 forbids.
  ///
  /// A sale made while no day was open for the branch belongs to no day, and
  /// is in no day's branch view — the same answer the day close gives.
  static String _inDay(String alias) =>
      '''
      EXISTS (SELECT 1 FROM day d
              WHERE $alias.business_day_id = d.id
                 OR ($alias.business_day_id IS NULL
                     AND $alias.occurred_at >= d.opened_at
                     AND (d.closed_at IS NULL OR $alias.occurred_at < d.closed_at)))''';

  /// `::bigint` on every sum: sum() over bigint is numeric in PostgreSQL, which
  /// arrives as a string. Minor units always fit.
  static final _summarySql =
      '''
    WITH $_dayCte,
    terminals AS (
      SELECT id, name FROM pos_terminals
      WHERE restaurant_id = @restaurant AND branch_id = @branch
    ),
    sales AS (
      SELECT o.id, o.restaurant_id, o.terminal_id, o.total_minor, o.discount_minor
      FROM pos_orders o
      WHERE o.restaurant_id = @restaurant AND o.branch_id = @branch
        AND o.status = ANY(@statuses)
        AND ${_inDay('o')}
        AND (@until::timestamptz IS NULL OR o.occurred_at < @until::timestamptz)
    ),
    sale_totals AS (
      SELECT terminal_id, count(*) AS orders,
             sum(total_minor + discount_minor)::bigint AS gross,
             sum(discount_minor)::bigint AS discounts
      FROM sales GROUP BY terminal_id
    ),
    -- Rule 4: the terminal that ISSUED the refund, on the day it was issued —
    -- `r.terminal_id` and `r`'s own day, never the original sale's.
    refund_totals AS (
      SELECT r.terminal_id, count(*) AS refunds, sum(r.total_minor)::bigint AS refunded
      FROM pos_refunds r
      WHERE r.restaurant_id = @restaurant AND r.branch_id = @branch
        AND ${_inDay('r')}
        AND (@until::timestamptz IS NULL OR r.occurred_at < @until::timestamptz)
      GROUP BY r.terminal_id
    ),
    $paymentTotalsCte,
    -- Rule 2, both halves: every registered terminal even with no sales, AND
    -- any terminal that took money here without being registered to the
    -- branch. Listing only registered terminals would drop a stranger's
    -- takings from the branch total without a trace.
    everyone AS (
      SELECT id FROM terminals
      UNION SELECT terminal_id FROM sale_totals
      UNION SELECT terminal_id FROM refund_totals
    )
    SELECT e.id::text, t.name,
           coalesce(st.orders, 0), coalesce(st.gross, 0), coalesce(st.discounts, 0),
           coalesce(rt.refunds, 0), coalesce(rt.refunded, 0),
           pt.tender_type_id, pt.label, pt.kind, pt.counts_as_cash,
           pt.payments, pt.amount
    FROM everyone e
    LEFT JOIN terminals t      ON t.id = e.id
    LEFT JOIN sale_totals st   ON st.terminal_id = e.id
    LEFT JOIN refund_totals rt ON rt.terminal_id = e.id
    LEFT JOIN payment_totals pt ON pt.terminal_id = e.id
    ORDER BY t.name NULLS LAST, e.id, pt.label, pt.tender_type_id
    ''';

  Money _money(Object? minor) =>
      Money(minor is int ? minor : 0, currency: currency, exponent: exponent);

  /// [until], when given, keeps only what happened before that instant — the
  /// back office's Home compares today with the previous day cut at the same
  /// time since it opened (plan 19 §2.1), because a whole-day comparison reads
  /// as a collapse every morning.
  ///
  /// **The same statement with one more bound, not a second query.** Sales
  /// and refunds are both cut, and payments follow their sale, so a cut day
  /// is still a [BranchSales] whose branch figures are its rows. A separate
  /// "so far" query would be a second definition of a day's takings, and the
  /// two would drift the first time either changed. On the platform's source
  /// there is no cut: POS-BE-029 answers whole days only, which is why this
  /// is a parameter here and not on [BranchSalesSource].
  @override
  Future<BranchSalesReading> summary(
    DateTime businessDay, {
    DateTime? until,
  }) async {
    final rows = await _db.query(
      config,
      _summarySql,
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'date': businessDayWire(businessDay),
        'statuses': _settled,
        'until': until?.toUtc(),
      },
    );

    // Insertion-ordered, so the terminals keep the statement's ORDER BY. The
    // payment join fans each terminal out to one row per method; the terminal
    // figures repeat on each and are read once.
    final order = <String>[];
    final heads = <String, List<Object?>>{};
    final payments = <String, List<MethodTotal>>{};
    for (final raw in rows) {
      final row = raw.toList();
      final id = row[0] as String;
      if (!heads.containsKey(id)) {
        order.add(id);
        heads[id] = row;
        payments[id] = [];
      }
      if (row[8] != null) payments[id]!.add(readMethod(row, 7, _money));
    }

    final terminals = [
      for (final id in order)
        TerminalSales(
          terminalId: id,
          name: heads[id]![1] as String?,
          orders: heads[id]![2] as int,
          gross: _money(heads[id]![3]),
          discounts: _money(heads[id]![4]),
          refundCount: heads[id]![5] as int,
          refunds: _money(heads[id]![6]),
          payments: List.unmodifiable(payments[id]!),
        ),
    ];

    return BranchSalesReading(
      freshness: BranchSalesFreshness.live,
      sales: BranchSales(
        branchId: branchId,
        businessDay: businessDay,
        terminals: List.unmodifiable(terminals),
        currency: currency,
        exponent: exponent,
      ),
      asOf: clock(),
      // Every till's rows are already in this database; there is nothing a
      // shared-database branch view is waiting to hear about.
      unsyncedOnThisTill: 0,
    );
  }

  /// This till's settled sales for [businessDay] that the platform has not
  /// received — the per-till shape's banner (§3a).
  ///
  /// Quarantined rows count: the platform refused them, so they are no more in
  /// its totals than the ones still queued, and hiding them would make the
  /// banner say "all synced" about money that is not.
  Future<int> unsyncedSalesOn(
    DateTime businessDay, {
    required String terminalId,
  }) async {
    final rows = await _db.query(
      config,
      '''
      WITH $_dayCte
      SELECT count(*)
      FROM pos_outbox ob
      JOIN pos_orders o ON o.id = ob.order_id
      WHERE ob.restaurant_id = @restaurant AND ob.branch_id = @branch
        AND o.terminal_id::text = @terminal
        AND ob.delivered_at IS NULL
        AND o.status = ANY(@statuses)
        AND ${_inDay('o')}
      ''',
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'terminal': terminalId,
        'date': businessDayWire(businessDay),
        'statuses': _settled,
      },
    );
    return rows.first[0] as int;
  }
}
