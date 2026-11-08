import '../sql/sql.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/business_day.dart';
import '../../domain/models/permissions.dart';
import '../../domain/repositories/admin_repositories.dart' show AuditAction;
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import 'postgres_order_history_repository.dart';

/// Shifts on the branch server.
///
/// Two rules are enforced by the **database** rather than by this class, because
/// both matter more than any code path that might forget them:
///
/// * **One open shift per terminal**, by a partial unique index. Two open shifts
///   means two people each answerable for the same drawer.
/// * **A shift is open or closed, never half**, by a check constraint. A closing
///   time with no count is not a state anybody can act on.
///
/// Closing runs in one transaction with the summary it is closing against, so
/// the expected total cannot be computed from one set of sales and stored
/// against another.
class PostgresShiftRepository implements ShiftRepository {
  const PostgresShiftRepository({
    required SqlDatabase database,
    required this._config,
    required this._businessId,
    required this._branchId,
    required this._terminalId,
    this.onQueued,
  }) : _db = database;

  /// Told when a shift open or close is queued for the platform — see
  /// `PostgresOrdersRepository.onQueued`.
  final void Function()? onQueued;

  final SqlDatabase _db;
  final DeploymentConfig _config;
  final int _businessId;
  final int _branchId;
  final String _terminalId;

  static const _selectShift = '''
    SELECT s.id, s.opened_at, s.opening_float_minor, st.name, s.closed_at,
           s.opened_by, s.client_transaction_id
    FROM pos_shifts s JOIN pos_users st ON st.id = s.opened_by
  ''';

  @override
  Future<PosShift?> current() async {
    final rows = await _db.query(
      _config,
      '$_selectShift WHERE s.terminal_id::text = @terminal AND s.closed_at IS NULL',
      parameters: {'terminal': _terminalId},
    );
    return rows.isEmpty
        ? null
        : _shift(rows.first, clientTransactionId: rows.first[6]?.toString());
  }

