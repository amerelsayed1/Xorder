import 'package:postgres/postgres.dart' show Result, Sql;

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/branch_sales.dart';
import '../../domain/models/finance_report.dart';
import '../../domain/models/order_record.dart';
import '../../domain/models/profit_report.dart';
import '../../domain/models/sales_report.dart';
import '../../domain/models/tax.dart';
import '../../domain/models/tender_method.dart';
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
  ///
  /// [columns] replaces the select list; the default is the sales cells'.
  /// The WHERE is the same whatever is selected, which is the point: the
  /// taxes' refunds (BO-9) are the refunds the refunds tile counts.
  ({String sql, Map<String, Object?> parameters}) _refunds(
    ReportFilter filter, {
    String? columns,
  }) {
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
          'SELECT '
          '${columns ?? 'r.terminal_id, r.total_minor, ${_filed('r')} AS filed'} '
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
    int? limit = 5,
  }) async {
    if (limit != null && limit < 1) {
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
       ${limit == null ? '' : 'LIMIT @limit'}
      ''',
      // No LIMIT at all for every product, rather than `LIMIT NULL`: the
      // same in PostgreSQL, but a null parameter has no type for the driver
      // to send, and "unknown" beside LIMIT is a planner's guess.
      parameters: {...sold.parameters, 'limit': ?limit},
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

  @override
  Future<ProfitReport> profit(ReportFilter filter) {
    final sold = _sales(filter, 'o.id');

    // Revenue per (order, item), as `topProducts` counts it: kept units at the
    // price they were sold at, a voided line out. The grouping key is the same
    // too — a line with no menu item (an open charge, a combo) is grouped by
    // its name, so two different open charges are not one anonymous row.
    //
    // Cost per (order, item), off the stock ledger. Three rules, all of them
    // in the WHERE and each one the library comment of [ProfitReport] argues:
    //
    //  * `kind = 'sale'` — receipts, waste and counts are not the cost of a
    //    sale, and they would be if this read the ledger whole.
    //  * `unit_cost_minor > 0` — a sale at a carrying cost of zero is "never
    //    bought", not "free". It stays out, so its revenue is uncosted.
    //  * the sale's own orders, by the same `sales` CTE the revenue uses — the
    //    cost is of exactly the sales the revenue is of, never a neighbouring
    //    day's.
    //
    // Revenue without tax. Where prices contain tax (`@inclusive`) each line is
    // scaled by its ORDER's net-to-gross ratio from `pos_order_taxes` —
    // sum(base) / sum(base + amount) — because a line records no tax of its
    // own. Exact for an order at one rate, an estimate for a mixed one; an
    // order with no tax rows is left whole. Half-up, in integer arithmetic, as
    // the cost below: the numerator is never negative.
    //
    // Per-movement rounding, half-up, exactly `Quantity.costAt`: the numerator
    // is positive (a sale issues, so its quantity is negative and is negated),
    // where integer division floors, so `+ 500` before `/ 1000` is half-up.
    // Summed after rounding, never rounded after summing, so the figure is the
    // sum of the movements an auditor can read.
    //
    // One LEFT JOIN: every item with revenue arrives, and a null cost is how
    // "not costed" reaches Dart. HAVING keeps an item every unit of which came
    // back only if its cost was spent — a refunded plate is a loss, and
    // dropping the row would hide it.
    final rowsSql =
        '''
      WITH sales AS (${sold.sql}),
      kept AS (
        SELECT l.order_id, l.menu_item_id,
               CASE WHEN l.menu_item_id IS NULL THEN l.name_snapshot END
                 AS open_name,
               (array_agg(l.name_snapshot ORDER BY l.id DESC))[1] AS name,
               sum(l.quantity - l.refunded_quantity)::bigint AS kept,
               sum((l.quantity - l.refunded_quantity) * l.unit_price_minor)
                 ::bigint AS amount
          FROM pos_order_lines AS l
          JOIN sales AS s ON s.id = l.order_id
         WHERE l.voided_at IS NULL
         GROUP BY l.order_id, l.menu_item_id,
                  CASE WHEN l.menu_item_id IS NULL THEN l.name_snapshot END
      ),
      taxed AS (
        SELECT t.order_id,
               sum(t.base_minor)::bigint AS net,
               sum(t.base_minor + t.amount_minor)::bigint AS gross
          FROM pos_order_taxes AS t
          JOIN sales AS s ON s.id = t.order_id
         GROUP BY t.order_id
      ),
      priced AS (
        SELECT k.*,
               CASE WHEN @inclusive::boolean AND x.gross > 0
                    THEN (k.amount * x.net * 2 + x.gross) / (x.gross * 2)
                    ELSE k.amount END AS net_amount
          FROM kept AS k
          LEFT JOIN taxed AS x ON x.order_id = k.order_id
      ),
      issued AS (
        SELECT m.order_id, m.product_id,
               sum(((-m.quantity_milli * m.unit_cost_minor) + 500) / 1000)
                 ::bigint AS cost
          FROM pos_stock_movements AS m
          JOIN sales AS s ON s.id = m.order_id
         WHERE m.kind = 'sale'
           AND m.quantity_milli < 0
           AND m.unit_cost_minor > 0
         GROUP BY m.order_id, m.product_id
      )
      SELECT k.menu_item_id,
             (array_agg(k.name ORDER BY k.order_id DESC))[1] AS name,
             sum(k.kept)::bigint AS kept,
             sum(k.net_amount)::bigint AS amount,
             coalesce(sum(k.net_amount) FILTER (WHERE i.cost IS NOT NULL), 0)
               ::bigint AS costed_amount,
             sum(i.cost)::bigint AS cost
        FROM priced AS k
        LEFT JOIN issued AS i
               ON i.order_id = k.order_id AND i.product_id = k.menu_item_id
       GROUP BY k.menu_item_id, k.open_name
      HAVING sum(k.kept) > 0 OR sum(i.cost) IS NOT NULL
      ''';

    // One snapshot, for the reason `sales` takes one: the revenue and the cost
    // are two reads of a ledger that is being written to while the report is
    // open, and a sale committed between them would be in one and not the
    // other.
    return _db.runTx(config, (tx) async {
      await tx.execute(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY',
      );
      // The mode first: whether the lines' prices contain tax decides the
      // arithmetic of the revenue, not only the note under it. Today's setting,
      // not a snapshot — orders do not record the mode they were taxed in, so a
      // restaurant that switched has its earlier orders read by the new one.
      //
      // Read from where the till prices from: `pos_money_config`'s payload,
      // the path `MoneyConfigCodec` writes and the Taxes pane saves to.
      // `pos_restaurants.tax_mode` is only ever its migration default, so
      // reading it alone called every inclusive restaurant exclusive.
      final mode = await tx.execute(
        Sql.named(
          "SELECT COALESCE(m.payload ->> 'tax_mode', r.tax_mode) "
          '  FROM pos_restaurants r '
          '  LEFT JOIN pos_money_config m ON m.restaurant_id = r.id '
          ' WHERE r.id = @r',
        ),
        parameters: {'r': restaurantId},
      );
      final inclusive = mode.isNotEmpty && mode.first[0] == 'inclusive';
      final rows = await tx.execute(
        Sql.named(rowsSql),
        parameters: {...sold.parameters, 'inclusive': inclusive},
      );

      return ProfitReport(
        filter: filter,
        currency: currency,
        exponent: exponent,
        pricesIncludeTax: inclusive,
        products: ProfitReport.ranked([
          for (final raw in rows)
            ProductProfit(
              menuItemId: raw[0] as int?,
              name: raw[1]! as String,
              quantity: raw[2]! as int,
              revenue: _money(raw[3]),
              costedRevenue: _money(raw[4]),
              cost: raw[5] == null ? null : _money(raw[5]),
            ),
        ]),
      );
    });
  }

  @override
  Future<StaffSalesReport> staffSales(ReportFilter filter) async {
    final sold = _sales(
      filter,
      'o.served_by, o.total_minor, o.discount_minor',
    );
    // `_refunds`' own WHERE, so a person's refunds are exactly the refunds
    // the refunds tile counts, split by who issued them.
    final refunded = _refunds(filter, columns: 'r.refunded_by, r.total_minor');

    // The voids: the drill-down's WHERE again, on the voided orders the
    // sales list shows under its Voided status — filed by the same trading
    // day. The status is its own parameter, not `filterFor`'s `statuses`:
    // that name is already bound to the settled set in [sold], and one name
    // with two values in one statement is the collision `_refunds` warns of.
    // The person filter reads `voided_by` here for the reason it reads
    // `refunded_by` there.
    final voidQuery = PostgresOrderHistoryRepository.filterFor(
      OrderHistoryQuery(
        from: filter.from,
        to: filter.to,
        orderTypes: filter.orderTypes,
        terminalId: filter.terminalId,
      ),
      restaurantId: restaurantId,
      branchId: branchId,
    );
    final voidWhere = [...voidQuery.where, 'o.status = @voidedStatus'];
    final voidParameters = <String, Object?>{
      ...voidQuery.parameters,
      'voidedStatus': OrderStatus.voided.wire,
    };
    final by = filter.servedByStaffId;
    if (by != null) {
      voidWhere.add('o.voided_by = @served');
      voidParameters['served'] = by;
    }

    // One statement, so one snapshot: the three CTEs cannot see different
    // moments of the till. `people` is a UNION, which counts NULL once — the
    // sales that record nobody are one row, not dropped and not repeated.
    // `IS NOT DISTINCT FROM` on the joins for the same NULL.
    final rows = await _db.query(
      config,
      '''
      WITH sales AS (${sold.sql}),
      refunds AS (${refunded.sql}),
      voids AS (
        SELECT o.voided_by FROM pos_orders AS o
        ${PostgresOrderHistoryRepository.tradingDayJoin('o')}
        WHERE ${voidWhere.join(' AND ')}
      ),
      sold AS (
        SELECT served_by AS staff_id, count(*) AS orders,
               sum(total_minor + discount_minor)::bigint AS gross,
               sum(discount_minor)::bigint AS discounts
          FROM sales GROUP BY served_by
      ),
      given AS (
        SELECT refunded_by AS staff_id, count(*) AS refunds,
               sum(total_minor)::bigint AS refunded
          FROM refunds GROUP BY refunded_by
      ),
      voided AS (
        SELECT voided_by AS staff_id, count(*) AS voids
          FROM voids GROUP BY voided_by
      ),
      people AS (
        SELECT staff_id FROM sold
        UNION SELECT staff_id FROM given
        UNION SELECT staff_id FROM voided
      )
      SELECT p.staff_id, st.name,
             coalesce(s.orders, 0), coalesce(s.gross, 0),
             coalesce(s.discounts, 0),
             coalesce(g.refunds, 0), coalesce(g.refunded, 0),
             coalesce(v.voids, 0)
        FROM people AS p
        LEFT JOIN sold AS s ON s.staff_id IS NOT DISTINCT FROM p.staff_id
        LEFT JOIN given AS g ON g.staff_id IS NOT DISTINCT FROM p.staff_id
        LEFT JOIN voided AS v ON v.staff_id IS NOT DISTINCT FROM p.staff_id
        LEFT JOIN pos_staff AS st ON st.id = p.staff_id
       ORDER BY coalesce(s.gross, 0) - coalesce(s.discounts, 0)
                  - coalesce(g.refunded, 0) DESC,
                st.name NULLS LAST, p.staff_id NULLS LAST
      ''',
      parameters: {
        ...sold.parameters,
        ...refunded.parameters,
        ...voidParameters,
      },
    );

    return StaffSalesReport(
      filter: filter,
      people: List.unmodifiable([
        for (final raw in rows)
          StaffSales(
            staffId: raw[0] as int?,
            name: raw[1] as String?,
            orders: raw[2]! as int,
            gross: _money(raw[3]),
            discounts: _money(raw[4]),
            refundCount: raw[5]! as int,
            refunds: _money(raw[6]),
            voids: raw[7]! as int,
          ),
      ]),
      currency: currency,
      exponent: exponent,
    );
  }

  @override
  Future<TaxReport> taxes(ReportFilter filter) {
    final sold = _sales(filter, 'o.id');
    // `sold` is `_refunds`' own join to the sale, there for the order type.
    // The sale's `vat_minor` is what the ETA credit note scales by, so the
    // split below is the one a credit note would file.
    final refunded = _refunds(
      filter,
      columns: 'r.id, r.order_id, r.vat_minor, sold.vat_minor AS sale_vat',
    );

    // Charged: the sales' own rows, summed per rate and name — the key the
    // table is unique on, so a rate renamed mid-range is two rows, as the
    // receipts were.
    final chargedSql =
        '''
      WITH sales AS (${sold.sql})
      SELECT t.rate_bp, t.name_snapshot, count(*),
             sum(t.base_minor)::bigint, sum(t.amount_minor)::bigint
        FROM pos_order_taxes AS t
        JOIN sales AS s ON s.id = t.order_id
       GROUP BY t.rate_bp, t.name_snapshot
      ''';

    // Refunded: each refund with its sale's rates, in `id` order — the order
    // `TaxEngine.refundShares` is given by the ETA filer too. LEFT JOIN so a
    // refund whose sale has no rate still arrives, and is counted as such
    // rather than lost.
    final refundedSql =
        '''
      WITH refunds AS (${refunded.sql})
      SELECT f.id, f.vat_minor, f.sale_vat, t.rate_bp, t.name_snapshot,
             t.amount_minor
        FROM refunds AS f
        LEFT JOIN pos_order_taxes AS t ON t.order_id = f.order_id
       WHERE f.vat_minor > 0
       ORDER BY f.id, t.id
      ''';

    // One snapshot, for the reason `sales` takes one: a refund committed
    // between the two reads would otherwise be in the refunded column of a
    // report whose charged column never saw its sale.
    return _db.runTx(config, (tx) async {
      await tx.execute(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY',
      );
      final charged = await tx.execute(
        Sql.named(chargedSql),
        parameters: sold.parameters,
      );
      final refunds = await tx.execute(
        Sql.named(refundedSql),
        parameters: refunded.parameters,
      );
      return _assembleTaxes(filter, charged, refunds);
    });
  }

  TaxReport _assembleTaxes(ReportFilter filter, Result charged, Result refunds) {
    final byRate = <(int, String), _TaxTally>{};
    for (final raw in charged) {
      final row = raw.toList();
      byRate[(row[0]! as int, row[1]! as String)] = _TaxTally()
        ..orders = row[2]! as int
        ..base = row[3]! as int
        ..charged = row[4]! as int;
    }

    // Rows arrive grouped by refund. Each group is split once, whole — the
    // split is of one refund's VAT, and splitting row by row would round each
    // rate against a different remainder.
    var unattributed = 0;
    final groups = <int, List<List<Object?>>>{};
    for (final raw in refunds) {
      final row = raw.toList();
      groups.putIfAbsent(row[0]! as int, () => []).add(row);
    }
    for (final rows in groups.values) {
      final vat = rows.first[1]! as int;
      if (rows.first[3] == null) {
        unattributed += vat;
        continue;
      }
      final shares = TaxEngine.refundShares(
        saleAmounts: [for (final row in rows) row[5]! as int],
        saleVat: rows.first[2]! as int,
        refundVat: vat,
      );
      for (final (i, row) in rows.indexed) {
        byRate
                .putIfAbsent((row[3]! as int, row[4]! as String), _TaxTally.new)
                .refunded +=
            shares[i];
      }
    }

    final keys = byRate.keys.toList()
      ..sort((a, b) {
        final byBp = b.$1.compareTo(a.$1);
        return byBp != 0 ? byBp : a.$2.compareTo(b.$2);
      });
    return TaxReport(
      filter: filter,
      rates: List.unmodifiable([
        for (final key in keys)
          TaxCollected(
            rateBp: key.$1,
            name: key.$2,
            orders: byRate[key]!.orders,
            base: _money(byRate[key]!.base),
            charged: _money(byRate[key]!.charged),
            refunded: _money(byRate[key]!.refunded),
          ),
      ]),
      unattributedRefunds: _money(unattributed),
      currency: currency,
      exponent: exponent,
    );
  }

  @override
  Future<PaymentLedger> payments(
    ReportFilter filter, {
    int limit = 500,
  }) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'A ledger lists something.');
    }
    final paid = _sales(
      filter,
      'o.id, o.restaurant_id, o.terminal_id, o.invoice_number',
    );

    // The tender kind by the branch view's own rule (`paymentTotalsCte`):
    // the payment's cash flag, and the tender type's kind or `other`. A row
    // here and a slice of the bar are then the same money in the same bucket.
    // One more than asked, to know whether there were more.
    final rows = await _db.query(
      config,
      '''
      WITH sales AS (${paid.sql})
      SELECT p.id, s.id, s.invoice_number, p.occurred_at, s.terminal_id::text,
             term.name, p.tender_type_id, p.label,
             coalesce(tt.kind, 'other'), p.counts_as_cash, p.amount_minor
        FROM pos_order_payments AS p
        JOIN sales AS s ON s.id = p.order_id
        LEFT JOIN pos_tender_types AS tt
          ON tt.restaurant_id = s.restaurant_id AND tt.id = p.tender_type_id
        LEFT JOIN pos_terminals AS term ON term.id = s.terminal_id
       ORDER BY p.occurred_at DESC, p.id DESC
       LIMIT @limit
      ''',
      parameters: {...paid.parameters, 'limit': limit + 1},
    );

    final entries = [
      for (final raw in rows.take(limit))
        PaymentEntry(
          paymentId: raw[0]! as int,
          orderId: raw[1]! as int,
          invoiceNumber: raw[2]! as String,
          occurredAt: (raw[3]! as DateTime).toLocal(),
          terminalId: raw[4]! as String,
          terminalName: raw[5] as String?,
          tenderTypeId: raw[6] as int?,
          label: raw[7]! as String,
          kind: TenderKind.fromWire(raw[8] as String?),
          countsAsCash: raw[9] as bool? ?? false,
          amount: _money(raw[10]),
        ),
    ];
    return PaymentLedger(
      filter: filter,
      entries: List.unmodifiable(entries),
      truncated: rows.length > limit,
      currency: currency,
      exponent: exponent,
    );
  }
}

/// One rate's figures while they are being summed, in minor units.
class _TaxTally {
  int orders = 0;
  int base = 0;
  int charged = 0;
  int refunded = 0;
}

/// One cell's figures while they are being summed, in minor units.
class _Tally {
  int orders = 0;
  int gross = 0;
  int discounts = 0;
  int refundCount = 0;
  int refunds = 0;
}
