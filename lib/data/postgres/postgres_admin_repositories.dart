import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/security/pin_hash.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/authorization.dart';
import 'pos_database.dart';

/// The Management section's data layer.
///
/// **The capability check is here, not only in the widgets.** A greyed-out
/// button is a courtesy to the person looking at it; this is the thing that
/// makes it true. Both ask [Authorization], so the screen can never offer an
/// action the write then rejects — only the harmless reverse.
///
/// Every write and its audit row go through one [PosDatabase.runTx]. A price
/// change that committed while its ledger entry did not would be a change
/// nobody can be asked about, which is the failure the ledger exists to
/// prevent.
class _AdminContext {
  const _AdminContext({
    required this.database,
    required this.config,
    required this.restaurantId,
    this.branchId,
    this.terminalId,
    this.shiftId,
  });

  final PosDatabase database;
  final DeploymentConfig config;
  final int restaurantId;
  final int? branchId;
  final String? terminalId;
  final int? shiftId;

  /// Write one ledger row on an open transaction.
  ///
  /// Takes the session rather than opening its own, so it cannot commit
  /// separately from the change it describes.
  Future<void> audit(
    TxSession tx, {
    required PosStaff by,
    required String action,
    required String entityType,
    PosStaff? approvedBy,
    String? entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String? reason,
  }) => tx.execute(
    Sql.named(
      'INSERT INTO pos_audit_events (restaurant_id, branch_id, terminal_id, shift_id, '
      '  actor_staff_id, actor_name, approved_by_id, approved_by_name, action, '
      '  entity_type, entity_id, before_value, after_value, reason) '
      'VALUES (@restaurant, @branch, @terminal, @shift, @actorId, @actorName, '
      '  @approverId, @approverName, @action, @entityType, @entityId, '
      // Cast rather than trusting the driver to infer jsonb from a string.
      '  @before::jsonb, @after::jsonb, @reason)',
    ),
    parameters: {
      'restaurant': restaurantId,
      'branch': branchId,
      'terminal': terminalId,
      'shift': shiftId,
      'actorId': by.id,
      'actorName': by.name,
      'approverId': approvedBy?.id,
      'approverName': approvedBy?.name,
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'before': before == null ? null : jsonEncode(before),
      'after': after == null ? null : jsonEncode(after),
      'reason': reason,
    },
  );
}

/// The columns [roleFromRow] expects, in order. Shared with the directory
/// repositories, which join the same row onto a member of staff.
const roleColumns = 'id, code, name_en, name_ar, capabilities, is_system';

/// The same columns aliased to `r`, for the queries that hang a role off a
/// member of staff. `pos_staff` and `pos_roles` both have an `id`, so an
/// unprefixed list is ambiguous the moment the two are joined.
const joinedRoleColumns =
    'r.id, r.code, r.name_en, r.name_ar, r.capabilities, r.is_system';

PosRole roleFromRow(List<Object?> row, [int offset = 0]) => PosRole(
  id: row[offset] as int,
  code: row[offset + 1] as String,
  nameEn: row[offset + 2] as String,
  nameAr: row[offset + 3] as String?,
  capabilities: PosCapability.canonicalAll(
    (row[offset + 4] as List).cast<String>(),
  ),
  isSystem: row[offset + 5] as bool,
);

/// A role row, or null when the staff member has none. The join is a LEFT one,
/// so every column arrives null together.
PosRole? optionalRoleFromRow(List<Object?> row, int offset) =>
    row[offset] == null ? null : roleFromRow(row, offset);

/// Reading roles is a TILL act; editing them is an administrator's.
///
/// Every sign-in reads this table — the permission gate has to know what the
/// person who just entered a PIN may do — so `all()` runs on the till's own
/// credential. Saving and deleting run on the administrator connection, which
/// exists only while somebody is in the back office.
class PostgresRolesRepository implements RolesRepository {
  PostgresRolesRepository({
    required PosDatabase database,
    required DeploymentConfig config,
    required int restaurantId,
    PosDatabase? readDatabase,
    DeploymentConfig? readConfig,
    this.adminAvailable = true,
    int? branchId,
    String? terminalId,
  }) : _c = _AdminContext(
         database: database,
         config: config,
         restaurantId: restaurantId,
         branchId: branchId,
         terminalId: terminalId,
       ),
       _read = _AdminContext(
         // Falls back to the write context so tests and the CLI keep working
         // on one connection; production passes the till's.
         database: readDatabase ?? database,
         config: readConfig ?? config,
         restaurantId: restaurantId,
         branchId: branchId,
         terminalId: terminalId,
       );