  @override
  Future<PosShift> open({
    required PosStaff by,
    required Money openingFloat,
  }) async {
    final existing = await current();
    if (existing != null) {
      // Reached when a till is restarted mid-shift, which is the common case
      // rather than an error: the drawer never closed, so neither did the
      // shift, and handing back the open one is what continuity means.
      return existing;
    }

    final clientId = _config.mode.syncsSalesToPlatform
        ? const Uuid().v4()
        : null;
    return _db.runTx(_config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_shifts '
          '  (business_id, branch_id, terminal_id, opened_by, opening_float_minor, '
          '   client_transaction_id) '
          'VALUES (@business, @branch, @terminal, @staff, @float, @client) '
          'RETURNING id, opened_at',
        ),
        parameters: {
          'business': _businessId,
          'branch': _branchId,
          'terminal': _terminalId,
          'staff': by.id,
          'float': openingFloat.minor,
          'client': clientId,
        },
      );
      final id = rows.first[0] as int;
      if (clientId != null) {
        await _enqueueSync(
          tx,
          eventType: 'shift_open',
          sourceId: id,
          clientTransactionId: clientId,
        );
        onQueued?.call();
      }
      return PosShift(
        id: id,
        openedAt: rows.first[1] as DateTime,
        openingFloat: openingFloat,
        openedByName: by.name,
        openedById: by.id,
        clientTransactionId: clientId,
      );
    });
  }

  @override
  Future<ShiftSummary> summarise(PosShift shift) =>
      _db.runTx(_config, (tx) => _summarise(tx, shift));

  @override
  Future<ShiftActivity> activity() async {
    // One grouped read rather than "count the open ones" plus "newest per
    // person": the tile and the column are then the same rows at the same
    // instant. Served by `pos_shifts_branch_opened_idx`, so it needs no new
    // index — and no migration.
    //
    // On the till's credential, which already reads `pos_shifts` to find its
    // own drawer; `grants_cover_usage_test.dart` holds that.
    final rows = await _db.query(
      _config,
      'SELECT opened_by, max(opened_at), '
      '       count(*) FILTER (WHERE closed_at IS NULL) '
      'FROM pos_shifts '
      'WHERE business_id = @business AND branch_id = @branch '
      'GROUP BY opened_by',
      parameters: {'business': _businessId, 'branch': _branchId},
    );

    var open = 0;
    final last = <int, DateTime>{};
    final onShift = <int>{};
    for (final row in rows) {
      final staff = row[0]! as int;
      final openHere = row[2]! as int;
      last[staff] = row[1]! as DateTime;
      open += openHere;
      if (openHere > 0) onShift.add(staff);
    }
    return ShiftActivity(openShifts: open, lastOpenedAt: last, onShift: onShift);
  }

  @override
  Future<List<OpenDrawer>> openDrawers() => _db.runTx(_config, (tx) async {
    // `activity`'s "open at this branch", with the rows rather than a count:
    // the same WHERE, so the Users tile and Finance's drawers count the same
    // drawers.
    final rows = await tx.execute(
      Sql.named('''
        SELECT s.id, s.opened_at, s.opening_float_minor, st.name, s.closed_at,
               s.opened_by, s.terminal_id::text, term.name
          FROM pos_shifts s
          JOIN pos_users st ON st.id = s.opened_by
          LEFT JOIN pos_terminals term ON term.id = s.terminal_id
         WHERE s.business_id = @business AND s.branch_id = @branch
           AND s.closed_at IS NULL
         ORDER BY term.name NULLS LAST, s.opened_at, s.id
      '''),
      parameters: {'business': _businessId, 'branch': _branchId},
    );

    // **Each drawer by `_summarise`, the function `close` stores the
    // expected cash from** — not a branch-wide sum written for this screen.
    // One query per drawer is four statements a till, and a branch has a
    // handful; a grouped query would be faster and would be the second
    // definition of "expected" that the cash-up does not use.
    final drawers = <OpenDrawer>[];
    for (final row in rows) {
      drawers.add(
        OpenDrawer(
          terminalId: row[6]! as String,
          terminalName: row[7] as String?,
          summary: await _summarise(tx, _shift(row)),
        ),
      );
    }
    return drawers;
  });

  /// The shifts a range covers, as `occurred_at` so the sales list's own
  /// business-date rule can file them — [PostgresOrderHistoryRepository
  /// .businessDateRange] and `tradingDayJoin` read `pos_business_days` against
  /// that column and no other. Aliasing it here is one line; a copy of the rule
  /// written for `opened_at` would be the second definition of "this week"
  /// that Finance and Sales then disagree by.
  static const _shiftsAsDated =
      '(SELECT *, opened_at AS occurred_at FROM pos_shifts) AS s';

  /// Enum-keyed, so a fourth state fails to compile here rather than falling
  /// through to "every shift". Each clause is [ShiftRecord.status]'s rule in
  /// SQL — closed by the opener, or by somebody else on an approval.
  static String _statusSql(ShiftStatus status) => switch (status) {
    ShiftStatus.open => 's.closed_at IS NULL',
    ShiftStatus.closed =>
      '(s.closed_at IS NOT NULL AND s.closed_by = s.opened_by)',
    ShiftStatus.forceClosed =>
      '(s.closed_at IS NOT NULL AND s.closed_by <> s.opened_by)',
  };

  @override
  Future<ShiftHistory> history(ShiftHistoryQuery query) =>
      _db.runTx(_config, (tx) async {
        final range = PostgresOrderHistoryRepository.businessDateRange(
          from: query.from,
          to: query.to,
          alias: 's',
        );
        // An open shift whatever the dates — see [ShiftHistoryQuery].
        final dated = [
          's.business_id = @business',
          's.branch_id = @branch',
          '(s.closed_at IS NULL OR (${range.where.join(' AND ')}))',
        ];
        final parameters = <String, Object?>{
          'business': _businessId,
          'branch': _branchId,
          ...range.parameters,
        };

        // The filters' choices: every till and opener in the dates, before the
        // filters narrow them. Offering only what the current filter left
        // would make a chosen till the only till there is to choose.
        final facets = await tx.execute(
          Sql.named('''
            SELECT DISTINCT s.terminal_id::text, term.name, s.opened_by, st.name
              FROM $_shiftsAsDated
              JOIN pos_users st ON st.id = s.opened_by
              LEFT JOIN pos_terminals term ON term.id = s.terminal_id
              ${PostgresOrderHistoryRepository.tradingDayJoin('s')}
             WHERE ${dated.join(' AND ')}
          '''),
          parameters: parameters,
        );

        final terminal = query.terminalId;
        final staff = query.staffId;
        final where = [
          ...dated,
          if (terminal != null) 's.terminal_id::text = @terminal',
          if (staff != null) 's.opened_by = @staff',
          if (query.statuses.isNotEmpty)
            '(${[for (final st in ShiftStatus.values)
                if (query.statuses.contains(st)) _statusSql(st)].join(' OR ')})',
        ];

        // The approval is read off the close's own ledger row, because that is
        // where `CloseShiftDialog` puts it: `pos_shifts` has a column for the
        // manager who allowed an *opening* and none for a close. Served by
        // `pos_audit_events_entity_idx`, which is keyed exactly so.
        final rows = await tx.execute(
          Sql.named('''
            SELECT s.id, s.opened_at, s.opening_float_minor, st.name,
                   s.closed_at, s.opened_by,
                   s.terminal_id::text, term.name, s.closed_by, closer.name,
                   s.counted_cash_minor, s.expected_cash_minor,
                   s.variance_minor, s.closing_note, approval.approved_by_name
              FROM $_shiftsAsDated
              JOIN pos_users st ON st.id = s.opened_by
              LEFT JOIN pos_users closer ON closer.id = s.closed_by
              LEFT JOIN pos_terminals term ON term.id = s.terminal_id
              ${PostgresOrderHistoryRepository.tradingDayJoin('s')}
              LEFT JOIN LATERAL (
                SELECT a.approved_by_name
                  FROM pos_audit_events a
                 WHERE a.business_id = s.business_id
                   AND a.entity_type = @entity
                   AND a.entity_id = s.id::text
                   AND a.action = @closed
                   AND a.approved_by_name IS NOT NULL
                 ORDER BY a.occurred_at DESC
                 LIMIT 1
              ) AS approval ON true
             WHERE ${where.join(' AND ')}
             ORDER BY (s.closed_at IS NULL) DESC, s.opened_at DESC, s.id DESC
             LIMIT @limit
          '''),
          parameters: {
            ...parameters,
            'terminal': ?terminal,
            'staff': ?staff,
            'entity': AuditAction.entityShift,
            'closed': AuditAction.shiftClosed,
            // One over, to know there were more without counting them all.
            'limit': ShiftHistory.limit + 1,
          },
        );

        Money? money(Object? minor) => minor == null ? null : Money(minor as int);

        // **Each row by `_summarise`**, as [openDrawers] does and for its
        // reason: a grouped query over the range would be faster and would be
        // the second definition of "expected" that the cash-up does not use.
        final records = <ShiftRecord>[];
        for (final row in rows.take(ShiftHistory.limit)) {
          records.add(
            ShiftRecord(
              summary: await _summarise(tx, _shift(row)),
              terminalId: row[6]! as String,
              terminalName: row[7] as String?,
              closedById: row[8] as int?,
              closedByName: row[9] as String?,
              countedCash: money(row[10]),
              recordedExpected: money(row[11]),
              recordedVariance: money(row[12]),
              note: row[13] as String?,
              approvedByName: row[14] as String?,
            ),
          );
        }

        final tills = <String, String>{};
        final people = <int, String>{};
        for (final row in facets) {
          final id = row[0]! as String;
          tills[id] = (row[1] as String?) ?? id;
          people[row[2]! as int] = row[3]! as String;
        }
        int byName<T>((T, String) a, (T, String) b) => a.$2.compareTo(b.$2);
        return ShiftHistory(
          shifts: records,
          tills: [for (final e in tills.entries) (e.key, e.value)]
            ..sort(byName),
          staff: [for (final e in people.entries) (e.key, e.value)]
            ..sort(byName),
          cut: rows.length > ShiftHistory.limit,
        );
      });

  @override
  Future<ShiftClose> close({
    required PosShift shift,
    required PosStaff by,
    required Money countedCash,
    String? note,
    Approval? approval,
  }) async {
    // The drawer is its opener's. Anybody else closes it on a manager's
    // approval for this shift — which the close dialog has asked for since the
    // count stopped being signable by whoever held the capability, and which
    // nothing below the dialog checked until now.
    Authorization.require(
      by,
      PosCapability.shiftClose,
      approval: approval,
      subject: '${shift.id}',
      approvalRequired: !shift.openedBy(by.id),
    );

    // The refusal below is raised *outside* the transaction on purpose.
    // `runTx` translates anything thrown inside it into a `PosDbException`,
    // which would turn "this shift is already closed" — a thing the person at
    // the till needs to read — into "the database did not answer as expected".
    final closed = await _db.runTx(_config, (tx) async {
      // Summarised inside the same transaction as the update. Computing the
      // expected total from one read and storing it after another would let a
      // sale settled in between fall down the gap between them.
      final summary = await _summarise(tx, shift);
      final variance = summary.varianceAgainst(countedCash);

      final closeClientId = _config.mode.syncsSalesToPlatform &&
              shift.clientTransactionId != null
          ? const Uuid().v4()
          : null;
      final rows = await tx.execute(
        Sql.named('''
            UPDATE pos_shifts SET
              closed_at           = now(),
              closed_by           = @staff,
              counted_cash_minor  = @counted,
              expected_cash_minor = @expected,
              variance_minor      = @variance,
              closing_note        = @note,
              close_client_transaction_id = @closeClient
            WHERE id = @id AND closed_at IS NULL
            RETURNING closed_at
          '''),
        parameters: {
          'id': shift.id,
          'staff': by.id,
          'counted': countedCash.minor,
          'expected': summary.expectedCash.minor,
          'variance': variance.minor,
          'note': note,
          'closeClient': closeClientId,
        },
      );

      // Conditional on `closed_at IS NULL`, so a second cash-up cannot
      // overwrite the first one's numbers.
      if (rows.isEmpty) return null;

      if (closeClientId != null) {
        await _enqueueSync(
          tx,
          eventType: 'shift_close',
          sourceId: shift.id,
          clientTransactionId: closeClientId,
        );
        onQueued?.call();
      }

      return ShiftClose(
        summary: summary,
        countedCash: countedCash,
        variance: variance,
        closedAt: rows.first[0] as DateTime,
      );
    });

    if (closed == null) {
      throw StateError(
        'That shift was already closed — probably from another till. Reprint '
        'the last Z report rather than counting again.',
      );
    }
    return closed;
  }

  Future<ShiftSummary> _summarise(TxSession tx, PosShift shift) async {
    final orders = await tx.execute(
      Sql.named(
        // `::bigint` matters: sum() over a bigint column returns *numeric* in
        // PostgreSQL, which arrives as a string and blows up the cast. The
        // totals are minor units and always fit, so narrowing is safe.
        '''
        SELECT
          count(*) FILTER (WHERE status <> 'VOIDED'),
          coalesce(sum(total_minor)    FILTER (WHERE status <> 'VOIDED'), 0)::bigint,
          coalesce(sum(subtotal_minor) FILTER (WHERE status <> 'VOIDED'), 0)::bigint,
          coalesce(sum(discount_minor) FILTER (WHERE status <> 'VOIDED'), 0)::bigint,
          coalesce(sum(service_minor)  FILTER (WHERE status <> 'VOIDED'), 0)::bigint,
          coalesce(sum(vat_minor)      FILTER (WHERE status <> 'VOIDED'), 0)::bigint,
          coalesce(sum(total_minor)    FILTER (WHERE status =  'VOIDED'), 0)::bigint,
          count(*) FILTER (WHERE status = 'VOIDED')
        FROM pos_orders WHERE shift_id = @shift
        ''',
      ),
      parameters: {'shift': shift.id},
    );

    // Grouped by label rather than by tender_type_id: the label is what the
    // cashier chose and what the Z report has to read back to them. Two ids
    // sharing a label would be one line on the report either way.
    final tenders = await tx.execute(
      Sql.named('''
        SELECT p.label, count(*), coalesce(sum(p.amount_minor), 0)::bigint,
               p.tender_type_id, bool_or(p.counts_as_cash)
        FROM pos_order_payments p
        JOIN pos_orders o ON o.id = p.order_id
        WHERE o.shift_id = @shift
        GROUP BY p.label, p.tender_type_id
        ORDER BY p.label
      '''),
      parameters: {'shift': shift.id},
    );

    // Refunds are their own table and their own shift stamp: a refund given on
    // Tuesday against Monday's sale belongs to Tuesday's drawer, which is the
    // shift that is short the money.
    final refunds = await tx.execute(
      Sql.named(
        'SELECT count(*), coalesce(sum(total_minor), 0)::bigint '
        'FROM pos_refunds WHERE shift_id = @shift',
      ),
      parameters: {'shift': shift.id},
    );

    final cashRefunds = await tx.execute(
      Sql.named(
        'SELECT coalesce(sum(p.amount_minor) FILTER (WHERE p.counts_as_cash), 0)::bigint '
        'FROM pos_refund_payments p '
        'JOIN pos_refunds r ON r.id = p.refund_id '
        'WHERE r.shift_id = @shift',
      ),
      parameters: {'shift': shift.id},
    );

    // Read here rather than left to the screen. `expectedCash` is float plus
    // cash taken plus paid in less paid out, so a summary without these would
    // report a shortage every time somebody paid a supplier out of the till —
    // silently, and only on the shifts where it mattered.
    final movements = await tx.execute(
      Sql.named(
        'SELECT kind, coalesce(sum(amount_minor), 0)::bigint, count(*) '
        'FROM pos_cash_movements WHERE shift_id = @shift GROUP BY kind',
      ),
      parameters: {'shift': shift.id},
    );

    var paidIn = Money.zero;
    var paidOut = Money.zero;
    var opens = 0;
    for (final raw in movements) {
      final amount = Money(raw[1]! as int);
      switch (CashMovementKind.fromWire(raw[0]! as String)) {
        case CashMovementKind.payIn:
        case CashMovementKind.floatAdjust:
          paidIn += amount;
        case CashMovementKind.payOut:
          paidOut += amount;
        case CashMovementKind.drawerOpen:
          opens += raw[2]! as int;
        // A kind this build does not know moves nothing, so it cannot push the
        // expected drawer in a direction that costs anybody money.
        case null:
          break;
      }
    }

    final row = orders.first;
    return ShiftSummary(
      movements: CashMovementTotals(
        paidIn: paidIn,
        paidOut: paidOut,
        drawerOpens: opens,
        // Totals only. The list itself is a separate read, because the cash-up
        // needs the sums and only the movements screen needs the rows.
        movements: const [],
      ),
      shift: shift,
      // Voided orders are excluded from every sales figure and counted
      // separately. They took no money; they are on the report because the
      // food was made and somebody has to answer for it.
      saleCount: row[0] as int,
      gross: Money(row[1] as int),
      subtotal: Money(row[2] as int),
      discounts: Money(row[3] as int),
      service: Money(row[4] as int),
      vat: Money(row[5] as int),
      voids: Money(row[6] as int),
      voidCount: row[7] as int,
      refunds: Money(refunds.first[1] as int),
      cashRefunded: Money(cashRefunds.first[0] as int),
      refundCount: refunds.first[0] as int,
      tenders: [
        for (final row in tenders)
          ShiftTenderTotal(
            label: row[0] as String,
            count: row[1] as int,
            amount: Money(row[2] as int),
            // Grouped by type as well as label, so the drawer's cash is found
            // by what the method is rather than by what it is called.
            typeId: row[3] as int?,
            // From the payment row, not from today's tender configuration. A
            // business that changes what counts as cash must not change what
            // a shift closed last week said the drawer should have held.
            countsAsCash: (row[4] as bool?) ?? false,
          ),
      ],
    );
  }

  PosShift _shift(ResultRow row, {String? clientTransactionId}) => PosShift(
    id: row[0] as int,
    openedAt: row[1] as DateTime,
    openingFloat: Money(row[2] as int),
    openedByName: row[3] as String,
    closedAt: row[4] as DateTime?,
    openedById: row[5] as int?,
    clientTransactionId: clientTransactionId,
  );

  Future<void> _enqueueSync(
    TxSession tx, {
    required String eventType,
    required int sourceId,
    required String clientTransactionId,
  }) => tx.execute(
    Sql.named('''
      INSERT INTO pos_sync_outbox
        (business_id, branch_id, event_type, source_id, client_transaction_id)
      VALUES (@business, @branch, @type, @source, @client)
      ON CONFLICT (business_id, client_transaction_id) DO NOTHING
    '''),
    parameters: {
      'business': _businessId,
      'branch': _branchId,
      'type': eventType,
      'source': sourceId,
      'client': clientTransactionId,
    },
  );
}
