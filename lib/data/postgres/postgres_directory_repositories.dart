import 'package:uuid/uuid.dart';

import '../../core/config/deployment.dart';
import '../../core/security/pin_hash.dart';
import '../../domain/models/permissions.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/permission_resolver.dart';
import 'pos_database.dart';
import 'postgres_admin_repositories.dart';
import 'postgres_tenant.dart';

const _uuid = Uuid();

/// The branches a terminal may be assigned to, read from the branch server.
class PostgresBranchRepository implements BranchRepository {
  PostgresBranchRepository({
    required PosDatabase database,
    required this._config,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig _config;
  late final _tenant = PosTenantResolver(_db, _config);

  @override
  Future<List<PosBranch>> forTenant() async {
    final tenant = await _tenant.resolve();

    final rows = await _db.query(
      _config,
      'SELECT id, name, code, supported_order_types, is_active FROM pos_branches '
      'WHERE restaurant_id = @restaurant AND is_active ORDER BY name',
      parameters: {'restaurant': tenant.id},
    );

    return [
      for (final row in rows)
        PosBranch(
          id: row[0] as int,
          name: row[1] as String,
          code: row[2] as String?,
          supportedOrderTypes: _textArray(row[3]),
          isActive: row[4] as bool,
        ),
    ];
  }
}

/// Terminal provisioning against the branch server (POS-BE-023).
///
/// Both paths land on the same `pos_terminals` row, which is the point: a till
/// set up by hand and a till claimed with a code are equally visible to whoever
/// is looking at the restaurant's terminals.
class PostgresProvisioningRepository implements ProvisioningRepository {
  PostgresProvisioningRepository({
    required PosDatabase database,
    required this._config,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig _config;

  @override
  Future<ClaimResult> claimByCode({
    required String tenantSlug,
    required String code,
  }) async {
    final tenant = await _tenantFor(tenantSlug);
    if (tenant == null) return _unknownTenant(tenantSlug);

    final normalised = code.trim().toUpperCase();

    // The code is kept on the row after it is spent rather than nulled. Keeping
    // it is what lets a second attempt say "already used" instead of "not
    // recognised" — the operator needs a new code, not another go at this one.
    final rows = await _db.query(
      _config,
      'SELECT t.id, t.name, t.sync_policy, t.claimed_at, b.id, b.name, b.code '
      'FROM pos_terminals t JOIN pos_branches b ON b.id = t.branch_id '
      'WHERE t.restaurant_id = @restaurant AND t.pairing_code = @code',
      parameters: {'restaurant': tenant.id, 'code': normalised},
    );

    if (rows.isEmpty) {
      return const ClaimResult(
        code: 'PAIRING_CODE_INVALID',
        message:
            'That setup code was not recognised. Check it with whoever '
            'added this till in the dashboard.',
      );
    }

    final row = rows.first;
    if (row[3] != null) {
      return const ClaimResult(
        code: 'PAIRING_CODE_SPENT',
        message:
            'That setup code has already been used. Issue a new one from '
            'the dashboard.',
      );
    }

    // Conditional on `claimed_at IS NULL`, so two tills racing the same code
    // cannot both win: the loser updates no rows and is told the code is spent.
    final claimed = await _db.query(
      _config,
      'UPDATE pos_terminals SET claimed_at = now() '
      'WHERE id::text = @id AND claimed_at IS NULL RETURNING id',
      parameters: {'id': row[0].toString()},
    );
    if (claimed.isEmpty) {
      return const ClaimResult(
        code: 'PAIRING_CODE_SPENT',
        message:
            'That setup code was claimed by another terminal a moment ago. '
            'Issue a new one from the dashboard.',
      );
    }

    return ClaimResult(
      claim: TerminalClaim(
        terminalId: row[0].toString(),
        terminalName: row[1] as String,
        syncPolicy:
            SyncPolicy.fromWire(row[2] as String?) ?? SyncPolicy.automatic,
        branchId: row[4] as int,
        branchName: row[5] as String,
        branchCode: row[6] as String?,
        restaurantId: tenant.id,
      ),
    );
  }

  /// Verify credentials and pull the tenant's branches from the branch
  /// database — the offline counterpart of the cloud pull, kept equivalent so
  /// the wizard's account step behaves the same on both paths.
  ///
  /// `password` is the member of staff's **PIN**, for the same reason as
  /// [registerManually] below.
  @override
  Future<TenantConnection> connect({
    required String tenantSlug,
    required String username,
    required String password,
  }) async {
    final tenant = await _tenantFor(tenantSlug);
    if (tenant == null) {
      return TenantConnection(
        code: 'TENANT_UNKNOWN',
        message:
            'No restaurant named "${tenantSlug.trim()}" exists on this '
            'server. Check the short name on the previous step.',
      );
    }

    final staff = await _db.query(
      _config,
      'SELECT pin_salt, pin_hash FROM pos_staff '
      'WHERE restaurant_id = @restaurant AND username = @username AND is_active',
      parameters: {'restaurant': tenant.id, 'username': username.trim()},
    );
    final authorised =
        staff.isNotEmpty &&
        await PinHash.verify(
          password,
          salt: staff.first[0] as String,
          expected: staff.first[1] as String,
        );
    if (!authorised) {
      return const TenantConnection(
        code: 'CREDENTIALS_REJECTED',
        message:
            'That username and PIN were not accepted. Check them with a '
            'manager, or use a setup code instead.',
      );
    }

    final branches = await _db.query(
      _config,
      'SELECT id, name, code, supported_order_types FROM pos_branches '
      'WHERE restaurant_id = @restaurant AND is_active ORDER BY name',
      parameters: {'restaurant': tenant.id},
    );
    return TenantConnection(
      tenantName: tenant.name,
      branches: [
        for (final row in branches)
          PosBranch(
            id: row[0] as int,
            name: row[1] as String,
            code: row[2] as String?,
            supportedOrderTypes: _textArray(row[3]),
          ),
      ],
    );
  }

  /// The fallback path, for an installer with no dashboard access.
  ///
  /// `password` is the member of staff's **PIN**. The till has no password
  /// column to check against and inventing one would be a second credential to
  /// keep in step with the first; the PIN is what this database actually knows
  /// about a person, so it is what this verifies.
  @override
  /// Not available on the LAN path, and saying so beats pretending.
  ///
  /// Adopting works by minting a pairing code and redeeming it, and both of
  /// those are platform operations — there is no dashboard here to have
  /// created the terminal in the first place. A till pointed at a branch
  /// server registers itself; that is the whole shape of this deployment.
  @override
  Future<ClaimResult> adoptTerminal({
    required String tenantSlug,
    required String username,
    required String password,
    required int terminalId,
  }) async => const ClaimResult(
    code: 'ADOPT_UNSUPPORTED',
    message:
        'This server has no dashboard to have created a terminal in '
        'advance. Name this till and register it instead.',
  );

  @override
  Future<ClaimResult> registerManually({
    required String tenantSlug,
    required String username,
    required String password,
    required String terminalName,
    required int branchId,
  }) async {
    final tenant = await _tenantFor(tenantSlug);
    if (tenant == null) return _unknownTenant(tenantSlug);

    final staff = await _db.query(
      _config,
      'SELECT pin_salt, pin_hash FROM pos_staff '
      'WHERE restaurant_id = @restaurant AND username = @username AND is_active',
      parameters: {'restaurant': tenant.id, 'username': username.trim()},
    );

    final authorised =
        staff.isNotEmpty &&
        await PinHash.verify(
          password,
          salt: staff.first[0] as String,
          expected: staff.first[1] as String,
        );

    // One message for both "no such user" and "wrong PIN", so the wizard cannot
    // be used to enumerate who works here.
    if (!authorised) {
      return const ClaimResult(
        code: 'CREDENTIALS_REJECTED',
        message:
            'That username and PIN were not accepted. Check them with a '
            'manager, or use a setup code instead.',
      );
    }

    final branch = await _db.query(
      _config,
      'SELECT id, name, code FROM pos_branches '
      'WHERE id = @branch AND restaurant_id = @restaurant AND is_active',
      parameters: {'branch': branchId, 'restaurant': tenant.id},
    );
    if (branch.isEmpty) {
      return const ClaimResult(
        code: 'BRANCH_UNKNOWN',
        message: 'That branch is not on this server any more. Pick another.',
      );
    }

    final terminalId = _uuid.v4();
    await _db.query(
      _config,
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name, claimed_at) '
      'VALUES (@id, @restaurant, @branch, @name, now())',
      parameters: {
        'id': terminalId,
        'restaurant': tenant.id,
        'branch': branchId,
        'name': terminalName.trim(),
      },
    );

    return ClaimResult(
      claim: TerminalClaim(
        terminalId: terminalId,
        terminalName: terminalName.trim(),
        syncPolicy: SyncPolicy.automatic,
        branchId: branch.first[0] as int,
        branchName: branch.first[1] as String,
        branchCode: branch.first[2] as String?,
        restaurantId: tenant.id,
      ),
    );
  }

  Future<PosTenant?> _tenantFor(String slug) async {
    if (slug.trim().isEmpty) return null;
    final rows = await _db.query(
      _config,
      'SELECT id, name FROM pos_restaurants WHERE slug = @slug AND is_active',
      parameters: {'slug': slug.trim().toLowerCase()},
    );
    if (rows.isEmpty) return null;
    return PosTenant(id: rows.first[0] as int, name: rows.first[1] as String);
  }

  ClaimResult _unknownTenant(String slug) => ClaimResult(
    code: 'TENANT_UNKNOWN',
    message:
        'No restaurant named "${slug.trim()}" exists on this server. '
        'Check the short name on the previous step.',
  );
}

/// Who is working this till, read from the branch server.
///
/// **There is no sign-in screen yet**, so "current" means the first active
/// member of staff for this branch rather than a person who authenticated.
/// [verifyPin] is real and offline — it is what the lock screen uses — but until
/// a sign-in step exists the name in the top bar is the branch's first cashier,
/// not necessarily the one holding the till. That is POS-BE-024.
class PostgresSessionRepository implements SessionRepository {
  const PostgresSessionRepository({
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

  @override
  Future<PosSession> current() async {
    final rows = await _db.query(
      _config,
      'SELECT r.name, b.name, t.name, s.name, s.capabilities '
      'FROM pos_restaurants r '
      'JOIN pos_branches b ON b.id = @branch '
      // `id::text`, not `id = @terminal`: the parameter arrives as a string and
      // PostgreSQL will not compare uuid to text without being told to.
      'JOIN pos_terminals t ON t.id::text = @terminal '
      'LEFT JOIN LATERAL ('
      // The role's capabilities unioned with the direct grants, which is what
      // `PosStaff.effectiveCapabilities` means — computed here because the top
      // bar reads a `PosSession`, which carries a flat set rather than a role.
      "  SELECT st.name, st.capabilities || coalesce(ro.capabilities, '{}'::text[]) "
      '    AS capabilities '
      '  FROM pos_staff st LEFT JOIN pos_roles ro ON ro.id = st.role_id '
      '  WHERE st.restaurant_id = r.id AND st.is_active '
      '    AND (st.branch_id IS NULL OR st.branch_id = @branch) '
      '  ORDER BY st.id LIMIT 1'
      ') s ON true '
      'WHERE r.id = @restaurant',
      parameters: {
        'restaurant': _restaurantId,
        'branch': _branchId,
        'terminal': _terminalId,
      },
    );

    if (rows.isEmpty) {
      throw StateError(
        'This terminal is configured for a restaurant, branch or terminal that '
        'is no longer on the branch server. Re-run setup.',
      );
    }

    final row = rows.first;
    return PosSession(
      tenantName: row[0] as String,
      branchName: row[1] as String,
      terminalCode: row[2] as String,
      // No staff row yet is a setup problem, not a crash: the till still shows
      // its identity and the operator can see what is missing.
      userName: (row[3] as String?) ?? 'No staff configured',
      capabilities: PosCapability.canonicalAll(_textArray(row[4])),
      // Shifts are not recorded yet (POS-BE-009). An invented reference on a
      // report would be worse than an empty one.
      shiftReference: '',
    );
  }

  /// Checked against every active member of staff, because a till is shared and
  /// the lock screen does not ask who is unlocking it — only that somebody who
  /// works here is.
  @override
  Future<bool> verifyPin(String pin) async => (await signIn(pin)) != null;

  /// The same check, but answering *who*.
  ///
  /// Opening a shift needs a name to put against the money; unlocking a
  /// terminal does not. Both walk the same rows, so a PIN that unlocks is
  /// always a PIN that can open a shift.
  ///
  /// Every candidate is hashed even after a match is found. Returning early
  /// would make the response time depend on where in the list the right person
  /// sits, which over a few hundred attempts is enough to order the staff table.
  @override
  Future<PosStaff?> signIn(String pin) async {
    if (pin.trim().isEmpty) return null;

    // The role comes back with the person. Signing in is the moment the till
    // learns what this cashier may do, and a second round trip to find out
    // would be one the lock screen has to make with a queue at the counter.
    final rows = await _db.query(
      _config,
      'SELECT s.id, s.name, s.username, s.capabilities, s.is_active, $joinedRoleColumns, '
      '       s.pin_salt, s.pin_hash '
      'FROM pos_staff s LEFT JOIN pos_roles r ON r.id = s.role_id '
      'WHERE s.restaurant_id = @restaurant AND s.is_active '
      '  AND (s.branch_id IS NULL OR s.branch_id = @branch) '
      'ORDER BY s.id',
      parameters: {'restaurant': _restaurantId, 'branch': _branchId},
    );

    PosStaff? matched;
    for (final row in rows) {
      final ok = await PinHash.verify(
        pin,
        salt: row[11] as String,
        expected: row[12] as String,
      );
      if (ok && matched == null) {
        matched = PosStaff(
          id: row[0] as int,
          name: row[1] as String,
          username: row[2] as String?,
          capabilities: PosCapability.canonicalAll(_textArray(row[3])),
          isActive: row[4] as bool,
          role: optionalRoleFromRow(row, 5),
        );
      }
    }
    return matched == null ? null : _withGrants(matched);
  }

  /// Loads the extra roles, the per-person overrides and the ceilings.
  ///
  /// **One query, and only for the person who matched.** Sign-in already walks
  /// every candidate row to keep its timing flat; loading grants for all of
  /// them would undo that saving for no benefit, because nobody but the matched
  /// person is about to use them.
  ///
  /// A failure here returns the person **unenriched** rather than refusing the
  /// sign-in. That is the conservative direction: they get their primary role
  /// and no extras, which is less than they should have rather than more, and a
  /// cashier locked out of the till by a permissions query is a queue at the
  /// counter over something nobody at the counter can fix.
  Future<PosStaff> _withGrants(PosStaff staff) async {
    try {
      final extras = await _db.query(
        _config,
        'SELECT $joinedRoleColumns FROM pos_staff_roles sr '
        'JOIN pos_roles r ON r.id = sr.role_id '
        'WHERE sr.staff_id = @staff ORDER BY r.id',
        parameters: {'staff': staff.id},
      );

      final overrides = await _db.query(
        _config,
        'SELECT capability, effect, granted_by, granted_at '
        'FROM pos_staff_permission_overrides WHERE staff_id = @staff',
        parameters: {'staff': staff.id},
      );

      // Role ceilings and personal ones in one read, ordered so the role's
      // arrive first — `PermissionResolver` tightens rather than replaces, so
      // the order does not change the answer, but it keeps the two apart for
      // the caller that wants to show which is which.
      final limits = await _db.query(
        _config,
        'SELECT subject_type, limit_key, limit_bp, limit_minor '
        'FROM pos_permission_limits '
        'WHERE restaurant_id = @restaurant AND ('
        "  (subject_type = 'staff' AND subject_id = @staff) OR "
        "  (subject_type = 'role' AND subject_id = ANY(@roles))) "
        'ORDER BY subject_type DESC',
        parameters: {
          'restaurant': _restaurantId,
          'staff': staff.id,
          'roles': [
            if (staff.role case final own?) own.id,
            for (final row in extras) row[0]! as int,
          ],
        },
      );

      final roleLimits = <String, PermissionLimit>{};
      final staffLimits = <String, PermissionLimit>{};
      for (final row in limits) {
        final target = (row[0]! as String) == 'role' ? roleLimits : staffLimits;
        final key = row[1]! as String;
        final limit = PermissionLimit(
          maxBp: row[2] as int?,
          maxMinor: (row[3] as int?),
        );
        // Two roles with a ceiling on the same key tighten each other — see
        // [PermissionLimit.tightenedBy] for why the tighter wins.
        target[key] = (target[key] ?? PermissionLimit.unlimited).tightenedBy(
          limit,
        );
      }

      final extraRoles = <PosRole>[
        for (final row in extras)
          if (row[0] != staff.role?.id) roleFromRow(row),
      ];

      return staff.copyWith(
        extraRoles: extraRoles,
        overrides: [
          for (final row in overrides)
            if (OverrideEffect.fromWire(row[1]! as String) case final effect?)
              PermissionOverride(
                capability: row[0]! as String,
                effect: effect,
                grantedById: row[2] as int?,
                grantedAt: (row[3] as DateTime?)?.toUtc(),
              ),
        ],
        limits: PermissionResolver.resolve(
          isActive: staff.isActive,
          roles: const [],
          roleLimits: roleLimits,
          staffLimits: staffLimits,
        ).limits,
      );
    } on Object {
      return staff;
    }
  }
}

/// PostgreSQL `text[]` arrives as a `List` of dynamics.
List<String> _textArray(Object? value) => switch (value) {
  null => const [],
  final List<Object?> list => [
    for (final item in list)
      if (item != null) item.toString(),
  ],
  _ => const [],
};
