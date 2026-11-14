import '../sql/sql.dart';

import '../../core/config/deployment.dart';
import '../../domain/services/authorization.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/receipt_profile.dart';
import '../../domain/models/shift.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';

/// Reads and writes `pos_receipt_profiles`.
///
/// One row per branch, read whole. There is exactly one of these per till and
/// it is read on every settlement, so a column-per-question API would be a
/// round trip to print a receipt.
class PostgresReceiptProfileRepository implements ReceiptProfileRepository {
  const PostgresReceiptProfileRepository({
    required SqlDatabase database,
    required this.config,
    required SqlDatabase readDatabase,
    required this.readConfig,
    required this.adminAvailable,
    required this.businessId,
    required this.branchId,
  }) : _db = database,
       _tillDb = readDatabase;

  /// Writes, on the administrative connection.
  final SqlDatabase _db;
  final DeploymentConfig config;

  /// Reads, on the till's own credential — which holds SELECT and nothing
  /// more. A cashier printing a receipt must not need the back office's
  /// password to learn the business's address.
  final SqlDatabase _tillDb;
  final DeploymentConfig readConfig;

  final bool adminAvailable;
  final int businessId;
  final int branchId;

  static const _columns =
      'trade_name, registration_number, activity_code, branch_code, '
      'country, governate, region_city, street, building_number, '
      'postal_code, floor, room, landmark, additional_info, '
      'phone, header_note, footer_note, revision';

  @override
  Future<ReceiptProfile> load() async {
    final rows = await _tillDb.query(
      readConfig,
      'SELECT $_columns FROM pos_receipt_profiles WHERE branch_id = @branch',
      parameters: {'branch': branchId},
    );

    // A branch that has never been set up is not an error and not a null. It
    // is a blank profile, which knows it is blank — see [ReceiptProfile.isBlank].
    if (rows.isEmpty) return ReceiptProfile(branchId: branchId);
    return _read(rows.first);
  }

  ReceiptProfile _read(List<dynamic> row) {
    String at(int i) => (row[i] as String? ?? '').trim();
    String? orNull(int i) => at(i).isEmpty ? null : at(i);

    return ReceiptProfile(
      branchId: branchId,
      tradeName: at(0),
      registrationNumber: at(1),
      activityCode: at(2),
      branchCode: at(3),
      address: BranchAddress(
        country: at(4),
        governate: at(5),
        regionCity: at(6),
        street: at(7),
        buildingNumber: at(8),
        postalCode: orNull(9),
        floor: orNull(10),
        room: orNull(11),
        landmark: orNull(12),
        additionalInformation: orNull(13),
      ),
      phone: orNull(14),
      headerNote: orNull(15),
      footerNote: orNull(16),
      revision: row[17] as int? ?? 0,
    );
  }

  @override
  Future<AdminResult<ReceiptProfile>> save(
    ReceiptProfile profile, {
    required PosStaff by,
  }) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    // `Authorization.check` and not `by.capabilities`: that field holds the
    // direct grants alone, so a manager whose permission comes from their
    // role would have been refused. It also asks whether they are still
    // employed, which membership of a set does not.
    if (!Authorization.check(by, PosCapability.settingsManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.settingsManage),
      );
    }

    // Not `canFile`. A business types this in over several sittings, and a
    // form that refused to save until every ETA field was right would make the
    // half-finished state — which is the normal state — unsaveable.
    final problems = profile.printProblems;
    if (problems.isNotEmpty) {
      return AdminResult.refused(CatalogInvalid(problems.first.message));
    }

    return _db.runTx(config, (tx) async {
      final current = await tx.execute(
        Sql.named(
          'SELECT revision FROM pos_receipt_profiles WHERE branch_id = @branch',
        ),
        parameters: {'branch': branchId},
      );
      final held = current.isEmpty ? 0 : current.first[0]! as int;
      if (held != profile.revision) {
        // The office and the counter, editing the same profile. Refused rather
        // than merged: a tax registration number is not a field where the last
        // writer should quietly win.
        return AdminResult.refused(EditedElsewhere(held));
      }

      final parameters = <String, Object?>{
        'business': businessId,
        'branch': branchId,
        'trade': profile.tradeName.trim(),
        'rin': profile.registrationNumber.trim(),
        'activity': profile.activityCode.trim(),
        'code': profile.branchCode.trim(),
        'country': profile.address.country.trim(),
        'governate': profile.address.governate.trim(),
        'city': profile.address.regionCity.trim(),
        'street': profile.address.street.trim(),
        'building': profile.address.buildingNumber.trim(),
        'postal': profile.address.postalCode?.trim() ?? '',
        'floor': profile.address.floor?.trim() ?? '',
        'room': profile.address.room?.trim() ?? '',
        'landmark': profile.address.landmark?.trim() ?? '',
        'extra': profile.address.additionalInformation?.trim() ?? '',
        'phone': profile.phone?.trim() ?? '',
        'header': profile.headerNote?.trim() ?? '',
        'footer': profile.footerNote?.trim() ?? '',
        'by': by.id,
      };

      await tx.execute(
        Sql.named('''
        INSERT INTO pos_receipt_profiles
          (business_id, branch_id, trade_name, registration_number,
           activity_code, branch_code, country, governate, region_city,
           street, building_number, postal_code, floor, room, landmark,
           additional_info, phone, header_note, footer_note, revision,
           updated_at, updated_by)
        VALUES
          (@business, @branch, @trade, @rin, @activity, @code, @country,
           @governate, @city, @street, @building, @postal, @floor, @room,
           @landmark, @extra, @phone, @header, @footer, 1, now(), @by)
        ON CONFLICT (branch_id) DO UPDATE SET
          trade_name = excluded.trade_name,
          registration_number = excluded.registration_number,
          activity_code = excluded.activity_code,
          branch_code = excluded.branch_code,
          country = excluded.country,
          governate = excluded.governate,
          region_city = excluded.region_city,
          street = excluded.street,
          building_number = excluded.building_number,
          postal_code = excluded.postal_code,
          floor = excluded.floor,
          room = excluded.room,
          landmark = excluded.landmark,
          additional_info = excluded.additional_info,
          phone = excluded.phone,
          header_note = excluded.header_note,
          footer_note = excluded.footer_note,
          revision = pos_receipt_profiles.revision + 1,
          updated_at = now(),
          updated_by = excluded.updated_by
        '''),
        parameters: parameters,
      );

      // Audited because it changes what a legal document says. The
      // registration number in particular is the field a receipt is judged on.
      await tx.execute(
        Sql.named('''
        INSERT INTO pos_audit_events
          (business_id, branch_id, actor_user_id, actor_name, action,
           entity_type, entity_id, after_value)
        VALUES (@business, @branch, @by, @actor, @action, @type, @entity,
                @after::jsonb)
        '''),
        parameters: {
          'business': businessId,
          'branch': branchId,
          'by': by.id,
          'actor': by.name,
          'action': AuditAction.receiptProfileChanged,
          'type': AuditAction.entityReceiptProfile,
          'entity': '$branchId',
          'after':
              '{"trade_name": ${_json(profile.tradeName)}, '
              '"rin": ${_json(profile.registrationNumber)}, '
              '"branch_code": ${_json(profile.branchCode)}}',
        },
      );

      final saved = await tx.execute(
        Sql.named(
          'SELECT $_columns FROM pos_receipt_profiles WHERE branch_id = @branch',
        ),
        parameters: {'branch': branchId},
      );
      return AdminResult.done(_read(saved.first));
    });
  }

  static String _json(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