  final _AdminContext _c;

  /// The till credential. Reads only.
  final _AdminContext _read;

  /// Whether an administrator password has been supplied this session.
  final bool adminAvailable;

  @override
  Future<List<PosRole>> all() async {
    final rows = await _read.database.query(
      _read.config,
      'SELECT $roleColumns FROM pos_roles WHERE restaurant_id = @r ORDER BY id',
      parameters: {'r': _read.restaurantId},
    );
    return [for (final row in rows) roleFromRow(row)];
  }

  @override
  Future<AdminResult<PosRole>> save(
    PosRole role, {
    required PosStaff by,
  }) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    final decision = Authorization.check(by, PosCapability.staffManage);
    if (!decision.isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }

    // `editedBy` is what enforces §48: no escalating past what you hold.
    final invalid = Authorization.validateRole(role, editedBy: by);
    if (invalid != null) return AdminResult.refused(RoleNotAllowed(invalid));

    // Sorted before it is stored. The array is compared against its previous
    // value to write the audit row, and two saves that differ only in the order
    // somebody ticked the boxes must not read as a permission change.
    final capabilities = role.capabilities.toList()..sort();

    return _c.database.runTx(_c.config, (tx) async {
      if (role.id == 0) {
        final rows = await tx.execute(
          Sql.named(
            'INSERT INTO pos_roles (restaurant_id, code, name_en, name_ar, capabilities) '
            'VALUES (@r, @code, @nameEn, @nameAr, @capabilities) '
            'RETURNING $roleColumns',
          ),
          parameters: {
            'r': _c.restaurantId,
            'code': role.code,
            'nameEn': role.nameEn,
            'nameAr': role.nameAr,
            'capabilities': capabilities,
          },
        );
        final created = roleFromRow(rows.first);
        await _c.audit(
          tx,
          by: by,
          action: AuditAction.roleCreated,
          entityType: AuditAction.entityRole,
          entityId: '${created.id}',
          after: {
            'code': created.code,
            'name': created.nameEn,
            'capabilities': capabilities,
          },
        );
        return AdminResult.done(created);
      }

      // Locked for the length of the transaction. Two managers on two tills
      // editing the same role would otherwise both read the old capabilities
      // and the second write would silently discard the first.
      final existing = await tx.execute(
        Sql.named(
          'SELECT $roleColumns FROM pos_roles '
          'WHERE id = @id AND restaurant_id = @r FOR UPDATE',
        ),
        parameters: {'id': role.id, 'r': _c.restaurantId},
      );
      if (existing.isEmpty) {
        return const AdminResult.refused(EditedElsewhere(0));
      }
      final before = roleFromRow(existing.first);

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_roles SET name_en = @nameEn, name_ar = @nameAr, '
          '  capabilities = @capabilities, updated_at = now() '
          'WHERE id = @id AND restaurant_id = @r '
          'RETURNING $roleColumns',
        ),
        parameters: {
          'id': role.id,
          'r': _c.restaurantId,
          'nameEn': role.nameEn,
          'nameAr': role.nameAr,
          'capabilities': capabilities,
        },
      );
      final saved = roleFromRow(rows.first);

