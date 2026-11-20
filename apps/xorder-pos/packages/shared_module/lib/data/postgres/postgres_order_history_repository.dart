import 'package:collection/collection.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/customer.dart' show PosCustomer;
import '../../domain/models/order_record.dart';
import '../../domain/models/refund.dart' show RefundKind;
import '../../domain/models/refund_history.dart';
import '../../domain/models/tax.dart' show TaxLine;
import '../../domain/models/ticket.dart';
import '../../domain/repositories/admin_repositories.dart' show AuditAction;
import '../../domain/repositories/repositories.dart';
import '../../domain/services/payment_status.dart';
import '../sql/sql.dart';
import '../sql/row_reads.dart';

/// Reads settled orders back out of the branch database.
///
/// Read-only by construction: every statement here is a `SELECT`, and the till
/// role holds no more than that on these tables. Voiding an order from history
/// still goes through [OrdersRepository], which is the only thing that writes.
///
/// Scoped to one business and one branch. A till shows the orders taken at the
/// counter it is standing on — the branch filter is not a convenience, it is
/// what stops a terminal in one shop listing another shop's takings.
///
/// Whose sales within the branch is NOT decided here: a query arrives already
/// narrowed by `HistoryScope`, in the provider every reader goes through. This
/// class has no idea who is asking, which is what lets the DB suite read it
/// without signing anybody in.
class PostgresOrderHistoryRepository implements OrderHistoryRepository {
  const PostgresOrderHistoryRepository({
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

  /// Order rows carry their own currency, and a branch that changed currency
  /// mid-life would otherwise have its history re-denominated on screen.
  Money _rowMoney(Object? minor, Object? rowCurrency, Object? rowExponent) =>
      Money(
        minor is int ? minor : 0,
        currency: rowCurrency is String ? rowCurrency : currency,
        exponent: rowExponent is int ? rowExponent : exponent,
      );

  /// The payment status, in SQL — the twin of `paymentStatusFromSums`.
  ///
  /// Kept beside the Dart rule rather than in a view. A view was the plan's
  /// first shape (§3 S1), and it would be the right home once reports (S3)
  /// read it too; today the only reader is this class, and a view is a new
  /// object every install needs a grant on — a grant that works for the
  /// superuser in the test suite and fails on a real till until somebody
  /// remembers `LocalBootstrap`. When S3 needs it, this expression moves into
  /// a migration verbatim.
  ///
  /// Reads the lateral sums [_orderJoins] provides. `sales_history_test.dart`
  /// runs it against the same cases as the Dart rule and requires the same
  /// answer; edit one and that suite fails until the other agrees.
  static const paymentStatusSql = '''
        CASE
          WHEN given_back.minor > 0 AND given_back.minor >= taken.minor
            THEN 'REFUNDED'
          WHEN given_back.minor > 0 THEN 'PARTIALLY_REFUNDED'
          WHEN taken.minor >= o.total_minor THEN 'PAID'
          WHEN taken.minor = 0 THEN 'UNPAID'
          ELSE 'PARTIALLY_PAID'
        END''';

  static const _orderColumns = '''
        o.id, o.client_transaction_id,
        coalesce(nullif(o.server_invoice_number, ''), o.invoice_number),
        o.status, o.order_type,
        o.occurred_at, o.subtotal_minor, o.discount_minor, o.service_minor,
        o.vat_minor, o.total_minor, o.currency, o.exponent,
        o.table_label, o.guest_count, o.voided_at, o.void_note,
        served.name, voider.name, reason.name_en, reason.name_ar,
        o.served_by, taken.minor, given_back.minor, $paymentStatusSql,
        trading.business_date, o.terminal_id::text, term.name,
        tenders.labels, tenders.type_ids,
        o.customer_id, cust.name, cust.phone, cust.email,
        length(coalesce(o.server_invoice_number, '')) > 0,
        o.day_order_number''';

  /// The joins [_orderColumns] needs.
  ///
  /// All `LEFT`: an order whose seller has been deleted, or whose void reason
  /// predates the reason table, must still appear. An `INNER` join here would
  /// make orders disappear from history as staff leave, which is the failure
  /// mode nobody notices until an audit.
  ///
  /// **The sums are lateral, not a `GROUP BY` over a join.** Joining payments
  /// and refunds to the order in one go multiplies each by the other — a sale
  /// paid in two tenders with one refund would count the refund twice. One
  /// aggregate per table per order cannot.
  ///
  /// **The methods a sale was paid in are one lateral too** (BO-2's payment
  /// column): one entry per method, in the order it was first taken, so a
  /// split bill lists both and a card taken twice is one card. Grouped on the
  /// label as well as the id, because a method renamed since keeps the name it
  /// was taken under — a sale paid "Card" before it became "Visa" still says
  /// Card, as its receipt does. Aggregated here rather than read from the
  /// payments per row afterwards: two hundred rows would be two hundred more
  /// round trips to draw one column.
  static String _orderJoins(SqlDialect dialect) =>
      '''
        LEFT JOIN pos_users       AS served ON served.id = o.served_by
        LEFT JOIN pos_users       AS voider ON voider.id = o.voided_by
        LEFT JOIN pos_reason_codes AS reason ON reason.id = o.void_reason_id
        LEFT JOIN pos_terminals   AS term   ON term.id = o.terminal_id
        LEFT JOIN pos_customers   AS cust   ON cust.id = o.customer_id
        ${_moneyJoins(dialect)}
        ${_tendersJoin(dialect)}
        ${tradingDayJoin('o', dialect: dialect)}''';

  /// The methods a sale was paid in, in the order first used, as two arrays
  /// in step: `tenders.labels` and `tenders.type_ids`.
  static String _tendersJoin(SqlDialect dialect) => switch (dialect) {
    SqlDialect.postgres => '''
        LEFT JOIN LATERAL (
          SELECT coalesce(array_agg(used.label ORDER BY used.first_id),
                          '{}') AS labels,
                 coalesce(array_agg(used.tender_type_id ORDER BY used.first_id),
                          '{}') AS type_ids
            FROM (SELECT p.label, p.tender_type_id, min(p.id) AS first_id
                    FROM pos_order_payments AS p
                   WHERE p.order_id = o.id
                   GROUP BY p.label, p.tender_type_id) AS used
        ) AS tenders ON true''',
    // No LATERAL on SQLite: the same per-order arrays (as JSON), one row per
    // order, joined on the order's id. A till's own file is small enough
    // that computing them for every order the join touches costs nothing.
    SqlDialect.sqlite => '''
        LEFT JOIN (
          SELECT o2.id AS order_id,
                 (SELECT json_group_array(used.label ORDER BY used.first_id)
                    FROM (SELECT p.label, min(p.id) AS first_id
                            FROM pos_order_payments AS p
                           WHERE p.order_id = o2.id
                           GROUP BY p.label, p.tender_type_id) AS used)
                   AS labels,
                 (SELECT json_group_array(used.tender_type_id
                                          ORDER BY used.first_id)
                    FROM (SELECT p.tender_type_id, min(p.id) AS first_id
                            FROM pos_order_payments AS p
                           WHERE p.order_id = o2.id
                           GROUP BY p.label, p.tender_type_id) AS used)
                   AS type_ids
            FROM pos_orders AS o2
        ) AS tenders ON tenders.order_id = o.id''',
  };

  /// What was taken and what went back, per order, as `taken.minor` and
  /// `given_back.minor` — the sums [paymentStatusSql] reads.
  ///
  /// Apart from [_orderJoins] so [summarise] sums the very laterals the rows
  /// are drawn from, without the name and tender joins a total has no use
  /// for. A second copy of these two sums is where "paid" on the strip would
  /// start disagreeing with PAID on the row.
  static String _moneyJoins(SqlDialect dialect) => switch (dialect) {
    SqlDialect.postgres => '''
        LEFT JOIN LATERAL (
          SELECT coalesce(sum(p.amount_minor), 0)::bigint AS minor
            FROM pos_order_payments AS p WHERE p.order_id = o.id
        ) AS taken ON true
        LEFT JOIN LATERAL (
          SELECT coalesce(sum(r.total_minor), 0)::bigint AS minor
            FROM pos_refunds AS r WHERE r.order_id = o.id
        ) AS given_back ON true''',
    SqlDialect.sqlite => '''
        LEFT JOIN (
          SELECT o2.id AS order_id,
                 coalesce((SELECT sum(p.amount_minor)
                             FROM pos_order_payments AS p
                            WHERE p.order_id = o2.id), 0) AS minor
            FROM pos_orders AS o2
        ) AS taken ON taken.order_id = o.id
        LEFT JOIN (
          SELECT o2.id AS order_id,
                 coalesce((SELECT sum(r.total_minor)
                             FROM pos_refunds AS r
                            WHERE r.order_id = o2.id), 0) AS minor
            FROM pos_orders AS o2
        ) AS given_back ON given_back.order_id = o.id''',
  };

  /// The trading day the row [alias] belongs to, as `trading.business_date`.
  ///
  /// [alias] is a `pos_orders` or a `pos_refunds` row — both carry the four
  /// columns this reads. Public because the reports
  /// (`PostgresReportsRepository`) file sales and refunds under their day by
  /// this rule and no other; a second copy of it would be one edit away from a
  /// Reports tile that does not match the sales list it drills into.
  ///
  /// **The business day is found by window as well as by id.** Migrations
  /// 35–36 stamp `business_day_id` by trigger and backfilled every row written
  /// before them, so the id answers for nearly everything. The window is kept
  /// for the row the trigger could not stamp — written while no day was open
  /// — which it files the same way every reader always has, and because it
  /// costs nothing once the id is there: the `OR` only looks at windows when
  /// the id is null. Ordered by `opened_at` so the most recent day that covers
  /// it answers, should a force-closed day and its successor ever overlap by a
  /// second.
  ///
  /// [dialect] defaults to PostgreSQL for the offline-only readers (reports,
  /// supplier invoices); a reader a cloud till reaches passes its engine's.
  static String tradingDayJoin(
    String alias, {
    SqlDialect dialect = SqlDialect.postgres,
  }) => dialect == SqlDialect.sqlite
      // The same day, chosen by the same rule, joined by its id: a correlated
      // scalar subquery in the ON clause, which SQLite has where it has no
      // LATERAL.
      ? '''
        LEFT JOIN pos_business_days AS trading ON trading.id = (
          SELECT d.id
            FROM pos_business_days AS d
           WHERE d.business_id = $alias.business_id
             AND d.branch_id = $alias.branch_id
             AND (d.id = $alias.business_day_id
                  OR ($alias.business_day_id IS NULL
                      AND d.opened_at <= $alias.occurred_at
                      AND (d.closed_at IS NULL
                           OR $alias.occurred_at < d.closed_at)))
           ORDER BY d.opened_at DESC
           LIMIT 1)'''
      : '''
        LEFT JOIN LATERAL (
          SELECT d.business_date
            FROM pos_business_days AS d
           WHERE d.business_id = $alias.business_id
             AND d.branch_id = $alias.branch_id
             AND (d.id = $alias.business_day_id
                  OR ($alias.business_day_id IS NULL
                      AND d.opened_at <= $alias.occurred_at
                      AND (d.closed_at IS NULL
                           OR $alias.occurred_at < d.closed_at)))
           ORDER BY d.opened_at DESC
           LIMIT 1
        ) AS trading ON true''';

  OrderRecord _record(List<Object?> row) {
    final currencyCode = row[11];
    final rowExponent = row[12];
    Money money(Object? minor) => _rowMoney(minor, currencyCode, rowExponent);
    final businessDate = row.dateTimeOrNull(25);

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
      occurredAt: (row.dateTime(5)).toLocal(),
      subtotal: money(row[6]),
      discount: money(row[7]),
      service: money(row[8]),
      vat: money(row[9]),
      total: money(row[10]),
      tableLabel: row[13] as String?,
      guestCount: row[14] as int?,
      voidedAt: (row.dateTimeOrNull(15))?.toLocal(),
      voidNote: row[16] as String?,
      servedByName: row[17] as String?,
      voidedByName: row[18] as String?,
      voidReason: row[19] as String?,
      voidReasonAr: row[20] as String?,
      servedByStaffId: row[21] as int?,
      paidTotal: money(row[22]),
      refundedTotal: money(row[23]),
      // Null only if the SQL and the enum ever disagreed on a word — and then
      // the record applies the Dart rule to the same sums, which is the same
      // answer by a different road rather than no answer.
      paymentStatus: PaymentStatus.fromWire(row[24] as String),
      // A `date` arrives as UTC midnight. Rebuilt as local midnight so it
      // compares with the dates the screen builds, which are local.
      businessDate: businessDate == null
          ? null
          : DateTime(businessDate.year, businessDate.month, businessDate.day),
      terminalId: row[26] as String?,
      terminalName: row[27] as String?,
      // Two arrays in step rather than a jsonb of pairs: both columns are NOT
      // NULL and aggregated under one ORDER BY, so position i of each is the
      // same tender — and arrays arrive typed, where jsonb arrives as maps to
      // be re-typed by hand.
      tenders: [
        for (final (i, label) in row.list(28)!.indexed)
          OrderRecordTender(
            tenderTypeId: row.list(29)![i] as int,
            label: label as String,
          ),
      ],
      customerId: row[30] as int?,
      customerName: row[31] as String?,
      customerPhone: row[32] as String?,
      customerEmail: row[33] as String?,
      platformNumbered: row.boolean(34),
      dayOrderNumber: row[35] as int?,
    );
  }

  /// `YYYY-MM-DD`, for a `::date` parameter.
  ///
  /// Text rather than a `DateTime`: the driver sends a `DateTime` as a
  /// timestamp, and comparing a `date` column to a timestamp casts the date to
  /// midnight in the SERVER's zone — a branch server left on UTC would move
  /// every boundary by two hours.
  static String _day(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

  /// [from] ≤ business date < [to], for the row [alias] under
  /// [tradingDayJoin] — see [OrderHistoryQuery.from] for what the two dates
  /// mean. Shared with the reports' refunds, which are filed by the same rule.
  static ({List<String> where, Map<String, Object?> parameters})
  businessDateRange({DateTime? from, DateTime? to, String alias = 'o'}) {
    final where = <String>[];
    final parameters = <String, Object?>{};

    // Business date where a day covers the row, calendar instant where none
    // does. A CASE rather than an OR so each row is judged by exactly one of
    // the two, never whichever is kinder.
    if (from != null) {
      // The floor is what lets the index on `occurred_at` do the work. A
      // business day opens on or after midnight of its own date, so no sale
      // filed under a date at or after `from` can have been rung up before
      // that midnight. A day of slack covers a day somebody opened early; the
      // alternative, no floor, evaluates the day window for every sale the
      // branch ever made to answer "today".
      where.add('$alias.occurred_at >= @fromFloor');
      parameters['fromFloor'] = from
          .subtract(const Duration(days: 1))
          .toUtc();
      where.add(
        '(CASE WHEN trading.business_date IS NOT NULL '
        '      THEN trading.business_date >= @fromDay::date '
        '      ELSE $alias.occurred_at >= @from END)',
      );
      parameters['fromDay'] = _day(from);
      parameters['from'] = from.toUtc();
    }
    if (to != null) {
      // No ceiling to match the floor. A day left open over a weekend files
      // Sunday's sales under Friday, so a sale rung up well after `to` can
      // still belong before it.
      where.add(
        '(CASE WHEN trading.business_date IS NOT NULL '
        '      THEN trading.business_date < @toDay::date '
        '      ELSE $alias.occurred_at < @to END)',
      );
      parameters['toDay'] = _day(to);
      parameters['to'] = to.toUtc();
    }
    return (where: where, parameters: parameters);
  }

  /// The WHERE clauses and parameters [search] runs [query] with, over
  /// `pos_orders AS o` with [tradingDayJoin] on `o` in the FROM.
  ///
  /// Public and static because a figure that summarises this list has to be
  /// computed over exactly these rows. The reports build their sales from it
  /// (plan 17 S3: every figure equals the rows its drill-down lists), and so
  /// should BO-3's summary strip. Handing them the rule, rather than asking
  /// them to restate it, is what keeps that true after somebody changes a
  /// filter here.
  /// The fewest digits of a search that are also tried as a phone number.
  static const minPhoneDigits = 7;

  static ({List<String> where, Map<String, Object?> parameters}) filterFor(
    OrderHistoryQuery query, {
    required int businessId,
    required int branchId,
  }) {
    final range = businessDateRange(from: query.from, to: query.to);
    final where = <String>[
      'o.business_id = @business',
      'o.branch_id = @branch',
      ...range.where,
    ];
    final parameters = <String, Object?>{
      'business': businessId,
      'branch': branchId,
      ...range.parameters,
    };

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
    if (query.tenderTypeId != null) {
      // EXISTS, not a join: a sale paid in two tenders would otherwise come
      // back twice, and a list with the same invoice on two rows is a list
      // somebody totals wrong.
      where.add(
        'EXISTS (SELECT 1 FROM pos_order_payments AS tender '
        '        WHERE tender.order_id = o.id '
        '          AND tender.tender_type_id = @tender)',
      );
      parameters['tender'] = query.tenderTypeId;
    }
    if (query.terminalId != null) {
      // Compared as text. The id came from [terminals], so it is a uuid — but
      // a cast that throws on a malformed one would turn a stale filter into
      // an error screen, where comparing text turns it into an empty list.
      where.add('o.terminal_id::text = @terminal');
      parameters['terminal'] = query.terminalId;
    }

    final search = query.search?.trim();
    if (search != null && search.isNotEmpty) {
      // Anywhere in the string, not a prefix: what somebody reads off a receipt
      // is the tail of the number, and a prefix match would fail on exactly the
      // input they have. It costs the index — accepted, because the rows this
      // scans are one branch's orders inside a date window, and the alternative
      // is a search box that does not find what the customer is holding.
      //
      // And the customer the sale was for, by name or by number. The number
      // only from [minPhoneDigits] digits: a short run of digits is the tail of
      // a receipt number far more often than the tail of a phone, and matching
      // both would fill the list with strangers whose phones happen to end in
      // the same three digits. A customer found by fewer digits is one search
      // away in Customers.
      final digits = PosCustomer.normalisePhone(search);
      final byPhone = digits.length >= minPhoneDigits;
      where.add(
        '(coalesce(nullif(o.server_invoice_number, \'\'), o.invoice_number) '
        'ILIKE @search OR o.table_label ILIKE @search '
        'OR EXISTS (SELECT 1 FROM pos_customers AS buyer '
        '            WHERE buyer.id = o.customer_id '
        "              AND (buyer.name ILIKE @search${byPhone ? ' OR buyer.phone LIKE @searchDigits' : ''})))",
      );
      parameters['search'] = '%$search%';
      if (byPhone) parameters['searchDigits'] = '%$digits%';
    }
    return (where: where, parameters: parameters);
  }

  @override
  Future<List<OrderRecord>> search(OrderHistoryQuery query) async {
    final filter = filterFor(
      query,
      businessId: businessId,
      branchId: branchId,
    );
    // The cursor is added here and not in [filterFor]: the filter is what the
    // reports and [summarise] share, and a total is over every page.
    final where = [...filter.where];
    final parameters = <String, Object?>{
      ...filter.parameters,
      'limit': query.limit,
    };
    if (query.afterOrderId case final after?) {
      // Strictly after the cursor row in the ORDER BY below, compared as a
      // pair: two sales on one instant are told apart by id, so a page
      // boundary between them can neither repeat the one nor skip the other.
      //
      // The first clause says less than the second and is there for the
      // index. `pos_orders_history_idx` is (business, branch, occurred_at
      // DESC); a pair ending in `id` is not a range on it, while `occurred_at
      // <=` is, so page forty starts at its cursor instead of walking the
      // thirty-nine before it. That is also why BO-3 needs no migration 48:
      // the index serves the order and the bound, and the ties left for the
      // sort are the few sales that share a microsecond.
      where
        ..add(
          'o.occurred_at <= (SELECT a.occurred_at FROM pos_orders AS a '
          '                   WHERE a.id = @after)',
        )
        ..add(
          '(o.occurred_at, o.id) < (SELECT a.occurred_at, a.id '
          '                           FROM pos_orders AS a WHERE a.id = @after)',
        );
      parameters['after'] = after;
    }
    final rows = await _db.query(
      config,
      'SELECT $_orderColumns FROM pos_orders AS o ${_orderJoins(_db.dialect)} '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY o.occurred_at DESC, o.id DESC LIMIT @limit',
      parameters: parameters,
    );

    return rows.map((row) => _record(row.toList())).toList(growable: false);
  }

  /// The strip's figures, in one statement over [filterFor] — the rows
  /// [search] pages through and no others.
  ///
  /// [OrderHistorySummary.of] is the rule and this is its twin: which rows
  /// are struck through comes from [OrderStatus.isDead] and which are owed
  /// from [PaymentStatus], handed in as parameters rather than spelled out,
  /// so a status added to either enum moves both. The payment status is
  /// [paymentStatusSql] itself, over [_moneyJoins] itself.
  ///
  /// Rejected: fetching every row and applying the Dart rule. It is one
  /// answer either way, but "Last 30 days" at a busy branch is thousands of
  /// rows carried across the wire to make four numbers.
  @override
  Future<OrderHistorySummary> summarise(OrderHistoryQuery query) async {
    final filter = filterFor(
      query,
      businessId: businessId,
      branchId: branchId,
    );
    final rows = await _db.query(
      config,
      // `::bigint` on every sum: sum() over bigint is numeric in PostgreSQL,
      // which arrives as a string.
      'SELECT count(*)::bigint, '
      '       count(*) FILTER (WHERE listed.dead)::bigint, '
      '       coalesce(sum(listed.total) FILTER (WHERE NOT listed.dead), 0)'
      '         ::bigint, '
      '       coalesce(sum(listed.taken) FILTER (WHERE NOT listed.dead), 0)'
      '         ::bigint, '
      '       coalesce(sum(listed.total - listed.taken) '
      '                FILTER (WHERE NOT listed.dead '
      '                          AND listed.money = ANY(@owing)), 0)::bigint, '
      '       coalesce(sum(listed.total) FILTER (WHERE listed.dead), 0)'
      '         ::bigint '
      'FROM (SELECT o.status = ANY(@deadStatuses) AS dead, '
      '             o.total_minor AS total, taken.minor AS taken, '
      '             $paymentStatusSql AS money '
      '        FROM pos_orders AS o ${_moneyJoins(_db.dialect)} '
      '        ${tradingDayJoin('o', dialect: _db.dialect)} '
      '       WHERE ${filter.where.join(' AND ')}) AS listed',
      parameters: {
        ...filter.parameters,
        'deadStatuses': [
          for (final status in OrderStatus.values)
            if (status.isDead) status.wire,
        ],
        'owing': [
          for (final status in PaymentStatus.values)
            if (_owes(status)) status.wire,
        ],
      },
    );
    final row = rows.first.toList();
    Money money(Object? minor) =>
        Money(minor as int, currency: currency, exponent: exponent);
    return OrderHistorySummary(
      count: row[0] as int,
      dead: row[1] as int,
      total: money(row[2]),
      paid: money(row[3]),
      outstanding: money(row[4]),
      deadTotal: money(row[5]),
    );
  }

  /// Whether a sale in [status] still has money owed on it — the SQL side of
  /// the switch in [OrderHistorySummary.of], and exhaustive for the same
  /// reason.
  static bool _owes(PaymentStatus status) => switch (status) {
    PaymentStatus.unpaid || PaymentStatus.partiallyPaid => true,
    PaymentStatus.paid ||
    PaymentStatus.partiallyRefunded ||
    PaymentStatus.refunded => false,
  };

  @override
  Future<OrderRecord?> byInvoiceNumber(String invoiceNumber) async {
    final rows = await _db.query(
      config,
      'SELECT $_orderColumns FROM pos_orders AS o ${_orderJoins(_db.dialect)} '
      'WHERE o.business_id = @business AND o.branch_id = @branch '
      '  AND coalesce(nullif(o.server_invoice_number, \'\'), o.invoice_number) = @invoice',
      parameters: {
        'business': businessId,
        'branch': branchId,
        'invoice': invoiceNumber.trim(),
      },
    );
    if (rows.isEmpty) return null;
    return _record(rows.first.toList());
  }

  @override
  Future<List<HistoryTerminal>> terminals() async {
    // From `pos_terminals`, not `SELECT DISTINCT terminal_id FROM pos_orders`:
    // the distinct scans every sale the branch ever made to list three tills.
    // The cost is that a till whose row was deleted cannot be picked — its
    // sales still list, under every till, which is the safe side to be wrong.
    final rows = await _db.query(
      config,
      'SELECT id::text, name FROM pos_terminals '
      'WHERE business_id = @business AND branch_id = @branch '
      'ORDER BY name, id',
      parameters: {'business': businessId, 'branch': branchId},
    );
    return rows
        .map((raw) {
          final row = raw.toList();
          return HistoryTerminal(id: row[0] as String, name: row[1] as String?);
        })
        .toList(growable: false);
  }

  /// A Returns row: the refund, the sale it is against, and the names.
  ///
  /// The sale's currency, not the terminal's: a refund gives back in what it
  /// was paid in, and `pos_refunds` carries no currency of its own.
  static const _refundColumns = '''
        r.id, r.order_id,
        coalesce(nullif(o.server_invoice_number, ''), o.invoice_number),
        r.occurred_at, r.total_minor,
        o.currency, o.exponent, r.kind, issuer.name, approver.name,
        reason.name_en, reason.name_ar, r.note, counted.lines,
        r.terminal_id::text, term.name, o.served_by, trading.business_date''';

  /// The joins [_refundColumns] needs.
  ///
  /// The sale by `JOIN`, every name by `LEFT JOIN`. `order_id` is NOT NULL
  /// with `ON DELETE RESTRICT`, so the inner join drops no refund; a name
  /// joined inner would drop the refund of somebody who has since left.
  ///
  /// The lines are counted in a lateral, not joined and grouped: one refund
  /// row per refund is the list's whole promise, and a join to its lines is
  /// one row per line until something groups it back — the step a later
  /// edit forgets, and the strip starts counting items as refunds.
  static String _refundJoins(SqlDialect dialect) =>
      '''
        JOIN pos_orders AS o ON o.id = r.order_id
        LEFT JOIN pos_users        AS issuer   ON issuer.id = r.refunded_by
        LEFT JOIN pos_users        AS approver ON approver.id = r.approved_by_id
        LEFT JOIN pos_reason_codes AS reason   ON reason.id = r.reason_id
        LEFT JOIN pos_terminals    AS term     ON term.id = r.terminal_id
        ${dialect == SqlDialect.sqlite ? '''
        LEFT JOIN (
          SELECT r2.id AS refund_id,
                 (SELECT count(*) FROM pos_refund_lines AS l
                   WHERE l.refund_id = r2.id) AS lines
            FROM pos_refunds AS r2
        ) AS counted ON counted.refund_id = r.id''' : '''
        LEFT JOIN LATERAL (
          SELECT count(*)::bigint AS lines
            FROM pos_refund_lines AS l WHERE l.refund_id = r.id
        ) AS counted ON true'''}
        ${tradingDayJoin('r', dialect: dialect)}''';

  /// The WHERE clauses and parameters Returns runs [query] with, over
  /// `pos_refunds AS r JOIN pos_orders AS o` with [tradingDayJoin] on `r`.
  ///
  /// Shared by [refunds] and [summariseRefunds] for the reason [filterFor]
  /// is shared: a figure over a list is only its figure while both read one
  /// WHERE.
  ///
  /// The date is the refund's own trading day, not its sale's —
  /// [businessDateRange] on `r`, as the reports file refunds. A refund on
  /// Tuesday for Saturday's sale is Tuesday's money leaving the drawer.
  static ({List<String> where, Map<String, Object?> parameters})
  refundFilterFor(
    RefundHistoryQuery query, {
    required int businessId,
    required int branchId,
  }) {
    final range = businessDateRange(
      from: query.from,
      to: query.to,
      alias: 'r',
    );
    final where = <String>[
      'r.business_id = @business',
      'r.branch_id = @branch',
      ...range.where,
    ];
    final parameters = <String, Object?>{
      'business': businessId,
      'branch': branchId,
      ...range.parameters,
    };
    if (query.servedByStaffId != null) {
      where.add('o.served_by = @served');
      parameters['served'] = query.servedByStaffId;
    }
    final search = query.search?.trim();
    if (search != null && search.isNotEmpty) {
      // The refund's number exactly, with or without the `#` it is shown
      // with; the invoice anywhere, for the tail read off a receipt.
      where.add(
        '(coalesce(nullif(o.server_invoice_number, \'\'), o.invoice_number) '
        'ILIKE @search OR r.id::text = @refundNumber)',
      );
      parameters['search'] = '%$search%';
      parameters['refundNumber'] = search.startsWith('#')
          ? search.substring(1).trim()
          : search;
    }
    return (where: where, parameters: parameters);
  }

  @override
  Future<List<RefundRecord>> refunds(RefundHistoryQuery query) async {
    final filter = refundFilterFor(
      query,
      businessId: businessId,
      branchId: branchId,
    );
    final where = [...filter.where];
    final parameters = <String, Object?>{
      ...filter.parameters,
      'limit': query.limit,
    };
    if (query.afterRefundId case final after?) {
      // The sales list's keyset, on `pos_refunds_history_idx` — see [search]
      // for why the looser bound comes first.
      where
        ..add(
          'r.occurred_at <= (SELECT a.occurred_at FROM pos_refunds AS a '
          '                   WHERE a.id = @after)',
        )
        ..add(
          '(r.occurred_at, r.id) < (SELECT a.occurred_at, a.id '
          '                           FROM pos_refunds AS a WHERE a.id = @after)',
        );
      parameters['after'] = after;
    }
    final rows = await _db.query(
      config,
      'SELECT $_refundColumns FROM pos_refunds AS r ${_refundJoins(_db.dialect)} '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY r.occurred_at DESC, r.id DESC LIMIT @limit',
      parameters: parameters,
    );
    return rows
        .map((raw) {
          final row = raw.toList();
          final businessDate = row.dateTimeOrNull(17);
          return RefundRecord(
            id: row[0] as int,
            orderId: row[1] as int,
            invoiceNumber: row[2] as String,
            occurredAt: (row.dateTime(3)).toLocal(),
            total: _rowMoney(row[4], row[5], row[6]),
            // The CHECK in migration 12 allows two words. One this build does
            // not know is shown as the kind that claims less.
            kind: RefundKind.fromWire(row[7] as String) ?? RefundKind.partial,
            refundedByName: row[8] as String?,
            approvedByName: row[9] as String?,
            reasonName: row[10] as String?,
            reasonNameAr: row[11] as String?,
            note: row[12] as String?,
            lineCount: row[13] as int,
            terminalId: row[14] as String?,
            terminalName: row[15] as String?,
            servedByStaffId: row[16] as int?,
            businessDate: businessDate == null
                ? null
                : DateTime(
                    businessDate.year,
                    businessDate.month,
                    businessDate.day,
                  ),
          );
        })
        .toList(growable: false);
  }

  /// Without the names and the line count: a total has no use for them, and
  /// every join a figure does not need is one more way for it to multiply a
  /// row.
  @override
  Future<RefundHistorySummary> summariseRefunds(
    RefundHistoryQuery query,
  ) async {
    final filter = refundFilterFor(
      query,
      businessId: businessId,
      branchId: branchId,
    );
    final rows = await _db.query(
      config,
      'SELECT count(*)::bigint, coalesce(sum(r.total_minor), 0)::bigint '
      'FROM pos_refunds AS r JOIN pos_orders AS o ON o.id = r.order_id '
      '${tradingDayJoin('r', dialect: _db.dialect)} '
      'WHERE ${filter.where.join(' AND ')}',
      parameters: filter.parameters,
    );
    final row = rows.first.toList();
    return RefundHistorySummary(
      count: row[0] as int,
      total: Money(row[1] as int, currency: currency, exponent: exponent),
    );
  }

  @override
  Future<OrderRecordDetail?> detail(int orderId) async {
    final orderRows = await _db.query(
      config,
      'SELECT $_orderColumns FROM pos_orders AS o ${_orderJoins(_db.dialect)} '
      'WHERE o.id = @id AND o.business_id = @business '
      '  AND o.branch_id = @branch',
      parameters: {
        'id': orderId,
        'business': businessId,
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
      'LEFT JOIN pos_users AS voider ON voider.id = l.voided_by '
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
      'LEFT JOIN pos_users AS applier ON applier.id = d.applied_by '
      'LEFT JOIN pos_users AS approver ON approver.id = d.approved_by_id '
      'WHERE d.order_id = @order ORDER BY d.id',
      parameters: {'order': orderId},
    );

    // The breakdown by rate, in the order it was written — highest rate first,
    // as `TaxEngine.linesFor` sorts it. The rates are the snapshots taken at
    // settlement, so a business moved to 15% next year still reprints this
    // sale at the 14% it was charged.
    final taxRows = await _db.query(
      config,
      'SELECT name_snapshot, rate_bp, base_minor, amount_minor, tax_group_id '
      'FROM pos_order_taxes WHERE order_id = @order ORDER BY id',
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
          voidedAt: (row.dateTimeOrNull(10))?.toLocal(),
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
          occurredAt: (row.dateTimeOrNull(4))?.toLocal(),
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
          appliedAt: (row.dateTimeOrNull(5))?.toLocal(),
        );
      }).toList(growable: false),
      taxLines: taxRows.map((raw) {
        final row = raw.toList();
        return TaxLine(
          name: row[0] as String,
          rateBp: row[1] as int,
          base: money(row[2]),
          amount: money(row[3]),
          taxGroupId: row[4] as int?,
        );
      }).toList(growable: false),
      events: await _events(order, money),
    );
  }

