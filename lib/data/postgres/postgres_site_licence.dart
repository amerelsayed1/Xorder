import '../../core/config/deployment.dart';
import 'pos_database.dart';

/// One row of `pos_site_licence` (migration 43), as plain values.
///
/// Free of the licensing types, as the rest of `lib/data/` is: `providers.dart`
/// adapts it to `SiteLicenceSource`, the one layer allowed to see both.
class SiteLicenceRow {
  const SiteLicenceRow({
    required this.restaurantId,
    required this.payload,
    required this.signature,
    required this.keyId,
    required this.mode,
    this.terminalCount = 0,
  });

  final int restaurantId;
  final String payload;
  final String signature;
  final String keyId;
  final String mode;

  /// Registered terminals for [restaurantId], counted when read. Ignored on
  /// publish.
  final int terminalCount;
}

/// The licence a main device shares with the tablets that sell through it.
///
/// Written by the main device on the till credential, read by its children
/// on theirs — see `LocalBootstrap.tillGrants`.
class PostgresSiteLicence {
  const PostgresSiteLicence({
    required PosDatabase database,
    required this._config,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig _config;

  static const _select =
      'SELECT l.restaurant_id, l.payload, l.signature, l.key_id, l.mode, '
      '(SELECT count(*) FROM pos_terminals t '
      'WHERE t.restaurant_id = l.restaurant_id) '
      'FROM pos_site_licence l';

  /// Two statements rather than one `@restaurant IS NULL OR …`: a null
  /// parameter in that position has no type PostgreSQL can infer.
  Future<SiteLicenceRow?> read({int? restaurantId}) async {
    final rows = restaurantId == null
        ? await _db.query(
            _config,
            '$_select ORDER BY l.published_at DESC LIMIT 1',
          )
        : await _db.query(
            _config,
            '$_select WHERE l.restaurant_id = @restaurant',
            parameters: {'restaurant': restaurantId},
          );
    if (rows.isEmpty) return null;

    final row = rows.first;
    return SiteLicenceRow(
      restaurantId: row[0]! as int,
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
      '(restaurant_id, payload, signature, key_id, mode, published_at) '
      'VALUES (@restaurant, @payload, @signature, @key, @mode, now()) '
      'ON CONFLICT (restaurant_id) DO UPDATE SET '
      'payload = EXCLUDED.payload, signature = EXCLUDED.signature, '
      'key_id = EXCLUDED.key_id, mode = EXCLUDED.mode, published_at = now()',
      parameters: {
        'restaurant': licence.restaurantId,
        'payload': licence.payload,
        'signature': licence.signature,
        'key': licence.keyId,
        'mode': licence.mode,
      },
    );
  }
}
