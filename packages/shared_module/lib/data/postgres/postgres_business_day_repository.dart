import '../sql/sql.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/business_day.dart';
import '../../domain/repositories/repositories.dart';
import 'postgres_orders_repository.dart' show PosWriteContext;

/// The trading day, at one branch.
class PostgresBusinessDayRepository implements BusinessDayRepository {
  const PostgresBusinessDayRepository({
    required SqlDatabase database,
    required this.config,
    required this.context,
    this.currency = 'EGP',
    this.exponent = 2,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final PosWriteContext context;
  final String currency;
  final int exponent;

  static const _columns = '''
        d.id, d.business_date, d.opened_at, d.closed_at, d.forced,
        d.force_reason, d.gross_minor, d.net_minor,
        opener.name, closer.name''';

  static const _joins = '''
        LEFT JOIN pos_users AS opener ON opener.id = d.opened_by
        LEFT JOIN pos_users AS closer ON closer.id = d.closed_by''';

  Money? _money(Object? minor) => minor is int
      ? Money(minor, currency: currency, exponent: exponent)
      : null;

  BusinessDay _day(List<Object?> row) => BusinessDay(
    id: row[0]! as int,
    date: row[1]! as DateTime,
    openedAt: (row[2]! as DateTime).toLocal(),
    closedAt: (row[3] as DateTime?)?.toLocal(),
    forced: row[4] as bool? ?? false,
    forceReason: row[5] as String?,
    gross: _money(row[6]),
    net: _money(row[7]),
    openedByName: row[8] as String?,
    closedByName: row[9] as String?,
  );

  @override
  Future<BusinessDay?> current() async {
    final rows = await _db.query(
      config,
      'SELECT $_columns FROM pos_business_days AS d $_joins '
      'WHERE d.business_id = @business AND d.branch_id = @branch '
      '  AND d.closed_at IS NULL',
      parameters: {
        'business': context.businessId,
        'branch': context.branchId,
      },
    );
    return rows.isEmpty ? null : _day(rows.first.toList());
  }

  @override
  Future<BusinessDay?> lastClosed({DateTime? before}) async {
    final rows = await _db.query(
      config,
      'SELECT $_columns FROM pos_business_days AS d $_joins '
      'WHERE d.business_id = @business AND d.branch_id = @branch '
      '  AND d.closed_at IS NOT NULL '
      '  AND (@before::date IS NULL OR d.business_date < @before::date) '
      'ORDER BY d.business_date DESC LIMIT 1',
      parameters: {
        'business': context.businessId,
        'branch': context.branchId,
        'before': before == null ? null : _dateText(before),
      },
    );
    return rows.isEmpty ? null : _day(rows.first.toList());
  }

  @override
  Future<BusinessDay> open({
    required DateTime date,
    required PosStaff by,
  }) async {
    // `ON CONFLICT DO NOTHING` against the *date* key, then read back whatever
    // is open. Two tills starting the morning together is the normal case, and
    // the loser of that race wants the day the winner opened — not an error a
    // cashier has to read at 7 a.m.
    await _db.query(
      config,
      'INSERT INTO pos_business_days (business_id, branch_id, business_date, '
      '  opened_by) VALUES (@business, @branch, @date::date, @by) '
      'ON CONFLICT (business_id, branch_id, business_date) DO NOTHING',
      parameters: {
        'business': context.businessId,
        'branch': context.branchId,
        'date': _dateText(date),
        'by': by.id,
      },
    );

    final open = await current();
    if (open != null) return open;

    // The date exists but is closed, and no other day is open: reopening it
    // silently would resurrect a day somebody deliberately ended.
    throw StateError(
      'The business day for ${_dateText(date)} is already closed. '
      'Opening it again is not something a till may do.',
    );
  }

  @override
  Future<DayCloseCheck> check() async {
    final day = await current();
    if (day == null) {
      throw StateError('There is no open business day at this branch.');
    }

    final rows = await _db.query(
      config,
      // One round trip for three counts. Three queries would be three chances
      // for the state to move underneath a manager reading the list.
      '''
      SELECT
        (SELECT count(*) FROM pos_shifts s
          WHERE s.business_id = @business AND s.branch_id = @branch
            AND s.closed_at IS NULL),
        -- Every parked ticket, seated or not. `branch_id` was added to the
        -- table in migration 32 for this count: an INNER JOIN through
        -- `pos_dining_tables` was the only way to know the branch before that,
        -- and a held takeaway ticket has no table to join to — so it would have
        -- been an unpaid sale the day close could not see, closed over, and
        -- gone. The join survives as the fallback for rows parked before the
        -- migration whose table has since been deleted.
        (SELECT count(*) FROM pos_parked_tickets t
          LEFT JOIN pos_dining_tables dt ON dt.id = t.table_id
         WHERE t.business_id = @business
           AND coalesce(t.branch_id, dt.branch_id) = @branch),
        (SELECT count(*) FROM pos_orders o
          WHERE o.business_id = @business AND o.branch_id = @branch
            AND o.business_day_id = @day
            AND o.status IN ('DRAFT', 'OPEN', 'SENT_TO_KITCHEN', 'READY'))
      ''',
      parameters: {
        'business': context.businessId,
        'branch': context.branchId,
        'day': day.id,
      },
    );

    final counts = rows.first.toList();
    return DayCloseCheck(
      day: day,
      blockers: [
        for (final (kind, index) in const [
          (DayBlockerKind.openShift, 0),
          (DayBlockerKind.parkedTicket, 1),
          (DayBlockerKind.unpaidOrder, 2),
        ])
          if ((counts[index] as int? ?? 0) > 0)
            DayBlocker(kind: kind, count: counts[index]! as int),
      ],
    );
  }

  @override
  Future<BusinessDay> close({
    required BusinessDay day,
    required PosStaff by,
    bool force = false,
    String? forceReason,
  }) async {
    final reason = forceReason?.trim();
    if (force && (reason == null || reason.isEmpty)) {
      // The database refuses this too. Refusing here as well means the message
      // names the missing thing rather than surfacing a constraint name.
      throw ArgumentError('A forced close has to say why.');
    }

    return _db.runTx(config, (tx) async {
      // Totalled inside the same transaction as the close, so a sale settled
      // between reading the figure and writing it cannot land in a day whose
      // total has already been decided.
      final totals = await tx.execute(
        Sql.named(
          'SELECT coalesce(sum(total_minor), 0)::bigint, '
          '       coalesce(sum(total_minor - refunded_minor), 0)::bigint '
          'FROM pos_orders WHERE business_day_id = @day '
          "  AND status IN ('PAID', 'CLOSED', 'PARTIALLY_REFUNDED', 'REFUNDED')",
        ),
        parameters: {'day': day.id},
      );

      final closed = await tx.execute(
        Sql.named(
          'UPDATE pos_business_days '
          '   SET closed_at = now(), closed_by = @by, forced = @forced, '
          '       force_reason = @reason, gross_minor = @gross, '
          '       net_minor = @net '
          ' WHERE id = @id AND closed_at IS NULL '
          ' RETURNING id',
        ),
        parameters: {
          'id': day.id,
          'by': by.id,
          'forced': force,
          'reason': reason,
          'gross': totals.first[0],
          'net': totals.first[1],
        },
      );

      // Somebody else closed it first. Not an error worth throwing — the day
      // is closed, which is what the caller wanted.
      if (closed.isEmpty) {
        final rows = await tx.execute(
          Sql.named(
            'SELECT $_columns FROM pos_business_days AS d $_joins '
            'WHERE d.id = @id',
          ),
          parameters: {'id': day.id},
        );
        return _day(rows.first.toList());
      }

      final rows = await tx.execute(
        Sql.named(
          'SELECT $_columns FROM pos_business_days AS d $_joins '
          'WHERE d.id = @id',
        ),
        parameters: {'id': day.id},
      );
      return _day(rows.first.toList());
    });
  }

  /// `yyyy-MM-dd`, bound as text and cast in SQL. The driver has no `date`
  /// type and a `DateTime` would carry a time nobody asked about.
  static String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// What a terminal with no branch database answers with.
class UnconfiguredBusinessDayRepository implements BusinessDayRepository {
  const UnconfiguredBusinessDayRepository();

  @override
  Future<BusinessDay?> current() async => null;

  @override
  Future<BusinessDay?> lastClosed({DateTime? before}) async => null;

  @override
  Future<DayCloseCheck> check() async =>
      throw StateError('This terminal has no business day to close.');

  @override
  Future<BusinessDay> open({
    required DateTime date,
    required PosStaff by,
  }) async => throw StateError(
    'This terminal has nowhere to record a business day. It is not connected '
    'to a database.',
  );

  @override
  Future<BusinessDay> close({
    required BusinessDay day,
    required PosStaff by,
    bool force = false,
    String? forceReason,
  }) async => throw StateError(
    'This terminal has nowhere to record a business day close.',
  );
}
