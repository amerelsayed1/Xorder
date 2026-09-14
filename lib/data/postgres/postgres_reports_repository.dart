import 'package:postgres/postgres.dart' show Result, Sql;

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/branch_sales.dart';
import '../../domain/models/sales_report.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';
import 'postgres_branch_sales_repository.dart';
import 'postgres_order_history_repository.dart';

/// Wave G's figures, over the rows every till at the branch already writes.
///
/// **Built on the two readers that exist, not beside them.** The sales are
/// `PostgresOrderHistoryRepository.filterFor` applied to the report's own
/// drill-down query, so a tile counts exactly what the sales list under it
/// lists; the tenders are grouped by the branch view's
/// `PostgresBranchSalesRepository.paymentTotalsCte`; the totals are read off
/// the terminal rows by the branch view's `TerminalRollup`. What this class
/// adds is only what neither has: a range instead of one day, and a day
/// column to spread it over.
///
/// **Filed by the sales list's rule, not the branch view's.** The branch view
/// counts only rows inside a business day. The list files a row no day covers
/// by its local calendar date instead — a restaurant that never opens a day
/// still sees its takings — and the drill-down is the list, so that rule wins
/// here. The two agree on every row a day covers, which since migrations
/// 35–36 is every row written while a day was open.
///
/// Read-only; every table here is already `SELECT`-granted to the till role.
class PostgresReportsRepository implements ReportsRepository {
  const PostgresReportsRepository({
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

  Money _money(Object? minor) =>
      Money(minor is int ? minor : 0, currency: currency, exponent: exponent);

  /// The range's dates, each with the instants of its local calendar day.
  ///
  /// The calendar half is for the row no business day covers. Its day is
  /// worked out here, in Dart, from the same local midnights the sales list
  /// compares against — not in SQL, which would need the terminal's zone by
  /// name and would file by the SERVER's zone if it were ever left off.
  static const _days = '''
    days AS (
      SELECT u.business_date, u.starts, u.ends
        FROM unnest(@dates::date[], @starts::timestamptz[], @ends::timestamptz[])
             AS u(business_date, starts, ends)
    )''';

  static Map<String, Object?> _dayParameters(ReportFilter filter) {
    final dates = filter.dates;
    String instant(DateTime at) => at.toUtc().toIso8601String();
    return {
      'dates': [for (final day in dates) businessDayWire(day)],
      'starts': [for (final day in dates) instant(day)],
      'ends': [
        for (final day in dates)
          instant(DateTime(day.year, day.month, day.day + 1)),
      ],
    };
  }

  /// The date the row [alias] is filed under: its trading day's, or — with no
  /// day covering it — the calendar day [_days] puts it in. Needs
  /// `tradingDayJoin` on [alias] and [_days] in the statement.
  static String _filed(String alias) =>
      '''
        coalesce(trading.business_date,
                 (SELECT d.business_date FROM days AS d
                   WHERE $alias.occurred_at >= d.starts
                     AND $alias.occurred_at < d.ends))''';

  /// The report's sales, as a SELECT of [columns] — the drill-down's WHERE,
  /// verbatim.
  ({String sql, Map<String, Object?> parameters}) _sales(
    ReportFilter filter,
    String columns,
  ) {
    final list = PostgresOrderHistoryRepository.filterFor(
      filter.historyQuery(),
      restaurantId: restaurantId,
      branchId: branchId,
    );
    return (
      sql:
          'SELECT $columns FROM pos_orders AS o '
          '${PostgresOrderHistoryRepository.tradingDayJoin('o')} '
          'WHERE ${list.where.join(' AND ')}',
      parameters: list.parameters,
    );
  }

  /// The report's refunds (§3a rule 4): by the terminal that ISSUED each one
  /// and the day it was issued in — `r`'s own columns, never the sale's. The
  /// sale is joined only for its order type.
  ///
  /// Its parameters share names with [_sales]'s on purpose — `terminal`,
  /// `served`, `types` and the range — and carry the same values, because
  /// both are read off one filter. Distinct names would let the two drift
  /// onto different values without anything noticing.
  ({String sql, Map<String, Object?> parameters}) _refunds(
    ReportFilter filter,
  ) {
    final range = PostgresOrderHistoryRepository.businessDateRange(
      from: filter.from,
      to: filter.to,
      alias: 'r',
    );
    final where = [
      'r.restaurant_id = @restaurant',
      'r.branch_id = @branch',
      ...range.where,
    ];
    final parameters = <String, Object?>{
      'restaurant': restaurantId,
      'branch': branchId,
      ...range.parameters,
    };
    final terminal = filter.terminalId;
    if (terminal != null) {
      where.add('r.terminal_id::text = @terminal');
      parameters['terminal'] = terminal;
    }
    final by = filter.servedByStaffId;
    if (by != null) {
      where.add('r.refunded_by = @served');
      parameters['served'] = by;
    }
    if (filter.orderTypes.isNotEmpty) {
      where.add('sold.order_type = ANY(@types)');
      parameters['types'] = [for (final type in filter.orderTypes) type.wire];
    }
    return (
      sql:
          'SELECT r.terminal_id, r.total_minor, ${_filed('r')} AS filed '
          'FROM pos_refunds AS r '
          'JOIN pos_orders AS sold ON sold.id = r.order_id '
          '${PostgresOrderHistoryRepository.tradingDayJoin('r')} '
          'WHERE ${where.join(' AND ')}',
      parameters: parameters,
    );
  }

  @override
  Future<SalesReport> sales(ReportFilter filter) {
    final sold = _sales(
      filter,
      'o.terminal_id, o.total_minor, o.discount_minor, ${_filed('o')} AS filed',
    );
    final refunded = _refunds(filter);

    // One cell per (date, terminal) that saw a sale or a refund. The tiles,
    // the trend and the terminal table are all sums of these cells, so none
    // can disagree with another. `::bigint` on every sum: sum() over bigint is
    // numeric in PostgreSQL, which arrives as a string.
    final cellsSql =
        '''
      WITH $_days,
      sales AS (${sold.sql}),
      refunds AS (${refunded.sql}),
      sale_cells AS (
        SELECT filed, terminal_id, count(*) AS orders,
               sum(total_minor + discount_minor)::bigint AS gross,
               sum(discount_minor)::bigint AS discounts
          FROM sales GROUP BY filed, terminal_id
      ),
      refund_cells AS (
        SELECT filed, terminal_id, count(*) AS refunds,
               sum(total_minor)::bigint AS refunded
          FROM refunds GROUP BY filed, terminal_id
      )
      SELECT coalesce(s.filed, r.filed),
             coalesce(s.terminal_id, r.terminal_id)::text,
             coalesce(s.orders, 0), coalesce(s.gross, 0),
             coalesce(s.discounts, 0),
             coalesce(r.refunds, 0), coalesce(r.refunded, 0)
        FROM sale_cells AS s
        FULL JOIN refund_cells AS r
          ON r.filed = s.filed AND r.terminal_id = s.terminal_id
      ''';

    final paid = _sales(filter, 'o.id, o.restaurant_id, o.terminal_id');
    final paymentsSql =
        '''
      WITH sales AS (${paid.sql}),
      ${PostgresBranchSalesRepository.paymentTotalsCte}
      SELECT terminal_id::text, tender_type_id, label, kind, counts_as_cash,
             payments, amount
        FROM payment_totals
       ORDER BY terminal_id, label, tender_type_id
      ''';

    final terminal = filter.terminalId;
    final terminalsSql =
        'SELECT id::text, name FROM pos_terminals '
        'WHERE restaurant_id = @restaurant AND branch_id = @branch '
        '${terminal == null ? '' : 'AND id::text = @terminal '}'
        'ORDER BY name NULLS LAST, id';

    // One snapshot for the three reads. REPEATABLE READ is what makes a sale
    // committed at another till between the first and the last either in all
    // three or in none — without it the tender bar could count a sale the
    // terminal table does not. READ ONLY because nothing here writes, and a
    // report that somebody later taught to would fail loudly.
    return _db.runTx(config, (tx) async {
      await tx.execute(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY',
      );
      final cells = await tx.execute(
        Sql.named(cellsSql),
        parameters: {
          ..._dayParameters(filter),
          ...sold.parameters,
          ...refunded.parameters,
        },
      );
      final payments = await tx.execute(
        Sql.named(paymentsSql),
        parameters: paid.parameters,
      );
      final registered = await tx.execute(
        Sql.named(terminalsSql),
        parameters: {
          'restaurant': restaurantId,
          'branch': branchId,
          'terminal': ?terminal,
        },
      );
      return _assemble(filter, cells, payments, registered);
    });
  }

  SalesReport _assemble(
    ReportFilter filter,
    Result cells,
    Result payments,
    Result registered,
  ) {
    // Insertion-ordered: registered terminals by name, as the statement sorted
    // them.
    final names = <String, String?>{
      for (final raw in registered) raw[0]! as String: raw[1] as String?,
    };
    final wanted = {for (final day in filter.dates) businessDayWire(day)};

    final byTerminal = <String, _Tally>{};
    final byDay = <String, _Tally>{};
    for (final raw in cells) {
      final row = raw.toList();
      final filed = row[0] as DateTime?;
      // Both would mean the filing rule and the range disagree — a row the
      // WHERE let in that no date of the range owns. Thrown rather than
      // skipped: skipping it would leave the terminal table and the trend
      // short by the same sale, and each would look right on its own.
      if (filed == null) {
        throw StateError('A row in this report is filed under no date.');
      }
      final day = businessDayWire(filed);
      if (!wanted.contains(day)) {
        throw StateError('A row in this report is filed under $day, outside it.');
      }
      for (final tally in [
        byTerminal.putIfAbsent(row[1]! as String, _Tally.new),
        byDay.putIfAbsent(day, _Tally.new),
      ]) {
        tally
          ..orders += row[2]! as int
          ..gross += row[3]! as int
          ..discounts += row[4]! as int
          ..refundCount += row[5]! as int
          ..refunds += row[6]! as int;
      }
    }

    final methods = <String, List<MethodTotal>>{};
    for (final raw in payments) {
      final row = raw.toList();
      methods
          .putIfAbsent(row[0]! as String, () => [])
          .add(PostgresBranchSalesRepository.readMethod(row, 1, _money));
    }

    // §3a rule 2, both halves: every registered terminal even with nothing,
    // and after them any terminal that took money here without being
    // registered to the branch. Dropping the second would leave the totals
    // short by a stranger's takings with nothing on screen to say so.
    final strangers =
        byTerminal.keys.where((id) => !names.containsKey(id)).toList()..sort();

    final terminals = [
      for (final id in [...names.keys, ...strangers])
        TerminalSales(
          terminalId: id,
          name: names[id],
          orders: byTerminal[id]?.orders ?? 0,
          gross: _money(byTerminal[id]?.gross ?? 0),
          discounts: _money(byTerminal[id]?.discounts ?? 0),
          refunds: _money(byTerminal[id]?.refunds ?? 0),
          refundCount: byTerminal[id]?.refundCount ?? 0,
          payments: List.unmodifiable(methods[id] ?? const <MethodTotal>[]),
        ),
    ];

    final days = [
      for (final date in filter.dates)
        ReportDay(
          date: date,
          orders: byDay[businessDayWire(date)]?.orders ?? 0,
          gross: _money(byDay[businessDayWire(date)]?.gross ?? 0),
          discounts: _money(byDay[businessDayWire(date)]?.discounts ?? 0),
          refunds: _money(byDay[businessDayWire(date)]?.refunds ?? 0),
          refundCount: byDay[businessDayWire(date)]?.refundCount ?? 0,
        ),
    ];

    return SalesReport(
      filter: filter,
      terminals: List.unmodifiable(terminals),
      days: List.unmodifiable(days),
      currency: currency,
      exponent: exponent,
    );
  }

  @override
  Future<List<ProductSales>> topProducts(
    ReportFilter filter, {
    required ProductRanking by,
    int limit = 5,
  }) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'A top list lists something.');
    }
    final sold = _sales(filter, 'o.id');
    final ranking = switch (by) {
      ProductRanking.quantity => 'kept DESC, amount DESC',
      ProductRanking.amount => 'amount DESC, kept DESC',
    };

