import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/business_day.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/sales_report.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';
import 'postgres_order_history_repository.dart';
import 'postgres_orders_repository.dart' show PosWriteContext;

/// The one INSERT that puts a row in `pos_cash_movements`.
///
/// **Extracted because there is now a second writer.** A supplier paid out of
/// the till drawer has to record its `pay_out` in the *same transaction* as the
/// payment, and [PostgresCashMovementsRepository.record] opens its own
/// connection — so the back office cannot call it from inside that transaction.
///
/// The rejected alternative was a second INSERT written out in
/// `postgres_supplier_invoices_repository.dart`. That is how the drawer-open
/// normalisation and the refusal of a movement of nothing come to exist in one
/// place and not the other, and how a column added to this table gets set by
/// one writer and left null by the other.
abstract final class CashMovementWrite {
  static const sql =
      'INSERT INTO pos_cash_movements (restaurant_id, branch_id, terminal_id, '
      '  shift_id, business_day_id, kind, amount_minor, reason_id, note, '
      '  staff_id, approved_by_id, client_transaction_id) '
      'VALUES (@restaurant, @branch, @terminal, @shift, @day, @kind, @amount, '
      '  @reason, @note, @staff, @approvedBy, @client) '
      'RETURNING id, occurred_at';

  /// What actually gets stored for [kind].
  ///
  /// Opening the drawer moves nothing, and migration 14 refuses a row that
  /// claims otherwise. Normalised here rather than trusted from the caller,
  /// because a screen passing the till's float by accident would otherwise
  /// surface as a constraint violation instead of a zero.
  static Money normalise(CashMovementKind kind, Money amount) =>
      kind == CashMovementKind.drawerOpen ? amount.copyWith(minor: 0) : amount;

  /// Throws if [amount] is not something that can move. Called by both writers
  /// before the INSERT, so the message names the act rather than a constraint.
  static void refuseNothing(CashMovementKind kind, Money amount) {
    if (kind != CashMovementKind.drawerOpen && amount.minor <= 0) {
      throw ArgumentError('A ${kind.wire} of nothing is not a movement.');
    }
  }

  static Map<String, Object?> parameters({
    required int restaurantId,
    required int branchId,
    required String terminalId,
    required int shiftId,
    required CashMovementKind kind,
    required Money amount,
    required int staffId,
    int? businessDayId,
    int? reasonId,
    String? note,
    int? approvedById,
    String? clientTransactionId,
  }) => {
    'restaurant': restaurantId,
    'branch': branchId,
    'terminal': terminalId,
    'shift': shiftId,
    'day': businessDayId,
    'kind': kind.wire,
    'amount': amount.minor,
    'reason': reasonId,
    'note': note,
    'staff': staffId,
    // Both people on the row when there were two, as everywhere else.
    'approvedBy': approvedById,
    'client': clientTransactionId,
  };
}

/// Money into and out of the drawer that is not a sale.
///
/// Append-only by grant: the till holds `SELECT, INSERT` and nothing more. A
/// pay-out already recorded is a record of money that left, and correcting one
/// is a second movement, not an edit of the first.
class PostgresCashMovementsRepository implements CashMovementsRepository {
  const PostgresCashMovementsRepository({
    required PosDatabase database,
    required this.config,
    required this.context,
    this.currency = 'EGP',
    this.exponent = 2,
    this.onQueued,
  }) : _db = database;

  /// Told after a movement is recorded — see
  /// `PostgresOrdersRepository.onQueued`.
  final void Function()? onQueued;

  final PosDatabase _db;
  final DeploymentConfig config;
  final PosWriteContext context;
  final String currency;
  final int exponent;

  Money _money(Object? minor) =>
      Money(minor is int ? minor : 0, currency: currency, exponent: exponent);

  static const _columns = '''
        m.id, m.kind, m.amount_minor, m.occurred_at, m.note,
        reason.name_en, reason.name_ar, staff.name, approver.name''';

  static const _joins = '''
        LEFT JOIN pos_reason_codes AS reason ON reason.id = m.reason_id
        LEFT JOIN pos_staff AS staff ON staff.id = m.staff_id
        LEFT JOIN pos_staff AS approver ON approver.id = m.approved_by_id''';

  CashMovement _movement(List<Object?> row) => CashMovement(
    id: row[0]! as int,
    // A kind this build does not know is read as a drawer opening: it moves
    // nothing, so a total built from it cannot be wrong in a direction that
    // costs anybody money.
    kind:
        CashMovementKind.fromWire(row[1]! as String) ??
        CashMovementKind.drawerOpen,
    amount: _money(row[2]),
    occurredAt: (row[3]! as DateTime).toLocal(),
    note: row[4] as String?,
    reasonName: row[5] as String?,
    reasonNameAr: row[6] as String?,
    staffName: row[7] as String?,
    approvedByName: row[8] as String?,
    // Only [between] selects it.
    terminalName: row.length > 9 ? row[9] as String? : null,
  );

