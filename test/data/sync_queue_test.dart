@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_orders_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_sync_queue_repository.dart';
import 'package:xorder_pos/domain/models/held_sync.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// Held sync records: listed, counted apart, and released (D1/D2/D13).
///
/// **The defect behind this file.** The drain sets `quarantined_at` on a
/// record the platform refused for cause, and nothing ever cleared it. A sale
/// whose product was deleted on the dashboard, or that was paid on a tender
/// the platform had not sent yet, sat in the outbox for ever — and because the
/// pending count was `delivered_at IS NULL`, it sat on the sync pill for ever
/// too, a number no pass could bring down. The only way out was a psql prompt.
void main() {
  if (PgFixture.host == null) {
    test('sync queue (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late DeploymentConfig cloud;
  late int restaurantId;
  late int branchId;
  var invoice = 0;

  const terminalId = '5b0d7c3e-2f1a-4c8e-9d6b-3a7e1f0c2b44';

  const owner = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'owner',
      nameEn: 'Owner',
      capabilities: {PosCapability.terminalManage},
    ),
  );
  const manager = PosStaff(
    id: 0,
    name: 'Hany S.',
    role: PosRole(
      id: 2,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.settingsManage, PosCapability.reportsView},
    ),
  );

  setUp(() async {
    // The database is emptied for every test, so the invoice numbers start
    // again too; left running across the file, `MAADI-000001` below was only
    // true when that test happened to run first.
    invoice = 0;
    pg = await PgFixture.open('sync_queue');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_restaurants');
    cloud = pg.config.copyWith(mode: DeploymentMode.cloud);

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('sq', 'SQ') "
      'RETURNING id',
    )).first[0]! as int;
    branchId = (await db.query(
      pg.config,
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'MAADI', 'Maadi') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;
  });

  tearDown(() => pg.close());

  PostgresSyncQueueRepository queue({
    PosDatabase? database,
    DeploymentConfig? config,
    int? branch,
  }) => PostgresSyncQueueRepository(
    database: database ?? db,
    config: config ?? cloud,
    restaurantId: restaurantId,
    branchId: branch ?? branchId,
    terminalId: terminalId,
  );

  PostgresOrdersRepository orders() => PostgresOrdersRepository(
    database: db,
    config: cloud,
    context: PosWriteContext(
      restaurantId: restaurantId,
      branchId: branchId,
      terminalId: terminalId,
      branchCode: 'MAADI',
    ),
  );

  /// A settled sale, queued for the platform. Returns its outbox row id.
  Future<int> queueSale({int? branch}) async {
    invoice++;
    final orderId = (await db.query(
      pg.config,
      '''
      INSERT INTO pos_orders (client_transaction_id, restaurant_id, branch_id,
        terminal_id, invoice_number, order_type, currency, exponent,
        subtotal_minor, service_minor, vat_minor, total_minor, occurred_at)
      VALUES (gen_random_uuid(), @r, @b, @t, @invoice, 'takeaway', 'EGP', 2,
        10000, 0, 1400, 11400, now())
      RETURNING id
      ''',
      parameters: {
        'r': restaurantId,
        'b': branch ?? branchId,
        't': terminalId,
        'invoice': 'MAADI-${invoice.toString().padLeft(6, '0')}',
      },
    )).first[0]! as int;
    return (await db.query(
      pg.config,
      'INSERT INTO pos_outbox (order_id, client_transaction_id, restaurant_id, '
      '  branch_id) SELECT id, client_transaction_id, restaurant_id, branch_id '
      'FROM pos_orders WHERE id = @o RETURNING id',
      parameters: {'o': orderId},
    )).first[0]! as int;
  }

  /// What a pass that got `422 MENU_ITEM_NOT_FOUND` leaves behind.
  Future<void> holdSale(int outboxId) => db.query(
    pg.config,
    '''
    UPDATE pos_outbox
       SET quarantined_at = now() - interval '1 hour',
           quarantine_code = 'MENU_ITEM_NOT_FOUND',
           last_error = '422 MENU_ITEM_NOT_FOUND Menu item 88 does not exist.',
           attempts = 1, last_attempt_at = now()
     WHERE id = @id
    ''',
    parameters: {'id': outboxId},
  );

  /// A flat-amount refund the till would not send (D13).
  Future<int> heldRefund({int? branch}) async => (await db.query(
    pg.config,
    '''
    INSERT INTO pos_sync_outbox (restaurant_id, branch_id, event_type,
      source_id, client_transaction_id, quarantined_at, quarantine_code,
      last_error)
    VALUES (@r, @b, 'refund', 31, gen_random_uuid(), now(),
      'REFUND_HAS_NO_LINES', 'This refund was given as an amount.')
    RETURNING id
    ''',
    parameters: {'r': restaurantId, 'b': branch ?? branchId},
  )).first[0]! as int;

  Future<List<Object?>> outboxRow(int id) async => (await db.query(
    pg.config,
    'SELECT quarantined_at, quarantine_code, last_error, attempts, '
    '       delivered_at '
    'FROM pos_outbox WHERE id = @id',
    parameters: {'id': id},
  )).first;

  Future<List<List<Object?>>> auditRows() async => [
    for (final row in await db.query(
      pg.config,
      'SELECT action, entity_type, entity_id, actor_name, before_value, '
      '       terminal_id::text '
      'FROM pos_audit_events WHERE restaurant_id = @r ORDER BY id',
      parameters: {'r': restaurantId},
    ))
      row.toList(),
  ];

  test('lists both queues, newest first, with the reason and the reference',
      () async {
    final saleId = await queueSale();
    await holdSale(saleId);
    final refundId = await heldRefund();
    await queueSale(); // pending, not held — must not be listed

    final held = await queue().listHeldSync();

    expect(held, hasLength(2));
    // The refund was held an hour after the sale.
    final [refund, sale] = held;
    expect(refund.id, refundId);
    expect(refund.kind, HeldSyncKind.refund);
    expect(refund.code, QuarantineCode.refundHasNoLines);
    expect(refund.sourceId, 31);
    expect(refund.reference, isNull);
    expect(refund.attempts, 0, reason: 'held before it was ever sent');

    expect(sale.id, saleId);
    expect(sale.kind, HeldSyncKind.sale);
    expect(sale.code, QuarantineCode.menuItemNotFound);
    expect(sale.rawCode, 'MENU_ITEM_NOT_FOUND');
    expect(sale.reference, 'MAADI-000001');
    expect(sale.lastError, contains('Menu item 88'));
    expect(sale.attempts, 1);
  });

  test('pending leaves held out, and held is counted apart', () async {
    await holdSale(await queueSale());
    await heldRefund();
    await queueSale();

    // One sale the next pass will try. Before this it said three.
    expect(await orders().pendingSyncCount(), 1);
    expect(await queue().heldSyncCount(), 2);
  });

  test('release clears the hold and writes the ledger in one go', () async {
    final saleId = await queueSale();
    await holdSale(saleId);
    final [sale] = await queue().listHeldSync();

    final result = await queue().releaseHeldSync(sale, by: owner);

    expect(result.succeeded, isTrue);
    final row = await outboxRow(saleId);
    expect(row[0], isNull, reason: 'quarantined_at');
    expect(row[1], isNull, reason: 'quarantine_code');
    expect(row[2], isNull, reason: 'last_error');
    expect(row[3], 1, reason: 'attempts counts conversations, and keeps them');
    expect(row[4], isNull, reason: 'released is not delivered');

    // It moved from one count to the other.
    expect(await orders().pendingSyncCount(), 1);
    expect(await queue().heldSyncCount(), 0);

    final [audit] = await auditRows();
    expect(audit[0], AuditAction.syncRecordReleased);
    expect(audit[1], AuditAction.entitySyncRecord);
    expect(audit[2], 'pos_outbox:$saleId');
    expect(audit[3], 'Amer M.');
    final before = audit[4] is String
        ? jsonDecode(audit[4]! as String) as Map
        : audit[4]! as Map;
    // After the release the row no longer says why it was held; the ledger
    // is the only place that still does.
    expect(before['quarantine_code'], 'MENU_ITEM_NOT_FOUND');
    expect(before['last_error'], contains('Menu item 88'));
    expect(before['reference'], 'MAADI-000001');
    expect(audit[5], terminalId);
  });

  test('a lifecycle record is released in its own table, not the sales one',
      () async {
    // The outboxes number their rows independently, so the same id can name
    // a sale in one and a refund in the other. A release that chose the table
    // by id alone could clear the sale when asked for the refund.
    final saleId = await queueSale();
    await holdSale(saleId);
    final refundId = await heldRefund();
    final refund = (await queue().listHeldSync()).firstWhere(
      (h) => h.kind == HeldSyncKind.refund,
    );

    expect(
      (await queue().releaseHeldSync(refund, by: owner)).succeeded,
      isTrue,
    );

    final rows = await db.query(
      pg.config,
      'SELECT quarantined_at FROM pos_sync_outbox WHERE id = @id',
      parameters: {'id': refundId},
    );
    expect(rows.first[0], isNull, reason: 'the refund is back in its queue');
    expect(
      (await outboxRow(saleId))[1],
      'MENU_ITEM_NOT_FOUND',
      reason: 'the sale is still held, whatever its id',
    );
    final [audit] = await auditRows();
    expect(audit[2], 'pos_sync_outbox:$refundId');
  });

  test('refused without terminal.manage, and nothing changes', () async {
    final saleId = await queueSale();
    await holdSale(saleId);
    final [sale] = await queue().listHeldSync();

    final result = await queue().releaseHeldSync(sale, by: manager);

    expect(result.succeeded, isFalse);
    expect(
      result.refusal,
      isA<NotPermitted>().having(
        (r) => r.capability,
        'capability',
        PosCapability.terminalManage,
      ),
    );
    expect((await outboxRow(saleId))[1], 'MENU_ITEM_NOT_FOUND');
    expect(await auditRows(), isEmpty);
  });

  test('the second Retry on the same record is refused, not doubled',
      () async {
    // Two managers on two tills, one held sale.
    final saleId = await queueSale();
    await holdSale(saleId);
    final [sale] = await queue().listHeldSync();

    expect((await queue().releaseHeldSync(sale, by: owner)).succeeded, isTrue);
    final second = await queue().releaseHeldSync(sale, by: owner);

    expect(second.refusal, isA<EditedElsewhere>());
    expect(await auditRows(), hasLength(1));
  });

  test("another branch's held record cannot be released from this one",
      () async {
    // The list was scoped to the branch and the release was not: the lock
    // and the update asked only for the id and the restaurant, so a manager
    // at Maadi could clear — and sign the ledger for — a sale held at
    // Zamalek, by naming its id.
    final zamalek = (await db.query(
      pg.config,
      'INSERT INTO pos_branches (restaurant_id, code, name) '
      "VALUES (@r, 'ZAMALEK', 'Zamalek') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;
    final theirSale = await queueSale(branch: zamalek);
    await holdSale(theirSale);
    await heldRefund(branch: zamalek);
    final theirs = await queue(branch: zamalek).listHeldSync();
    expect(theirs, hasLength(2));
    expect(await queue().listHeldSync(), isEmpty, reason: 'not listed here');

    for (final item in theirs) {
      final result = await queue().releaseHeldSync(item, by: owner);
      expect(result.refusal, isA<EditedElsewhere>(), reason: item.kind.name);
    }

    expect((await outboxRow(theirSale))[1], 'MENU_ITEM_NOT_FOUND');
    expect(await queue(branch: zamalek).heldSyncCount(), 2);
    expect(await auditRows(), isEmpty);

    // And their own branch still can.
    expect(
      (await queue(branch: zamalek).releaseHeldSync(theirs.first, by: owner))
          .succeeded,
      isTrue,
    );
  });

  test('an offline till holds nothing it could ever send', () async {
    await holdSale(await queueSale());
    final offline = queue(
      config: pg.config.copyWith(mode: DeploymentMode.offline),
    );

    expect(await offline.listHeldSync(), isEmpty);
    expect(await offline.heldSyncCount(), 0);
  });

  test('release works on the till credential, not only the superuser',
      () async {
    // Every other test here runs as the superuser, who needs no grant at all.
    // A cloud till releases on its own credential, so ask PostgreSQL.
    final saleId = await queueSale();
    await holdSale(saleId);

    final role = PgFixture.roleFor('sync_queue_probe');
    const password = 'probe-only';
    Future<void> dropRole() async {
      for (final statement in [
        'DROP OWNED BY "$role"',
        'DROP ROLE IF EXISTS "$role"',
      ]) {
        try {
          await db.query(pg.config, statement);
        } on Object {
          // Nothing to revoke, or nothing to drop.
        }
      }
    }

    await dropRole();
    await db.query(
      pg.config,
      'CREATE ROLE "$role" LOGIN PASSWORD \'$password\'',
    );
    final probe = PosDatabase(credentials: InMemoryPosDbCredentials(password));
    try {
      for (final statement in LocalBootstrap.tillGrants(
        database: pg.config.databaseName,
        role: role,
        cloudSeeding: true,
      )) {
        await db.query(pg.config, statement);
      }
      final asTill = queue(
        database: probe,
        config: DeploymentConfig(
          mode: DeploymentMode.cloud,
          databaseHost: pg.config.databaseHost,
          allowInsecureLan: true,
          databaseName: pg.config.databaseName,
          databaseUser: role,
          databasePort: pg.config.databasePort,
        ),
      );

      final [sale] = await asTill.listHeldSync();
      final result = await asTill.releaseHeldSync(sale, by: owner);

      expect(result.succeeded, isTrue);
      expect((await outboxRow(saleId))[0], isNull);
      expect(await auditRows(), hasLength(1));
    } finally {
      await probe.close();
      await dropRole();
    }
  });
}
