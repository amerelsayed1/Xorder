import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/business_day.dart';
import '../../domain/models/permissions.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';

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
    required PosDatabase database,
    required this._config,
    required this._restaurantId,
    required this._branchId,
    required this._terminalId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig _config;
  final int _restaurantId;
  final int _branchId;
  final String _terminalId;

  static const _selectShift = '''
    SELECT s.id, s.opened_at, s.opening_float_minor, st.name, s.closed_at,
           s.opened_by
    FROM pos_shifts s JOIN pos_staff st ON st.id = s.opened_by
  ''';

  @override
  Future<PosShift?> current() async {
    final rows = await _db.query(
      _config,
      '$_selectShift WHERE s.terminal_id::text = @terminal AND s.closed_at IS NULL',
      parameters: {'terminal': _terminalId},
    );
    return rows.isEmpty ? null : _shift(rows.first);
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

    final rows = await _db.query(
      _config,
      'INSERT INTO pos_shifts '
      '  (restaurant_id, branch_id, terminal_id, opened_by, opening_float_minor) '
      'VALUES (@restaurant, @branch, @terminal, @staff, @float) '
      'RETURNING id, opened_at',
      parameters: {
        'restaurant': _restaurantId,
        'branch': _branchId,
        'terminal': _terminalId,
        'staff': by.id,
        'float': openingFloat.minor,
      },
    );

    return PosShift(
      id: rows.first[0] as int,
      openedAt: rows.first[1] as DateTime,
      openingFloat: openingFloat,
      openedByName: by.name,
      openedById: by.id,
    );
  }

  @override
  Future<ShiftSummary> summarise(PosShift shift) =>
      _db.runTx(_config, (tx) => _summarise(tx, shift));

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

      final rows = await tx.execute(
        Sql.named('''
            UPDATE pos_shifts SET
              closed_at           = now(),
              closed_by           = @staff,
              counted_cash_minor  = @counted,
              expected_cash_minor = @expected,
              variance_minor      = @variance,
              closing_note        = @note
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
        },
      );

      // Conditional on `closed_at IS NULL`, so a second cash-up cannot
      // overwrite the first one's numbers.
      if (rows.isEmpty) return null;

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
            // restaurant that changes what counts as cash must not change what
            // a shift closed last week said the drawer should have held.
            countsAsCash: (row[4] as bool?) ?? false,
          ),
      ],
    );
  }

  PosShift _shift(ResultRow row) => PosShift(
    id: row[0] as int,
    openedAt: row[1] as DateTime,
    openingFloat: Money(row[2] as int),
    openedByName: row[3] as String,
    closedAt: row[4] as DateTime?,
    openedById: row[5] as int?,
  );
}