    // Kept units at the price they were sold at — see [ProductSales]. A line
    // with no menu item (an open-price charge, a combo) is grouped by its name,
    // so two different open charges are not summed into one anonymous row.
    // HAVING drops a product every unit of which came back: it did not sell.
    final rows = await _db.query(
      config,
      '''
      WITH sales AS (${sold.sql})
      SELECT l.menu_item_id,
             (array_agg(l.name_snapshot ORDER BY l.id DESC))[1] AS name,
             sum(l.quantity - l.refunded_quantity)::bigint AS kept,
             sum((l.quantity - l.refunded_quantity) * l.unit_price_minor)::bigint
               AS amount
        FROM pos_order_lines AS l
        JOIN sales AS s ON s.id = l.order_id
       WHERE l.voided_at IS NULL
       GROUP BY l.menu_item_id,
                CASE WHEN l.menu_item_id IS NULL THEN l.name_snapshot END
      HAVING sum(l.quantity - l.refunded_quantity) > 0
       ORDER BY $ranking, name, l.menu_item_id
       LIMIT @limit
      ''',
      parameters: {...sold.parameters, 'limit': limit},
    );

    return [
      for (final raw in rows)
        ProductSales(
          menuItemId: raw[0] as int?,
          name: raw[1]! as String,
          quantity: raw[2]! as int,
          amount: _money(raw[3]),
        ),
    ];
  }
}

/// One cell's figures while they are being summed, in minor units.
class _Tally {
  int orders = 0;
  int gross = 0;
  int discounts = 0;
  int refundCount = 0;
  int refunds = 0;
}
