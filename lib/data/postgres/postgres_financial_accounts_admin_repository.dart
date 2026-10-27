import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/financial_account.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/models/tender_method.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';

/// Authoring financial accounts, on the till, against the branch database.
///
/// **Offline only**, for the reason [FinancialAccountsAdminRepository] gives:
/// on a cloud till the platform authors these and `BootstrapSeeder` replaces
/// them from the bundle. [adminAvailable] and [offline] are both checked here
/// as well as in the provider, because a rule that lives only in a provider is
/// a rule the next caller does not know about.
///
/// Every write follows the shape `PostgresCatalogAdminRepository` set:
/// capability check → one transaction → refuse on a broken rule →
/// `INSERT/UPDATE … RETURNING` → audit row in the SAME transaction, so a change
/// cannot commit without the record of who made it. Nothing here deletes an
/// account.
class PostgresFinancialAccountsAdminRepository
    implements FinancialAccountsAdminRepository {
  PostgresFinancialAccountsAdminRepository({
    required this.database,
    required this.config,
    required this.restaurantId,
    this.branchId,
    this.terminalId,
    this.adminAvailable = true,
    this.offline = true,
  });

  final PosDatabase database;
  final DeploymentConfig config;
  final int restaurantId;
  final int? branchId;
  final String? terminalId;
  final bool adminAvailable;
  final bool offline;

  static const _columns =
      'id, name, kind, branch_id, currency, reference_label, is_active, '
      'sort_order';

  AdminRefusal? _blocked(PosStaff by) {
    if (!offline) return const NotPermitted(PosCapability.financeAccounts);
    if (!adminAvailable) return const AdministratorCredentialRequired();
    if (!Authorization.check(by, PosCapability.financeAccounts).isAllowed) {
      return const NotPermitted(PosCapability.financeAccounts);
    }
    return null;
  }

  static AdminResult<T> _refused<T>(AccountProblem problem) =>
      AdminResult<T>.refused(AccountRefused(problem));

  static FinancialAccount _account(List<Object?> row) => FinancialAccount(
    id: row[0]! as int,
    name: row[1]! as String,
    kind: AccountKind.fromWire(row[2] as String?) ?? AccountKind.cash,
    branchId: row[3] as int?,
    currency: row[4] as String?,
    referenceLabel: row[5] as String?,
    isActive: row[6]! as bool,
    sortOrder: row[7]! as int,
  );

  @override
  Future<AdminResult<FinancialAccount>> saveAccount(
    FinancialAccount account, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    final name = account.name.trim();
    final reference = account.referenceLabel?.trim();
    if (name.isEmpty) return _refused(AccountProblem.nameMissing);
    if (AccountRules.looksLikeNumber(name)) {
      return _refused(AccountProblem.nameLooksLikeNumber);
    }
    if (AccountRules.referenceLooksLikeNumber(reference)) {
      return _refused(AccountProblem.referenceLooksLikeNumber);
    }

    return database.runTx(config, (tx) async {
      // A branch is this restaurant's own, or the account cannot exist.
      final tiedTo = account.branchId;
      if (tiedTo != null) {
        final branch = await tx.execute(
          Sql.named(
            'SELECT 1 FROM pos_branches WHERE id = @b AND restaurant_id = @r',
          ),
          parameters: {'b': tiedTo, 'r': restaurantId},
        );
        if (branch.isEmpty) return _refused(AccountProblem.branchUnknown);
      }

      // The label an owner says out loud must be unambiguous.
      final clash = await tx.execute(
        Sql.named(
          'SELECT 1 FROM pos_financial_accounts '
          'WHERE restaurant_id = @r AND lower(btrim(name)) = lower(@name) '
          '  AND id <> @id',
        ),
        parameters: {'r': restaurantId, 'name': name, 'id': account.id},
      );
      if (clash.isNotEmpty) return _refused(AccountProblem.nameTaken);

      Map<String, Object?>? before;

      if (account.id != 0) {
        final existing = await tx.execute(
          Sql.named(
            'SELECT $_columns FROM pos_financial_accounts '
            'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
          ),
          parameters: {'id': account.id, 'r': restaurantId},
        );
        if (existing.isEmpty) {
          return const AdminResult<FinancialAccount>.refused(
            EditedElsewhere(0),
          );
        }
        final was = _account(existing.first);
        before = {
          'name': was.name,
          'kind': was.kind.wire,
          'branch_id': was.branchId,
          'is_active': was.isActive,
        };

        // An account that is somebody's default cannot be switched off, or
        // tied to a branch other than the one(s) that default is for.
        final switchedOff = was.isActive && !account.isActive;
        final retied = tiedTo != null && tiedTo != was.branchId;
        if (switchedOff || retied) {
          final held = await tx.execute(
            Sql.named(
              'SELECT 1 FROM pos_tender_account_defaults '
              'WHERE financial_account_id = @id '
              '  AND (@off::boolean OR branch_key <> @tied::bigint) LIMIT 1',
            ),
            parameters: {
              'id': account.id,
              'off': switchedOff,
              'tied': tiedTo ?? 0,
            },
          );
          if (held.isNotEmpty) return _refused(AccountProblem.accountIsDefault);
        }
      }

      final parameters = <String, Object?>{
        'r': restaurantId,
        'name': name,
        'kind': account.kind.wire,
        'branch': tiedTo,
        'reference': (reference == null || reference.isEmpty)
            ? null
            : reference,
        'active': account.isActive,
        'sort': account.sortOrder,
      };

      final rows = account.id == 0
          ? await tx.execute(
              Sql.named(
                'INSERT INTO pos_financial_accounts (restaurant_id, name, kind, '
                '  branch_id, reference_label, is_active, sort_order) '
                'VALUES (@r, @name, @kind, @branch, @reference, @active, @sort) '
                'RETURNING $_columns',
              ),
              parameters: parameters,
            )
          : await tx.execute(
              Sql.named(
                'UPDATE pos_financial_accounts SET name = @name, kind = @kind, '
                '  branch_id = @branch, reference_label = @reference, '
                '  is_active = @active, sort_order = @sort '
                'WHERE id = @id AND restaurant_id = @r RETURNING $_columns',
              ),
              parameters: {...parameters, 'id': account.id},
            );

      if (rows.isEmpty) {
        return const AdminResult<FinancialAccount>.refused(EditedElsewhere(0));
      }

      final saved = _account(rows.first);
      await _audit(
        tx,
        by: by,
        action: AuditAction.financialAccountSaved,
        entityType: AuditAction.entityFinancialAccount,
        entityId: '${saved.id}',
        before: before,
        after: {
          'name': saved.name,
          'kind': saved.kind.wire,
          'branch_id': saved.branchId,
          'is_active': saved.isActive,
        },
      );

      return AdminResult.done(saved);
    });
  }

  @override
  Future<AdminResult<TenderAccountDefault?>> setDefault({
    required int tenderTypeId,
    required int? branchId,
    required int? accountId,
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    return database.runTx(config, (tx) async {
      final method = await tx.execute(
        Sql.named(
          'SELECT kind FROM pos_tender_types '
          'WHERE id = @t AND restaurant_id = @r',
        ),
        parameters: {'t': tenderTypeId, 'r': restaurantId},
      );
      if (method.isEmpty) return _refused(AccountProblem.methodUnknown);
      // A kind this build does not know falls to `other` (any account will do).
      final methodKind = TenderKind.fromWire(method.first[0] as String?);

      if (branchId != null) {
        final branch = await tx.execute(
          Sql.named(
            'SELECT 1 FROM pos_branches WHERE id = @b AND restaurant_id = @r',
          ),
          parameters: {'b': branchId, 'r': restaurantId},
        );
        if (branch.isEmpty) return _refused(AccountProblem.branchUnknown);
      }

      final branchKey = branchId ?? 0;

      final current = await tx.execute(
        Sql.named(
          'SELECT financial_account_id FROM pos_tender_account_defaults '
          'WHERE tender_type_id = @t AND branch_key = @k FOR UPDATE',
        ),
        parameters: {'t': tenderTypeId, 'k': branchKey},
      );
      final was = current.isEmpty ? null : current.first[0]! as int;

      if (accountId == null) {
        if (was != null) {
          await tx.execute(
            Sql.named(
              'DELETE FROM pos_tender_account_defaults '
              'WHERE tender_type_id = @t AND branch_key = @k',
            ),
            parameters: {'t': tenderTypeId, 'k': branchKey},
          );
          await _auditDefault(
            tx,
            by: by,
            tenderTypeId: tenderTypeId,
            branchId: branchId,
            from: was,
            to: null,
          );
        }
        return const AdminResult<TenderAccountDefault?>.done(null);
      }

      final rows = await tx.execute(
        Sql.named(
          'SELECT $_columns FROM pos_financial_accounts '
          'WHERE id = @a AND restaurant_id = @r',
        ),
        parameters: {'a': accountId, 'r': restaurantId},
      );
      if (rows.isEmpty) return _refused(AccountProblem.accountUnavailable);

      final problem = AccountRules.defaultProblem(
        _account(rows.first),
        branchId: branchId,
        method: methodKind,
      );
      if (problem != null) return _refused(problem);

      await tx.execute(
        Sql.named(
          'INSERT INTO pos_tender_account_defaults (restaurant_id, '
          '  tender_type_id, branch_id, branch_key, financial_account_id) '
          'VALUES (@r, @t, @b, @k, @a) '
          'ON CONFLICT (tender_type_id, branch_key) DO UPDATE '
          '  SET financial_account_id = EXCLUDED.financial_account_id',
        ),
        parameters: {
          'r': restaurantId,
          't': tenderTypeId,
          'b': branchId,
          'k': branchKey,
          'a': accountId,
        },
      );

      if (was != accountId) {
        await _auditDefault(
          tx,
          by: by,
          tenderTypeId: tenderTypeId,
          branchId: branchId,
          from: was,
          to: accountId,
        );
      }

      return AdminResult.done(
        TenderAccountDefault(
          tenderTypeId: tenderTypeId,
          branchId: branchId,
          accountId: accountId,
        ),
      );
    });
  }

  Future<void> _auditDefault(
    TxSession tx, {
    required PosStaff by,
    required int tenderTypeId,
    required int? branchId,
    required int? from,
    required int? to,
  }) => _audit(
    tx,
    by: by,
    action: AuditAction.tenderAccountDefaultSaved,
    entityType: AuditAction.entityTenderAccountDefault,
    entityId: '$tenderTypeId:${branchId ?? 0}',
    before: {'financial_account_id': from},
    after: {'financial_account_id': to},
  );

  Future<void> _audit(
    TxSession tx, {
    required PosStaff by,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) => tx.execute(
    Sql.named(
      'INSERT INTO pos_audit_events (restaurant_id, branch_id, terminal_id, '
      '  actor_user_id, actor_name, action, entity_type, entity_id, '
      '  before_value, after_value) '
      'VALUES (@r, @branch, @terminal, @actor, @actorName, @action, '
      '        @entityType, @entityId, @before::jsonb, @after::jsonb)',
    ),
    parameters: {
      'r': restaurantId,
      'branch': branchId,
      'terminal': terminalId,
      'actor': by.id,
      'actorName': by.name,
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'before': before == null ? null : jsonEncode(before),
      'after': after == null ? null : jsonEncode(after),
    },
  );
}
