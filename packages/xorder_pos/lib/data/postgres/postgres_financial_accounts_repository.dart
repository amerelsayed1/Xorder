import '../../core/config/deployment.dart';
import '../../domain/models/financial_account.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// Reads `pos_financial_accounts` and `pos_tender_account_defaults`.
///
/// Read-only for the till, like the payment methods and for the same reason: a
/// cashier takes a payment, they do not decide where it lands. On a cloud till
/// the rows were written by `BootstrapSeeder` from the bundle; offline,
/// Management wrote them over the administrator credential.
class PostgresFinancialAccountsRepository
    implements FinancialAccountsRepository {
  const PostgresFinancialAccountsRepository({
    required PosDatabase database,
    required this.config,
    required this.businessId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int businessId;

  @override
  Future<List<FinancialAccount>> accounts({
    bool includeInactive = false,
  }) async {
    final rows = await _db.query(
      config,
      'SELECT id, name, kind, branch_id, currency, reference_label, '
      '       is_active, sort_order '
      'FROM pos_financial_accounts WHERE business_id = @r '
      '${includeInactive ? '' : 'AND is_active '}'
      'ORDER BY sort_order, id',
      parameters: {'r': businessId},
    );

    return [
      for (final row in rows)
        // A kind this build does not know is skipped, not guessed: an account
        // shown as the wrong sort of place is worse than one not shown yet.
        if (AccountKind.fromWire(row[2] as String?) case final kind?)
          FinancialAccount(
            id: row[0]! as int,
            name: row[1]! as String,
            kind: kind,
            branchId: row[3] as int?,
            currency: row[4] as String?,
            referenceLabel: row[5] as String?,
            isActive: row[6]! as bool,
            sortOrder: row[7]! as int,
          ),
    ];
  }

  @override
  Future<List<TenderAccountDefault>> defaults() async {
    final rows = await _db.query(
      config,
      'SELECT tender_type_id, branch_id, financial_account_id '
      'FROM pos_tender_account_defaults WHERE business_id = @r '
      'ORDER BY tender_type_id, branch_key',
      parameters: {'r': businessId},
    );

    return [
      for (final row in rows)
        TenderAccountDefault(
          tenderTypeId: row[0]! as int,
          branchId: row[1] as int?,
          accountId: row[2]! as int,
        ),
    ];
  }

  @override
  Future<List<PosBranch>> branches() async {
    final rows = await _db.query(
      config,
      'SELECT id, name, code FROM pos_branches '
      'WHERE business_id = @r AND is_active ORDER BY name',
      parameters: {'r': businessId},
    );

    return [
      for (final row in rows)
        PosBranch(
          id: row[0]! as int,
          name: row[1]! as String,
          code: row[2] as String?,
        ),
    ];
  }
}

/// What a till binds before it has a database: no accounts, nothing invented.
class UnconfiguredFinancialAccountsRepository
    implements FinancialAccountsRepository {
  const UnconfiguredFinancialAccountsRepository();

  @override
  Future<List<FinancialAccount>> accounts({
    bool includeInactive = false,
  }) async => const [];

  @override
  Future<List<TenderAccountDefault>> defaults() async => const [];

  @override
  Future<List<PosBranch>> branches() async => const [];
}