      await _c.audit(
        tx,
        by: by,
        action: AuditAction.roleUpdated,
        entityType: AuditAction.entityRole,
        entityId: '${saved.id}',
        before: {
          'name': before.nameEn,
          'capabilities': before.capabilities.toList()..sort(),
        },
        after: {'name': saved.nameEn, 'capabilities': capabilities},
      );
      return AdminResult.done(saved);
    });
  }

  @override
  Future<AdminResult<void>> delete(PosRole role, {required PosStaff by}) async {
    if (!adminAvailable) {
      return const AdminResult<void>.refused(AdministratorCredentialRequired());
    }

    if (!Authorization.check(by, PosCapability.staffManage).isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }
    if (role.isSystem) {
      return AdminResult.refused(RoleIsSystemDefined(role.code));
    }

    return _c.database.runTx(_c.config, (tx) async {
      // Named rather than counted. "3 people still hold this role" sends a
      // manager hunting through a list; the names are one join away.
      final held = await tx.execute(
        Sql.named(
          'SELECT name FROM pos_staff WHERE role_id = @id AND restaurant_id = @r ORDER BY name',
        ),
        parameters: {'id': role.id, 'r': _c.restaurantId},
      );
      if (held.isNotEmpty) {
        return AdminResult<void>.refused(
          RoleStillHeld([for (final row in held) row[0] as String]),
        );
      }

      await tx.execute(
        Sql.named(
          'DELETE FROM pos_roles WHERE id = @id AND restaurant_id = @r',
        ),
        parameters: {'id': role.id, 'r': _c.restaurantId},
      );
      await _c.audit(
        tx,
        by: by,
        action: AuditAction.roleDeleted,
        entityType: AuditAction.entityRole,
        entityId: '${role.id}',
        before: {
          'code': role.code,
          'name': role.nameEn,
          'capabilities': role.capabilities.toList()..sort(),
        },
      );
      return const AdminResult<void>.done(null);
    });
  }
}

const _staffColumns =
    's.id, s.name, s.username, s.capabilities, s.is_active, $joinedRoleColumns';

PosStaff _staffFrom(List<Object?> row) => PosStaff(
  id: row[0] as int,
  name: row[1] as String,
  username: row[2] as String?,
  capabilities: PosCapability.canonicalAll((row[3] as List).cast<String>()),
  isActive: row[4] as bool,
  role: optionalRoleFromRow(row, 5),
);

/// Reading the directory is a TILL act; changing it is an administrator's.
///
/// Signing in has to resolve a PIN against the staff table, and that happens at
/// the counter on the till's own credential — which holds SELECT and nothing
/// more. Creating people, moving them between roles and resetting PINs run on
/// the administrator connection, which exists only while somebody is in the
/// back office. Hence two contexts: the same repository, two credentials,
/// chosen by what the method actually does.
class PostgresStaffDirectoryRepository implements StaffDirectoryRepository {
  PostgresStaffDirectoryRepository({
    required PosDatabase database,
    required DeploymentConfig config,
    required int restaurantId,
    PosDatabase? readDatabase,
    DeploymentConfig? readConfig,
    this.adminAvailable = true,
    int? branchId,
    String? terminalId,
  }) : _c = _AdminContext(
         database: database,
         config: config,
         restaurantId: restaurantId,
         branchId: branchId,
         terminalId: terminalId,
       ),
       _read = _AdminContext(
         // Falls back to the write context so tests and the CLI keep working
         // with one connection; production passes the till's.
         database: readDatabase ?? database,
         config: readConfig ?? config,
         restaurantId: restaurantId,
         branchId: branchId,
         terminalId: terminalId,
       );

  final _AdminContext _c;

  /// The till credential. Reads only.
  final _AdminContext _read;

  /// Whether an administrator password has been supplied this session.
  final bool adminAvailable;

  static const _from =
      'FROM pos_staff s LEFT JOIN pos_roles r ON r.id = s.role_id';

  @override
  Future<List<PosStaff>> all({bool includeInactive = true}) async {
    final rows = await _read.database.query(
      _read.config,
      'SELECT $_staffColumns $_from WHERE s.restaurant_id = @r '
      '${includeInactive ? '' : 'AND s.is_active '}'
      'ORDER BY s.is_active DESC, s.name',
      parameters: {'r': _read.restaurantId},
    );
    return [for (final row in rows) _staffFrom(row)];
  }

  /// Walks every active member of staff and verifies the PIN against each.
  ///
  /// Linear on purpose: a PIN is not a username, so there is nothing to index
  /// on, and the alternative — asking who you are before asking for the PIN —
  /// is a second prompt at a counter with a queue at it. A branch has tens of
  /// staff, not thousands.
  @override
  Future<PosStaff?> byPin(String pin) async {
    final rows = await _read.database.query(
      _read.config,
      'SELECT $_staffColumns, s.pin_salt, s.pin_hash $_from '
      'WHERE s.restaurant_id = @r AND s.is_active ORDER BY s.id',
      parameters: {'r': _read.restaurantId},
    );

    // Every candidate is hashed even after a match, exactly as
    // `PostgresSessionRepository.signIn` does: returning early would make the
    // response time depend on where in the list the right person sits, which
    // over a few hundred attempts is enough to order the staff table.
    PosStaff? matched;
    for (final row in rows) {
      final matches = await PinHash.verify(
        pin,
        salt: row[11] as String,
        expected: row[12] as String,
      );
      if (matches && matched == null) matched = _staffFrom(row);
    }
    return matched;
  }

