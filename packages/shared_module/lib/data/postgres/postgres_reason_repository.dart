import '../../core/config/deployment.dart';
import '../../domain/models/reason_code.dart';
import '../../domain/repositories/repositories.dart';
import '../sql/sql.dart';
import '../sql/row_reads.dart';

/// The reason lists, read from `pos_reason_codes`.
///
/// Read-only at the till. A cashier picks a reason; adding one is a settings
/// act, because somebody who could add a void reason could add one that reads
/// well.
class PostgresReasonsRepository implements ReasonsRepository {
  const PostgresReasonsRepository({
    required SqlDatabase database,
    required this.config,
    required this.businessId,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final int businessId;

  @override
  Future<List<ReasonCode>> forScope(ReasonScope scope) async {
    final rows = await _db.query(
      config,
      'SELECT id, code, name_en, name_ar, requires_note, sort_order '
      'FROM pos_reason_codes '
      'WHERE business_id = @r AND scope = @scope AND is_active '
      // The business's own order, which is what the number keys follow.
      'ORDER BY sort_order, id',
      parameters: {'r': businessId, 'scope': scope.wire},
    );

    return [
      for (final row in rows)
        ReasonCode(
          id: row[0] as int,
          scope: scope,
          code: row[1] as String,
          nameEn: row[2] as String,
          nameAr: row[3] as String?,
          requiresNote: row.booleanOrNull(4) ?? false,
          sortOrder: row[5] as int? ?? 0,
        ),
    ];
  }
}

/// Before there is a database: no reasons, and therefore no reason picker.
///
/// Empty rather than invented. A till mid-setup offering "Manager comp" would
/// be describing a business that has not been configured yet.
class UnconfiguredReasonsRepository implements ReasonsRepository {
  const UnconfiguredReasonsRepository();

  @override
  Future<List<ReasonCode>> forScope(ReasonScope scope) async => const [];
}
