import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/business_day.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';
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
      '  staff_id, approved_by_id) '
      'VALUES (@restaurant, @branch, @terminal, @shift, @day, @kind, @amount, '
      '  @reason, @note, @staff, @approvedBy) RETURNING id, occurred_at';

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
  }) : _db = database;

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
  );

  @override
  Future<CashMovement> record({
    required CashMovementKind kind,
    required Money amount,
    required PosStaff by,
    required int shiftId,
    int? reasonId,
    String? note,
    PosStaff? approvedBy,
    int? businessDayId,
  }) async {
    final stored = CashMovementWrite.normalise(kind, amount);
    CashMovementWrite.refuseNothing(kind, stored);

    final rows = await _db.query(
      config,
      CashMovementWrite.sql,
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
      ),
    );

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
}

/// What a terminal with no branch database answers with.
class UnconfiguredCashMovementsRepository implements CashMovementsRepository {
  const UnconfiguredCashMovementsRepository();

  @override
  Future<List<CashMovement>> forShift(int shiftId) async => const [];

  @override
  Future<CashMovement> record({
    required CashMovementKind kind,
    required Money amount,
    required PosStaff by,
    required int shiftId,
    int? reasonId,
    String? note,
    PosStaff? approvedBy,
    int? businessDayId,
  }) async => throw StateError(
    'This terminal has nowhere to record a cash movement. It is not connected '
    'to a database, so the money must not leave the drawer on this till.',
  );
}