  @override
  Future<AdminResult<PosStaff>> create({
    required PosStaff by,
    required String name,
    required String username,
    required String pin,
    required int roleId,
    int? branchId,
    Set<String> directGrants = const {},
  }) async {
    if (!adminAvailable) {
      return const AdminResult<PosStaff>.refused(
        AdministratorCredentialRequired(),
      );
    }

    if (!Authorization.check(by, PosCapability.staffManage).isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }

    final salt = PinHash.newSalt();
    final hash = await PinHash.hash(pin, salt);
    final grants = directGrants.toList()..sort();

    return _c.database.runTx(_c.config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, pin_salt, '
          '  pin_hash, role_id, capabilities) '
          'VALUES (@r, @branch, @name, @username, @salt, @hash, @role, @grants) '
          'ON CONFLICT (restaurant_id, username) DO NOTHING '
          'RETURNING id',
        ),
        parameters: {
          'r': _c.restaurantId,
          'branch': branchId ?? _c.branchId,
          'name': name,
          'username': username,
          'salt': salt,
          'hash': hash,
          'role': roleId,
          'grants': grants,
        },
      );
      if (rows.isEmpty) {
        return AdminResult<PosStaff>.refused(UsernameTaken(username));
      }

      final id = rows.first[0] as int;
      // Neither the PIN nor its hash goes anywhere near the ledger. That a PIN
      // was set is the auditable fact; what it is, is not.
      await _c.audit(
        tx,
        by: by,
        action: AuditAction.staffCreated,
        entityType: AuditAction.entityStaff,
        entityId: '$id',
        after: {
          'name': name,
          'username': username,
          'role_id': roleId,
          'grants': grants,
        },
      );
      return AdminResult.done(await _readStaff(tx, id));
    });
  }

  @override
  Future<AdminResult<PosStaff>> update({
    required PosStaff by,
    required int staffId,
    String? name,
    String? username,
    int? roleId,
    Set<String>? directGrants,
    int? branchId,
  }) async {
    if (!adminAvailable) {
      return const AdminResult<PosStaff>.refused(
        AdministratorCredentialRequired(),
      );
    }

    if (!Authorization.check(by, PosCapability.staffManage).isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }

    return _c.database.runTx(_c.config, (tx) async {
      final before = await _readStaffOrNull(tx, staffId, lock: true);
      if (before == null) {
        return const AdminResult<PosStaff>.refused(EditedElsewhere(0));
      }

      final grants = directGrants?.toList()?..sort();

      // Taking `staff.manage` away from the last person who has it is the same
      // act as disabling them, as far as lock-out goes — and it happens two
      // ways: moving them to a role without it, or clearing the direct grant
      // that was carrying it. Both are checked, because a manager doing the
      // second one is not thinking about the first.
      final losingManage =
          before.can(PosCapability.staffManage) &&
          (roleId != null || directGrants != null);
      if (losingManage) {
        final targetRole = roleId == null
            ? before.role
            : await _readRole(tx, roleId);
        final keptGrants = grants ?? before.capabilities.toList();
        final stillManages =
            (targetRole?.holds(PosCapability.staffManage) ?? false) ||
            keptGrants.contains(PosCapability.staffManage);

        if (!stillManages &&
            !await _someoneElseCanManageStaff(tx, excluding: staffId)) {
          return const AdminResult<PosStaff>.refused(
            WouldLockEveryoneOut(PosCapability.staffManage),
          );
        }
      }

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_staff SET '
          '  name = coalesce(@name, name), '
          '  username = coalesce(@username, username), '
          '  role_id = coalesce(@role, role_id), '
          '  branch_id = coalesce(@branch, branch_id), '
          '  capabilities = coalesce(@grants, capabilities) '
          'WHERE id = @id AND restaurant_id = @r '
          'RETURNING id',
        ),
        parameters: {
          'id': staffId,
          'r': _c.restaurantId,
          'name': name,
          'username': username,
          'role': roleId,
          'branch': branchId,
          'grants': grants,
        },
      );
      if (rows.isEmpty) {
        return const AdminResult<PosStaff>.refused(EditedElsewhere(0));
      }

      final after = await _readStaff(tx, staffId);
      await _c.audit(
        tx,
        by: by,
        action: roleId != null && roleId != before.role?.id
            ? AuditAction.staffRoleChanged
            : AuditAction.staffUpdated,
        entityType: AuditAction.entityStaff,
        entityId: '$staffId',
        before: _staffSnapshot(before),
        after: _staffSnapshot(after),
      );
      return AdminResult.done(after);
    });
  }

  @override
  Future<AdminResult<PosStaff>> setActive({
    required PosStaff by,
    required int staffId,
    required bool isActive,
  }) async {
    if (!adminAvailable) {
      return const AdminResult<PosStaff>.refused(
        AdministratorCredentialRequired(),
      );
    }

    if (!Authorization.check(by, PosCapability.staffManage).isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }

    return _c.database.runTx(_c.config, (tx) async {
      final before = await _readStaffOrNull(tx, staffId, lock: true);
      if (before == null) {
        return const AdminResult<PosStaff>.refused(EditedElsewhere(0));
      }

      // Refused, not warned about: the screen that would put this back is the
      // screen this would make unreachable, and the remedy from there is a psql
      // prompt at a restaurant on a Sunday.
      if (!isActive && before.can(PosCapability.staffManage)) {
        final survives = await _someoneElseCanManageStaff(
          tx,
          excluding: staffId,
        );
        if (!survives) {
          return const AdminResult<PosStaff>.refused(
            WouldLockEveryoneOut(PosCapability.staffManage),
          );
        }
      }

      await tx.execute(
        Sql.named(
          'UPDATE pos_staff SET is_active = @active WHERE id = @id AND restaurant_id = @r',
        ),
        parameters: {'id': staffId, 'r': _c.restaurantId, 'active': isActive},
      );

      await _c.audit(
        tx,
        by: by,
        action: isActive
            ? AuditAction.staffReactivated
            : AuditAction.staffDisabled,
        entityType: AuditAction.entityStaff,
        entityId: '$staffId',
        before: {'is_active': before.isActive, 'name': before.name},
        after: {'is_active': isActive, 'name': before.name},
      );
      return AdminResult.done(await _readStaff(tx, staffId));
    });
  }

  @override
  Future<AdminResult<void>> resetPin({
    required PosStaff by,
    required int staffId,
    required String pin,
  }) async {
    if (!adminAvailable) {
      return const AdminResult<void>.refused(AdministratorCredentialRequired());
    }

    if (!Authorization.check(by, PosCapability.staffManage).isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }

    final salt = PinHash.newSalt();
    final hash = await PinHash.hash(pin, salt);

    return _c.database.runTx(_c.config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_staff SET pin_salt = @salt, pin_hash = @hash '
          'WHERE id = @id AND restaurant_id = @r RETURNING name',
        ),
        parameters: {
          'id': staffId,
          'r': _c.restaurantId,
          'salt': salt,
          'hash': hash,
        },
      );
      if (rows.isEmpty) {
        return const AdminResult<void>.refused(EditedElsewhere(0));
      }

      // No before and no after. That a PIN changed is the auditable fact; the
      // old value is a secret and the new one is the same secret.
      await _c.audit(
        tx,
        by: by,
        action: AuditAction.staffPinReset,
        entityType: AuditAction.entityStaff,
        entityId: '$staffId',
        after: {'name': rows.first[0] as String},
      );
      return const AdminResult<void>.done(null);
    });
  }

  /// §105 and §16 — one person's exceptions and ceilings, written whole.
  ///
  /// Delete-then-insert inside one transaction rather than a diff. A diff here
  /// would need three separate reconciliations against three tables to express
  /// what the editor already knows in full, and would get "removed" wrong,
  /// which is the case that matters: taking a DENY off somebody is the write
  /// most likely to be attempted and most damaging to half-apply.
  @override
  Future<AdminResult<PosStaff>> setGrants({
    required PosStaff by,
    required int staffId,
    required Set<int> extraRoleIds,
    required List<PermissionOverride> overrides,
    required Map<String, PermissionLimit> limits,
  }) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    if (!Authorization.check(by, PosCapability.staffManage).isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }

    // §48 again, in the one place it would otherwise be trivially avoidable.
    // Without this, a manager who cannot refund grants somebody *else* an
    // ALLOW override for refunding — which is granting a permission they do
    // not hold, through a different door.
    final granting = <String>{
      for (final override in overrides)
        if (override.effect == OverrideEffect.allow)
          PosCapability.canonical(override.capability),
    }..removeWhere(by.can);
    if (granting.isNotEmpty) {
      return AdminResult.refused(
        RoleNotAllowed(CannotGrantWhatYouLack(granting)),
      );
    }

    return _c.database.runTx(_c.config, (tx) async {
      final before = await _readStaffOrNull(tx, staffId, lock: true);
      if (before == null) return const AdminResult.refused(EditedElsewhere(0));

      await tx.execute(
        Sql.named('DELETE FROM pos_staff_roles WHERE staff_id = @s'),
        parameters: {'s': staffId},
      );
      for (final roleId in extraRoleIds) {
        // The primary role is a column, not a row here — see migration 22.
        // Writing it into both places is what makes a role change leave the
        // old one behind.
        if (roleId == before.role?.id) continue;
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_staff_roles (staff_id, role_id) VALUES (@s, @r)',
          ),
          parameters: {'s': staffId, 'r': roleId},
        );
      }

      await tx.execute(
        Sql.named(
          'DELETE FROM pos_staff_permission_overrides WHERE staff_id = @s',
        ),
        parameters: {'s': staffId},
      );
      for (final override in overrides) {
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_staff_permission_overrides '
            '  (staff_id, capability, effect, granted_by) '
            'VALUES (@s, @c, @e, @by)',
          ),
          parameters: {
            's': staffId,
            'c': PosCapability.canonical(override.capability),
            'e': override.effect.wire,
            'by': by.id == 0 ? null : by.id,
          },
        );
      }

      await tx.execute(
        Sql.named(
          "DELETE FROM pos_permission_limits WHERE restaurant_id = @r "
          "  AND subject_type = 'staff' AND subject_id = @s",
        ),
        parameters: {'r': _c.restaurantId, 's': staffId},
      );
      for (final entry in limits.entries) {
        // A limit that limits nothing is not written at all — unlimited is the
        // absence of a row, and the CHECK constraint refuses the alternative.
        if (entry.value.isUnlimited) continue;
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_permission_limits (restaurant_id, subject_type, '
            "  subject_id, limit_key, limit_bp, limit_minor, updated_by) "
            "VALUES (@r, 'staff', @s, @k, @bp, @m, @by)",
          ),
          parameters: {
            'r': _c.restaurantId,
            's': staffId,
            'k': entry.key,
            'bp': entry.value.maxBp,
            'm': entry.value.maxMinor,
            'by': by.id == 0 ? null : by.id,
          },
        );
      }

      await _c.audit(
        tx,
        by: by,
        action: AuditAction.staffGrantsChanged,
        entityType: AuditAction.entityStaff,
        entityId: '$staffId',
        after: {
          'roles': extraRoleIds.toList()..sort(),
          'allow': [
            for (final o in overrides)
              if (o.effect == OverrideEffect.allow) o.capability,
          ]..sort(),
          'deny': [
            for (final o in overrides)
              if (o.effect == OverrideEffect.deny) o.capability,
          ]..sort(),
          'limits': {
            for (final e in limits.entries)
              if (!e.value.isUnlimited)
                e.key: {'bp': e.value.maxBp, 'minor': e.value.maxMinor},
          },
        },
      );

      return AdminResult.done(await _readStaff(tx, staffId));
    });
  }

  Map<String, Object?> _staffSnapshot(PosStaff staff) => {
    'name': staff.name,
    'username': staff.username,
    'role': staff.role?.code,
    'grants': staff.capabilities.toList()..sort(),
    'is_active': staff.isActive,
  };

  Future<PosStaff> _readStaff(TxSession tx, int id) async =>
      (await _readStaffOrNull(tx, id))!;

  Future<PosStaff?> _readStaffOrNull(
    TxSession tx,
    int id, {
    bool lock = false,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_staffColumns $_from WHERE s.id = @id AND s.restaurant_id = @r'
        '${lock ? ' FOR UPDATE OF s' : ''}',
      ),
      parameters: {'id': id, 'r': _c.restaurantId},
    );
    return rows.isEmpty ? null : _staffFrom(rows.first);
  }

  Future<PosRole?> _readRole(TxSession tx, int id) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $roleColumns FROM pos_roles WHERE id = @id AND restaurant_id = @r',
      ),
      parameters: {'id': id, 'r': _c.restaurantId},
    );
    return rows.isEmpty ? null : roleFromRow(rows.first);
  }

  /// Whether anybody else active could still reach the Management screen.
  ///
  /// Asked of the database rather than of a list already in memory, because the
  /// other manager may have been disabled from a different till a second ago.
  Future<bool> _someoneElseCanManageStaff(
    TxSession tx, {
    required int excluding,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT 1 FROM pos_staff s LEFT JOIN pos_roles r ON r.id = s.role_id '
        'WHERE s.restaurant_id = @r AND s.is_active AND s.id <> @id '
        "  AND ('staff.manage' = ANY(s.capabilities) "
        "    OR 'staff.manage' = ANY(coalesce(r.capabilities, '{}'::text[]))) "
        'LIMIT 1',
      ),
      parameters: {'r': _c.restaurantId, 'id': excluding},
    );
    return rows.isNotEmpty;
  }
}

