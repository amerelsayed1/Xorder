@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/security/pin_hash.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:xorder_pos_cloud/data/cloud/outbox_drain.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_shift_repository.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// What a shift's close looks like on the wire.
///
/// The platform computes expected cash itself, from the payments it attributed
/// to the shift, and answers 422 `VALIDATION_FAILED` to a close whose count
/// differs unless `variance_reason` comes with it. The drain quarantines that
/// 422 for good, so a close sent without a reason that the platform disagreed
/// with stayed open on the dashboard forever (audit, 17 Oct 2026). These tests
/// drive the real drain over a real database and read what the platform would
/// have been sent.
void main() {
  if (PgFixture.host == null) {
    test('shift close drain (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late DeploymentConfig cloud;
  late int businessId;
  late int branchId;
  late String terminalId;
  late PosStaff sara;

  setUp(() async {
    pg = await PgFixture.open('shift_close_drain');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    cloud = pg.config.copyWith(mode: DeploymentMode.cloud);

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('close-drain', 'Close Drain') RETURNING id",
    )).first[0] as int;
    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (business_id, code, name) VALUES (@r, 'CLD', 'Close') RETURNING id",
      parameters: {'r': businessId},
    )).first[0] as int;
    terminalId = (await db.query(
      pg.config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name) '
      "VALUES (gen_random_uuid(), @r, @b, 'Counter 1') RETURNING id::text",
      parameters: {'r': businessId, 'b': branchId},
    )).first[0] as String;

    final salt = PinHash.newSalt();
    final row = await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, branch_id, name, username, pin_salt, pin_hash) '
      "VALUES (@r, @b, 'Sara M.', 'sara', @s, @h) RETURNING id",
      parameters: {
        'r': businessId,
        'b': branchId,
        's': salt,
        'h': await PinHash.hash('1111', salt),
      },
    );
    sara = PosStaff(
      id: row.first[0] as int,
      name: 'Sara M.',
      role: const PosRole(
        id: 1,
        code: SystemRoles.cashierCode,
        nameEn: 'Cashier',
        capabilities: SystemRoles.cashier,
      ),
    );
  });

  tearDown(() => pg.close());

  PostgresShiftRepository shifts() => PostgresShiftRepository(
        database: db,
        config: cloud,
        businessId: businessId,
        branchId: branchId,
        terminalId: terminalId,
      );

  /// Run the drain once and hand back the one close the platform was sent.
  Future<(DrainReport, Map<String, Object?>)> drainOneClose() async {
    final api = _RecordingApi();
    final report = await OutboxDrain(database: db, config: cloud, api: api).run();
    expect(api.closes, hasLength(1), reason: 'one shift, one close');
    return (report, api.closes.single);
  }

  test('a close the till finds short carries the till\'s own figures', () async {
    final shift = await shifts().open(by: sara, openingFloat: Money(50000));
    await shifts().close(shift: shift, by: sara, countedCash: Money(49500));

    final (report, close) = await drainOneClose();

    expect(close['counted_cash_minor'], 49500);
    expect(close['variance_reason'], isA<String>());
    expect(close['variance_reason'], contains('counted 49500'));
    expect(close['variance_reason'], contains('expected 50000'));
    expect(report.quarantined, 0);
  });

  test('a close that balances on the till still carries a reason', () async {
    // The case the audit found: the till saw no variance, the platform did —
    // two sales it had stamped with no shift. A reason sent only when the till
    // saw a variance would not have helped.
    final shift = await shifts().open(by: sara, openingFloat: Money(50000));
    await shifts().close(shift: shift, by: sara, countedCash: Money(50000));

    final (_, close) = await drainOneClose();

    expect(close['variance_reason'], isA<String>());
    expect((close['variance_reason'] as String).trim(), isNotEmpty);
  });

  test('the cashier\'s note, when there is one, is what the platform reads',
      () async {
    final shift = await shifts().open(by: sara, openingFloat: Money(50000));
    await shifts().close(
      shift: shift,
      by: sara,
      countedCash: Money(49500),
      note: 'Short 5 EGP — change given twice',
    );

    final (_, close) = await drainOneClose();

    expect(close['variance_reason'], 'Short 5 EGP — change given twice');
  });
}

class _RecordingApi extends PosCloudApi {
  _RecordingApi() : super(baseUrl: 'http://127.0.0.1:9');

  final closes = <Map<String, Object?>>[];

  @override
  Future<CloudReply> openShift(Map<String, Object?> request) async =>
      const CloudReply(status: 201, body: {'data': {'id': 1}});

  @override
  Future<CloudReply> closeShift(
    String shiftClientId,
    Map<String, Object?> request,
  ) async {
    closes.add(request);
    return const CloudReply(status: 200, body: {'data': {'id': 1}});
  }
}
