import 'dart:convert';
import 'dart:typed_data';

import '../sql/sql.dart';

import '../../core/config/deployment.dart';
import '../../domain/models/business_logo.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/authorization.dart';
import '../sql/row_reads.dart';

/// Authoring the business logo on the till (XORD-021), offline installs only.
///
/// A cloud till's logo is the platform's: the bundle names it and the sync
/// downloads it (`LogoSync`), and a local upload there would be overwritten by
/// the next change on the dashboard. So [offline] false refuses, as every other
/// authoring repository does.
///
/// Same shape as the rest of the back office: capability check, one
/// transaction, the row locked, the write, and the audit row in the SAME
/// transaction. The audit row records the size and type and never the image.
class PostgresBusinessLogoRepository implements BusinessLogoRepository {
  PostgresBusinessLogoRepository({
    required this.database,
    required this.config,
    required this.businessId,
    this.branchId,
    this.terminalId,
    this.adminAvailable = true,
    this.offline = true,
  });

  final SqlDatabase database;
  final DeploymentConfig config;
  final int businessId;
  final int? branchId;
  final String? terminalId;
  final bool adminAvailable;
  final bool offline;

  AdminRefusal? _blocked(PosStaff by) {
    if (!offline) return const NotPermitted(PosCapability.brandingManage);
    if (!adminAvailable) return const AdministratorCredentialRequired();
    if (!Authorization.check(by, PosCapability.brandingManage).isAllowed) {
      return const NotPermitted(PosCapability.brandingManage);
    }
    return null;
  }

  @override
  Future<AdminResult<BusinessLogo>> save(
    Uint8List bytes, {
    required PosStaff by,
  }) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    final check = BusinessLogoRules.inspect(bytes);
    if (!check.accepted) {
      return AdminResult.refused(LogoRejected(check.refusal!));
    }
    final image = check.image!;

    return database.runTx(config, (tx) async {
      final row = await tx.execute(
        Sql.named(
          'SELECT logo_mime, length(logo_bytes) FROM pos_businesses '
          'WHERE id = @r FOR UPDATE',
        ),
        parameters: {'r': businessId},
      );
      if (row.isEmpty) {
        return const AdminResult<BusinessLogo>.refused(
          CatalogInvalid('This business is not set up on this till yet.'),
        );
      }

      // `logo_remote_url` and `logo_fetched_url` are cleared: an owner's own
      // choice is final, and a leftover platform URL would make a later sync
      // think there is something to fetch. A Uint8List is sent as `bytea`.
      final saved = await tx.execute(
        Sql.named(
          'UPDATE pos_businesses '
          '   SET logo_bytes = @bytes, logo_mime = @mime, '
          "       logo_source = 'local', logo_remote_url = NULL, "
          '       logo_fetched_url = NULL, logo_updated_at = now() '
          ' WHERE id = @r RETURNING logo_updated_at',
        ),
        parameters: {'r': businessId, 'bytes': bytes, 'mime': image.mime},
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.businessLogoSaved,
        before: row.first[0] == null
            ? null
            : {'mime': row.first[0], 'bytes': row.first[1]},
        after: {
          'mime': image.mime,
          'bytes': bytes.length,
          'width': image.width,
          'height': image.height,
        },
      );

      return AdminResult.done(
        BusinessLogo(
          bytes: bytes,
          mime: image.mime,
          source: LogoSource.local,
          updatedAt: saved.first.dateTimeOrNull(0),
        ),
      );
    });
  }

  @override
  Future<AdminResult<bool>> remove({required PosStaff by}) async {
    final blocked = _blocked(by);
    if (blocked != null) return AdminResult.refused(blocked);

    return database.runTx(config, (tx) async {
      final row = await tx.execute(
        Sql.named(
          'SELECT logo_mime, length(logo_bytes) FROM pos_businesses '
          'WHERE id = @r FOR UPDATE',
        ),
        parameters: {'r': businessId},
      );
      if (row.isEmpty || row.first[0] == null) {
        return const AdminResult.done(false);
      }

      await tx.execute(
        Sql.named(
          'UPDATE pos_businesses '
          '   SET logo_bytes = NULL, logo_mime = NULL, logo_source = NULL, '
          '       logo_remote_url = NULL, logo_fetched_url = NULL, '
          '       logo_updated_at = now() '
          ' WHERE id = @r',
        ),
        parameters: {'r': businessId},
      );

      await _audit(
        tx,
        by: by,
        action: AuditAction.businessLogoRemoved,
        before: {'mime': row.first[0], 'bytes': row.first[1]},
        after: null,
      );
      return const AdminResult.done(true);
    });
  }

  Future<void> _audit(
    TxSession tx, {
    required PosStaff by,
    required String action,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) => tx.execute(
    Sql.named(
      'INSERT INTO pos_audit_events (business_id, branch_id, terminal_id, '
      '  actor_user_id, actor_name, action, entity_type, entity_id, '
      '  before_value, after_value) '
      'VALUES (@r, @branch, @terminal, @actor, @actorName, @action, '
      '        @entityType, @entityId, @before::jsonb, @after::jsonb)',
    ),
    parameters: {
      'r': businessId,
      'branch': branchId,
      'terminal': terminalId,
      'actor': by.id,
      'actorName': by.name,
      'action': action,
      'entityType': AuditAction.entityBusinessLogo,
      'entityId': '$businessId',
      'before': before == null ? null : jsonEncode(before),
      'after': after == null ? null : jsonEncode(after),
    },
  );
}
