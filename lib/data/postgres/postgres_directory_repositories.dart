import 'package:uuid/uuid.dart';

import '../../core/config/deployment.dart';
import '../../core/security/pin_hash.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';
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
  Future<ClaimResult> claimByCode({required String tenantSlug, required String code}) async {
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
        message: 'That setup code was not recognised. Check it with whoever '
            'added this till in the dashboard.',
      );
    }

    final row = rows.first;
    if (row[3] != null) {
      return const ClaimResult(
        code: 'PAIRING_CODE_SPENT',
        message: 'That setup code has already been used. Issue a new one from '
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
        message: 'That setup code was claimed by another terminal a moment ago. '
            'Issue a new one from the dashboard.',
      );
    }

    return ClaimResult(
      claim: TerminalClaim(
        terminalId: row[0].toString(),
        terminalName: row[1] as String,
        syncPolicy: SyncPolicy.fromWire(row[2] as String?) ?? SyncPolicy.automatic,
        branchId: row[4] as int,
        branchName: row[5] as String,
        branchCode: row[6] as String?,
        restaurantId: tenant.id,
      ),
    );
  }

  /// The fallback path, for an installer with no dashboard access.
  ///
  /// `password` is the member of staff's **PIN**. The till has no password
  /// column to check against and inventing one would be a second credential to
  /// keep in step with the first; the PIN is what this database actually knows
  /// about a person, so it is what this verifies.
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

    final authorised = staff.isNotEmpty &&
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
        message: 'That username and PIN were not accepted. Check them with a '
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
        message: 'No restaurant named "${slug.trim()}" exists on this server. '
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
      '  SELECT name, capabilities FROM pos_staff '
      '  WHERE restaurant_id = r.id AND is_active '
      '    AND (branch_id IS NULL OR branch_id = @branch) '
      '  ORDER BY id LIMIT 1'
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
      capabilities: _textArray(row[4]).toSet(),
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

    final rows = await _db.query(
      _config,
      'SELECT id, name, capabilities, pin_salt, pin_hash FROM pos_staff '
      'WHERE restaurant_id = @restaurant AND is_active '
      '  AND (branch_id IS NULL OR branch_id = @branch) '
      'ORDER BY id',
      parameters: {'restaurant': _restaurantId, 'branch': _branchId},
    );

    PosStaff? matched;
    for (final row in rows) {
      final ok = await PinHash.verify(
        pin,
        salt: row[3] as String,
        expected: row[4] as String,
      );
      if (ok && matched == null) {
        matched = PosStaff(
          id: row[0] as int,
          name: row[1] as String,
          capabilities: _textArray(row[2]).toSet(),
        );
      }
    }
    return matched;
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