class PostgresAuditRepository implements AuditRepository {
  PostgresAuditRepository({
    required PosDatabase database,
    required DeploymentConfig config,
    required int restaurantId,
    int? branchId,
    String? terminalId,
    int? shiftId,
  }) : _c = _AdminContext(
         database: database,
         config: config,
         restaurantId: restaurantId,
         branchId: branchId,
         terminalId: terminalId,
         shiftId: shiftId,
       );

  final _AdminContext _c;

  @override
  Future<void> record({
    required PosStaff by,
    required String action,
    required String entityType,
    PosStaff? approvedBy,
    String? entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String? reason,
  }) => _c.database.runTx(
    _c.config,
    (tx) => _c.audit(
      tx,
      by: by,
      action: action,
      entityType: entityType,
      approvedBy: approvedBy,
      entityId: entityId,
      before: before,
      after: after,
      reason: reason,
    ),
  );

  @override
  Future<List<AuditEntry>> recent({
    int limit = 100,
    String? entityType,
    String? entityId,
    int? staffId,
  }) async {
    final rows = await _c.database.query(
      _c.config,
      'SELECT id, action, entity_type, entity_id, actor_staff_id, actor_name, '
      '  approved_by_id, approved_by_name, before_value, after_value, reason, occurred_at '
      'FROM pos_audit_events WHERE restaurant_id = @r '
      '  AND (@entityType::text IS NULL OR entity_type = @entityType) '
      '  AND (@entityId::text IS NULL OR entity_id = @entityId) '
      '  AND (@staffId::bigint IS NULL OR actor_staff_id = @staffId) '
      'ORDER BY occurred_at DESC, id DESC LIMIT @limit',
      parameters: {
        'r': _c.restaurantId,
        'entityType': entityType,
        'entityId': entityId,
        'staffId': staffId,
        'limit': limit,
      },
    );

    return [
      for (final row in rows)
        AuditEntry(
          id: row[0] as int,
          action: row[1] as String,
          entityType: row[2] as String,
          entityId: row[3] as String?,
          actorId: row[4] as int?,
          actorName: row[5] as String,
          approvedById: row[6] as int?,
          approvedByName: row[7] as String?,
          before: _json(row[8]),
          after: _json(row[9]),
          reason: row[10] as String?,
          occurredAt: row[11] as DateTime,
        ),
    ];
  }

  /// The driver hands `jsonb` back already decoded on some paths and as a
  /// string on others, depending on how the column was written.
  static Map<String, Object?>? _json(Object? value) => switch (value) {
    null => null,
    final Map<String, Object?> map => map,
    final Map map => map.cast<String, Object?>(),
    final String text => jsonDecode(text) as Map<String, Object?>,
    _ => null,
  };
}
