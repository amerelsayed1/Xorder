import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../../core/config/deployment.dart';
import '../../core/security/pin_hash.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/authorization.dart';
import 'open_shift.dart';
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
  });

  final PosDatabase database;
  final DeploymentConfig config;
  final int restaurantId;
  final int? branchId;
  final String? terminalId;

  /// Write one ledger row on an open transaction.
  ///
  /// Takes the session rather than opening its own, so it cannot commit
  /// separately from the change it describes.
  ///
  /// [by] is null only for an act no member of staff performed — the
  /// technician's password reset — and then [actorName] says who did:
  /// `actor_user_id` is nullable for exactly this, and `actor_name` is not.
  Future<void> audit(
    TxSession tx, {
    required PosStaff? by,
    String? actorName,
    required String action,
    required String entityType,
    PosStaff? approvedBy,
    String? entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String? reason,
  }) async {
    // The drawer open when the thing happened, read on this transaction: an
    // audit row belongs to that shift even when the till has changed shifts
    // since this repository was built (see [openShiftIdFor]).
    final shiftId = await openShiftIdFor(tx, terminalId);
    await tx.execute(
      Sql.named(
        'INSERT INTO pos_audit_events (restaurant_id, branch_id, terminal_id, shift_id, '
        '  actor_user_id, actor_name, approved_by_id, approved_by_name, action, '
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
        'actorId': by?.id,
        'actorName': actorName ?? by?.name,
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
}

/// The columns [roleFromRow] expects, in order. Shared with the directory
/// repositories, which join the same row onto a member of staff.
const roleColumns = 'id, code, name_en, name_ar, capabilities, is_system';

/// The same columns aliased to `r`, for the queries that hang a role off a
/// member of staff. `pos_users` and `pos_roles` both have an `id`, so an
/// unprefixed list is ambiguous the moment the two are joined.
const joinedRoleColumns =
    'r.id, r.code, r.name_en, r.name_ar, r.capabilities, r.is_system';

/// Whether [error] is PostgreSQL saying a column does not exist (42703).
///
/// For the reads of a column a recent migration added, on a database the
/// upgrade has not reached yet — the back-office door is what upgrades an
/// installed till, so the till reads before it. Asked of the SQLSTATE and
/// not the text — a missing `password_hash` contains the word "password".
/// Not `PosDbFailure.classify(...) == query` either: that now reads 42703
/// as `query` too, but so is every other failed statement, and this is the
/// one failure the PIN-only entry in `AdminSession.setPassword` lets
/// through.
bool isUndefinedColumn(Object error) {
  final raw = error is PosDbException ? error.raw : error;
  return raw is ServerException && raw.code == '42703';
}

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
          'SELECT name FROM pos_users WHERE role_id = @id AND restaurant_id = @r ORDER BY name',
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
    this.offline = true,
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

  /// Whether this terminal owns its own staff records.
  ///
  /// **False on a cloud till, and it changes what may be written here — not
  /// whether anything may be.** `BootstrapSeeder` upserts `pos_users` from the
  /// bundle and deactivates anybody the bundle does not name, so creating,
  /// renaming, disabling or re-PINning somebody locally lasts until the next
  /// sync and then silently does not.
  ///
  /// It does **not** seed `pos_roles`, `pos_users.role_id`, `pos_user_roles`,
  /// the per-person overrides or the ceilings. Assigning a role and setting
  /// somebody's permissions are local, permanent and correct on a cloud till —
  /// which is why this refuses per *act* rather than closing the pane. Hiding
  /// the whole thing would take away the half that works.
  final bool offline;

  final _AdminContext _c;

  /// The till credential. Reads only.
  final _AdminContext _read;

  /// Whether an administrator password has been supplied this session.
  final bool adminAvailable;

  static const _from =
      'FROM pos_users s LEFT JOIN pos_roles r ON r.id = s.role_id';

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
    // The bundle owns this record — see [offline].
    if (!offline) {
      return const AdminResult<PosStaff>.refused(
        ManagedByPlatform(ManagedByPlatform.staffRecords),
      );
    }

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
      // One owner per restaurant — see [OwnerAlreadyExists]. Asked here so the
      // manager gets a sentence naming the owner; migration 42 refuses the same
      // insert with an exception if anything gets past this.
      final ownerRole = await _lockOwnerRole(tx);
      if (roleId == ownerRole) {
        final incumbent = await _activeOwnerOtherThan(
          tx,
          ownerRoleId: ownerRole!,
        );
        if (incumbent != null) {
          return AdminResult<PosStaff>.refused(OwnerAlreadyExists(incumbent));
        }
      }

      final rows = await tx.execute(
        Sql.named(
          'INSERT INTO pos_users (restaurant_id, branch_id, name, username, pin_salt, '
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
    // Per field, not per call. `role_id` is not in the bundle, so moving
    // somebody between roles on a cloud till is permanent and correct — while
    // renaming them, or changing their direct grants, is not. Refusing the
    // whole method would take away the half that works.
    final touchesPlatformOwned =
        name != null ||
        username != null ||
        directGrants != null ||
        branchId != null;
    if (!offline && touchesPlatformOwned) {
      return const AdminResult<PosStaff>.refused(
        ManagedByPlatform(ManagedByPlatform.staffRecords),
      );
    }

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

      // The owner's own access is fixed — see [OwnerIsFixed]. Asked before the
      // lock-out rule because, for the owner, it is the whole answer: "this
      // would lock everybody out" is sometimes also true, and it sends the
      // manager off to fix the wrong thing.
      //
      // The role half applies to the ACTIVE owner only. A disabled former
      // owner is not the owner, and has to be movable: otherwise the person
      // who sold the restaurant could never come back as its manager, because
      // re-enabling them on Owner is refused while the new owner is active.
      // Their grants stay shut either way — they are still on the role that
      // holds everything.
      final onOwnerRole = before.role?.code == SystemRoles.ownerCode;
      final changingRole = roleId != null && roleId != before.role?.id;
      if (onOwnerRole &&
          (directGrants != null || (changingRole && before.isActive))) {
        return const AdminResult<PosStaff>.refused(OwnerIsFixed());
      }

      var appointing = false;
      if (changingRole) {
        final ownerRole = await _lockOwnerRole(tx);
        appointing = roleId == ownerRole;
        if (appointing && before.isActive) {
          final incumbent = await _activeOwnerOtherThan(
            tx,
            ownerRoleId: ownerRole!,
            excluding: staffId,
          );
          if (incumbent != null) {
            return AdminResult<PosStaff>.refused(
              OwnerAlreadyExists(incumbent),
            );
          }
        }
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

      // Appointing an owner takes away their extra roles, exceptions and
      // ceilings in the same transaction. All three mean nothing on somebody
      // who holds everything, and a DENY among them is a lock-out waiting to
      // happen. Refusing the appointment over them instead would send the
      // manager into the permissions dialog to untick things by hand, for no
      // gain. Before the UPDATE, because migration 42 refuses an owner who
      // still has them.
      final clearedExceptions = appointing && await _clearGrants(tx, staffId);

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_users SET '
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
        after: {
          ..._staffSnapshot(after),
          // Said on the row, because "who took Nour's refund exception away"
          // has an answer — her appointment — that is otherwise nowhere.
          if (clearedExceptions) 'exceptions_cleared': true,
        },
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
    // The bundle owns this record — see [offline].
    if (!offline) {
      return const AdminResult<PosStaff>.refused(
        ManagedByPlatform(ManagedByPlatform.staffRecords),
      );
    }

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

      // Bringing a former owner back while somebody else owns the restaurant
      // would make two. Disabling the owner is not touched here — that is the
      // lock-out rule's business, below, and it is how a handover starts.
      if (isActive &&
          !before.isActive &&
          before.role?.code == SystemRoles.ownerCode) {
        final ownerRole = await _lockOwnerRole(tx);
        final incumbent = await _activeOwnerOtherThan(
          tx,
          ownerRoleId: ownerRole ?? before.role!.id,
          excluding: staffId,
        );
        if (incumbent != null) {
          return AdminResult<PosStaff>.refused(OwnerAlreadyExists(incumbent));
        }
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
          'UPDATE pos_users SET is_active = @active WHERE id = @id AND restaurant_id = @r',
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
    // The bundle owns this record — see [offline].
    if (!offline) {
      return const AdminResult<void>.refused(
        ManagedByPlatform(ManagedByPlatform.staffRecords),
      );
    }

    if (!adminAvailable) {
      return const AdminResult<void>.refused(AdministratorCredentialRequired());
    }

    if (!Authorization.check(by, PosCapability.staffManage).isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }

    final salt = PinHash.newSalt();
    final hash = await PinHash.hash(pin, salt);

    return _c.database.runTx(_c.config, (tx) async {
      // Only the owner sets the owner's PIN — see [OwnerPinIsTheirs]. Read and
      // locked in the same transaction as the write, so a role change landing
      // between the two cannot slip a reset past it.
      //
      // Here and not in a trigger: the database sees a role, not a person, and
      // the installer and the cloud seeder both write the owner's PIN. A
      // trigger would refuse them, or trust a session setting that anybody at
      // a psql prompt can set — a guard that only stops honest writers.
      final target = await _readStaffOrNull(tx, staffId, lock: true);
      if (target == null) {
        return const AdminResult<void>.refused(EditedElsewhere(0));
      }
      if (target.role?.code == SystemRoles.ownerCode && target.id != by.id) {
        return const AdminResult<void>.refused(OwnerPinIsTheirs());
      }

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_users SET pin_salt = @salt, pin_hash = @hash '
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

  @override
  Future<Set<int>> withPassword() async {
    try {
      final rows = await _read.database.query(
        _read.config,
        'SELECT id FROM pos_users '
        'WHERE restaurant_id = @r AND password_hash IS NOT NULL',
        parameters: {'r': _read.restaurantId},
      );
      return {for (final row in rows) row[0]! as int};
    } on PosDbException catch (error) {
      // Migration 55 not applied yet: nobody has one — see the interface.
      if (isUndefinedColumn(error)) return const {};
      rethrow;
    }
  }

  /// No `staff.manage` check, and no [offline] one: this is the person's own
  /// secret, and the proof is the PIN the door has just verified plus the
  /// administrator credential only the door holds. Asking `staff.manage`
  /// would lock out a supervisor the owner let into Admin Mode.
  @override
  Future<AdminResult<void>> setOwnPassword({
    required PosStaff by,
    required String password,
  }) async {
    if (!adminAvailable) {
      return const AdminResult<void>.refused(AdministratorCredentialRequired());
    }
    if (PasswordPolicy.validate(password, username: by.username)
        case final problem?) {
      return AdminResult<void>.refused(PasswordRejected(problem));
    }

    // Hashed before the transaction opens: 600 000 iterations is long enough
    // that holding a row lock across it would make every other write to this
    // person's row wait on a key derivation.
    final hash = await PasswordHash.create(password);

    return _c.database.runTx(_c.config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_users SET password_hash = @hash, password_set_at = now() '
          'WHERE id = @id AND restaurant_id = @r AND is_active RETURNING name',
        ),
        parameters: {'id': by.id, 'r': _c.restaurantId, 'hash': hash},
      );
      if (rows.isEmpty) {
        return const AdminResult<void>.refused(EditedElsewhere(0));
      }

      // The fact and nothing else, as for a PIN: no before, no after beyond
      // the name. A hash on the ledger is a hash anybody who can read the
      // ledger can attack.
      await _c.audit(
        tx,
        by: by,
        action: AuditAction.staffPasswordSet,
        entityType: AuditAction.entityStaff,
        entityId: '${by.id}',
        after: {'name': rows.first[0] as String},
      );
      return const AdminResult<void>.done(null);
    });
  }

  @override
  Future<AdminResult<void>> clearPassword({
    required PosStaff by,
    required int staffId,
  }) async {
    if (!adminAvailable) {
      return const AdminResult<void>.refused(AdministratorCredentialRequired());
    }
    if (!Authorization.check(by, PosCapability.staffManage).isAllowed) {
      return const AdminResult.refused(NotPermitted(PosCapability.staffManage));
    }

    return _c.database.runTx(_c.config, (tx) async {
      // Read and locked with the write, as `resetPin` does, so a role change
      // landing between the two cannot slip the owner's row past the rule.
      final target = await _readStaffOrNull(tx, staffId, lock: true);
      if (target == null) {
        return const AdminResult<void>.refused(EditedElsewhere(0));
      }
      if (target.role?.code == SystemRoles.ownerCode) {
        return const AdminResult<void>.refused(OwnerPasswordIsTheirs());
      }

      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_users SET password_hash = NULL, password_set_at = NULL '
          'WHERE id = @id AND restaurant_id = @r '
          '  AND password_hash IS NOT NULL RETURNING name',
        ),
        parameters: {'id': staffId, 'r': _c.restaurantId},
      );
      // Nothing to clear is not a refusal: the person is where the manager
      // wanted them, and a ledger row for a change that did not happen would
      // be one more thing to explain.
      if (rows.isEmpty) return const AdminResult<void>.done(null);

      await _c.audit(
        tx,
        by: by,
        action: AuditAction.staffPasswordCleared,
        entityType: AuditAction.entityStaff,
        entityId: '$staffId',
        after: {'name': rows.first[0] as String},
      );
      return const AdminResult<void>.done(null);
    });
  }

  /// No capability check, on purpose: nobody is signed in — that is why a
  /// technician is here. [adminAvailable] is the whole gate, and the caller
  /// builds this repository on the credential the technician has just typed
  /// rather than the one this till keeps, so knowing the database password
  /// is what it takes. Matched as every door matches a username: trimmed,
  /// case-blind, active only.
  @override
  Future<AdminResult<String?>> clearPasswordAsTechnician({
    required String username,
  }) async {
    if (!adminAvailable) {
      return const AdminResult<String?>.refused(
        AdministratorCredentialRequired(),
      );
    }
    final wanted = username.trim().toLowerCase();
    if (wanted.isEmpty) return const AdminResult<String?>.done(null);

    return _c.database.runTx(_c.config, (tx) async {
      final rows = await tx.execute(
        Sql.named(
          'UPDATE pos_users SET password_hash = NULL, password_set_at = NULL '
          'WHERE restaurant_id = @r AND is_active '
          '  AND lower(trim(username)) = @u AND password_hash IS NOT NULL '
          'RETURNING id, name',
        ),
        parameters: {'r': _c.restaurantId, 'u': wanted},
      );
      if (rows.isEmpty) return const AdminResult<String?>.done(null);

      // One row per account cleared. Usernames are unique as typed, not
      // case-blind, so "Amer" and "amer" are two rows a case-blind door
      // treats as one name — both are cleared, and both are written down.
      for (final row in rows) {
        await _c.audit(
          tx,
          by: null,
          actorName: AuditAction.technicianActor,
          action: AuditAction.staffPasswordCleared,
          entityType: AuditAction.entityStaff,
          entityId: '${row[0]}',
          after: {'name': row[1] as String, 'by': AuditAction.technicianActor},
        );
      }
      return AdminResult<String?>.done(rows.first[1] as String);
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

      // Nothing here means anything on the owner, and a DENY is a lock-out —
      // see [OwnerIsFixed]. Refused for anybody on the owner role, active or
      // not: a former owner's grants are as meaningless as the owner's.
      if (before.role?.code == SystemRoles.ownerCode) {
        return const AdminResult<PosStaff>.refused(OwnerIsFixed());
      }

      // Owner as an extra role: a second owner if there is one already, and
      // never a thing an extra role can be even if there is not.
      final ownerRole = await _lockOwnerRole(tx);
      if (ownerRole != null && extraRoleIds.contains(ownerRole)) {
        final incumbent = await _activeOwnerOtherThan(
          tx,
          ownerRoleId: ownerRole,
          excluding: staffId,
        );
        return AdminResult<PosStaff>.refused(
          incumbent == null
              ? const OwnerIsNotAnExtraRole()
              : OwnerAlreadyExists(incumbent),
        );
      }

      await tx.execute(
        Sql.named('DELETE FROM pos_user_roles WHERE user_id = @s'),
        parameters: {'s': staffId},
      );
      for (final roleId in extraRoleIds) {
        // The primary role is a column, not a row here — see migration 22.
        // Writing it into both places is what makes a role change leave the
        // old one behind.
        if (roleId == before.role?.id) continue;
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_user_roles (user_id, role_id) VALUES (@s, @r)',
          ),
          parameters: {'s': staffId, 'r': roleId},
        );
      }

      await tx.execute(
        Sql.named(
          'DELETE FROM pos_user_permission_overrides WHERE user_id = @s',
        ),
        parameters: {'s': staffId},
      );
      for (final override in overrides) {
        await tx.execute(
          Sql.named(
            'INSERT INTO pos_user_permission_overrides '
            '  (user_id, capability, effect, granted_by) '
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

  /// This restaurant's owner role, locked for the rest of the transaction —
  /// or null when it has none.
  ///
  /// Locked so that two managers appointing an owner from two tills at once
  /// queue here rather than each counting the other's uncommitted appointment
  /// as nobody. Migration 42's trigger takes the same lock; taking it first is
  /// what makes the refusal below the answer rather than the trigger's
  /// exception. NO KEY UPDATE, so it does not block the KEY SHARE lock every
  /// other staff insert's foreign key takes on its role.
  Future<int?> _lockOwnerRole(TxSession tx) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id FROM pos_roles WHERE restaurant_id = @r AND code = @owner '
        'FOR NO KEY UPDATE',
      ),
      parameters: {'r': _c.restaurantId, 'owner': SystemRoles.ownerCode},
    );
    return rows.isEmpty ? null : rows.first[0] as int;
  }

  /// The active owner who is not [excluding], by name — the count migration
  /// 42 makes, asked first so the answer is a sentence.
  Future<String?> _activeOwnerOtherThan(
    TxSession tx, {
    required int ownerRoleId,
    int? excluding,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT name FROM pos_users '
        'WHERE restaurant_id = @r AND role_id = @role AND is_active '
        '  AND (@id::bigint IS NULL OR id <> @id::bigint) '
        'ORDER BY id LIMIT 1',
      ),
      parameters: {'r': _c.restaurantId, 'role': ownerRoleId, 'id': excluding},
    );
    return rows.isEmpty ? null : rows.first[0] as String;
  }

  /// Takes away somebody's extra roles, exceptions and ceilings. True when
  /// there was anything to take.
  Future<bool> _clearGrants(TxSession tx, int staffId) async {
    var removed = 0;
    for (final table in ['pos_user_roles', 'pos_user_permission_overrides']) {
      removed += (await tx.execute(
        Sql.named('DELETE FROM $table WHERE user_id = @s'),
        parameters: {'s': staffId},
      )).affectedRows;
    }
    removed += (await tx.execute(
      Sql.named(
        "DELETE FROM pos_permission_limits WHERE restaurant_id = @r "
        "  AND subject_type = 'staff' AND subject_id = @s",
      ),
      parameters: {'r': _c.restaurantId, 's': staffId},
    )).affectedRows;
    return removed > 0;
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
        'SELECT 1 FROM pos_users s LEFT JOIN pos_roles r ON r.id = s.role_id '
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
  }) : _c = _AdminContext(
         database: database,
         config: config,
         restaurantId: restaurantId,
         branchId: branchId,
         terminalId: terminalId,
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
      'SELECT id, action, entity_type, entity_id, actor_user_id, actor_name, '
      '  approved_by_id, approved_by_name, before_value, after_value, reason, occurred_at '
      'FROM pos_audit_events WHERE restaurant_id = @r '
      '  AND (@entityType::text IS NULL OR entity_type = @entityType) '
      '  AND (@entityId::text IS NULL OR entity_id = @entityId) '
      '  AND (@staffId::bigint IS NULL OR actor_user_id = @staffId) '
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