  /// Everything that happened to [order] after it was rung up, oldest first.
  ///
  /// Three reads rather than one `UNION`: the four sources share no columns
  /// worth the name, and a union padded with NULLs to make them line up is a
  /// query nobody can change without counting commas.
  Future<List<SaleEvent>> _events(
    OrderRecord order,
    Money Function(Object?) money,
  ) async {
    final events = <SaleEvent>[];

    final printRows = await _db.query(
      config,
      'SELECT kind, status, queued_at, printed_at FROM pos_print_jobs '
      'WHERE order_id = @order AND business_id = @business '
      '  AND branch_id = @branch ORDER BY id',
      parameters: {
        'order': order.id,
        'business': businessId,
        'branch': branchId,
      },
    );
    for (final raw in printRows) {
      final row = raw.toList();
      // Two kinds and two states, both held by CHECK constraints in migration
      // 34 — so `reprint` or not, `printed` or not, is the whole space.
      final copy = row[0] == 'reprint';
      final printedAt = row.dateTimeOrNull(3);
      final done = row[1] == 'printed' && printedAt != null;
      events.add(
        SaleEvent(
          kind: switch ((copy, done)) {
            (false, true) => SaleEventKind.printed,
            (false, false) => SaleEventKind.printPending,
            (true, true) => SaleEventKind.reprinted,
            (true, false) => SaleEventKind.reprintPending,
          },
          at: (done ? printedAt : row.dateTime(2)).toLocal(),
        ),
      );
    }

    final auditRows = await _db.query(
      config,
      'SELECT action, actor_name, approved_by_name, occurred_at '
      'FROM pos_audit_events '
      'WHERE business_id = @business AND entity_type = @entity '
      '  AND entity_id = @id '
      'ORDER BY occurred_at, id',
      parameters: {
        'business': businessId,
        'entity': AuditAction.entityOrder,
        'id': '${order.id}',
      },
    );
    for (final raw in auditRows) {
      final row = raw.toList();
      final action = row[0] as String;
      final reprint = action == AuditAction.receiptReprinted;
      events.add(
        SaleEvent(
          kind: reprint ? SaleEventKind.reprintRequested : SaleEventKind.audit,
          at: (row.dateTime(3)).toLocal(),
          actorName: row[1] as String?,
          approvedByName: row[2] as String?,
          auditAction: reprint ? null : action,
        ),
      );
    }

    // The void is on the order itself — there is no audit row for it, the
    // order's own `voided_by` and `voided_at` are the record.
    final voidedAt = order.voidedAt;
    if (voidedAt != null) {
      events.add(
        SaleEvent(
          kind: SaleEventKind.voided,
          at: voidedAt,
          actorName: order.voidedByName,
        ),
      );
    }

    final refundRows = await _db.query(
      config,
      'SELECT r.occurred_at, issuer.name, approver.name, r.total_minor '
      'FROM pos_refunds AS r '
      'LEFT JOIN pos_users AS issuer ON issuer.id = r.refunded_by '
      'LEFT JOIN pos_users AS approver ON approver.id = r.approved_by_id '
      'WHERE r.order_id = @order AND r.business_id = @business '
      'ORDER BY r.occurred_at, r.id',
      parameters: {'order': order.id, 'business': businessId},
    );
    for (final raw in refundRows) {
      final row = raw.toList();
      events.add(
        SaleEvent(
          kind: SaleEventKind.refunded,
          at: (row.dateTime(0)).toLocal(),
          actorName: row[1] as String?,
          approvedByName: row[2] as String?,
          amount: money(row[3]),
        ),
      );
    }

    // Stable, so two things in the same second keep the order their own table
    // gave them — a reprint request stays ahead of the copy it produced.
    mergeSort(events, compare: (a, b) => a.at.compareTo(b.at));
    return events;
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
  Future<OrderHistorySummary> summarise(OrderHistoryQuery query) async =>
      OrderHistorySummary.empty;

  @override
  Future<OrderRecordDetail?> detail(int orderId) async => null;

  @override
  Future<OrderRecord?> byInvoiceNumber(String invoiceNumber) async => null;

  @override
  Future<List<HistoryTerminal>> terminals() async => const [];

  @override
  Future<List<RefundRecord>> refunds(RefundHistoryQuery query) async =>
      const [];

  @override
  Future<RefundHistorySummary> summariseRefunds(
    RefundHistoryQuery query,
  ) async => RefundHistorySummary.empty;
}
