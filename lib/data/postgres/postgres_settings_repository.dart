import '../../core/config/deployment.dart';
import '../../domain/models/pos_settings.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// Reads and writes `pos_settings`.
///
/// The whole table for one business in one query, resolved in Dart. A
/// per-key read would be a round trip per question, and the questions — is
/// blind close on, when does the day start, may this person refund — are asked
/// on every screen.
class PostgresSettingsRepository implements SettingsRepository {
  const PostgresSettingsRepository({
    required PosDatabase database,
    required this.config,
    required this.businessId,
    required this.branchId,
    required this.terminalId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int businessId;
  final int branchId;
  final String terminalId;

  @override
  Future<PosSettings> load() async {
    final rows = await _db.query(
      config,
      'SELECT scope, scope_id, key, value FROM pos_settings '
      'WHERE business_id = @business',
      parameters: {'business': businessId},
    );

    return PosSettings.resolve(
      [
        for (final raw in rows)
          if (SettingScope.fromWire(raw[0]! as String) case final scope?)
            PosSettingRow(
              scope: scope,
              scopeId: raw[1] as String? ?? '',
              key: raw[2]! as String,
              value: raw[3] as String? ?? '',
            ),
      ],
      branchId: '$branchId',
      terminalId: terminalId,
    );
  }

  @override
  Future<void> save({
    required String key,
    required String value,
    required SettingScope scope,
    required PosStaff by,
    String scopeId = '',
  }) async {
    await _db.query(
      config,
      'INSERT INTO pos_settings (business_id, scope, scope_id, key, value, '
      '  updated_by, updated_at) '
      'VALUES (@business, @scope, @scopeId, @key, @value, @by, now()) '
      // The database's own uniqueness constraint, so saving a key twice is a
      // change rather than a second row nothing can tell apart from the first.
      'ON CONFLICT (business_id, scope, scope_id, key) DO UPDATE '
      '  SET value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, '
      '      updated_at = now()',
      parameters: {
        'business': businessId,
        'scope': scope.wire,
        'scopeId': scopeId,
        'key': key,
        'value': value,
        'by': by.id,
      },
    );
  }
}

/// What a terminal with no branch database answers with.
///
/// Empty, which resolves to every default. A till mid-setup is not
/// misconfigured, it is unconfigured, and the defaults are what the SRS says
/// happens then. [save] refuses out loud — reporting success while writing
/// nowhere would tell somebody their blind-close switch was on.
class UnconfiguredSettingsRepository implements SettingsRepository {
  const UnconfiguredSettingsRepository();

  @override
  Future<PosSettings> load() async => PosSettings.empty;

  @override
  Future<void> save({
    required String key,
    required String value,
    required SettingScope scope,
    required PosStaff by,
    String scopeId = '',
  }) async => throw StateError(
    'This terminal has nowhere to store a setting. It is not connected to a '
    'database.',
  );
}
