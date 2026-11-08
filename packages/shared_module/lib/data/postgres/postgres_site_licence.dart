import '../../core/config/deployment.dart';
import '../sql/sql.dart';

/// One row of `pos_site_licence` (migration 43), as plain values.
///
/// Free of the licensing types, as the rest of `lib/data/` is: `providers.dart`
/// adapts it to `SiteLicenceSource`, the one layer allowed to see both.
class SiteLicenceRow {
  const SiteLicenceRow({
    required this.businessId,
    required this.payload,
    required this.signature,
    required this.keyId,
    required this.mode,
    this.terminalCount = 0,
  });

  final int businessId;
  final String payload;
  final String signature;
  final String keyId;
  final String mode;

  /// Registered terminals for [businessId], counted when read. Ignored on
  /// publish.
  final int terminalCount;
}

/// The licence a main device shares with the tablets that sell through it.
///
/// Written by the main device on the till credential, read by its children
/// on theirs — see `LocalBootstrap.tillGrants`.
class PostgresSiteLicence {
  const PostgresSiteLicence({
    required SqlDatabase database,
    required this._config,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig _config;

  static const _select =
      'SELECT l.business_id, l.payload, l.signature, l.key_id, l.mode, '
      '(SELECT count(*) FROM pos_terminals t '
      'WHERE t.business_id = l.business_id) '
      'FROM pos_site_licence l';

  /// Two statements rather than one `@business IS NULL OR …`: a null
  /// parameter in that position has no type PostgreSQL can infer.
  Future<SiteLicenceRow?> read({int? businessId}) async {
    final rows = businessId == null
        ? await _db.query(
            _config,
            '$_select ORDER BY l.published_at DESC LIMIT 1',
          )
        : await _db.query(
            _config,
            '$_select WHERE l.business_id = @business',
            parameters: {'business': businessId},
          );
    if (rows.isEmpty) return null;

    final row = rows.first;
    return SiteLicenceRow(
      businessId: row[0]! as int,
      payload: row[1]! as String,
      signature: row[2]! as String,
      keyId: row[3]! as String,
      mode: row[4]! as String,
      terminalCount: row[5]! as int,
    );
  }

  Future<void> publish(SiteLicenceRow licence) async {
    await _db.query(
      _config,
      'INSERT INTO pos_site_licence '
      '(business_id, payload, signature, key_id, mode, published_at) '
      'VALUES (@business, @payload, @signature, @key, @mode, now()) '
      'ON CONFLICT (business_id) DO UPDATE SET '
      'payload = EXCLUDED.payload, signature = EXCLUDED.signature, '
      'key_id = EXCLUDED.key_id, mode = EXCLUDED.mode, published_at = now()',
      parameters: {
        'business': licence.businessId,
        'payload': licence.payload,
        'signature': licence.signature,
        'key': licence.keyId,
        'mode': licence.mode,
      },
    );
  }
}