  @override
  Future<CashMovement> record({
    required CashMovementKind kind,
    required Money amount,
    required PosStaff by,
    required int shiftId,
    int? reasonId,
    String? note,
    Approval? approval,
    int? businessDayId,
  }) async {
    // A drawer opening asks its own key, not `cash.movement`: it is the one
    // drawer act that moves no money, which is why a dishonest cashier wants
    // it most — and a key of its own is only worth something if the write
    // asks for it.
    final approvedBy = Authorization.require(
      by,
      kind == CashMovementKind.drawerOpen
          ? PosCapability.cashOpenWithoutSale
          : PosCapability.cashMovement,
      approval: approval,
    ).approvedBy;
    final stored = CashMovementWrite.normalise(kind, amount);
    CashMovementWrite.refuseNothing(kind, stored);

    // A drawer opening is an audit event but not a platform cash movement:
    // BE-009 only accepts money in or out.  Every money-moving row gets an
    // idempotency key and its outbox claim in the same transaction.
    final clientId = config.mode.syncsSalesToPlatform &&
            kind != CashMovementKind.drawerOpen
        ? const Uuid().v4()
        : null;
    final rows = await _db.runTx(config, (tx) async {
      final inserted = await tx.execute(
        Sql.named(CashMovementWrite.sql),
        parameters: CashMovementWrite.parameters(
          restaurantId: context.restaurantId,
          branchId: context.branchId,
          terminalId: context.terminalId,
          shiftId: shiftId,
          businessDayId: businessDayId,
          kind: kind,
          amount: stored,
          reasonId: reasonId,
          note: note,
          staffId: by.id,
          approvedById: approvedBy?.id,
          clientTransactionId: clientId,
        ),
      );
      if (clientId != null) {
        await tx.execute(
          Sql.named('''
            INSERT INTO pos_sync_outbox
              (restaurant_id, branch_id, event_type, source_id, client_transaction_id)
            VALUES (@restaurant, @branch, 'cash_movement', @source, @client)
            ON CONFLICT (restaurant_id, client_transaction_id) DO NOTHING
          '''),
          parameters: {
            'restaurant': context.restaurantId,
            'branch': context.branchId,
            'source': inserted.first[0] as int,
            'client': clientId,
          },
        );
      }
      return inserted;
    });

    onQueued?.call();
    return CashMovement(
      id: rows.first[0]! as int,
      kind: kind,
      amount: stored,
      occurredAt: (rows.first[1]! as DateTime).toLocal(),
      note: note,
      staffName: by.name,
      approvedByName: approvedBy?.name,
    );
  }

  @override
  Future<List<CashMovement>> forShift(int shiftId) async {
    final rows = await _db.query(
      config,
      'SELECT $_columns FROM pos_cash_movements AS m $_joins '
      'WHERE m.shift_id = @shift ORDER BY m.occurred_at, m.id',
      parameters: {'shift': shiftId},
    );
    return rows
        .map((raw) => _movement(raw.toList()))
        .toList(growable: false);
  }

  /// The range read Finance's expenses are made of (BO-10).
  ///
  /// **Filed by the sales list's rule, through the sales list's own SQL** —
  /// `tradingDayJoin` and `businessDateRange`, which `pos_cash_movements`
  /// can take because it carries the four columns they read. A pay-out and
  /// the sales of the night it was paid in then sit on one business date,
  /// and a date rule written a second time here would be the one that
  /// disagreed about the pay-out at 1 a.m.
  ///
  /// On the till's credential, which has read this table since migration 14.
  /// Deliberately nothing of the supplier ledger: that is the back office's,
  /// and whether a pay-out is also a supplier payment is answered there.
  @override
  Future<List<CashMovement>> between(
    ReportFilter filter, {
    Set<CashMovementKind> kinds = const {CashMovementKind.payOut},
  }) async {
    if (kinds.isEmpty) return const [];
    final range = PostgresOrderHistoryRepository.businessDateRange(
      from: filter.from,
      to: filter.to,
      alias: 'm',
    );
    final terminal = filter.terminalId;
    final where = [
      'm.restaurant_id = @restaurant',
      'm.branch_id = @branch',
      'm.kind = ANY(@kinds)',
      ...range.where,
      if (terminal != null) 'm.terminal_id::text = @terminal',
    ];
    final rows = await _db.query(
      config,
      'SELECT $_columns, term.name FROM pos_cash_movements AS m $_joins '
      'LEFT JOIN pos_terminals AS term ON term.id = m.terminal_id '
      '${PostgresOrderHistoryRepository.tradingDayJoin('m')} '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY m.occurred_at DESC, m.id DESC',
      parameters: {
        'restaurant': context.restaurantId,
        'branch': context.branchId,
        'kinds': [for (final kind in kinds) kind.wire],
        ...range.parameters,
        'terminal': ?terminal,
      },
    );
    return rows
        .map((raw) => _movement(raw.toList()))
        .toList(growable: false);
  }
}

/// What a terminal with no branch database answers with.
class UnconfiguredCashMovementsRepository implements CashMovementsRepository {
  const UnconfiguredCashMovementsRepository();

  @override
  Future<List<CashMovement>> forShift(int shiftId) async => const [];

  @override
  Future<List<CashMovement>> between(
    ReportFilter filter, {
    Set<CashMovementKind> kinds = const {CashMovementKind.payOut},
  }) async => const [];

  @override
  Future<CashMovement> record({
    required CashMovementKind kind,
    required Money amount,
    required PosStaff by,
    required int shiftId,
    int? reasonId,
    String? note,
    Approval? approval,
    int? businessDayId,
  }) async => throw StateError(
    'This terminal has nowhere to record a cash movement. It is not connected '
    'to a database, so the money must not leave the drawer on this till.',
  );
}
